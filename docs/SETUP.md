# Setup

One-time, about ten minutes. Do it in this order.

## 1. Build and install

1. Install Xcode 26 or newer and sign in with your Apple Developer account (Xcode ▸ Settings ▸ Accounts).
2. `brew install xcodegen`
3. `cp Config/Local.example.xcconfig Config/Local.xcconfig` and set:
   - `TF_DEVELOPMENT_TEAM` — your 10-character Team ID.
   - `TF_BUNDLE_PREFIX` — a reverse-DNS prefix you own, e.g. `com.yourname`. It names the bundle IDs, the App Group and the iCloud container, so choose once.
4. `xcodegen` then `open TrueFocus.xcodeproj`.
5. Pick the **TrueFocus** scheme, your iPhone as destination, Run. Pick **TrueFocusMac**, My Mac, Run.

Xcode's automatic signing registers the App IDs, the App Group and the iCloud container the first time. If it asks to enable a capability (Family Controls, iCloud, App Groups, Push, Time Sensitive Notifications), allow it.

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

## 4. Use it

- Morning: Today ▸ **Start the day** ▸ empty your head ▸ keep what matters ▸ pick the win ▸ **Attack**.
- Working: **Done** (⌥⌘D anywhere on the Mac), **Stuck** (⌥⌘S), **Back to it / Next** (⌥⌘B).
- Evening: **Shut down the day** from Today or the scoreboard.

## Troubleshooting

- **Nothing syncs.** Both devices must be signed into the same iCloud account, and the build must be signed with your team (unsigned builds keep data local). First sync can take a minute.
- **Shields don't appear.** Guard ▸ check Screen Time access is *Approved*, and that you've picked scroll apps.
- **Live Activity didn't start for a session begun on the Mac.** iOS only lets an app start one while it's open; unlock and open TrueFocus once and it appears.
- **Chrome extension says "app not running".** The Mac app serves state on `127.0.0.1:52525`; launch it.
