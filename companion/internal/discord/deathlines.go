package discord

import (
	"io/fs"
	"strconv"
	"strings"
	"sync"

	navtok "github.com/vebbbbb/addon-discord"
	"github.com/vebbbbb/addon-discord/companion/internal/event"
	"github.com/vebbbbb/addon-discord/companion/internal/savedvars"
)

// The death flavour lines live in the addon (Data/DeathLines.lua, plain data). The barcode only
// carries "<pool>:<index>"; the text comes from the copy of that file embedded in NAVTOK.exe.
var (
	deathLinesOnce sync.Once
	deathLines     map[string][]string // "3", "5", "7", "10", ... -> lines
)

// LoadDeathLines parses Data/DeathLines.lua source.
func LoadDeathLines(src string) (map[string][]string, error) {
	g, err := savedvars.Parse(src)
	if err != nil {
		return nil, err
	}
	out := map[string][]string{}
	root, _ := g["NavtokDeathLines"].(*savedvars.Table)
	for _, section := range []string{"exact", "from"} {
		t := root.Sub(section)
		if t == nil {
			continue
		}
		for k, v := range t.Map {
			pool, _ := v.(*savedvars.Table)
			if pool == nil {
				continue
			}
			for _, l := range pool.List {
				if s, ok := l.(string); ok {
					out[k] = append(out[k], s)
				}
			}
		}
	}
	return out, nil
}

func embeddedDeathLines() map[string][]string {
	deathLinesOnce.Do(func() {
		b, err := fs.ReadFile(navtok.AddonFS, navtok.AddonRoot+"/Data/DeathLines.lua")
		if err == nil {
			deathLines, _ = LoadDeathLines(string(b))
		}
	})
	return deathLines
}

// DeathLine renders the flavour line of a death event ("" when there is none).
func DeathLine(e *event.Event) string {
	return deathLineFrom(embeddedDeathLines(), e)
}

func deathLineFrom(lines map[string][]string, e *event.Event) string {
	pool, idxS, ok := strings.Cut(e.Get("line"), ":")
	if !ok {
		return ""
	}
	idx, err := strconv.Atoi(idxS)
	if err != nil || idx < 1 || idx > len(lines[pool]) {
		return ""
	}
	r := strings.NewReplacer("{name}", e.Char, "{n}", e.Get("session"), "{zone}", e.Get("zone"))
	return r.Replace(lines[pool][idx-1])
}
