//go:build !windows

package platform

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

// SetAutoStart is a no-op outside Windows.
func SetAutoStart(bool) error { return nil }

// SingleInstance always succeeds outside Windows.
func SingleInstance(time.Duration) bool { return true }

// Restart starts a new process with the same binary.
func Restart() error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	return exec.Command(exe, append([]string{"--restarted"}, os.Args[1:]...)...).Start()
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
func Notify(title, msg string) { fmt.Fprintf(os.Stderr, "[%s] %s\n", title, msg) }

// Interactive reports whether a terminal is attached for prompts.
func Interactive() bool {
	st, err := os.Stdin.Stat()
	return err == nil && st.Mode()&os.ModeCharDevice != 0
}
