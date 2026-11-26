// Package app wires the companion together:
//
//	screenshot created ─► wait complete ─► decode barcode ─► claim ─► crop/scale/JPEG ─► queue ─► Discord
//	SavedVariables changed ─► parse ─► unposted events ─► match screenshot ±3 s ─► "(late)" post
//	plan B: live window band ─► decode ─► claim ─► post without screenshot
package app

import (
	"context"
	"errors"
	"fmt"
	"image"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/navtok/navtok-discord/companion/internal/bandcap"
	"github.com/navtok/navtok-discord/companion/internal/barcode"
	"github.com/navtok/navtok-discord/companion/internal/config"
	"github.com/navtok/navtok-discord/companion/internal/discord"
	"github.com/navtok/navtok-discord/companion/internal/event"
	"github.com/navtok/navtok-discord/companion/internal/imageproc"
	"github.com/navtok/navtok-discord/companion/internal/logx"
	"github.com/navtok/navtok-discord/companion/internal/matcher"
	"github.com/navtok/navtok-discord/companion/internal/notify"
	"github.com/navtok/navtok-discord/companion/internal/savedvars"
	"github.com/navtok/navtok-discord/companion/internal/state"
	"github.com/navtok/navtok-discord/companion/internal/watcher"
	"github.com/navtok/navtok-discord/companion/internal/wowdetect"
)

// Problem keys (one notification per problem until resolved).
const (
	ProblemOffline = "offline"
	ProblemWebhook = "webhook"
	ProblemTGA     = "tga"
	ProblemWatch   = "watch"
)

// SVGrace: SavedVariables events newer than this are left to the barcode path for a moment
// (the screenshot of an event that happened right before /reload may still be processing).
var SVGrace = 8 * time.Second

// App is one running companion.
type App struct {
	Cfg      config.Config
	State    *state.Store
	Sender   *discord.Sender
	Index    *matcher.Index
	Problems *notify.Problems
	Clients  []wowdetect.Client
	// OnPosted is called after each successful post with a one-line summary (tray).
	OnPosted func(summary string)

	now   func() time.Time
	svMu  sync.Mutex
	chars sync.Map // char name -> realm (learned from SavedVariables)
	// addon settings learned from SavedVariables (barcode corner/size for undecodable shots)
	setMu    sync.Mutex
	position string
	blockPx  int
}

// New creates an App. sender may be built with a DryRun poster.
func New(cfg config.Config, st *state.Store, sender *discord.Sender, problems *notify.Problems, clients []wowdetect.Client) *App {
	return &App{Cfg: cfg, State: st, Sender: sender, Problems: problems, Clients: clients,
		Index: matcher.New(time.Duration(cfg.LateWindowHours+1) * time.Hour), now: time.Now,
		position: "TOPRIGHT", blockPx: barcode.ModulePx}
}

func (a *App) screenshotDirs() []string {
	var out []string
	for _, c := range a.Clients {
		out = append(out, c.ScreenshotsDir())
	}
	return out
}

func (a *App) accountDirs() []string {
	var out []string
	for _, c := range a.Clients {
		out = append(out, c.AccountDir())
	}
	return out
}

// Run starts watchers, the sender and (if enabled) plan B, then blocks until ctx is done.
func (a *App) Run(ctx context.Context) error {
	w, err := watcher.New(watcher.Config{
		ScreenshotDirs: a.screenshotDirs(),
		AccountDirs:    a.accountDirs(),
		OnScreenshot:   func(p string) { a.HandleScreenshot(ctx, p) },
		OnSavedVars:    func(p string) { a.HandleSavedVars(ctx, p) },
		OnTGA: func(p string) {
			a.Problems.Report(ProblemTGA, "WoW saves screenshots as TGA. NAVTOK needs JPG: type /console screenshotFormat jpg in WoW.")
		},
		OnError: func(err error) { logx.Printf("watch: %v", err) },
	})
	if err != nil {
		a.Problems.Report(ProblemWatch, "NAVTOK cannot watch the WoW folders: "+err.Error())
		return err
	}
	go a.Sender.Run(ctx)
	go w.Run(ctx)
	if a.Cfg.PlanBBandCapture {
		go func() {
			logx.Printf("plan B: band capture enabled (corner %s)", a.Cfg.BandCorner)
			if err := bandcap.Run(ctx, a.Cfg.BandCorner, 100*time.Millisecond, func(p []byte) { a.HandlePayload(p, event.FromBand, nil) }); err != nil {
				logx.Printf("plan B: %v", err)
			}
		}()
	}
	// catch up: screenshots and SavedVariables written while NAVTOK was not running
	a.Index.Scan(a.screenshotDirs(), a.now().Add(-time.Duration(a.Cfg.LateWindowHours)*time.Hour), watcher.IsScreenshot)
	for _, f := range watcher.SavedVarsFiles(a.accountDirs()) {
		a.HandleSavedVars(ctx, f)
	}
	logx.Printf("watching %d client(s): %s", len(a.Clients), strings.Join(a.screenshotDirs(), ", "))
	<-ctx.Done()
	return nil
}

