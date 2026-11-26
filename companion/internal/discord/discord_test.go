package discord

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"mime"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/vebbbbb/addon-discord/companion/internal/event"
)

func ev(t string, data map[string]string) *event.Event {
	return &event.Event{Type: t, ID: "1.1", TS: 1764160000, Seq: 1, Char: "Navtok", Realm: "Forever", Class: "MAGE",
		ClassID: 8, Level: 60, Data: data}
}

func TestEmbedsPerType(t *testing.T) {
	o := Options{WowheadBase: "https://www.wowhead.com/classic", HasImage: true}
	cases := []struct {
		e     *event.Event
		title string
		color int
	}{
		{ev("loot", map[string]string{"itemId": "19019", "quality": "5", "count": "1", "item": "Thunderfury"}), "Looted [Thunderfury]", 0xFF8000},
		{ev("loot", map[string]string{"itemId": "1", "quality": "4", "count": "3", "item": "X"}), "Looted [X] x3", 0xA335EE},
		{ev("skill", map[string]string{"skill": "Mining", "rank": "300"}), "Mining skill 300", colorSkill},
		{ev("level", map[string]string{"zone": "Elwynn"}), "Reached level 60!", 0x69CCF0},
		{ev("reputation", map[string]string{"faction": "Stormwind", "standing": "8"}), "Now Exalted with Stormwind", 0xF1C40F},
		{ev("death", map[string]string{"zone": "STV", "subzone": "Booty Bay", "killer": "Pirate"}), "Died in Booty Bay, STV", 0x69CCF0},
		{ev("dungeon", map[string]string{"encounter": "Edwin VanCleef", "instance": "The Deadmines"}), "Defeated Edwin VanCleef - The Deadmines", colorDungeon},
		{ev("bg", map[string]string{"bg": "Warsong Gulch", "result": "win", "kb": "7", "duration": "1234"}), "Victory in Warsong Gulch", colorWin},
		{ev("bg", map[string]string{"bg": "Arathi Basin", "result": "loss"}), "Defeat in Arathi Basin", colorLoss},
		{ev("legacy", map[string]string{"text": "Explorer"}), "Legacy challenge completed", colorLegacy},
	}
	for _, c := range cases {
		m := Build(c.e, o)
		em := m.Embeds[0]
		if em.Title != c.title || em.Color != c.color {
			t.Errorf("%s: title %q color %06x", c.e.Type, em.Title, em.Color)
		}
		if em.Author.Name != "Navtok - Forever (60)" && em.Author.Name != "Navtok - Forever" {
			t.Errorf("author %q", em.Author.Name)
		}
		if em.Image == nil || em.Image.URL != "attachment://screenshot.jpg" || len(m.Attachments) != 1 {
			t.Errorf("%s: image not referenced", c.e.Type)
		}
		if m.AllowedMentions == nil || len(m.AllowedMentions.Parse) != 0 {
			t.Error("mentions must be disabled")
		}
	}
	loot := Build(cases[0].e, o).Embeds[0]
	if loot.URL != "https://www.wowhead.com/classic/item=19019" {
		t.Errorf("wowhead link %q", loot.URL)
	}
	bg := Build(cases[7].e, o).Embeds[0]
	if len(bg.Fields) != 2 || bg.Fields[1].Value != "20m 34s" {
		t.Errorf("bg fields %+v", bg.Fields)
	}
}

func TestEmbedFlagsAndNoImage(t *testing.T) {
	e := ev("level", nil)
	e.Test, e.Late = true, true
	m := Build(e, Options{})
	if m.Embeds[0].Title != "[TEST] Reached level 60! (late)" {
		t.Fatal(m.Embeds[0].Title)
	}
	if m.Embeds[0].Image != nil || m.Attachments != nil {
		t.Fatal("no image expected")
	}
	if Summary(e) != "Navtok: [TEST] Reached level 60! (late)" {
		t.Fatal(Summary(e))
	}
}

func TestValidURL(t *testing.T) {
	for _, u := range []string{"https://discord.com/api/webhooks/123/abc-DEF_1", "https://discordapp.com/api/webhooks/1/x", "https://canary.discord.com/api/v10/webhooks/1/x"} {
		if !ValidURL(u) {
			t.Errorf("rejected %s", u)
		}
	}
	for _, u := range []string{"http://discord.com/api/webhooks/1/x", "https://evil.com/api/webhooks/1/x", "https://discord.com/api/webhooks/x/y", ""} {
		if ValidURL(u) {
			t.Errorf("accepted %s", u)
		}
	}
}

func TestPostMultipart(t *testing.T) {
	var got struct {
		payload map[string]any
		file    []byte
		name    string
		query   string
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got.query = r.URL.RawQuery
		_, params, _ := mime.ParseMediaType(r.Header.Get("Content-Type"))
		mr := multipart.NewReader(r.Body, params["boundary"])
		for {
			p, err := mr.NextPart()
			if err != nil {
				break
			}
			b, _ := io.ReadAll(p)
			if p.FormName() == "payload_json" {
				json.Unmarshal(b, &got.payload)
			} else {
				got.file, got.name = b, p.FileName()
			}
		}
		w.WriteHeader(200)
		w.Write([]byte(`{"id":"1"}`))
	}))
	defer srv.Close()
	c := NewClient(srv.URL + "/api/webhooks/1/x")
	msg := Build(ev("level", nil), Options{HasImage: true})
	if err := c.Post(context.Background(), msg, []byte("JPEGDATA")); err != nil {
		t.Fatal(err)
	}
	if string(got.file) != "JPEGDATA" || got.name != "screenshot.jpg" || got.payload["embeds"] == nil || got.query != "wait=true" {
		t.Fatalf("%+v", got)
	}
}

