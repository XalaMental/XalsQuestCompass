# Xal's Quest Compass

A World of Warcraft addon that lists quests ready to turn in, sorted by
distance, with one-click TomTom/SuperTrack navigation.

## Features

- **Ready-to-turn-in list** — automatically detects every completed quest in your log
- **Zone filter** — shows only turn-ins in your current zone by default, with a one-click toggle to see everything
- **Live distances** — sorted nearest-first
- **One-click navigation** — uses TomTom's `/way` command if installed, falls back to WoW's native SuperTrack arrow otherwise
- **Quest tracking** — add/remove any turn-in from your objective tracker without leaving the window
- **Auto-show** — optionally pop the window open the moment a quest becomes ready, anywhere in your log
- **Resizable window** — drag the corner grip; position and size are remembered
- **Full appearance customization** — font, size, outline, shadow, class-color titles, window scale
- **Minimap button** — left-click to toggle, right-click for settings

## Commands

| Command | Effect |
|---|---|
| `/xqc` | Toggle the window |
| `/xqc show` / `/xqc hide` | Show or hide explicitly |
| `/xqc nav` | Navigate to the nearest ready quest |
| `/xqc options` | Open settings |

## Installation

1. Download the latest release.
2. Extract the `XalsQuestCompass` folder into `World of Warcraft/_retail_/Interface/AddOns/`.
3. Restart WoW or `/reload`.

## License

All Rights Reserved -- see [LICENSE.md](LICENSE.md).

The bundled font (`Fonts/CustomFont.ttf`, "Simply Sans") is licensed
separately under the SIL Open Font License -- see
[Fonts/SimplySans-LICENSE.txt](Fonts/SimplySans-LICENSE.txt).
