//go:build windows

package bandcap

import (
	"context"
	"errors"
	"image"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"

	"github.com/navtok/navtok-discord/companion/internal/barcode"
)

var (
	user32                  = windows.NewLazySystemDLL("user32.dll")
	gdi32                   = windows.NewLazySystemDLL("gdi32.dll")
	procGetForegroundWindow = user32.NewProc("GetForegroundWindow")
	procGetClassNameW       = user32.NewProc("GetClassNameW")
	procGetWindowTextW      = user32.NewProc("GetWindowTextW")
	procGetClientRect       = user32.NewProc("GetClientRect")
	procClientToScreen      = user32.NewProc("ClientToScreen")
	procGetDC               = user32.NewProc("GetDC")
	procReleaseDC           = user32.NewProc("ReleaseDC")
	procCreateCompatibleDC  = gdi32.NewProc("CreateCompatibleDC")
	procCreateDIBSection    = gdi32.NewProc("CreateDIBSection")
	procSelectObject        = gdi32.NewProc("SelectObject")
	procBitBlt              = gdi32.NewProc("BitBlt")
	procDeleteObject        = gdi32.NewProc("DeleteObject")
	procDeleteDC            = gdi32.NewProc("DeleteDC")
)

const (
	srccopy    = 0x00CC0020
	captureblt = 0x40000000
)

type rect struct{ Left, Top, Right, Bottom int32 }
type point struct{ X, Y int32 }

type bitmapInfoHeader struct {
	Size          uint32
	Width         int32
	Height        int32
	Planes        uint16
	BitCount      uint16
	Compression   uint32
	SizeImage     uint32
	XPelsPerMeter int32
	YPelsPerMeter int32
	ClrUsed       uint32
	ClrImportant  uint32
}

func windowString(proc *windows.LazyProc, hwnd uintptr) string {
	buf := make([]uint16, 256)
	proc.Call(hwnd, uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
	return windows.UTF16ToString(buf)
}

// foregroundWoW returns the screen rectangle of WoW's client area if WoW is in the foreground.
func foregroundWoW() (image.Rectangle, bool) {
	hwnd, _, _ := procGetForegroundWindow.Call()
	if hwnd == 0 {
		return image.Rectangle{}, false
	}
	if !IsWoWWindow(windowString(procGetClassNameW, hwnd), windowString(procGetWindowTextW, hwnd)) {
		return image.Rectangle{}, false
	}
	var r rect
	if ok, _, _ := procGetClientRect.Call(hwnd, uintptr(unsafe.Pointer(&r))); ok == 0 {
		return image.Rectangle{}, false
	}
	var p point
	procClientToScreen.Call(hwnd, uintptr(unsafe.Pointer(&p)))
	return image.Rect(int(p.X), int(p.Y), int(p.X+r.Right), int(p.Y+r.Bottom)), true
}

// grab copies a screen rectangle into a gray image.
func grab(r image.Rectangle) (*image.Gray, error) {
	w, h := r.Dx(), r.Dy()
	screen, _, _ := procGetDC.Call(0)
	if screen == 0 {
		return nil, errors.New("bandcap: GetDC failed")
	}
	defer procReleaseDC.Call(0, screen)
	mem, _, _ := procCreateCompatibleDC.Call(screen)
	if mem == 0 {
		return nil, errors.New("bandcap: CreateCompatibleDC failed")
	}
	defer procDeleteDC.Call(mem)
	bi := bitmapInfoHeader{Size: uint32(unsafe.Sizeof(bitmapInfoHeader{})), Width: int32(w), Height: -int32(h),
		Planes: 1, BitCount: 32}
	var bits unsafe.Pointer
	bmp, _, _ := procCreateDIBSection.Call(mem, uintptr(unsafe.Pointer(&bi)), 0, uintptr(unsafe.Pointer(&bits)), 0, 0)
	if bmp == 0 || bits == nil {
		return nil, errors.New("bandcap: CreateDIBSection failed")
	}
	defer procDeleteObject.Call(bmp)
	old, _, _ := procSelectObject.Call(mem, bmp)
	defer procSelectObject.Call(mem, old)
	if ok, _, _ := procBitBlt.Call(mem, 0, 0, uintptr(w), uintptr(h), screen, uintptr(r.Min.X), uintptr(r.Min.Y), srccopy|captureblt); ok == 0 {
		return nil, errors.New("bandcap: BitBlt failed")
	}
	px := unsafe.Slice((*byte)(bits), w*h*4)
	g := image.NewGray(image.Rect(0, 0, w, h))
	for i := 0; i < w*h; i++ {
		b, gg, rr := px[i*4], px[i*4+1], px[i*4+2]
		g.Pix[i] = byte((19595*uint32(rr) + 38470*uint32(gg) + 7471*uint32(b) + 1<<15) >> 16)
	}
	return g, nil
}

// Run captures the band every interval while WoW is in the foreground and calls onPayload for
// every barcode read. The decoder is the same one used for screenshots.
func Run(ctx context.Context, corner string, interval time.Duration, onPayload func([]byte)) error {
	t := time.NewTicker(interval)
	defer t.Stop()
	var last []byte
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-t.C:
		}
		win, ok := foregroundWoW()
		if !ok || win.Dx() < 64 || win.Dy() < 64 {
			last = nil
			continue
		}
		band := BandRect(win.Dx(), win.Dy(), corner).Add(win.Min)
		img, err := grab(band)
		if err != nil {
			continue
		}
		res, err := barcode.Decode(img)
		if err != nil {
			last = nil
			continue
		}
		if string(res.Payload) == string(last) {
			continue // same barcode still on screen
		}
		last = res.Payload
		onPayload(res.Payload)
	}
}

// Supported reports whether plan B works on this OS.
func Supported() bool { return true }
