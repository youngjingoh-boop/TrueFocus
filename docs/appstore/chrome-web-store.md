# Chrome Web Store listing: TrueFocus extension

The source is `Extensions/web/`: one MV3 extension, also bundled into the Safari targets. Checked
against `manifest.json`, `background.js`, `content.js`, `core.js`, `popup.*` and `rules_*.json` at `1da5526`.

**How Chrome differs from Safari.** On Chrome, Arc, Brave and Edge, the extension gets the current
task and settings from the TrueFocus **Mac** app over `http://127.0.0.1:52525`, and nowhere else.
Without the Mac app (on Windows, Linux or ChromeOS, or with the app closed), it runs on its own
defaults and the popup reads "Not connected". There's no iPhone pairing in Chrome.

---

## 0. Fix before you submit

| # | Issue | Where | Fix |
| --- | --- | --- | --- |
| C1 | **`nativeMessaging` is unused on Chrome.** `sendNativeMessage` runs only when `IS_SAFARI` (`background.js` L18, L54, L155, L180). Chrome reviewers reject unused permissions ("excessive permissions"). | `manifest.json` | Build a Chrome package whose `manifest.json` leaves out `nativeMessaging`, e.g. a `npm run chrome` step that copies the folder and removes the entry. Keep it in the Safari build. |
| ~~C2~~ | **Resolved (`11f3952`): no profanity by default.** `core.js` `effective()` now falls back to tone `'direct'` when the app isn't connected, and the copy helpers treat an unknown tone as Direct. Savage reaches the extension only when it's picked in the app. | `core.js` L404–406, L589 | Nothing more. |
| C3 | **The short description promises iPhone pairing.** The manifest says "Pairs with the TrueFocus app on iPhone and Mac", but Chrome pairs only with the Mac app. | `manifest.json` `description` | Use the short description below. |
| C4 | **The Mac app tells users to load the extension unpacked in Developer mode.** | `MacSettingsView.swift` L308–331, L353+ | Once the listing is live, link to it instead. |
| C5 | **Both DNR permissions are requested.** `declarativeNetRequest` and `declarativeNetRequestWithHostAccess` overlap, because `<all_urls>` is already granted. | `manifest.json` | For Chrome, keep only `declarativeNetRequestWithHostAccess`. It works with the existing host permission and avoids the extra "Block content on any page" warning. Test the redirects after removing the other one. If you keep both, use the justifications in §3. |

---

## 1. Store listing

**Name** (from the manifest, max 75): `TrueFocus`. Optionally, for search:
`TrueFocus: Feed Blocker & Doom-Scroll Guard` (43). The store shows the manifest `name`, so
change it there.

**Short description** (the manifest `description`, max 132): 124 chars

```
Removes Reels and Shorts, boots you out of doom-scrolling and blocks adult sites. Works alone or with the TrueFocus Mac app.
```

**Category:** Productivity → Workflow & Planning. If that subcategory isn't offered, use Productivity → Tools.

**Language:** English.

**Detailed description:**

```
TrueFocus takes the feed out of the web, so you stay on the task you chose.

SHORT-FORM, GONE
• Instagram Reels and Explore, YouTube Shorts, Facebook Reels, Watch and Stories, and Snapchat Spotlight are removed. Links to them open a quiet TrueFocus page instead.
• TikTok is closed, except messages and upload.
• Shorts shelves and Reels tabs are hidden, so there's nothing to tap.

SOCIAL, FOR WORK ONLY
• Instagram opens straight to your DMs. Messages, settings and posting still work.
• LinkedIn without the feed: the home page opens Messaging, and video is gone. Profiles, search, jobs, Sales Navigator, Recruiter and Campaign Manager stay open.
• Facebook without the feed: the News Feed opens Messenger, and posts, stories, Reels and video are gone. Pages, groups, events, Marketplace, Ads Manager, Business Suite and sign-ins stay open.
• Each of these is a switch in the popup.

A DOOM-SCROLL GUARD
On 14 feed sites (Instagram, YouTube, TikTok, Facebook, X, Threads, Reddit, LinkedIn, Snapchat, Pinterest, Twitch and more), TrueFocus counts downward scrolls: swipes, wheel bursts, Space, Page Down, j and the down arrow. Skim too fast, binge too long, or linger too long, and you get a warning. Keep going and a full-screen wake-up boots you out. The site then cools down for 10 minutes. Pick Gentle, Standard or Ruthless sensitivity.

AN ADULT-CONTENT FILTER
On by default: a block list of adult sites, keyword rules, and SafeSearch enforced on Google, Bing and DuckDuckGo. Turning it off starts a 24-hour cool-off, so you never make that call in a weak moment. You can cancel it any time before it ends.

BETTER WITH THE MAC APP (optional)
With the TrueFocus app for Mac running, the extension knows what you're working on:
• While a task is running, feed sites close entirely, except their messages and settings pages, and the doom-scroll limits tighten.
• The popup shows your current task and clock. Switch between juggled tasks, or park one as "waiting", without leaving the browser.
• Boot-outs count toward your day's scoreboard in the app.
The extension and the app talk only over a local connection on your Mac (127.0.0.1). Nothing goes through the internet.

PRIVATE BY DESIGN
• No account, no ads, no analytics, no tracking.
• Every decision is made on your device. The extension never sends the pages you visit anywhere.
• It doesn't read page text, forms, passwords or cookies.

HONEST LIMITS
TrueFocus is a speed bump, not a lock. You can always remove the extension from your browser's settings. It works in Chrome, Arc, Brave, Edge and other Chromium browsers.
```

