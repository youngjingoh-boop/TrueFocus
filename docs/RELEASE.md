# Releasing TrueFocus

The runbook for shipping TrueFocus: the iPhone app through TestFlight and the App Store, and the Mac app as a notarized download. Do the steps in this order. Steps 1–7 are one-time; after that, a release is step 8 onwards.

| What | Where it ships | How |
| --- | --- | --- |
| iPhone app with widgets, Live Activity, Screen Time extensions and the Safari extension | App Store (TestFlight first) | `Release` workflow → TestFlight → Submit for Review |
| Mac app with the menu bar and the Safari extension | Direct download (Developer ID, notarized) | `Release` workflow → zip on a draft GitHub release |
| Chrome / Arc / Brave / Edge extension | Chrome Web Store (separate, not covered here) | `Extensions/web` |

Why the Mac app isn't on the Mac App Store is explained in [Mac: App Store or direct download](#mac-app-store-or-direct-download).

Names used below (from `Config/Base.xcconfig`):

| | |
| --- | --- |
| Team ID | `7CVSS54KS4` (the VocaMonkey team) |
| Bundle prefix | `com.youngjingoh` |
| iPhone App Group | `group.com.youngjingoh.truefocus` |
| Mac App Group | `7CVSS54KS4.com.youngjingoh.truefocus` (team-prefixed; needs no registration) |

---

## 1. Check the Apple Developer account

