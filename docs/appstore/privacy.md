# Privacy: what leaves the device, the App Privacy label, the policy, and Screen Time answers

Everything in §1 comes from reading the code at `1da5526`: `Packages/TrueFocusKit/Sources/TrueFocusKit/Sync/*`,
`Shared/App/Sync/*`, `supabase/`, `iOS/`, `macOS/`, `iOSExtensions/` and `Extensions/web/`. The sync
parts (§1.3, §2, §3) were checked again after the end-to-end change (`1caee66`), against
`SyncSecrets.swift`, `SyncService.swift`, `SyncSettingsSection.swift`, `TFCloud.swift`,
`supabase/functions/tf-pair/index.ts` and `supabase/migrations/20261019000000_truefocus_e2e.sql`. Where
the code doesn't settle a question, this file says **Unclear** instead of guessing.

---

## 1. The facts

### 1.1 Third-party SDKs, analytics, tracking

- **No third-party SDKs.** `Packages/TrueFocusKit/Package.swift` declares no dependencies, and
  `project.yml` links only TrueFocusKit and Apple system frameworks. There's no CocoaPods, Carthage or
  other SwiftPM package.
- **No analytics, crash reporting, advertising or attribution.** The code contains no Firebase,
  Sentry, Mixpanel, Amplitude, TelemetryDeck, PostHog, AdSupport, ATT or IDFA.
- **No tracking** in Apple's sense. Nothing is shared with data brokers or used for ads, and no
  data is combined with other companies' data.
- The web extension has no dependencies at all: `package.json` has none, and its scripts are plain JS.

### 1.2 Network destinations (exhaustive)

| From | To | What | Code |
| --- | --- | --- | --- |
| iPhone app, Mac app | `fcfbsgvkanuywsmxvuee.supabase.co` (Supabase: PostgREST + Edge Functions) | Only once the user turns sync on or links the device: sync records, push-token registration, linking (public keys and a sealed box), wake-up requests, the one-time `tf_rekey` move, and `tf_delete_space` when the user deletes the server copy | `TFCloud.swift`, `SyncService.swift` |
| Supabase Edge Function `tf-notify` | Apple Push Notification service (`api.push.apple.com`) | A silent push `{"aps":{"content-available":1},"tf":"sync"}` to the space's other iPhones. **No content.** | `supabase/functions/tf-notify/index.ts` |
| iPhone app (only if the user picks "Apple Music" as focus music) | Apple Music (MusicKit) | Music authorization, a subscription check, a catalog search for the playlist "Pure Focus", playback | `AudioDirector.startAppleMusic` |
| Safari extension | The app, through `sendNativeMessage` and the App Group (stays on the device) | Read state; post boot-out `{site, reason}` and juggling commands | `background.js`, `SafariWebExtensionHandler.swift` |
| Chrome-family extension | `http://127.0.0.1:52525` (the Mac app, loopback only) | The same, over HTTP | `background.js`, `ExtensionBridgeServer.swift` |
| Brain-dump → tasks | Apple's on-device model (`FoundationModels`). **Nothing goes off the device.** | — | `TaskExtractor.swift` |

There are no other URLs in the apps or the extension. `rules_*.json` *redirect* matching
navigations to pages inside the extension, and they send nothing anywhere.

### 1.3 What the sync server receives

Sync is **off on a new install**. Nothing goes to the sync server until the user taps **Turn on sync**
or links the device with **Enter a code** in Settings ▸ Sync (`SyncService.isEnabled`, stored per
device as `tf.sync.enabled`). A device that synced with an earlier build stays on: its ledger names a
space, or its Keychain already holds a key (`SyncService.resolveEnabled`). The same check turns sync
back on after a reinstall that finds a key left in the Keychain.

