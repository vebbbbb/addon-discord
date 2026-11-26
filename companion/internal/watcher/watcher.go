package watcher

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
)

// SavedVarsFile is the addon's SavedVariables file name.
const SavedVarsFile = "NavtokDiscord.lua"

// Config of a Watcher.
type Config struct {
	ScreenshotDirs []string // <client>\Screenshots
	AccountDirs    []string // <client>\WTF\Account
	// OnScreenshot gets complete screenshot files.
	OnScreenshot func(path string)
	// OnTGA is called once per TGA screenshot (unsupported format).
	OnTGA func(path string)
	// OnSavedVars gets SavedVariables files after they stopped changing for Debounce.
	OnSavedVars func(path string)
	OnError     func(error)
	Debounce    time.Duration
}

// Watcher multiplexes one fsnotify watcher over all folders.
type Watcher struct {
	cfg Config
	fs  *fsnotify.Watcher

	mu       sync.Mutex
	inflight map[string]bool
	svTimers map[string]*time.Timer
}

// New creates the folders' watches. Missing Screenshots folders are created (WoW creates them
// lazily on the first screenshot, but we need a folder to watch).
func New(cfg Config) (*Watcher, error) {
	if cfg.Debounce == 0 {
		cfg.Debounce = 1500 * time.Millisecond
	}
	fw, err := fsnotify.NewWatcher()
	if err != nil {
		return nil, err
	}
	w := &Watcher{cfg: cfg, fs: fw, inflight: map[string]bool{}, svTimers: map[string]*time.Timer{}}
	for _, d := range cfg.ScreenshotDirs {
		_ = os.MkdirAll(d, 0o755)
		if err := fw.Add(d); err != nil {
			fw.Close()
			return nil, err
		}
	}
	for _, d := range cfg.AccountDirs {
		w.addAccountDir(d)
	}
	return w, nil
}

// addAccountDir watches WTF\Account (for new accounts) and each <account>\SavedVariables.
func (w *Watcher) addAccountDir(dir string) {
	if err := w.fs.Add(dir); err != nil {
		return
	}
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if e.IsDir() {
			w.addAccount(filepath.Join(dir, e.Name()))
		}
	}
}

// addAccount watches <account> (to see SavedVariables appear) and <account>\SavedVariables.
func (w *Watcher) addAccount(acc string) {
	if st, err := os.Stat(acc); err != nil || !st.IsDir() {
		return
	}
	_ = w.fs.Add(acc)
	w.addSavedVarsDir(filepath.Join(acc, "SavedVariables"))
}

func (w *Watcher) addSavedVarsDir(dir string) {
	if st, err := os.Stat(dir); err == nil && st.IsDir() {
		_ = w.fs.Add(dir)
	}
}

// SavedVarsFiles lists the current NavtokDiscord.lua files under the account dirs.
func SavedVarsFiles(accountDirs []string) []string {
	var out []string
	for _, a := range accountDirs {
		matches, _ := filepath.Glob(filepath.Join(a, "*", "SavedVariables", SavedVarsFile))
		out = append(out, matches...)
	}
	return out
}

func (w *Watcher) isAccountDir(dir string) bool {
	for _, a := range w.cfg.AccountDirs {
		if filepath.Clean(a) == filepath.Clean(dir) {
			return true
		}
	}
	return false
}

func (w *Watcher) isScreenshotDir(dir string) bool {
	for _, s := range w.cfg.ScreenshotDirs {
		if strings.EqualFold(filepath.Clean(s), filepath.Clean(dir)) {
			return true
		}
	}
	return false
}

// Run handles events until ctx is cancelled.
func (w *Watcher) Run(ctx context.Context) {
	defer w.fs.Close()
	for {
		select {
		case <-ctx.Done():
			return
		case err, ok := <-w.fs.Errors:
			if !ok {
				return
			}
			if w.cfg.OnError != nil {
				w.cfg.OnError(err)
			}
		case ev, ok := <-w.fs.Events:
			if !ok {
				return
			}
			w.handle(ctx, ev)
		}
	}
}

func (w *Watcher) handle(ctx context.Context, ev fsnotify.Event) {
	if !ev.Has(fsnotify.Create) && !ev.Has(fsnotify.Write) && !ev.Has(fsnotify.Rename) {
		return
	}
	dir, name := filepath.Dir(ev.Name), filepath.Base(ev.Name)
	switch {
	case w.isAccountDir(dir):
		// new account folder: watch it and its SavedVariables (which may not exist yet)
		w.addAccount(ev.Name)
	case strings.EqualFold(name, "SavedVariables") && w.isAccountDir(filepath.Dir(dir)):
		w.addSavedVarsDir(ev.Name)
	case strings.EqualFold(name, SavedVarsFile):
		w.debounceSavedVars(ev.Name)
	case w.isScreenshotDir(dir) && IsScreenshot(name):
		w.screenshot(ctx, ev.Name)
	case w.isScreenshotDir(dir) && IsTGA(name) && w.cfg.OnTGA != nil:
		w.cfg.OnTGA(ev.Name)
	}
}

func (w *Watcher) screenshot(ctx context.Context, path string) {
	w.mu.Lock()
	if w.inflight[path] {
		w.mu.Unlock()
		return
	}
	w.inflight[path] = true
	w.mu.Unlock()
	go func() {
		defer func() {
			// keep the path marked a little longer: WoW sends several Write events per file
			time.AfterFunc(10*time.Second, func() {
				w.mu.Lock()
				delete(w.inflight, path)
				w.mu.Unlock()
			})
		}()
		if err := WaitStable(ctx, path, 25*time.Millisecond, 75*time.Millisecond, 15*time.Second); err != nil {
			if w.cfg.OnError != nil && ctx.Err() == nil {
				w.cfg.OnError(err)
			}
			return
		}
		w.cfg.OnScreenshot(path)
	}()
}

func (w *Watcher) debounceSavedVars(path string) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if t, ok := w.svTimers[path]; ok {
		t.Reset(w.cfg.Debounce)
		return
	}
	w.svTimers[path] = time.AfterFunc(w.cfg.Debounce, func() {
		w.mu.Lock()
		delete(w.svTimers, path)
		w.mu.Unlock()
		if _, err := os.Stat(path); err == nil && w.cfg.OnSavedVars != nil {
			w.cfg.OnSavedVars(path)
		}
	})
}
