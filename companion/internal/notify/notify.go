// Package notify shows a Windows notification once per problem, until the problem is resolved.
package notify

import (
	"sync"

	"github.com/vebbbbb/addon-discord/companion/internal/logx"
)

// Problems tracks active problems.
type Problems struct {
	mu     sync.Mutex
	active map[string]bool
	Show   func(title, msg string)
}

// New creates a tracker that shows notifications with show.
func New(show func(title, msg string)) *Problems {
	return &Problems{active: map[string]bool{}, Show: show}
}

// Report notifies about a problem unless it is already active. Returns true if shown.
func (p *Problems) Report(key, msg string) bool {
	p.mu.Lock()
	if p.active[key] {
		p.mu.Unlock()
		return false
	}
	p.active[key] = true
	p.mu.Unlock()
	logx.Printf("problem [%s]: %s", key, msg)
	if p.Show != nil {
		p.Show("NAVTOK", msg)
	}
	return true
}

// Resolve clears a problem so it can be reported again later.
func (p *Problems) Resolve(key string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.active[key] {
		logx.Printf("problem [%s] resolved", key)
	}
	delete(p.active, key)
}

// Active reports whether a problem is active.
func (p *Problems) Active(key string) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.active[key]
}
