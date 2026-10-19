# Privacy: what leaves the device, the App Privacy label, the policy, and Screen Time answers

Everything in §1 comes from reading the code at `1da5526`: `Packages/TrueFocusKit/Sources/TrueFocusKit/Sync/*`,
`Shared/App/Sync/*`, `supabase/`, `iOS/`, `macOS/`, `iOSExtensions/` and `Extensions/web/`. Where
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
| iPhone app, Mac app | `fcfbsgvkanuywsmxvuee.supabase.co` (Supabase: PostgREST + Edge Functions) | Sync records, push-token registration, pairing, wake-up requests | `TFCloud.swift`, `SyncService.swift` |
| Supabase Edge Function `tf-notify` | Apple Push Notification service (`api.push.apple.com`) | A silent push `{"aps":{"content-available":1},"tf":"sync"}` to the space's other iPhones. **No content.** | `supabase/functions/tf-notify/index.ts` |
| iPhone app (only if the user picks "Apple Music" as focus music) | Apple Music (MusicKit) | Music authorization, a subscription check, a catalog search for the playlist "Pure Focus", playback | `AudioDirector.startAppleMusic` |
| Safari extension | The app, through `sendNativeMessage` and the App Group (stays on the device) | Read state; post boot-out `{site, reason}` and juggling commands | `background.js`, `SafariWebExtensionHandler.swift` |
| Chrome-family extension | `http://127.0.0.1:52525` (the Mac app, loopback only) | The same, over HTTP | `background.js`, `ExtensionBridgeServer.swift` |
| Brain-dump → tasks | Apple's on-device model (`FoundationModels`). **Nothing goes off the device.** | — | `TaskExtractor.swift` |

There are no other URLs in the apps or the extension. `rules_*.json` *redirect* matching
navigations to pages inside the extension, and they send nothing anywhere.

### 1.3 What the sync server receives

Sync runs **automatically on every launch** whenever the build has `TF_SUPABASE_HOST` set, and the
App Store build does. There's no switch to turn it off. On first launch the device creates a random
256-bit *space key*, stores it in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
not iCloud Keychain), and starts uploading.

**Table `tf_records`, one row per task, focus segment, day plan or note:**

| Column | In plain text on the server? | Content |
| --- | --- | --- |
| `space` | yes | SHA-256 of the space key (a pseudonymous ID shared by linked devices) |
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

**Table `tf_devices` (iPhone only):** the APNs device token, platform `ios`, environment, `updated_at` and
the space hash, **all in plain text**. The Mac never registers a token.

**Table `tf_pairings`, while linking:** the **raw space key** plus the six-digit code and its
expiry. The row is deleted when the code is redeemed. An expired row is deleted only the next time
anyone calls `tf-pair`, so it can outlive its 10 minutes.

**On every request:** the raw space key in the `x-tf-space` header, the public anon key, the
device's IP address, and the default `URLSession` user agent (app name and build, CFNetwork and
Darwin versions).

> **Is sync end-to-end encrypted? Not strictly.** The payloads are encrypted on the device with
> AES-GCM under `HKDF-SHA256(spaceKey, salt "truefocus.sync", info "payload.v1")`, and the database
> holds only ciphertext and a hash. So someone with read access to the database alone can't read
> anything. **But the space key itself, the input to that HKDF, reaches the server on every
> request**, both in the `x-tf-space` header that `tf_space()` hashes and in the body of
> `tf-pair create`. Anyone who can see request headers or pairing rows (the Supabase project owner,
> Supabase staff, a malicious edge function, or a log that records headers) could derive the key and
> decrypt everything in that space. **Unclear:** whether Supabase's managed API/edge logs keep the
> `x-tf-space` header. Check Logs Explorer in the dashboard. Either way, the design gives the server
> operator the ability to decrypt.
>
> **The fix, to earn an "end-to-end" claim:**
> 1. Derive two keys from the space key: `authToken = HKDF(spaceKey, info "auth.v1")` for
>    `x-tf-space`, and `payloadKey = HKDF(spaceKey, info "payload.v1")` for AES-GCM. Send only
>    `authToken`. The server hashes it exactly as it does today. Existing spaces migrate by
>    re-uploading under the new space hash.
> 2. Stop sending the raw key through `tf-pair`. Six digits are too few to protect it against the
>    server, which could brute-force 10⁶ codes offline. Show a QR code (or a longer code) that carries
>    a random 128-bit secret, upload only `AES-GCM(secret, spaceKey)`, and let the joining device
>    decrypt it locally. A PAKE such as SPAKE2 would also work.
>
> Until then, say "encrypted on your device; the server stores only encrypted data", which is true,
> and drop "end-to-end" from the README and any marketing.

### 1.4 What never leaves the device

- **Screen Time data.** The `FamilyActivitySelection` (opaque app, category and domain tokens),
  Reply-pass state, budget and cooldown state all sit in `GuardConfig`, saved in the App Group
  (`GuardStore`). It isn't part of any sync payload. The app reads no usage reports: it has no
  DeviceActivityReport extension, and the monitor only receives threshold and interval callbacks.
