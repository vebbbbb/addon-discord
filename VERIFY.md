# VERIFY.md: checks to run in the WoW Forever beta (client 1.60.1)

Everything below is **assumed, not known** about Forever. Work through the list on a real
client and tick the boxes. Each item gives the exact steps, what to look for in `/navtok probe`
output, and what to change if the answer is "no".

**How the probe works**
* `/navtok probe` turns it on (it stays on across `/reload`), `/navtok probe off` turns it off
  and `/navtok probe clear` empties the buffer.
* Each line goes to chat and to the `["probe"]` list in
  `<client>\WTF\Account\<ACCOUNT>\SavedVariables\NavtokDiscord.lua`, written on `/reload` or
  logout. Lines look like `14:03:11 [12345.678] EVENT(arg1, arg2, ...)`.
* Turning the probe on first dumps the environment: build info, screen size, UI scale, CVars,
  which APIs exist, and which events the client rejected (`unknown events -> ...`).
* Companion side: `%LOCALAPPDATA%\NAVTOK\navtok.log` (tray → Open log).
  `NAVTOK.exe --decode <file.jpg>` decodes a single screenshot and prints the event.

---

## 1. `Screenshot()` works without a key press (decides plan A vs plan B)

- [ ] **Result:** ______

Steps:
1. Install NAVTOK and log in.
2. Type `/navtok probe shot`. One second later the probe calls `Screenshot()` from a timer, not
   from a key press.
3. Watch for these lines:
   ```
   shot test: Screenshot() now, time()=...
   shot test: returned ok=true
   SCREENSHOT_SUCCEEDED()
   ```
   A new `WoWScrnShot_*.jpg` should also appear in `<client>\Screenshots`.
4. Repeat `/navtok probe shot` while **in combat** and from inside an **event handler**:
   `/navtok test level` calls it from the queue's OnUpdate, which is the real code path.

If you see `ok=false` and an error mentioning "protected", "blocked" or "hardware event", or
`SCREENSHOT_FAILED()`, or no file appears, switch to **plan B**:
* In game: `/navtok mode band`. The barcode is then held on screen for 0.6 s and
  `Screenshot()` is not called.
* Companion: set `"plan_b_band_capture": true` and `"band_corner"` to match the addon's corner
  in `%LOCALAPPDATA%\NAVTOK\config.json`, then restart NAVTOK.
* Check that posts arrive without a picture and `navtok.log` shows `posted ... [band]`.
* Note whether band capture works in **fullscreen**. GDI capture of exclusive fullscreen may be
  black; windowed or borderless is expected to work.

## 2. The barcode decodes from real screenshots

- [ ] **Result:** ______ (format / quality CVars: ______)

1. In the probe environment dump, read `GetCVar(screenshotFormat)` and
   `GetCVar(screenshotQuality)`.
2. `/navtok test loot`, then run `NAVTOK.exe --decode "<client>\Screenshots\WoWScrnShot_....jpg"`.
   It should print `"key": "<Char>|<ts>.<seq>"` and a `module_px` of about `8.00x8.00`.
3. Repeat at the lowest screenshot quality the client allows (`/console screenshotQuality 1`)
   and at UI scale 0.64 and 1.0.

If the format is `tga`, NAVTOK shows a notification asking you to switch with
`/console screenshotFormat jpg`, because TGA is not supported. If decoding fails, keep the
screenshot and run `--decode` on it; a module size far from 8 px points to item 8.

## 3. Screenshot files appear on disk immediately

- [ ] **Result:** delay ______ ms

1. `/navtok test level`. Compare the probe time of `SCREENSHOT_SUCCEEDED()` with the file's
   creation time (Explorer → Details, or `dir /T:C`).
2. In `navtok.log` the line `posted <key> [barcode] "..." in <N>ms (event age <S>s)` gives the
   companion's own time and the total age (target under 2 s).

If WoW buffers the file and writes it later, the latency target moves. Nothing breaks: the
watcher waits for a complete JPEG.