Turning sync on creates a random 256-bit *space key* and stores it in the Keychain
(`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not iCloud Keychain). **The space key never goes
to the server**, except once for spaces made by older builds (see "The one-time move" below). Two
keys are derived from it with HKDF-SHA256, salt `"truefocus.sync"` (`SyncSecrets.swift`):

- the **access token** (info `"access.v1"`, base64url, `SyncAccess`), which goes in the `x-tf-space`
  header of every request, and
- the **payload key** (info `"payload.v1"`, `SyncCipher`), which seals each payload with AES-GCM
  and never leaves the device.

The server can't get from the access token to the payload key: both come one way from the space key.

**Table `tf_records`, one row per task, focus segment, day plan or note:**

| Column | In plain text on the server? | Content |
| --- | --- | --- |
| `space` | yes | SHA-256 of the access token (`tf_space()`), a pseudonymous ID shared by linked devices |
| `id` | yes | Random UUID; for a day plan, the day encoded into the UUID (`RecordID.plan`) |
| `kind` | yes | `task` / `segment` / `plan` / `note` |
| `deleted` | yes | Tombstone flag |
| `modified_at`, `updated_at` | yes | Timestamps of edits |
| `data` | **no: AES-GCM ciphertext** | The payload below |

The encrypted payloads (`SyncModels.swift`):

- **Task:** title, done flag and time, created time, order, focus seconds, breadcrumb ("where I
  left off"), whether it's in play and since when, and whether it's waiting and since when.
- **Segment** (the focus timeline): mode (focus/think/rest), task ID, task title, start and end, outcome,
  planned seconds, and device label (`"iPhone"` or `"Mac"`, a constant, **not** the user's device name).
- **Day plan:** day, "the win", the full **brain-dump text**, the boot-out *count*, when the day was
  ended, and the reflection line.
- **Note:** body text, created/updated, pinned.

When a record is deleted, its row becomes a tombstone with an empty payload.

**Table `tf_devices` (iPhone only, and only while sync is on):** the APNs device token, platform
`ios`, environment, `updated_at` and the space ID, **all in plain text**. The Mac never registers a
token. *Turn off here* doesn't remove the token. *Delete server copy…* does.

**Table `tf_pairings`, while linking (`tf-pair` `host` / `join` / `wait` / `seal` / `fetch`):** the
six-digit code and its expiry, the host's and the joiner's X25519 **public keys**, and the **sealed
box**: the space key under AES-GCM with a key the two devices derive from their X25519 exchange.
The server holds none of the private keys, so it can't open the box. `space_key` stays empty for
these rows. A row is deleted when the joiner fetches the box. An expired row is deleted only the next
time anyone calls `tf-pair`, so it can outlive its 10 minutes.

**Table `tf_pair_failures`:** one timestamp per failed join, nothing else. They drive the global
lock after 40 misses in 10 minutes.

**On every request:** the access token in the `x-tf-space` header (the database keeps only its
hash), the public anon key, the device's IP address, and the default `URLSession` user agent (app
name and build, CFNetwork and Darwin versions). Whoever holds an access token can read, overwrite
and delete that space's ciphertext, but can't decrypt it. **Unclear:** whether Supabase's managed
API and edge-function logs keep the `x-tf-space` header. Check Logs Explorer in the dashboard.

**The one-time move.** Older builds filed a space under `sha256(space key)` and sent the raw key on
every request. On its first sync after the update, each such device calls the RPC `tf_rekey` once
(`SyncService.cycle`, `TFCloud.rekey`). That request carries the raw key in `x-tf-space`, the last
time it travels, and the new access token in the body. The server moves the space's records and push
tokens to `sha256(access token)`, merging by last writer wins, and deletes the old rows. Spaces made
by this build, or adopted by linking, never make the call.

> **Is sync end-to-end encrypted? Yes.** Payloads are sealed on the device under a key the server
> never receives and can't derive. Requests carry a separate one-way access token. Linking passes
> the key sealed between the two devices. So the server operator, Supabase, a database dump and
> request logs can't read tasks, notes, the brain dump or the timeline. The honest caveats:
>
> 1. **Metadata is visible.** The server sees how many records a space has, their kinds and IDs (a
>    day plan's ID encodes its day), the `modified_at` / `updated_at` timestamps, the deleted flags,
>    the size of each ciphertext, iPhone push tokens and IP addresses. The timestamps show *when*
>    someone works, though not on what.
> 2. **Builds older than this release keep the legacy paths until they update.** They send the raw
>    space key on every request, and they link with `tf-pair` `create` / `redeem`, which stores the
>    raw key in `tf_pairings.space_key` for up to ten minutes. New builds never call those actions,
>    which are due for removal. No App Store build has the legacy paths, because 1.0 is the first
>    release. They exist only in development, TestFlight and `docs/SHARING.md` builds made before
>    `1caee66`.
> 3. **The one-time `tf_rekey` request sends the legacy key once.** The key isn't rotated by the
>    move. For a space that an older build created, the server already saw that key on every earlier
>    request, so its protection depends on nothing having kept it (a log, for instance). To start
>    clean, use *Delete server copy…* on every device in the space, then *Turn on sync* on one
>    (which makes a new key), and link the others to it again.
> 4. **The match number is four digits.** Linking uses a commitment step: the host publishes only a
>    hash of its public key, the joiner sends its key only once it holds that hash, and the host
>    reveals its key only after the joiner's is in (`tf-pair`, `PairingSecret`). A server in the
>    middle must fix every key it shows either side before it can know the other side's number, so
>    it gets one guess per link: the screens agree by chance 1 time in 10,000, and every failed
>    attempt shows the user two different numbers.

### 1.4 What never leaves the device

- **Screen Time data.** The `FamilyActivitySelection` (opaque app, category and domain tokens),
  Reply-pass state, budget and cooldown state all sit in `GuardConfig`, saved in the App Group
  (`GuardStore`). It isn't part of any sync payload. The app reads no usage reports: it has no
  DeviceActivityReport extension, and the monitor only receives threshold and interval callbacks.
- **Settings** (`TFSettings`: tone, custom reminder text, budgets, always-allowed sites, Mac blocked
  apps, the filter cool-off) stay in the App Group, and they aren't synced. Sync carries only the four
  record kinds above.
- **Boot-out details** (site name, reason) stay in the App Group. Only the daily *count* is synced,
  inside the encrypted day plan.
- **Browsing.** The extension looks at URLs, scroll and touch events and four scroll keys (Space,
  PageDown, `j`, ↓) on the 14 feed sites in `manifest.json`, and decides locally. It stores only
  preferences, cooldown times per site and a daily boot count in `storage.local`. It never reads
  page text, form fields or cookies, and it never sends URLs anywhere.
- **Mac scroll watch.** It reads `scrollingDeltaY` while a listed feed app is frontmost: distance only,
  with no screen contents and no keystrokes.
- **Notes, tasks and the brain dump**, except in their end-to-end encrypted form on the sync server
  once sync is on, as above. With sync off, nothing goes to the server at all.

---

## 2. App Privacy "nutrition label" answers

Apple's definition: data is *collected* if it's "transmitted off the device in a way that allows you
and/or your third-party partners to access it for a period longer than what is necessary to service
the transmitted request in real time". Since `1caee66` the developer can't read the synced content
(§1.3), so the encrypted payloads are no longer declared. **Label B is the one to submit.** Label A
is kept below only as history.

### Label B: end-to-end sync (submit this)

**Do you or your third-party partners collect data from this app?** → **Yes** (iPhone), because of
the push token.

| Data type | Collected? | Linked to the user? | Used for tracking? | Purposes | Why |
| --- | --- | --- | --- | --- | --- |
| **Contact Info** (name, email, phone, address, other) | No | — | — | — | No account, no form, no contact fields |
| **Health & Fitness** | No | — | — | — | — |
| **Financial Info** | No | — | — | — | No purchases in the code |
| **Location** (precise / coarse) | No | — | — | — | No Core Location. Supabase sees IP addresses but doesn't use them to derive location |
| **Sensitive Info** | No | — | — | — | — |
| **Contacts** | No | — | — | — | — |
| **User Content** (all subtypes) | No | — | — | — | Task titles, breadcrumbs, the brain dump, the day's win, reflections and note bodies reach the server only end-to-end encrypted, under a key the developer never has (§1.3) |
| **Browsing History** | No | — | — | — | The extension decides on the device and never transmits URLs |
| **Search History** | No | — | — | — | — |
| **Identifiers → User ID** | No (see note 2) | — | — | — | — |
| **Identifiers → Device ID** | **Yes (iPhone record only)** | **No** | No | **App Functionality** | The APNs device token in `tf_devices`, used for silent sync wake-ups, stored once sync is on |
| **Purchases** | No | — | — | — | — |
| **Usage Data → Product Interaction** | No (see note 3) | — | — | — | The focus timeline is in the encrypted payloads |
| Usage Data → Advertising Data / Other Usage Data | No | — | — | — | — |
| **Diagnostics** (crash, performance, other) | No | — | — | — | No crash SDK. Apple's own crash reports don't count |
| **Surroundings / Body** | No | — | — | — | — |
| **Other Data** | No | — | — | — | — |

The **Mac record**, if there ever is one (the Mac app ships as a Developer ID download, see
`docs/RELEASE.md`), answers **Data Not Collected**: the Mac never registers a push token.

**Notes on the judgement calls:**

1. **"Not linked to the user."** There's no account, name, email or phone number. The only key is a
   random space ID (a hash of the access token) that the developer can't tie to a person. Apple
   counts data as linked when it's tied to "the user's identity (via their account, device, or other
   details)". A random space with no identity data qualifies as de-identified. The conservative
   alternative is to mark Device ID as *Linked to You*. The label then reads worse but stays safe.
2. **User ID.** The space ID is an assigned ID for a *group of devices*. It's used only to keep one
   person's records apart from another's. Most anonymous-sync apps don't declare it separately.
   Declare it (App Functionality, not linked) if you took the conservative route in note 1.
3. **Plaintext metadata.** Record `kind`, `modified_at` and `updated_at` are in plain text, so the
   server can tell *when* someone works, though not on what. That isn't the "app launches, taps,
   clicks" Apple lists under Product Interaction, so this label leaves it out. If you'd rather not
   defend that, declare **Usage Data → Product Interaction** (App Functionality, not linked, not
   tracking). It costs little.
4. **The APNs token as Device ID.** Apple doesn't say whether push tokens count. Declaring it is
   the cautious choice and costs little.
5. **IP addresses** seen by Supabase aren't a data type in Apple's list unless you use them, for
   example to derive location. The code doesn't.
6. **Apple Music, APNs and Apple Intelligence** are Apple's services. Data Apple handles under its
   own policy isn't declared by the developer.
7. **Keep the privacy manifests in step.** `PrivacyManifests/iOSApp/PrivacyInfo.xcprivacy` declares
   only `NSPrivacyCollectedDataTypeDeviceID`, and `PrivacyManifests/MacApp/PrivacyInfo.xcprivacy`
   declares nothing, matching Label B. Change them together with the label.

### Label A: before end-to-end sync (history, don't submit)

Until `1caee66`, every request carried the raw space key, and linking stored it in `tf_pairings`, so
the developer *could* have decrypted the payloads. Label A therefore declared **User Content → Other
User Content** and **Usage Data → Product Interaction** (both App Functionality, not linked, not
tracking) as well as **Identifiers → Device ID** (iPhone). It no longer describes the App Store build.

---

## 3. Privacy policy (ready to host)

> Replace every `[BRACKETED]` placeholder. Host it at the Privacy Policy URL in `listing.md`.
> It describes the end-to-end sync shipped since `1caee66` (Label B).

```markdown
# TrueFocus Privacy Policy

Effective [EFFECTIVE DATE]

TrueFocus is made by [DEVELOPER LEGAL NAME] ("we"). This policy covers the TrueFocus apps for
iPhone and Mac and the TrueFocus browser extension for Safari and Chrome.

## The short version

- There's no account. We never ask for your name, email or phone number.
- There are no ads, no analytics, no tracking and no third-party SDKs.
- Your Screen Time choices, your app usage and your browsing stay on your device.
- Sync between your iPhone and Mac is off until you turn it on. When it's on, your tasks, notes and
  focus timeline are end-to-end encrypted: they're sealed on your device with a key that stays on
  your devices, and we can't read them.
- You can turn sync off, or delete everything on our server, in Settings ▸ Sync.

## What stays on your device

- **Screen Time.** TrueFocus uses Apple's Screen Time framework, with your permission, to shield the
  apps you pick, run your scroll budget and filter adult websites. Apple gives TrueFocus only
  anonymous tokens for the apps and sites you choose, not their names or your usage history.
  These stay on your iPhone and are never uploaded.
- **Browsing.** The browser extension checks the address of pages on a short list of feed sites
  (such as Instagram, YouTube, Facebook and LinkedIn) and counts how far you scroll there, so it can
  remove short-form video and stop doom-scrolling. It blocks known adult sites. It decides all of
  this on your device. It doesn't read page text, forms or cookies, and it never sends the pages
  you visit anywhere. On a Mac, it talks only to the TrueFocus app on the same Mac.
- **Scrolling on the Mac.** While a feed app is in front, the Mac app counts how far you scroll.
  It never reads what's on screen or what you type.
- **Settings**, including your tone, your own reminder words, budgets and allowed sites.
- **Turning a brain dump into tasks** uses Apple Intelligence on your device when it's available.
  Nothing is sent to us or to anyone else for this.
- **Everything, while sync is off.** With sync off, TrueFocus sends nothing to our server until
  you turn it on or link a device.

## What we receive when sync is on, and why

TrueFocus syncs your devices through a server we run on Supabase ([SUPABASE REGION, e.g. "the
EU (Frankfurt)" — check in the Supabase dashboard]). When you turn sync on, your device makes a
random key and keeps it in its Keychain. That key never leaves your devices. The server receives:

- **Your tasks, notes and day plans** (task titles, notes, the morning brain dump, the day's win,
  your reflection) and **your focus timeline**, **end-to-end encrypted** with AES-256-GCM on your
  device before upload. The server stores only the encrypted copy. We don't have the key and
  can't decrypt it.
- **Record details the server needs to sync:** a random ID for each record, its type (task, note,
  session or day), when it was last changed, and whether it was deleted. These aren't encrypted, so
  we could see how many records you have and when they changed, though not what they say.
- **A sync ID:** a fingerprint (SHA-256 hash) of an access code your device derives from its key.
  It ties your linked devices together. It isn't connected to your name or any account, and the
  key can't be worked out from it.
- **On iPhone, a push token**, so the server can silently wake your phone to sync when your Mac
  changes something. The wake-up carries no content.
- **When you link a device:** a six-digit code, a public key from each device, and your key sealed
  so that only the device you're linking can open it. Both screens show the same four-digit number
  before anything is sent. This is deleted once the new device has the key. If linking doesn't
  finish, the code stops working after ten minutes and the record is cleared out after that.
- **The usual connection details,** such as your IP address, which our hosting provider sees on
  every internet request.

**If your device used an earlier version of TrueFocus,** it sends its old key to the server once,
over an encrypted connection, to move your synced data to the new end-to-end scheme. After that,
the key never leaves your devices.

We use this data only to sync your devices. We don't sell it, share it, use it for advertising,
or combine it with other data.

## Apple services

- **Apple Music.** If you choose Apple Music as focus music, TrueFocus asks for permission and plays
  a playlist through Apple's MusicKit. Apple handles that under its own privacy policy. We receive
  nothing.
- **Notifications.** Nudges are scheduled on your device. Silent sync wake-ups go through Apple's
  push service.

## Who processes data for us

- **Supabase, Inc.** hosts the sync database and functions.
- **Apple** delivers push notifications.

No one else.

## How long we keep it

Encrypted records stay on the server while your devices use them, or until you delete them in
Settings ▸ Sync. When you delete a task or note, its encrypted content is removed from the server
and a small "deleted" marker remains so your other devices delete it too. [RETENTION POLICY: e.g.
"Records in a sync space with no activity for 12 months are deleted." Add this once a cleanup job
exists. See the note for the owner below.]

## Your choices

- **Leave sync off.** It's off until you turn it on in Settings ▸ Sync. TrueFocus works fully on
  one device without it.
- **Turn sync off on a device:** Settings ▸ Sync ▸ **Turn off here**. That device stops sending
  anything. It keeps its key, so turning sync back on carries on where it was. What's already on the
  server stays there until you delete it.
- **Delete your data from the server:** Settings ▸ Sync ▸ **Delete server copy…** deletes every
  synced record and push token for your sync space right away, turns sync off on that device and
  forgets its key. Your devices keep their own copies. Other linked devices that still have sync on
  will upload their future changes again, so turn sync off or delete the server copy on each of them
  too.
- **Don't grant Screen Time access,** or revoke it any time in Settings ▸ Screen Time. The task flow
  still works without it.
- **Remove the extension** any time from Safari or Chrome settings.
- **Deleting the app** removes everything on that device.
- **Access, correction and portability:** your data is on your devices in readable form. On the
  server it's end-to-end encrypted, so we can't read it or hand you anything but ciphertext. We also
  can't find your sync space from the Sync ID shown in Settings, so please use **Delete server copy…**
  rather than asking us to delete it.

## Children

TrueFocus isn't directed at children under [13 / 16 — match the age rating] and doesn't knowingly
collect data from them.

## Security

Connections use HTTPS. Content is end-to-end encrypted on your device with AES-256-GCM, under a
key that never leaves your devices. The database only answers requests that carry the access code
for the matching sync space.

## Changes

If this policy changes, we'll update the date above and say what changed in the app's release notes.

## Contact

[DEVELOPER LEGAL NAME] · [CONTACT EMAIL] · [WEBSITE URL] · [POSTAL ADDRESS, if you sell in the EU/UK]
```

**Notes for the owner before hosting:**

- **Retention.** Nothing in `supabase/` deletes rows on a schedule. `tf_delete_space` deletes a
  space when a device asks, but a space whose devices are all lost stays forever, because no one
  can call it any more. Either add a cleanup job (a `pg_cron` job that deletes spaces idle for 12
  months) and state it, or write "until you delete it in Settings ▸ Sync".
- **Deletion requests by email can't be served by Sync ID any more.** The Sync ID in Settings is the
  first 8 hex characters of `SHA-256(space key)`. The server's `space` is now `SHA-256(access token)`,
  so the two no longer match, and the old `space like '<id>%'` procedure finds nothing. That's why the
  policy points to **Delete server copy…**. Someone who has lost every device can't be helped, beyond
  the retention job above.
- **"Turn off here" leaves the push token on the server**, so other iPhones in the space keep sending
  silent pushes to this one. It ignores them while sync is off. The policy above doesn't claim the
  token is removed.
- **The four-digit match number** (§1.3, caveat 4): the policy says both screens show the same
  number and that you should cancel if they don't. A hostile server gets one guess per link (1 in
  10,000), so the policy doesn't promise it can never succeed.
- The Supabase project is **shared with another app (ListingLine)**, according to the migration header and
  `docs/SETUP.md`. That's fine legally, since it's the same controller, but anyone with access to that
  project can see the TrueFocus tables (ciphertext and metadata). The access group for the project is
  also the access group for TrueFocus users' sync metadata.

---

## 4. Family Controls / Screen Time: data-use answers

For the **Family Controls (Distribution)** entitlement request (developer.apple.com ▸ Account ▸
request Family Controls), and for App Review if it asks. Apple's form wording changes. These answers
cover the questions it has asked: what the app does, the authorization type, the data accessed, and
whether data is shared.

**Request the entitlement for all four bundle IDs that carry `com.apple.developer.family-controls`:**

| Target | Bundle ID |
| --- | --- |
| App | `com.youngjingoh.truefocus` |
| Device Activity Monitor extension | `com.youngjingoh.truefocus.monitor` |
| Shield Configuration extension | `com.youngjingoh.truefocus.shieldconfig` |
| Shield Action extension | `com.youngjingoh.truefocus.shieldaction` |

**What does your app do with Family Controls?**
TrueFocus is a self-control focus app for adults. The person using the iPhone chooses which of their
own apps distract them. TrueFocus then (1) shields those apps while they're working on a task,
(2) gives them a daily time budget for those apps outside work, after which the apps are
shielded for a cooldown of 15 minutes or more, (3) lets them open apps they marked for messaging for a
short "Reply" pass a limited number of times a day, and (4) turns on Screen Time's adult-website
filter. Turning that filter off takes effect only after a 24-hour cool-off, which the user can cancel.

**Which authorization do you request?**
`AuthorizationCenter.shared.requestAuthorization(for: .individual)`. It's individual
authorization only. The user approves it with Face ID, Touch ID or their passcode. There's no parental or
guardian mode, no Family Sharing and no child accounts.

**Which frameworks and extensions?**
FamilyControls (`FamilyActivityPicker`, authorization), ManagedSettings (three named stores: `tf.focus`,
`tf.scrollBudget`, `tf.adultFilter`), ManagedSettingsUI (a custom shield that shows the user's current
task, with a "Back to work" button and an optional "Reply · 2 min" button), and DeviceActivity
(a daily schedule with a usage threshold event, plus one-off schedules for cooldowns, Reply passes and
the filter cool-off). There's no DeviceActivityReport extension.

**What data do you access?**
Only what the user picks in `FamilyActivityPicker`: opaque `ApplicationToken`, `ActivityCategoryToken`
and `WebDomainToken` values, plus DeviceActivity callbacks when a threshold is reached or an interval
starts or ends. TrueFocus never sees app names (the shield extension gets `localizedDisplayName` from the
system only to display it), app usage history or browsing history.

**Where is that data stored? Is it transmitted, shared or sold?**
It's stored on the device only, in the App Group container shared by the app and its extensions
(`GuardConfig` in `UserDefaults(suiteName:)`). It's **never transmitted**. It isn't part of the app's
sync payloads, it isn't sent to any server, and it isn't shared with or sold to anyone. Nothing from
Screen Time is used for advertising, analytics or profiling.

**Can the user turn it off?**
Yes, at any time. They can revoke access in Settings ▸ Screen Time ▸ (apps with access) or delete the app,
and either removes every shield and the filter immediately. Inside the app, "Shield during focus" can
be switched off and the selections cleared. The 24-hour cool-off applies only to switching the adult
filter off *inside TrueFocus*. It's a speed bump the user signed up for, not a lock, and the
system-level revoke always works.

**Is this a parental-control app?**
No. It's a self-management tool for the device owner. The App Store listing and the age rating don't
present it as parental control.
