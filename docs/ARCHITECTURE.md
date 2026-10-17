# Architecture

```
                       ┌────────────── iCloud (private CloudKit DB) ──────────────┐
                       │      FocusTask · FlowSegment · DayPlan · Note            │
                       └───────────────▲──────────────────────────▲───────────────┘
                                       │ SwiftData sync           │
                 ┌─────────────────────┴───────┐        ┌─────────┴─────────────────────┐
                 │ iPhone app                  │        │ Mac app                        │
                 │  FocusController ──effects──┤        ├──effects── FocusController     │
                 │   ├ ScreenTimeGuard         │        │   ├ DistractionGuard           │
                 │   ├ NudgeScheduler          │        │   ├ ScrollWatch                │
                 │   └ LiveActivityController  │        │   ├ MacNudger / WakeUpOverlay  │
                 │        │ LiveSnapshot        │        │   └ FocusModeBridge            │
                 │        ▼ (App Group)         │        │        │ LiveSnapshot          │
                 │  Widgets · Live Activity    │        │        ▼ (App Group + :52525)  │
                 │  Shield UI · Shield actions │        │  Menu bar · Safari/Chrome ext. │
                 │  Device Activity monitor    │        │                                │
                 │  Safari extension           │        │                                │
                 └─────────────────────────────┘        └────────────────────────────────┘
```

## One timeline

A day is a list of **segments** — contiguous blocks of one mode (`focus`, `think`, `rest`). The open segment *is* the current state. There's no separate "status" record to conflict: if two devices each open a segment, the newest wins and the other is closed as `superseded`. A segment left open overnight is closed at the day boundary (4 am).

Every number on the scoreboard — focus time, chain, momentum — is replayed from the segments by `DayStats.compute`, a pure function in TrueFocusKit.

## FocusController

`Shared/App/FocusController.swift` is the only writer. Views and intents call its verbs:

| Verb | Effect |
| --- | --- |
| `start(task)` | Close the open segment (`switched`/`resumed`), open `focus` on the task, put it in play. |
| `stuck()` | `focus` → `think` on the same task. |
| `complete()` | Close with `completed`, cross the task off, open `rest` sized by `RestPolicy`. |
| `backToIt()` | `think` → `focus` same task; `rest`/idle → `focus` next task. |
| `endDay()` | Close everything, mark the plan ended. Nudges stop. |

After each change it saves, refetches, builds a `LiveSnapshot`, writes it to the App Group, reloads widgets, and calls every registered `FocusEffect`. Remote iCloud changes trigger the same path, so the iPhone's shields, Lock Screen and Live Activity follow a session started on the Mac.

Auto-continue (start the next task when rest ends) only runs on the device that opened the rest, so two devices never both start it.

## TrueFocusKit

Foundation-only Swift package shared by every target and extension, tested on Linux:

- `Flow.swift` — modes, outcomes, `SegmentRecord`, `RestPolicy`.
- `DayStats.swift` — focus/think/rest totals, chain, momentum.
- `Nudges.swift` + `Copy.swift` — when to nudge and what to say, in three tones.
- `DoomScroll.swift` — the burst / binge / dwell detector (ported 1:1 to the extension's `core.js`).
- `NoteDocument.swift` — the plain-text note format (title, headings, bullets, checklists).
- `BrainDump.swift` — deterministic brain-dump → task list.
- `Blocklist.swift` — feed sites, short-form paths, respond paths, adult domains.
- `LiveSnapshot.swift`, `Settings.swift`, `SharedStore.swift` — the App Group contract.

## Enforcement

**iPhone** (`iOS/Guard`, `iOSExtensions/*`), all Screen Time APIs:
- `.focus` store — scroll apps + categories shielded while `snapshot.shouldShield`.
- `.scrollBudget` store — the Device Activity monitor shields scroll apps when the usage budget is spent, then lifts it after the cooldown and restarts the budget.
- `.adultFilter` store — `webContent.blockedByFilter = .auto(...)` while `settings.adultFilterActive()`.
- Shield UI names the current task; the secondary button grants a short Reply pass on reply apps.

**Mac** (`macOS/Guard`): frontmost-app guard during focus, scroll-stroke detector for native feed apps, full-screen wake-up overlay, optional Shortcuts hook to flip a shared Focus.

**Browser** (`Extensions/web`): one MV3 extension. Declarative rules for short-form paths and adult domains; content script for SPA navigation, feed hiding, Instagram messages-only, and the scroll detector. State comes from the app — native messaging in Safari, `http://127.0.0.1:52525/state` from the Mac app for Chrome-family browsers.

## Why intents are compiled into the widget

Widget, Live Activity and Control buttons use the same `CompleteTaskIntent` etc. On iPhone they adopt `LiveActivityIntent`, which runs them in the app's process. If one ever runs in the extension (`TF_EXTENSION`), it queues a `RemoteCommand` in the App Group; the app drains the queue when it becomes active.
