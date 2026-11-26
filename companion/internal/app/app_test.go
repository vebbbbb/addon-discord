package app

import (
	"bytes"
	"context"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/vebbbbb/addon-discord/companion/internal/barcode"
	"github.com/vebbbbb/addon-discord/companion/internal/config"
	"github.com/vebbbbb/addon-discord/companion/internal/discord"
	"github.com/vebbbbb/addon-discord/companion/internal/event"
	"github.com/vebbbbb/addon-discord/companion/internal/notify"
	"github.com/vebbbbb/addon-discord/companion/internal/state"
	"github.com/vebbbbb/addon-discord/companion/internal/wowdetect"
)

type recorder struct {
	mu    sync.Mutex
	posts []post
}

type post struct {
	msg discord.Message
	img []byte
	at  time.Time
}

func (r *recorder) Post(_ context.Context, m discord.Message, img []byte) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.posts = append(r.posts, post{m, img, time.Now()})
	return nil
}

func (r *recorder) wait(t *testing.T, n int, d time.Duration) []post {
	t.Helper()
	deadline := time.Now().Add(d)
	for time.Now().Before(deadline) {
		r.mu.Lock()
		if len(r.posts) >= n {
			p := append([]post(nil), r.posts...)
			r.mu.Unlock()
			return p
		}
		r.mu.Unlock()
		time.Sleep(10 * time.Millisecond)
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	t.Fatalf("got %d posts, want %d", len(r.posts), n)
	return nil
}

func (r *recorder) count() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.posts)
}

type env struct {
	root, client, shots, sv string
	dataDir                 string
}

func newEnv(t *testing.T) env {
	root := t.TempDir()
	client := filepath.Join(root, "World of Warcraft", "_forever_")
	e := env{root: root, client: client, shots: filepath.Join(client, "Screenshots"),
		sv: filepath.Join(client, "WTF", "Account", "ACC", "SavedVariables"), dataDir: filepath.Join(root, "navtok")}
	for _, d := range []string{filepath.Join(client, "Interface", "AddOns"), e.shots, e.sv, e.dataDir} {
		os.MkdirAll(d, 0o755)
	}
	return e
}

func start(t *testing.T, e env, cfg config.Config) (*App, *recorder, context.CancelFunc) {
	st, err := state.Open(e.dataDir)
	if err != nil {
		t.Fatal(err)
	}
	rec := &recorder{}
	s := discord.NewSender(rec)
	c, _ := wowdetect.ClientFromDir(e.client)
	a := New(cfg, st, s, notify.New(nil), []wowdetect.Client{c})
	ctx, cancel := context.WithCancel(context.Background())
	go a.Run(ctx)
	time.Sleep(100 * time.Millisecond)
	return a, rec, cancel
}

func scene() *image.RGBA {
	img := image.NewRGBA(image.Rect(0, 0, 2560, 1440))
	draw.Draw(img, img.Bounds(), &image.Uniform{color.RGBA{30, 100, 60, 255}}, image.Point{}, draw.Src)
	return img
}

func shotName(t time.Time) string { return "WoWScrnShot_" + t.Local().Format("010206_150405") + ".jpg" }

