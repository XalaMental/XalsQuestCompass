# Xal's Quest Compass - Changelog

## Release 1.1.1 - August 7, 2026

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
