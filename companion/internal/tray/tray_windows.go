//go:build windows

package tray

import (
	"fyne.io/systray"
)

// Menu callbacks.
type Menu struct {
	OnSendTest func()
	OnOpenLog  func()
	OnQuit     func()
	// SetLastPost is filled by Run: call it to update the "Last post" entry.
	SetLastPost func(string)
}

// Run blocks (it must run on the main goroutine) and calls ready once the tray exists.
func Run(m *Menu, initialLast string, ready func()) {
	systray.Run(func() {
		systray.SetIcon(IconICO())
		systray.SetTitle("NAVTOK")
		systray.SetTooltip("NAVTOK DISCORD - posting your milestones")
		last := systray.AddMenuItem(lastLabel(initialLast), "Most recent Discord post")
		last.Disable()
		systray.AddSeparator()
		test := systray.AddMenuItem("Send test", "Post a test message to the Discord webhook")
		logItem := systray.AddMenuItem("Open log", "Open navtok.log")
		systray.AddSeparator()
		quit := systray.AddMenuItem("Quit", "Stop NAVTOK")
		m.SetLastPost = func(s string) { last.SetTitle(lastLabel(s)) }
		go func() {
			for {
				select {
				case <-test.ClickedCh:
					if m.OnSendTest != nil {
						m.OnSendTest()
					}
				case <-logItem.ClickedCh:
					if m.OnOpenLog != nil {
						m.OnOpenLog()
					}
				case <-quit.ClickedCh:
					if m.OnQuit != nil {
						m.OnQuit()
					}
					systray.Quit()
					return
				}
			}
		}()
		ready()
	}, func() {})
}

func lastLabel(s string) string {
	if s == "" {
		return "Last post: none yet"
	}
	if len(s) > 60 {
		s = s[:57] + "..."
	}
	return "Last post: " + s
}

// Available reports whether a tray exists on this OS.
func Available() bool { return true }
