# App Review: notes, test plan, compliance, risks, age rating, export compliance

Checked against the code at `1da5526`. The sync, consent and tone parts were checked again after
`11f3952` (Direct default), `7721c30` (custom reminders) and `1caee66` (end-to-end sync). File and
line references point to what each statement rests on.

---

## 1. Paste into App Store Connect ▸ App Review Information ▸ Notes

The Notes field allows 4,000 characters. This block uses 3,913.

```
TrueFocus is a self-control focus app for adults. No account or login exists — every feature works on first launch. Please test on a physical iPhone: Screen Time APIs do not run in the Simulator.

WHY FAMILY CONTROLS
TrueFocus uses FamilyControls with INDIVIDUAL authorization (requestAuthorization(for: .individual)) so the device owner can restrict their own distracting apps. There is no parental mode, no child account and no Family Sharing. Screen Time data (opaque tokens from FamilyActivityPicker, DeviceActivity threshold events) stays on the device in the App Group and is never transmitted. The user can revoke access at any time in Settings > Screen Time.

HOW TO TEST (about 10 minutes)
1. Launch. Allow notifications when asked. On Today, tap "Start the day", type a few lines (e.g. "email Sam, write report"), tap through to the list and the win, then "Attack". A task is now running with a clock.
2. Guard tab > "Allow Screen Time access" > approve with Face ID/passcode.
3. Guard > Scroll apps > pick Apple TV and News (or any app you can open). Done.
4. Shield: with the task still running, open News. A TrueFocus shield names the task and how long you've been on it. "Back to work" closes it.
5. Reply pass: Guard > Reply apps > pick Podcasts. Open Podcasts while the task runs: the shield shows "Reply · 2 min (8 left)". Tap it and Podcasts opens for 2 minutes of use.
6. Scroll budget: in Focus, tap Pause (shields drop while paused). Guard > "Boot me out after" > 1 minute. Use News for a little over a minute. A "Budget spent" shield appears and stays for the 15-minute lockout (iOS minimum). DeviceActivity can take a minute or two to fire.
7. Adult filter: it is on by default once Screen Time access is granted. In Safari, open a well-known adult domain: Screen Time's "restricted" page appears instead. In Guard > Adult filter, "Turn off…" starts a 24-hour cool-off ("Turns off <date>") that can be cancelled with "Keep it on". Revoking Screen Time access in iOS Settings removes it immediately.
8. Safari extension: Settings > Apps > Safari > Extensions > TrueFocus > on, All Websites > Allow. Then in Safari: youtube.com/shorts and instagram.com/reels open a TrueFocus page instead of short-form video. On reddit.com, swipe the feed quickly ~25 times within a minute: a warning toast, then a full-screen boot-out.
9. Lock the phone while a task runs: a Live Activity with Done / Stuck / Pause. Settings (slider icon on Today) > Sound > Focus music "Drive", then lock: music continues (UIBackgroundModes audio, mixes with other apps).
10. Sync (optional, off by default): nothing is uploaded until you tap "Turn on sync" or "Enter a code" in Settings > Sync. To link a Mac: "Turn on sync" > "Link a device" shows a 6-digit code; on the other device, "Enter a code". Both show the same 4-digit number; tap "They match" on the first. "Turn off here" and "Delete server copy…" are there too.

THE SAFARI EXTENSION
Bundled with the app. It removes short-form video (Reels, Shorts, TikTok except messages), opens Instagram to messages, hides the LinkedIn and Facebook feeds, counts scroll strokes on 14 feed sites to stop doom-scrolling, applies SafeSearch and blocks adult sites. It decides everything locally and sends no browsing data anywhere. It needs access to all websites because the adult-site block and SafeSearch redirects must apply to any domain.

DATA
No ads, analytics, tracking or third-party SDKs. Sync is off until the user turns it on; then tasks, notes and the timeline sync between their own devices through our Supabase server, end-to-end encrypted (AES-GCM; the key is never sent to the server). Settings > Sync can turn it off or delete the server copy.

TONE
Tones in Settings > Voice: Calm, Direct (default), Savage. Savage is opt-in, labelled "Strong language", uses profanity, and is declared in the age rating. "Your own words" lets users write their own nudges.
```

