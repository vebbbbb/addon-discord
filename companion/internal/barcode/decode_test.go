package barcode

import (
	"bytes"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"math/rand"
	"testing"

	xdraw "golang.org/x/image/draw"
)

// fakeScene paints a busy game-like background (gradients, noise, random shapes).
func fakeScene(w, h int, seed int64) *image.RGBA {
	rng := rand.New(rand.NewSource(seed))
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		row := img.Pix[y*img.Stride:]
		for x := 0; x < w; x++ {
			row[x*4], row[x*4+1], row[x*4+2], row[x*4+3] = uint8(x*255/w), uint8(y*255/h), uint8((x+y)%256), 255
		}
	}
	for i := 0; i < 60; i++ {
		r := image.Rect(rng.Intn(w), rng.Intn(h), rng.Intn(w), rng.Intn(h)).Canon()
		c := color.RGBA{uint8(rng.Intn(256)), uint8(rng.Intn(256)), uint8(rng.Intn(256)), 255}
		draw.Draw(img, r, &image.Uniform{c}, image.Point{}, draw.Src)
	}
	// stripes that look a bit like a clock track
	for x := 0; x < w; x += 16 {
		draw.Draw(img, image.Rect(x, h/2, x+8, h/2+20), image.Black, image.Point{}, draw.Src)
	}
	return img
}

func place(scene *image.RGBA, code *image.Gray, corner string) {
	b := scene.Bounds()
	var p image.Point
	switch corner {
	case "tr":
		p = image.Pt(b.Max.X-code.Bounds().Dx(), 0)
	case "tl":
		p = image.Pt(0, 0)
	case "br":
		p = image.Pt(b.Max.X-code.Bounds().Dx(), b.Max.Y-code.Bounds().Dy())
	case "bl":
		p = image.Pt(0, b.Max.Y-code.Bounds().Dy())
	case "mid":
		p = image.Pt(b.Dx()/3, b.Dy()/3)
	}
	draw.Draw(scene, code.Bounds().Add(p), code, image.Point{}, draw.Src)
}

func jpegRoundTrip(t testing.TB, img image.Image, q int) image.Image {
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: q}); err != nil {
		t.Fatal(err)
	}
	out, err := jpeg.Decode(&buf)
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func scale(img image.Image, f float64) image.Image {
	b := img.Bounds()
	dst := image.NewRGBA(image.Rect(0, 0, int(float64(b.Dx())*f), int(float64(b.Dy())*f)))
	xdraw.BiLinear.Scale(dst, dst.Bounds(), img, b, draw.Src, nil)
	return dst
}

func testPayload(n int) []byte {
	p := make([]byte, n)
	rng := rand.New(rand.NewSource(int64(n)))
	for i := range p {
		p[i] = byte(rng.Intn(256))
	}
	return p
}

func TestCRC16CheckValue(t *testing.T) {
	if got := CRC16([]byte("123456789")); got != 0x29B1 {
		t.Fatalf("crc = %04x, want 29b1", got)
	}
}

func TestDecodeJPEGQualitiesScalesCorners(t *testing.T) {
	payloads := [][]byte{[]byte("L\x1f\x1f1764160000\x1f1\x1fNavtok\x1f8\x1f60\x1f19019\x1f5\x1f1\x1fThunderfury"), testPayload(96), testPayload(1), {}}
	for pi, payload := range payloads {
		g, err := Encode(payload)
		if err != nil {
			t.Fatal(err)
		}
		for _, px := range []int{8, 6, 10} {
			if testing.Short() && px != 8 {
				continue
			}
			code := Render(g, px, Quiet)
			for _, corner := range []string{"tr", "tl", "br", "bl", "mid"} {
				scene := fakeScene(1920, 1080, int64(px))
				place(scene, code, corner)
				for _, f := range []float64{1, 0.93, 1.07, 1.25} {
					var src image.Image = scene
					if f != 1 {
						src = scale(scene, f)
					}
					for _, q := range []int{50, 75, 95} {
						name := fmt.Sprintf("p%d/px%d/%s/x%.2f/q%d", pi, px, corner, f, q)
						img := jpegRoundTrip(t, src, q)
						res, err := Decode(img)
						if err != nil {
							t.Errorf("%s: %v", name, err)
							continue
						}
						if !bytes.Equal(res.Payload, payload) {
							t.Errorf("%s: payload mismatch", name)
						}
					}
				}
			}
		}
	}
}

func TestDecodeLowQualityStress(t *testing.T) {
	g, _ := Encode(testPayload(96))
	code := Render(g, ModulePx, Quiet)
	ok := 0
	for q := 20; q <= 45; q += 5 {
		scene := fakeScene(1280, 720, int64(q))
		place(scene, code, "tr")
		if _, err := Decode(jpegRoundTrip(t, scene, q)); err == nil {
			ok++
		} else {
			t.Logf("quality %d: %v", q, err)
		}
	}
	if ok < 5 {
		t.Errorf("only %d/6 very-low-quality images decoded", ok)
	}
}

func TestDecodeRectCoversCode(t *testing.T) {
	g, _ := Encode([]byte("hello"))
	code := Render(g, ModulePx, Quiet)
	scene := fakeScene(1920, 1080, 1)
	place(scene, code, "tr")
	res, err := Decode(jpegRoundTrip(t, scene, 75))
	if err != nil {
		t.Fatal(err)
	}
	want := image.Rect(1920-code.Bounds().Dx(), 0, 1920, code.Bounds().Dy())
	if d := res.Rect.Min.Sub(want.Min); abs(d.X) > 3 || abs(d.Y) > 3 {
		t.Errorf("rect %v, want ~%v", res.Rect, want)
	}
	if d := res.Rect.Max.Sub(want.Max); abs(d.X) > 3 || abs(d.Y) > 3 {
		t.Errorf("rect %v, want ~%v", res.Rect, want)
	}
	if res.Rows != Rows || res.Cols != Cols {
		t.Errorf("dims %dx%d", res.Rows, res.Cols)
	}
}

func TestNoFalsePositive(t *testing.T) {
	for seed := int64(0); seed < 5; seed++ {
		if _, err := Decode(jpegRoundTrip(t, fakeScene(1920, 1080, seed), 75)); err == nil {
			t.Fatal("decoded a barcode from a scene without one")
		}
	}
}

func TestCorruptedCRCRejected(t *testing.T) {
	f, _ := BuildFrame([]byte("abc"))
	f[len(f)-1] ^= 1
	g := BuildGrid(f)
	scene := fakeScene(800, 400, 2)
	place(scene, Render(g, 8, Quiet), "tr")
	if _, err := Decode(scene); err == nil {
		t.Fatal("bad crc accepted")
	}
}

func abs(v int) int {
	if v < 0 {
		return -v
	}
	return v
}

func BenchmarkDecode1080p(b *testing.B) {
	g, _ := Encode(testPayload(80))
	scene := fakeScene(1920, 1080, 3)
	place(scene, Render(g, 8, Quiet), "tr")
	img := jpegRoundTrip(b, scene, 85)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if _, err := Decode(img); err != nil {
			b.Fatal(err)
		}
	}
}
