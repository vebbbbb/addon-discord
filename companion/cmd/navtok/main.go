// NAVTOK.exe - the NAVTOK DISCORD companion.
//
//	NAVTOK.exe                 first run: set up, then live in the tray (later runs: silent)
//	NAVTOK.exe --dry-run       print posts instead of sending them
//	NAVTOK.exe --decode X.jpg  decode the barcode of one screenshot and print the event
//	NAVTOK.exe --setup         ask for the webhook / WoW folder again
//	NAVTOK.exe --uninstall     remove the addon and the autostart entry
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"runtime/debug"
	"syscall"
	"time"

	navtok "github.com/navtok/navtok-discord"
	"github.com/navtok/navtok-discord/companion/internal/app"
	"github.com/navtok/navtok-discord/companion/internal/barcode"
	"github.com/navtok/navtok-discord/companion/internal/config"
	"github.com/navtok/navtok-discord/companion/internal/discord"
	"github.com/navtok/navtok-discord/companion/internal/event"
	"github.com/navtok/navtok-discord/companion/internal/imageproc"
	"github.com/navtok/navtok-discord/companion/internal/install"
	"github.com/navtok/navtok-discord/companion/internal/logx"
	"github.com/navtok/navtok-discord/companion/internal/notify"
	"github.com/navtok/navtok-discord/companion/internal/platform"
	"github.com/navtok/navtok-discord/companion/internal/setup"
	"github.com/navtok/navtok-discord/companion/internal/state"
	"github.com/navtok/navtok-discord/companion/internal/tray"
	"github.com/navtok/navtok-discord/companion/internal/update"
	"github.com/navtok/navtok-discord/companion/internal/wowdetect"
)

// version is set with -ldflags "-X main.version=v1.2.3".
var version = "dev"

type uiAdapter struct{}

func (uiAdapter) AskWebhook(p string) (string, bool) { return platform.AskWebhook(p) }
func (uiAdapter) ShowError(m string)                 { platform.ShowError(m) }
func (uiAdapter) PickFolder(p string) (string, bool) { return platform.PickFolder(p) }
func (uiAdapter) PickFromList(p string, i []string) (string, bool) {
	return platform.PickFromList(p, i)
}

