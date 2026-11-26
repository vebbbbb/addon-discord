// Package setup is the "one and done" first run: find WoW Forever, ask for the webhook once.
package setup

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/navtok/navtok-discord/companion/internal/config"
	"github.com/navtok/navtok-discord/companion/internal/discord"
	"github.com/navtok/navtok-discord/companion/internal/logx"
	"github.com/navtok/navtok-discord/companion/internal/wowdetect"
)

// UI is the dialog surface (zenity on Windows, console elsewhere, fake in tests).
type UI interface {
	AskWebhook(prompt string) (string, bool)
	ShowError(msg string)
	PickFolder(prompt string) (string, bool)
	PickFromList(prompt string, items []string) (string, bool)
}

// ErrCancelled means the user closed a setup dialog.
var ErrCancelled = errors.New("setup cancelled")

// Validator checks a webhook URL (GET). Permanent errors mean "wrong URL".
type Validator func(ctx context.Context, url string) error

// DefaultValidator uses discord.Client.Validate.
func DefaultValidator(ctx context.Context, url string) error {
	return discord.NewClient(url).Validate(ctx)
}

// Clients returns the Forever client folders: the configured ones if they still exist, else
// detected ones, else the user's pick. cfg.WoWClients is updated.
func Clients(cfg *config.Config, ui UI, roots []string, force bool) ([]wowdetect.Client, error) {
	if !force {
		var out []wowdetect.Client
		for _, d := range cfg.WoWClients {
			if c, ok := wowdetect.ClientFromDir(d); ok {
				out = append(out, c)
			}
		}
		if len(out) > 0 {
			return out, nil
		}
	}
	all, forever := wowdetect.Detect(roots)
	for _, c := range all {
		logx.Printf("found client %s score %d %v", c.Dir, c.Score, c.Reasons)
	}
	chosen := forever
	if len(chosen) == 0 && len(all) > 0 {
		var items []string
		for _, c := range all {
			items = append(items, c.Dir)
		}
		pick, ok := ui.PickFromList("NAVTOK could not tell which of your WoW clients is WoW Forever.\nPlease pick the Forever client:", items)
		if !ok {
			return nil, ErrCancelled
		}
		for _, c := range all {
			if c.Dir == pick {
				chosen = []wowdetect.Client{c}
			}
		}
	}
	for len(chosen) == 0 {
		dir, ok := ui.PickFolder("NAVTOK could not find World of Warcraft.\nPlease choose your WoW Forever folder (the one that contains Interface and WTF, e.g. ...\\World of Warcraft\\_classic_era_).")
		if !ok {
			return nil, ErrCancelled
		}
		if c, ok := wowdetect.ClientFromDir(dir); ok {
			chosen = []wowdetect.Client{c}
		} else {
			ui.ShowError("That folder does not look like a WoW client folder (no Interface folder or Wow*.exe inside).")
		}
	}
	cfg.WoWClients = nil
	for _, c := range chosen {
		cfg.WoWClients = append(cfg.WoWClients, c.Dir)
	}
	return chosen, nil
}

// Webhook makes sure cfg.WebhookURL is set and valid, asking until it is (or the user cancels).
// A webhook that cannot be checked because the PC is offline is accepted if it looks right.
func Webhook(ctx context.Context, cfg *config.Config, ui UI, validate Validator, force bool) error {
	url := strings.TrimSpace(cfg.WebhookURL)
	if url != "" && !force {
		return nil
	}
	prompt := "Paste your guild's Discord webhook URL\n(Discord: Server Settings > Integrations > Webhooks > Copy Webhook URL):"
	for {
		in, ok := ui.AskWebhook(prompt)
		if !ok {
			return ErrCancelled
		}
		in = strings.TrimSpace(in)
		if !discord.ValidURL(in) {
			ui.ShowError("That is not a Discord webhook URL.\nIt looks like https://discord.com/api/webhooks/123.../abc...")
			continue
		}
		err := validate(ctx, in)
		var pe *discord.PermanentError
		if errors.As(err, &pe) {
			ui.ShowError(fmt.Sprintf("Discord does not accept this webhook (%s).\nPlease copy it again.", strings.TrimSpace(pe.Body)))
			continue
		}
		if err != nil {
			logx.Printf("webhook could not be verified (offline?): %v", err)
		}
		cfg.WebhookURL = in
		return nil
	}
}

// Exists reports whether a path exists (helper for main).
func Exists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}
