// Package savedvars reads WoW SavedVariables files (a restricted Lua table literal syntax) and
// extracts the NavtokDiscordDB event ring buffers.
package savedvars

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"

	"github.com/vebbbbb/addon-discord/companion/internal/event"
)

// Table is a Lua table: positional values in List, everything else in Map (keys as strings).
type Table struct {
	List []any
	Map  map[string]any
}

// Get returns Map[k] or nil.
func (t *Table) Get(k string) any {
	if t == nil {
		return nil
	}
	return t.Map[k]
}

// Sub returns the sub table Map[k] or nil.
func (t *Table) Sub(k string) *Table {
	v, _ := t.Get(k).(*Table)
	return v
}

// ParseFile parses a SavedVariables file into its global assignments.
func ParseFile(path string) (map[string]any, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return Parse(string(b))
}

// Parse parses "Name = value" statements.
func Parse(src string) (map[string]any, error) {
	p := &parser{s: src}
	out := map[string]any{}
	for {
		p.skip()
		if p.eof() {
			return out, nil
		}
		name := p.ident()
		if name == "" {
			return nil, p.errf("expected identifier")
		}
		p.skip()
		if !p.consume('=') {
			return nil, p.errf("expected '='")
		}
		v, err := p.value(0)
		if err != nil {
			return nil, err
		}
		out[name] = v
		p.skip()
		p.consume(';')
	}
}

type parser struct {
	s   string
	pos int
}

func (p *parser) eof() bool { return p.pos >= len(p.s) }

func (p *parser) errf(f string, a ...any) error {
	line := strings.Count(p.s[:min(p.pos, len(p.s))], "\n") + 1
	return fmt.Errorf("savedvars: line %d: %s", line, fmt.Sprintf(f, a...))
}

func (p *parser) skip() {
	for !p.eof() {
		c := p.s[p.pos]
		switch {
		case c == ' ' || c == '\t' || c == '\r' || c == '\n':
			p.pos++
		case strings.HasPrefix(p.s[p.pos:], "--[["):
			end := strings.Index(p.s[p.pos:], "]]")
			if end < 0 {
				p.pos = len(p.s)
			} else {
				p.pos += end + 2
			}
		case strings.HasPrefix(p.s[p.pos:], "--"):
			end := strings.IndexByte(p.s[p.pos:], '\n')
			if end < 0 {
				p.pos = len(p.s)
			} else {
				p.pos += end + 1
			}
		default:
			return
		}
	}
}

func (p *parser) consume(c byte) bool {
	if !p.eof() && p.s[p.pos] == c {
		p.pos++
		return true
	}
	return false
}

func isIdent(c byte, first bool) bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (!first && c >= '0' && c <= '9')
}

func (p *parser) ident() string {
	start := p.pos
	for !p.eof() && isIdent(p.s[p.pos], p.pos == start) {
		p.pos++
	}
	return p.s[start:p.pos]
}

func (p *parser) value(depth int) (any, error) {
	if depth > 64 {
		return nil, p.errf("nesting too deep")
	}
	p.skip()
	if p.eof() {
		return nil, p.errf("unexpected end of file")
	}
	c := p.s[p.pos]
	switch {
	case c == '{':
		return p.table(depth)
	case c == '"' || c == '\'':
		return p.str()
	case c == '-' || c == '.' || (c >= '0' && c <= '9'):
		return p.number()
	case isIdent(c, true):
		id := p.ident()
		switch id {
		case "true":
			return true, nil
		case "false":
			return false, nil
		case "nil":
			return nil, nil
		}
		return nil, p.errf("unexpected identifier %q", id)
	}
	return nil, p.errf("unexpected %q", c)
}

func (p *parser) number() (any, error) {
	start := p.pos
	for !p.eof() && strings.IndexByte("+-.0123456789eExXabcdefABCDEF", p.s[p.pos]) >= 0 {
		p.pos++
	}
	txt := p.s[start:p.pos]
	if strings.HasPrefix(txt, "0x") || strings.HasPrefix(txt, "0X") {
		v, err := strconv.ParseInt(txt[2:], 16, 64)
		return float64(v), err
	}
	v, err := strconv.ParseFloat(txt, 64)
	if err != nil {
		return nil, p.errf("bad number %q", txt)
	}
	return v, nil
}

