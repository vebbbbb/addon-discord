// Package tray is the system tray UI: Last post, Send test, Open log, Quit.
package tray

import (
	"bytes"
	"encoding/binary"
	"image"
	"image/color"
	"image/png"
)

// IconICO draws the tray icon (a blurple tile with a white "N"-ish barcode) and wraps the PNG in
// an ICO container (Windows Vista+ accept PNG-compressed ICO entries).
func IconICO() []byte {
	const s = 32
	img := image.NewNRGBA(image.Rect(0, 0, s, s))
	blurple := color.NRGBA{0x58, 0x65, 0xF2, 0xFF}
	white := color.NRGBA{0xFF, 0xFF, 0xFF, 0xFF}
	for y := 0; y < s; y++ {
		for x := 0; x < s; x++ {
			// rounded corners
			dx, dy := min(x, s-1-x), min(y, s-1-y)
			if dx+dy < 4 {
				continue
			}
			img.Set(x, y, blurple)
		}
	}
	// N: two bars and a diagonal, made of 2 px blocks like the barcode modules
	for y := 8; y < 24; y++ {
		for _, x := range []int{8, 9, 22, 23} {
			img.Set(x, y, white)
		}
		d := 8 + (y-8)*14/16
		img.Set(d, y, white)
		img.Set(d+1, y, white)
	}
	var p bytes.Buffer
	_ = png.Encode(&p, img)
	var ico bytes.Buffer
	binary.Write(&ico, binary.LittleEndian, []uint16{0, 1, 1}) // reserved, type icon, count
	ico.Write([]byte{s, s, 0, 0})                              // w, h, palette, reserved
	binary.Write(&ico, binary.LittleEndian, []uint16{1, 32})   // planes, bpp
	binary.Write(&ico, binary.LittleEndian, []uint32{uint32(p.Len()), 22})
	ico.Write(p.Bytes())
	return ico.Bytes()
}