func (a *App) skip(e *event.Event) bool {
	if e.Test && a.Cfg.SkipTestEvents {
		return true
	}
	return false
}

func (a *App) enrich(e *event.Event) {
	if e.Realm == "" {
		if r, ok := a.chars.Load(e.Char); ok {
			e.Realm = r.(string)
		}
	}
	if e.Class == "" {
		e.Class = event.ClassToken(e.ClassID)
	}
}

// HandleScreenshot is the real-time path.
func (a *App) HandleScreenshot(ctx context.Context, path string) {
	start := a.now()
	img, err := imageproc.Load(path)
	if err != nil {
		logx.Printf("screenshot %s: %v", filepath.Base(path), err)
		return
	}
	res, err := barcode.Decode(img)
	shotTime := matcher.ShotTime(path, time.Local)
	if err != nil {
		a.Index.Add(path, shotTime, false)
		logx.Printf("screenshot %s: no barcode (%s)", filepath.Base(path), logx.Since(start))
		return
	}
	a.Index.Add(path, shotTime, true)
	a.HandlePayload(res.Payload, event.FromBarcode, &shot{path: path, img: img, rect: res.Rect, start: start})
}

type shot struct {
	path  string
	img   image.Image
	rect  image.Rectangle
	start time.Time
}

// HandlePayload posts a decoded barcode payload (screenshot or plan B).
func (a *App) HandlePayload(p []byte, src event.Source, s *shot) {
	e, err := event.ParsePayload(p)
	if err != nil {
		logx.Printf("barcode payload: %v", err)
		return
	}
	e.Source = src
	a.enrich(e)
	if a.skip(e) || !a.State.Claim(e) {
		return
	}
	var jpg []byte
	if s != nil {
		jpg, _, err = imageproc.Process(s.img, s.rect, a.Cfg.BarcodeRemoval, a.Cfg.MaxImageWidth, a.Cfg.JPEGQuality)
		if err != nil {
			logx.Printf("image %s: %v", filepath.Base(s.path), err)
			jpg = nil
		}
	}
	path := ""
	start := a.now()
	if s != nil {
		path, start = s.path, s.start
	}
	a.enqueue(e, jpg, path, start)
}

func (a *App) enqueue(e *event.Event, jpg []byte, shotPath string, start time.Time) {
	msg := discord.Build(e, discord.Options{WowheadBase: a.Cfg.WowheadBase, HasImage: len(jpg) > 0})
	summary := discord.Summary(e)
	a.Sender.Enqueue(&discord.Job{Event: e, Msg: msg, Image: jpg, Done: func(err error) {
		if err != nil {
			a.State.Release(e)
			logx.Printf("post %s failed permanently: %v", e.Key(), err)
			var pe *discord.PermanentError
			if errors.As(err, &pe) && (pe.Status == 401 || pe.Status == 403 || pe.Status == 404) {
				a.Problems.Report(ProblemWebhook, "The Discord webhook was rejected (deleted?). Run NAVTOK.exe --setup to enter a new one.")
			}
			return
		}
		a.Problems.Resolve(ProblemOffline)
		a.Problems.Resolve(ProblemWebhook)
		if err := a.State.MarkPosted(e, summary); err != nil {
			logx.Printf("state: %v", err)
		}
		logx.Printf("posted %s [%s] %q in %s (event age %ds)", e.Key(), e.Source, summary, logx.Since(start), a.now().Unix()-e.TS)
		if a.Cfg.DeleteScreenshots && shotPath != "" {
			_ = os.Remove(shotPath)
		}
		if a.OnPosted != nil {
			a.OnPosted(summary)
		}
	}})
}

