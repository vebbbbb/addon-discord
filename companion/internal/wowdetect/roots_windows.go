//go:build windows

package wowdetect

import (
	"os"
	"path/filepath"

	"golang.org/x/sys/windows/registry"
)

// Roots returns candidate installation roots: registry first, then common paths on every drive.
func Roots() []string {
	var roots []string
	for _, k := range []string{
		`SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft`,
		`SOFTWARE\Blizzard Entertainment\World of Warcraft`,
	} {
		key, err := registry.OpenKey(registry.LOCAL_MACHINE, k, registry.QUERY_VALUE)
		if err != nil {
			continue
		}
		for _, v := range []string{"InstallPath", "GamePath"} {
			if s, _, err := key.GetStringValue(v); err == nil && s != "" {
				roots = append(roots, NormalizeRoot(s))
			}
		}
		key.Close()
	}
	for d := 'C'; d <= 'Z'; d++ {
		drive := string(d) + `:\`
		if _, err := os.Stat(drive); err != nil {
			continue
		}
		for _, rel := range []string{
			`Program Files (x86)\World of Warcraft`, `Program Files\World of Warcraft`, `World of Warcraft`,
			`Games\World of Warcraft`, `Blizzard\World of Warcraft`, `Battle.net\World of Warcraft`,
		} {
			p := filepath.Join(drive, rel)
			if dirExists(p) {
				roots = append(roots, p)
			}
		}
	}
	return roots
}
