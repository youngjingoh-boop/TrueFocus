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
                 │                             │        │   ├ DriftGuard / DriftPanel    │
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

Each device keeps its own SwiftData store. `Shared/App/Sync/SyncService.swift` carries changes between them through Supabase (`supabase/`), end to end, with no user accounts. The server never holds the key the content is sealed with.

- **Spaces and keys.** A device belongs to a *space*, named by a random 256-bit *space key* in its Keychain (`SyncKeychain`, this device only, never iCloud Keychain). The key never goes to the server, apart from the one-time move below. Two keys are derived from it with HKDF-SHA256, salt `truefocus.sync` (`SyncSecrets.swift`):
  - **Access token** (`SyncAccess`, info `access.v1`, base64url). Every request carries it in `x-tf-space`. `tf_space()` hashes it, and row-level security shows only rows whose `space` equals `sha256(access token)`. It proves membership of the space, but it can't be turned back into the space key.
  - **Payload key** (`SyncCipher`, info `payload.v1`). Each payload is sealed with AES-GCM under this key. It can't be derived from the access token, so the server operator, a database dump and the request logs can't open anything.
- **Records.** One row per task, segment, day plan or note: `id`, `kind`, `deleted`, `modified_at`, and the sealed payload. The server sees that metadata in plain text, but never the content. Day plans get an ID derived from their day, so two devices' plans for one day are one record.
- **Moving off the legacy id.** Builds before access tokens stored a space under `sha256(space key)` and sent the raw key on every request. On its first sync after the update, each device calls `tf-space` (`rekey`) once. The request carries the raw key in `x-tf-space` (the last time it travels) and the access token in the body. The server copies the space's records and push tokens to the new id, merging by last writer wins (the `tf_records_stamp` trigger skips an older `modified_at`), and deletes the old rows. The move is remembered per key in `UserDefaults` (`tf.sync.access.<tag>`). Because it merges, the order the devices upgrade in doesn't matter. Spaces created by this build (or adopted by linking) are marked moved from the start and never send the raw key. Until every device in a space has updated, devices on the old build keep writing to the legacy id. They don't see the moved devices' edits until they update and move too.
- **Linking** (`PairingSecret`, `tf-pair`). The two devices swap X25519 public keys through the server, and the key travels sealed:
  1. `host`: the device that has the key opens a six-digit code with a commitment, `sha256` of its public key (single use, ten minutes).
  2. `join`: the other device claims the code and gets the commitment. Only then does it send its own public key (`offer`).
  3. `wait`, `reveal`: the host polls until the joiner's key appears, then reveals its own; the server and the joiner check it against the commitment.
  4. Both derive a box key and a four-digit **match number** from the shared secret, with `code|hostKey|guestKey` as the HKDF salt (infos `truefocus.pair.box.v1` and `truefocus.pair.match.v1`). Both screens show the number. On the host you confirm with *They match*.
  5. `seal`: only then does the host send the space key, AES-GCM-sealed under the box key.
  6. `fetch`: the joiner polls, opens the box and adopts the key, and the code row is deleted. The joiner's tasks and notes merge into the space on its next sync.

  The server sees only public keys and ciphertext. The order makes the number meaningful: the host publishes only `sha256` of its public key (`host`), the joiner claims the code and gets that commitment (`join`) before it sends its own key (`offer`), and the host reveals its key (`reveal`, checked against the commitment by the server and by the joiner) only after the joiner's is in. A server in the middle has to fix every key it shows either side before it can know the other side's number, so it gets one guess per link: the screens agree by chance 1 time in 10,000. Failed joins are counted globally, and `join` locks for everyone after 40 misses in ten minutes. The old `create`/`redeem` actions, which pass the raw key through the server, remain only for builds older than this one. New builds never call them, and they're due for removal (along with `tf_pairings.space_key`). A new build and an old build can't link to each other, so update both devices first.
- **Consent.** Sync is off on a new install. `SyncService.isEnabled` (`UserDefaults` `tf.sync.enabled`) turns on only when you tap *Turn on sync*, which makes the key, or when you link with *Enter a code*. While it's off, nothing is uploaded, no push token is registered, and *Link a device* turns sync on first. A device that synced before this release (its ledger names a space) stays on. A key alone doesn't count, because iOS keeps Keychain items after an app is deleted: a reinstall asks again, and *Turn on sync* then reuses that key. Settings ▸ Sync (`SyncSettingsSection`) also has:
  - **Turn off here.** It stops syncing on this device and keeps the key, so turning it back on carries on in the same space. The space's records and this iPhone's push token stay on the server.
  - **Delete server copy…** It calls `tf-space` (`delete`), which deletes every record and push token stored for the space. Then it turns sync off here, forgets the key and deletes the ledger. Other linked devices keep their own copies, and if they're still on, they upload their future edits again.
