package watcher

import (
	"context"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

var jpegish = append(append([]byte{0xFF, 0xD8}, make([]byte, 4000)...), 0xFF, 0xD9)

func TestIsScreenshot(t *testing.T) {
	for n, want := range map[string]bool{"WoWScrnShot_112626_143005.jpg": true, "wowscrnshot_1.PNG": true,
		"WoWScrnShot_1.tga": false, "other.jpg": false} {
		if IsScreenshot(n) != want {
			t.Errorf("%s", n)
		}
	}
}

func TestWaitStableWaitsForCompleteFile(t *testing.T) {
	p := filepath.Join(t.TempDir(), "WoWScrnShot_1.jpg")
	f, _ := os.Create(p)
	f.Write(jpegish[:1000])
	start := time.Now()
	go func() {
		time.Sleep(200 * time.Millisecond)
		f.Write(jpegish[1000:])
		f.Close()
	}()
	if err := WaitStable(context.Background(), p, 10*time.Millisecond, 50*time.Millisecond, 3*time.Second); err != nil {
		t.Fatal(err)
	}
	if time.Since(start) < 200*time.Millisecond {
		t.Fatal("returned before the file was complete")
	}
	b, _ := os.ReadFile(p)
	if len(b) != len(jpegish) {
		t.Fatal("size")
	}
}

func TestWaitStableTimeoutOnTruncatedJPEG(t *testing.T) {
	p := filepath.Join(t.TempDir(), "WoWScrnShot_2.jpg")
	os.WriteFile(p, jpegish[:500], 0o644)
	if err := WaitStable(context.Background(), p, 10*time.Millisecond, 20*time.Millisecond, 200*time.Millisecond); err == nil {
		t.Fatal("truncated jpeg accepted")
	}
}

func TestWatcherScreenshotsAndSavedVars(t *testing.T) {
	root := t.TempDir()
	shots := filepath.Join(root, "Screenshots")
	acct := filepath.Join(root, "WTF", "Account")
	sv := filepath.Join(acct, "ACC1", "SavedVariables")
	os.MkdirAll(sv, 0o755)
	var mu sync.Mutex
	var gotShots, gotSV []string
	w, err := New(Config{ScreenshotDirs: []string{shots}, AccountDirs: []string{acct}, Debounce: 100 * time.Millisecond,
		OnScreenshot: func(p string) { mu.Lock(); gotShots = append(gotShots, p); mu.Unlock() },
		OnSavedVars:  func(p string) { mu.Lock(); gotSV = append(gotSV, p); mu.Unlock() }})
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go w.Run(ctx)
	time.Sleep(50 * time.Millisecond)
	os.WriteFile(filepath.Join(shots, "WoWScrnShot_112626_143005.jpg"), jpegish, 0o644)
	os.WriteFile(filepath.Join(shots, "notes.txt"), []byte("x"), 0o644)
	for i := 0; i < 3; i++ { // WoW rewrites the file; debounced to one callback
		os.WriteFile(filepath.Join(sv, SavedVarsFile), []byte("NavtokDiscordDB = {}"), 0o644)
		time.Sleep(20 * time.Millisecond)
	}
	// a new account created later is picked up
	sv2 := filepath.Join(acct, "ACC2")
	os.MkdirAll(sv2, 0o755)
	time.Sleep(50 * time.Millisecond)
	os.MkdirAll(filepath.Join(sv2, "SavedVariables"), 0o755)
	time.Sleep(50 * time.Millisecond)
	os.WriteFile(filepath.Join(sv2, "SavedVariables", SavedVarsFile), []byte("NavtokDiscordDB = {}"), 0o644)
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		mu.Lock()
		done := len(gotShots) >= 1 && len(gotSV) >= 2
		mu.Unlock()
		if done {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	mu.Lock()
	defer mu.Unlock()
	if len(gotShots) != 1 || len(gotSV) != 2 {
		t.Fatalf("shots %v sv %v", gotShots, gotSV)
	}
	if files := SavedVarsFiles([]string{acct}); len(files) != 2 {
		t.Fatalf("SavedVarsFiles %v", files)
	}
}