> **Before you paste:** the default tone is Direct (`TFSettings.tone = .direct`, R1 resolved), so a
> reviewer meets no profanity unless they pick Savage. **Attach a demo video link** showing steps
> 4 to 8 on a real device. Apple accepts a URL in the notes, and it avoids the "we couldn't trigger
> the shield" rejection.

**Mac record notes:** use the block above, but replace steps 2 to 9 with:

```
On Mac: launch from Applications; TrueFocus lives in the menu bar. Start a task (menu bar > quick-add, or the window). Settings > Guard > "Add App…" > pick e.g. Podcasts; while the task runs, bringing Podcasts forward hides it and shows a "shielded while you focus" toast. Global hotkeys: ⌥⌘D Done, ⌥⌘S Stuck, ⌥⌘B Back to it. Safari > Settings > Extensions > TrueFocus > enable, allow on all websites; then youtube.com/shorts is replaced by a TrueFocus page. Scroll guard: open a listed feed app (e.g. the Instagram iPad app on Apple silicon) and scroll quickly ~25 strokes; a full-screen wake-up appears and the app is hidden for 10 minutes.
```

---

## 2. Why the app uses Screen Time / Family Controls

- **Purpose: self-control for the device owner.** The user picks their own distracting apps in
  `FamilyActivityPicker`. TrueFocus shields them while a focus or think segment runs
  (`ManagedSettingsStore(named: .focus)`), enforces a daily usage budget outside work through a
  `DeviceActivityEvent` threshold that shields the apps for a cooldown (`.scrollBudget`), and applies
  the Screen Time adult-website filter (`.adultFilter`, `webContent.blockedByFilter = .auto(...)`).
- **Authorization: `.individual` only** (`ScreenTimeGuard.requestAuthorization`). There's no
  `.child` and no Family Sharing flow.
