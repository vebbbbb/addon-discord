// Package state persists which events were posted (state.json) so nothing is posted twice.
package state

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/vebbbbb/addon-discord/companion/internal/config"
	"github.com/vebbbbb/addon-discord/companion/internal/event"
)

// Retention: posted keys older than this are forgotten (must exceed the late window).
const Retention = 30 * 24 * time.Hour

type file struct {
	InstalledAt int64            `json:"installed_at"`
	Posted      map[string]int64 `json:"posted"` // event key -> unix time posted
	LastPost    string           `json:"last_post,omitempty"`
	LastPostAt  int64            `json:"last_post_at,omitempty"`
	AddonHash   string           `json:"addon_hash,omitempty"`
}

// Store is the thread-safe dedupe store. Claim marks an event as in flight (memory only) so the
// barcode path and the SavedVariables path never post the same event concurrently.
type Store struct {
	mu      sync.Mutex
	path    string
	f       file
	claimed map[string]bool
	now     func() time.Time
}

// Open loads (or creates) state.json in dir.
func Open(dir string) (*Store, error) {
	s := &Store{path: filepath.Join(dir, "state.json"), claimed: map[string]bool{}, now: time.Now}
	b, err := os.ReadFile(s.path)
	switch {
	case errors.Is(err, os.ErrNotExist):
	case err != nil:
		return nil, err
	default:
		if err := json.Unmarshal(b, &s.f); err != nil {
			// a corrupt state must not stop the program; start fresh but keep a copy
			_ = os.Rename(s.path, s.path+".corrupt")
			s.f = file{}
		}
	}
	if s.f.Posted == nil {
		s.f.Posted = map[string]int64{}
	}
	if s.f.InstalledAt == 0 {
		s.f.InstalledAt = s.now().Unix()
		if err := s.saveLocked(); err != nil {
			return nil, err
		}
	}
	return s, nil
}

// InstalledAt is when NAVTOK first ran; older SavedVariables events are never posted.
func (s *Store) InstalledAt() int64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.f.InstalledAt
}

// sameChar treats names as equal when one is a prefix of the other (the barcode may carry a
// truncated name in extreme cases).
func sameChar(a, b string) bool {
	return a == b || (a != "" && b != "" && (strings.HasPrefix(a, b) || strings.HasPrefix(b, a)))
}

func (s *Store) knownLocked(e *event.Event) bool {
	if _, ok := s.f.Posted[e.Key()]; ok || s.claimed[e.Key()] {
		return true
	}
	suffix := "|" + e.ID
	for k := range s.f.Posted {
		if strings.HasSuffix(k, suffix) && sameChar(strings.TrimSuffix(k, suffix), e.Char) {
			return true
		}
	}
	for k := range s.claimed {
		if strings.HasSuffix(k, suffix) && sameChar(strings.TrimSuffix(k, suffix), e.Char) {
			return true
		}
	}
	return false
}

// Posted reports whether the event was posted (or is being posted).
func (s *Store) Posted(e *event.Event) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.knownLocked(e)
}

// Claim reserves an event for posting. It returns false if it was posted or is already claimed.
func (s *Store) Claim(e *event.Event) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.knownLocked(e) {
		return false
	}
	s.claimed[e.Key()] = true
	return true
}

// Release gives up a claim without posting (permanent failure: allows a later retry path).
func (s *Store) Release(e *event.Event) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.claimed, e.Key())
}

// MarkPosted records a successful post and saves state.json.
func (s *Store) MarkPosted(e *event.Event, summary string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now()
	delete(s.claimed, e.Key())
	s.f.Posted[e.Key()] = now.Unix()
	s.f.LastPost, s.f.LastPostAt = summary, now.Unix()
	cutoff := now.Add(-Retention).Unix()
	for k, t := range s.f.Posted {
		if t < cutoff {
			delete(s.f.Posted, k)
		}
	}
	return s.saveLocked()
}

// LastPost returns the summary and time of the last post.
func (s *Store) LastPost() (string, time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.f.LastPostAt == 0 {
		return "", time.Time{}
	}
	return s.f.LastPost, time.Unix(s.f.LastPostAt, 0)
}

// AddonHash / SetAddonHash remember which addon build was installed.
func (s *Store) AddonHash() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.f.AddonHash
}

func (s *Store) SetAddonHash(h string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.f.AddonHash = h
	return s.saveLocked()
}

func (s *Store) saveLocked() error {
	b, err := json.MarshalIndent(s.f, "", " ")
	if err != nil {
		return err
	}
	return config.WriteFileAtomic(s.path, b)
}
