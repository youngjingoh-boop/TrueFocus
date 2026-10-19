# Design

**Ink on warm paper. One hot accent that only ever means "you are working."**

## Principles

1. **One thing on screen.** The focus canvas shows a task, a clock and three moves. Nothing else earns a pixel.
2. **Outcome over activity.** The day starts with the win, not the list. The scoreboard counts finished things, not hours.
3. **Momentum is visible.** A chain of dots and a thin meter that rises with finished tasks and leaks with long rests and boot-outs.
4. **The interface gets out of the way.** No badges, no streak guilt, no confetti. A check, a soft haptic, the next task.
5. **Typography does the work.** Hierarchy comes from size and weight, not boxes and color.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `ink` | `#050506` | `#F4F3EE` | Text, solid controls (brand Ink / Paper) |
| `ink2` | `#6B6B70` | `#9A9AA0` | Secondary text |
| `ink3` | `#A9A9AE` | `#58585E` | Placeholders, empty circles |
| `paper` | `#F4F3EE` | `#0A0A0B` | Background (brand Paper) |
| `surface` | `#FFFFFF` | `#151517` | Cards |
| **Ember** `signal` | `#FF5A1F` | | Focus, Done, the live dot |
| Think | `#7C7CFF` | | Stuck / think time |
| Rest | `#34C98E` | | Micro-rest |

The immersive focus canvas is always night (`#050506`) with a faint wash of the mode color from the top.

## Type

System San Francisco throughout.

- Focus clock: 96 pt **Thin**, tabular digits. The clock should feel like it's barely there.
- Display: 34 pt Bold ("Today", "Empty your head.").
- Headline: 28 pt Semibold — the day's win and the task in focus.
- Eyebrows: 11 pt Semibold, tracked +1.4, uppercase.
- **Notes and task rows use the platform `body` style with default paragraph metrics** (17 pt on iPhone, 13 pt on Mac) — identical line height and spacing to Apple Notes. Note titles use `title1` bold, headings `title2` bold, as Notes does.

## Motion

Springs, never linear, except clocks. Check-off: a 0.28 s spring with a little overshoot and a success haptic. Mode changes cross-fade with a 2% scale. The rest ring breathes on a 4-second cycle.

## Voice

Short. Specific. Always names the task. Three tones — Calm, Direct (the default), Savage (opt-in, strong language) — chosen in settings. All copy lives in `Packages/TrueFocusKit/Sources/TrueFocusKit/Copy.swift`. Users can replace any moment's line with their own words (`CustomReminders.swift`); `Copy.apply(_:to:task:)` holds the one rule for where those words go.

## Icon

Ember Open, from the brand handover in `docs/brand` (v2.0): one ring, one point of light. A thin ring with a top-to-bottom gradient (`#FF7A40` → `#E2460E`) around a glowing core (`#FFE6D6` → `#FF9560` → `#FF5A1F`). Glow on dark, flat on light, and below 24 px the small cut: thicker solid ring, solid core. The iOS icon ships Any, Dark and Tinted appearances plus an alternate Paper icon (Settings ▸ App icon); the Mac icon, the menu bar template, the browser extension icons and the website's favicons all come from the same kit. In SwiftUI the mark is `TFMark`. The wordmark is outlined Geist SemiBold; use the lockup files, never live type.
