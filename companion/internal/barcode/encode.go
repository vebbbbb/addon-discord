package barcode

import (
	"errors"
	"image"
	"image/color"
)

// Grid is a module matrix; Bits[r*Cols+c] == 1 means black.
type Grid struct {
	Rows, Cols int
	Bits       []byte
}

// At returns the module at row r, column c.
func (g Grid) At(r, c int) byte { return g.Bits[r*g.Cols+c] }

// BuildFrame wraps a payload: "NV" version length payload crc16(big endian).
func BuildFrame(payload []byte) ([]byte, error) {
	if len(payload) > MaxPayload {
		return nil, errors.New("barcode: payload too long")
	}
	f := make([]byte, 0, len(payload)+6)
	f = append(f, magic[0], magic[1], Version, byte(len(payload)))
	f = append(f, payload...)
	crc := CRC16(f)
	return append(f, byte(crc>>8), byte(crc)), nil
}

// BuildGrid lays the frame into the default 13x77 grid.
func BuildGrid(frame []byte) Grid { return BuildGridSize(frame, Rows, Cols) }

// BuildGridSize lays the frame into a rows x cols grid: L finder (left column + bottom row solid),
// clock tracks (top row, right column), data row-major MSB-first, pad 0xEC 0x11..., zero bits.
func BuildGridSize(frame []byte, rows, cols int) Grid {
	g := Grid{Rows: rows, Cols: cols, Bits: make([]byte, rows*cols)}
	for r := 0; r < rows; r++ {
		for c := 0; c < cols; c++ {
			var v byte
			switch {
			case c == 0 || r == rows-1:
				v = 1
			case r == 0:
				if c%2 == 0 {
					v = 1
				}
			case c == cols-1:
				if (rows-1-r)%2 == 0 {
					v = 1
				}
			}
			g.Bits[r*cols+c] = v
		}
	}
	capBits := (rows - 2) * (cols - 2)
	capBytes := capBits / 8
	stream := append([]byte(nil), frame...)
	pad := [2]byte{0xEC, 0x11}
	for p := 0; len(stream) < capBytes; p ^= 1 {
		stream = append(stream, pad[p])
	}
	i := 0
	for r := 1; r < rows-1; r++ {
		for c := 1; c < cols-1; c++ {
			var v byte
			if bi := i / 8; bi < len(stream) {
				v = (stream[bi] >> (7 - uint(i%8))) & 1
			}
			g.Bits[r*cols+c] = v
			i++
		}
	}
	return g
}

// Encode builds the default grid for a payload.
func Encode(payload []byte) (Grid, error) {
	f, err := BuildFrame(payload)
	if err != nil {
		return Grid{}, err
	}
	return BuildGrid(f), nil
}

// Render draws the grid like the addon does: white quiet zone, module px x px black squares.
func Render(g Grid, px, quiet int) *image.Gray {
	w, h := (g.Cols+2*quiet)*px, (g.Rows+2*quiet)*px
	img := image.NewGray(image.Rect(0, 0, w, h))
	for i := range img.Pix {
		img.Pix[i] = 0xFF
	}
	for r := 0; r < g.Rows; r++ {
		for c := 0; c < g.Cols; c++ {
			if g.At(r, c) == 0 {
				continue
			}
			x0, y0 := (quiet+c)*px, (quiet+r)*px
			for y := y0; y < y0+px; y++ {
				for x := x0; x < x0+px; x++ {
					img.SetGray(x, y, color.Gray{0})
				}
			}
		}
	}
	return img
}