## 4. Dungeon and raid clears: final bosses, popup, deaths

- [ ] **Result:** ______

The final-boss list (`Data/Dungeons.lua`) is kept by hand and uses Forever's own encounter ids.
1. With the probe on, kill a listed final boss (e.g. Edwin VanCleef). `ENCOUNTER_END(id, name,
   difficulty, size, 1)` must appear and a post must follow within seconds. If only
   `BOSS_KILL(id, name)` fires, add a `BOSS_KILL` handler in `Notifiers/Dungeon.lua`.
2. In a dungeon whose final boss is not listed (e.g. Blackmaw Hold), kill a few bosses and
   hearth out. Expect no post per boss (navtok.log: `kept candidate screenshot ...`), then the
   popup "Did you complete Blackmaw Hold?". Yes -> one post with the screenshot of the last boss.
3. Wipe, release and run back in: **no popup**. Leave alive afterwards: popup.
4. Check `GetInstanceInfo()` / `IsInInstance` in the probe's `PLAYER_ENTERING_WORLD` lines, and
   that the popup is not blocked while in combat.
5. Add missing final bosses to `Data/Dungeons.lua` (`python3 scripts/gen_data.py --encounters`
   lists the ids) and release; players click **Check for updates**.

## 5. `GetBattlefieldWinner()` / `GetBattlefieldScore()` in Forever battlegrounds

- [ ] **Result:** ______

1. Play a battleground with the probe on. At the end, look for
   `UPDATE_BATTLEFIELD_STATUS(...)` followed by `GetBattlefieldWinner -> 0` (Horde) or `1`
   (Alliance).
2. Also check `GetBattlefieldStatus(i) -> active, <map name>, <instanceID>` and the instance
   id (is it non-zero?).
3. Check `own score row i -> <name>, <kb>, <hk>, <deaths>, <honor>, ...` and that the order is
   name, killingBlows, honorableKills, deaths, honorGained.
4. Check `GetBattlefieldInstanceRunTime -> <ms>`.
5. Exactly **one** post should arrive per battleground, about 1 s after the scoreboard opens.
   `/reload` on the scoreboard must not post again.

## 6. Reputation standing changes are detected for every tier

- [ ] Friendly - [ ] Honored - [ ] Revered - [ ] Exalted

1. With the probe on, gain a standing. `UPDATE_FACTION()` should be followed by
   `GetFactionInfo(i) -> name, desc, standingID, ...`. Check that `standingID` is the 3rd value
   and `factionID` the 14th (`nil` is fine; the name is used instead).
2. A post `Now <Standing> with <Faction>` should appear.
3. Check `CHAT_MSG_COMBAT_FACTION_CHANGE(...)` too, as a backup trigger if `UPDATE_FACTION`
   turns out unreliable.
4. Collapse the faction's header in the reputation window and gain rep. Nothing breaks, but
   that faction is only checked again when the header is expanded. Note it.

## 7. Legacy challenges fire `ACHIEVEMENT_EARNED`

- [ ] **Result:** ______

Forever's client database defines the legacy challenges as achievements (176 of them, in
`Data/Legacy.lua`, generated by `scripts/gen_data.py`). The addon posts on `ACHIEVEMENT_EARNED`.
1. With the probe on, complete any legacy challenge (the quickest is exploring a zone, which
   posts "Explore <zone>"; set `legacyZones = false` in SavedVariables if those are too many).
   Look for `ACHIEVEMENT_EARNED(<id>, ...)` and `GetAchievementInfo -> function`, then the post.
2. If `ACHIEVEMENT_EARNED` is listed under `unknown events`, the addon falls back to system
   messages matching `settings.legacyPatterns`. Note the exact completion message so the pattern
   can be made precise.
3. Each challenge exists twice in the data (two flag variants, probably account vs character).
   Check which id actually fires; duplicates within 10 s are merged anyway.

## 7b. Rare kills are detected

- [ ] **Result:** ______

