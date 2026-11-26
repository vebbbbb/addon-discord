package setup

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/navtok/navtok-discord/companion/internal/config"
	"github.com/navtok/navtok-discord/companion/internal/discord"
)

type fakeUI struct {
	answers []string
	picks   []string
	errors  []string
	asked   int
}

func (f *fakeUI) AskWebhook(string) (string, bool) {
	f.asked++
	if len(f.answers) == 0 {
		return "", false
	}
	a := f.answers[0]
	f.answers = f.answers[1:]
	return a, true
}
func (f *fakeUI) ShowError(m string) { f.errors = append(f.errors, m) }
func (f *fakeUI) PickFolder(string) (string, bool) {
	if len(f.picks) == 0 {
		return "", false
	}
	p := f.picks[0]
	f.picks = f.picks[1:]
	return p, true
}
func (f *fakeUI) PickFromList(_ string, items []string) (string, bool) {
	if len(f.picks) == 0 {
		return "", false
	}
	return f.picks[0], true
}

const good = "https://discord.com/api/webhooks/123/abc"

func TestWebhookAsksUntilValid(t *testing.T) {
	cfg := config.Defaults()
	ui := &fakeUI{answers: []string{"nonsense", "https://discord.com/api/webhooks/1/deleted", good}}
	v := func(_ context.Context, u string) error {
		if u == good {
			return nil
		}
		return &discord.PermanentError{Status: 404, Body: "Unknown Webhook"}
	}
	if err := Webhook(context.Background(), &cfg, ui, v, false); err != nil {
		t.Fatal(err)
	}
	if cfg.WebhookURL != good || len(ui.errors) != 2 {
		t.Fatalf("%q %v", cfg.WebhookURL, ui.errors)
	}
}

func TestWebhookBuildDefaultMeansNoQuestion(t *testing.T) {
	cfg := config.Defaults()
	cfg.WebhookURL = good
	ui := &fakeUI{}
	if err := Webhook(context.Background(), &cfg, ui, nil, false); err != nil || ui.asked != 0 {
		t.Fatal(err, ui.asked)
	}
}

func TestWebhookOfflineAccepted(t *testing.T) {
	cfg := config.Defaults()
	ui := &fakeUI{answers: []string{good}}
	if err := Webhook(context.Background(), &cfg, ui, func(context.Context, string) error { return errors.New("offline") }, false); err != nil || cfg.WebhookURL != good {
		t.Fatal(err)
	}
}

func TestWebhookCancel(t *testing.T) {
	cfg := config.Defaults()
	if err := Webhook(context.Background(), &cfg, &fakeUI{}, nil, false); err != ErrCancelled {
		t.Fatal(err)
	}
}

func client(t *testing.T, root, name string) string {
	d := filepath.Join(root, name)
	os.MkdirAll(filepath.Join(d, "Interface", "AddOns"), 0o755)
	return d
}

func TestClientsDetectPickAndRemember(t *testing.T) {
	root := t.TempDir()
	client(t, root, "_retail_")
	era := client(t, root, "_classic_era_")
	cfg := config.Defaults()
	ui := &fakeUI{picks: []string{era}}
	cs, err := Clients(&cfg, ui, []string{root}, false)
	if err != nil || len(cs) != 1 || cs[0].Dir != era || len(cfg.WoWClients) != 1 {
		t.Fatal(cs, err)
	}
	// second run: remembered, no dialog
	cs, err = Clients(&cfg, &fakeUI{}, []string{root}, false)
	if err != nil || len(cs) != 1 {
		t.Fatal(err)
	}
	// automatic detection by name
	fv := client(t, root, "_forever_")
	cfg2 := config.Defaults()
	cs, err = Clients(&cfg2, &fakeUI{}, []string{root}, false)
	if err != nil || len(cs) != 1 || cs[0].Dir != fv {
		t.Fatal(cs, err)
	}
}

func TestClientsNothingFoundAsksFolder(t *testing.T) {
	other := t.TempDir()
	d := client(t, other, "_classic_era_")
	cfg := config.Defaults()
	ui := &fakeUI{picks: []string{t.TempDir(), d}}
	cs, err := Clients(&cfg, ui, nil, false)
	if err != nil || len(cs) != 1 || cs[0].Dir != d || len(ui.errors) != 1 {
		t.Fatal(cs, err, ui.errors)
	}
}