- **Settings** (`TFSettings`: tone, budgets, always-allowed sites, Mac blocked apps, the filter
  cool-off) stay in the App Group, and they aren't synced.
- **Boot-out details** (site name, reason) stay in the App Group. Only the daily *count* is synced,
  inside the encrypted day plan.
- **Browsing.** The extension looks at URLs, scroll and touch events and four scroll keys (Space,
  PageDown, `j`, ↓) on the 14 feed sites in `manifest.json`, and decides locally. It stores only
  preferences, cooldown times per site and a daily boot count in `storage.local`. It never reads
  page text, form fields or cookies, and it never sends URLs anywhere.
- **Mac scroll watch.** It reads `scrollingDeltaY` while a listed feed app is frontmost: distance only,
  with no screen contents and no keystrokes.
- **Notes, tasks and the brain dump**, except in their encrypted form on the sync server, as above.

---

## 2. App Privacy "nutrition label" answers

Apple's definition: data is *collected* if it's "transmitted off the device in a way that allows you
and/or your third-party partners to access it for a period longer than what is necessary to service
the transmitted request in real time". Because of the key issue in §1.3, the developer *can*
access the synced content, so it has to be declared. Two versions follow: **A** for the current code,
which is the one to submit, and **B** for after the §1.3 fix.

### Label A: current code (submit this)

**Do you or your third-party partners collect data from this app?** → **Yes**

| Data type | Collected? | Linked to the user? | Used for tracking? | Purposes | Why |
| --- | --- | --- | --- | --- | --- |
| **Contact Info** (name, email, phone, address, other) | No | — | — | — | No account, no form, no contact fields |
| **Health & Fitness** | No | — | — | — | — |
| **Financial Info** | No | — | — | — | No purchases in the code |
| **Location** (precise / coarse) | No | — | — | — | No Core Location. Supabase sees IP addresses but doesn't use them to derive location |
| **Sensitive Info** | No | — | — | — | — |
| **Contacts** | No | — | — | — | — |
| **User Content → Other User Content** | **Yes** | **No** | No | **App Functionality** | Task titles, breadcrumbs, the brain dump, the day's win, reflections and note bodies, encrypted, so devices can sync |
| User Content → Emails or Text Messages / Photos or Videos / Audio / Gameplay / Customer Support | No | — | — | — | — |
| **Browsing History** | No | — | — | — | The extension decides on the device and never transmits URLs |
| **Search History** | No | — | — | — | — |
| **Identifiers → User ID** | No (see note 2) | — | — | — | — |
| **Identifiers → Device ID** | **Yes (iPhone record only)** | **No** | No | **App Functionality** | The APNs device token in `tf_devices`, used for silent sync wake-ups |
| **Purchases** | No | — | — | — | — |
| **Usage Data → Product Interaction** | **Yes** | **No** | No | **App Functionality** | The focus timeline: when sessions start and end, their mode and outcome, focus seconds and the boot-out count, encrypted, so devices can sync |
| Usage Data → Advertising Data / Other Usage Data | No | — | — | — | — |
| **Diagnostics** (crash, performance, other) | No | — | — | — | No crash SDK. Apple's own crash reports don't count |
| **Surroundings / Body** | No | — | — | — | — |
| **Other Data** | No | — | — | — | — |

The **Mac record** gets the same answers, but **without Device ID**, because the Mac never registers a
push token.

**Notes on the judgement calls:**

1. **"Not linked to the user."** There's no account, name, email or phone number. The only key is a
   random space hash that the developer can't tie to a person. Apple counts data as linked when it's
   tied to "the user's identity (via their account, device, or other details)". A random space with no
   identity data qualifies as de-identified. The conservative alternative is to mark the three types as
   *Linked to You*, and if you'd rather never have to defend the call, do that. The label then reads
   worse but stays safe.
2. **User ID.** The space hash is an assigned ID for a *group of devices*. It's used only to keep one
   person's records apart from another's, never on its own, and it's covered by the types above. Most
   anonymous-sync apps don't declare it separately. Declare it (App Functionality, not linked) if you
   took the conservative route in note 1.
3. **The APNs token as Device ID.** Apple doesn't say whether push tokens count. Declaring it is
   the cautious choice and costs little.
4. **IP addresses** seen by Supabase aren't a data type in Apple's list unless you use them, for
   example to derive location. The code doesn't.
5. **Apple Music, APNs and Apple Intelligence** are Apple's services. Data Apple handles under its
   own policy isn't declared by the developer.

### Label B: after the §1.3 fix (key never sent to the server, pairing doesn't reveal it)

Once the server can't decrypt anything, the payloads are no longer accessible to the developer:

| Data type | Collected? | Linked? | Tracking? | Purpose |
| --- | --- | --- | --- | --- |
| Identifiers → Device ID (iPhone) | Yes | No | No | App Functionality |
| Everything else | No | — | — | — |

Even then, keep declaring Product Interaction if you add any plaintext metadata. The record
`kind` and `modified_at` timestamps already reveal *when* someone works. Declaring that is
defensible either way.

---

## 3. Privacy policy (ready to host)

