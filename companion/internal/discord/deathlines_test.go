package discord

import (
	"strings"
	"testing"
)

func TestEmbeddedDeathLines(t *testing.T) {
	l := embeddedDeathLines()
	for _, k := range []string{"3", "5", "7", "10", "15", "20", "25"} {
		if len(l[k]) == 0 {
			t.Errorf("pool %s missing", k)
		}
	}
	if !strings.Contains(l["5"][0], "{name}") {
		t.Fatalf("unexpected first 5-line %q", l["5"][0])
	}
}

func TestDeathLineRendering(t *testing.T) {
	e := ev("death", map[string]string{"zone": "Stranglethorn Vale", "session": "5", "line": "5:6"})
	if got := DeathLine(e); got != "Navtok died again in Stranglethorn Vale. Maybe try a different zone. Or game." {
		t.Fatalf("%q", got)
	}
	e.Data["line"] = "10:1"
	e.Data["session"] = "12"
	if got := DeathLine(e); got != "💀 12 deaths this session! Navtok, it might be time for a break." {
		t.Fatalf("%q", got)
	}
	m := Build(e, Options{}).Embeds[0]
	if !strings.Contains(m.Description, "*💀 12 deaths this session! Navtok, it might be time for a break.*") {
		t.Fatalf("%q", m.Description)
	}
	for _, bad := range []string{"", "x", "10:99", "99:1", "10:0"} {
		e.Data["line"] = bad
		if DeathLine(e) != "" {
			t.Errorf("line %q rendered", bad)
		}
	}
}
