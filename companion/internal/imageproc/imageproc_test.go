package imageproc

import (
	"bytes"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"testing"

	"github.com/vebbbbb/addon-discord/companion/internal/barcode"
)

func scene(w, h int) *image.RGBA {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	draw.Draw(img, img.Bounds(), &image.Uniform{color.RGBA{40, 90, 160, 255}}, image.Point{}, draw.Src)
	return img
}

func withCode(w, h int, at string) (*image.RGBA, image.Rectangle) {
	img := scene(w, h)
	g, _ := barcode.Encode([]byte("x"))
	code := barcode.Render(g, 8, barcode.Quiet)
	var p image.Point
	switch at {
	case "tr":
		p = image.Pt(w-code.Bounds().Dx(), 0)
	case "bl":
		p = image.Pt(0, h-code.Bounds().Dy())
	case "mid":
		p = image.Pt(w/3, h/3)
	}
	r := code.Bounds().Add(p)
	draw.Draw(img, r, code, image.Point{}, draw.Src)
	return img, r
}

func TestCropTopRightRemovesRows(t *testing.T) {
	img, _ := withCode(1920, 1080, "tr")
	res, err := barcode.Decode(img)
	if err != nil {
		t.Fatal(err)
	}
	out := RemoveBarcode(img, res.Rect, "crop")
	if out.Bounds().Dx() != 1920 || out.Bounds().Dy() != 1080-res.Rect.Max.Y {
		t.Fatalf("bounds %v (rect %v)", out.Bounds(), res.Rect)
	}
	if _, err := barcode.Decode(out); err == nil {
		t.Fatal("barcode still present after crop")
	}
}

func TestCropBottomLeft(t *testing.T) {
	img, r := withCode(1280, 720, "bl")
	out := RemoveBarcode(img, r, "crop")
	if out.Bounds().Max.Y != r.Min.Y || out.Bounds().Dx() != 1280 {
		t.Fatalf("bounds %v", out.Bounds())
	}
}

func TestFillWhenNotAtEdge(t *testing.T) {
	img, r := withCode(1280, 720, "mid")
	out := RemoveBarcode(img, r, "crop")
	if out.Bounds() != img.Bounds() {
		t.Fatal("mid barcode must be filled, not cropped")
	}
	c := color.RGBAModel.Convert(out.At(r.Min.X+20, r.Min.Y+20)).(color.RGBA)
	if c.R != 40 || c.G != 90 || c.B != 160 {
		t.Fatalf("fill colour %v", c)
	}
	if _, err := barcode.Decode(out); err == nil {
		t.Fatal("barcode still decodes")
	}
}

func TestNoneKeeps(t *testing.T) {
	img, r := withCode(800, 600, "tr")
	if RemoveBarcode(img, r, "none") != image.Image(img) {
		t.Fatal("none must not change")
	}
}

func TestScaleAndEncode(t *testing.T) {
	img, r := withCode(3840, 2160, "tr")
	b, bounds, err := Process(img, r, "crop", 1920, 85)
	if err != nil {
		t.Fatal(err)
	}
	if bounds.Dx() != 1920 {
		t.Fatalf("width %d", bounds.Dx())
	}
	dec, err := jpeg.Decode(bytes.NewReader(b))
	if err != nil || dec.Bounds().Dx() != 1920 {
		t.Fatal(err)
	}
	small := scene(1280, 720)
	if Scale(small, 1920) != image.Image(small) {
		t.Fatal("must not upscale")
	}
}
