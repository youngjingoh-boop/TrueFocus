# TruFocus web extension

One Manifest V3 extension, used unchanged by Safari (iPhone and Mac) and by
Chrome-family browsers on the Mac (Chrome, Arc, Brave, Edge, Vivaldi, Dia).

## What it does

- **Short-form is gone.** Instagram Reels and Explore, YouTube Shorts, all of TikTok
  (except messages and upload), Facebook Reels and Watch, Snapchat Spotlight. Blocked at
  navigation by `rules_shortform.json` and on in-app (SPA) navigation by `content.js`;
  shelves and nav links are hidden by `content.css`.
- **Instagram, messages only.** instagram.com and the story viewer open your DMs. DMs,
  account settings and posting still work.
- **Doom-scroll guard.** On feed sites, `content.js` counts downward strokes (touch
  flicks, wheel bursts, Space/PageDown/j, held ↓, and a scroll-position fallback) through
  `TFCore.DoomScrollDetector` — a line-for-line port of the Swift detector in
  `Packages/TrueFocusKit`. Burst, binge or dwell: a toast warns you, then a full-screen
  overlay boots you out to `blocked.html` and the site cools down for 10 minutes
  (20 if it happened during focus).
- **Focus closes the feeds.** While a focus or think segment runs in the TruFocus app,
  every feed site is closed except its messages and settings pages.
- **Your voice.** Copy follows the app's tone (Direct when there's no app, or no tone
  set). If the app's settings carry your own words — `customReminders.bootOut` for the
  boot-out overlay and doom-scroll page, `customReminders.shield` for the focus page —
  they're used with the app's rule (`Copy.apply`): `{task}` becomes the task, up to 40
  characters is the title, anything longer is the message under the tone's title.
- **Adult content filter.** On by default (`rules_adult.json`,
  `rules_adult_keywords.json`, plus SafeSearch in `rules_safesearch.json`). Turning it off
  starts a cool-off (24 hours by default, set in the app); it turns off only after that,
  and you can cancel any time before. It's a speed bump against impulse, not a lock — the
  extension can always be removed through the browser's normal settings.

## Files

Everything the browser loads sits at this folder's root, because Xcode copies the Safari
extension's resources flat. `test/`, `package.json` and this README are excluded from the
app bundle.

| File | Role |
| --- | --- |
| `manifest.json` | MV3 manifest (service worker background, DNR rulesets, content script) |
| `core.js` | Pure logic: detector, site lists, URL classification, cooldowns, copy |
| `background.js` | Pulls app state, toggles rulesets, counts and forwards boot-outs |
| `content.js`, `content.css` | Route guard, scroll guard, toast and boot overlay |
| `blocked.html`, `wall.html`, `shorts.html` + `blocked.css/js` | Where you land instead |
| `popup.html/css/js` | Current task, toggles, sensitivity, adult filter cool-off |
| `rules_*.json` | Generated rulesets — edit `core.js`, then `npm run rules` |

## Talking to the app

| Browser | Transport | Endpoint |
| --- | --- | --- |
| Safari (iPhone, Mac) | `browser.runtime.sendNativeMessage` | `Extensions/Safari/SafariWebExtensionHandler.swift` reads the App Group |
| Chrome family (Mac) | `fetch` to loopback | `macOS/Bridge/ExtensionBridgeServer.swift` on `127.0.0.1:52525` |

Messages:

- `{type: "state"}` → `{snapshot, settings}` — `LiveSnapshot` and `TFSettings` JSON, dates
  as seconds since 1970.
- `{type: "boot", site, reason}` → recorded as a `BootEvent(source: "web")` for the app.

The background stores `{snapshot, settings, fetchedAt, source, connected}` in
`storage.local.tfState`; content scripts and pages read it and listen to
`storage.onChanged`. App settings win over the popup's local toggles. Without the app the
extension still works on its defaults.

## Load it in Chrome (or Arc, Brave, Edge)

1. Generate the icons if they aren't there yet (the Xcode build does this).
2. Open `chrome://extensions`, switch on **Developer mode**.
3. **Load unpacked** → choose this `Extensions/web` folder.
4. Keep the TruFocus Mac app running so the extension can see your current task.

## Safari

The `TrueFocusSafariiOS` and `TrueFocusSafariMac` targets bundle this folder. After
installing the app:

- **iPhone:** Settings ▸ Apps ▸ Safari ▸ Extensions ▸ TruFocus ▸ allow, and set
  *All Websites* to **Allow**.
- **Mac:** Safari ▸ Settings ▸ Extensions ▸ TruFocus ▸ enable, then **Always Allow on
  Every Website**.

## Tests

```sh
cd Extensions/web
npm test          # detector parity, URL classification, cooldowns, rulesets, manifest
npm run rules     # regenerate rules_*.json after editing the lists in core.js
```

The tests also parse `Blocklist.swift` and fail if the site or adult lists drift apart.
