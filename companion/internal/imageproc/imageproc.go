// Package imageproc removes the barcode from a screenshot, scales it and re-encodes it as JPEG.
package imageproc

import (
	"bytes"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"os"

	_ "image/png" // WoW can also be set to png screenshots

	xdraw "golang.org/x/image/draw"
)

// Load decodes a jpg/png file.
func Load(path string) (image.Image, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	img, _, err := image.Decode(f)
	return img, err
}

// RemoveBarcode returns img without the barcode rectangle r.
//
//	"crop": cut off the rows (or columns) that contain the barcode, whichever loses fewer pixels,
//	        if the barcode touches that image edge; otherwise falls back to "fill"
//	"fill": paint the rectangle with the average colour of the pixels around it
//	"none": unchanged
func RemoveBarcode(img image.Image, r image.Rectangle, mode string) image.Image {
	b := img.Bounds()
	r = r.Intersect(b)
	if r.Empty() || mode == "none" {
		return img
	}
	if mode == "crop" {
		slack := max(4, r.Dy()/8)
		type option struct {
			rect image.Rectangle
			lost int
		}
		var opts []option
		if r.Min.Y-b.Min.Y <= slack {
			opts = append(opts, option{image.Rect(b.Min.X, r.Max.Y, b.Max.X, b.Max.Y), r.Max.Y - b.Min.Y})
		}
		if b.Max.Y-r.Max.Y <= slack {
			opts = append(opts, option{image.Rect(b.Min.X, b.Min.Y, b.Max.X, r.Min.Y), b.Max.Y - r.Min.Y})
		}
		if r.Min.X-b.Min.X <= slack {
			opts = append(opts, option{image.Rect(r.Max.X, b.Min.Y, b.Max.X, b.Max.Y), (r.Max.X - b.Min.X) * b.Dy() / max(1, b.Dx())})
		}
		if b.Max.X-r.Max.X <= slack {
			opts = append(opts, option{image.Rect(b.Min.X, b.Min.Y, r.Min.X, b.Max.Y), (b.Max.X - r.Min.X) * b.Dy() / max(1, b.Dx())})
		}
		best := -1
		for i, o := range opts {
			// "lost" is normalised to rows; keep at least half the image
			if o.rect.Dx() < b.Dx()/2 || o.rect.Dy() < b.Dy()/2 {
				continue
			}
			if best < 0 || o.lost < opts[best].lost {
				best = i
			}
		}
		if best >= 0 {
			return subImage(img, opts[best].rect)
		}
	}
	return fill(img, r)
}

func subImage(img image.Image, r image.Rectangle) image.Image {
	if s, ok := img.(interface {
		SubImage(image.Rectangle) image.Image
	}); ok {
		return s.SubImage(r)
	}
	dst := image.NewRGBA(image.Rect(0, 0, r.Dx(), r.Dy()))
	draw.Draw(dst, dst.Bounds(), img, r.Min, draw.Src)
	return dst
}

func fill(img image.Image, r image.Rectangle) image.Image {
	b := img.Bounds()
	ring := r.Inset(-6).Intersect(b)
	var sr, sg, sb, n uint64
	for y := ring.Min.Y; y < ring.Max.Y; y++ {
		for x := ring.Min.X; x < ring.Max.X; x++ {
			if image.Pt(x, y).In(r) {
				continue
			}
			cr, cg, cb, _ := img.At(x, y).RGBA()
			sr, sg, sb, n = sr+uint64(cr), sg+uint64(cg), sb+uint64(cb), n+1
		}
	}
	c := color.RGBA{0, 0, 0, 255}
	if n > 0 {
		c = color.RGBA{uint8(sr / n >> 8), uint8(sg / n >> 8), uint8(sb / n >> 8), 255}
	}
	dst := image.NewRGBA(b)
	draw.Draw(dst, b, img, b.Min, draw.Src)
	draw.Draw(dst, r, &image.Uniform{c}, image.Point{}, draw.Src)
	return dst
}

// Scale shrinks img to at most maxWidth pixels wide (never enlarges).
func Scale(img image.Image, maxWidth int) image.Image {
	b := img.Bounds()
	if maxWidth <= 0 || b.Dx() <= maxWidth {
		return img
	}
	h := b.Dy() * maxWidth / b.Dx()
	dst := image.NewRGBA(image.Rect(0, 0, maxWidth, h))
	xdraw.ApproxBiLinear.Scale(dst, dst.Bounds(), img, b, draw.Src, nil)
	return dst
}

// EncodeJPEG encodes img with the given quality.
func EncodeJPEG(img image.Image, quality int) ([]byte, error) {
	var buf bytes.Buffer
	err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: quality})
	return buf.Bytes(), err
}

// Process = RemoveBarcode + Scale + EncodeJPEG.
func Process(img image.Image, barcode image.Rectangle, mode string, maxWidth, quality int) ([]byte, image.Rectangle, error) {
	out := Scale(RemoveBarcode(img, barcode, mode), maxWidth)
	b, err := EncodeJPEG(out, quality)
	return b, out.Bounds(), err
}
