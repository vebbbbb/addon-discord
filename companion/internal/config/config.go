// Package config holds config.json and the data directory (%LOCALAPPDATA%\NAVTOK).
package config

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"runtime"
)

// DefaultWebhook can be baked into a private guild build:
//
//	go build -ldflags "-X github.com/vebbbbb/addon-discord/companion/internal/config.DefaultWebhook=https://discord.com/api/webhooks/..."
var DefaultWebhook = ""

// UpdateRepo is the GitHub "owner/repo" used by the optional self-update (ldflags too).
var UpdateRepo = "vebbbbb/addon-discord"

// Config is config.json.
type Config struct {
	WebhookURL string `json:"webhook_url"`
	// WoWClients are client folders (e.g. C:\Games\World of Warcraft\_classic_era_); empty = auto detect.
	WoWClients []string `json:"wow_clients"`
	// PlanBBandCapture reads the barcode from the live WoW window instead of screenshots.
	PlanBBandCapture bool `json:"plan_b_band_capture"`
	// BandCorner is the corner the addon draws in (must match /navtok position): top-right ...
	BandCorner string `json:"band_corner"`
	// SelfUpdate enables checking GitHub Releases (the only other host contacted). Off by default.
	SelfUpdate bool `json:"self_update"`
	// DeleteScreenshots removes NAVTOK screenshots after a successful post.
	DeleteScreenshots bool `json:"delete_screenshots_after_post"`
	// LateWindowHours: SavedVariables events older than this are never posted.
	LateWindowHours int `json:"late_window_hours"`
	// MatchToleranceSec: max distance between an event and a screenshot for late matching.
	MatchToleranceSec int `json:"match_tolerance_seconds"`
	MaxImageWidth     int `json:"max_image_width"`
	JPEGQuality       int `json:"jpeg_quality"`
	// BarcodeRemoval: "crop" (cut the rows/columns), "fill" (paint over) or "none".
	BarcodeRemoval string `json:"barcode_removal"`
	// WowheadBase is used for item links.
	WowheadBase string `json:"wowhead_base"`
	// SkipTestEvents: do not post events created with /navtok test.
	SkipTestEvents bool `json:"skip_test_events"`
	// AutoStart registers NAVTOK in HKCU\...\Run.
	AutoStart bool `json:"autostart"`
}

// Defaults returns a config with every default applied.
func Defaults() Config {
	return Config{
		WebhookURL:        DefaultWebhook,
		BandCorner:        "top-right",
		LateWindowHours:   48,
		MatchToleranceSec: 3,
		MaxImageWidth:     1920,
		JPEGQuality:       85,
		BarcodeRemoval:    "crop",
		WowheadBase:       "https://www.wowhead.com/classic",
		AutoStart:         true,
	}
}

func (c *Config) fill() {
	d := Defaults()
	if c.WebhookURL == "" {
		c.WebhookURL = d.WebhookURL
	}
	if c.BandCorner == "" {
		c.BandCorner = d.BandCorner
	}
	if c.LateWindowHours <= 0 {
		c.LateWindowHours = d.LateWindowHours
	}
	if c.MatchToleranceSec <= 0 {
		c.MatchToleranceSec = d.MatchToleranceSec
	}
	if c.MaxImageWidth <= 0 {
		c.MaxImageWidth = d.MaxImageWidth
	}
	if c.JPEGQuality <= 0 || c.JPEGQuality > 100 {
		c.JPEGQuality = d.JPEGQuality
	}
	if c.BarcodeRemoval == "" {
		c.BarcodeRemoval = d.BarcodeRemoval
	}
	if c.WowheadBase == "" {
		c.WowheadBase = d.WowheadBase
	}
}

// Dir returns the data directory: $NAVTOK_HOME, else %LOCALAPPDATA%\NAVTOK (Windows) or the
// user cache dir elsewhere.
func Dir() (string, error) {
	if d := os.Getenv("NAVTOK_HOME"); d != "" {
		return d, os.MkdirAll(d, 0o700)
	}
	base := os.Getenv("LOCALAPPDATA")
	if base == "" || runtime.GOOS != "windows" {
		var err error
		if base, err = os.UserCacheDir(); err != nil {
			return "", err
		}
	}
	d := filepath.Join(base, "NAVTOK")
	return d, os.MkdirAll(d, 0o700)
}

// Load reads config.json from dir (missing file = defaults, exists=false).
func Load(dir string) (cfg Config, exists bool, err error) {
	b, err := os.ReadFile(filepath.Join(dir, "config.json"))
	if errors.Is(err, os.ErrNotExist) {
		return Defaults(), false, nil
	}
	if err != nil {
		return Defaults(), false, err
	}
	cfg = Defaults()
	cfg.AutoStart = false
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(b, &raw); err != nil {
		return Defaults(), true, err
	}
	if _, ok := raw["autostart"]; !ok {
		cfg.AutoStart = true
	}
	if err := json.Unmarshal(b, &cfg); err != nil {
		return Defaults(), true, err
	}
	cfg.fill()
	return cfg, true, nil
}

// Save writes config.json atomically.
func Save(dir string, cfg Config) error {
	b, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return WriteFileAtomic(filepath.Join(dir, "config.json"), append(b, '\n'))
}

// WriteFileAtomic writes via a temp file + rename so readers never see half a file.
func WriteFileAtomic(path string, data []byte) error {
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}
