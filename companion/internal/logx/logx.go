// Package logx is a size-capped log file (navtok.log): when it grows past Max bytes the oldest
// half is dropped, so it never needs a second file.
package logx

import (
	"fmt"
	"io"
	"log"
	"os"
	"sync"
	"time"
)

// Max is the size cap of the log file.
var Max int64 = 1 << 20

// Capped is an io.Writer to a capped file.
type Capped struct {
	mu   sync.Mutex
	path string
	f    *os.File
	size int64
	also io.Writer
}

// Open opens (appends to) path. also receives a copy of every line (may be nil).
func Open(path string, also io.Writer) (*Capped, error) {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return nil, err
	}
	st, _ := f.Stat()
	c := &Capped{path: path, f: f, also: also}
	if st != nil {
		c.size = st.Size()
	}
	return c, nil
}

func (c *Capped) Write(p []byte) (int, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.also != nil {
		_, _ = c.also.Write(p)
	}
	if c.size+int64(len(p)) > Max {
		c.shrink()
	}
	n, err := c.f.Write(p)
	c.size += int64(n)
	return n, err
}

// shrink keeps the newest half of the file.
func (c *Capped) shrink() {
	c.f.Close()
	b, err := os.ReadFile(c.path)
	if err == nil && int64(len(b)) > Max/2 {
		b = b[int64(len(b))-Max/2:]
		for i, ch := range b { // start at a line boundary
			if ch == '\n' {
				b = b[i+1:]
				break
			}
		}
		_ = os.WriteFile(c.path, b, 0o600)
	}
	c.f, _ = os.OpenFile(c.path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	st, _ := c.f.Stat()
	c.size = 0
	if st != nil {
		c.size = st.Size()
	}
}

// Close closes the file.
func (c *Capped) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.f.Close()
}

// Logger is the program wide logger (stderr until Init is called).
var Logger = log.New(os.Stderr, "", log.LstdFlags)

// Init points Logger at w.
func Init(w io.Writer) { Logger = log.New(w, "", log.LstdFlags) }

// Printf logs a line.
func Printf(format string, a ...any) { Logger.Output(2, fmt.Sprintf(format, a...)) }

// Since formats a duration for log lines.
func Since(t time.Time) string { return time.Since(t).Round(time.Millisecond).String() }
