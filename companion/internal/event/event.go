// Package event is the companion side of the event data contract (see CLAUDE.md).
package event

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
)

// Source says where the companion learned about an event.
type Source string

const (
	FromBarcode   Source = "barcode"   // decoded from a screenshot (real time)
	FromBand      Source = "band"      // plan B: decoded from the live window
	FromSavedVars Source = "savedvars" // fallback: SavedVariables after /reload or logout
)

// Event is one milestone. Data holds the type specific fields as strings.
type Event struct {
	ID   string `json:"id"` // "<ts>.<seq>"
	Type string `json:"type"`
	Test bool   `json:"test"`
	// Candidate: a screenshot kept for a later summary post (dungeon boss kill), never posted itself.
	Candidate bool              `json:"candidate,omitempty"`
	TS        int64             `json:"ts"`
	Seq       int64             `json:"seq"`
	Char      string            `json:"char"`
	Realm     string            `json:"realm,omitempty"`
	Class     string            `json:"class,omitempty"`
	ClassID   int               `json:"classId"`
	Level     int               `json:"level"`
	Shot      int64             `json:"shot,omitempty"` // time() when the screenshot was taken
	Data      map[string]string `json:"data"`

	Source Source `json:"-"`
	Late   bool   `json:"-"`
}

// Key identifies an event for dedupe: "<char>|<ts>.<seq>".
func (e *Event) Key() string { return e.Char + "|" + e.ID }

// CandidateKey names a candidate screenshot: "<char>#<seq>" (seq is unique per character).
func CandidateKey(char string, seq int64) string { return fmt.Sprintf("%s#%d", char, seq) }

// Get returns a data field ("" when missing).
func (e *Event) Get(k string) string { return e.Data[k] }

// Int returns a numeric data field (0 when missing or not a number).
func (e *Event) Int(k string) int {
	v, _ := strconv.Atoi(strings.TrimSpace(e.Data[k]))
	return v
}

// Types lists the known event types in display order.
var Types = []string{"loot", "skill", "level", "reputation", "death", "dungeon", "bg", "legacy", "rare"}

// typeCodes and fields mirror Barcode.lua (TYPE_CODES / FIELDS).
var typeCodes = map[string]string{
	"L": "loot", "S": "skill", "V": "level", "R": "reputation",
	"D": "death", "K": "dungeon", "B": "bg", "G": "legacy", "E": "rare",
}

var fields = map[string][]string{
	"loot":       {"itemId", "quality", "count", "item"},
	"skill":      {"skill", "rank"},
	"level":      {"zone"},
	"reputation": {"faction", "standing"},
	"death":      {"zone", "subzone", "killer"},
	"dungeon":    {"encounterId", "encounter", "instance", "bosses", "duration", "shotSeq"},
	"bg":         {"bg", "result", "duration", "kb", "hk", "deaths", "honor"},
	"legacy":     {"achievementId", "text", "group"},
	"rare":       {"npcId", "classification", "mobLevel", "npc", "zone", "subzone"},
}

// Fields returns the ordered payload fields of a type.
func Fields(t string) []string { return fields[t] }

// CodeOf returns the one-letter barcode code of a type.
func CodeOf(t string) string {
	for c, n := range typeCodes {
		if n == t {
			return c
		}
	}
	return ""
}

const sep = "\x1f"

// ParsePayload decodes a barcode payload (docs/barcode.md "Payload v1").
func ParsePayload(p []byte) (*Event, error) {
	parts := strings.Split(string(p), sep)
	if len(parts) < 7 {
		return nil, fmt.Errorf("payload: %d fields, need at least 7", len(parts))
	}
	t, ok := typeCodes[parts[0]]
	if !ok {
		return nil, fmt.Errorf("payload: unknown type code %q", parts[0])
	}
	ts, err := strconv.ParseInt(parts[2], 10, 64)
	if err != nil {
		return nil, fmt.Errorf("payload: bad ts %q", parts[2])
	}
	seq, err := strconv.ParseInt(parts[3], 10, 64)
	if err != nil {
		return nil, fmt.Errorf("payload: bad seq %q", parts[3])
	}
	classID, _ := strconv.Atoi(parts[5])
	level, _ := strconv.Atoi(parts[6])
	e := &Event{
		Type: t, Test: strings.Contains(parts[1], "T"), Candidate: strings.Contains(parts[1], "C"), TS: ts, Seq: seq,
		ID: fmt.Sprintf("%d.%d", ts, seq), Char: parts[4], ClassID: classID, Level: level,
		Class: ClassToken(classID), Data: map[string]string{}, Source: FromBarcode,
	}
	for i, name := range fields[t] {
		if 7+i < len(parts) && parts[7+i] != "" {
			e.Data[name] = parts[7+i]
		}
	}
	return e, nil
}

// EncodePayload builds a payload the way the addon does (no truncation; used by tests/test posts).
func EncodePayload(e *Event) []byte {
	flags := ""
	if e.Test {
		flags = "T"
	}
	if e.Candidate {
		flags += "C"
	}
	parts := []string{CodeOf(e.Type), flags, strconv.FormatInt(e.TS, 10), strconv.FormatInt(e.Seq, 10),
		e.Char, strconv.Itoa(e.ClassID), strconv.Itoa(e.Level)}
	for _, f := range fields[e.Type] {
		parts = append(parts, e.Data[f])
	}
	return []byte(strings.Join(parts, sep))
}

// rawJSON is the SavedVariables JSON line written by Core.lua.
type rawJSON struct {
	ID        string         `json:"id"`
	Type      string         `json:"type"`
	Test      bool           `json:"test"`
	Candidate bool           `json:"candidate"`
	TS        int64          `json:"ts"`
	Seq       int64          `json:"seq"`
	Char      string         `json:"char"`
	Realm     string         `json:"realm"`
	Class     string         `json:"class"`
	ClassID   int            `json:"classId"`
	Level     int            `json:"level"`
	Shot      int64          `json:"shot"`
	Data      map[string]any `json:"data"`
}

// ParseJSON decodes one SavedVariables event line.
func ParseJSON(line string) (*Event, error) {
	var r rawJSON
	if err := json.Unmarshal([]byte(line), &r); err != nil {
		return nil, err
	}
	if r.Type == "" || r.TS == 0 {
		return nil, fmt.Errorf("event json: missing type/ts")
	}
	if r.ID == "" {
		r.ID = fmt.Sprintf("%d.%d", r.TS, r.Seq)
	}
	e := &Event{ID: r.ID, Type: r.Type, Test: r.Test, Candidate: r.Candidate, TS: r.TS, Seq: r.Seq, Char: r.Char, Realm: r.Realm,
		Class: r.Class, ClassID: r.ClassID, Level: r.Level, Shot: r.Shot, Data: map[string]string{},
		Source: FromSavedVars}
	if e.Class == "" {
		e.Class = ClassToken(e.ClassID)
	}
	for k, v := range r.Data {
		switch x := v.(type) {
		case string:
			e.Data[k] = x
		case float64:
			e.Data[k] = strconv.FormatFloat(x, 'f', -1, 64)
		case bool:
			e.Data[k] = strconv.FormatBool(x)
		case nil:
		default:
			b, _ := json.Marshal(x)
			e.Data[k] = string(b)
		}
	}
	return e, nil
}

var classTokens = map[int]string{
	1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST", 6: "DEATHKNIGHT",
	7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 10: "MONK", 11: "DRUID",
}

// ClassToken maps a class id to its file token ("" if unknown).
func ClassToken(id int) string { return classTokens[id] }
