// fakeshot writes a fake WoW screenshot carrying a NAVTOK barcode - a developer tool to test the
// companion without the game:
//
//	go run ./companion/cmd/fakeshot -dir "<client>/Screenshots" -type level -level 42
package main

import (
	"bytes"
	"flag"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"os"
	"path/filepath"
	"time"

	"github.com/navtok/navtok-discord/companion/internal/barcode"
	"github.com/navtok/navtok-discord/companion/internal/event"
)

func main() {
	dir := flag.String("dir", ".", "Screenshots folder")
	typ := flag.String("type", "level", "event type: "+fmt.Sprint(event.Types))
	char := flag.String("char", "Navtok", "character name")
	level := flag.Int("level", 60, "character level")
	w := flag.Int("w", 1920, "width")
	h := flag.Int("h", 1080, "height")
	q := flag.Int("q", 75, "JPEG quality")
	test := flag.Bool("test", true, "mark as test event")
	flag.Parse()
	samples := map[string]map[string]string{
		"loot":       {"itemId": "19019", "quality": "5", "count": "1", "item": "Thunderfury, Blessed Blade of the Windseeker"},
		"skill":      {"skill": "Mining", "rank": "300"},
		"level":      {"zone": "Elwynn Forest"},
		"reputation": {"faction": "Stormwind", "standing": "8"},
		"death":      {"zone": "Stranglethorn Vale", "subzone": "Booty Bay", "killer": "Bloodsail Swashbuckler"},
		"dungeon":    {"encounterId": "0", "encounter": "Edwin VanCleef", "instance": "The Deadmines"},
		"bg":         {"bg": "Warsong Gulch", "result": "win", "duration": "1234", "kb": "7", "hk": "31", "deaths": "2", "honor": "412"},
		"legacy":     {"text": "Legacy challenge complete: Explorer"},
	}
	data, ok := samples[*typ]
	if !ok {
		fmt.Fprintln(os.Stderr, "unknown type", *typ)
		os.Exit(2)
	}
	now := time.Now()
	e := &event.Event{Type: *typ, Test: *test, TS: now.Unix(), Seq: int64(now.Nanosecond() % 100000), Char: *char, ClassID: 8, Level: *level, Data: data}
	g, err := barcode.Encode(event.EncodePayload(e))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	code := barcode.Render(g, barcode.ModulePx, barcode.Quiet)
	img := image.NewRGBA(image.Rect(0, 0, *w, *h))
	for y := 0; y < *h; y++ {
		for x := 0; x < *w; x++ {
			img.Set(x, y, color.RGBA{uint8(40 + x*80 / *w), uint8(60 + y*100 / *h), 90, 255})
		}
	}
	draw.Draw(img, code.Bounds().Add(image.Pt(*w-code.Bounds().Dx(), 0)), code, image.Point{}, draw.Src)
	var buf bytes.Buffer
	jpeg.Encode(&buf, img, &jpeg.Options{Quality: *q})
	os.MkdirAll(*dir, 0o755)
	p := filepath.Join(*dir, "WoWScrnShot_"+now.Format("010206_150405")+".jpg")
	if err := os.WriteFile(p, buf.Bytes(), 0o644); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println(p)
}
