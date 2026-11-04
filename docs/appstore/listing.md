# App Store listing: TruFocus 1.0

The App Store Connect metadata for the iPhone app and the Mac app. Every claim here was checked
against the code on `main` at `1da5526` (see "Claims checked" at the end). The sync and tone
claims were checked again after `1caee66` (end-to-end sync), `11f3952` (Direct default) and
`7721c30` (custom reminders), and the Mac drift guard and the TruFocus name after `306ac2f`. The copy for each field
sits in a code block so you can paste it as it is. Character counts include spaces and
were measured, not estimated.

> **Two app records, not one.** The iPhone app (`com.youngjingoh.truefocus`) and the Mac app
> (`com.youngjingoh.truefocus.mac`) have different bundle IDs, so App Store Connect treats them as
> two separate apps, each with its own name, privacy label and review. App names must be unique
> across the store, so the Mac record can't reuse the iPhone name word for word. If you want
> one name, one listing and one purchase for both, switch to **Universal Purchase**: give the Mac
> target the same bundle ID as the iPhone app in `project.yml`, and add macOS as a platform on the
> same record. Do this before the first upload, because it's painful to change afterwards. The Mac
> options below assume two records.

---

## 1. Name and subtitle

App Store Connect allows **30 characters** for the name and **30** for the subtitle. The counts
below include spaces and punctuation, and were measured.

### iPhone: name and subtitle (decided)

| | Text | Chars |
| --- | --- | --- |
| **Name** | `TruFocus: ADHD Hyperfocus` | 25 |
| **Subtitle** | `Focus timer & app blocker` | 25 |

The name is the product brief's decision. The subtitle changed from the brand line ("New-world
focus for ADHD") to the two things people search for, a focus timer and an app blocker, because the
brand line repeated "ADHD" and "focus" from the name and added no search weight. The website hero
("Designed to sustain your hyperfocus.") opens the promotional text and the description instead.

Notes on the pair:

- **"ADHD" names the audience, not a treatment.** Nothing in the copy says TruFocus diagnoses,
  treats or improves ADHD, and both descriptions end with a line saying it doesn't. Keep it that
  way (guideline 1.4.1 and the brief's voice rules: no medical claims, no "clinically proven", no
  shame words).
- **The subtitle repeats "ADHD" and "focus" from the name.** Apple indexes the name and subtitle
  together, so the repeat adds no search weight. That's acceptable because the subtitle is there
  for the voice. The words in both are left out of the keywords below.
- **Reserve the name early.** A small habit app called "True Focus" is already on the store
  (`docs/brand/README.md` §10). Names must be unique, so create the App Store Connect record before
  the screenshots are final.

Earlier options, kept only as fallbacks if the name is refused:

| Name | Chars | Subtitle | Chars |
| --- | --- | --- | --- |
| `TruFocus: Focus & App Blocker` | 29 | `Block feeds. Finish the task.` | 29 |
| `TruFocus — Momentum Planner` | 27 | `Momentum, not minutes.` | 22 |

### Mac: name and subtitle (for a future store record)

The Mac app ships as a Developer ID download (`docs/RELEASE.md`), so there's no Mac App Store record
today. Use the Mac copy below on the download page, and keep these for a store record later. A
second record can't reuse the iPhone name word for word.

| | Text | Chars |
| --- | --- | --- |
| **Name (recommended)** | `TruFocus for Mac: Deep Work` | 27 |
| Alt name | `TruFocus: Menu Bar Focus` | 24 |
| **Subtitle (recommended)** | `Knows what you're working on.` | 29 |
| Alt subtitle | `Menu bar focus. Feeds hidden.` | 29 |

With Universal Purchase, use the iPhone name and subtitle for both.

---

## 2. iPhone

