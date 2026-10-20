# Chrome Web Store listing: TruFocus extension

The source is `Extensions/web/`: one MV3 extension, also bundled into the Safari targets. Checked
against `manifest.json`, `background.js`, `content.js`, `core.js`, `popup.*` and `rules_*.json` at `1da5526`,
and again at `306ac2f` for the rename and the drift-guard tab reports (`background.js`
`reportActiveTab`, `core.js` `tabActivity`, `test/activity.test.mjs`, `ExtensionBridgeServer.swift`).

**How Chrome differs from Safari.** On Chrome, Arc, Brave and Edge, the extension gets the current
task and settings from the TruFocus **Mac** app over `http://127.0.0.1:52525`, and nowhere else.
Without the Mac app (on Windows, Linux or ChromeOS, or with the app closed), it runs on its own
defaults and the popup reads "Not connected". There's no iPhone pairing in Chrome.

**What changed with the drift guard (`306ac2f`).** While a focus task runs in the Mac app, and the
app's drift guard is on (it is by default), the extension sends the active tab's **host and title**
to the Mac app: `POST http://127.0.0.1:52525/activity` with `{"host": "docs.google.com", "title": "…"}`.
It sends only for `http(s)` pages, cuts the URL down to its host (no path or query) and the title to
200 characters, and repeats a report for the same host and title at most every 10 seconds. It sends
when the active tab or window changes, when the tab's URL or title changes, and on the 30-second
alarm. The manifest didn't change: no `tabs` permission was added. `tabs.query` returns `url` and
`title` because the extension already holds `<all_urls>`. That makes this **web browsing data
leaving the extension**, so the old "never sends URLs" and "reads nothing outside the feed sites"
lines were wrong. They're fixed below. The data goes only to the user's own Mac app on the same
computer, never to a server.

---

## 0. Fix before you submit

