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

## Linux (WoW through Lutris, Steam/Proton, Bottles, Heroic or Wine)

1. Download **`navtok-linux-amd64`** from the [latest release](../../releases/latest) and put it
   somewhere it can stay, e.g. `~/.local/bin/navtok`. Then make it executable:
   `chmod +x ~/.local/bin/navtok`
2. **Run it once in a terminal:** `~/.local/bin/navtok`. It finds WoW inside your Wine/Lutris/
   Steam prefix, installs the addon and asks for the webhook link. If it can't find WoW, run it
   with `--wow "<path to the Forever client folder>"`. It then continues in the background, so
   you can close the terminal. It starts by itself at every login (`~/.config/autostart/navtok.desktop`).
3. **Log in to WoW Forever** (or `/reload`).

Differences from Windows: there is no tray icon, and problems show as desktop notifications.
Update with `navtok --update` (then log out and in). Test with `navtok --console --dry-run`.
Settings, state and log live in `~/.config/NAVTOK/`.

## What gets posted

| Event | When |
|---|---|
| Loot | you loot an epic (or better) item |
| Need roll | you **win anything on a Need roll**: "Won [Item] (Need 87)" |
| BoE equipped | you equip a Bind-on-Equip item (blue or better) |
| Recipe | you learn a recipe/pattern/plan **from an item** (green or better; trainer recipes are not posted) |
| Quest reward | notable quest turn-ins: **attunements** (Onyxia, Molten Core), **Tier 0.5** upgrade stages, **epic** rewards, blue rewards from **dungeon/raid quests**, and a short allowlist (Carrot on a Stick, ...) |
| Riding | you learn riding (normal mount) or epic riding |
| Dual spec | you unlock Dual Specialization |
| Skill | a profession or weapon skill reaches 75 / 150 / 225 / 300 |
| Level | you level up (screenshot catches the level-up glow) |
| Reputation | you reach Friendly, Honored, Revered or Exalted with a faction |
| Death | you die (zone, and the killer when it can be told); **PvP deaths** show as "Killed by \<player\> (PvP)" in red. Deaths can't be switched off. |
| Dungeon / raid | you kill a final boss from NAVTOK's list (instant post). Left without the final boss? When you leave (alive) WoW asks *"Did you complete Blackmaw Hold?"*; **Yes** posts it with the screenshot of your last boss kill. Dying and running back never asks. |
| Rare | you kill a rare or rare-elite mob |
| Battleground | a battleground ends: win or loss, duration, your kills, deaths and honor |
| Legacy | you complete a legacy challenge (all 176 from the game data: Classes, Tradeskills, Dungeons, Raids, PvP, Adventure) |

Chat is hidden for the one frame the screenshot is taken, so whispers never end up in Discord.

**Searching the channel:** every post has a small grey line like `Kjell · death`. Search Discord for
`Kjell death`, `Kjell pvp`, `Kjell need`, `Kjell level` and so on.

## In-game commands

| Command | |
|---|---|
| `/navtok` | status, what is posted, and the list of commands |
| `/navtok settings` | window: switch post types on/off, minimum rarity, profession milestones, level interval |
| `/navtok off <type>` / `on <type>` | e.g. `/navtok off rare` (types: loot, need, equip, recipe, level, skill, reputation, dungeon, bg, rare, legacy, quest, riding, dualspec) |
| `/navtok set <name> <value>` | `loot epic`, `need green`, `boe rare`, `recipe green`, `skills 75,150,225,300`, `levels 5` |
| `/navtok test <type>` | post a fake event (marked TEST). Types: loot, skill, level, reputation, death, dungeon, bg, legacy, rare, equip, recipe |
| `/navtok position tl\|tr\|bl\|br` | move the barcode to another screen corner (default top-right) |
| `/navtok chat on\|off` | hide chat in screenshots (default on) |
| `/navtok done` | ask "dungeon complete?" for a run you left by dying (no popup appears then) |
| `/navtok debug` | debug messages |
| `/navtok probe` | diagnostics for testers (see VERIFY.md) |
| `/navtok probe quest` | prints quest ID, title, tag and reward IDs at every quest turn-in (for the data files) |

Tray menu: **Last post**, **Send test**, **Check for updates**, **Open log**, **Quit**.
**Check for updates** downloads the newest NAVTOK from GitHub (new final bosses, fixes) and
restarts it; type `/reload` in WoW afterwards.

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
  ports. GitHub is contacted only when you click **Check for updates** (or switch on
  `self_update`).
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
| `self_update` | `false` | also check GitHub Releases automatically at start (the tray button always works) |
| `autostart` | `true` | start with Windows |

Command line: `NAVTOK.exe --setup` (enter the webhook again), `--uninstall`, `--dry-run`
(print posts instead of sending them), `--decode <screenshot.jpg>`, `--console`.

## Release announcements in Discord (for the guild officer)

Every release published on GitHub can be announced in a Discord channel automatically (version,
release notes, download links, "click Check for updates"):
1. In Discord, create a webhook for the channel that should get the announcements.
2. In GitHub: **Settings -> Secrets and variables -> Actions -> New repository secret**, name
   `DISCORD_RELEASE_WEBHOOK`, value = that webhook link.
3. Publish releases on the **Releases** page. What you write in the release description is posted.

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
