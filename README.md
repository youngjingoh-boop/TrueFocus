# TrueFocus

**Momentum, not minutes.** A focus system for iPhone and Mac that keeps one task in front of you, takes the feeds away while you work, and pulls you back when you drift.

Not pomodoro. You attack a task until it's done. When you're stuck you switch to *think* without leaving it. When it's done you cross it off and get a micro-rest sized to the work — seconds for an email, a couple of minutes for a long build — and the next task starts on its own.

---

## The day

1. **Empty your head.** A blank page every morning. Type everything.
2. **Keep what matters.** The dump becomes a task list — sorted by the on-device Apple Intelligence model when your device has it, by a deterministic parser when it doesn't. Untick the noise.
3. **Pick the win.** One line: what makes today count.
4. **Attack.** One task on screen. A thin clock counting up. Three moves: **Stuck · Done · Switch.**
5. **Rest, then go.** A breathing ring counts the micro-rest down. Overrun it and the nudges escalate — in your choice of tone. *Savage* says exactly what you asked for: "Wake the fuck up."
6. **Shut it down.** A scoreboard — momentum, chain, focus time, boot-outs — and a line of reflection. Unfinished tasks roll to tomorrow.

Hold up to three tasks **in play** for parallel work and switch with one tap. Each keeps a breadcrumb — "where I left off" — so switching back costs nothing.

## Everywhere you look

| Surface | What it shows |
| --- | --- |
| **Mac menu bar** | Mode glyph, the current task, minutes in. Click for Done / Stuck / Switch / quick-add. |
| **iPhone Lock Screen** | Live Activity with the task and a live clock, plus a Lock Screen widget. Buttons work without unlocking. |
| **Dynamic Island** | Mode and timer; expand for the task and Done. |
| **Home Screen widget** | Task, clock, progress, momentum, Done / Stuck. |
| **Control Center & Action Button** | "Done" and "Next Task" controls; Siri: "Done in TrueFocus". |
| **The shield** | When a blocked app opens: "Wake up. You're 23 min into ‘Investor update’." |

Everything syncs through the TrueFocus server, end-to-end encrypted, no account and no iCloud storage. Link your devices once with a six-digit code, then start on the Mac and see it on the iPhone Lock Screen.

## Cutting out distractions

| | iPhone | Mac |
| --- | --- | --- |
| **During focus** | Apps you pick (Instagram, YouTube, TikTok, X…) are shielded by Screen Time. | Apps you pick are hidden the moment they come forward. |
| **Doom-scroll guard** | Screen Time usage budget: after *N* minutes in your scroll apps you're booted out for a cooldown. | Native feed apps: scroll strokes are counted; skim, binge or linger and you're booted out with a full-screen wake-up. |
| **Browser** | Safari extension: scroll strokes counted on feed sites; Reels, Shorts and TikTok removed; Instagram opens to your DMs only. | Same extension in Safari, Chrome, Arc, Brave, Edge. |
| **Still need to reply** | Shield button **Reply · 2 min** on apps you mark as messaging apps (limited passes per day). | Instagram web stays usable for DMs, minus the feed. |
| **Notifications** | Use a system Focus with the TrueFocus filter; with *Share Across Devices*, turning it on from the Mac silences and shields the iPhone too. | Optional Shortcuts hook flips the Focus when a session starts. |
| **Adult sites** | On by default: Screen Time web-content filter + the extension's blocklist. Turning it off takes a 24-hour cool-off. | The extension's blocklist, plus a guide to macOS's built-in filter. |

### Honest limits

- iOS doesn't let any app see inside another app, so on iPhone **native** apps are guarded by time budgets, not scroll counts. Scroll counting runs in browsers and in feed apps on the Mac.
- Reels can't be removed from inside the Instagram iPhone app. The playbook: shield the app during work, and reply from instagram.com in Safari, where the extension strips Reels, Explore and the feed.
- TrueFocus raises the walls; you own the device. Everything can be undone through system settings. For an extra layer, switch on Screen Time's own *Limit Adult Websites* on both devices — the setup guide shows where.

## Build it

You need a Mac with Xcode 26+, an iPhone on iOS 26+, and a paid Apple Developer account (Screen Time APIs and App Groups require one). Signing is preset to the VocaMonkey team (`7CVSS54KS4`) in `Config/Base.xcconfig`.

```sh
brew install xcodegen
xcodegen
open TrueFocus.xcodeproj
```

Run **TrueFocus** on your iPhone and **TrueFocusMac** on your Mac. Then follow [docs/SETUP.md](docs/SETUP.md) — ten minutes of one-time switches (Screen Time access, the Safari extension, the Focus filter, linking devices). To put it on a partner's or friend's phone without the App Store, see [docs/SHARING.md](docs/SHARING.md).

## Inside

```
Packages/TrueFocusKit   Pure Swift: flow engine, momentum, nudges, doom-scroll detector, note format. Unit-tested on Linux.
Shared/                 SwiftUI app shared by iPhone and Mac: Today, Focus, Brain dump, Notes, Review, Settings, intents.
iOS/                    iPhone app shell, Screen Time guard, nudges, Live Activity controller.
iOSExtensions/          Widgets + Live Activity + Controls, Device Activity monitor, shield UI and actions.
macOS/                  Menu bar, window, wake-up overlay, distraction guard, scroll watch, hotkeys.
Extensions/web          One Manifest V3 extension for Safari (bundled) and Chrome (load unpacked).
supabase/               Sync server: tables + row-level security, device-link and wake-up edge functions.
```

More in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/DESIGN.md](docs/DESIGN.md).

```sh
swift test --package-path Packages/TrueFocusKit   # core logic
(cd Extensions/web && npm test)                    # extension logic
```
