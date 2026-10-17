# Setup

One-time, about ten minutes. Do it in this order.

## 1. Build and install

1. Xcode 26 or newer, signed in with the Apple Developer account that ships VocaMonkey (Xcode ▸ Settings ▸ Accounts). The project already uses that team, `7CVSS54KS4`, and the bundle prefix `com.youngjingoh` (`Config/Base.xcconfig`).
2. `brew install xcodegen`
3. `xcodegen` then `open TrueFocus.xcodeproj`.
4. Pick the **TrueFocus** scheme, your iPhone as destination, Run. Pick **TrueFocusMac**, My Mac, Run.

Signing is automatic (unlike VocaMonkey's manual App Store profiles): the first build registers the App IDs and the App Group under your team. If Xcode asks to enable a capability (Family Controls, App Groups, Push, Time Sensitive Notifications), allow it. No iCloud capability or iCloud storage is needed.

To build under another team or prefix, `cp Config/Local.example.xcconfig Config/Local.xcconfig` and set `TF_DEVELOPMENT_TEAM` / `TF_BUNDLE_PREFIX` there. The prefix names the bundle IDs and App Group, so choose it once.

> Coming from a build that used iCloud: the data on each device stays where it is and is uploaded on the first sync, so nothing needs re-entering.

> **Family Controls.** Development builds on your own devices work with the standard *Family Controls (Development)* capability. Only TestFlight / App Store distribution needs Apple's distribution entitlement, which you request at developer.apple.com.

## 2. iPhone

1. **Screen Time access.** Open TrueFocus ▸ Guard ▸ *Enable*. Approve with Face ID.
2. **Scroll apps.** Guard ▸ *Scroll apps* — pick Instagram, YouTube, TikTok, X, Reddit, anything you lose time in. These are shielded during focus and budgeted outside it.
3. **Reply apps.** Guard ▸ *Reply apps* — pick the ones you must answer messages in (e.g. Instagram). Their shield shows **Reply · 2 min**.
4. **Notifications.** Allow them when asked. Then Settings ▸ Notifications ▸ TrueFocus ▸ turn on *Time Sensitive Notifications* so the wake-up nudges get through a Focus.
5. **Safari extension.** Settings ▸ Apps ▸ Safari ▸ Extensions ▸ TrueFocus ▸ *Allow Extension*, and set *All Websites* to *Allow*.
6. **Focus filter** (silences notifications and shields everything, on both devices):
   - Settings ▸ Focus ▸ *Work* (or make a "Deep Work" Focus).
   - *Allowed Notifications*: People — only those who may reach you; Apps — **TrueFocus** only.
   - *Focus Filters* ▸ Add Filter ▸ **TrueFocus** ▸ turn on **Deep Work shields**.
   - Back on the Focus page: make sure **Share Across Devices** is on (Settings ▸ Focus).
7. **Lock Screen.** Long-press the Lock Screen ▸ Customize ▸ add the **TrueFocus** widget. Live Activities appear on their own once a task is running.
8. **Optional, extra wall:** Settings ▸ Screen Time ▸ Content & Privacy Restrictions ▸ App Store, Media, Web & Games ▸ Web Content ▸ *Limit Adult Websites*.

## 3. Mac

1. Launch TrueFocus. It lives in the menu bar; the window opens from there.
2. **Safari:** Safari ▸ Settings ▸ Extensions ▸ enable **TrueFocus**, allow on all websites.
3. **Chrome / Arc / Brave / Edge:** open `chrome://extensions`, turn on *Developer mode*, *Load unpacked* ▸ select `Extensions/web` in this repo. It talks to the Mac app over `127.0.0.1:52525`, so keep the app running.
4. **Blocked apps:** TrueFocus ▸ Settings ▸ Guard ▸ *Add App…* for any Mac app that steals your focus.
5. **Focus sync (optional):** in the Shortcuts app create two shortcuts:
   - **TrueFocus On** — action *Set Focus* ▸ Work ▸ On.
   - **TrueFocus Off** — action *Set Focus* ▸ Work ▸ Off.
   Then TrueFocus ▸ Settings ▸ Focus ▸ turn on *Flip Focus with sessions*. Because the Focus is shared across devices, starting a task on the Mac now silences and shields your iPhone too.
6. **Optional, extra wall:** System Settings ▸ Screen Time ▸ Content & Privacy ▸ Store, Web, Siri & Game Center ▸ Access to Web Content ▸ *Limit Adult Websites*.

## 4. Link iPhone and Mac

Sync runs through the TrueFocus server (Supabase), not iCloud. There's no account: each device starts with its own private space, and you join them once.

1. On the Mac: TrueFocus ▸ Settings ▸ Flow ▸ **Sync** ▸ *Link a device*. A six-digit code appears.
2. On the iPhone: Today ▸ settings (the slider icon) ▸ **Sync** ▸ *Enter a code*, type it, *Link*.

The code works once, for 10 minutes. The iPhone's tasks and notes are merged into the Mac's, and from then on both show one plan. Link more of your devices the same way, from any linked one.

Everything is encrypted on the device before it's uploaded; the server only holds ciphertext and a hash of your space key. Losing every device means losing the key, and with it the synced copy.

**Instant iPhone updates (optional).** Without this, the iPhone catches up whenever it's opened or unlocked into TrueFocus. To have it follow the Mac in the background (Lock Screen, Live Activity, shields), give the server an APNs key — the VocaMonkey one works, since it's the same team:

1. developer.apple.com ▸ Keys ▸ the existing APNs key (or *+* ▸ Apple Push Notifications service). Note its Key ID; download the `.p8` (only possible once — reuse VocaMonkey's saved copy).
2. Supabase dashboard ▸ project *listingline* ▸ Edge Functions ▸ Secrets, add:
   - `APNS_KEY_ID` — the Key ID
   - `APNS_TEAM_ID` — `7CVSS54KS4`
   - `APNS_PRIVATE_KEY` — the full contents of the `.p8`

## 5. Use it

- Morning: Today ▸ **Start the day** ▸ empty your head ▸ keep what matters ▸ pick the win ▸ **Attack**.
- Working: **Done** (⌥⌘D anywhere on the Mac), **Stuck** (⌥⌘S), **Back to it / Next** (⌥⌘B).
- Evening: **Shut down the day** from Today or the scoreboard.

## Troubleshooting

- **Nothing syncs.** Check Settings ▸ Sync on both devices: each should say *Synced …* and they must have been linked with a code (step 4). A red dot shows the reason (offline, server error).
- **iPhone only updates when opened.** That's the default; add the APNs secrets in step 4 for background updates.
- **Shields don't appear.** Guard ▸ check Screen Time access is *Approved*, and that you've picked scroll apps.
- **Live Activity didn't start for a session begun on the Mac.** iOS only lets an app start one while it's open; unlock and open TrueFocus once and it appears.
- **Chrome extension says "app not running".** The Mac app serves state on `127.0.0.1:52525`; launch it.
