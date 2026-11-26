//go:build !windows

package bandcap

import (
	"context"
	"errors"
	"time"
)

// Run is only implemented on Windows.
func Run(ctx context.Context, corner string, interval time.Duration, onPayload func([]byte)) error {
	return errors.New("bandcap: plan B band capture is only supported on Windows")
}

// Supported reports whether plan B works on this OS.
func Supported() bool { return false }
