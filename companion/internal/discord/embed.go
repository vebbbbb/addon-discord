// Package discord builds webhook messages and posts them (429-aware, retrying, ordered queue).
package discord

import (
	"fmt"
	"strings"
	"time"

	"github.com/vebbbbb/addon-discord/companion/internal/event"
)

// Message is the webhook JSON body (payload_json).
type Message struct {
	Username        string           `json:"username,omitempty"`
	Content         string           `json:"content,omitempty"`
	Embeds          []Embed          `json:"embeds,omitempty"`
	AllowedMentions *AllowedMentions `json:"allowed_mentions,omitempty"`
	Attachments     []Attachment     `json:"attachments,omitempty"`
}

// AllowedMentions with an empty Parse list disables @everyone/@here/role pings from game text.
type AllowedMentions struct {
	Parse []string `json:"parse"`
}

type Attachment struct {
	ID       int    `json:"id"`
	Filename string `json:"filename"`
}

type Embed struct {
	Title       string       `json:"title,omitempty"`
	URL         string       `json:"url,omitempty"`
	Description string       `json:"description,omitempty"`
	Color       int          `json:"color,omitempty"`
	Timestamp   string       `json:"timestamp,omitempty"`
	Author      *EmbedAuthor `json:"author,omitempty"`
	Fields      []EmbedField `json:"fields,omitempty"`
	Image       *EmbedImage  `json:"image,omitempty"`
	Footer      *EmbedFooter `json:"footer,omitempty"`
}

type EmbedAuthor struct {
	Name string `json:"name"`
}
type EmbedField struct {
	Name   string `json:"name"`
	Value  string `json:"value"`
	Inline bool   `json:"inline,omitempty"`
}
type EmbedImage struct {
	URL string `json:"url"`
}
type EmbedFooter struct {
	Text string `json:"text"`
}

// ImageName is the attachment file name referenced by the embed.
const ImageName = "screenshot.jpg"

// ClassColors are the classic RAID_CLASS_COLORS.
var ClassColors = map[string]int{
	"WARRIOR": 0xC79C6E, "PALADIN": 0xF58CBA, "HUNTER": 0xABD473, "ROGUE": 0xFFF569,
	"PRIEST": 0xFFFFFF, "DEATHKNIGHT": 0xC41F3B, "SHAMAN": 0x0070DE, "MAGE": 0x69CCF0,
	"WARLOCK": 0x9482C9, "MONK": 0x00FF96, "DRUID": 0xFF7D0A,
}

// QualityColors are the item quality colours (0 poor ... 7 heirloom).
var QualityColors = map[int]int{
	0: 0x9D9D9D, 1: 0xFFFFFF, 2: 0x1EFF00, 3: 0x0070DD, 4: 0xA335EE, 5: 0xFF8000, 6: 0xE6CC80, 7: 0x00CCFF,
}

var qualityNames = map[int]string{4: "Epic", 5: "Legendary", 6: "Artifact", 3: "Rare", 2: "Uncommon"}

// Standings are the reputation labels by standingID.
var Standings = map[int]string{
	1: "Hated", 2: "Hostile", 3: "Unfriendly", 4: "Neutral", 5: "Friendly", 6: "Honored", 7: "Revered", 8: "Exalted",
}

var standingColors = map[int]int{5: 0x2ECC71, 6: 0x1ABC9C, 7: 0x3498DB, 8: 0xF1C40F}

const (
	colorWin     = 0x2ECC71
	colorLoss    = 0xE74C3C
	colorNeutral = 0x95A5A6
	colorDungeon = 0x9B59B6
	colorSkill   = 0xE67E22
	colorLegacy  = 0xF1C40F
	// rare / rare elite (silver dragon, gold dragon portraits)
	colorRare      = 0xC0C0C0
	colorRareElite = 0xE5B53A
)

// Options influence message building.
type Options struct {
	WowheadBase string
	HasImage    bool
}

func classColor(e *event.Event) int {
	if c, ok := ClassColors[e.Class]; ok {
		return c
	}
	return colorNeutral
}

func titleCase(s string) string {
	if s == "" {
		return s
	}
	return strings.ToUpper(s[:1]) + s[1:]
}

