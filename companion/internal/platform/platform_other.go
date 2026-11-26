//go:build !windows

package platform

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"

	"github.com/vebbbbb/addon-discord/companion/internal/config"
)

// AutostartFile is the XDG autostart entry (Linux): the desktop starts NAVTOK at login.
func AutostartFile() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		h, _ := os.UserHomeDir()
		base = filepath.Join(h, ".config")
	}
	return filepath.Join(base, "autostart", "navtok.desktop")
}

// SetAutoStart writes or removes ~/.config/autostart/navtok.desktop (Linux only).
func SetAutoStart(on bool) error {
	if runtime.GOOS != "linux" {
		return nil
	}
	f := AutostartFile()
	if !on {
		if err := os.Remove(f); err != nil && !os.IsNotExist(err) {
			return err
		}
		return nil
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	if exe, err = filepath.EvalSymlinks(exe); err != nil {
		return err
	}
	desktop := "[Desktop Entry]\nType=Application\nName=NAVTOK\nComment=Posts WoW Forever milestones to Discord\n" +
		"Exec=\"" + strings.ReplaceAll(exe, `"`, `\"`) + "\"\nTerminal=false\nX-GNOME-Autostart-enabled=true\nNoDisplay=true\n"
	if err := os.MkdirAll(filepath.Dir(f), 0o755); err != nil {
		return err
	}
	return os.WriteFile(f, []byte(desktop), 0o644)
}

var lockFile *os.File

// SingleInstance takes an exclusive lock on <data dir>/navtok.lock; false if another NAVTOK
// holds it. wait > 0 keeps trying that long (after a restart).
func SingleInstance(wait time.Duration) bool {
	dir, err := config.Dir()
	if err != nil {
		return true
	}
	f, err := os.OpenFile(filepath.Join(dir, "navtok.lock"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return true
	}
	deadline := time.Now().Add(wait)
	for {
		if syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB) == nil {
			lockFile = f // keep it open for the life of the process
			return true
		}
		if time.Now().After(deadline) {
			f.Close()
			return false
		}
		time.Sleep(250 * time.Millisecond)
	}
}

// Restart starts a new process with the same binary.
func Restart() error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	return exec.Command(exe, append([]string{"--restarted"}, os.Args[1:]...)...).Start()
}

// Detach starts NAVTOK again in its own session (no terminal), so the caller can exit and the
// user can close the terminal. The child waits for this process to release the lock.
func Detach() error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	cmd := exec.Command(exe, "--restarted")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	cmd.Stdin, cmd.Stdout, cmd.Stderr = nil, nil, nil
	return cmd.Start()
}

// Open uses xdg-open.
func Open(path string) error { return exec.Command("xdg-open", path).Start() }

func ask(prompt string) (string, bool) {
	fmt.Fprint(os.Stderr, prompt+"\n> ")
	s, err := bufio.NewReader(os.Stdin).ReadString('\n')
	if err != nil {
		return "", false
	}
	return strings.TrimSpace(s), true
}

func AskWebhook(prompt string) (string, bool) { return ask(prompt) }
func ShowError(msg string)                    { fmt.Fprintln(os.Stderr, "ERROR:", msg) }
func ShowInfo(msg string)                     { fmt.Fprintln(os.Stderr, msg) }
func PickFolder(prompt string) (string, bool) { return ask(prompt) }
func PickFromList(prompt string, items []string) (string, bool) {
	for i, it := range items {
		fmt.Fprintf(os.Stderr, "  %d) %s\n", i+1, it)
	}
	s, ok := ask(prompt + " (number)")
	if !ok {
		return "", false
	}
	var n int
	if _, err := fmt.Sscan(s, &n); err != nil || n < 1 || n > len(items) {
		return "", false
	}
	return items[n-1], true
}

// Notify shows a desktop notification (notify-send) and also prints it.
func Notify(title, msg string) {
	fmt.Fprintf(os.Stderr, "[%s] %s\n", title, msg)
	if p, err := exec.LookPath("notify-send"); err == nil {
		_ = exec.Command(p, "--app-name=NAVTOK", title, msg).Start()
	}
}

// Interactive reports whether a terminal is attached for prompts. /dev/null (what a desktop
// autostart gives a program as stdin) is a character device too, so it is excluded.
func Interactive() bool {
	st, err := os.Stdin.Stat()
	if err != nil || st.Mode()&os.ModeCharDevice == 0 {
		return false
	}
	if null, err := os.Stat(os.DevNull); err == nil && os.SameFile(st, null) {
		return false
	}
	return true
}
