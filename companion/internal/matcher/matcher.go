// Package matcher pairs SavedVariables events whose barcode was never decoded with a screenshot
// taken within ±tolerance seconds (the "(late)" path).
package matcher

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

// Shot is a screenshot we have seen.
type Shot struct {
	Path string
	Time time.Time
	// Decoded: a barcode was read from it (it belongs to that event, never to a late one).
	Decoded bool
	// Used: already attached to a late post.
	Used bool
}

// Index of recent screenshots.
type Index struct {
	mu    sync.Mutex
	shots map[string]*Shot
	keep  time.Duration
}

// New creates an index that forgets shots older than keep.
func New(keep time.Duration) *Index { return &Index{shots: map[string]*Shot{}, keep: keep} }

var nameRe = regexp.MustCompile(`(?i)WoWScrnShot_(\d{2})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})`)

// ShotTime returns when a screenshot was taken: from the file name (local time, 1 s resolution)
// or else the modification time.
func ShotTime(path string, loc *time.Location) time.Time {
	if m := nameRe.FindStringSubmatch(filepath.Base(path)); m != nil {
		n := make([]int, 6)
		for i := range n {
			n[i] = atoi(m[i+1])
		}
		t := time.Date(2000+n[2], time.Month(n[0]), n[1], n[3], n[4], n[5], 0, loc)
		if t.Month() == time.Month(n[0]) { // valid date
			return t
		}
	}
	if st, err := os.Stat(path); err == nil {
		return st.ModTime()
	}
	return time.Time{}
}

func atoi(s string) int {
	n := 0
	for _, c := range s {
		n = n*10 + int(c-'0')
	}
	return n
}

// Add records a screenshot (idempotent; Decoded is sticky).
func (x *Index) Add(path string, t time.Time, decoded bool) {
	x.mu.Lock()
	defer x.mu.Unlock()
	key := strings.ToLower(path)
	if s, ok := x.shots[key]; ok {
		s.Decoded = s.Decoded || decoded
		return
	}
	x.shots[key] = &Shot{Path: path, Time: t, Decoded: decoded}
	x.pruneLocked()
}

func (x *Index) pruneLocked() {
	cutoff := time.Now().Add(-x.keep)
	for k, s := range x.shots {
		if s.Time.Before(cutoff) {
			delete(x.shots, k)
		}
	}
}

// Scan adds every screenshot in dirs taken after since (used when SavedVariables changed while
// the companion was not running).
func (x *Index) Scan(dirs []string, since time.Time, isShot func(string) bool) {
	for _, d := range dirs {
		entries, err := os.ReadDir(d)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if e.IsDir() || !isShot(e.Name()) {
				continue
			}
			p := filepath.Join(d, e.Name())
			t := ShotTime(p, time.Local)
			if t.After(since) {
				x.Add(p, t, false)
			}
		}
	}
}

// Find returns the closest free (not decoded, not used) screenshot within tol of at and marks it
// used. Returns "" when there is none.
func (x *Index) Find(at time.Time, tol time.Duration) string {
	x.mu.Lock()
	defer x.mu.Unlock()
	var cands []*Shot
	for _, s := range x.shots {
		if s.Decoded || s.Used {
			continue
		}
		d := s.Time.Sub(at)
		if d < 0 {
			d = -d
		}
		if d <= tol {
			cands = append(cands, s)
		}
	}
	if len(cands) == 0 {
		return ""
	}
	sort.Slice(cands, func(i, j int) bool {
		di, dj := absDur(cands[i].Time.Sub(at)), absDur(cands[j].Time.Sub(at))
		if di != dj {
			return di < dj
		}
		return cands[i].Path < cands[j].Path
	})
	cands[0].Used = true
	return cands[0].Path
}

func absDur(d time.Duration) time.Duration {
	if d < 0 {
		return -d
	}
	return d
}

// Len is the number of tracked screenshots.
func (x *Index) Len() int {
	x.mu.Lock()
	defer x.mu.Unlock()
	return len(x.shots)
}