1. Sign in at [developer.apple.com/account](https://developer.apple.com/account) as the **Account Holder** of team `7CVSS54KS4`. Some steps below (Developer ID certificate, Family Controls request, agreements) only work for the Account Holder.
2. Membership must be active (renews yearly).
3. In [App Store Connect ▸ Business](https://appstoreconnect.apple.com/business), make sure there are no pending agreements. A free app needs only the standard agreement; a paid app or in-app purchases also need the **Paid Apps** agreement plus tax and banking.
4. Have these ready for App Store Connect: a **privacy policy URL** and a **support URL** (both required), and a contact email and phone for App Review.

## 2. Request the Family Controls distribution entitlement (start now; it takes days to weeks)

Development builds use *Family Controls (Development)*, which every team has. **TestFlight and App Store builds need *Family Controls (Distribution)*, which Apple grants per bundle ID on request.** Until it's granted, the workflow's iPhone upload fails at the signing step (see [Troubleshooting](#troubleshooting)).

Four bundle IDs carry `com.apple.developer.family-controls`, and each needs it:

- `com.youngjingoh.truefocus` (the app)
- `com.youngjingoh.truefocus.monitor` (DeviceActivity monitor)
- `com.youngjingoh.truefocus.shieldconfig` (shield configuration)
- `com.youngjingoh.truefocus.shieldaction` (shield action)

Register the bundle IDs first (step 3), then:

1. Open [developer.apple.com/contact/request/family-controls-distribution](https://developer.apple.com/contact/request/family-controls-distribution) as the Account Holder.
2. Submit **one request per bundle ID**, the app first, then the three extensions. Use the same description each time and name the app's bundle ID in the extension requests.
3. Apple replies by email. Then, in [Identifiers](https://developer.apple.com/account/resources/identifiers/list), open each of the four IDs and check that **Family Controls (Distribution)** is on (under *Capabilities* or *Additional Capabilities*). Save.

Ready-to-paste text for the form's description field:

> TrueFocus is a personal focus app for adults that helps the user stay on one task and stop doom-scrolling. It uses the Screen Time APIs only for the person using the device: it calls `AuthorizationCenter.shared.requestAuthorization(for: .individual)`. There is no parent/child mode and no remote management.
>
> How each API is used:
> - **FamilyControls**: the user picks the apps, categories and websites that distract them with `FamilyActivityPicker`. The selection is stored only on the device, in the app's App Group.
> - **ManagedSettings**: while the user runs a focus session, the picked apps are shielded. The user can also set a daily scroll budget; when they reach it, the same apps are shielded for a short cool-down. An optional adult-content web filter (`webContent.blockedByFilter`) is on by default; turning it off takes effect after a 24-hour cool-off.
> - **DeviceActivity** (extension `com.youngjingoh.truefocus.monitor`): monitors the user's own budget threshold and schedules, and starts and ends the cool-downs.
> - **ManagedSettingsUI** (extension `com.youngjingoh.truefocus.shieldconfig`): a custom shield that names the task the user is working on ("You're 23 min into 'Investor update'").
> - **Shield actions** (extension `com.youngjingoh.truefocus.shieldaction`): the shield's buttons, including a limited "Reply · 2 min" pass for messaging apps the user marked.
>
> Every shield can be removed by the user, either by ending the session in TrueFocus or by revoking Screen Time access in Settings. TrueFocus never collects, transmits, sells or shares Screen Time or app-usage data; the opaque application tokens never leave the device. App bundle ID: `com.youngjingoh.truefocus`. Extension bundle IDs: `com.youngjingoh.truefocus.monitor`, `com.youngjingoh.truefocus.shieldconfig`, `com.youngjingoh.truefocus.shieldaction`. Team ID `7CVSS54KS4`.

If the form asks whether this is a parental-controls app: **No, it's an individual self-control (Screen Time for yourself) app.**

## 3. Register the identifiers

Automatic signing can create these itself, but registering them by hand makes the capabilities explicit and lets you file the Family Controls requests early. In [Certificates, Identifiers & Profiles ▸ Identifiers](https://developer.apple.com/account/resources/identifiers/list):

**3a. App Group.** `+` ▸ *App Groups* ▸ description `TrueFocus`, identifier `group.com.youngjingoh.truefocus`.

**3b. iPhone App IDs.** `+` ▸ *App IDs* ▸ *App*, platform iOS, *Explicit* bundle ID:

| Bundle ID | Description | Capabilities to tick |
| --- | --- | --- |
| `com.youngjingoh.truefocus` | TrueFocus | App Groups, Family Controls, Push Notifications, Time Sensitive Notifications. *App Services* tab: **MusicKit** (the Apple Music focus playlist uses a catalog search) |
| `com.youngjingoh.truefocus.widgets` | TrueFocus Widgets | App Groups |
| `com.youngjingoh.truefocus.monitor` | TrueFocus Monitor | App Groups, Family Controls |
| `com.youngjingoh.truefocus.shieldconfig` | TrueFocus Shield | App Groups, Family Controls |
| `com.youngjingoh.truefocus.shieldaction` | TrueFocus Shield Action | App Groups, Family Controls |
| `com.youngjingoh.truefocus.safari` | TrueFocus Safari | App Groups |

For each one with App Groups: *Edit* next to App Groups ▸ select `group.com.youngjingoh.truefocus` ▸ Save.

**3c. Mac App IDs.** Platform macOS: `com.youngjingoh.truefocus.mac` and `com.youngjingoh.truefocus.mac.safari`, no extra capabilities (the Mac uses the team-prefixed group, which needs no registration).

**3d. Push for sync.** Silent pushes wake the iPhone when the Mac changes the plan. TestFlight and App Store builds register their device token as `production`, so the sync server must be able to reach production APNs:

1. [Keys](https://developer.apple.com/account/resources/authkeys/list) ▸ `+` ▸ name `TrueFocus APNs` ▸ tick *Apple Push Notifications service (APNs)* ▸ environment **Sandbox & Production** ▸ Register, download the `.p8` (once only). Skip this if a key already exists for the team; one APNs key serves every app.
2. Supabase project `fcfbsgvkanuywsmxvuee` ▸ Edge Functions ▸ Secrets: set `APNS_KEY_ID`, `APNS_TEAM_ID` (`7CVSS54KS4`) and `APNS_PRIVATE_KEY` (the `.p8` text). `APNS_TOPIC` defaults to `com.youngjingoh.truefocus`.

Without these, sync still works by polling; only the instant background wake-ups are missing.

## 4. Create the Developer ID certificate (Mac)

The Mac app is signed with **Developer ID Application**. Only the Account Holder can create it.

1. On your Mac: Xcode ▸ Settings ▸ Accounts ▸ select the team ▸ *Manage Certificates…* ▸ `+` ▸ **Developer ID Application**.
2. Recommended: export it for CI. In Keychain Access ▸ *My Certificates*, right-click *Developer ID Application: … (7CVSS54KS4)* ▸ Export ▸ `.p12` with a strong password. Then `base64 -i DeveloperID.p12 | pbcopy` and keep it for step 6.

Why export it: the workflow first tries Apple's cloud-managed Developer ID certificate through the API key. That only works if the key is allowed to use it. The `.p12` always works.

## 5. Create the App Store Connect app record (iPhone)

[App Store Connect ▸ Apps](https://appstoreconnect.apple.com/apps) ▸ `+` ▸ *New App*:

- Platforms: **iOS** only.
- Name: the store name from the listing work (it must be unique on the store; if "TrueFocus" is taken, use the listing's fallback).
- Primary language: English (U.S.).
- Bundle ID: `com.youngjingoh.truefocus`.
- SKU: `truefocus-ios`.
- User access: Full Access.

The Mac app needs **no** App Store Connect record (Developer ID). Uploads fail with "No suitable application records were found" until this record exists.

## 6. Create the API key and add the GitHub secrets

1. [App Store Connect ▸ Users and Access ▸ Integrations ▸ App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) ▸ *Team Keys*. If asked, request access first (Account Holder).
2. `+` ▸ name `GitHub Release` ▸ access **Admin**. Admin is needed for automatic provisioning (registering devices and profiles, cloud signing); notarization needs Developer or higher.
3. Download `AuthKey_XXXXXXXXXX.p8`. It downloads **once**; store it in your password manager. Note the **Key ID** (on the row) and the **Issuer ID** (above the table).
4. GitHub repo ▸ Settings ▸ Secrets and variables ▸ Actions ▸ *New repository secret*:

| Secret | Value | Needed |
| --- | --- | --- |
| `ASC_KEY_ID` | The Key ID, e.g. `2X9R4HXF34` | Yes |
| `ASC_ISSUER_ID` | The Issuer ID (a UUID) | Yes |
| `ASC_KEY_P8` | The whole `.p8` file, including the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` lines | Yes |
| `DEVELOPER_ID_P12_BASE64` | The base64 text from step 4 | Recommended (Mac) |
| `DEVELOPER_ID_P12_PASSWORD` | The `.p12` password | With the one above |
| `APPLE_DEVELOPMENT_P12_BASE64` / `APPLE_DEVELOPMENT_P12_PASSWORD` | An *Apple Development* certificate exported the same way | Optional, see Troubleshooting |

   With the GitHub CLI instead: `gh secret set ASC_KEY_P8 < AuthKey_XXXXXXXXXX.p8`, `gh secret set ASC_KEY_ID -b 2X9R4HXF34`, and so on.

5. Optional repository **variables** (same page, *Variables* tab):
   - `BUILD_NUMBER_OFFSET`: added to the run number to make the build number. Leave it unset (0) unless you've already uploaded builds by hand; then set it above the highest build number you used.
   - `XCODE_VERSION`: e.g. `26.0.1` to pin the Xcode. Unset means the newest non-beta Xcode on the runner.

Never commit the `.p8`, the `.p12` files or their passwords. `Config/Base.xcconfig` holds only the team ID and the Supabase anon key, which is public by design.

## 7. Fill in App Store Connect before the first submission

You can do this while waiting for Family Controls.

**App Privacy** (App ▸ App Privacy ▸ *Get Started*). Use **Label B** in [`docs/appstore/privacy.md`](appstore/privacy.md) §2:

- *Do you collect data?* **Yes**, for the push token only. Sync is **off on a new install** and uploads nothing until the user taps *Turn on sync* or links a device with *Enter a code* (Settings ▸ Sync). When it's on, tasks, plans and notes are end-to-end encrypted: sealed with AES-GCM under a key the server never receives, so the developer can't read them and they aren't declared.
- **Identifiers ▸ Device ID**: collected; App Functionality; not linked; not tracking. (The iPhone push token used for silent sync wake-ups, registered only while sync is on.)
- Nothing else: no user content, contact info, location, usage data, diagnostics or purchases. Screen Time data never leaves the device. (If you'd rather declare the plaintext record timestamps, add *Usage Data ▸ Product Interaction*, not linked, App Functionality. See privacy.md §2, note 3.)

**Before the first submission, bring the manifests in line:** `PrivacyManifests/iOSApp` and `PrivacyManifests/MacApp` still declare `NSPrivacyCollectedDataTypeOtherUserContent`, which matched the old label (from before end-to-end sync). Remove it, keep `NSPrivacyCollectedDataTypeDeviceID` on iPhone, or else declare Other User Content in App Store Connect too. If you change what the app sends, update `PrivacyManifests/*/PrivacyInfo.xcprivacy` and these answers together.

**Age rating** (App Information ▸ Age Rating). Answer honestly. The default nudge tone is *Direct*, which has no profanity. *Savage* is opt-in, labelled "Strong language", and still says "Wake the fuck up" on its strongest lines, so *Profanity or Crude Humor* is not "None". [`docs/appstore/review-notes.md`](appstore/review-notes.md) §6 recommends *Infrequent or Mild* and explains why. The app's own content has no web browsing and no user-to-user communication.

**Pricing and Availability**:
- Set the price.
- Under *iPhone and iPad Apps on Apple Silicon Macs*, **untick** availability: there is a dedicated Mac app, and Screen Time shielding doesn't work in the iPhone app on a Mac.
- Untick *Apple Vision Pro* for the same reason.

**Export compliance** is answered by the build: `ITSAppUsesNonExemptEncryption` is `false` because TrueFocus only uses encryption built into the OS (HTTPS through URLSession; AES-GCM, HKDF, SHA-256 and X25519 through CryptoKit). TestFlight won't ask the encryption question.

## 8. Run the Release workflow

Two ways to start it:

- **Tag** (normal releases): `git tag v1.0.0 && git push origin v1.0.0`. The tag sets the version (`1.0.0`); both the iPhone and the Mac jobs run.
- **By hand**: GitHub ▸ Actions ▸ *Release* ▸ *Run workflow*. Optional `version` (empty uses `MARKETING_VERSION` in `project.yml`), and the `ios` / `mac` switches.

What it does (`.github/workflows/release.yml`):

1. **Version numbers**: version from the tag or input; build number = GitHub run number + `BUILD_NUMBER_OFFSET`. Every bundle (apps and extensions) gets the same pair. The run log prints them.
2. **iPhone → TestFlight**: `xcodegen generate`, archive the `TrueFocus` scheme with automatic signing through the API key, then `xcodebuild -exportArchive` with `Config/ExportOptions/AppStore.plist`, which signs for App Store Connect and uploads the build.
3. **Mac → notarized download**: archive `TrueFocusMac`, export with Developer ID (`Config/ExportOptions/DeveloperID.plist`), notarize with `notarytool` (same API key), staple, zip. The zip is a run artifact, and on a tag it's attached to a **draft** GitHub release.

If a run fails after the iPhone upload succeeded, use *Re-run failed jobs*, not *Re-run all jobs*: a re-run keeps the run number, and App Store Connect refuses the same build number twice.

## 9. Test on TestFlight

1. App Store Connect ▸ TrueFocus ▸ **TestFlight**. The build appears as *Processing*, usually ready in 5–30 minutes. You get an email when it's done.
2. **Internal testing** (up to 100 people on your team, no review): *Internal Testing* ▸ `+` group ▸ add testers ▸ add the build. Install the **TestFlight** app on the iPhone and accept the invite.
3. **External testing** (friends, up to 10,000, by email or public link): create an external group and add the build. The first build of each version goes through *Beta App Review* (usually under a day). Fill in *Test Information* (what to test, contact email) first.
4. Test on a real iPhone. The simulator can't run Screen Time. Use this checklist:
   - [ ] First launch, notification permission, Brain dump → tasks → Focus.
   - [ ] Guard ▸ Enable: the Screen Time prompt appears and is approved (this proves the distribution entitlement is in the build).
   - [ ] Pick scroll apps; start focus; opening one shows the TrueFocus shield with the task name.
   - [ ] Shield **Reply · 2 min** on a reply app; the pass ends after two minutes.
   - [ ] Scroll budget: a small budget shields the apps after it's used up (DeviceActivity monitor).
   - [ ] Adult filter on; turning it off waits 24 hours.
   - [ ] Live Activity on the Lock Screen and Dynamic Island; buttons work while locked.
   - [ ] Home Screen and Lock Screen widgets; Control Center controls; "Done in TrueFocus" with Siri.
   - [ ] Safari extension: enable it in Settings ▸ Apps ▸ Safari ▸ Extensions; Reels/Shorts are removed.
   - [ ] Apple Music focus playlist (needs an Apple Music subscription; others hear the built-in music).
   - [ ] Sync is off on a fresh install: Settings ▸ Sync reads "Off on this device", and nothing syncs until *Turn on sync*.
   - [ ] Sync: *Turn on sync* on the Mac, *Link a device*; on the TestFlight iPhone, *Enter a code*. Both screens show the same four-digit number; *They match* on the Mac links them. A change on the Mac shows on the iPhone within seconds while it's in the background (production APNs).
   - [ ] *Turn off here* stops uploads on that device; *Delete server copy…* empties the space and turns sync off there.
   - [ ] A device that synced on an older build moves its space once (`tf-space` `rekey`) and keeps its data. Update every device before linking: new and old builds can't link to each other.
5. TestFlight builds expire after 90 days.

## 10. Publish the Mac download

1. Open the draft release (GitHub ▸ Releases) or the run's artifact `TrueFocus-<version>-<build>-mac`.
2. On a Mac, download the zip, unzip, move `TrueFocus.app` to Applications and open it. Gatekeeper should open it without any warning. You can also check in Terminal: `spctl -a -vv /Applications/TrueFocus.app` should say `accepted, source=Notarized Developer ID`.
3. Run the Mac part of [SETUP.md](SETUP.md): Safari extension, Chrome extension, linking with the iPhone.
4. Edit the draft release notes and **Publish**. Link to the zip from your website.

There is no automatic updater yet: people update by downloading the new zip. Adding Sparkle is the usual next step.

## 11. Submit the iPhone app for review

App Store Connect ▸ TrueFocus ▸ the iOS version (e.g. *1.0 Prepare for Submission*):

1. **Screenshots**: iPhone 6.9" (1320 × 2868 or 1290 × 2796) are required; the smaller sizes scale from them. No iPad screenshots: the app is iPhone-only.
2. **Promotional text, description, keywords, support URL, marketing URL** from the listing work. Copyright, e.g. `2026 <your legal name>`.
3. **Build**: *Add Build* ▸ pick the TestFlight build you tested.
4. **App Review Information**: *Sign-in required* off (there's no account). Contact details. Notes, ready to paste:

   > TrueFocus is a personal focus app. No account or sign-in is needed.
   >
   > To see the core loop: open the app, type a few tasks on the Brain dump page, keep them, pick the win, and start the first task. The focus screen shows one task and a clock; Done, Stuck, Switch and Pause are the moves.
   >
   > Screen Time: Guard ▸ Enable asks for Screen Time access for this device's user (FamilyControls, `.individual`). Then pick a couple of apps under Scroll apps and start a focus session; opening one of those apps shows TrueFocus's shield naming the current task. The shield and all limits go away when the session ends, or if access is revoked in Settings ▸ Screen Time. Screen Time data stays on the device.
   >
   > Sync: off until the user turns it on in Settings ▸ Sync. Then tasks and notes sync between the user's own iPhone and Mac through our server, end-to-end encrypted: the key never leaves the devices, and the server only stores ciphertext. Linking a second device is optional: a six-digit code, then both screens show the same four-digit number to confirm. Settings ▸ Sync also has *Turn off here* and *Delete server copy…*.
   >
   > The Safari extension (Settings ▸ Apps ▸ Safari ▸ Extensions ▸ TrueFocus) removes Reels/Shorts and counts scrolling on feed sites.
   >
   > The default nudge tone is "Direct". "Savage" is opt-in in Settings ▸ Voice and uses strong language.
   >
   > Background modes: "audio" plays the focus music the user starts during a session; "remote-notification" is a silent push that tells the app new sync data is waiting.

5. **Version Release**: choose *Manually release this version* for the first one.
6. **Add for Review** ▸ **Submit to App Review**. Reviews usually take one to two days. If you're rejected, answer in the Resolution Center; metadata-only fixes don't need a new build.
7. After approval, press **Release This Version**.

## 12. The next release

1. Merge the changes to `main`.
2. Tag the next version, e.g. `git tag v1.0.1 && git push origin v1.0.1`. The build number keeps rising by itself.
3. TestFlight check (step 9), publish the Mac release (step 10), then in App Store Connect ▸ `+ Version` ▸ `1.0.1`, add *What's New*, pick the build, submit (step 11).

You don't need to edit `MARKETING_VERSION` in `project.yml` for CI; bump it when you want local builds to show the new version.

---

## Troubleshooting

| Symptom (in the job log) | Cause | Fix |
| --- | --- | --- |
| iPhone export: *Provisioning profile … doesn't include the com.apple.developer.family-controls entitlement* or *… doesn't support the Family Controls (Distribution) capability* | The distribution entitlement isn't granted for one of the four IDs yet | Step 2. Check that all four IDs show Family Controls (Distribution). |
| *No suitable application records were found* | No App Store Connect record | Step 5 |
| *The bundle version must be higher than the previously uploaded version* / *has already been used* | Build number reused (re-run, or earlier manual uploads) | Set `BUILD_NUMBER_OFFSET` above the highest build uploaded |
| *Cloud signing permission error* or *No signing certificate "Developer ID Application" found* (Mac export) | The API key can't use the cloud-managed Developer ID certificate | Add `DEVELOPER_ID_P12_BASE64` + `DEVELOPER_ID_P12_PASSWORD` (step 4) |
| *You have reached the maximum number of certificates* / many *Created via API* development certificates | Each run on a clean runner may create a new Apple Development certificate | Revoke the old *Created via API* ones under Certificates, then add `APPLE_DEVELOPMENT_P12_BASE64` + `_PASSWORD` so runs reuse one |
| *Authentication failed* / 401 | Wrong key ID, issuer ID or `.p8`, or the key was revoked | Re-check the three `ASC_*` secrets; the key must be a **Team** key with Admin access |
| Notarization *Invalid* | The log printed after it names the binary and the problem | Usually a missing hardened runtime or an unsigned nested binary |
| Upload rejected: *built with a beta version of Xcode* | The runner picked a beta | Set the `XCODE_VERSION` variable |
| Upload rejected: *Missing purpose string* / *Missing privacy manifest* | A new framework or API was added without the plist key or manifest entry | Add the `NS…UsageDescription` in `project.yml`, or the reason to `PrivacyManifests/` |

The full `xcodebuild` logs are in each run's `release-logs-ios` / `release-logs-mac` artifacts.

---

## Mac: App Store or direct download

**Recommendation: ship the Mac app as a Developer ID–signed, notarized direct download.** Keep the iPhone app on the App Store.

What the Mac app does, and how each part fares in the Mac App Store's sandbox and review:

| Feature | How it's built | In the sandbox / review |
| --- | --- | --- |
| Browser bridge for Chrome-family browsers | `NWListener` on `127.0.0.1:52525` | Allowed with `com.apple.security.network.server`. Not a blocker. |
| Native doom-scroll watch | `NSEvent.addGlobalMonitorForEvents(.scrollWheel)` while a listed feed app is frontmost. No Accessibility, no `CGEventTap`, no AppleScript (browsers are covered by the extension) | Global mouse/scroll monitors work without Accessibility, but App Review may question a store app watching input in other apps. A risk, not a hard blocker. |
| Shielding Mac apps during focus | `NSRunningApplication.hide()` on other apps, plus a full-screen overlay at screen-saver level | An app that hides other apps the moment they come forward invites a rejection under guideline 2.4.5 / 2.5.9 (interfering with other apps and system behaviour). Untested in the sandbox. |
| Focus mode automation | Runs `/usr/bin/shortcuts run "TrueFocus On"` with `Process` | A sandboxed child process inherits the sandbox, and the `shortcuts` tool is unlikely to work there. It would need rewriting (for example `shortcuts://run-shortcut?name=…`, which brings Shortcuts to the front). |
| Chrome extension hand-off | Copies the bundled extension to Application Support and reveals it for *Load unpacked* | In the sandbox that folder is inside `~/Library/Containers/…`, which is hidden; it would need a save panel. |
| Open at login | `SMAppService.mainApp.register()`, **on first launch without asking** | Fine in the sandbox, but guideline 2.4.5(iii) requires consent first. It would need an explicit opt-in. |
| Sandbox today | `macOS/App/TrueFocus.entitlements` has no `com.apple.security.app-sandbox`; the app has never run sandboxed | The Mac App Store requires the sandbox on the app and every extension. |

Why Developer ID wins for v1:

- **Nothing has to change in the code.** The app ships exactly as it's tested today. The hardened runtime is already on, and the embedded Safari extension is already sandboxed, as Safari requires.
- **No review risk** for the hide-other-apps shield and the global scroll watch, which are core features.
- **Little to gain from the store.** The Mac bundle ID (`…truefocus.mac`) differs from the iPhone one, so there's no universal purchase anyway. Sync goes through Supabase, not anything store-only.
- **Same tooling.** The same API key signs, notarizes and uploads, and the `Release` workflow already does it.

The cost: no Mac App Store discovery and no store updates (add Sparkle when updates matter), and you host the download yourself (draft GitHub release).

If you want the Mac App Store later, you'd need to:

1. Add `com.apple.security.app-sandbox`, `com.apple.security.network.server` and `com.apple.security.network.client` to the Mac app's entitlements.
2. Replace the `shortcuts` CLI call, ask before turning on *Open at login*, and replace the Chrome-folder copy with a save panel.
3. Test the hide-on-activate shield and the scroll watch in a sandboxed build.
4. Create a macOS App Store Connect record for `com.youngjingoh.truefocus.mac`, and add a Mac App Store export (`method` `app-store-connect`, `destination` `upload`) to the workflow.

---

## Release-readiness audit (October 2026)

Fixed in config:

- Privacy manifests for the iPhone app, the Mac app and all six extensions (`PrivacyManifests/`, wired in `project.yml`). UserDefaults is the only required-reason API in use; there are no file-timestamp, boot-time, disk-space or keyboard APIs.
- `ITSAppUsesNonExemptEncryption = false` on the Mac app (the iPhone app already had it).
- Version and build number driven by CI (tag or input → `MARKETING_VERSION`, run number → `CURRENT_PROJECT_VERSION`) for every target.
- Release workflow: TestFlight upload plus a notarized Mac zip.

Checked and fine:

- Bundle IDs derive from `TF_BUNDLE_PREFIX`; extension IDs are children of their app's ID. The team comes from `Config/Base.xcconfig`, which `Config/Local.xcconfig` (git-ignored) can override.
- App icons: iPhone 1024 × 1024 universal icon with no alpha. Mac: all ten sizes from 16 pt to 512 pt @2x.
- Usage strings: `NSAppleMusicUsageDescription` is the only one needed. The other permissions (Screen Time, notifications, Live Activities) need no Info.plist string. Loopback networking needs no local-network string.
- Entitlements: App Groups on every target; Family Controls on the app and the three Screen Time extensions; push (`aps-environment` becomes `production` when the build is exported for the App Store); time-sensitive notifications. Mac: hardened runtime on the app and the Safari extension; sandbox on the Safari extension.
- Launch screen: `UILaunchScreen` with the `LaunchBackground` colour. Portrait only, iPhone only (`TARGETED_DEVICE_FAMILY = 1`). The app still installs on iPads in compatibility mode, which is fine.
- Minimum OS: iOS 26 / macOS 26. This is deliberate (Foundation Models, current SwiftUI) but limits the audience to devices on 26.
- Safari extensions are embedded in their apps with the shared `Extensions/web` resources; tests and `package.json` are excluded.

Open (owner decisions or code changes outside release config):

- **Family Controls (Distribution)** must be granted before any TestFlight build (step 2).
- **MusicKit** App Service must be on for `com.youngjingoh.truefocus`, or the Apple Music playlist falls back to the built-in music (step 3b).
- ~~Default tone is Savage~~. Resolved in `11f3952`: the default is *Direct*, and Savage is opt-in with a "Strong language" label. Profanity still has to be declared in the age rating (step 7).
- **Privacy manifests still declare Other User Content**, which no longer matches the App Privacy answers in step 7 now that sync is end-to-end. Fix the two manifests before the first submission.
- **Login item on first launch without asking** (`macOS/App/LoginItem.swift`). Acceptable for Developer ID, but it's friendlier (and required for the Mac App Store) to ask first. Its footnote also mentions Xcode ("Run TrueFocus from Applications rather than Xcode"), which end users shouldn't see.
- Mac `NSHumanReadableCopyright` is "Built for momentum." rather than a copyright line.
- No auto-update for the Mac app (Sparkle).
- The web extension's `manifest.json` version (`1.0.0`) is separate from the app version; bump it with releases if you publish to the Chrome Web Store.
