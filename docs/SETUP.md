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

1. **Screen Time access.** Open TruFocus ▸ Guard ▸ *Enable*. Approve with Face ID.
2. **Scroll apps.** Guard ▸ *Scroll apps* — pick Instagram, YouTube, TikTok, X, Reddit, anything you lose time in. These are shielded during focus and budgeted outside it.
   Running ads for clients? Pick the Facebook and Instagram **apps**, but leave out Meta Business Suite and Ads Manager, and don't add facebook.com or instagram.com as websites (Screen Time would block business.facebook.com with them). On the web the extension closes the feeds and leaves Ads Manager, Business Suite, Business Manager, Events Manager and the Ad Library open.
3. **Reply apps.** Guard ▸ *Reply apps* — pick the ones you must answer messages in (e.g. Instagram). Their shield shows **Reply · 2 min**.
4. **Notifications.** Allow them when asked. Then Settings ▸ Notifications ▸ TruFocus ▸ turn on *Time Sensitive Notifications* so the wake-up nudges get through a Focus.
5. **Safari extension.** Settings ▸ Apps ▸ Safari ▸ Extensions ▸ TruFocus ▸ *Allow Extension*, and set *All Websites* to *Allow*.
6. **Focus filter** (silences notifications and shields everything, on both devices):
   - Settings ▸ Focus ▸ *Work* (or make a "Deep Work" Focus).
   - *Allowed Notifications*: People — only those who may reach you; Apps — **TruFocus** only.
   - *Focus Filters* ▸ Add Filter ▸ **TruFocus** ▸ turn on **Deep Work shields**.
   - Back on the Focus page: make sure **Share Across Devices** is on (Settings ▸ Focus).
7. **Lock Screen.** Long-press the Lock Screen ▸ Customize ▸ add the **TruFocus** widget. Live Activities appear on their own once a task is running.
8. **Optional, extra wall:** Settings ▸ Screen Time ▸ Content & Privacy Restrictions ▸ App Store, Media, Web & Games ▸ Web Content ▸ *Limit Adult Websites*.

## 3. Mac

1. Launch TruFocus. It lives in the menu bar; the window opens from there.
2. **Safari:** Safari ▸ Settings ▸ Extensions ▸ enable **TruFocus**, allow on all websites.
3. **Chrome / Arc / Brave / Edge:** open `chrome://extensions`, turn on *Developer mode*, *Load unpacked* ▸ select `Extensions/web` in this repo. It talks to the Mac app over `127.0.0.1:52525`, so keep the app running.
4. **Blocked apps:** TruFocus ▸ Settings ▸ Guard ▸ *Add App…* for any Mac app that steals your focus.
5. **Focus sync (optional):** in the Shortcuts app create two shortcuts:
   - **TruFocus On** — action *Set Focus* ▸ Work ▸ On.
   - **TruFocus Off** — action *Set Focus* ▸ Work ▸ Off.
   Then TruFocus ▸ Settings ▸ Focus ▸ turn on *Flip Focus with sessions*. Because the Focus is shared across devices, starting a task on the Mac now silences and shields your iPhone too.
6. **Optional, extra wall:** System Settings ▸ Screen Time ▸ Content & Privacy ▸ Store, Web, Siri & Game Center ▸ Access to Web Content ▸ *Limit Adult Websites*.
7. **Drift guard:** TruFocus ▸ Settings ▸ Guard ▸ *Drift guard* ▸ *Window titles* ▸ **Allow…**, then switch TruFocus on under System Settings ▸ Privacy & Security ▸ Accessibility. It works without this (app names and, with the extension, sites), but titles are what tell a marketing doc from a side project in the same app. The browser extension (steps 2–3) supplies the site; without it a browser counts as "unsure" (about four minutes before a nudge) rather than drift. Mail and chat apps (Mail, Slack, KakaoTalk, Teams…) are "unsure" too unless you add them to a task; calls (Zoom, FaceTime) never count.