func TestRateLimitHonoured(t *testing.T) {
	var calls int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if atomic.AddInt32(&calls, 1) == 1 {
			w.Header().Set("Retry-After", "5")
			w.WriteHeader(429)
			w.Write([]byte(`{"message":"You are being rate limited.","retry_after":0.25,"global":false}`))
			return
		}
		w.WriteHeader(204)
	}))
	defer srv.Close()
	c := NewClient(srv.URL)
	err := c.Post(context.Background(), Message{Content: "x"}, nil)
	var rl *RateLimitError
	if !errors.As(err, &rl) || rl.After < 250*time.Millisecond || rl.After > time.Second {
		t.Fatalf("err %v", err)
	}
	var slept []time.Duration
	s := NewSender(c)
	s.sleep = func(_ context.Context, d time.Duration) error { slept = append(slept, d); return nil }
	done := make(chan error, 1)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go s.Run(ctx)
	atomic.StoreInt32(&calls, 0)
	s.Enqueue(&Job{Msg: Message{Content: "x"}, Done: func(err error) { done <- err }})
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if len(slept) != 1 || slept[0] < 250*time.Millisecond {
		t.Fatalf("slept %v", slept)
	}
}

func TestBucketHeadersDelayNextPost(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-RateLimit-Remaining", "0")
		w.Header().Set("X-RateLimit-Reset-After", "1.5")
		w.WriteHeader(204)
	}))
	defer srv.Close()
	c := NewClient(srv.URL)
	var slept time.Duration
	c.sleep = func(_ context.Context, d time.Duration) error { slept = d; return nil }
	c.Post(context.Background(), Message{Content: "a"}, nil)
	c.Post(context.Background(), Message{Content: "b"}, nil)
	if slept < time.Second || slept > 1600*time.Millisecond {
		t.Fatalf("slept %v", slept)
	}
}

type fakePoster struct {
	mu    sync.Mutex
	errs  []error
	posts []Message
}

func (f *fakePoster) Post(_ context.Context, m Message, img []byte) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.errs) > 0 {
		e := f.errs[0]
		f.errs = f.errs[1:]
		return e
	}
	f.posts = append(f.posts, m)
	return nil
}

func TestSenderRetriesOfflineThenDelivers(t *testing.T) {
	f := &fakePoster{errs: []error{errors.New("offline"), errors.New("offline"), errors.New("dns")}}
	s := NewSender(f)
	var backoffs []time.Duration
	s.sleep = func(_ context.Context, d time.Duration) error { backoffs = append(backoffs, d); return nil }
	transient := 0
	s.OnTransient = func(error) { transient++ }
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go s.Run(ctx)
	done := make(chan error, 2)
	s.Enqueue(&Job{Msg: Message{Content: "1"}, Done: func(err error) { done <- err }})
	s.Enqueue(&Job{Msg: Message{Content: "2"}, Done: func(err error) { done <- err }})
	<-done
	<-done
	if len(f.posts) != 2 || f.posts[0].Content != "1" || f.posts[1].Content != "2" {
		t.Fatalf("order %+v", f.posts)
	}
	if transient != 3 || backoffs[0] != 2*time.Second || backoffs[1] != 4*time.Second || backoffs[2] != 8*time.Second {
		t.Fatalf("backoffs %v transient %d", backoffs, transient)
	}
}

func TestSenderPermanentAndTooLarge(t *testing.T) {
	f := &fakePoster{errs: []error{&PermanentError{Status: 413}, &PermanentError{Status: 404, Body: "Unknown Webhook"}}}
	s := NewSender(f)
	s.sleep = func(context.Context, time.Duration) error { return nil }
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go s.Run(ctx)
	done := make(chan error, 2)
	msg := Build(ev("level", nil), Options{HasImage: true})
	s.Enqueue(&Job{Msg: msg, Image: []byte("big"), Done: func(err error) { done <- err }})
	if err := <-done; !IsPermanent(err) {
		t.Fatalf("want permanent, got %v", err)
	}
	s.Enqueue(&Job{Msg: msg, Done: func(err error) { done <- err }})
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}

func TestDryRun(t *testing.T) {
	var b strings.Builder
	DryRun{W: &b}.Post(context.Background(), Build(ev("level", nil), Options{}), []byte("abc"))
	if !strings.Contains(b.String(), "Reached level 60!") || !strings.Contains(b.String(), "image: 3 bytes") {
		t.Fatal(b.String())
	}
}

func TestValidate(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/good") {
			w.Write([]byte(`{"type":1,"id":"123","name":"x"}`))
			return
		}
		w.WriteHeader(404)
		w.Write([]byte(`{"message":"Unknown Webhook","code":10015}`))
	}))
	defer srv.Close()
	c := NewClient("https://discord.com/api/webhooks/1/good")
	c.HTTP = srv.Client()
	c.HTTP.Transport = rewrite{srv.URL}
	if err := c.Validate(context.Background()); err != nil {
		t.Fatal(err)
	}
	c.URL = "https://discord.com/api/webhooks/1/bad"
	if err := c.Validate(context.Background()); !IsPermanent(err) {
		t.Fatal(err)
	}
	c.URL = "https://example.com/x"
	if err := c.Validate(context.Background()); !IsPermanent(err) {
		t.Fatal(err)
	}
}

type rewrite struct{ base string }

func (r rewrite) RoundTrip(req *http.Request) (*http.Response, error) {
	u := r.base + req.URL.Path
	nr, _ := http.NewRequest(req.Method, u, req.Body)
	return http.DefaultTransport.RoundTrip(nr)
}
