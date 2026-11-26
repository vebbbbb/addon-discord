// Package bandcap is plan B: when Screenshot() cannot be called from addon code, the addon holds
// the barcode on screen for ~0.6 s and NAVTOK reads it from a thin band of the live WoW window.
// It captures ONLY while WoW is the foreground window and only the corner band the barcode is
// drawn in. It reads pixels from the screen (GDI BitBlt) - never game memory, never input.
package bandcap

import (
	"image"
	"strings"
)

// Corner names as used in config ("top-right" etc.).
const (
	TopLeft     = "top-left"
	TopRight    = "top-right"
	BottomLeft  = "bottom-left"
	BottomRight = "bottom-right"
)

// BandW and BandH bound the captured band in pixels (the barcode is 81x17 modules = 648x136 px
// at 8 px modules; leave room for larger module sizes).
const (
	BandW = 1100
	BandH = 300
)

// BandRect returns the band to capture inside a client area of w x h pixels.
func BandRect(w, h int, corner string) image.Rectangle {
	bw, bh := min(w, BandW), min(h, BandH)
	corner = strings.ToLower(corner)
	x0, y0 := w-bw, 0
	if strings.HasSuffix(corner, "left") {
		x0 = 0
	}
	if strings.HasPrefix(corner, "bottom") {
		y0 = h - bh
	}
	return image.Rect(x0, y0, x0+bw, y0+bh)
}

// IsWoWWindow decides from the window class/title whether the foreground window is WoW.
func IsWoWWindow(class, title string) bool {
	c := strings.ToLower(class)
	return strings.HasPrefix(c, "gxwindowclass") || strings.EqualFold(strings.TrimSpace(title), "World of Warcraft")
}
