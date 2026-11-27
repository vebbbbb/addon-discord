# NAVTOK barcode, version 1

Every screenshot NAVTOK posts carries its own event as a barcode, drawn by the addon for one
frame right before `Screenshot()`. The companion decodes it, cuts it out and posts the picture.

Encoder: `addon/NavtokDiscord/Barcode.lua`. Decoder (and a mirror encoder for tests):
`companion/internal/barcode`. The two are bound together by the fixture
`addon/tests/fixtures/barcode_v1.txt`, which the Lua encoder writes and both test suites check
(see [Keeping encoder and decoder in sync](#keeping-encoder-and-decoder-in-sync)).

## Geometry

| item | value |
|---|---|
| modules | **77 columns × 13 rows** |
| quiet zone | 2 white modules on every side (drawn by the addon, part of the frame) |
| total size | 81 × 17 modules = **648 × 136 px** at the default 8 px module |
| module size | `blockSize` setting, default **8 physical pixels** |
| colours | pure black `#000` on pure white `#FFF`, fully opaque |
| position | flush with the configured screen corner (default top-right, `/navtok position`) |

```
 c=0                                                            c=76
  ┌──────────────────────────────────────────────────────────────┐
r=0  █ █ █ █ █ █ █ ... █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █ █   ← top clock: black on even columns
  █ . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
  █ . . . . . . . .   DATA  75 × 11 = 825 bits  . . . . . . . . █   ← right clock: black on rows
  █ . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .     where (12 - r) is even
  █ . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . █
  ...
r=12 ███████████████████████████████████████████████████████████████  ← bottom row solid
  ↑ left column solid
```

The layout borrows Data Matrix's "L finder plus clock tracks":

* **Left column (c = 0) and bottom row (r = 12) are solid black.**
* **Top row (r = 0):** black where `c` is even. 77 is odd, so it starts and ends black.
* **Right column (c = 76):** black where `(12 - r)` is even. That makes it black at the top and
  bottom corners and alternating in between.
* **Data** fills rows 1..11 × columns 1..75 row-major, from top-left to bottom-right, most
  significant bit first. A black module is a 1 bit.

## Frame

```
offset  size  value
0       2     "N" "V"            (0x4E 0x56)
2       1     version            (1)
3       1     length N           (0..96)
4       N     payload            (UTF-8 text, see below)
4+N     2     CRC-16, big endian
```

* CRC-16/CCITT-FALSE: polynomial 0x1021, initial value 0xFFFF, no reflection, no final XOR.
  It covers bytes `0 .. 3+N`, so the magic, version and length are protected too. Check value:
  `CRC("123456789") = 0x29B1`.
* After the frame, the 103-byte capacity is padded with `0xEC 0x11 0xEC 0x11 …`. The last
  (825th) bit is 0.
* Maximum frame: 2 + 1 + 1 + 96 + 2 = 102 bytes = 816 bits, which fits in 825.

## Payload v1

The payload is UTF-8 text with fields separated by `0x1F` (ASCII unit separator). The game's
own escape character `|` is never used. Colour codes and links are stripped, and control
characters are replaced by spaces.

| # | field | example |
|---|---|---|
| 0 | type code | `L` |
| 1 | flags: `T` = test event, `C` = candidate (kept by the companion, not posted) | `` |
| 2 | `time()` of the event (unix seconds) | `1764160000` |
| 3 | per-character sequence number | `42` |
| 4 | character name | `Navtök` |
| 5 | class id (1 Warrior … 11 Druid) | `8` |
| 6 | character level | `60` |
| 7… | type-specific fields | |

The event id is `<time>.<seq>`, and the dedupe key is `<char>|<time>.<seq>`. The same id is
written to SavedVariables, which is how the late path recognises events that were already
posted.

| code | type | fields 7… (in order) | shortened first when > 96 bytes |
|---|---|---|---|
| `L` | loot | itemId, quality, count, item, roll (`need` or empty), rollValue | item |
| `S` | skill | skill, rank | skill |
| `V` | level | zone | zone |
| `R` | reputation | faction, standing (1..8) | faction |
| `D` | death | zone, subzone, killer, pvp (`1` = killed by a player / in a battleground) | subzone, killer, zone |
| `K` | dungeon | encounterId, encounter, instance, bosses, duration, shotSeq | instance, encounter |
| `B` | bg | bg, result (`win`/`loss`/`draw`), duration (s), kb, hk, deaths, honor | bg |
| `G` | legacy | achievementId, text, group | group, text |
| `E` | rare | npcId, classification, mobLevel, npc, zone, subzone | subzone, zone, npc |
| `Q` | equip | itemId, quality, slot, item | item |
| `P` | recipe | itemId, quality, item, learned | learned, item |
| `U` | quest | sub (attunement/tier05/class/epic/dungeon/allowlist), questId, itemId, quality, stage, item, extra, quest | quest, extra, item |
| `M` | unlock | sub (riding/epicriding/dualspec), rank, skill | skill |

If the payload is longer than 96 bytes, the free-text fields in the right-hand column are
shortened in that order, never splitting a UTF-8 sequence. The character name is shortened only
as a last resort; the companion's dedupe treats a shortened name as a prefix match. The full
text is always available in SavedVariables.

## Pixel-perfect drawing

The barcode frame has **no parent**, so its effective scale is its own scale and it ignores the
UI scale. It also stays visible when the UI is hidden with Alt+Z. The addon sets

```
scale = 768 / physicalScreenHeight
```

so one UI unit equals one physical pixel. Every module is then exactly `blockSize` pixels at an
integer offset. The physical height comes from `GetPhysicalScreenSize()`, falling back to the
`gxFullscreenResolution`/`gxWindowedResolution` CVars, then to 1080. Which one was used is
shown by `/navtok probe` (VERIFY.md item 8). Texture pixel snapping is turned off where the
client supports it.

## Decoding

1. Search regions in order: top-right, top-left, bottom-right and bottom-left corners
   (min(1100 px, half the width) × min(360 px, a third of the height)), then the whole image.
2. Binarise the luma with a fixed threshold of 128. The code is pure black and white, so this
   survives JPEG well. For YCbCr JPEGs the Y plane is read directly, with no copy.
3. Scan pixel rows for a **clock**: at least 21 alternating runs of near-equal length (each
   within 0.5–1.6 × the running mean), starting and ending black, bounded by wider white runs
   (the quiet zone). This gives the column count, x-extent and module width.
4. Follow the solid **left column** up and down to get the code's height. Count the runs of the
   **right clock column** to get the row count (one-pixel JPEG slivers are merged). Check that
   rows are near-square to columns.
5. Check the **finder**: the bottom row and left column must be black, with at most 10% bad
   samples.
6. Sample every data module at its centre, averaging ±20% of a module. Rebuild the bytes and
   check magic, version, length and CRC. Any failure moves on to the next candidate.
7. Return the payload and the rectangle including the quiet zone. The companion removes that
   rectangle from the image:
   * `crop` (default): cut the rows or columns at the edge it touches, whichever loses less.
   * `fill`: paint it with the surrounding average colour.
   * `none`: leave the image as it is.

Because the grid size is measured rather than assumed, the decoder tolerates a module size
other than 8 px: other `blockSize` values, a UI that wasn't pixel-perfect, or a screenshot that
was scaled.

## Robustness (tests)

`companion/internal/barcode/decode_test.go` renders the code exactly like the addon and places
it on a busy synthetic scene in every corner and in the middle. It then rescales the scene by
0.93, 1.07 or 1.25 (bilinear), JPEG-compresses it at quality **50, 75 and 95** and decodes it,
for module sizes 6, 8 and 10 px and payloads of 0, 1, typical and 96 bytes. It also checks
quality 20–45 (at least 5 of 6 must decode), that scenes without a code produce no false
positive, and that a frame with a bad CRC is rejected. Decoding a 1080p JPEG takes about
0.07 ms once it is in memory.

## Keeping encoder and decoder in sync

```
luajit addon/tests/gen_fixture.lua     # rewrites addon/tests/fixtures/barcode_v1.txt
```

* The Lua suite (`addon/tests/test_barcode.lua`) fails if the fixture differs from what the
  current Lua encoder produces.
* The Go suite (`companion/internal/barcode/fixture_test.go`) checks that the Go encoder builds
  the same frame and grid from the fixture payload. It also renders the fixture grid (the Lua
  one, not Go's), JPEG-compresses it at quality 50/75/95 and decodes it back to the fixture
  payload.
* CI regenerates the fixture and fails on any diff.

Any format change needs a new `VERSION` and a new fixture file.
