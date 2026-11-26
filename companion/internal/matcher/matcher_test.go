package matcher

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestShotTimeFromName(t *testing.T) {
	got := ShotTime(`C:\x\WoWScrnShot_112626_143005.jpg`, time.UTC)
	want := time.Date(2026, 11, 26, 14, 30, 5, 0, time.UTC)
	if !got.Equal(want) {
		t.Fatalf("%v", got)
	}
	p := filepath.Join(t.TempDir(), "WoWScrnShot_bad.jpg")
	os.WriteFile(p, []byte("x"), 0o644)
	mt := time.Now().Add(-time.Hour).Truncate(time.Second)
	os.Chtimes(p, mt, mt)
	if !ShotTime(p, time.UTC).Equal(mt) {
		t.Fatal("mtime fallback")
	}
}

func TestFindNearestFreeWithinTolerance(t *testing.T) {
	x := New(24 * time.Hour)
	base := time.Now().Truncate(time.Second)
	x.Add("a.jpg", base.Add(-2*time.Second), false)
	x.Add("b.jpg", base.Add(1*time.Second), false)
	x.Add("c.jpg", base, true) // decoded: belongs to another event
	x.Add("d.jpg", base.Add(5*time.Second), false)
	tol := 3 * time.Second
	if p := x.Find(base, tol); p != "b.jpg" {
		t.Fatalf("got %q", p)
	}
	if p := x.Find(base, tol); p != "a.jpg" {
		t.Fatalf("second match %q (b is used)", p)
	}
	if p := x.Find(base, tol); p != "" {
		t.Fatalf("nothing left within ±3s, got %q", p)
	}
	if p := x.Find(base.Add(4*time.Second), tol); p != "d.jpg" {
		t.Fatalf("got %q", p)
	}
}

func TestDecodedIsSticky(t *testing.T) {
	x := New(time.Hour)
	now := time.Now()
	x.Add("a.jpg", now, true)
	x.Add("a.jpg", now, false)
	if x.Find(now, time.Second) != "" {
		t.Fatal("decoded shot reused")
	}
}

func TestScanAndPrune(t *testing.T) {
	dir := t.TempDir()
	now := time.Now()
	name := "WoWScrnShot_" + now.Format("010206_150405") + ".jpg"
	os.WriteFile(filepath.Join(dir, name), []byte("x"), 0o644)
	os.WriteFile(filepath.Join(dir, "WoWScrnShot_010120_000000.jpg"), []byte("x"), 0o644)
	x := New(48 * time.Hour)
	x.Scan([]string{dir}, now.Add(-time.Hour), func(string) bool { return true })
	if x.Len() != 1 {
		t.Fatalf("len %d", x.Len())
	}
}
