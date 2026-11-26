package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadSaveDefaults(t *testing.T) {
	dir := t.TempDir()
	c, exists, err := Load(dir)
	if err != nil || exists {
		t.Fatal(err, exists)
	}
	if c.MaxImageWidth != 1920 || c.JPEGQuality != 85 || c.MatchToleranceSec != 3 || !c.AutoStart || c.SelfUpdate || c.PlanBBandCapture {
		t.Fatalf("defaults %+v", c)
	}
	c.WebhookURL = "https://discord.com/api/webhooks/1/x"
	c.AutoStart = false
	if err := Save(dir, c); err != nil {
		t.Fatal(err)
	}
	c2, exists, err := Load(dir)
	if err != nil || !exists || c2.WebhookURL != c.WebhookURL || c2.AutoStart {
		t.Fatalf("%+v %v %v", c2, exists, err)
	}
}

func TestPartialConfigGetsDefaults(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "config.json"), []byte(`{"webhook_url":"x","jpeg_quality":0}`), 0o600)
	c, _, err := Load(dir)
	if err != nil || c.JPEGQuality != 85 || c.BarcodeRemoval != "crop" || !c.AutoStart {
		t.Fatalf("%+v %v", c, err)
	}
}

func TestDirOverride(t *testing.T) {
	d := filepath.Join(t.TempDir(), "x")
	t.Setenv("NAVTOK_HOME", d)
	got, err := Dir()
	if err != nil || got != d {
		t.Fatal(got, err)
	}
}
