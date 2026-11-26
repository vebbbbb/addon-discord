package discord

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"sync"
	"time"

	"github.com/navtok/navtok-discord/companion/internal/event"
)

// Poster is what the Sender needs from Client (DryRun implements it too).
type Poster interface {
	Post(ctx context.Context, msg Message, image []byte) error
}

// Job is one queued post.
type Job struct {
	Event *event.Event
	Msg   Message
	Image []byte
	// Done is called once, with nil on success or the permanent error.
	Done func(error)
}

// Sender posts jobs in order from one goroutine: waits out 429s, retries transient errors with
// exponential backoff forever (offline PCs catch up later), drops only permanent failures.
type Sender struct {
	P          Poster
	MinBackoff time.Duration
	MaxBackoff time.Duration
	// OnTransient is called when a post fails but will be retried (for problem notifications);
	// OnOK after every success.
	OnTransient func(err error)
	OnOK        func()

	mu    sync.Mutex
	queue []*Job
	wake  chan struct{}
	sleep func(context.Context, time.Duration) error
}

// NewSender creates a sender for p.
func NewSender(p Poster) *Sender {
	return &Sender{P: p, MinBackoff: 2 * time.Second, MaxBackoff: 5 * time.Minute,
		wake: make(chan struct{}, 1), sleep: sleepCtx}
}

// Enqueue adds a job.
func (s *Sender) Enqueue(j *Job) {
	s.mu.Lock()
	s.queue = append(s.queue, j)
	s.mu.Unlock()
	select {
	case s.wake <- struct{}{}:
	default:
	}
}

// Len is the number of queued jobs.
func (s *Sender) Len() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.queue)
}

func (s *Sender) next() *Job {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.queue) == 0 {
		return nil
	}
	j := s.queue[0]
	s.queue = s.queue[1:]
	return j
}

// Run processes the queue until ctx is done.
func (s *Sender) Run(ctx context.Context) {
	for {
		j := s.next()
		if j == nil {
			select {
			case <-ctx.Done():
				return
			case <-s.wake:
				continue
			}
		}
		err := s.deliver(ctx, j)
		if ctx.Err() != nil && err != nil {
			return
		}
		if j.Done != nil {
			j.Done(err)
		}
	}
}

func (s *Sender) deliver(ctx context.Context, j *Job) error {
	backoff := s.MinBackoff
	for {
		err := s.P.Post(ctx, j.Msg, j.Image)
		if err == nil {
			if s.OnOK != nil {
				s.OnOK()
			}
			return nil
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
		var rl *RateLimitError
		if errors.As(err, &rl) {
			if e := s.sleep(ctx, rl.After); e != nil {
				return e
			}
			continue
		}
		if IsPermanent(err) {
			// 413 = attachment too large: retry once without the image instead of losing the event
			var p *PermanentError
			if errors.As(err, &p) && p.Status == 413 && j.Image != nil {
				j.Image = nil
				j.Msg.Attachments = nil
				if len(j.Msg.Embeds) > 0 {
					j.Msg.Embeds[0].Image = nil
				}
				continue
			}
			return err
		}
		if s.OnTransient != nil {
			s.OnTransient(err)
		}
		if e := s.sleep(ctx, backoff); e != nil {
			return e
		}
		backoff = min(backoff*2, s.MaxBackoff)
	}
}

// DryRun prints posts instead of sending them.
type DryRun struct{ W io.Writer }

func (d DryRun) Post(_ context.Context, msg Message, image []byte) error {
	b, _ := json.MarshalIndent(msg, "", "  ")
	fmt.Fprintf(d.W, "--- dry-run post (image: %d bytes) ---\n%s\n", len(image), b)
	return nil
}
