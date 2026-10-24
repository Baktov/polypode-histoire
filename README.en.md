# Polypode History (Polypode Histoire)

*Version française : [README.md](README.md)*

**Shared chronological journal** of all your characters for
[Polypode](https://github.com/Baktov/polypode), as a separate addon: logins, logouts, team
groups, delves, dungeons, Mythic+ keys, raid bosses, achievements, levels and item level, filed by
year, month and day.

Requires **Polypode**.

> **Languages**: French, English, German, Spanish, Italian and Brazilian Portuguese, following the
> language chosen in Polypode (option "Langue / Language"). The translations were made with the help
> of Claude, Anthropic's AI: feedback from native speakers is very welcome
> ([GitHub issue](https://github.com/Baktov/polypode-histoire/issues)).

---

## Installation

1. Install **Polypode** first (required dependency).
2. Download **`Polypode_Histoire-<version>.zip`** from the
   [latest release](https://github.com/Baktov/polypode-histoire/releases/latest) (not "Source
   code") and unzip it into `World of Warcraft/_retail_/Interface/AddOns/` (and into
   `_forever_/Interface/AddOns/` for WoW Forever): it directly contains the two folders,
   `Polypode_Histoire` and `Polypode_Histoire_Archive`, to keep as they are.
3. From the sources (git repository): **also** put the `Polypode_Histoire_Archive` subfolder
   directly in `Interface/AddOns/` (WoW does not read an addon stored inside another one; a
   `mklink /J` junction works).
4. Enable "Polypode History" and "Polypode Histoire Archive" in the AddOns list, **on each
   character**: each one records its own events and shares them with the others.

---

## Usage

The **History** button (Polypode title bar) or `/poly histoire` opens the journal window: a **Year >
Month > Day** tree, from the most recent to the oldest. **Click** on a year, a month or a day:
collapse or expand it (by default, only the current year, month and day are expanded; your choices
are kept). The **Collapse all** / **Expand all** button acts on the whole tree. The number of events
is given right of each year, month and day.

**Patch release** days (European server date) are shown **in green** right of the day, with the
patch name ("Wednesday, October 14  Patch 12.1.5 ..."), even with no event that day, in the months
shown; an announced upcoming patch is always shown, marked "(upcoming)" (Retail only). **Exp** box
at the bottom right of the window: show these patch and expansion days or not (checked by default).

**Filters** (boxes at the bottom left of the window, short labels, full name on hover): **Log.**
logins, **Ach.** achievements, **Del.** delves, **Dun.** dungeons (with M+ keys), **Rai.** raids
(entries included), **Col.** collections (toys, mounts, pets), **Rep.** renown and reputation and
**Soc.** social (friends, guilds, communities). No box checked (default): the whole journal;
otherwise, only the events of the checked categories, days without a kept event being hidden. The
choice is kept.

### Timeline

**List** / **Timeline** buttons at the top left of the window (choice kept). The **timeline** shows
the journal on a horizontal axis:

- **Scales** (buttons at the top right): **Day** (framed on the played range), **Week** (Monday to
  Sunday), **Month**, **All** (the whole current journal); **<** and **>**: previous or next period.
- **Event track**: one game icon per event, with a short text ("Lvl 84", "+12 ...", "Delve 11")
  when there is room; events too close together are grouped into one icon with a counter.
  **Hover**: the details (time of each character, full text); **click**: this day in the list.
- **Click elsewhere on the timeline** (area lit on hover, session bars included): in **Month**, the
  clicked week shows; in **Week**, the clicked day.
- **One track per character**: their play sessions in their class color (hover: "from 21:06 to
  00:20", duration), with the time played over the period next to the name.
- **Patch releases** (Retail, **Exp** box): green line and icon with a green border.
- **Importance** (**?** button): the longer the period, the fewer details shown. Weights: 3 raid
  boss, M+ key, level, mount; 2 achievement, dungeon, renown, guild; 1 delve, toy, pet, reputation,
  item level, friends, communities, team; 0 instance entry. Threshold: Day 0, Week 1, Month 2,
  All 3. **A category checked at the bottom of the window takes over**: all its events are shown,
  whatever the scale.
- The timeline follows the **width of the window** (grip at the bottom right): grouping is redone.

Within a day, events are in time order:

| Event | Example |
|---|---|
| Login / logout (with the time played since login) | 21:05 Mordsith logs in · 23:10 Mordsith logs out (2 h 05) |
| Team grouped in full (recorded by its leader) | 21:07 Team "Midnight" groups up (5 characters) |
| Entering a delve, a dungeon or a raid | 21:15 Mordsith, Darà enter the delve "The Well" |
| Delve completed (with the section for a delve in several parts) | 21:40 Mordsith, Darà complete the delve "The Well": "..." (tier 8, 25 min) |
| Dungeon completed (last boss) | 22:10 ... complete the dungeon "..." (Heroic, 32 min) |
| Mythic+ key completed (duration: timer) | 22:45 ... complete the key "..." +10 (in time, 28 min) |
| Raid boss defeated | 23:20 ... defeat "..." (raid, difficulty, 12 min) |
| Achievement (**click**: open the game's achievement window on it) | Mordsith earns the achievement "..." |
| Level | Darà reaches level 90 |
| Item level (no decimals, only when it goes above the highest known) | Corwin reaches item level 245 (+3) |
| Toy, mount, pet obtained | Mordsith obtains the mount "..." |
| Renown level | Mordsith reaches renown 12 with "..." |
| Friend added or removed (character, or Battle.net: with no character name, the account being shared) | Mordsith adds "Bob-Elune" as a friend · Battle.net friend added: "Zed" |
| Guild or community joined or left | Mordsith joins the guild "..." · Mordsith leaves the community "..." |
| Reputation rank reached (friendship included; only when going up, the first reading of a faction being the reference) | Mordsith becomes "Revered" with "..." |

The **duration** in brackets starts at the instance entry, or at the previous completion in the
same instance (delve section, previous raid boss); coming back into the instance less than 15
minutes after leaving it (death, exit) does not count as a new entry. Within a day, events go from
the **most recent to the oldest**, like the days.

The same event lived by several characters less than 5 minutes apart fits on **one line**; **on
hover**, each one's exact time.

**Right-click** on a line: **delete** it from the journal, after confirmation (all the characters of
the line), here and on the logged-in clients.

**Shared journal**: each character sends its events to the other logged-in clients, and sends again
those of its session to each client that logs in; all clients thus keep the same journal. A logout
is recorded as soon as it is requested (menu, `/logout`, `/quit`) and removed if it is cancelled;
`/reload` is not one. A **logout-login of less than 3 minutes** is not recorded (the character stays
logged in in the journal), nor a **session of less than 3 minutes** (login then logout).

### Journal size and export

The window header gives the number of events and the estimated size of the journal in its save
file. Beyond **2 MB**, it turns orange ("export advised") and a message reminds you at login; beyond
**5 MB**, red.

The **Export** button moves the days **before the previous month** (the current month and the
previous one are always kept) to the **archive**: the file
`WTF\Account\<account>\SavedVariables\Polypode_Histoire_Archive.lua`, held by the "Polypode
Histoire Archive" addon, loaded only at that moment (never at startup: it slows nothing down). The
archive is **added to** at each export, never replaced; the exported days are then removed from
the journal, here and on the logged-in clients. It is written at logout or `/reload` of the client
that exported.

### Data format

Journal (`PolypodeHistoireData`) and archive (`PolypodeHistoireArchive`) have the same format,
meant to be read by third-party software:

```lua
days = {
	["2026-10-11"] = {
		"1791745500~Mordsith-Elune~in",
		"1791747600~Mordsith-Elune~delve~Le Puits~8",
	},
},
deleted = { -- journal only (1.11.0): removed events, kept 120 days
	["1791746000~Mordsith-Elune~ach~1234"] = "D:1791750000", -- deleted by hand (right-click)
	["1791745400~Darà-Elune~in"] = "R:1791745500", -- removed automatically (session too short)
},
```

Software keeping its own history must remove the events listed in `deleted`.

Each event: `time~character~type~fields`, time = seconds since 1970 (server time), character =
`name-realm`, day = local date. Types and fields:

| Type | Fields |
|---|---|
| `in` / `out` | — |
| `grp` | team, number of members |
| `lvl` | level |
| `ach` | achievement ID |
| `ilvl` | new item level, old one |
| `delve` | delve name, tier ("0" in old events: unknown, not shown), section, duration (seconds) |
| `enter` | instance name, difficulty ID, kind (`delve` / `party` / `raid`) |
| `dng` | dungeon name, difficulty ID, duration |
| `mplus` | dungeon name, key level, in time (1 / 0), key upgrades, duration (timer) |
| `boss` | boss name, difficulty ID, raid name, duration |
| `toy` / `mount` / `pet` | ID (item, mount, pet species), name |
| `renown` | major faction ID, level, faction name |
| `friend` | name (BattleTag without number for a Battle.net friend), `+` / `-`, `c` (character) / `b` (Battle.net) |
| `guild` | guild name, `+` / `-` |
| `club` | community name, `+` / `-`, `c` / `b` |
| `rep` | faction ID, rank (text), faction name, rank number |

---

## Languages

Polypode History follows the language chosen in Polypode ("Langue / Language" option,
`/poly language`), by default the game's: French, English, German, Spanish, Italian or Brazilian
Portuguese (English for any other language). Choosing the language requires Polypode 2.9; with an
older Polypode, the module stays in French. The `/poly histoire` command keeps its name.

---

## Versions

The full version history is in the [French README](README.md#version).