func writeJPEG(t *testing.T, path string, img image.Image) {
	var buf bytes.Buffer
	jpeg.Encode(&buf, img, &jpeg.Options{Quality: 75})
	if err := os.WriteFile(path+".part", buf.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
	os.Rename(path+".part", path) // like a finished write
}

func screenshotWithEvent(t *testing.T, dir string, e *event.Event) string {
	img := scene()
	g, _ := barcode.Encode(event.EncodePayload(e))
	code := barcode.Render(g, 8, barcode.Quiet)
	draw.Draw(img, code.Bounds().Add(image.Pt(2560-code.Bounds().Dx(), 0)), code, image.Point{}, draw.Src)
	p := filepath.Join(dir, shotName(time.Unix(e.TS, 0)))
	writeJPEG(t, p, img)
	return p
}

func svFile(events ...*event.Event) string {
	var lines []string
	for _, e := range events {
		js := fmt.Sprintf(`{"char":"%s","class":"MAGE","classId":8,"data":{"zone":"Elwynn"},"id":"%s","level":%d,"realm":"Forever","seq":%d,"shot":%d,"test":false,"ts":%d,"type":"level"}`,
			e.Char, e.ID, e.Level, e.Seq, e.Shot, e.TS)
		lines = append(lines, `"`+strings.ReplaceAll(js, `"`, `\"`)+`", -- [x]`)
	}
	return "\nNavtokDiscordDB = {\n[\"settings\"] = {\n[\"position\"] = \"TOPRIGHT\",\n[\"blockSize\"] = 8,\n},\n[\"chars\"] = {\n[\"Navtok-Forever\"] = {\n[\"realm\"] = \"Forever\",\n[\"events\"] = {\n" +
		strings.Join(lines, "\n") + "\n},\n},\n},\n}\n"
}

func levelEvent(ts int64, seq int64, lvl int) *event.Event {
	return &event.Event{Type: "level", TS: ts, Seq: seq, ID: fmt.Sprintf("%d.%d", ts, seq), Char: "Navtok", ClassID: 8, Level: lvl,
		Data: map[string]string{"zone": "Elwynn"}}
}

func TestRealTimeScreenshotPathUnder2s(t *testing.T) {
	e := newEnv(t)
	cfg := config.Defaults()
	_, rec, cancel := start(t, e, cfg)
	defer cancel()
	ev := levelEvent(time.Now().Unix(), 1, 42)
	t0 := time.Now()
	shot := screenshotWithEvent(t, e.shots, ev)
	p := rec.wait(t, 1, 3*time.Second)[0]
	if lat := p.at.Sub(t0); lat > 2*time.Second {
		t.Fatalf("latency %v", lat)
	}
	if p.msg.Embeds[0].Title != "Reached level 42!" || p.msg.Embeds[0].Color != discord.ClassColors["MAGE"] {
		t.Fatalf("%+v", p.msg.Embeds[0])
	}
	img, err := jpeg.Decode(bytes.NewReader(p.img))
	if err != nil {
		t.Fatal(err)
	}
	if img.Bounds().Dx() != 1920 {
		t.Fatalf("not scaled to 1920: %v", img.Bounds())
	}
	if _, err := barcode.Decode(img); err == nil {
		t.Fatal("barcode still in posted image")
	}
	// the same screenshot touched again -> no second post
	os.Chtimes(shot, time.Now(), time.Now())
	os.WriteFile(shot+".x", nil, 0o644)
	time.Sleep(300 * time.Millisecond)
	if rec.count() != 1 {
		t.Fatal("double post")
	}
}

func TestSavedVarsFallbackLateMatchAndDedupe(t *testing.T) {
	old := SVGrace
	SVGrace = 0
	defer func() { SVGrace = old }()
	e := newEnv(t)
	// installed an hour ago (events before installation are ignored by design)
	os.WriteFile(filepath.Join(e.dataDir, "state.json"), []byte(fmt.Sprintf(`{"installed_at":%d}`, time.Now().Unix()-3600)), 0o600)
	cfg := config.Defaults()
	_, rec, cancel := start(t, e, cfg)

	now := time.Now().Unix()
	decoded := levelEvent(now-30, 1, 10) // will be posted live via barcode
	missed := levelEvent(now-20, 2, 11)  // barcode unreadable: screenshot without code
	missed.Shot = now - 19
	noShot := levelEvent(now-10, 3, 12) // no screenshot at all
	screenshotWithEvent(t, e.shots, decoded)
	rec.wait(t, 1, 3*time.Second)

	// screenshot without a readable barcode, taken 1 s after the missed event
	writeJPEG(t, filepath.Join(e.shots, shotName(time.Unix(missed.Shot, 0))), scene())
	time.Sleep(300 * time.Millisecond)
	if rec.count() != 1 {
		t.Fatal("undecodable screenshot must not be posted on its own")
	}

	// /reload writes SavedVariables with all three events
	svPath := filepath.Join(e.sv, "NavtokDiscord.lua")
	os.WriteFile(svPath, []byte(svFile(decoded, missed, noShot)), 0o644)
	posts := rec.wait(t, 3, 5*time.Second)
	byTitle := map[string]post{}
	for _, p := range posts[1:] {
		byTitle[p.msg.Embeds[0].Title] = p
	}
	late, ok := byTitle["Reached level 11! (late)"]
	if !ok || late.img == nil {
		t.Fatalf("missed event not posted late with its screenshot: %v", byTitle)
	}
	if p, ok := byTitle["Reached level 12! (late)"]; !ok || p.img != nil {
		t.Fatalf("no-screenshot event: %v", byTitle)
	}
	if !strings.Contains(late.msg.Embeds[0].Author.Name, "Forever") {
		t.Fatalf("realm from savedvars: %q", late.msg.Embeds[0].Author.Name)
	}
	// SavedVariables written again: nothing new
	os.WriteFile(svPath, []byte(svFile(decoded, missed, noShot)), 0o644)
	time.Sleep(2500 * time.Millisecond)
	if rec.count() != 3 {
		t.Fatalf("reposted: %d", rec.count())
	}
	cancel()

	// restart: catch-up scan must not repost anything either
	_, rec2, cancel2 := start(t, e, cfg)
	defer cancel2()
	time.Sleep(500 * time.Millisecond)
	if rec2.count() != 0 {
		t.Fatalf("restart reposted %d", rec2.count())
	}
}

func TestEventsBeforeInstallAreIgnored(t *testing.T) {
	old := SVGrace
	SVGrace = 0
	defer func() { SVGrace = old }()
	e := newEnv(t)
	ancient := levelEvent(time.Now().Add(-time.Hour).Unix(), 1, 5) // before first run
	os.WriteFile(filepath.Join(e.sv, "NavtokDiscord.lua"), []byte(svFile(ancient)), 0o644)
	_, rec, cancel := start(t, e, config.Defaults())
	defer cancel()
	time.Sleep(500 * time.Millisecond)
	if rec.count() != 0 {
		t.Fatal("posted an event from before NAVTOK was installed")
	}
}

func TestPlanBPayloadPostsWithoutImageOnce(t *testing.T) {
	e := newEnv(t)
	a, rec, cancel := start(t, e, config.Defaults())
	defer cancel()
	ev := levelEvent(time.Now().Unix(), 9, 30)
	for i := 0; i < 3; i++ {
		a.HandlePayload(event.EncodePayload(ev), event.FromBand, nil)
	}
	p := rec.wait(t, 1, 2*time.Second)
	time.Sleep(200 * time.Millisecond)
	if rec.count() != 1 || p[0].img != nil || p[0].msg.Embeds[0].Image != nil {
		t.Fatal("plan B post")
	}
}

func TestSendTest(t *testing.T) {
	e := newEnv(t)
	a, rec, cancel := start(t, e, config.Defaults())
	defer cancel()
	done := make(chan error, 1)
	a.SendTest(func(err error) { done <- err })
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if rec.wait(t, 1, time.Second)[0].msg.Embeds[0].Title != "NAVTOK is connected" {
		t.Fatal("test title")
	}
}
