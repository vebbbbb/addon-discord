package savedvars

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

const sample = `
NavtokDiscordDB = {
	["version"] = 1,
	["settings"] = {
		["position"] = "TOPRIGHT",
		["hideChat"] = true,
		["skillMilestones"] = {
			75, -- [1]
			150, -- [2]
		},
		["neg"] = -1.5,
	},
	["chars"] = {
		["Testchar-Testrealm"] = {
			["realm"] = "Testrealm",
			["events"] = {
				"{\"char\":\"Testchar\",\"classId\":1,\"data\":{\"item\":\"A \\\"quoted\\\" \\\\ item\",\"itemId\":19019},\"id\":\"1764160003.1\",\"level\":20,\"seq\":1,\"test\":false,\"ts\":1764160003,\"type\":\"loot\"}", -- [1]
				"not json", -- [2]
				"{\"char\":\"Testchar\",\"classId\":1,\"data\":{},\"id\":\"1764160009.2\",\"level\":21,\"seq\":2,\"test\":true,\"ts\":1764160009,\"type\":\"level\"}", -- [3]
			},
			["rep"] = { ["72"] = 5, [7] = 1 },
		},
	},
	["probe"] = {
	},
}
OtherGlobal = nil
`

func TestParseSample(t *testing.T) {
	g, err := Parse(sample)
	if err != nil {
		t.Fatal(err)
	}
	s := Settings(g)
	if s.Get("position") != "TOPRIGHT" || s.Get("hideChat") != true || s.Get("neg") != -1.5 {
		t.Fatalf("settings %+v", s.Map)
	}
	if ms := s.Sub("skillMilestones"); len(ms.List) != 2 || ms.List[1] != 150.0 {
		t.Fatalf("milestones %+v", ms)
	}
	chars, bad := Events(g)
	if bad != 1 || len(chars) != 1 || len(chars[0].Events) != 2 {
		t.Fatalf("chars %+v bad %d", chars, bad)
	}
	e := chars[0].Events[0]
	if e.Get("item") != `A "quoted" \ item` || e.Realm != "Testrealm" || e.Key() != "Testchar|1764160003.1" {
		t.Fatalf("%+v", e)
	}
	if !chars[0].Events[1].Test {
		t.Fatal("test flag")
	}
}

func TestParseErrors(t *testing.T) {
	for _, src := range []string{"X = {", "X = \"abc", "= 1", "X = { [1] 2 }", "X = @"} {
		if _, err := Parse(src); err == nil {
			t.Errorf("accepted %q", src)
		}
	}
}

func TestDecimalEscapesAndUTF8(t *testing.T) {
	g, err := Parse("A = \"Navt\\195\\182k\"\nB = 'x\\'y'")
	if err != nil {
		t.Fatal(err)
	}
	if g["A"] != "Navtök" || g["B"] != "x'y" {
		t.Fatalf("%q %q", g["A"], g["B"])
	}
}

// TestRealAddonOutput runs the Lua addon in the stub world, serialises NavtokDiscordDB like WoW
// does and parses it back (skipped when luajit is not installed).
func TestRealAddonOutput(t *testing.T) {
	lj, err := exec.LookPath("luajit")
	if err != nil {
		t.Skip("luajit not installed")
	}
	script := filepath.Join("..", "..", "..", "addon", "tests", "dump_savedvars.lua")
	out, err := exec.Command(lj, script).Output()
	if err != nil {
		t.Fatalf("luajit: %v", err)
	}
	tmp := filepath.Join(t.TempDir(), "NavtokDiscord.lua")
	if err := os.WriteFile(tmp, out, 0o644); err != nil {
		t.Fatal(err)
	}
	g, err := ParseFile(tmp)
	if err != nil {
		t.Fatalf("%v\n%s", err, out)
	}
	chars, bad := Events(g)
	if bad != 0 || len(chars) != 1 {
		t.Fatalf("bad=%d chars=%d", bad, len(chars))
	}
	types := map[string]bool{}
	for _, e := range chars[0].Events {
		types[e.Type] = true
		if !e.Test || e.Char != "Testchar" || e.Realm != "Testrealm" {
			t.Errorf("event %+v", e)
		}
	}
	for _, typ := range []string{"loot", "skill", "level", "reputation", "death", "dungeon", "bg", "legacy"} {
		if !types[typ] {
			t.Errorf("missing %s", typ)
		}
	}
}
