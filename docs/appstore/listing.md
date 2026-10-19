# App Store listing: TrueFocus 1.0

The App Store Connect metadata for the iPhone app and the Mac app. Every claim here was checked
against the code on `main` at `1da5526` (see "Claims checked" at the end). The copy for each field
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

### iPhone: name options (limit 30)

| # | Name | Chars | Notes |
| --- | --- | --- | --- |
| **A (recommended)** | `TrueFocus: Focus & App Blocker` | 30 | Says what it is in the two terms people search for. "App Blocker" is fair: Screen Time shields block the apps during focus. |
| B | `TrueFocus: Deep Work Timer` | 26 | Calmer, but "timer" undersells the shields and invites a pomodoro comparison the app rejects. |
| C | `TrueFocus — Momentum Planner` | 28 | On brand ("Momentum, not minutes"), but nobody searches for "momentum". |

### iPhone: subtitle options (limit 30)

| # | Subtitle | Chars | Notes |
| --- | --- | --- | --- |
| **A (recommended)** | `Block feeds. Finish the task.` | 29 | Blunt, two verbs, and it names the outcome. It also covers "block" and "task" for search. |
| B | `One task. No feeds. No excuses.` | 31 | **Too long by 1.** Shown only so you don't reach for it. |
| B′ | `One task. No feeds. Go.` | 23 | Punchy, but less searchable. |
| C | `Momentum, not minutes.` | 22 | The README's tagline. Best kept for the promotional text and the first line of the description. |

**Recommendation:** name **A** with subtitle **A**. The name carries the category terms, the
subtitle carries the attitude, and neither repeats the other's words, so all 100 keyword characters
are free for other terms.

> Check that the name is free in App Store Connect before you commit to it. "TrueFocus" may already
> be taken, and I couldn't check that from here. If it is, `TrueFocus — Momentum Planner` or
> `True Focus: Feed Blocker` (24) are the next best choices.

### Mac: name and subtitle (two-record setup)

| | Text | Chars |
| --- | --- | --- |
| **Name (recommended)** | `TrueFocus for Mac: Deep Work` | 28 |
| Alt name | `TrueFocus: Menu Bar Focus` | 25 |
| **Subtitle (recommended)** | `Menu bar focus. Feeds hidden.` | 29 |
| Alt subtitle | `One task. Hotkeys. No feeds.` | 28 |

With Universal Purchase, use the iPhone name and subtitle for both.

---

## 2. iPhone

### Promotional text (limit 170): 148 chars

```
One task on screen. The feeds out of reach. Nudges that get blunter the longer you drift. Start the day with a blank page, end it with a scoreboard.
```

### Description (limit 4000): 3,738 chars

```
Momentum, not minutes.

TrueFocus keeps one task in front of you, takes the feeds away while you work, and pulls you back when you drift. It isn't a pomodoro timer. You attack a task until it's done, cross it off, take a short rest sized to the work, and the next task starts on its own.

THE DAY
• Empty your head. A blank page every morning. Type everything.
• Keep what matters. The brain dump becomes a task list, sorted by Apple Intelligence on your iPhone when it's available, or by a built-in parser when it isn't. Untick the noise.
• Pick the win. One line: what makes today count.
• Attack. One task on screen, a thin clock counting up, and four moves: Stuck, Waiting, Done, Switch. Pause stops the clock and drops the shields; Resume carries on from the same second.
• Rest, then go. A breathing ring counts down a micro-rest: seconds for an email, a few minutes for a long build. Overrun it and the nudges escalate.
• Shut it down. A scoreboard of momentum, chain, focus time and boot-outs, plus one line of reflection. Unfinished tasks roll to tomorrow.

JUGGLE WITHOUT LOSING THE THREAD
Keep several tasks in play and switch with one tap. Each one keeps a "where I left off" note, so switching back costs nothing. Waiting on someone? Park the task and move to the next.

CUT THE FEED
With your permission, TrueFocus uses Apple's Screen Time framework on this iPhone.
• While you work, the apps you pick are shielded. The shield names your task and how long you've been on it.
• Outside focus, those apps run on a daily scroll budget, 5 minutes by default. Spend it and you're locked out for a cooldown.
• Apps you mark for replies get a short Reply pass on the shield: two minutes to answer messages, a few times a day.
• An adult-content filter covers Safari and in-app browsers and is on by default. Turning it off takes a 24-hour cool-off, so you never make that call in a weak moment.

SAFARI WITHOUT THE SCROLL
The included Safari extension removes Reels and Shorts, closes TikTok except messages, opens Instagram straight to your DMs, and keeps LinkedIn and Facebook to work: messages, pages and ad tools stay open, the feed doesn't. On feed sites it counts your swipes. Skim, binge or linger, and it boots you out.

ON YOUR LOCK SCREEN
A Live Activity and the Dynamic Island show the task and a live clock, with Done, Stuck and Pause buttons that work without unlocking. There are widgets for the Home Screen and Lock Screen and controls for Control Center and the Action Button, and Siri understands "Done in TrueFocus".

YOUR TONE
Choose how hard the nudges hit: Calm, Direct or Savage. Savage doesn't soften anything.

SOUND
Optional studio cues for done, rest and back-to-it, a calm river under rests, and three original focus tracks that keep playing when the screen locks. Apple Music subscribers can play a focus playlist instead.

NOTES
Fast notes with headings, bullets and checklists, right beside your day.

IPHONE AND MAC
Link your devices once with a six-digit code. There's no account and no sign-up. Start a task on the Mac and it appears on your iPhone's Lock Screen. Your tasks, notes and timeline are encrypted on your device before they're uploaded, and the sync server stores only the encrypted copy. No ads, no analytics, no tracking.

HONEST LIMITS
iOS doesn't let any app see inside another app, so on iPhone, native apps are guarded by time, not by counting scrolls. Reels can't be removed from inside the Instagram app. Shield the app, and reply from instagram.com in Safari instead. Everything TrueFocus switches on can be undone in iOS Settings. It's your device.

Requires iOS 26 or later. The shields and the filter need Screen Time access, which you approve with Face ID or your passcode.
```