1. Target a rare. The probe shows `target <name> class=rare|rareelite guid=Creature-... tapDenied=false`.
2. Kill it while targeted: a post "Killed <name>" must follow. Kill another while it is NOT
   targeted at the moment of death (e.g. after mouseover only). The XP message
   (`CHAT_MSG_COMBAT_XP_GAIN(<name> dies, you gain ...)`) should still trigger it below level 60.
3. At level 60 there is no XP message: then only a rare that is the target, mouseover or a visible
   nameplate when it dies is caught. Check whether `NAME_PLATE_UNIT_*` events exist
   (`unknown events` line) - if they do, enemy nameplates on (V key) make detection reliable.

## 8. Physical pixel size / UI scale for pixel-perfect drawing

- [ ] **Result:** ______

1. The probe environment dump shows `GetPhysicalScreenSize -> W, H`,
   `UIParent:GetEffectiveScale -> ...` and `barcode physical height used -> H (source)`.
2. The source should be `GetPhysicalScreenSize`. If it says `fallback`, the barcode is sized for
   1080p and the decoder adapts to the actual module size.
3. Run `--decode` on a test screenshot. `module_px` should be exactly `8.00x8.00`. Test both
   windowed and fullscreen and at several UI scales.

If the module size is off, check whether `SetScale(768 / H)` on a parentless frame really maps
1 unit to 1 pixel in Forever. Also check that `SetSnapToPixelGrid` and `SetTexelSnappingBias`
exist; the probe lists the API presence.

## 9. Hiding chat frames before the screenshot works, including in combat

- [ ] **Result:** ______

1. Get a whisper so chat has text, then `/navtok test loot`. The screenshot posted to Discord
   must show **no chat**, while in game chat is back on the next frame.
2. Repeat in combat. The addon uses `SetAlpha(0)`, which is not protected, so it should work.
3. If chat still shows, check for other chat addons' frames (Prat, Chatter) and add their frame
   names to `CHAT_EXTRA` in `Screenshot.lua`.
4. `/navtok chat off` disables hiding.

## 10. How to recognise the Forever client folder

- [ ] **Result:** folder name ______, `.flavor.info` product ______, `.build.info` version ______

NAVTOK scores every `_*_` folder that contains `Interface\` or a `Wow*.exe` (see
`companion/internal/wowdetect/detect.go`):

| points | condition |
|---|---|
| 100 | folder name contains `forever` |
| 90 | `.flavor.info` product has a `.build.info` Version starting with `1.60.` |
| 80 | the product name contains `forever` |
| 40 | an executable named `Wow*Forever*.exe` |
| 10 | `Interface\AddOns\NavtokDiscord` already exists |

A folder with 60 or more points counts as Forever. If nothing matches, the user picks from the
list once, and the choice is saved in `config.json` → `wow_clients`.

Please record:
1. The registry `InstallPath` under
   `HKLM\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft`.
2. The client folder name.
3. The contents of `<client>\.flavor.info`.
4. The Forever row of `<root>\.build.info` (Product and Version columns).
5. The executable name.

`navtok.log` lists every client found with its score and reasons
(`found client ... score N [...]`). Adjust the rules once the real layout is known.

---

## Also worth a look

- [ ] `## Interface: 16001` is accepted (the addon is not flagged "out of date").
- [ ] `C_Timer.After` exists (the probe environment dump: `API C_Timer -> table`). If not, the
      addon falls back to its own OnUpdate timer.
- [ ] `GET_ITEM_INFO_RECEIVED` fires for uncached epics, so `/navtok test loot` and real loot of
      a never-seen item both post.
- [ ] `PLAYER_DEAD` does not fire on login while dead (the addon ignores the first 3 s anyway).
- [ ] `GetItemInfo` quality values match the classic-era numbering (4 = epic).
- [ ] The Wowhead base URL in `config.json` → `wowhead_base` points somewhere sensible for
      Forever items.
- [ ] Idle CPU of NAVTOK.exe is about 0% and memory stays under 40 MB (Task Manager) over a
      multi-hour session.
