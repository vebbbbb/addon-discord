package watcher

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime/debug"
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
	// OnLog gets diagnostic lines (every file seen in a Screenshots folder).
	OnLog    func(string)
	Debounce time.Duration
	// RescanEvery: safety-net folder check interval (default 3 s).
	RescanEvery time.Duration
}

// Watcher multiplexes one fsnotify watcher over all folders.
type Watcher struct {
	cfg Config
	fs  *fsnotify.Watcher

	mu   sync.Mutex
	seen map[string]bool // screenshot paths already handled (or present at start)

	readErrLogged bool // only touched by rescanLoop
	svTimers      map[string]*time.Timer
}

// RescanEvery is the default safety-net interval: the Screenshots folders are also listed this
// often, in case a file notification was missed.
const RescanEvery = 3 * time.Second

// New creates the folders' watches. Missing Screenshots folders are created (WoW creates them
// lazily on the first screenshot, but we need a folder to watch).
func New(cfg Config) (*Watcher, error) {
	if cfg.Debounce == 0 {
		cfg.Debounce = 1500 * time.Millisecond
	}
	if cfg.RescanEvery == 0 {
		cfg.RescanEvery = RescanEvery
	}
	fw, err := fsnotify.NewWatcher()
	if err != nil {
		return nil, err
	}
	w := &Watcher{cfg: cfg, fs: fw, seen: map[string]bool{}, svTimers: map[string]*time.Timer{}}
	for _, d := range cfg.ScreenshotDirs {
		_ = os.MkdirAll(d, 0o755)
		if err := fw.Add(d); err != nil {
			fw.Close()
			return nil, err
		}
		entries, _ := os.ReadDir(d) // existing screenshots are not new
		for _, e := range entries {
			w.seen[strings.ToLower(filepath.Join(d, e.Name()))] = true
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
	defer func() {
		if r := recover(); r != nil && w.cfg.OnLog != nil {
			w.cfg.OnLog(fmt.Sprintf("watcher crashed: %v\n%s", r, debug.Stack()))
		}
	}()
	// The folder check runs on its own goroutine: it must keep working even if the
	// notification loop below were ever stuck.
	go w.rescanLoop(ctx)
	if w.cfg.OnLog != nil {
		w.cfg.OnLog(fmt.Sprintf("watcher running (%d screenshot folder(s), folder check every %s)", len(w.cfg.ScreenshotDirs), w.cfg.RescanEvery))
	}
	// This loop only reads events and never calls back into fsnotify (no Add): on Windows
	// fsnotify.Add waits for fsnotify's own goroutine, which waits for us to read the next event -
	// calling Add from here deadlocks and the watcher goes deaf.
	for {
		select {
		case <-ctx.Done():
			if w.cfg.OnLog != nil {
				w.cfg.OnLog("watcher stopped")
			}
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
		// new account folder: watch it and its SavedVariables (which may not exist yet).
		// In a separate goroutine: never call fsnotify.Add from the event loop (see Run).
		if ev.Has(fsnotify.Create) {
			go w.addAccount(ev.Name)
		}
	case strings.EqualFold(name, "SavedVariables") && w.isAccountDir(filepath.Dir(dir)):
		if ev.Has(fsnotify.Create) {
			go w.addSavedVarsDir(ev.Name)
		}
	case strings.EqualFold(name, SavedVarsFile):
		w.debounceSavedVars(ev.Name)
	case w.isScreenshotDir(dir) && IsScreenshot(name):
		w.screenshot(ctx, ev.Name)
	case w.isScreenshotDir(dir) && IsTGA(name) && w.cfg.OnTGA != nil:
		w.cfg.OnTGA(ev.Name)
	case w.isScreenshotDir(dir) && w.cfg.OnLog != nil && ev.Has(fsnotify.Create):
		w.cfg.OnLog("ignoring " + name + " in the Screenshots folder (not a .jpg/.png)")
	}
}

func (w *Watcher) rescanLoop(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil && w.cfg.OnLog != nil {
			w.cfg.OnLog(fmt.Sprintf("folder check crashed: %v\n%s", r, debug.Stack()))
		}
	}()
	rescan := time.NewTicker(w.cfg.RescanEvery)
	defer rescan.Stop()
	alive := time.NewTicker(30 * time.Minute)
	defer alive.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-alive.C:
			if w.cfg.OnLog != nil {
				w.mu.Lock()
				n := len(w.seen)
				w.mu.Unlock()
				w.cfg.OnLog(fmt.Sprintf("watcher alive (%d screenshots known)", n))
			}
		case <-rescan.C:
			w.rescan(ctx)
		}
	}
}

// rescan lists the Screenshots folders and handles image files that no notification announced.
func (w *Watcher) rescan(ctx context.Context) {
	for _, d := range w.cfg.ScreenshotDirs {
		entries, err := os.ReadDir(d)
		if err != nil {
			if w.cfg.OnLog != nil && !w.readErrLogged {
				w.readErrLogged = true
				w.cfg.OnLog("cannot read " + d + ": " + err.Error())
			}
			continue
		}
		for _, e := range entries {
			if e.IsDir() || !IsScreenshot(e.Name()) {
				continue
			}
			p := filepath.Join(d, e.Name())
			w.mu.Lock()
			known := w.seen[strings.ToLower(p)]
			w.mu.Unlock()
			if !known {
				if w.cfg.OnLog != nil {
					w.cfg.OnLog("found " + e.Name() + " by folder check (no change notification)")
				}
				w.screenshot(ctx, p)
			}
		}
	}
}

func (w *Watcher) screenshot(ctx context.Context, path string) {
	key := strings.ToLower(path)
	w.mu.Lock()
	if w.seen[key] {
		w.mu.Unlock()
		return
	}
	w.seen[key] = true
	w.mu.Unlock()
	if w.cfg.OnLog != nil {
		w.cfg.OnLog("new screenshot " + filepath.Base(path))
	}
	go func() {
		defer func() {
			if r := recover(); r != nil && w.cfg.OnLog != nil {
				w.cfg.OnLog(fmt.Sprintf("crash while handling %s: %v\n%s", filepath.Base(path), r, debug.Stack()))
			}
		}()
		if err := WaitStable(ctx, path, 25*time.Millisecond, 75*time.Millisecond, 15*time.Second); err != nil {
			if w.cfg.OnError != nil && ctx.Err() == nil {
				w.cfg.OnError(errors.New(filepath.Base(path) + ": " + err.Error()))
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