### Keywords (limit 100): 100 chars

```
deep work,productivity,doomscroll,distraction,detox,social media,planner,todo,timer,brain dump,habit
```

The keywords leave out words already in the name or subtitle (truefocus, focus, app, blocker,
block, feeds, finish, task), because Apple indexes those anyway. They also leave out third-party
trademarks (Instagram, TikTok, YouTube, Reels, Shorts) and Apple's "Screen Time", which guideline
2.3.7 forbids in keywords. They avoid health and medical terms such as "ADHD", because the app makes
no clinical claim and the term would invite one. If you swap one keyword out, "discipline" (10) and
"lock" (4) are the strongest spares.

### What's New in 1.0

```
The first release. Empty your head, pick the win, attack one task at a time. Screen Time shields, a daily scroll budget, an adult-content filter with a 24-hour cool-off, and a Safari extension that takes the feed out of Instagram, YouTube, Facebook and LinkedIn. Lock Screen Live Activity, widgets, and sync with the Mac app.
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
| Support URL (required) | `https://[WEBSITE]/support` |
| Marketing URL (optional) | `https://[WEBSITE]` |
| Privacy Policy URL (required) | `https://[WEBSITE]/privacy` (host the policy in `privacy.md` §2 there) |
| Copyright | `© 2026 [LEGAL NAME OF SELLER]` |
| Price | `[DECIDE]`. The code has no in-app purchase or subscription. |
| Sign-in required for review | **No.** There are no accounts. |

---

## 3. Mac

The Mac app has no Screen Time shields, no Live Activity and no widgets, so its copy doesn't mention them.
What it does have: the menu bar, global hotkeys, hiding blocked apps during focus, the scroll guard for
feed apps, the full-screen wake-up, the Safari extension, and the optional Shortcuts hook for a
macOS Focus.

### Promotional text (limit 170): 142 chars

```
One task in your menu bar. Feed apps hidden while you work. A full-screen wake-up when you start doom-scrolling. Done is one hotkey away: ⌥⌘D.
```

### Description (limit 4000): 2,672 chars

```
Momentum, not minutes.

TrueFocus lives in your menu bar, keeps one task in front of you, and takes the feeds away while you work. You attack a task until it's done, cross it off, take a short rest sized to the work, and the next task starts on its own. It isn't a pomodoro timer.

THE DAY
• Empty your head. A blank page every morning. Type everything.
• Keep what matters. The brain dump becomes a task list, sorted by Apple Intelligence on your Mac when it's available, or by a built-in parser when it isn't.
• Pick the win. One line: what makes today count.
• Attack. One task, a thin clock counting up, and four moves: Stuck, Waiting, Done, Switch.
• Rest, then go. A micro-rest sized to the work. Overrun it and the nudges escalate.
• Shut it down. A scoreboard of momentum, chain, focus time and boot-outs. Unfinished tasks roll to tomorrow.

IN THE MENU BAR
The mode, the current task and the minutes in, always in view. Click for Done, Stuck, Switch and quick-add. The hotkeys work from any app:
⌥⌘D Done · ⌥⌘S Stuck · ⌥⌘B Back to it · ⌥⌘K Next juggled task · ⌥⌘P Waiting on it · ⌥⌘T Show TrueFocus

CUT THE FEED
• While you work, the Mac apps you pick are hidden the moment they come forward, with a quiet reminder of what you're on. Nothing is quit, nothing is changed.
• Feed apps get a scroll guard, including iPhone and iPad apps running on Apple silicon. TrueFocus counts how far you scroll, never what's on screen. Skim, binge or linger, and a full-screen wake-up boots you out.
• The included Safari extension removes Reels and Shorts, opens Instagram straight to your DMs, keeps LinkedIn and Facebook to work, counts your swipes on feed sites, and blocks adult sites. Turning that filter off takes a 24-hour cool-off.

JUGGLE WITHOUT LOSING THE THREAD
Keep several tasks in play and switch with one tap or ⌥⌘K. Each one keeps a "where I left off" note.

YOUR TONE
Calm, Direct or Savage. Choose how hard the nudges hit.

SOUND
Optional studio cues, a calm river under rests, and three original focus tracks.

NOTES
Fast notes with headings, bullets and checklists.

WITH YOUR IPHONE
Link your devices once with a six-digit code. There's no account and no sign-up. Start a task on the Mac and it appears on your iPhone's Lock Screen. Your tasks, notes and timeline are encrypted on your device before they're uploaded, and the sync server stores only the encrypted copy. No ads, no analytics, no tracking.

HONEST LIMITS
TrueFocus raises the walls; you own the Mac. Everything it does can be undone in Settings or by quitting it. For an extra layer, macOS's own Screen Time can limit adult websites. TrueFocus shows you where.

Requires macOS 26 or later.
```

