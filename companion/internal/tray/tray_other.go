//go:build !windows

package tray

// Menu callbacks (no tray outside Windows: the companion runs in the console).
type Menu struct {
	OnSendTest  func()
	OnUpdate    func()
	OnOpenLog   func()
	OnQuit      func()
	SetLastPost func(string)
}

// Run just calls ready and blocks forever; OnQuit is driven by signals in main.
func Run(m *Menu, _ string, ready func()) {
	m.SetLastPost = func(string) {}
	ready()
	select {}
}

// Available reports whether a tray exists on this OS.
func Available() bool { return false }

// Quit is a no-op without a tray: cancelling the context ends the console run.
func Quit() {}
