package main

import (
	"bytes"
	"image"
	"image/draw"
	"image/jpeg"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/vebbbbb/addon-discord/companion/internal/barcode"
	"github.com/vebbbbb/addon-discord/companion/internal/event"
)

func TestDecodeFlag(t *testing.T) {
	e := &event.Event{Type: "loot", TS: 1764160000, Seq: 3, Char: "Navtok", ClassID: 8, Level: 60,
		Data: map[string]string{"itemId": "19019", "quality": "5", "count": "1", "item": "Thunderfury"}}
	g, _ := barcode.Encode(event.EncodePayload(e))
	code := barcode.Render(g, 8, barcode.Quiet)
	img := image.NewRGBA(image.Rect(0, 0, 1920, 1080))
	draw.Draw(img, code.Bounds().Add(image.Pt(1920-code.Bounds().Dx(), 0)), code, image.Point{}, draw.Src)
	p := filepath.Join(t.TempDir(), "WoWScrnShot_112626_120000.jpg")
	var buf bytes.Buffer
	jpeg.Encode(&buf, img, &jpeg.Options{Quality: 60})
	os.WriteFile(p, buf.Bytes(), 0o644)
	var out bytes.Buffer
	if code := decodeFile(p, &out); code != 0 {
		t.Fatalf("exit %d: %s", code, out.String())
	}
	for _, want := range []string{`"key": "Navtok|1764160000.3"`, "Looted [Thunderfury]", "item=19019"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("missing %s in\n%s", want, out.String())
		}
	}
	blank := filepath.Join(t.TempDir(), "blank.jpg")
	buf.Reset()
	jpeg.Encode(&buf, image.NewRGBA(image.Rect(0, 0, 100, 100)), nil)
	os.WriteFile(blank, buf.Bytes(), 0o644)
	if decodeFile(blank, &out) != 1 {
		t.Fatal("blank image should exit 1")
	}
}
