// Package watcher watches the Screenshots folder and the SavedVariables files with fsnotify
// (ReadDirectoryChangesW on Windows - no folder polling).
package watcher

import (
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// IsScreenshot reports whether name is an image we can read. Any name is accepted: clients do
// not all use the classic "WoWScrnShot_MMDDYY_HHMMSS.jpg" pattern.
func IsScreenshot(name string) bool {
	base := strings.ToLower(filepath.Base(name))
	if strings.HasPrefix(base, ".") || strings.HasSuffix(base, ".tmp") {
		return false
	}
	switch filepath.Ext(base) {
	case ".jpg", ".jpeg", ".png":
		return true
	}
	return false
}

// IsTGA: WoW is set to TGA screenshots, which we cannot decode (VERIFY.md item 2).
func IsTGA(name string) bool {
	return strings.ToLower(filepath.Ext(name)) == ".tga"
}

// complete checks the end-of-image marker so a half-written file is never decoded.
func complete(path string) bool {
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil || st.Size() < 16 {
		return false
	}
	n := int64(64)
	if st.Size() < n {
		n = st.Size()
	}
	tail := make([]byte, n)
	if _, err := f.ReadAt(tail, st.Size()-n); err != nil && !errors.Is(err, io.EOF) {
		return false
	}
	switch strings.ToLower(filepath.Ext(path)) {
	case ".png":
		return bytes.Contains(tail, []byte("IEND"))
	default: // jpeg: FF D9 near the end (some writers pad or append a few bytes)
		return bytes.Contains(tail, []byte{0xFF, 0xD9})
	}
}

// WaitStable waits until the file size has been unchanged for `settle` and the image is complete.
// It polls the single file every `step` (cheap: only while a screenshot is being written).
func WaitStable(ctx context.Context, path string, step, settle, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	var last int64 = -1
	var since time.Time
	for {
		st, err := os.Stat(path)
		if err == nil {
			if st.Size() != last {
				last, since = st.Size(), time.Now()
			} else if st.Size() > 0 && time.Since(since) >= settle && complete(path) {
				return nil
			} else if st.Size() > 0 && time.Since(since) >= time.Second {
				return nil // size unchanged for a second: done, even without the end marker
			}
		}
		if time.Now().After(deadline) {
			if err != nil {
				return err
			}
			return errors.New("watcher: file never became stable")
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(step):
		}
	}
}
