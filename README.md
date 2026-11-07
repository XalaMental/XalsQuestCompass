# Xal's Quest Compass

A World of Warcraft addon that lists quests ready to turn in, sorted by
distance, with one-click TomTom/SuperTrack navigation. Runs on Retail, MoP
Classic, Classic Era, and WoW Forever.

## Features

- **Floating alert icon** — a small icon that stays dark until a quest is ready, then glows; hover it for the list, click it to open the full window (the minimized bar is still available as an option)
- **Ready-to-turn-in list** — automatically detects every completed quest in your log, one at a time, nearest first
- **Zone filter** — one-click toggle between This Zone Only and All Zones
- **Live distances** — shown on Retail; on Classic and Forever, quests in your current zone show as "nearby"
- **One-click navigation** — uses TomTom's `/way` command if installed, falls back to WoW's native SuperTrack arrow otherwise
- **Route All** — plans a multi-stop route through every ready quest and walks you through it stop by stop
- **Quest tracking** — add/remove any turn-in from your objective tracker without leaving the window
- **Reward preview** — hover a quest to see its money, XP, items, and reward choices
- **Reset warning** — a ready daily or weekly quest warns you once it's under an hour from resetting
- **Auto-show** — optionally pop the window open the moment a quest becomes ready
- **Optional automation** — auto turn-in, auto accept, and a ready sound, all off by default; hold Shift to pause them
- **Full appearance customization** — font, size, outline, shadow, class-color text, window scale, optional ElvUI skinning
- **Minimap button** — left-click for settings, right-click to toggle the quest list

## Commands

| Command | Effect |
|---|---|
| `/xqc` | Toggle the window |
| `/xqc show` / `/xqc hide` | Show or hide explicitly |
| `/xqc nav` | Navigate to the nearest ready quest |
| `/xqc options` | Open settings |

## Installation

1. Download the latest release.
2. Extract the `XalsQuestCompass` folder into your game's `Interface/AddOns/` folder (for example `World of Warcraft/_retail_/Interface/AddOns/`).
3. Restart WoW or `/reload`.

## License

All Rights Reserved -- see [LICENSE.md](LICENSE.md).

The bundled fonts are licensed separately under their own open-source
licenses -- see [LICENSE.md](LICENSE.md) and the license files in `Fonts/`.