**Lines to check before submitting the Mac copy:**

- The **Shortcuts / Focus** hook (`FocusModeBridge` runs `/usr/bin/shortcuts`) isn't in the copy
  above on purpose. A sandboxed Mac App Store build may not be able to launch that binary. Add the
  line "Optionally flips a macOS Focus when you start, so your iPhone goes quiet too" only after you've
  tested it in a sandboxed build.
- Don't add "works with Chrome, Arc, Brave and Edge" until the Chrome extension is live on the
  Chrome Web Store. Today the Mac app tells people to load it unpacked in developer mode.

### Keywords (Mac, limit 100): 92 chars

```
productivity,doomscroll,distraction,detox,planner,todo,timer,hotkey,brain dump,blocker,habit
```

(The Mac name has no "blocker", so it moves into the keywords here.)

### What's New in 1.0 (Mac)

```
The first release. A menu bar focus flow with global hotkeys, feed apps hidden while you work, a scroll guard with a full-screen wake-up, a Safari extension that takes the feed out of the web, and sync with the iPhone app.
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
| Scroll budget 5 min by default, cooldown ≥ 15 min | `TFSettings.scrollBudgetMinutes = 5`, `scrollCooldownMinutes = 15`, clamped `15...240` |
| Reply pass of 2 minutes, a few times a day | `respondPassMinutes = 2`, `respondPassesPerDay = 8` |
| Adult filter on by default, 24-hour cool-off | `adultFilterEnabled = true`, `adultFilterCoolOffHours = 24` |
| Filter covers Safari and in-app browsers | `AdultFilter.apply`: `webContent.blockedByFilter = .auto(...)` |
| Apple Intelligence used on-device | `TaskExtractor` → `FoundationModels.LanguageModelSession` with fallback `BrainDump` |
| Live Activity buttons Done / Stuck / Pause | `FocusLiveActivity.swift` `LiveButton(intent: CompleteTaskIntent / StuckIntent / PauseIntent)` |
| Siri "Done in TrueFocus" | `AppShortcuts.swift` phrases |
| Music keeps playing when locked | `UIBackgroundModes: audio`, `.playback` session while music or rest ambience plays |
| No ads, analytics or tracking | No third-party SDK: `Package.swift` has no dependencies, there are no analytics imports, and the only network calls are to Supabase, plus Apple's services (APNs from the server, MusicKit if chosen) |
| "Encrypted on your device before upload; server stores only the encrypted copy" | `SyncCipher` (AES-GCM, HKDF-SHA256 from the space key); `tf_records.data` holds ciphertext |
| Mac hides apps but quits nothing | `DistractionGuard` calls only `NSRunningApplication.hide()` |
| Mac scroll guard counts distance, not content | `ScrollWatch` reads `scrollingDeltaY` from a global scroll-wheel monitor, only while a listed feed app is frontmost |

**Left out on purpose:**

- **"End-to-end encrypted"** (the README uses it). The sync payloads are encrypted, but the key
  they're encrypted with is derived from the space key, and that space key is sent to the server in
  the `x-tf-space` header on every request. It's also held in plain text in `tf_pairings` for up
  to 10 minutes while linking. The server operator could therefore decrypt the data. Don't claim
  end-to-end encryption until that changes. `privacy.md` §1.3 describes the fix.
- **"Blocks Reels in the Instagram app."** It doesn't, and the README says so.
- **Specific scroll counts on iPhone native apps.** iPhone native apps are guarded by time only.
- **"Works without the app"** for the Chrome extension on the iPhone listing. Not relevant there.
- **Profanity.** Guideline 2.3.8 requires metadata suitable for a 4+ audience even when the app is
  rated higher. "Savage" is named, never quoted.
