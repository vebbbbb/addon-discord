//go:build !windows

package wowdetect

import (
	"os"
	"path/filepath"
)

// Roots on non-Windows systems (development): $NAVTOK_WOW_ROOT or ~/Games/World of Warcraft.
func Roots() []string {
	var roots []string
	if r := os.Getenv("NAVTOK_WOW_ROOT"); r != "" {
		roots = append(roots, r)
	}
	if h, err := os.UserHomeDir(); err == nil {
		p := filepath.Join(h, "Games", "World of Warcraft")
		if dirExists(p) {
			roots = append(roots, p)
		}
	}
	return roots
}
