package tray

import (
	"bytes"
	"encoding/binary"
	"image/png"
	"testing"
)

func TestIconICO(t *testing.T) {
	ico := IconICO()
	var hdr [3]uint16
	binary.Read(bytes.NewReader(ico), binary.LittleEndian, &hdr)
	if hdr != [3]uint16{0, 1, 1} {
		t.Fatal(hdr)
	}
	img, err := png.Decode(bytes.NewReader(ico[22:]))
	if err != nil || img.Bounds().Dx() != 32 {
		t.Fatal(err)
	}
}