Built on the website hero (`website/index.html`): "Designed to sustain your hyperfocus." and "Your
to-dos stay on screen. Social feeds are blocked. The timer is designed to keep your focus going."
The copy describes the one rule for feeds (#33): closed on a task, messages always open, open off a
task with a reminder.

### Promotional text (limit 170): 149 chars

```
Designed to sustain your hyperfocus. Your to-dos stay on screen, social feeds close while you work, and messages stay open. Rest as long as you need.
```

### Description (limit 4000): 3,527 chars

```
Designed to sustain your hyperfocus.

Your to-dos stay on screen. Social feeds are blocked. The timer is designed to keep your focus going.

TruFocus is made for brains that can lock onto a task for hours, or lose it to one swipe. It keeps your task in front of you, takes the feeds away while you work, and gives them back when you stop. No countdown cuts you off mid-flow: the clock counts up, and you keep going until it's done.

DUMP IT, THEN DO IT
• Dump everything on your mind. One box, no order, no rules.
• Make it a list. Every line becomes a task, exactly as you wrote it. Keep the dump in Notes too, so you can read it back days later.
• Attack. One task on screen, a clock counting up, and the moves you actually need: Done, Stuck, Waiting on it, Switch task.
• Juggle. Keep a few tasks in play in one Focus box. Each one remembers where you left off, so switching back costs nothing.

ONE RULE FOR FEEDS
The same rule on your iPhone, your Mac and your browser.
• On a task, the feed apps you pick are closed: Instagram, TikTok, YouTube, whatever pulls you in. The shield names your task and how long you've been on it.
• Messages stay open. Tap Message on the shield for a few minutes in the app, as often as you need. Made for people who run their business from their DMs.
• Off a task, everything opens again. Stay on a feed too long and TruFocus reminds you to get out. Want a hard stop instead? Turn on Lock me out.
• Always allowed: a booking, banking or work app is never shielded, even when its category is.

REST AND STOP
Pause holds the clock. Rest has no timer: break music plays until you're ready to resume. Stop ends the task for now and opens the feeds, with a reminder keeping an eye on the time.

ON YOUR LOCK SCREEN
A Live Activity and the Dynamic Island show your task and its clock, with Done, Stuck and Pause buttons that work without unlocking. Widgets, Control Center controls and Siri ("Done in TruFocus") too.

SOUND
Original TruFocus music, from driving focus tracks to Calm focus, plus break music for rests and soft cues for done and back-to-it. It keeps playing when the screen locks. Apple Music subscribers can play their own focus playlist.

NOTES
Headings, bullets, numbered lists, checklists, quotes and indents, with the formatting you already know, right beside your day.

YOUR VOICE
Choose how hard the nudges hit: Calm, Direct (the default) or Savage, which uses strong language and is opt-in. Or write every nudge in your own words.

SAFARI, TOO
The included Safari extension follows the same rule. On a task, Reels and Shorts are closed and messages stay open. Use Instagram, Facebook, YouTube or X for work, for research, pages or ads, with the feed hidden and a quick "working or scrolling?" check after two minutes. An adult-content filter takes 24 hours to turn off, so it's never an impulse decision.

IPHONE AND MAC
Optional end-to-end encrypted sync, off until you turn it on. Link your devices with a six-digit code, then check both screens show the same four-digit number. No account, no sign-up. No ads, no analytics, no tracking.

HONEST LIMITS
iOS doesn't let any app see inside another app, so on iPhone, native apps are guarded by time, not by what's on screen. Everything TruFocus switches on can be undone in iOS Settings. It's your device.

TruFocus is a focus tool made with ADHD brains in mind. It doesn't diagnose or treat ADHD or anything else.

Requires iOS 26 or later. Shields need Screen Time access, which you approve with Face ID or your passcode.
```

### Keywords (limit 100): 98 chars

```
to do list,planner,productivity,doomscroll,distraction,social media,app limit,brain dump,deep work
```

The keywords leave out words already in the name or subtitle (trufocus, adhd, hyperfocus, focus,
timer, app, blocker), because Apple indexes those anyway. They also leave out third-party trademarks
(Instagram, TikTok, YouTube, Reels, Shorts) and Apple's "Screen Time", which guideline 2.3.7 forbids
in keywords. "ADHD" is in the name as the audience; the keywords add no health or medical terms,
because the app makes no clinical claim. Two characters are spare.

### What's New in 1.0

```
The first release. Dump everything on your mind, make it a list, and attack one task at a time. One rule for feeds on iPhone, Mac and Safari: closed on a task, messages always open, a reminder when you linger off one. Rest with break music, Stop when you're done, notes with real formatting, Lock Screen Live Activity, and end-to-end encrypted sync with the Mac app.
```

(App Store Connect doesn't show "What's New" for a first version. Keep this for the 1.0 release
notes, or for 1.0.1 if you'd rather.)

### Categories

| | Category | Why |
| --- | --- | --- |
| **Primary** | Productivity | The task flow, juggling and scoreboard are the product, and the shields serve them. |
| **Secondary** | Lifestyle | This is where the digital-wellbeing and screen-time apps sit. |

Health & Fitness is another possible secondary category, but it pulls the app toward
"wellness" questions in review and in the age-rating questionnaire. Lifestyle avoids that.

### URLs and other fields

| Field | Value |
| --- | --- |
| Support URL (required) | `https://trufocus.vercel.app/support/` |
| Marketing URL (optional) | `https://trufocus.vercel.app/` |
| Privacy Policy URL (required) | `https://trufocus.vercel.app/privacy/` (the policy in `privacy.md` §3) |
| Copyright | `© 2026 Youngjin Koh` |
| Support email | `youngjingoh@gmail.com` |
| Price | Free, unless you decide otherwise. The code has no in-app purchase or subscription. |
| Sign-in required for review | **No.** There are no accounts. |

---

## 3. Mac

The Mac app has no Screen Time shields, no Live Activity and no widgets, so its copy doesn't mention them.
What it does have: the menu bar, global hotkeys, hiding blocked apps during focus, the scroll guard for
feed apps, the full-screen wake-up, the drift guard, the Safari extension, and the optional Shortcuts
hook for a macOS Focus.

### Promotional text (limit 170): 141 chars

```
One task in your menu bar. Feed apps hidden while you work. Drift off the task and a small card walks you back. Done is one hotkey away: ⌥⌘D.
```

### Description (limit 4000): 3,902 chars

```
Momentum, not minutes.

TruFocus lives in your menu bar, keeps one task in front of you, and takes the feeds away while you work. You attack a task until it's done, cross it off, take a short rest sized to the work, and the next task starts on its own. It isn't a pomodoro timer.

THE DAY
• Empty your head. A blank page every morning. Type everything.
• Keep what matters. The brain dump becomes a task list, sorted by Apple Intelligence on your Mac when it's available, or by a built-in parser when it isn't.
• Pick the win. One line: what makes today count.
• Attack. One task, a thin clock counting up, and four moves: Stuck, Waiting, Done, Switch.
• Rest, then go. A micro-rest sized to the work. Overrun it and the nudges escalate.
• Shut it down. A scoreboard of momentum, chain, focus time and boot-outs. Unfinished tasks roll to tomorrow.

IN THE MENU BAR
The mode, the current task and the minutes in, always in view. Click for Done, Stuck, Switch and quick-add. The hotkeys work from any app:
⌥⌘D Done · ⌥⌘S Stuck · ⌥⌘B Back to it · ⌥⌘K Next juggled task · ⌥⌘P Waiting on it · ⌥⌘T Show TruFocus

CUT THE FEED
• While you work, the Mac apps you pick are hidden the moment they come forward, with a quiet reminder of what you're on. Nothing is quit, nothing is changed.
• Feed apps get a scroll guard, including iPhone and iPad apps running on Apple silicon. TruFocus counts how far you scroll, never what's on screen. Skim, binge or linger, and a full-screen wake-up boots you out.
• The included Safari extension removes Reels and Shorts, opens Instagram straight to your DMs, keeps LinkedIn and Facebook to work, counts your swipes on feed sites, and blocks adult sites. Turning that filter off takes a 24-hour cool-off.

STAY ON THE TASK, NOT JUST OFF THE FEED
Blockers know which sites are bad. TruFocus knows what you're working on.
• When a task starts, say where it happens: the apps and sites it uses, and your first move.
• If something else holds the front for a minute or more, a small card asks if you want to head back: Back to it, Part of the task, or Switch task. Say it's part of the task and TruFocus remembers that for this task.
• The Safari extension adds the site and the tab's title. With your OK, TruFocus also reads window titles (macOS asks for Accessibility access), so a work doc and a side project in the same app look different.
• When the rules can't tell, Apple Intelligence decides on your Mac, if it's available.
• The menu bar panel shows today's time on task and time drifted.
It reads only app names, sites, and window and tab titles, on this Mac, while a task runs. No screenshots, no page contents, nothing uploaded. It's on by default, and one switch turns it off.

JUGGLE WITHOUT LOSING THE THREAD
Keep several tasks in play and switch with one tap or ⌥⌘K. Each one keeps a "where I left off" note.

YOUR TONE
Calm, Direct (the default) or Savage, which uses strong language and is opt-in. Choose how hard the nudges hit, or write your own words for any nudge.

SOUND
Optional studio cues, a calm river under rests, and three original focus tracks.

NOTES
Fast notes with headings, bullets and checklists.

WITH YOUR IPHONE
End-to-end encrypted sync, off until you turn it on. Link your devices once with a six-digit code and check that both screens show the same four-digit number. No account, no sign-up. Start a task on the Mac and it appears on your iPhone's Lock Screen. Your tasks, notes and timeline are sealed with a key that never leaves your devices. No ads, no analytics, no tracking.

HONEST LIMITS
TruFocus raises the walls; you own the Mac. Everything it does can be undone in Settings or by quitting it. For an extra layer, macOS's own Screen Time can limit adult websites. TruFocus shows you where.

TruFocus is a focus tool made with ADHD brains in mind. It doesn't diagnose or treat ADHD or anything else.

Requires macOS 26 or later.
```

**Lines to check before submitting the Mac copy:**

- The **Shortcuts / Focus** hook (`FocusModeBridge` runs `/usr/bin/shortcuts`) isn't in the copy
  above on purpose. A sandboxed Mac App Store build may not be able to launch that binary. Add the
  line "Optionally flips a macOS Focus when you start, so your iPhone goes quiet too" only after you've
  tested it in a sandboxed build.
- Don't add "works with Chrome, Arc, Brave and Edge" until the Chrome extension is live on the
  Chrome Web Store. Today the Mac app tells people to load it unpacked in developer mode. The drift
  guard copy names only the Safari extension for the same reason, although Chrome-family browsers
  report tabs too.
- **Window titles need Accessibility**, which a sandboxed Mac App Store build can't use
  (`docs/RELEASE.md`, "Mac: App Store or direct download"). The copy is right for the Developer ID
  download. For a store build, cut the sentence "With your OK, TruFocus also reads window titles…"
  and change "window and tab titles" in the last line to "tab titles".

### Keywords (Mac, limit 100): 92 chars

```
productivity,doomscroll,distraction,detox,planner,todo,timer,hotkey,brain dump,blocker,habit
```

(The Mac name has no "blocker", so it moves into the keywords here.)

### What's New in 1.0 (Mac)

```
The first release. A menu bar focus flow with global hotkeys, feed apps hidden while you work, a scroll guard with a full-screen wake-up, a drift guard that notices when you wander off the task, a Safari extension that takes the feed out of the web, and end-to-end encrypted sync with the iPhone app.
```

### Categories (Mac)

| | Category |
| --- | --- |
| **Primary** | Productivity |
| **Secondary** | Utilities. Menu bar apps are often browsed here, and the Mac App Store has no Lifestyle-style home for screen-time apps. |

URLs: the same as the iPhone app.

---

## 4. Claims checked, and claims left out on purpose

| Claim in the copy | Where it's backed |
| --- | --- |
| Off a task, a reminder after 15 min by default; Lock me out is opt-in | `TFSettings.scrollBudgetMinutes = 15`, `lockOutAtLimit = false`; `GuardShields.budgetReached` posts a reminder unless `lockOutAtLimit` |
| Message pass for a few minutes, as often as you need | `respondPassMinutes = 5`, `messagePassesUnlimited = true`; `GuardConfig.offersPass` offers it on every picked app during a task |
| Rest has no timer, with break music; Stop | `FocusScreen` Rest and Stop controls; `tf_music_rest.m4a` (#31) |
| Brain dump keeps every line; dump saved to Notes | `BrainDumpView` "Make it a list", "Also keep it in Notes" (#26, #32) |
| Adult filter on by default, 24-hour cool-off | `adultFilterEnabled = true`, `adultFilterCoolOffHours = 24` |
| Filter covers Safari and in-app browsers | `AdultFilter.apply`: `webContent.blockedByFilter = .auto(...)` |
| Apple Intelligence used on-device | `TaskExtractor` → `FoundationModels.LanguageModelSession` with fallback `BrainDump` |
| Live Activity buttons Done / Stuck / Pause | `FocusLiveActivity.swift` `LiveButton(intent: CompleteTaskIntent / StuckIntent / PauseIntent)` |
| Siri "Done in TruFocus" | `AppShortcuts.swift` phrases |
| Music keeps playing when locked | `UIBackgroundModes: audio`, `.playback` session while music or rest ambience plays |
| No ads, analytics or tracking | No third-party SDK: `Package.swift` has no dependencies, there are no analytics imports, and the only network calls are to Supabase, plus Apple's services (APNs from the server, MusicKit if chosen) |
| "End-to-end encrypted sync"; "sealed with a key that never leaves your devices" | `SyncCipher` seals payloads with AES-GCM under `HKDF(spaceKey, "payload.v1")`; requests carry only `SyncAccess.token`, `HKDF(spaceKey, "access.v1")`, and the server stores its SHA-256; `tf_records.data` holds ciphertext. The raw key travels once, in an older device's `tf-space` `rekey` move (no App Store build ever had the legacy paths) |
| "Off until you turn it on" | `SyncService.isEnabled` is false on a new install until *Turn on sync* or *Enter a code* (`SyncSettingsSection`). Devices that synced before stay on |
| "Six-digit code", "both screens show the same four-digit number" | `tf-pair` codes are six digits; `PairingSecret.session` derives a four-digit match number on both sides, and the host sends the sealed key only after *They match* |
| "Direct (the default)", Savage "uses strong language" and is opt-in | `TFSettings.tone = .direct`; `NudgeTone.savage.note` = "Strong language" |
| "Put any nudge in your own words, with {task}" | `CustomReminders` (ten moments, `{task}` placeholder), Settings ▸ *Your own words* (`CustomRemindersSection`) |
| Mac hides apps but quits nothing | `DistractionGuard` calls only `NSRunningApplication.hide()` |
| Mac scroll guard counts distance, not content | `ScrollWatch` reads `scrollingDeltaY` from a global scroll-wheel monitor, only while a listed feed app is frontmost |
| "When a task starts, say where it happens: the apps and sites it uses, and your first move" | `StartContractWindow` ("Where does … happen?": Apps, Sites, Topic words, First move, Done when), shown when a task starts on the Mac with no apps or sites yet (`DriftGuard.start`) |
| "For a minute or more", then a card: Back to it, Part of the task, Switch task | `DriftConfig.standard`: 90 s clearly off-task, 4 min unsure, both doubled in the 5-minute warm-up; `DriftPanel` buttons; the app's own copy says "more than a minute or two" |
| "Remembers that for this task" | `TaskContract.include` adds the host or app to that task's contract (`DriftGuard.partOfTask`) |
| "The Safari extension adds the site and the tab's title" | `core.js` `tabActivity` (host and title only, during focus), `SafariWebExtensionHandler` `activity` → App Group, read by `ActivityWatcher.latestTab` |
| "Reads window titles", "macOS asks for Accessibility access", "with your OK" | `ActivityWatcher.focusedWindowTitle` (AX), only when `AXIsProcessTrusted()`; the prompt comes only from Settings ▸ Guard ▸ Drift guard ▸ *Allow…* |
| "Apple Intelligence decides on your Mac, if it's available" | `DriftJudge.judge` → `LanguageModelSession`, only for `.unsure` verdicts with `macDriftUsesModel` on and `TaskExtractor.usesOnDeviceModel` |
| "The menu bar panel shows today's time on task and time drifted" | `MenuBarPanel` `DriftTodayLine`: "On task … · drifted …, mostly …" |
| "Only app names, sites, and window and tab titles … No screenshots, no page contents, nothing uploaded" | `ActivityWatcher` reads those three only; `DriftBook` lives in the App Group and isn't a sync record kind (`privacy.md` §1.5) |
| "On by default, and one switch turns it off" | `TFSettings.macDriftGuard = true`; Settings ▸ Guard ▸ Drift guard ▸ "Nudge me when I drift off the task" |
| "Blockers know which sites are bad. TruFocus knows what you're working on." | The positioning line: verdicts come from the task's own contract (`DriftClassifier.classify`), not from a block list alone |
| `TruFocus: ADHD Hyperfocus`, "made with ADHD brains in mind", "doesn't diagnose or treat ADHD" | Audience and brand line (`docs/brand/README.md`); the website footer says the same ("TruFocus is a focus tool. It doesn't diagnose or treat ADHD.") |

**Left out on purpose:**

- **"Even we can't see when you work"** or "zero knowledge". Record kinds, IDs and timestamps are
  in plain text on the server (`privacy.md` §1.3, caveat 1). "End-to-end encrypted" is accurate for
  the content; don't stretch it to the metadata.
- **"Linking can't be intercepted."** The four-digit match number, with its commitment step, leaves
  an attacking server one guess in 10,000 per link (`privacy.md` §1.3, caveat 4). "Linking is
  checked with a match number on both screens" is accurate; "impossible to intercept" isn't.
- **"Blocks Reels in the Instagram app."** It doesn't, and the README says so.
- **Any medical or outcome claim about ADHD:** "treats", "manages symptoms", "clinically proven",
  "science-backed", "doctor-approved". The name uses ADHD for the audience only. Keep shame words
  ("lazy", "no excuses", "weak moment", "procrastinator") out too; the adult-filter line now reads
  "so it's never an impulse decision".
- **"Watches everything you do"** or "knows exactly what you're doing" for the drift guard. It reads
  app names, window titles and tab sites and titles, nothing more, and only during focus.
- **Drift guard on iPhone.** It's Mac only. The iPhone copy doesn't mention it.
- **Specific scroll counts on iPhone native apps.** iPhone native apps are guarded by time only.
- **"Works without the app"** for the Chrome extension on the iPhone listing. Not relevant there.
- **Profanity.** Guideline 2.3.8 requires metadata suitable for a 4+ audience even when the app is
  rated higher. "Savage" is named, never quoted.
