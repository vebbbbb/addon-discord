package barcode

import (
	"errors"
	"image"
	"image/color"
)

// Result of a successful decode.
type Result struct {
	Version int
	Payload []byte
	// Rect is the barcode including its quiet zone, in image coordinates.
	Rect image.Rectangle
	// Module size in pixels (horizontal, vertical) as measured.
	ModuleW, ModuleH float64
	Rows, Cols       int
}

// ErrNotFound means no valid barcode was found in the image.
var ErrNotFound = errors.New("barcode: not found")

const (
	threshold  = 128
	minCols    = 21
	minRows    = 5
	maxAttempt = 400
)

// luma is a read-only 8-bit view on an image region.
type luma struct {
	pix    []byte
	stride int
	rect   image.Rectangle
}

func (l *luma) at(x, y int) byte {
	if x < l.rect.Min.X || y < l.rect.Min.Y || x >= l.rect.Max.X || y >= l.rect.Max.Y {
		return 0xFF
	}
	return l.pix[(y-l.rect.Min.Y)*l.stride+(x-l.rect.Min.X)]
}

func (l *luma) black(x, y int) bool { return l.at(x, y) < threshold }

// newLuma gives a luma view of r without copying for YCbCr/Gray images.
func newLuma(img image.Image, r image.Rectangle) *luma {
	r = r.Intersect(img.Bounds())
	switch m := img.(type) {
	case *image.YCbCr:
		off := m.YOffset(r.Min.X, r.Min.Y)
		return &luma{pix: m.Y[off:], stride: m.YStride, rect: r}
	case *image.Gray:
		off := m.PixOffset(r.Min.X, r.Min.Y)
		return &luma{pix: m.Pix[off:], stride: m.Stride, rect: r}
	}
	g := image.NewGray(r)
	for y := r.Min.Y; y < r.Max.Y; y++ {
		for x := r.Min.X; x < r.Max.X; x++ {
			g.Pix[g.PixOffset(x, y)] = color.GrayModel.Convert(img.At(x, y)).(color.Gray).Y
		}
	}
	return &luma{pix: g.Pix, stride: g.Stride, rect: r}
}

// Regions returns the search order: the four corners (the addon draws in a corner), then the
// whole image.
func Regions(b image.Rectangle) []image.Rectangle {
	w, h := b.Dx(), b.Dy()
	cw, ch := max(min(w, 1100), w/2), max(min(h, 360), h/3)
	cw, ch = min(cw, w), min(ch, h)
	return []image.Rectangle{
		image.Rect(b.Max.X-cw, b.Min.Y, b.Max.X, b.Min.Y+ch), // top-right (default)
		image.Rect(b.Min.X, b.Min.Y, b.Min.X+cw, b.Min.Y+ch), // top-left
		image.Rect(b.Max.X-cw, b.Max.Y-ch, b.Max.X, b.Max.Y), // bottom-right
		image.Rect(b.Min.X, b.Max.Y-ch, b.Min.X+cw, b.Max.Y), // bottom-left
		b,
	}
}

// Decode searches img for a NAVTOK barcode.
func Decode(img image.Image) (*Result, error) {
	for _, r := range Regions(img.Bounds()) {
		if res, err := DecodeRegion(img, r); err == nil {
			return res, nil
		}
	}
	return nil, ErrNotFound
}

// DecodeRegion searches only inside r (used by plan B for the captured band).
func DecodeRegion(img image.Image, r image.Rectangle) (*Result, error) {
	l := newLuma(img, r)
	d := decoder{l: l}
	return d.scan()
}

type run struct {
	black      bool
	start, len int
}

type decoder struct {
	l        *luma
	runs     []run
	attempts int
	tried    map[[3]int]bool
}

func (d *decoder) rowRuns(y int) []run {
	d.runs = d.runs[:0]
	r := d.l.rect
	cur := run{black: d.l.black(r.Min.X, y), start: r.Min.X}
	for x := r.Min.X + 1; x < r.Max.X; x++ {
		b := d.l.black(x, y)
		if b != cur.black {
			cur.len = x - cur.start
			d.runs = append(d.runs, cur)
			cur = run{black: b, start: x}
		}
	}
	cur.len = r.Max.X - cur.start
	return append(d.runs, cur)
}

func (d *decoder) scan() (*Result, error) {
	d.tried = map[[3]int]bool{}
	r := d.l.rect
	for y := r.Min.Y; y < r.Max.Y; y++ {
		runs := d.rowRuns(y)
		for i := 0; i < len(runs); i++ {
			if !runs[i].black {
				continue
			}
			n, x0, x1 := clockAt(runs, i)
			if n < minCols {
				continue
			}
			// one attempt per (x0, x1) span and module row band
			key := [3]int{x0 / 2, x1 / 2, y / max(1, (x1-x0)/n)}
			if d.tried[key] {
				i += n - 1
				continue
			}
			d.tried[key] = true
			d.attempts++
			if res := d.try(x0, x1, n, y); res != nil {
				return res, nil
			}
			if d.attempts > maxAttempt {
				return nil, ErrNotFound
			}
			i += n - 1
		}
	}
	return nil, ErrNotFound
}

