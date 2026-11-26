//go:build windows

package platform

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"time"

	"github.com/ncruces/zenity"
	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

const runKey = `Software\Microsoft\Windows\CurrentVersion\Run`

// SetAutoStart adds/removes NAVTOK in HKCU\...\Run (no admin rights needed).
func SetAutoStart(on bool) error {
	k, _, err := registry.CreateKey(registry.CURRENT_USER, runKey, registry.SET_VALUE|registry.QUERY_VALUE)
	if err != nil {
		return err
	}
	defer k.Close()
	if !on {
		err := k.DeleteValue(AppName)
		if errors.Is(err, registry.ErrNotExist) {
			return nil
		}
		return err
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	return k.SetStringValue(AppName, fmt.Sprintf(`"%s"`, exe))
}

var mutex windows.Handle

// SingleInstance returns false if another NAVTOK is already running (named mutex, no ports).
// wait > 0 keeps trying that long (used right after a restart, while the old process exits).
func SingleInstance(wait time.Duration) bool {
	name, _ := windows.UTF16PtrFromString(`Local\NAVTOK-Discord-Companion`)
	deadline := time.Now().Add(wait)
	for {
		h, err := windows.CreateMutex(nil, false, name)
		if err == nil {
			mutex = h
			return true
		}
		if h != 0 {
			windows.CloseHandle(h)
		}
		if !errors.Is(err, windows.ERROR_ALREADY_EXISTS) {
			return true
		}
		if time.Now().After(deadline) {
			return false
		}
		time.Sleep(250 * time.Millisecond)
	}
}

// Restart starts a new NAVTOK process (after an update); the caller then quits.
func Restart() error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	return exec.Command(exe, "--restarted").Start()
}

// Open opens a file or folder with its default application.
func Open(path string) error {
	return exec.Command("explorer.exe", path).Start()
}

// AskWebhook shows the first-run entry dialog. ok=false when cancelled.
func AskWebhook(prompt string) (string, bool) {
	s, err := zenity.Entry(prompt, zenity.Title(AppName+" - Discord webhook"), zenity.Width(520))
	if err != nil {
		return "", false
	}
	return s, true
}

// ShowError shows an error dialog.
func ShowError(msg string) { _ = zenity.Error(msg, zenity.Title(AppName)) }

// ShowInfo shows an info dialog.
func ShowInfo(msg string) { _ = zenity.Info(msg, zenity.Title(AppName)) }

// PickFolder lets the user choose the WoW Forever client folder.
func PickFolder(prompt string) (string, bool) {
	_ = zenity.Info(prompt, zenity.Title(AppName))
	p, err := zenity.SelectFile(zenity.Directory(), zenity.Title(AppName+" - choose the WoW Forever folder"))
	if err != nil {
		return "", false
	}
	return p, true
}

// PickFromList lets the user choose one of several items.
func PickFromList(prompt string, items []string) (string, bool) {
	s, err := zenity.List(prompt, items, zenity.Title(AppName), zenity.Width(560), zenity.Height(320))
	if err != nil {
		return "", false
	}
	return s, true
}

// Notify shows a Windows notification.
func Notify(title, msg string) { _ = zenity.Notify(msg, zenity.Title(title)) }

// Interactive reports whether dialogs can be shown.
func Interactive() bool { return true }
