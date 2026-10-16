# EllesmereUI Spell Rank

Shows the **rank of the spell on each action button** of the [EllesmereUI](https://www.curseforge.com/wow/addons/ellesmereui) action bars, and highlights buttons that hold a **lower rank than the highest one in your spellbook**.

Classic doesn't always update your action bars when you learn a new rank at the trainer, so it's easy to keep casting Frostbolt (Rank 2) without noticing. This add-on makes that visible at a glance.

> Unofficial add-on for EllesmereUI. It does not modify any EllesmereUI file. It attaches to the Action Bars module at runtime, and if anything it needs is missing, it stays off quietly.

![Spell Rank on action bars](screenshots/bars.png)

## Features

- **Rank label** on every button that holds a ranked spell (spells or macros that cast a spell)
- **Max Rank Checker**: the label switches to a warning color (red by default) when your spellbook has a higher rank of the same spell
- **Show Only Lower Ranks**: hide the label everywhere except on outdated buttons
- **Per-bar settings**: every bar is configured on its own, and the sync icon copies the settings to other bars
- **Position**: 9 anchor points plus X / Y offset
- **Font**: font face (or the Action Bars font), size and outline
- **Format**: `R3`, `3`, `Rank 3` or `3/5` (rank / max rank)
- **Background**: optional, with your own color, opacity and padding; it can also take the warning color on lower ranks
- **`/spellrank`**: lists every action slot holding a lower rank in chat, for example `Frostbolt  2 -> 3  (slot 1)`
- Settings are saved in your EllesmereUI profile, so they follow profile switches, import and export

## Requirements

- **WoW Forever** client (Interface 16001) or a 12.x client supported by EllesmereUI
- **EllesmereUI** with the **EllesmereUIActionBars** module enabled (built against v9.4)

## Installation

1. Download the latest release, or clone this repository.
2. Copy the `EllesmereUI_SpellRank` folder into
   `World of Warcraft\_classic_beta_\Interface\AddOns\` (or the `Interface\AddOns` folder of your client).
3. Make sure the folder name is exactly `EllesmereUI_SpellRank` and contains the `.toc` file directly, not inside a second subfolder.
4. Restart the game or `/reload`, then enable **EllesmereUI Spell Rank** in the add-on list.

## Usage

Open EllesmereUI → **Action Bars** → **Bar Display**, pick a bar, and scroll down to the **EXTRAS** section.

| Setting | What it does |
|---|---|
| Show Spell Rank | Turns the rank label on for the selected bar |
| Rank Font | Font face; the default follows the Action Bars font |
| Rank Text Size | Text size; the cog next to it sets position and X / Y offset |
| Rank Text Color | Color of a rank that is already your highest |
| Rank Text Outline | Action Bars default, Outline, Thick Outline or None (shadow) |
| Rank Format | `R3`, `3`, `Rank 3` or `3/5` |
| Rank Background | None or a custom color (the swatch sets color and opacity) |
| Background Padding | Space between the text and the edge of its background |
| Max Rank Checker | Highlights buttons that hold a lower rank than your spellbook |
| Lower Rank Color | Text color used for those buttons |
| Show Only Lower Ranks | Shows the label only on outdated buttons |
| Lower Rank Background | Also paints the background in the Lower Rank Color |

Stance and pet bars are skipped, because they don't hold ranked player spells.

Type `/spellrank` to list every outdated spell on your bars in chat.

## How it works

- The rank of a button comes from the spell's subtext (`Rank 3` → `3`). Spells without a numeric rank (Racial, Passive, single-rank abilities without a subtext) get no label.
- The highest known rank comes from a scan of your spellbook (spell name → highest rank). The scan is redone when you learn a spell, level up or change talents.
- Labels refresh when bars page, forms change, macros change or a button's action changes. Refreshes are batched, so a burst of events causes a single update.
- Labels are created out of combat. A button that appears during combat gets its label after combat ends.

## Works with EllesmereUI Spell Cost

This add-on shares the **EXTRAS** section with **EllesmereUI Spell Cost** (the mana / rage / energy cost label). With both installed you get one EXTRAS header, with Spell Cost first and Spell Rank below it. Each add-on works on its own as well.

If you use both, use **Spell Cost 1.1.0 or newer**. Older versions draw a second EXTRAS header.

Default positions don't collide: the rank goes top-left and the cost goes bottom-left.

## Troubleshooting

- **No EXTRAS section**: check that EllesmereUIActionBars is enabled and that this add-on is enabled in the add-on list.
- **A spell shows no rank**: the client returns no numeric rank for it. Please open an issue with the spell's name.
- **The checker doesn't flag a spell you know is outdated**: run `/spellrank`. If it isn't listed, please open an issue with the spell name and your class.
- **Errors**: install [BugGrabber](https://www.curseforge.com/wow/addons/bug-grabber) and [BugSack](https://www.curseforge.com/wow/addons/bugsack), and attach the error text to your issue.

## Files

```
EllesmereUI_SpellRank/
├── EllesmereUI_SpellRank.toc   add-on manifest
├── SpellRank.lua               runtime: labels, spellbook scan, /spellrank
└── SpellRank_Options.lua       settings rows in Action Bars > Bar Display > EXTRAS
```

## Changelog

### 1.0.0
- First release: rank label, Max Rank Checker, per-bar settings, `/spellrank`