// mdEscape keeps game text from being interpreted as Discord markdown.
func mdEscape(s string) string {
	r := strings.NewReplacer(`\`, `\\`, "*", `\*`, "_", `\_`, "~", `\~`, "`", "\\`", "|", `\|`, ">", `\>`)
	return r.Replace(s)
}

func fmtDuration(sec int) string {
	d := time.Duration(sec) * time.Second
	if d >= time.Hour {
		return fmt.Sprintf("%dh %02dm", int(d.Hours()), int(d.Minutes())%60)
	}
	return fmt.Sprintf("%dm %02ds", int(d.Minutes()), int(d.Seconds())%60)
}

// Summary is a one-line description (tray "Last post", log).
func Summary(e *event.Event) string {
	m := Build(e, Options{})
	if len(m.Embeds) == 0 {
		return e.Type
	}
	return e.Char + ": " + m.Embeds[0].Title
}

// Build creates the webhook message for an event.
func Build(e *event.Event, o Options) Message {
	em := Embed{Color: colorNeutral}
	wowhead := strings.TrimRight(o.WowheadBase, "/")
	switch e.Type {
	case "loot":
		q := e.Int("quality")
		item := e.Get("item")
		if item == "" {
			item = "item " + e.Get("itemId")
		}
		em.Title = "Looted [" + item + "]"
		if c := e.Int("count"); c > 1 {
			em.Title += fmt.Sprintf(" x%d", c)
		}
		if id := e.Get("itemId"); id != "" && id != "0" && wowhead != "" {
			em.URL = wowhead + "/item=" + id
		}
		if c, ok := QualityColors[q]; ok {
			em.Color = c
		}
		if n, ok := qualityNames[q]; ok {
			em.Description = n + " item"
		}
	case "skill":
		em.Title = fmt.Sprintf("%s skill %d", e.Get("skill"), e.Int("rank"))
		em.Description = fmt.Sprintf("Reached **%d** in %s", e.Int("rank"), mdEscape(e.Get("skill")))
		em.Color = colorSkill
	case "level":
		em.Title = fmt.Sprintf("Reached level %d!", e.Level)
		if z := e.Get("zone"); z != "" {
			em.Description = "in " + mdEscape(z)
		}
		em.Color = classColor(e)
	case "reputation":
		st := e.Int("standing")
		label := Standings[st]
		if label == "" {
			label = fmt.Sprintf("standing %d", st)
		}
		em.Title = fmt.Sprintf("Now %s with %s", label, e.Get("faction"))
		if c, ok := standingColors[st]; ok {
			em.Color = c
		}
	case "death":
		where := e.Get("zone")
		if sz := e.Get("subzone"); sz != "" && sz != where {
			if where != "" {
				where = sz + ", " + where
			} else {
				where = sz
			}
		}
		em.Title = "Died"
		if where != "" {
			em.Title += " in " + where
		}
		if k := e.Get("killer"); k != "" {
			em.Description = "Killed by **" + mdEscape(k) + "**"
		}
		em.Color = classColor(e)
	case "dungeon":
		boss, inst := e.Get("encounter"), e.Get("instance")
		em.Title = "Defeated " + boss
		if inst != "" {
			em.Title += " - " + inst
		}
		em.Description = "Dungeon cleared!"
		em.Color = colorDungeon
	case "bg":
		bg := e.Get("bg")
		switch e.Get("result") {
		case "win":
			em.Title, em.Color = "Victory in "+bg, colorWin
		case "loss":
			em.Title, em.Color = "Defeat in "+bg, colorLoss
		default:
			em.Title = "Draw in " + bg
		}
		add := func(name, key string) {
			if v := e.Get(key); v != "" {
				em.Fields = append(em.Fields, EmbedField{Name: name, Value: v, Inline: true})
			}
		}
		add("Killing blows", "kb")
		add("Honorable kills", "hk")
		add("Deaths", "deaths")
		add("Honor", "honor")
		if d := e.Int("duration"); d > 0 {
			em.Fields = append(em.Fields, EmbedField{Name: "Duration", Value: fmtDuration(d), Inline: true})
		}
	case "legacy":
		em.Title = "Legacy challenge: " + e.Get("text")
		if g := e.Get("group"); g != "" {
			em.Description = mdEscape(g)
		}
		if id := e.Get("achievementId"); id != "" && id != "0" && wowhead != "" {
			em.URL = wowhead + "/achievement=" + id
		}
		em.Color = colorLegacy
	case "rare":
		npc := e.Get("npc")
		em.Title = "Killed " + npc
		kind := "Rare"
		switch e.Get("classification") {
		case "rareelite":
			kind = "Rare Elite"
			em.Color = colorRareElite
		case "worldboss":
			kind = "World Boss"
			em.Color = colorDungeon
		default:
			em.Color = colorRare
		}
		if lvl := e.Int("mobLevel"); lvl > 0 {
			kind += fmt.Sprintf(", level %d", lvl)
		}
		where := e.Get("subzone")
		if z := e.Get("zone"); z != "" && z != where {
			if where != "" {
				where += ", " + z
			} else {
				where = z
			}
		}
		em.Description = kind
		if where != "" {
			em.Description += " - " + mdEscape(where)
		}
		if id := e.Get("npcId"); id != "" && id != "0" && wowhead != "" {
			em.URL = wowhead + "/npc=" + id
		}
	case "test":
		em.Title = "NAVTOK is connected"
		em.Description = "If you can read this, milestones from WoW Forever will show up here."
		em.Color = colorWin
	default:
		em.Title = titleCase(e.Type)
	}
	if e.Test && e.Type != "test" {
		em.Title = "[TEST] " + em.Title
	}
	if e.Late {
		em.Title += " (late)"
	}
	if len(em.Title) > 256 {
		em.Title = em.Title[:253] + "..."
	}
	author := e.Char
	if e.Realm != "" {
		author += " - " + e.Realm
	}
	if e.Level > 0 && e.Type != "level" {
		author += fmt.Sprintf(" (%d)", e.Level)
	}
	em.Author = &EmbedAuthor{Name: author}
	em.Timestamp = time.Unix(e.TS, 0).UTC().Format(time.RFC3339)
	em.Footer = &EmbedFooter{Text: "NAVTOK DISCORD"}
	msg := Message{Embeds: []Embed{em}, AllowedMentions: &AllowedMentions{Parse: []string{}}}
	if o.HasImage {
		msg.Embeds[0].Image = &EmbedImage{URL: "attachment://" + ImageName}
		msg.Attachments = []Attachment{{ID: 0, Filename: ImageName}}
	}
	return msg
}