| # | Issue | Where | Fix |
| --- | --- | --- | --- |
| C1 | **`nativeMessaging` is unused on Chrome.** `sendNativeMessage` runs only when `IS_SAFARI` (`background.js` L20, L55, L156, L181, L222). Chrome reviewers reject unused permissions ("excessive permissions"). | `manifest.json` | Build a Chrome package whose `manifest.json` leaves out `nativeMessaging`, e.g. a `npm run chrome` step that copies the folder and removes the entry. Keep it in the Safari build. (If C8 moves Chrome to native messaging, keep the permission and justify it instead.) |
| ~~C2~~ | **Resolved (`11f3952`): no profanity by default.** `core.js` `effective()` now falls back to tone `'direct'` when the app isn't connected, and the copy helpers treat an unknown tone as Direct. Savage reaches the extension only when it's picked in the app. | `core.js` L405–406, L603 | Nothing more. |
| C3 | **The short description promises iPhone pairing.** The manifest says "Pairs with the TruFocus app on iPhone and Mac", but Chrome pairs only with the Mac app. | `manifest.json` `description` | Use the short description below. |
| C4 | **The Mac app tells users to load the extension unpacked in Developer mode.** | `MacSettingsView.swift` Browser tab (L355–356) | Once the listing is live, link to it instead. |
| C5 | **Both DNR permissions are requested.** `declarativeNetRequest` and `declarativeNetRequestWithHostAccess` overlap, because `<all_urls>` is already granted. | `manifest.json` | For Chrome, keep only `declarativeNetRequestWithHostAccess`. It works with the existing host permission and avoids the extra "Block content on any page" warning. Test the redirects after removing the other one. If you keep both, use the justifications in §3. |
| **C6** | **The extension's own UI doesn't mention the tab reports.** The Limited Use policy allows collecting web browsing activity only "to the extent required for a user-facing feature" that's described prominently on the store page **and in the product's user interface**. The Mac app says what it reads (Settings ▸ Guard ▸ Drift guard, and the start window's footnote "Only app names, window titles and sites are read, on this Mac, while a task runs."), but the popup says nothing. | `popup.html`, `popup.js` | Add one line to the popup while connected, in focus, with the guard on, e.g. *"Drift guard: this tab's site and title go to TruFocus on this Mac."* The store copy below covers the store-page half. |
| **C7** | **The data-use answers change.** Web history is now handled and sent out of the extension. | Dashboard ▸ Privacy practices | Tick **Web history** and **User activity** (§4). |
| **C8** | **The tab report travels as plain HTTP over loopback.** The User Data Policy asks for personal or sensitive data to be sent securely. Its FAQ exempts "transmissions between a Chrome extension or app and a native program on the same computer" for native messaging. The bridge does the same thing over `127.0.0.1` (the listener is bound to loopback only), but it isn't native messaging. | `background.js`, `ExtensionBridgeServer.swift` | Say so in the reviewer notes (§5). If a reviewer still objects, move Chrome to native messaging. The Mac app isn't sandboxed, so it can install a native-messaging host manifest under `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`. |

---

## 1. Store listing

**Name** (from the manifest, max 75): `TruFocus`. Optionally, for search:
`TruFocus: Feed Blocker & Doom-Scroll Guard` (42). The store shows the manifest `name`, so
change it there.

**Short description** (the manifest `description`, max 132): 123 chars

```
Removes Reels and Shorts, boots you out of doom-scrolling and blocks adult sites. Works alone or with the TruFocus Mac app.
```

**Category:** Productivity → Workflow & Planning. If that subcategory isn't offered, use Productivity → Tools.

**Language:** English.

**Detailed description:**

```
TruFocus takes the feed out of the web, so you stay on the task you chose.

SHORT-FORM, GONE
• Instagram Reels and Explore, YouTube Shorts, Facebook Reels, Watch and Stories, and Snapchat Spotlight are removed. Links to them open a quiet TruFocus page instead.
• TikTok is closed, except messages and upload.
• Shorts shelves and Reels tabs are hidden, so there's nothing to tap.

SOCIAL, FOR WORK ONLY
• Instagram opens straight to your DMs. Messages, settings and posting still work.
• LinkedIn without the feed: the home page opens Messaging, and video is gone. Profiles, search, jobs, Sales Navigator, Recruiter and Campaign Manager stay open.
• Facebook without the feed: the News Feed opens Messenger, and posts, stories, Reels and video are gone. Pages, groups, events, Marketplace, Ads Manager, Business Suite and sign-ins stay open.
• Each of these is a switch in the popup.

A DOOM-SCROLL GUARD
On 14 feed sites (Instagram, YouTube, TikTok, Facebook, X, Threads, Reddit, LinkedIn, Snapchat, Pinterest, Twitch and more), TruFocus counts downward scrolls: swipes, wheel bursts, Space, Page Down, j and the down arrow. Skim too fast, binge too long, or linger too long, and you get a warning. Keep going and a full-screen wake-up boots you out. The site then cools down for 10 minutes. Pick Gentle, Standard or Ruthless sensitivity.

AN ADULT-CONTENT FILTER
On by default: a block list of adult sites, keyword rules, and SafeSearch enforced on Google, Bing and DuckDuckGo. Turning it off starts a 24-hour cool-off, so it's never an impulse decision. You can cancel it any time before it ends.

BETTER WITH THE MAC APP (optional)
With the TruFocus app for Mac running, the extension knows what you're working on:
• While a task is running, feed sites close entirely, except their messages and settings pages, and the doom-scroll limits tighten.
• The popup shows your current task and clock. Switch between juggled tasks, or park one as "waiting", without leaving the browser.
• Boot-outs count toward your day's scoreboard in the app.
• Drift guard: while a task is running, the extension tells the Mac app which site your active tab is on and the tab's title, so the app can notice when you've wandered off the task and offer a way back. It sends the site name, not the full address, and only during focus. Turn it off in the app under Settings ▸ Guard ▸ Drift guard.
The extension and the app talk only over a local connection on your Mac (127.0.0.1). Nothing goes through the internet.

PRIVATE BY DESIGN
• No account, no ads, no analytics, no tracking.
• Nothing is sent to a server. Every decision is made on your device. The only browsing data that leaves the extension is the active tab's site and title during focus, and it goes to the TruFocus app on your own Mac.
• It doesn't read page text, forms, passwords or cookies.

HONEST LIMITS
TruFocus is a speed bump, not a lock. You can always remove the extension from your browser's settings. It works in Chrome, Arc, Brave, Edge and other Chromium browsers.
```

**Assets:**

- Icon 128 × 128: `Extensions/web/icon-128.png` (already in the repo).
- Screenshots, 1280 × 800 (at least 1, up to 5):
  1. The popup over a neutral page: current task, Juggling, the toggles, and the Adult filter "On".
     Once C6 is in, the drift-guard line should be visible here too.
  2. The doom-scroll boot-out page (Direct tone), with the URL bar cropped.
  3. The short-form page (`shorts.html`) that replaces Shorts or Reels, with the URL bar cropped.
  4. The adult-filter cool-off confirm in the popup ("Start cool-off" / "Keep it on").
  5. A side-by-side: LinkedIn opening to Messaging (only if you can stage it without a real account's
     data; otherwise skip it).
- Small promo tile, 440 × 280: the Ember ring icon and "Take the feed out of the web."
- Avoid third-party logos and feed content in every image.

**Links:** Website `https://[WEBSITE]` · Support `https://[WEBSITE]/support` · Privacy policy
`https://[WEBSITE]/privacy` (the policy in `privacy.md` §3 covers the extension, including the
drift-guard tab reports).

---

## 2. Single-purpose statement

```
TruFocus has one purpose: to keep the user on the work they chose by limiting distracting and unwanted web content. It removes short-form video and social feeds, stops doom-scrolling on feed sites with a scroll limit and a cooldown, and blocks adult websites. With the optional TruFocus Mac app, the popup shows the user's current task and lets them switch tasks, and during a focus task the extension tells that app which site the active tab is on and its title, so the app can notice when the user drifts off the task and offer a way back. Each of these serves the same purpose.
```

The weak point is that a reviewer could read the adult filter as a second purpose. The statement
presents it as unwanted content, blocked for the same self-control reason, and the description
does the same. If the reviewer still objects, the fallback is to make the adult filter an opt-in
switch in the popup rather than an always-on default.

The drift guard is the other place a reviewer may push: "sends the active tab to another program"
can read as monitoring. The statement ties it to the same purpose (noticing drift from the task the
user chose), and it's off outside focus and whenever the user turns the drift guard off in the app.

---

## 3. Permission justifications

Paste one per field in Developer Dashboard ▸ Privacy practices. No permission was added for the drift
guard: it uses `tabs.query` under the existing `<all_urls>` host access.

**`storage`**
```
Stores the user's preferences (which feed restrictions are on, scroll-guard sensitivity), per-site cooldown end times after a doom-scroll boot-out, today's boot-out count, a pending adult-filter cool-off time, and the last state read from the TruFocus Mac app. All of it is kept in chrome.storage.local on the device and never sent anywhere. Active-tab reports for the Mac app's drift guard are not stored by the extension.
```

**`alarms`**
```
A 30-second repeating alarm keeps the extension in step with the TruFocus Mac app (so feed sites close when a focus session starts, and the app's drift guard knows which site is in front) and prunes expired site cooldowns. MV3 service workers stop when idle, so an alarm is the supported way to do this.
```

**`declarativeNetRequest`** *(drop it for Chrome if you keep `…WithHostAccess`. See C5.)*
```
Ships four static rulesets that block or redirect navigations on the device without reading page content: short-form video paths (e.g. /shorts, /reels) are redirected to an extension page; adult domains and adult keywords in host names are blocked or redirected to an extension page; SafeSearch parameters are added to Google, Bing and DuckDuckGo searches. Rulesets are turned on and off with updateEnabledRulesets as the user's settings change.
```

**`declarativeNetRequestWithHostAccess`**
```
Redirect rules (short-form video to the extension's own page, adult sites to a block page, SafeSearch parameters on search engines) require host access for the URLs they act on. This permission lets those declarative rules run with the host access the extension already holds, without the extension ever reading or modifying requests itself.
```

**`nativeMessaging`** *(remove for Chrome, per C1. Kept here only for the Safari build.)*
```
Used only in Safari, where the extension asks its containing TruFocus app for the current task and settings via browser.runtime.sendNativeMessage. Not used in Chrome.
```

**Host permission `<all_urls>`**
```
The adult-content filter must apply to any website: its block list covers many domains and its keyword rules match host names on any domain (e.g. any host containing an adult keyword), and SafeSearch is enforced on Google's country domains, Bing and DuckDuckGo. Declarative redirect rules only run on hosts the extension has access to, so broad host access is required for the filter to work. The same access lets the extension talk to the optional TruFocus Mac app at http://127.0.0.1:52525 (loopback only, on the same computer): it reads the user's current task, and while a focus task is running and the app's drift guard is on, it reads the active tab's address and title with tabs.query and sends only the site's host name and the title to the app, so the app can tell whether the user is still on their task. Nothing is sent to any server. Content scripts run only on the 14 feed sites listed in the manifest; the extension doesn't read page content on any other site.
```

**Content scripts on 14 feed sites** (instagram.com, youtube.com, youtu.be, tiktok.com,
facebook.com, x.com, twitter.com, threads.net, threads.com, reddit.com, linkedin.com, snapchat.com,
pinterest.com, twitch.tv)
```
On these feed sites only, a content script (1) catches in-app (single-page) navigation to short-form video and feeds that network rules can't see, (2) hides Reels/Shorts shelves and feed links with CSS, (3) counts downward scroll strokes — touch, wheel, Space/PageDown/j/arrow-down — to detect doom-scrolling and shows a warning and a boot-out page. It reads only the page URL and scroll/touch/key events needed to count strokes; it does not read page text, form fields, passwords or cookies, and sends nothing off the device.
```

**`web_accessible_resources` (`blocked.html`, `wall.html`, `shorts.html` and their CSS/JS, `core.js`)**
```
These are the pages the declarative redirect rules send the user to (boot-out, adult-site block page, short-form page). Chrome requires redirect targets to be web-accessible.
```

**Are you using remote code?** → **No.** All JavaScript is in the package. There's no `eval`, no
remote `<script>`, and no fetched code. The only `fetch` calls go to `127.0.0.1:52525` (`/state`,
`/boot`, `/command`, `/activity`).

**If `<all_urls>` is ever narrowed,** `tabs.query` stops returning `url` and `title` for other sites,
and the drift guard would need the `tabs` permission, which adds the "Read your browsing history"
install warning.

---

## 4. Data-use disclosures

**What user data do you collect?** Tick **Web history** and **User activity**. Leave the rest unticked.

The Developer Program's User Data FAQ defines *handling* as "collecting, transmitting, using, or
sharing user data", and says the disclosure applies "even when data is processed or stored locally
on a user's device". So "it never leaves the computer" is a reason the use is acceptable, not a
reason to answer No. The category descriptions below are as the dashboard shows them; check the
wording on the form when you submit, since Google edits it.

| CWS category | Ticked? | Reasoning |
| --- | --- | --- |
| Personally identifiable information | No | None is asked for, read or stored on purpose. A tab title can happen to contain a name or an email address (a webmail inbox title, for instance). It goes only to the user's own Mac app, together with the Web history below. |
| Health information | No | |
| Financial and payment information | No | |
| Authentication information | No | It doesn't read passwords, forms or cookies. |
| Personal communications | No | Instagram/LinkedIn/Facebook messages are only *navigated to*, never read. |
| Location | No | |
| **Web history** ("the list of web pages a user has visited, and associated data such as page title and time of visit") | **Yes** | During a focus task, with the Mac app's drift guard on, the active tab's **host and title** are sent to the TruFocus Mac app on the same computer (`POST 127.0.0.1:52525/activity`). Separately, URLs are checked against local lists and never stored. Only per-site cooldown timestamps (e.g. `{"Instagram": <time>}`) are kept in local storage. |
| **User activity** (examples include "scroll" and "keystroke logging") | **Yes** | On the 14 feed sites, scroll strokes, touch and four keys (Space, PageDown, `j`, ↓) are counted in memory to make a local decision. Only a daily boot-out count is stored locally. A boot-out `{site name, reason}` goes only to the TruFocus Mac app on the same computer. No keystrokes are recorded, only those four keys counted. |
| Website content | No | No page text, images, sounds, videos or links are read. The tab title is declared under Web history, where the dashboard lists it. If a reviewer counts the title as website content, tick it too with the same explanation. |

**What it's used for** (for the privacy policy and any reviewer question): "The active tab's site
and title are used only by the TruFocus Mac app on the same computer, during a focus task, to tell
whether the user is still on the task they chose. They're never sent to a server, sold or shared,
and the extension doesn't store them."

**Certifications (tick all three):** all stay true. The Mac app is the developer's own software
running on the user's computer, not a third party, and nothing is transferred off the device.

- ☑ I do not sell or transfer user data to third parties, outside of the approved use cases.
- ☑ I do not use or transfer user data for purposes that are unrelated to my item's single purpose.
- ☑ I do not use or transfer user data to determine creditworthiness or for lending purposes.

**Privacy policy URL:** `https://[WEBSITE]/privacy`. Required because of the ticks above. The policy
in `privacy.md` §3 has a "Browsing" paragraph and a "drift guard on the Mac" paragraph covering
the extension. Keep the store answers, the policy and the popup (C6) saying the same thing.

---

## 5. Notes for the reviewer (optional field, or a reply if asked)

```
The extension works on its own. With the optional TruFocus Mac app it talks to that app over http://127.0.0.1:52525 on the same computer; the app's listener is bound to the loopback interface and refuses requests from web pages. During a focus task, if the app's drift guard is on, the extension sends the active tab's host name and title (no full URL, no page content) to the app, which uses them to notice when the user drifts off their task. Nothing is sent to any server. Without the Mac app the requests fail and nothing is kept.
```

Reviewers can't easily test the Mac-app half. Say so plainly, and offer a short screen recording of
the drift card if they ask.