func main() {
	var (
		dryRun    = flag.Bool("dry-run", false, "print Discord posts instead of sending them")
		decode    = flag.String("decode", "", "decode the barcode in a screenshot `file` and exit")
		forceSet  = flag.Bool("setup", false, "run the first-run setup again")
		uninstall = flag.Bool("uninstall", false, "remove the addon and the autostart entry")
		console   = flag.Bool("console", false, "run without tray icon, log to the console")
		wowDir    = flag.String("wow", "", "use this WoW client `folder` (skips detection)")
		showVer   = flag.Bool("version", false, "print the version")
	)
	flag.Parse()
	if *showVer {
		fmt.Println("NAVTOK", version)
		return
	}
	if *decode != "" {
		os.Exit(decodeFile(*decode, os.Stdout))
	}
	debug.SetMemoryLimit(32 << 20) // stay well below 40 MB

	dir, err := config.Dir()
	if err != nil {
		fatal("cannot create the NAVTOK data folder: " + err.Error())
	}
	var also io.Writer
	if *console || *dryRun || !tray.Available() {
		also = os.Stderr
	}
	lw, err := logx.Open(filepath.Join(dir, "navtok.log"), also)
	if err == nil {
		logx.Init(lw)
		defer lw.Close()
	}
	logx.Printf("NAVTOK %s starting (data %s)", version, dir)

	if !platform.SingleInstance() {
		logx.Printf("already running, exiting")
		return
	}
	update.Cleanup()

	cfg, exists, err := config.Load(dir)
	if err != nil {
		logx.Printf("config.json unreadable (%v), using defaults", err)
	}
	firstRun := !exists || *forceSet
	if *wowDir != "" {
		cfg.WoWClients = []string{*wowDir}
	}

	ui := uiAdapter{}
	clients, err := setup.Clients(&cfg, ui, wowdetect.Roots(), *forceSet && *wowDir == "")
	if err != nil {
		logx.Printf("setup: %v", err)
		return
	}

	if *uninstall {
		for _, c := range clients {
			if err := install.Uninstall(c.AddOnsDir()); err != nil {
				platform.ShowError("Could not remove the addon: " + err.Error())
			}
		}
		_ = platform.SetAutoStart(false)
		platform.ShowInfo("NAVTOK was removed from WoW and from Windows startup.\nYou can delete NAVTOK.exe and the folder " + dir + ".")
		return
	}

	problems := notify.New(platform.Notify)
	installAddon(clients, problems)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	if !*dryRun {
		if err := setup.Webhook(ctx, &cfg, ui, setup.DefaultValidator, *forceSet); err != nil {
			logx.Printf("setup: %v", err)
			return
		}
	}
	if cfg.AutoStart {
		if err := platform.SetAutoStart(true); err != nil {
			logx.Printf("autostart: %v", err)
		}
	}
	if err := config.Save(dir, cfg); err != nil {
		logx.Printf("save config: %v", err)
	}

	st, err := state.Open(dir)
	if err != nil {
		fatal("cannot open state.json: " + err.Error())
	}
	var poster discord.Poster = discord.NewClient(cfg.WebhookURL)
	if *dryRun {
		poster = discord.DryRun{W: os.Stdout}
	}
	sender := discord.NewSender(poster)
	sender.OnTransient = func(err error) {
		logx.Printf("post failed, will retry: %v", err)
		problems.Report(app.ProblemOffline, "NAVTOK cannot reach Discord right now. Posts are kept and sent as soon as the connection is back.")
	}
	a := app.New(cfg, st, sender, problems, clients)

	if cfg.SelfUpdate && !*dryRun {
		go func() {
			if tag, err := update.Check(ctx, config.UpdateRepo, version); err != nil {
				logx.Printf("self-update: %v", err)
			} else if tag != "" {
				logx.Printf("self-update: installed %s, active after the next start", tag)
			}
		}()
	}

	if firstRun && !*dryRun {
		platform.ShowInfo("NAVTOK is set up!\n\nLog in to WoW Forever (or type /reload) to load the NavtokDiscord addon.\nNAVTOK now runs in the tray and starts with Windows - nothing else to do.")
	}

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	menu := &tray.Menu{
		OnSendTest: func() {
			a.SendTest(func(err error) {
				if err != nil {
					platform.ShowError("The test post failed: " + err.Error())
				}
			})
		},
		OnOpenLog: func() { _ = platform.Open(filepath.Join(dir, "navtok.log")) },
		OnQuit:    cancel,
	}
	last, _ := st.LastPost()
	a.OnPosted = func(s string) {
		if menu.SetLastPost != nil {
			menu.SetLastPost(s)
		}
	}
	done := make(chan struct{})
	run := func() {
		go func() {
			select {
			case <-sig:
				cancel()
			case <-ctx.Done():
			}
		}()
		go func() {
			if err := a.Run(ctx); err != nil {
				logx.Printf("run: %v", err)
			}
			close(done)
		}()
	}
	if *console || *dryRun || !tray.Available() {
		run()
		<-done
		return
	}
	tray.Run(menu, last, run)
}

func installAddon(clients []wowdetect.Client, problems *notify.Problems) {
	for _, c := range clients {
		res, err := install.Install(navtok.AddonFS, navtok.AddonRoot, c.AddOnsDir())
		if err != nil {
			problems.Report("install", "NAVTOK could not install the addon into "+c.AddOnsDir()+": "+err.Error())
			continue
		}
		if res.Changed() {
			logx.Printf("addon installed/updated in %s (%d files written, %d removed)", res.Dir, len(res.Written), len(res.Removed))
		}
	}
}

// decodeFile implements --decode.
func decodeFile(path string, out io.Writer) int {
	start := time.Now()
	img, err := imageproc.Load(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	res, err := barcode.Decode(img)
	if err != nil {
		fmt.Fprintln(os.Stderr, "no NAVTOK barcode found:", err)
		return 1
	}
	e, perr := event.ParsePayload(res.Payload)
	report := map[string]any{
		"barcode": map[string]any{"version": res.Version, "rect": res.Rect.String(), "module_px": fmt.Sprintf("%.2fx%.2f", res.ModuleW, res.ModuleH),
			"payload": string(res.Payload), "decode_ms": time.Since(start).Milliseconds()},
	}
	if perr != nil {
		report["error"] = perr.Error()
	} else {
		report["event"] = e
		report["key"] = e.Key()
		report["discord"] = discord.Build(e, discord.Options{WowheadBase: config.Defaults().WowheadBase, HasImage: true})
	}
	b, _ := json.MarshalIndent(report, "", "  ")
	fmt.Fprintln(out, string(b))
	if perr != nil {
		return 1
	}
	return 0
}

func fatal(msg string) {
	logx.Printf("fatal: %s", msg)
	platform.ShowError(msg)
	os.Exit(1)
}