// clockAt checks whether runs[i:] starts an alternating black/white sequence of equal-length runs
// bounded by wider white runs (the quiet zone). Returns run count and pixel span.
func clockAt(runs []run, i int) (n, x0, x1 int) {
	first := runs[i]
	if first.len < 2 {
		return 0, 0, 0
	}
	// quiet zone (or image edge) before the clock
	if i > 0 && float64(runs[i-1].len) < 1.3*float64(first.len) {
		return 0, 0, 0
	}
	sum := 0
	j := i
	for ; j < len(runs); j++ {
		avg := float64(first.len)
		if j > i {
			avg = float64(sum) / float64(j-i)
		}
		l := float64(runs[j].len)
		if l < 0.5*avg || l > 1.6*avg {
			break
		}
		sum += runs[j].len
	}
	n = j - i
	if n%2 == 0 { // must end on black
		n--
		if n > 0 {
			sum -= runs[i+n].len
		}
	}
	if n < minCols {
		return 0, 0, 0
	}
	avg := float64(sum) / float64(n)
	end := i + n
	if end < len(runs) && float64(runs[end].len) < 1.3*avg {
		return 0, 0, 0
	}
	return n, first.start, first.start + sum
}

func (d *decoder) try(x0, x1, cols, y int) *Result {
	l := d.l
	mw := float64(x1-x0) / float64(cols)
	xl := x0 + int(mw*0.5)
	if !l.black(xl, y) {
		return nil
	}
	// vertical extent along the solid left column
	top := y
	for top > l.rect.Min.Y && l.black(xl, top-1) {
		top--
	}
	bottom := y
	for bottom < l.rect.Max.Y && l.black(xl, bottom) {
		bottom++
	}
	height := bottom - top
	// rows from the right clock column
	xr := x1 - 1 - int(mw*0.5)
	if !l.black(xr, top) {
		return nil
	}
	var col []run
	cur := run{black: true, start: top}
	for yy := top + 1; yy < bottom; yy++ {
		if b := l.black(xr, yy); b != cur.black {
			cur.len = yy - cur.start
			col = append(col, cur)
			cur = run{black: b, start: yy}
		}
	}
	cur.len = bottom - cur.start
	col = mergeSlivers(append(col, cur), max(1, int(mw*0.35)))
	lens := make([]int, len(col))
	for i, c := range col {
		lens[i] = c.len
	}
	rows := len(lens)
	if rows%2 == 0 || rows < minRows {
		return nil
	}
	mh := float64(height) / float64(rows)
	for _, n := range lens {
		if float64(n) < 0.5*mh || float64(n) > 1.6*mh {
			return nil
		}
	}
	if ratio := mh / mw; ratio < 0.6 || ratio > 1.6 {
		return nil
	}
	sample := func(r, c int) byte {
		cx := float64(x0) + (float64(c)+0.5)*mw
		cy := float64(top) + (float64(r)+0.5)*mh
		rx, ry := max(0, int(mw*0.2)), max(0, int(mh*0.2))
		sum, n := 0, 0
		for dy := -ry; dy <= ry; dy++ {
			for dx := -rx; dx <= rx; dx++ {
				sum += int(l.at(int(cx)+dx, int(cy)+dy))
				n++
			}
		}
		if sum/n < threshold {
			return 1
		}
		return 0
	}
	// finder check: bottom row and left column solid (allow a few errors)
	bad := 0
	for c := 0; c < cols; c++ {
		if sample(rows-1, c) != 1 {
			bad++
		}
	}
	for r := 0; r < rows; r++ {
		if sample(r, 0) != 1 {
			bad++
		}
	}
	if bad > (rows+cols)/10 {
		return nil
	}
	// data
	nbits := (rows - 2) * (cols - 2)
	data := make([]byte, (nbits+7)/8)
	i := 0
	for r := 1; r < rows-1; r++ {
		for c := 1; c < cols-1; c++ {
			if sample(r, c) == 1 {
				data[i/8] |= 0x80 >> uint(i%8)
			}
			i++
		}
	}
	payload, ver, ok := parseFrame(data)
	if !ok {
		return nil
	}
	qx, qy := int(float64(Quiet)*mw+0.5), int(float64(Quiet)*mh+0.5)
	rect := image.Rect(x0-qx, top-qy, x1+qx, bottom+qy)
	return &Result{Version: ver, Payload: payload, Rect: rect, ModuleW: mw, ModuleH: mh, Rows: rows, Cols: cols}
}

func parseFrame(data []byte) ([]byte, int, bool) {
	if len(data) < 6 || data[0] != magic[0] || data[1] != magic[1] {
		return nil, 0, false
	}
	ver := int(data[2])
	if ver != Version {
		return nil, 0, false
	}
	n := int(data[3])
	if n > MaxPayload || 4+n+2 > len(data) {
		return nil, 0, false
	}
	crc := CRC16(data[:4+n])
	if byte(crc>>8) != data[4+n] || byte(crc) != data[5+n] {
		return nil, 0, false
	}
	return append([]byte(nil), data[4:4+n]...), ver, true
}

// mergeSlivers folds runs shorter than minLen (JPEG/scaling edge artefacts) into their neighbours.
func mergeSlivers(runs []run, minLen int) []run {
	out := make([]run, 0, len(runs))
	for _, r := range runs {
		if len(out) > 0 && (r.len < minLen || out[len(out)-1].black == r.black) {
			out[len(out)-1].len += r.len
			continue
		}
		if len(out) > 0 && out[len(out)-1].len < minLen {
			// previous run was a leading sliver: absorb it into this one
			r.start = out[len(out)-1].start
			r.len += out[len(out)-1].len
			out[len(out)-1] = r
			continue
		}
		out = append(out, r)
	}
	// a sliver merged into its predecessor may now sit between equal colours: collapse them
	res := out[:0]
	for _, r := range out {
		if len(res) > 0 && res[len(res)-1].black == r.black {
			res[len(res)-1].len += r.len
			continue
		}
		res = append(res, r)
	}
	return res
}
