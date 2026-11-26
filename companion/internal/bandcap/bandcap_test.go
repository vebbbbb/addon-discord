package bandcap

import (
	"image"
	"testing"
)

func TestBandRect(t *testing.T) {
	cases := map[string]image.Rectangle{
		TopRight:    image.Rect(1920-BandW, 0, 1920, BandH),
		TopLeft:     image.Rect(0, 0, BandW, BandH),
		BottomRight: image.Rect(1920-BandW, 1080-BandH, 1920, 1080),
		BottomLeft:  image.Rect(0, 1080-BandH, BandW, 1080),
	}
	for c, want := range cases {
		if got := BandRect(1920, 1080, c); got != want {
			t.Errorf("%s: %v want %v", c, got, want)
		}
	}
	if got := BandRect(800, 200, TopRight); got != image.Rect(0, 0, 800, 200) {
		t.Errorf("small window %v", got)
	}
}

func TestIsWoWWindow(t *testing.T) {
	if !IsWoWWindow("GxWindowClass", "") || !IsWoWWindow("x", "World of Warcraft") || IsWoWWindow("Chrome_WidgetWin_1", "WoW guide") {
		t.Fatal()
	}
}
