// Package platform wraps the few OS specific things: autostart, single instance, dialogs,
// opening files. Windows is the real target; other systems get no-op/console fallbacks so the
// companion can be developed and tested on Linux.
package platform

// AppName is used for the Run key value, mutex and dialog titles.
const AppName = "NAVTOK"