- **Extensions:** a Device Activity monitor (budget, cooldown, reply pass, filter cool-off), a
  Shield Configuration (a custom shield naming the current task) and a Shield Action (a "Reply ·
  2 min" pass, `respondPassesPerDay` = 8 by default).
- **No data leaves the device**: see `privacy.md` §1.4 and §4.
- **The user stays in control.** iOS Settings ▸ Screen Time can revoke access at any time. The 24-hour
  cool-off on turning the adult filter off is an in-app speed bump that can be cancelled. It isn't a
  lock: `README.md` "Honest limits", and `ScreenTimeGuard.keepAdultFilterOn`.

## 3. The Safari extension, and how to enable it

**What it does** (`Extensions/web/`, one MV3 extension shared by iPhone and Mac Safari):

- **Short-form removed:** Instagram Reels and Explore, YouTube Shorts, TikTok except messages and
  upload, Facebook Reels, Watch and Stories, Snapchat Spotlight. Navigations are redirected to
  `shorts.html` by `rules_shortform.json`, in-app navigations are caught by `content.js`, and shelves
  are hidden by `content.css`.
- **Instagram, messages only:** instagram.com opens `/direct/inbox/`. DMs, settings and posting work.
- **LinkedIn and Facebook, work only:** the home feed opens Messaging or Messenger, and video is gone.
  Profiles, search, jobs, Sales Navigator, Campaign Manager, pages, groups, events, Marketplace,
  Ads Manager and Business Suite stay open.
- **Doom-scroll guard** on 14 feed sites: it counts downward strokes (touch, wheel, Space, PageDown,
  `j`, ↓). The standard limits are 25 strokes in 60 s, 60 strokes in one sitting, or 8 minutes of
  dwell, ×0.3 during focus. It warns at 70%, then boots you to `blocked.html` with a 10-minute
  cooldown (20 during focus).
- **Adult filter:** `rules_adult.json`, `rules_adult_keywords.json`, and SafeSearch for Google, Bing
  and DuckDuckGo (`rules_safesearch.json`). Turning it off starts a 24-hour cool-off.
- **State comes from the app** through `sendNativeMessage`, which reads the App Group. The extension
  sends nothing to any server.

**Enable it:**

- iPhone: Settings ▸ Apps ▸ Safari ▸ Extensions ▸ **TrueFocus** ▸ on, then *All Websites* ▸ **Allow**.
- Mac: Safari ▸ Settings ▸ Extensions ▸ **TrueFocus** ▸ enable ▸ *Always Allow on Every Website*.

---

## 4. Guidelines it complies with

Guideline numbers follow the App Review Guidelines as I know them through mid-2026. Check them against
the live page before you quote them to App Review.

| Guideline | How TrueFocus complies | Evidence |
| --- | --- | --- |
| **2.1** App completeness | Full functionality without login. A demo video is recommended because Screen Time needs a device | No account code anywhere |
| **2.3.1 / 2.3.7 / 2.3.8** Accurate metadata, keywords, 4+ metadata | "End-to-end encrypted sync" is now accurate: the space key never reaches the server (apart from one move per device on an older build, R4), requests carry a one-way access token, and linking hands the key over sealed. No trademarks in keywords, no profanity in metadata or screenshots, and screenshots use the default Direct tone | `listing.md` §4, `privacy.md` §1.3, `SyncSecrets.swift` |
| **2.5.1** Public APIs only | FamilyControls, ManagedSettings(UI), DeviceActivity, ActivityKit, WidgetKit, AppIntents, FoundationModels, MusicKit; on Mac, NSWorkspace, NSEvent global monitor, Carbon `RegisterEventHotKey`, Network.framework | `project.yml`, sources |
| **2.5.4** Background services for their intended purpose | `audio` only while audible focus music or the rest-ambience river plays (`AudioDirector.configureSession(sustained:)` uses `.playback` only then, otherwise `.ambient`). `remote-notification` for silent sync wake-ups | `AudioDirector.swift`, `tf-notify` |
| **2.5.9** Doesn't alter standard switches or system UI | Shields come from Apple's ManagedSettings. On Mac, apps are hidden, never quit or modified | `DistractionGuard.swift` |
| **2.5.16** Widgets, Live Activities, notifications relate to app content | All show the current task and its flow actions | `iOSExtensions/Widgets/` |
| **4.2** Minimum functionality | A full task flow, notes, review, widgets, Live Activity and sound, even without Screen Time | — |
| **4.4.2** Safari extensions | Run on current Safari, don't interfere with Safari UI, aren't malicious. Access to all sites is explained as needed for blocklist and SafeSearch redirects | `manifest.json` |
| **4.5.4** Push notifications | Not required to use the app. No marketing. Time-sensitive level only for the nudges the user set up (rest overrun, stuck, idle) | `NudgeScheduler.swift` |
| **5.1.1(i)** Privacy policy | Hosted policy linked in metadata and in the app. The policy in `privacy.md` §3 describes end-to-end sync, the off switch and self-serve deletion | `privacy.md` §3. **Add an in-app link** (none exists yet) |
| **5.1.1(ii)** Consent | Screen Time, notifications and Apple Music each use the system prompts. Sync is off on a new install and uploads nothing until the user taps "Turn on sync" or links with "Enter a code". "Turn off here" stops it on a device (R6 resolved) | `SyncService.isEnabled`, `SyncSettingsSection.swift` |
| **5.1.1(v)** Account deletion | Not applicable: no accounts. Server data deletion is self-serve: Settings ▸ Sync ▸ "Delete server copy…" calls `tf_delete_space`, which deletes every record and push token for the space | `SyncService.deleteServerCopy`, `20261019000000_truefocus_e2e.sql`, `privacy.md` §3 |
| **5.1.2** Data use and sharing | No sharing, no ads, no tracking. Screen Time data never leaves the device | `privacy.md` §1 |
| **5.2.1 / 5.2.2** IP and third-party content | Feed sites are named only factually. No third-party logos in screenshots. Sound licences documented | `docs/SOUND.md` |
| **Family Controls entitlement terms** | Individual authorization, used only to provide the shields and filter, data on the device | §2 |
| **2.4.5** (Mac App Store) | **Not yet compliant**: see R5 | — |

---

## 5. Likely rejection risks and what to do

**R1 to R7 were the blockers or near-blockers.** R1, R4 and R6 are resolved in the code. Fix the
open ones before you submit.

| # | Risk | What's in the code | Mitigation |
| --- | --- | --- | --- |
| ~~R1~~ | **Resolved: profanity is opt-in.** The default tone is now **Direct** (`TFSettings.tone = .direct`; `NudgeContext` defaults to `.direct`; `core.js` `effective()` falls back to `'direct'`, L404–406). Saved settings keep the tone they hold. Savage is opt-in, and its chip reads "Strong language" (VoiceOver: "Savage · strong language", `NudgeTone.fullLabel`). In Savage, the strongest nudge in each ladder, the doom-scroll boot-out and the **budget-spent shield title** still say "Wake the fuck up." (`Copy.swift` L95, 116, 153, 173, 190, 264; `core.js` L589). With the default, Settings ▸ Voice previews Direct's `restOver(level: 3)`, "Momentum's leaking." | `Settings.swift`, `Nudges.swift`, `FlowSettingsView.swift` | Declare the opt-in profanity in the age rating (§6). Keep "fuck" out of all screenshots and metadata (guideline 2.3.8). If you want 4+ instead, rewrite the six Savage lines without it, e.g. "WAKE UP." or "Up. Now." |
| **R2** | **Family Controls distribution entitlement not granted.** Archiving or exporting for TestFlight and the App Store fails without it. | 4 targets carry `com.apple.developer.family-controls` | Request it now for all 4 bundle IDs (`privacy.md` §4). Approval takes days to weeks. |
| **R3** | ~~Privacy manifests out of step with the label.~~ **Resolved.** `UserDefaults` is a required-reason API (`SharedStore` in the app and every extension, `LoginItem` on Mac) and is declared in `PrivacyManifests/`. The iPhone manifest declares only Device ID (the push token) and the Mac one nothing, matching `privacy.md` Label B. | `PrivacyManifests/*/PrivacyInfo.xcprivacy` | Keep them in step with the label. |
| ~~R4~~ | **Resolved: the encryption claim is accurate.** Requests carry an access token, `HKDF(spaceKey, "access.v1")`, and the server stores its SHA-256 as the space id. Payloads are sealed under `HKDF(spaceKey, "payload.v1")`, which the server can't derive. Linking swaps X25519 public keys and sends the key sealed, after both screens show the same match number. The raw key travels only once, in each older device's `tf_rekey` move. | `SyncSecrets.swift`, `TFCloud.swift`, `tf-pair`, `20261019000000_truefocus_e2e.sql` | "End-to-end encrypted" may be used. Keep the caveats in `privacy.md` §1.3 in mind: plaintext metadata, the one-time legacy move, and a four-digit match number that a server actively attacking a link could beat. Don't claim "even we can't intercept linking". |
| **R5** | **The Mac app can't go to the Mac App Store as built.** (a) `TrueFocusMac` has **no `com.apple.security.app-sandbox`**, and App Store Connect rejects unsandboxed Mac uploads (2.4.5(i)). (b) It **registers itself as a login item on first launch without asking** (`LoginItem.enableOnFirstLaunch`), which breaks 2.4.5(iii). (c) Sandboxed, the loopback bridge needs `com.apple.security.network.server`, and sync needs `network.client`. (d) **Unclear:** `/usr/bin/shortcuts` via `Process` (FocusModeBridge), `NSRunningApplication.hide()` on other apps, and the global scroll-wheel monitor may not work in the sandbox. Test each one. (e) The Mac settings copy the Chrome extension into Application Support and tell users to "Load unpacked" in developer mode. Reviewers may read that as installing extra code (2.4.5(iv)). | `project.yml`, `macOS/` | Either ship the Mac app outside the store (Developer ID plus notarization, as `docs/SHARING.md` already describes), or add the sandbox and network entitlements, ask before enabling the login item, test (d), and point Chrome users to the Chrome Web Store listing. |
| ~~R6~~ | **Resolved: sync asks first (5.1.1(ii)).** On a new install sync is off and nothing is uploaded until the user taps **Turn on sync** or links with **Enter a code** (`SyncService.isEnabled`, `tf.sync.enabled`). Devices that synced before this release stay on. Settings ▸ Sync has **Turn off here** (keeps the key, stops uploading) and **Delete server copy…** (`tf_delete_space`: deletes all records and push tokens for the space, turns sync off here and forgets the key). | `SyncService.swift`, `SyncSettingsSection.swift` | Nothing more for review. Two edges to know: a reinstall that finds a key left in the Keychain turns sync back on without asking, even if it was off before; and the in-app privacy policy link is still missing (R13). |
| **R7** | **The adult filter and an adult domain list in the binary.** Reviewers may ask about it, or flag the cool-off as "the app prevents the user from changing settings". | `Blocklist.adultDomains`, `GuardView` | The review notes explain it's a block list that shows no content, that the cool-off can be cancelled, and that the system revoke always works. Don't show adult domain names in screenshots. |
| R8 | **Background audio questioned.** A reviewer with music off sees no audio, and may ask why the `audio` mode is there. | `UIBackgroundModes: audio` | Covered in notes step 9: focus music and the rest river are audible and play only during focus or rest. |
| R9 | **`aps-environment` = `development`** in `iOS/App/TrueFocus.entitlements` and `project.yml`. | — | Automatic signing normally sets `production` at export. Check the exported `.ipa` with `codesign -d --entitlements :- TrueFocus.app`. `tf-notify` picks the APNs host from the `environment` column, which the app sets from `DEBUG`, so that part is consistent. |
| R10 | **Third-party trademarks.** The description names Instagram, YouTube, TikTok, Facebook and LinkedIn. | — | Factual references only. No logos or feed screenshots of those services (5.2.1). Already kept out of the name, subtitle and keywords. |
| R11 | **iPad.** The app is iPhone-only (`TARGETED_DEVICE_FAMILY: "1"`) but runs on iPad in compatibility mode, and review sometimes happens on iPad. | — | Run it once on an iPad: portrait-only layout, Screen Time authorization, shields. |
| R12 | **Music rights.** The focus tracks were made with ElevenLabs Music (`docs/SOUND.md`). Commercial use depends on the ElevenLabs plan in force **when they were generated**. The free tier is non-commercial. The Sonniss GDC bundle licence covers commercial use in apps, with no attribution. | `docs/SOUND.md` | Keep a record of the ElevenLabs paid plan and its terms on the generation date, and a copy of the Sonniss licence. **Unclear from the repo** which ElevenLabs plan was used. Confirm it. |
| R13 | **No in-app privacy policy link.** | — | Add one in Settings (both apps). |
| R14 | **The Mac `Info.plist` lacks `ITSAppUsesNonExemptEncryption`.** | `project.yml` TrueFocusMac `info.properties` | Add `ITSAppUsesNonExemptEncryption: false` (as on iPhone) so every Mac build skips the export question. |
| R15 | **Name taken.** | — | Check in App Store Connect before you finalize the screenshots. |

---

## 6. Age rating questionnaire

App Store Connect's questionnaire was reworked in 2025 (the new 13+, 16+ and 18+ tiers, plus
questions about in-app controls and capabilities). The answers below cover both the old and new
items. Use the ones your form shows. **App Store Connect computes the rating. Don't pick it by hand.**

