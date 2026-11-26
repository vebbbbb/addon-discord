package state

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/vebbbbb/addon-discord/companion/internal/event"
)

func ev(char, id string) *event.Event { return &event.Event{Char: char, ID: id} }

func TestDedupeAcrossRestart(t *testing.T) {
	dir := t.TempDir()
	s, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	a := ev("Navtok", "100.1")
	if !s.Claim(a) {
		t.Fatal("first claim")
	}
	if s.Claim(a) {
		t.Fatal("double claim")
	}
	if err := s.MarkPosted(a, "loot"); err != nil {
		t.Fatal(err)
	}
	s2, _ := Open(dir)
	if !s2.Posted(a) || s2.Claim(a) {
		t.Fatal("posted not persisted")
	}
	if s2.InstalledAt() != s.InstalledAt() {
		t.Fatal("installedAt changed")
	}
	if sum, _ := s2.LastPost(); sum != "loot" {
		t.Fatal(sum)
	}
}

func TestTruncatedCharNameIsSameEvent(t *testing.T) {
	s, _ := Open(t.TempDir())
	s.MarkPosted(ev("Navtokverylong", "100.1"), "x")
	if !s.Posted(ev("Navtokv", "100.1")) {
		t.Fatal("prefix name should match")
	}
	if s.Posted(ev("Other", "100.1")) || s.Posted(ev("Navtokverylong", "100.2")) {
		t.Fatal("false match")
	}
}

func TestReleaseAndRetention(t *testing.T) {
	s, _ := Open(t.TempDir())
	a := ev("A", "1.1")
	s.Claim(a)
	s.Release(a)
	if !s.Claim(a) {
		t.Fatal("release")
	}
	old := time.Now().Add(-Retention - time.Hour)
	s.now = func() time.Time { return old }
	s.MarkPosted(a, "")
	s.now = time.Now
	s.MarkPosted(ev("B", "2.1"), "")
	if s.Posted(a) {
		t.Fatal("old entry should be pruned")
	}
}

func TestCorruptStateRecovers(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "state.json"), []byte("{garbage"), 0o600)
	s, err := Open(dir)
	if err != nil || s.InstalledAt() == 0 {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "state.json.corrupt")); err != nil {
		t.Fatal("corrupt copy missing")
	}
}
