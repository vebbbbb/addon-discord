//go:build !windows

package wowdetect

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLinuxRootsFindsWinePrefixes(t *testing.T) {
	home := t.TempDir()
	mkClient := func(root string) {
		os.MkdirAll(filepath.Join(home, root, "_classic_era_", "Interface", "AddOns"), 0o755)
	}
	mkClient("Games/battlenet/drive_c/Program Files (x86)/World of Warcraft")
	mkClient(".local/share/Steam/steamapps/compatdata/12345/pfx/drive_c/Program Files (x86)/World of Warcraft")
	mkClient(".local/share/bottles/bottles/WoW/drive_c/Program Files/World of Warcraft")
	os.MkdirAll(filepath.Join(home, "Games", "other-game", "drive_c"), 0o755)
	roots := linuxRoots(home)
	if len(roots) != 3 {
		t.Fatalf("roots %v", roots)
	}
	all, _ := Detect(roots)
	if len(all) != 3 {
		t.Fatalf("clients %v", all)
	}
}