> Replace every `[BRACKETED]` placeholder. Host it at the Privacy Policy URL in `listing.md`.
> It describes the **current** code (Label A). Update the "How sync works" section if you ship the
> §1.3 fix.

```markdown
# TrueFocus Privacy Policy

Effective [EFFECTIVE DATE]

TrueFocus is made by [DEVELOPER LEGAL NAME] ("we"). This policy covers the TrueFocus apps for
iPhone and Mac and the TrueFocus browser extension for Safari and Chrome.

## The short version

- There's no account. We never ask for your name, email or phone number.
- There are no ads, no analytics, no tracking and no third-party SDKs.
- Your Screen Time choices, your app usage and your browsing stay on your device.
- To keep your iPhone and Mac in step, TrueFocus uploads your tasks, notes and focus timeline to
  our sync server. It encrypts them on your device first. The server stores only the encrypted copy.

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
- **Settings**, including your tone, budgets and allowed sites.
- **Turning a brain dump into tasks** uses Apple Intelligence on your device when it's available.
  Nothing is sent to us or to anyone else for this.

## What we receive, and why

TrueFocus syncs your devices through a server we run on Supabase ([SUPABASE REGION, e.g. "the
EU (Frankfurt)" — check in the Supabase dashboard]). The server receives:

- **Your tasks, notes and day plans** (task titles, notes, the morning brain dump, the day's win,
  your reflection) and **your focus timeline** (when each session started and ended, and how it
  ended). All of this is **encrypted on your device** with AES-256-GCM before it's uploaded. The
  server stores only the encrypted copy.
- **Record details the server needs to sync:** a random ID for each record, its type (task, note,
  session or day), when it was last changed, and whether it was deleted.
- **A sync ID:** a fingerprint (SHA-256 hash) of a random key your device creates. It ties your
  linked devices together. It isn't connected to your name or any account.
- **On iPhone, a push token**, so the server can silently wake your phone to sync when your Mac
  changes something. The wake-up carries no content.
- **The usual connection details,** such as your IP address, which our hosting provider sees on
  every internet request.

**How the encryption key is handled.** The random key lives in your device's Keychain. Your device
also sends it to the server with each sync request, over an encrypted connection, so the server
can check which sync space you belong to. The server keeps only its fingerprint, not the key
itself. When you link a new device, the key is held on the server for up to about ten minutes
until the six-digit code is used. This means our server *could* technically decrypt your data,
though we never do. For that reason we describe sync as "encrypted on your device", not
"end-to-end encrypted".

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

Encrypted records stay on the server while your devices use them. When you delete a task or note,
its encrypted content is removed from the server and a small "deleted" marker remains so your other
devices delete it too. [RETENTION POLICY: e.g. "Records in a sync space with no activity for 12
months are deleted." Add this once a cleanup job exists. See the note for the owner below.]

## Your choices

- **Don't grant Screen Time access,** or revoke it any time in Settings ▸ Screen Time. The task flow
  still works without it.
- **Remove the extension** any time from Safari or Chrome settings.
- **Delete your data from the server:** email [CONTACT EMAIL] with the **Sync ID** shown in
  TrueFocus ▸ Settings ▸ Sync (eight characters, the same on every linked device). We'll delete every
  record in that space within [30] days. Deleting the app removes everything on that device.
- **Access, correction and portability:** your data is on your devices in readable form. On the
  server it's encrypted, so all we could give you is ciphertext.

## Children

TrueFocus isn't directed at children under [13 / 16 — match the age rating] and doesn't knowingly
collect data from them.

## Security

Connections use HTTPS. Content is encrypted on your device with AES-256-GCM. The database only
answers requests that carry a valid key for the matching space.

## Changes

If this policy changes, we'll update the date above and say what changed in the app's release notes.

## Contact

[DEVELOPER LEGAL NAME] · [CONTACT EMAIL] · [WEBSITE URL] · [POSTAL ADDRESS, if you sell in the EU/UK]
```

**Notes for the owner before hosting:**

- **Retention.** Nothing in `supabase/` ever deletes rows. `revoke delete` stops clients
  deleting rows, and there's no scheduled cleanup. Either add one (a `pg_cron` job that deletes spaces
  idle for 12 months) and state it, or write "until you ask us to delete it".
- **The deletion promise needs a procedure.** The Sync ID shown in Settings is the first 8 hex
  characters of `SHA-256(spaceKey)`, and `tf_records.space` starts with exactly those. So:
  `delete from tf_records where space like '<id>%'; delete from tf_devices where space like '<id>%';`
  Eight hex characters could in theory match two spaces, so check the row counts before deleting.
- **There's no switch to turn sync off.** A privacy-minded user can't opt out. Consider an "Off"
  switch in Settings ▸ Sync, plus an "Erase my data from the server" button that tombstones all records,
  or better, a `tf-erase` edge function that deletes the space.
- The Supabase project is **shared with another app (ListingLine)**, according to the migration header and
  `docs/SETUP.md`. That's fine legally, since it's the same controller, but anyone with access to that
  project can see the TrueFocus tables. The access group for the project is also the access
  group for TrueFocus users' data.

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
