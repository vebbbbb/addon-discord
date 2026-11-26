//go:build !windows

package wowdetect

import (
	"os"
	"path/filepath"
)

// wineInstalls are the places WoW usually lives inside a Wine prefix.
var wineInstalls = []string{
	"drive_c/Program Files (x86)/World of Warcraft",
	"drive_c/Program Files/World of Warcraft",
	"drive_c/World of Warcraft",
	"drive_c/Games/World of Warcraft",
}

// prefixGlobs are Wine prefixes of common Linux launchers, relative to $HOME.
var prefixGlobs = []string{
	".wine",
	"Games/*",                         // Lutris (e.g. ~/Games/battlenet, ~/Games/world-of-warcraft)
	"Games/Heroic/Prefixes/*",         // Heroic
	"Games/Heroic/Prefixes/default/*", // Heroic (newer layout)
	".local/share/lutris/prefixes/*",  // Lutris (alternative)
	".local/share/bottles/bottles/*",  // Bottles
	".var/app/com.usebottles.bottles/data/bottles/bottles/*",
	".local/share/Steam/steamapps/compatdata/*/pfx",                                  // Steam / Proton
	".steam/steam/steamapps/compatdata/*/pfx",                                        // Steam (symlinked root)
	".var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/compatdata/*/pfx", // Steam Flatpak
	".var/app/net.lutris.Lutris/data/lutris/prefixes/*",                              // Lutris Flatpak
}

// Roots returns candidate WoW installation roots on Linux (Wine/Lutris/Steam/Bottles/Heroic
// prefixes) plus $NAVTOK_WOW_ROOT and ~/Games/World of Warcraft.
func Roots() []string {
	var roots []string
	if r := os.Getenv("NAVTOK_WOW_ROOT"); r != "" {
		roots = append(roots, r)
	}
	if p := os.Getenv("WINEPREFIX"); p != "" {
		roots = append(roots, installsIn(p)...)
	}
	h, err := os.UserHomeDir()
	if err != nil {
		return roots
	}
	return append(roots, linuxRoots(h)...)
}

func linuxRoots(home string) []string {
	var roots []string
	if p := filepath.Join(home, "Games", "World of Warcraft"); dirExists(p) {
		roots = append(roots, p)
	}
	for _, g := range prefixGlobs {
		prefixes, _ := filepath.Glob(filepath.Join(home, g))
		for _, pfx := range prefixes {
			roots = append(roots, installsIn(pfx)...)
		}
	}
	return roots
}

func installsIn(prefix string) []string {
	var out []string
	for _, rel := range wineInstalls {
		if p := filepath.Join(prefix, rel); dirExists(p) {
			out = append(out, p)
		}
	}
	return out
}