func (p *parser) str() (any, error) {
	q := p.s[p.pos]
	p.pos++
	var b strings.Builder
	for {
		if p.eof() {
			return nil, p.errf("unterminated string")
		}
		c := p.s[p.pos]
		p.pos++
		if c == q {
			return b.String(), nil
		}
		if c != '\\' {
			b.WriteByte(c)
			continue
		}
		if p.eof() {
			return nil, p.errf("bad escape")
		}
		e := p.s[p.pos]
		p.pos++
		switch e {
		case 'n':
			b.WriteByte('\n')
		case 't':
			b.WriteByte('\t')
		case 'r':
			b.WriteByte('\r')
		case 'a':
			b.WriteByte('\a')
		case 'b':
			b.WriteByte('\b')
		case 'f':
			b.WriteByte('\f')
		case 'v':
			b.WriteByte('\v')
		case '\n':
			b.WriteByte('\n')
		case '\\', '"', '\'':
			b.WriteByte(e)
		default:
			if e >= '0' && e <= '9' {
				n := int(e - '0')
				for i := 0; i < 2 && !p.eof() && p.s[p.pos] >= '0' && p.s[p.pos] <= '9'; i++ {
					n = n*10 + int(p.s[p.pos]-'0')
					p.pos++
				}
				if n > 255 {
					return nil, p.errf("bad decimal escape")
				}
				b.WriteByte(byte(n))
			} else {
				b.WriteByte(e)
			}
		}
	}
}

func keyString(k any) string {
	switch v := k.(type) {
	case string:
		return v
	case float64:
		return strconv.FormatFloat(v, 'f', -1, 64)
	case bool:
		return strconv.FormatBool(v)
	}
	return fmt.Sprint(k)
}

func (p *parser) table(depth int) (any, error) {
	p.pos++ // {
	t := &Table{Map: map[string]any{}}
	for {
		p.skip()
		if p.consume('}') {
			return t, nil
		}
		var key any
		hasKey := false
		if p.consume('[') {
			k, err := p.value(depth + 1)
			if err != nil {
				return nil, err
			}
			p.skip()
			if !p.consume(']') {
				return nil, p.errf("expected ']'")
			}
			p.skip()
			if !p.consume('=') {
				return nil, p.errf("expected '='")
			}
			key, hasKey = k, true
		} else if !p.eof() && isIdent(p.s[p.pos], true) {
			save := p.pos
			id := p.ident()
			p.skip()
			if p.consume('=') && id != "true" && id != "false" && id != "nil" {
				key, hasKey = id, true
			} else {
				p.pos = save
			}
		}
		v, err := p.value(depth + 1)
		if err != nil {
			return nil, err
		}
		if hasKey {
			if f, ok := key.(float64); ok && f == float64(len(t.List)+1) {
				t.List = append(t.List, v)
			} else {
				t.Map[keyString(key)] = v
			}
		} else {
			t.List = append(t.List, v)
		}
		p.skip()
		if !p.consume(',') && !p.consume(';') {
			p.skip()
			if p.consume('}') {
				return t, nil
			}
			return nil, p.errf("expected ',' or '}'")
		}
	}
}

// CharEvents are the events of one character key ("Name-Realm").
type CharEvents struct {
	Key    string
	Realm  string
	Events []*event.Event
}

// Events extracts every event line from NavtokDiscordDB.chars[*].events. Bad lines are skipped
// and counted.
func Events(globals map[string]any) (chars []CharEvents, bad int) {
	db, _ := globals["NavtokDiscordDB"].(*Table)
	all := db.Sub("chars")
	if all == nil {
		return nil, 0
	}
	keys := make([]string, 0, len(all.Map))
	for k := range all.Map {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		c, _ := all.Map[k].(*Table)
		evs := c.Sub("events")
		if evs == nil {
			continue
		}
		realm, _ := c.Get("realm").(string)
		ce := CharEvents{Key: k, Realm: realm}
		for _, v := range evs.List {
			s, ok := v.(string)
			if !ok {
				bad++
				continue
			}
			e, err := event.ParseJSON(s)
			if err != nil {
				bad++
				continue
			}
			if e.Realm == "" {
				e.Realm = realm
			}
			ce.Events = append(ce.Events, e)
		}
		chars = append(chars, ce)
	}
	return chars, bad
}

// Settings returns NavtokDiscordDB.settings (or nil).
func Settings(globals map[string]any) *Table {
	db, _ := globals["NavtokDiscordDB"].(*Table)
	return db.Sub("settings")
}
