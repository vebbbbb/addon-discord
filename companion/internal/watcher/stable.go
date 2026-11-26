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

// IsScreenshot reports whether name looks like a WoW screenshot we can read.
func IsScreenshot(name string) bool {
	base := strings.ToLower(filepath.Base(name))
	if !strings.HasPrefix(base, "wowscrnshot_") {
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
	base := strings.ToLower(filepath.Base(name))
	return strings.HasPrefix(base, "wowscrnshot_") && filepath.Ext(base) == ".tga"
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
	tail := make([]byte, 12)
	if _, err := f.ReadAt(tail, st.Size()-12); err != nil && !errors.Is(err, io.EOF) {
		return false
	}
	switch strings.ToLower(filepath.Ext(path)) {
	case ".png":
		return bytes.Contains(tail, []byte("IEND"))
	default: // jpeg: FF D9, possibly followed by padding zeros
		t := bytes.TrimRight(tail, "\x00")
		return len(t) >= 2 && t[len(t)-2] == 0xFF && t[len(t)-1] == 0xD9
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
