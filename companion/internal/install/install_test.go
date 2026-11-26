package install

import (
	"os"
	"path/filepath"
	"testing"

	navtok "github.com/vebbbbb/addon-discord"
)

func TestInstallEmbeddedAddon(t *testing.T) {
	addOns := filepath.Join(t.TempDir(), "Interface", "AddOns")
	other := filepath.Join(addOns, "OtherAddon")
	os.MkdirAll(other, 0o755)
	os.WriteFile(filepath.Join(other, "x.lua"), []byte("x"), 0o644)

	res, err := Install(navtok.AddonFS, navtok.AddonRoot, addOns)
	if err != nil {
		t.Fatal(err)
	}
	toc := filepath.Join(addOns, AddonName, "NavtokDiscord.toc")
	b, err := os.ReadFile(toc)
	if err != nil || len(res.Written) < 10 {
		t.Fatalf("written %v err %v", res.Written, err)
	}
	if string(b[:len("## Interface: 16001")]) != "## Interface: 16001" {
		t.Fatal("toc content")
	}
	if _, err := os.Stat(filepath.Join(addOns, AddonName, "Notifiers", "Battleground.lua")); err != nil {
		t.Fatal(err)
	}
	// second run: nothing to do
	res, _ = Install(navtok.AddonFS, navtok.AddonRoot, addOns)
	if res.Changed() {
		t.Fatalf("not idempotent: %+v", res)
	}
	// modified + stale files are repaired
	os.WriteFile(toc, []byte("broken"), 0o644)
	os.WriteFile(filepath.Join(addOns, AddonName, "Old.lua"), []byte("old"), 0o644)
	res, _ = Install(navtok.AddonFS, navtok.AddonRoot, addOns)
	if len(res.Written) != 1 || len(res.Removed) != 1 {
		t.Fatalf("%+v", res)
	}
	if _, err := os.Stat(filepath.Join(other, "x.lua")); err != nil {
		t.Fatal("touched another addon")
	}
	h1, _ := Hash(navtok.AddonFS, navtok.AddonRoot)
	if len(h1) != 16 {
		t.Fatal(h1)
	}
	if err := Uninstall(addOns); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(other); err != nil {
		t.Fatal("uninstall removed another addon")
	}
}