**Assets:**

- Icon 128 × 128: `Extensions/web/icon-128.png` (already in the repo).
- Screenshots, 1280 × 800 (at least 1, up to 5):
  1. The popup over a neutral page: current task, Juggling, the toggles, and the Adult filter "On".
  2. The doom-scroll boot-out page (Direct tone), with the URL bar cropped.
  3. The short-form page (`shorts.html`) that replaces Shorts or Reels, with the URL bar cropped.
  4. The adult-filter cool-off confirm in the popup ("Start cool-off" / "Keep it on").
  5. A side-by-side: LinkedIn opening to Messaging (only if you can stage it without a real account's
     data; otherwise skip it).
- Small promo tile, 440 × 280: the Ember ring icon and "Take the feed out of the web."
- Avoid third-party logos and feed content in every image.

**Links:** Website `https://[WEBSITE]` · Support `https://[WEBSITE]/support` · Privacy policy
`https://[WEBSITE]/privacy` (the policy in `privacy.md` §3 already covers the extension).

---

## 2. Single-purpose statement

```
TrueFocus has one purpose: to keep the user on their chosen work by limiting distracting and unwanted web content. It does this by removing short-form video and social feeds, stopping doom-scrolling on feed sites with a scroll limit and a cooldown, and blocking adult websites. The popup shows the user's current task from the optional TrueFocus Mac app and lets them switch tasks, which serves the same purpose.
```

The weak point is that a reviewer could read the adult filter as a second purpose. The statement
presents it as unwanted content, blocked for the same self-control reason, and the description
does the same. If the reviewer still objects, the fallback is to make the adult filter an opt-in
switch in the popup rather than an always-on default.

---

## 3. Permission justifications

Paste one per field in Developer Dashboard ▸ Privacy practices.

**`storage`**
```
Stores the user's preferences (which feed restrictions are on, scroll-guard sensitivity), per-site cooldown end times after a doom-scroll boot-out, today's boot-out count, a pending adult-filter cool-off time, and the last state read from the TrueFocus Mac app. All of it is kept in chrome.storage.local on the device and never sent anywhere.
```

**`alarms`**
```
A 30-second repeating alarm keeps the extension in step with the TrueFocus Mac app (so feed sites close when a focus session starts) and prunes expired site cooldowns. MV3 service workers stop when idle, so an alarm is the supported way to do this.
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
Used only in Safari, where the extension asks its containing TrueFocus app for the current task and settings via browser.runtime.sendNativeMessage. Not used in Chrome.
```

**Host permission `<all_urls>`**
```
The adult-content filter must apply to any website: its block list covers many domains and its keyword rules match host names on any domain (e.g. any host containing an adult keyword), and SafeSearch is enforced on Google's country domains, Bing and DuckDuckGo. Declarative redirect rules only run on hosts the extension has access to, so broad host access is required for the filter to work. The same access lets the extension read the user's current task from the TrueFocus Mac app at http://127.0.0.1:52525 (loopback only). The extension does not inject scripts into, read, or collect data from sites outside the 14 feed sites listed in its content scripts.
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
remote `<script>`, and no fetched code. The only `fetch` calls go to `127.0.0.1:52525`.

---

## 4. Data-use disclosures

**What user data do you collect?** The recommended answer is **none of the categories.**

| CWS category | Ticked? | Reasoning |
| --- | --- | --- |
| Personally identifiable information | No | None is read or stored. |
| Health information | No | |
| Financial and payment information | No | |
| Authentication information | No | It doesn't read passwords, forms or cookies. |
| Personal communications | No | Instagram/LinkedIn/Facebook messages are only *navigated to*, never read. |
| Location | No | |
| Web history | **No** (see below) | URLs are checked against local lists on the device and never transmitted or stored. Only per-site cooldown timestamps (e.g. `{"Instagram": <time>}`) are kept in local storage. |
| User activity | **No** (see below) | Scroll strokes are counted in memory to make a local decision. Only a daily boot-out count is stored locally. A boot-out `{site name, reason}` goes only to the TrueFocus Mac app on the same computer, over loopback. |
| Website content | No | No page content is read. |

**Why "No" is defensible, and the fallback:** the extension sends nothing over the
internet. Its only network destination is `127.0.0.1` on the user's own Mac, which is the
same device. If a Chrome reviewer counts local *handling* as collection, tick **Web history** and
**User activity** with this explanation: "Processed locally to block distracting content; never
transmitted off the device, sold or shared". The certifications below stay true either way.

**Certifications (tick all three):**

- ☑ I do not sell or transfer user data to third parties, outside of the approved use cases.
- ☑ I do not use or transfer user data for purposes that are unrelated to my item's single purpose.
- ☑ I do not use or transfer user data to determine creditworthiness or for lending purposes.

**Privacy policy URL:** `https://[WEBSITE]/privacy`. Required in practice because of
`<all_urls>`. The policy in `privacy.md` §3 has a "Browsing" paragraph covering the extension.