- **A sync** (on launch, foreground, every 20 s, 1.5 s after a save, on a silent push; only while sync is on): move off the legacy id if this key hasn't been moved yet, then pull rows newer than the cursor and decide each against the ledger (`SyncPlanner.resolve`). It takes the server's version unless this device edited the record since the last sync, in which case its edit wins. Day plans merge field by field against the last agreed version. Then it uploads what changed here. The server keeps the newer `modified_at` if two uploads race. Deletions are tombstones.
- **Wake-ups.** After an upload, `tf-notify` sends a silent push to the space's other iPhones (needs the APNs secrets, see SETUP), so they sync in the background. It finds them by hashing the access token, as `tf_space()` does.
- **Sync ID.** Settings shows the first 8 hex digits of `sha256(space key)`, the same on every linked device. It isn't the server's space id, which hashes the access token, so it can't be matched to rows on the server.

The decisions (`SyncPlanner`, `PlanPayload.merge`) and the wire client (`TFCloud`) are in TrueFocusKit and unit-tested; `SyncLiveTests` runs them against the real server when `TF_LIVE_SUPABASE_HOST` / `TF_LIVE_SUPABASE_KEY` are set. `PairingSecret`, `SyncAccess` and `SyncCipher` live in the app target (`Shared/App/Sync/SyncSecrets.swift`).

## TrueFocusKit

Foundation-only Swift package shared by every target and extension, tested on Linux:

- `Flow.swift` — modes, outcomes, `SegmentRecord`, `RestPolicy`.
- `DayStats.swift` — focus/think/rest totals, chain, momentum.
- `Nudges.swift` + `Copy.swift` — when to nudge and what to say, in three tones.
- `DoomScroll.swift` — the burst / binge / dwell detector (ported 1:1 to the extension's `core.js`).
- `NoteDocument.swift` — the plain-text note format (title, headings, bullets, checklists).
- `BrainDump.swift` — deterministic brain-dump → task list.
- `Blocklist.swift` — feed sites, short-form paths, respond paths, adult domains.
- `Drift.swift` — the drift guard's rules: start contracts, on/neutral/off-task classification, the dwell monitor (warm-up, re-nudge gap) and today's tally.
- `LiveSnapshot.swift`, `Settings.swift`, `SharedStore.swift` — the App Group contract.
- `Sync/` — sync payloads, the planner (what to upload, what to apply, merges), and the Supabase client.

## Enforcement

**iPhone** (`iOS/Guard`, `iOSExtensions/*`), all Screen Time APIs:
- `.focus` store — scroll apps + categories shielded while `snapshot.shouldShield`.
- `.scrollBudget` store — the Device Activity monitor shields scroll apps when the usage budget is spent, then lifts it after the cooldown and restarts the budget.
- `.adultFilter` store — `webContent.blockedByFilter = .auto(...)` while `settings.adultFilterActive()`.
- Shield UI names the current task; the secondary button grants a Post or reply pass on reply apps (5 min by default, warned a minute before it closes). The scroll budget warns 2 minutes before it shields.

**Mac** (`macOS/Guard`): frontmost-app guard during focus, scroll-stroke detector for native feed apps, full-screen wake-up overlay, optional Shortcuts hook to flip a shared Focus.

**Drift guard** (`macOS/Guard/DriftGuard.swift`): while a focus segment runs, every 3 seconds it samples the frontmost app, its window title (Accessibility) and the active tab (the extension posts host + title to `/activity` on the bridge, or Safari writes it to the App Group). `DriftClassifier` judges the sample against the task's start contract (apps, sites, topic words); what the rules can't place is judged by Apple's on-device model (`DriftJudge`) when available. `DriftMonitor` nudges only after sustained drift — 90 s, doubled in the first five minutes — with a card offering *Back to it*, *Part of the task* (learns the app or site) and *Switch task*. Only names and titles are read; nothing is stored beyond today's on-task / drifted tally.

**Browser** (`Extensions/web`): one MV3 extension. Declarative rules for short-form paths and adult domains; content script for SPA navigation, feed hiding, Instagram messages-only, and the scroll detector. State comes from the app — native messaging in Safari, `http://127.0.0.1:52525/state` from the Mac app for Chrome-family browsers.

## Why intents are compiled into the widget

Widget, Live Activity and Control buttons use the same `CompleteTaskIntent` etc. On iPhone they adopt `LiveActivityIntent`, which runs them in the app's process. If one ever runs in the extension (`TF_EXTENSION`), it queues a `RemoteCommand` in the App Group; the app drains the queue when it becomes active.