## 4. Link iPhone and Mac

Sync runs through the TruFocus server (Supabase), not iCloud. There's no account, and it's off until you turn it on: nothing leaves a device before then.

1. On the Mac: TruFocus ▸ Settings ▸ Flow ▸ **Sync** ▸ *Turn on sync*, then *Link a device*. A six-digit code appears.
2. On the iPhone: Today ▸ settings (the slider icon) ▸ **Sync** ▸ *Enter a code*, type it, *Link*.
3. Both screens show the same four-digit number. If they match, tap *They match* on the Mac. If they don't, cancel: something is between your devices.

The code works for 10 minutes and links one device. The iPhone's tasks and notes are merged into the Mac's, and from then on both show one plan. Link more of your devices the same way, from any linked one.

Sync is end-to-end encrypted: everything is sealed on the device, and the key never goes to the server. Requests carry a token derived one way from it, and linking passes the key sealed from one device to the other. Losing every device means losing the key, and with it the synced copy. *Turn off here* stops a device syncing; *Delete server copy…* removes everything the server holds for your devices.

**Instant iPhone updates (optional).** Without this, the iPhone catches up whenever it's opened or unlocked into TruFocus. To have it follow the Mac in the background (Lock Screen, Live Activity, shields), give the server an APNs key — the VocaMonkey one works, since it's the same team:

1. developer.apple.com ▸ Keys ▸ the existing APNs key (or *+* ▸ Apple Push Notifications service). Note its Key ID; download the `.p8` (only possible once — reuse VocaMonkey's saved copy).
2. Supabase dashboard ▸ project *listingline* ▸ Edge Functions ▸ Secrets, add:
   - `APNS_KEY_ID` — the Key ID
   - `APNS_TEAM_ID` — `7CVSS54KS4`
   - `APNS_PRIVATE_KEY` — the full contents of the `.p8`

## 5. Use it

- Morning: Today ▸ **Start the day** ▸ empty your head ▸ keep what matters ▸ pick the win ▸ **Attack**.
- Working: **Done** (⌥⌘D anywhere on the Mac), **Stuck** (⌥⌘S), **Back to it / Next** (⌥⌘B).
- Waiting on someone: **Waiting on it** (the hourglass, or ⌥⌘P) keeps the task juggled and moves you to the next one. Juggle up to 3 more with **+ Juggle another task**, switch with a tap in the Juggling list (menu bar, Today, the Chrome/Safari popup, the Lock Screen chips) or ⌥⌘K. The number of tasks is in Settings ▸ Rhythm.
- Evening: **Shut down the day** from Today or the scoreboard.

## Troubleshooting

- **Nothing syncs.** Check Settings ▸ Sync on both devices: each should say *Synced …* and they must have been linked with a code (step 4). A red dot shows the reason (offline, server error).
- **iPhone only updates when opened.** That's the default; add the APNs secrets in step 4 for background updates.
- **Shields don't appear.** Guard ▸ check Screen Time access is *Approved*, and that you've picked scroll apps.
- **Live Activity didn't start for a session begun on the Mac.** iOS only lets an app start one while it's open; unlock and open TruFocus once and it appears.
- **Chrome extension says "app not running".** The Mac app serves state on `127.0.0.1:52525`; launch it.
- **Drift guard says *Allow…* although TruFocus is switched on under Accessibility.** macOS ties the grant to the app's code signature. A debug build signed to run locally (no team) gets a new signature on every rebuild, so the old grant no longer applies even though the switch still looks on. Select TruFocus in the Accessibility list, remove it with **–**, then press *Allow…* again (or run `tccutil reset Accessibility <your bundle ID>` and relaunch). Builds signed with your Apple Development team keep the grant across rebuilds.
- **A task started and nothing asked where it happens.** The question appears once per task, only for tasks started on the Mac with no apps or sites yet. After *Skip* it isn't asked again for that task; set it from the menu bar (the line under the task ▸ *Set*).