**Content descriptors (None / Infrequent or Mild / Frequent or Intense):**

| Item | Answer | Why |
| --- | --- | --- |
| Cartoon or Fantasy Violence | None | |
| Realistic Violence | None | |
| Prolonged Graphic or Sadistic Realistic Violence | None | |
| Guns or Other Weapons | None | |
| **Profanity or Crude Humor** | **Infrequent or Mild** *(recommended while the Savage lines keep "fuck")*. **None** *(only if R1's 4+ rewrite is applied)* | See "Why Infrequent" below. |
| Mature or Suggestive Themes | None | The adult filter *blocks* content. The app shows none. |
| Horror / Fear Themes | None | |
| Medical or Treatment Information | None | |
| Alcohol, Tobacco, or Drug Use or References | None | |
| Simulated Gambling | None | |
| Sexual Content or Nudity | None | |
| Graphic Sexual Content and Nudity | None | |

**Yes / No items:**

| Item | Answer | Why |
| --- | --- | --- |
| Unrestricted Web Access | **No** | The app has no browser or web view. The Safari extension restricts browsing and doesn't provide it. |
| User-Generated Content (shared with others) | No | Notes and tasks are private to the user's own devices. |
| Messaging and Chat | No | |
| Advertising | No | |
| Contests | No | |
| Gambling | No | |
| Loot boxes / paid random items | No | |
| Parental Controls (in-app controls) | **No** | It's self-control under individual authorization. There's no guardian mode, so answering Yes would misdescribe the app. |
| Age Assurance | No | |
| Health or Wellness Topics | No | Productivity and focus. No health claims. |
| Made for Kids | No | |

**Why Infrequent, not None or Frequent.** The rating covers everything the app can show, so an
opt-in setting doesn't make the answer **None**: anyone can pick Savage in Settings ▸ Voice. But
since `11f3952` the profanity is off by default. A user meets it only after choosing Savage, which
is labelled "Strong language", and even then only on the last rung of each nudge ladder, the
doom-scroll boot-out and the budget-spent shield (six lines in `Copy.swift`, one in `core.js`).
Calm and Direct (the default) have none. That's occasional strong language that the user asked
for, which fits **Infrequent or Mild** better than *Frequent or Intense*. Custom reminder text is
the user's own, shown only to them, so it doesn't change the answer. If you'd rather not defend the
call, answer **Frequent or Intense**. It's the safe answer, and the rating then goes up a tier.

**Expected result** (App Store Connect computes it; this is a prediction, not a rule): with
"Infrequent or Mild" profanity, **12+** on the old scale and most likely **13+** on the 2025 scale.
With "Frequent or Intense", **17+** on the old scale and most likely **16+** on the new one. With
the profanity removed, **4+**. **Recommendation: answer Infrequent or Mild and expect 13+.** The
audience is adults, and 13+ keeps the app visible to more accounts than 16+. Choose the 4+ rewrite
only if reaching younger users matters to you. **Unclear:** exactly how App Store Connect maps an
opt-in setting and one descriptor onto the 2025 tiers. Check the computed rating on the form before
you submit.

---

## 7. Export compliance

**What the code uses:** HTTPS through `URLSession` (TLS from the OS), and **CryptoKit**: AES-GCM
256-bit, HKDF-SHA256 and SHA-256 for sync payloads, the access token and the Sync ID, and X25519
key agreement (`Curve25519.KeyAgreement`) for linking devices (`SyncSecrets.swift`).
There's no proprietary or non-standard algorithm and no crypto library of its own. Everything goes
through Apple's OS frameworks.

**App Store Connect answers** (asked once per build unless the Info.plist key is set):

| Question | Answer |
| --- | --- |
| Does your app use encryption? | **Yes** (HTTPS and CryptoKit) |
| What type of encryption algorithms does your app implement? | **None of the algorithms mentioned above.** It uses only the encryption within Apple's operating system (URLSession TLS, CryptoKit), not proprietary algorithms and not its own implementation of standard ones. |
| Exempt? / Documentation required? | **Exempt. No documentation.** This matches `ITSAppUsesNonExemptEncryption = false`, which is already set in the iPhone `Info.plist`. **Add the same key to the Mac target** (R14). |
| Available in France? | Yes. With only exempt OS-provided encryption, Apple doesn't ask for a French declaration. |

**Caveat, not legal advice:** under US EAR, encrypting user data for confidentiality is
"mass-market" encryption (5D992.c, License Exception ENC §740.17(b)(1)). Since the March 2021 rule
change, such items don't need an annual self-classification report, and Apple treats apps that only call
the OS crypto as exempt for App Store purposes. If you ever bundle your own crypto library, such as
libsodium or OpenSSL, revisit these answers.