// HandleSavedVars is the safety net: post every logged event that was not posted yet.
func (a *App) HandleSavedVars(ctx context.Context, path string) {
	a.svMu.Lock()
	defer a.svMu.Unlock()
	g, err := savedvars.ParseFile(path)
	if err != nil {
		logx.Printf("savedvars %s: %v", path, err)
		return
	}
	a.learnSettings(g)
	chars, bad := savedvars.Events(g)
	if bad > 0 {
		logx.Printf("savedvars: %d unreadable event lines", bad)
	}
	now := a.now()
	installed := a.State.InstalledAt()
	oldest := now.Add(-time.Duration(a.Cfg.LateWindowHours) * time.Hour).Unix()
	recheck := false
	var pending []*event.Event
	for _, c := range chars {
		for _, e := range c.Events {
			if e.Char != "" && e.Realm != "" {
				a.chars.Store(e.Char, e.Realm)
			}
			if e.TS < installed || e.TS < oldest || a.skip(e) || a.State.Posted(e) {
				continue
			}
			if now.Unix()-e.TS < int64(SVGrace/time.Second) {
				recheck = true
				continue
			}
			pending = append(pending, e)
		}
	}
	if len(pending) > 0 {
		a.Index.Scan(a.screenshotDirs(), time.Unix(pending[0].TS, 0).Add(-time.Minute), watcher.IsScreenshot)
	}
	for _, e := range pending {
		if !a.State.Claim(e) {
			continue
		}
		e.Late = true
		a.enrich(e)
		jpg, shotPath := a.lateImage(e)
		logx.Printf("late event %s (%s), screenshot: %q", e.Key(), e.Type, filepath.Base(shotPath))
		a.enqueue(e, jpg, shotPath, now)
	}
	if recheck {
		time.AfterFunc(SVGrace, func() {
			if ctx.Err() == nil {
				a.HandleSavedVars(ctx, path)
			}
		})
	}
}

// lateImage finds and prepares the screenshot of a late event (nil when none matches).
func (a *App) lateImage(e *event.Event) ([]byte, string) {
	at := e.TS
	if e.Shot > 0 {
		at = e.Shot
	}
	tol := time.Duration(a.Cfg.MatchToleranceSec) * time.Second
	for tries := 0; tries < 5; tries++ {
		p := a.Index.Find(time.Unix(at, 0), tol)
		if p == "" {
			return nil, ""
		}
		img, err := imageproc.Load(p)
		if err != nil {
			continue
		}
		rect := a.expectedRect(img.Bounds())
		if res, err := barcode.Decode(img); err == nil {
			other, perr := event.ParsePayload(res.Payload)
			if perr == nil && other.ID != e.ID {
				// this screenshot belongs to a different event: never attach it here
				a.Index.Add(p, time.Time{}, true)
				continue
			}
			rect = res.Rect
		}
		jpg, _, err := imageproc.Process(img, rect, a.Cfg.BarcodeRemoval, a.Cfg.MaxImageWidth, a.Cfg.JPEGQuality)
		if err != nil {
			return nil, ""
		}
		return jpg, p
	}
	return nil, ""
}

func (a *App) learnSettings(g map[string]any) {
	s := savedvars.Settings(g)
	if s == nil {
		return
	}
	a.setMu.Lock()
	defer a.setMu.Unlock()
	if p, ok := s.Get("position").(string); ok && p != "" {
		a.position = p
	}
	if b, ok := s.Get("blockSize").(float64); ok && b >= 2 {
		a.blockPx = int(b)
	}
}

// expectedRect is where the (undecodable) barcode should be, from the addon settings.
func (a *App) expectedRect(b image.Rectangle) image.Rectangle {
	a.setMu.Lock()
	pos, px := a.position, a.blockPx
	a.setMu.Unlock()
	w, h := (barcode.Cols+2*barcode.Quiet)*px, (barcode.Rows+2*barcode.Quiet)*px
	x0, y0 := b.Max.X-w, b.Min.Y
	if strings.HasSuffix(pos, "LEFT") {
		x0 = b.Min.X
	}
	if strings.HasPrefix(pos, "BOTTOM") {
		y0 = b.Max.Y - h
	}
	return image.Rect(x0, y0, x0+w, y0+h)
}

// SendTest posts a connection test message (tray "Send test").
func (a *App) SendTest(done func(error)) {
	e := &event.Event{Type: "test", Test: true, Char: "NAVTOK", TS: a.now().Unix(), ID: fmt.Sprintf("test.%d", a.now().UnixNano())}
	msg := discord.Build(e, discord.Options{})
	a.Sender.Enqueue(&discord.Job{Event: e, Msg: msg, Done: done})
}
