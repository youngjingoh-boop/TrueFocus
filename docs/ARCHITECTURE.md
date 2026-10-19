# Architecture

```
                       ┌──────── Supabase (tf_records, encrypted per space) ──────┐
                       │      FocusTask · FlowSegment · DayPlan · Note            │
                       └───────────────▲──────────────────────────▲───────────────┘
                                       │ SyncService (HTTPS)      │
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

After each change it saves, refetches, builds a `LiveSnapshot`, writes it to the App Group, reloads widgets, and calls every registered `FocusEffect`. Changes pulled by sync trigger the same path, so the iPhone's shields, Lock Screen and Live Activity follow a session started on the Mac.

Auto-continue (start the next task when rest ends) only runs on the device that opened the rest, so two devices never both start it.

## Sync

Each device keeps its own SwiftData store. `Shared/App/Sync/SyncService.swift` carries changes between them through Supabase (`supabase/`), with no user accounts:

- **Spaces.** A device belongs to a *space*, named by a random 256-bit key in its Keychain. Every request sends it in `x-tf-space`; row-level security only shows rows whose `space` equals its SHA-256 (`tf_space()`). A new device joins with a six-digit code from `tf-pair`, single use, ten minutes, rate-limited.
- **Records.** One row per task, segment, day plan or note: `id`, `kind`, `deleted`, `modified_at`, and the payload sealed with AES-GCM under a key derived from the space key. The server never sees content. Day plans get an ID derived from their day, so two devices' plans for one day are one record.
- **A sync** (on launch, foreground, every 20 s, 1.5 s after a save, on a silent push): pull rows newer than the cursor, decide each against the ledger (`SyncPlanner.resolve`) — take the server's version unless this device edited the record since the last sync, in which case its edit wins; day plans merge field by field against the last agreed version — then upload what changed here. The server keeps the newer `modified_at` if two uploads race. Deletions are tombstones.
- **Wake-ups.** After an upload, `tf-notify` sends a silent push to the space's other iPhones (needs the APNs secrets, see SETUP), so they sync in the background.

The decisions (`SyncPlanner`, `PlanPayload.merge`) and the wire client (`TFCloud`) are in TrueFocusKit and unit-tested; `SyncLiveTests` runs them against the real server when `TF_LIVE_SUPABASE_HOST` / `TF_LIVE_SUPABASE_KEY` are set.

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
- `Sync/` — sync payloads, the planner (what to upload, what to apply, merges), and the Supabase client.

## Enforcement

**iPhone** (`iOS/Guard`, `iOSExtensions/*`), all Screen Time APIs:
- `.focus` store — scroll apps + categories shielded while `snapshot.shouldShield`.
- `.scrollBudget` store — the Device Activity monitor shields scroll apps when the usage budget is spent, then lifts it after the cooldown and restarts the budget.
- `.adultFilter` store — `webContent.blockedByFilter = .auto(...)` while `settings.adultFilterActive()`.
- Shield UI names the current task; the secondary button grants a Post or reply pass on reply apps (5 min by default, warned a minute before it closes). The scroll budget warns 2 minutes before it shields.

**Mac** (`macOS/Guard`): frontmost-app guard during focus, scroll-stroke detector for native feed apps, full-screen wake-up overlay, optional Shortcuts hook to flip a shared Focus.

**Browser** (`Extensions/web`): one MV3 extension. Declarative rules for short-form paths and adult domains; content script for SPA navigation, feed hiding, Instagram messages-only, and the scroll detector. State comes from the app — native messaging in Safari, `http://127.0.0.1:52525/state` from the Mac app for Chrome-family browsers.

## Why intents are compiled into the widget

Widget, Live Activity and Control buttons use the same `CompleteTaskIntent` etc. On iPhone they adopt `LiveActivityIntent`, which runs them in the app's process. If one ever runs in the extension (`TF_EXTENSION`), it queues a `RemoteCommand` in the App Group; the app drains the queue when it becomes active.
