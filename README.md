# D&D Beyond — Omarchy shell plugin

Character sheets from your D&D Beyond account, right in the Omarchy bar.
Pick a character, browse the sheet in tabs, roll dice, take rests — without
opening a browser.

![preview](preview.png?v=2)

Uses the same unofficial, undocumented endpoints the D&D Beyond web app uses.
Not affiliated with or endorsed by D&D Beyond or Wizards of the Coast —
endpoints may change without notice.

## Features

**Bar widget**
- d20 glyph with live HP (`8/15`), tinted green > 75%, yellow 25–75%, red < 25%
- Optional character name in the bar
- Click opens the sheet card; right/middle-click refreshes

![bar widget](screenshots/bar.png?v=2)

**Main tab** — portrait (click for full-size), ability scores, saving throws,
HP / AC / initiative / proficiency / speed / passive perception, hit dice,
level & XP, conditions, inspiration. Equipped-weapon **attack rolls** and
**damage rolls** built from ability modifiers, proficiency, and magic item
bonuses.

**Skills tab** — all 18 skills with proficiency (●) / expertise (◆) markers
and final modifiers.

![skills](screenshots/skills.png?v=2)

**Spells tab** — spell slots (remaining/max, pact magic derived from the
warlock table), spellcasting DC & attack bonus, spells grouped by level.
Click a spell to expand: full description, duration, components, material,
save/attack type, at-higher-levels scaling. Attack-roll spells and damage
spells get clickable roll chips.

![spells](screenshots/spells.png?v=2)

**Features** — class/subclass features, racial traits, feats (HTML stripped).

![features](screenshots/features.png?v=2)

**Inventory** — equipped first, attunement, quantities, currency.

![inventory](screenshots/inventory.png?v=2)
**Notes** — backstory, allies, enemies, organizations, personal possessions,
other holdings/notes from the DDB notes fields.

![notes](screenshots/notes.png?v=2)

**Dice rolls** — click abilities, skills, attacks, damage, or spell attack
chips; the banner shows the breakdown (`Initiative 13 + 2 = 15`), with nat-20
/ nat-1 flair. Roll initiative with the `i` key, the Init box, or globally via
IPC (see below).

**HP tracking** — `+`/`−` buttons beside the HP box (click = 1, right-click = 5),
or `-`/`=` keys. Writes back to D&D Beyond server-side, clamped to 0–max.

**Death saves** — at 0 HP the Main tab grows a death-save section: flat-d20
roll with auto-applied rules (nat 20 regains 1 HP, nat 1 is two failures),
manual pip buttons, reset. Writes back to DDB.

![death saves](screenshots/deathsaves.png?v=2)

**Rests** — short rest / long rest buttons write back to D&D Beyond
server-side (two-click confirm). Along with HP, the only write APIs DDB
still exposes.

**Settings pane** (gear button or `s`) — show/color HP, character name in
bar, default tab, refresh interval, card width/height, additional character
IDs, and CobaltSession cookie management.

![settings](screenshots/settings.png?v=2)

![portrait zoom](screenshots/portrait.png?v=2)

## Install

```bash
omarchy plugin add https://github.com/brianstarke/omarchy-plugin-dndbeyond.git
```

or from a checkout:

```bash
./install.sh
```

Then enable the widget (plugins land disabled for review) and place it with
`omarchy bar move brianstarke.dndbeyond --section left` (or right).

## Authentication

D&D Beyond has no public API, so the plugin reuses your browser session:

1. Log into [dndbeyond.com](https://www.dndbeyond.com) in your browser.
2. Open dev tools → Application/Storage → Cookies → `https://www.dndbeyond.com`.
3. Copy the **`CobaltSession`** cookie value.
4. Paste it into the widget's settings pane (gear icon → paste field),
   or into `~/.config/omarchy-dndbeyond/config.json`:

   ```json
   { "cobaltSession": "PASTE_HERE" }
   ```

The helper exchanges the cookie for a short-lived API token (cached, auto-
refreshed). When the cookie expires (every few weeks), the card shows
"not authenticated" — paste a fresh one in the settings pane.

**Keep the cookie private.** `config.json` is mode 600. It grants full access
to your D&D Beyond account; never commit or share it.

### Characters the account list misses

The account list covers your own characters plus campaign rosters. For other
shared/private characters, add their IDs (from `dndbeyond.com/characters/<id>`)
in the settings pane's character list (add/remove rows), or as `characterIds`
in `config.json`. Names resolve automatically and are cached.

## Usage

| Key / action | Effect |
|---|---|
| `1`–`6`, `[` `]`, tab | switch tab |
| `c` | character picker |
| `s` | settings pane |
| `i` | roll initiative |
| `r` | refresh |
| arrows / wheel | scroll |
| click ability / skill / attack / damage chip | roll |
| click spell | expand details |
| click portrait | full-size zoom |
| esc / click outside | close |

## IPC

```bash
omarchy-shell brianstarke.dndbeyond toggle
omarchy-shell brianstarke.dndbeyond refresh
omarchy-shell brianstarke.dndbeyond select 167909431
omarchy-shell brianstarke.dndbeyond tab Spells
omarchy-shell brianstarke.dndbeyond rollInitiative   # rolls + pops the card
omarchy-shell brianstarke.dndbeyond rest short       # or long
omarchy-shell brianstarke.dndbeyond heal 3           # or damage 2
omarchy-shell brianstarke.dndbeyond status
```

Handy as a global keybind, e.g. in `~/.config/hypr/bindings.lua`:

```lua
o.bind { "SUPER SHIFT, I", exec = "omarchy-shell brianstarke.dndbeyond rollInitiative" }
```

## Settings

All settings live in the in-card pane, or via CLI:

```bash
omarchy bar set brianstarke.dndbeyond showHealth false
omarchy bar set brianstarke.dndbeyond colorHealth false
omarchy bar set brianstarke.dndbeyond showCharacterName true
omarchy bar set brianstarke.dndbeyond defaultTab Spells
omarchy bar set brianstarke.dndbeyond refreshIntervalSec 600
omarchy bar set brianstarke.dndbeyond width 520
omarchy bar set brianstarke.dndbeyond maxHeight 800
```

## Files

| File | Purpose |
|------|---------|
| `omarchy-dndbeyond-fetch` | python3 (stdlib only) helper: auth, list, sheet transform, rests |
| `Service.qml` | schedules the helper, config file watching, exposes models |
| `Panel.qml` | bar button + tabbed sheet card + settings pane |
| `tests/` | offline transform checks: `tests/run-tests.sh` |

## Developing

`install.sh` symlinks a checkout into `~/.config/omarchy/plugins/`, and the
shell's hot-reload watcher does not follow symlinks — after editing the QML,
reload with `omarchy restart shell` (manifest-only changes:
`omarchy-shell shell rescanPlugins`).

## Uninstall

```bash
omarchy plugin remove brianstarke.dndbeyond   # or ./uninstall.sh
```

The auth config is kept; delete it by hand if you want the cookie gone too:

```bash
rm -rf ~/.config/omarchy-dndbeyond
```
