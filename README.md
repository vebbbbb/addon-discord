# NAVTOK DISCORD

Your WoW Forever milestones in your guild's Discord, **live, with a screenshot**: epic loot,
level-ups, skill milestones, reputation, deaths, dungeon clears and battleground results. Each
one posts within a couple of seconds, not when you log out.

<sub>Inspired by Dink (RuneLite) and DOINK. NAVTOK posts in real time instead of on `/reload`.</sub>

## Install in 3 steps

1. **Download `NAVTOK.exe`** from the [latest release](../../releases/latest). Your guild officer
   may hand you a guild build instead.
2. **Run it once.** It finds WoW Forever, installs the addon, asks once for your guild's Discord
   webhook link (guild builds skip this question) and adds itself to Windows startup.
3. **Log in to WoW Forever**, or type `/reload` if you were already in game.

That's it. NAVTOK sits in the tray and starts with Windows. You only hear from it if something
breaks, and only once per problem.

> Where do I get the webhook link? In Discord: *Server Settings → Integrations → Webhooks → New
> Webhook → Copy Webhook URL*. Usually your guild officer gives it to you.

## What gets posted

| Event | When |
|---|---|
| Loot | you loot an epic (or better) item |
| Skill | a profession or weapon skill reaches 75 / 150 / 225 / 300 |
| Level | you level up (screenshot catches the level-up glow) |
| Reputation | you reach Friendly, Honored, Revered or Exalted with a faction |
| Death | you die (zone, and the killer when it can be told) |
| Dungeon | you kill a dungeon's or raid's final boss |
| Battleground | a battleground ends: win or loss, duration, your kills, deaths and honor |
| Legacy | a legacy point challenge is completed (experimental) |

Chat is hidden for the one frame the screenshot is taken, so whispers never end up in Discord.

## In-game commands

| Command | |
|---|---|
| `/navtok` | status |
| `/navtok test <type>` | post a fake event (marked TEST). Types: loot, skill, level, reputation, death, dungeon, bg, legacy |
| `/navtok position tl\|tr\|bl\|br` | move the barcode to another screen corner (default top-right) |
| `/navtok chat on\|off` | hide chat in screenshots (default on) |
| `/navtok debug` | debug messages |
| `/navtok probe` | diagnostics for testers (see VERIFY.md) |

Tray menu: **Last post**, **Send test**, **Open log**, **Quit**.

## How it works

WoW addons can't use the internet, and they can only save data to disk on `/reload` or logout.
So when something happens, the addon draws a small black-and-white barcode in a screen corner
for a single frame, takes a screenshot and hides the barcode again. WoW saves the screenshot
straight away. NAVTOK spots the new file, reads the barcode, cuts it out of the picture and
posts the picture to Discord.

If a barcode can't be read, the event is still in the addon's saved data. NAVTOK posts it after
your next `/reload` or logout, marked *(late)*. Nothing is ever posted twice.

## Privacy and safety

* NAVTOK talks to **one** address: your Discord webhook. It sends no telemetry and opens no
  ports. A self-update from GitHub Releases exists but is off unless you switch it on.
* It never reads game memory, never injects anything and never sends keys or clicks to the
  game. It only reads the screenshots WoW saves and the addon's own saved data.
* It writes files only to `%LOCALAPPDATA%\NAVTOK` (settings, posted-event list and a log capped
  at 1 MB), plus the addon folder in WoW.

## Settings (optional)

`%LOCALAPPDATA%\NAVTOK\config.json`:

| key | default | |
|---|---|---|
| `webhook_url` | | your Discord webhook |
| `wow_clients` | auto | WoW Forever client folder(s) |
| `delete_screenshots_after_post` | `false` | remove the screenshot once it is posted |
| `skip_test_events` | `false` | don't post `/navtok test` events |
| `barcode_removal` | `crop` | `crop`, `fill` or `none` |
| `max_image_width` / `jpeg_quality` | `1920` / `85` | |
| `plan_b_band_capture` / `band_corner` | `false` / `top-right` | fallback mode, see VERIFY.md item 1 |
| `self_update` | `false` | check GitHub Releases for new versions |
| `autostart` | `true` | start with Windows |

Command line: `NAVTOK.exe --setup` (enter the webhook again), `--uninstall`, `--dry-run`
(print posts instead of sending them), `--decode <screenshot.jpg>`, `--console`.

## For developers

See [CLAUDE.md](CLAUDE.md) for the architecture, [docs/barcode.md](docs/barcode.md) for the
barcode format and [VERIFY.md](VERIFY.md) for what still has to be confirmed in the Forever
beta.

```bash
luajit addon/tests/run.lua          # addon tests (WoW API stubs)
go test ./...                        # companion tests
./scripts/build.sh v1.0.0            # dist/NAVTOK.exe + addon zip
go run ./companion/cmd/fakeshot -dir /tmp/wow/_forever_/Screenshots -type bg
```

## License

[MIT](LICENSE)
