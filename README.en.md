# Sempan 🧮

[한국어](README.md) | **English**

A deck-building roguelike where you defeat monsters with arithmetic.
Build equations from number and operator cards to deal damage, pick your path up a branching map, and grow your deck along the way.

The game itself is in Korean.

## How to play

- Pick numbers and operators from your hand, alternating between them, to build an equation of up to 5 cards (3 numbers, 2 operators).
- The equation is evaluated strictly left to right, and the result is dealt as damage to the monster.
- Bring the monster's HP to 0 within your limited number of calculations to win; otherwise the run ends.
- Each win earns gold and lets you choose a perk that upgrades your cards.

## Core systems

**Branching map**
Each act generates a random 10-floor map. Every floor has 1–3 paths, and you choose between monsters, elites and shops. Defeat the boss on floor 10 to move on to the next act.

**Economy**
Gold = kill reward + overkill gold + remaining calculations × rate + remaining discards × rate

- Overkill gold follows a logarithmic curve that flattens quickly, and it is capped.
- All rewards and shop prices grow exponentially along with enemy HP.
- A card bought in the shop replaces a card of the same kind in your deck, so the deck size never changes.

**Card enhancements**
| Enhancement | Effect |
|---|---|
| Gold | Final result ×2 |
| Fire | Adds a bonus to the final result |
| Luck | 25% chance of final result ×5 |
| Amplify (+) | Adds the right-hand number three times |
| Accumulate (+) | Adds a bonus that grows every time the card is used |
| Reversal (−) | If the subtraction would go negative, adds the two numbers instead and multiplies by 4 |
| Exact (÷) | If the division is exact, multiplies instead and doubles the result (numbers in hand that divide evenly glow) |

× cards are powerful but cannot be enhanced.

**Number transformations (unlocked per act)**
| Unlocked | Transformation | Input cap |
|---|---|---|
| Act 2 | Square n² | 20 |
| Act 3 | Power of two 2ⁿ | 15 |
| Act 4 | Natural exponent eⁿ | 12 |
| Act 5 | Factorial n! | 10 |

## Download and play

**Play now: https://sempan.vercel.app** (progress is saved in your browser)

Three builds are available on the [Releases](https://github.com/seamus08160816-droid/sempan_the_game/releases) page. All three share the same rules and balance.

| File | Platform | How to run |
|---|---|---|
| `sempan-<version>.html` | Web browser | Open the file in a browser (works offline) |
| `sempan-<version>.apk` | Android 7.0+ | Install on your phone (requires allowing apps from unknown sources) |
| `sempan-xcode-<version>.zip` | iOS · iPadOS · macOS · visionOS | Unzip, open `sempan_the_game.xcodeproj` in Xcode and run |

## Building from source

```bash
# iOS / macOS (Xcode)
open sempan_the_game.xcodeproj

# Web: embeds the Gaegu font into web/index.html and writes a single file, web/dist/sempan.html (pip install fonttools)
python3 web/build.py
# Web deploy (Vercel): upload web/dist after building
cd web/dist && npx vercel deploy --prod

# Android: an APK wrapping the web build in a WebView (Android SDK build-tools 35, JDK 11+)
android/build.sh 1.0.0-beta.1 1
```

The web and Android builds share the same `web/index.html`. When changing game rules, update both the Swift code (`Game/`) and the web code (`web/index.html`).

## Balance tuning

Most values live in `CFG` and the `Transform` enum at the top of `sempan_the_game/Game/GameModels.swift`. In the web build they are `CFG` and `TR` at the top of the script in `web/index.html`.

| Key | Meaning |
|---|---|
| `baseHP`, `actGrowth`, `growthAfter` | Floor 1 HP and the per-floor HP multiplier for each act |
| `econPow` | How closely rewards and prices track enemy HP |
| `goldA`, `goldK`, `goldCap` | Overkill gold curve |
| `playGold`, `discGold` | Gold per remaining calculation / discard |
| `fireBase`, `firePow` | Size of the Fire bonus |
| `Transform.cap` | Input cap for each transformation |

## Project layout

| Path | Contents |
|---|---|
| `Game/GameModels.swift` | Balance values, cards, enhancements, transformations, map, HP and economy formulas |
| `Game/GameSession.swift` | Map generation, combat and equation evaluation, perks, shop |
| `Game/Progress.swift` | Three save slots, achievements, card collection |
| `Views/` | Main menu, map, combat (fanned hand), shop, theme |
| `web/` | Web build (single HTML file) and the font-embedding build script |
| `android/` | Android WebView app that hosts the web build, plus its build script |

## Tech stack

- Swift, SwiftUI, Observation (no third-party libraries)
- Web: vanilla JavaScript, HTML and CSS (no third-party libraries); Android: Java WebView
- Progress is saved per slot (Apple: JSON files in Application Support/Saves; web and Android: localStorage)
- Light and dark mode, portrait and landscape, touch and mouse input
