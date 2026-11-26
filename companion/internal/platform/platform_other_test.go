//go:build linux

package platform

import (
	"os"
	"strings"
	"testing"
)

func TestAutostartEntry(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	if err := SetAutoStart(true); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(AutostartFile())
	if err != nil || !strings.Contains(string(b), "Exec=\"") || !strings.Contains(string(b), "Type=Application") {
		t.Fatalf("%s %v", b, err)
	}
	if err := SetAutoStart(false); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(AutostartFile()); !os.IsNotExist(err) {
		t.Fatal("not removed")
	}
	if SetAutoStart(false) != nil {
		t.Fatal("removing twice must be fine")
	}
}

func TestSingleInstanceLock(t *testing.T) {
	t.Setenv("NAVTOK_HOME", t.TempDir())
	if !SingleInstance(0) {
		t.Fatal("first lock")
	}
	// a second open file description on the same lock file must fail to lock
	held := lockFile
	lockFile = nil
	if SingleInstance(300 * 1e6) {
		t.Fatal("second instance got the lock")
	}
	held.Close()
	if !SingleInstance(0) {
		t.Fatal("lock not free after close")
	}
}
