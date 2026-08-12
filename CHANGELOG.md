# Xal's Quest Compass - Changelog

## 1.3.0 - August 11, 2026

---

This one's mostly about how Quest Compass actually looks and feels, not new mechanics. I wanted it to stop looking like a stock, thrown-together addon and actually match the rest of what I build - so the whole options window got rebuilt from scratch with real sections instead of one long list, plus real color pickers, a new minimap icon, and an adjustable window scale. I also snuck in an experimental option for ElvUI users - it's new and not widely tested yet, so if something looks off with it on, let me know.

### 🆕 New
- **Redesigned Options window** - a real standalone window with sections (Home, Behavior, Automation, Font, Display) instead of one long settings list, matching the look of Xal's other addons.
- **Font Color and Text Shadow color pickers** - click a swatch to pick a custom color for either, or use your class color for the font.
- **UI Scaling** - adjust the whole window's size from the new Display section.
- **ElvUI Skinning (Experimental)** - if you use ElvUI, an opt-in toggle in Display lets the main quest window defer to ElvUI's own look instead. Off by default, requires ElvUI installed, applies on `/reload`. New and lightly tested - feedback welcome.
- **New minimap icon** - an owl gripping a compass, replacing the old design.
- Sliders now show their current value live as you drag them.

### 🔧 Improved
- Footer buttons (Route All, Track All, Untrack All, Navigate to Nearest) no longer crowd or overlap each other.
- The Font section's scrollbar now only appears when there's actually more content than fits.

### 🐛 Fixed
- Fixed an error that could break the Options window entirely on the current game patch (an old Blizzard function the addon relied on was removed).

## 1.2.0 - August 8, 2026

---

Route All: one click plans and walks you through every quest you have ready to turn in.

### 🆕 New
- **Route All** - computes an efficient multi-stop route through every quest ready to turn in, across every zone, and walks you through it. A live "Stop X/Y" readout with Skip and Cancel replaces the button while a route is active, and it auto-advances as you turn quests in. If an NPC has more than one of your ready quests, one visit clears all of them.
- On Retail, Route All covers every zone and continent. On Classic, it routes what's locatable in your current zone right now - click it again after traveling to pick up more.

## 1.1.1 - August 7, 2026

---

Reward previews, an optional ready sound, two new opt-in automation features, a couple of bug fixes, and support for MoP Classic and Classic Era.

### 🆕 New
- **Reward preview** - hover any quest in the list to see what it gives before you turn it in: money, guaranteed items, and any reward choices.
- **Ready sound** - an optional chime when a quest becomes ready to turn in. Off by default.
- **Auto turn-in** - automatically completes quests that don't require you to choose between rewards. Anything with a real choice to make, or that costs you money, is always left open so you can handle it yourself. Off by default.
- **Auto accept** - automatically accepts new quests offered by NPCs. A few quest types (escort, item-start, PvP-flagged) are always skipped and left for you, since they need special handling. Off by default.
- **MoP Classic and Classic Era support** - the addon now works on both Classic flavors, loading automatically alongside the existing Retail version. Distance and navigation are limited to your current zone on Classic (no precise cross-zone distance there), but detection, tracking, reward previews, and navigation all work.

### 🐛 Fixed
- **Navigate** no longer opens TomTom's options menu instead of setting a waypoint - it now points TomTom's arrow (or the built-in on-screen arrow, if TomTom isn't installed) straight at the quest turn-in.
- Fixed non-quest things (like Renown reward-track notifications) showing up in the ready-to-turn-in list as if they were real quests.
- Updated for the 12.1.0 game patch, so the addon no longer shows as "Out of Date".

### 🔧 Improved
- Holding **Shift** now pauses both auto turn-in and auto accept, instantly, at any time.
- All buttons (Track, Navigate, and the footer actions) now look like real buttons instead of plain clickable text, so they're much easier to spot.
- The Options window now scrolls, so nothing ever gets cut off as more settings are added.
- New installs now default to: All Zones shown, the window auto-opening when a quest becomes ready, and a smaller starting window scale. All still adjustable in Options.
