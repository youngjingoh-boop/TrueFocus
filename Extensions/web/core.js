/*
 * TrueFocus web core.
 *
 * Pure logic shared by background.js, content.js, popup.js, blocked.js and the node tests.
 * Classic script: sets globalThis.TFCore, and module.exports under node.
 *
 * The doom-scroll detector is a 1:1 port of
 * Packages/TrueFocusKit/Sources/TrueFocusKit/DoomScroll.swift, and the site lists mirror
 * Blocklist.swift. Keep them in step — test/parity.test.mjs checks.
 */
(function (root, factory) {
  'use strict';
  var core = factory();
  root.TFCore = core;
  if (typeof module !== 'undefined' && module.exports) { module.exports = core; }
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  // ───────────────────────────── Doom-scroll detector ─────────────────────────────

  /** Same defaults as DoomScrollConfig.standard. */
  var DEFAULT_CONFIG = Object.freeze({
    burstWindowSeconds: 60,
    burstStrokes: 25,
    sessionStrokes: 60,
    sessionGapSeconds: 45,
    dwellSeconds: 8 * 60,
    focusMultiplier: 0.3,
    warnFraction: 0.7
  });

  /** DoomScrollConfig.gentle / .standard / .ruthless. */
  var PRESETS = Object.freeze({
    gentle: Object.freeze(Object.assign({}, DEFAULT_CONFIG, { burstStrokes: 40, sessionStrokes: 100, dwellSeconds: 15 * 60 })),
    standard: DEFAULT_CONFIG,
    ruthless: Object.freeze(Object.assign({}, DEFAULT_CONFIG, { burstStrokes: 15, sessionStrokes: 35, dwellSeconds: 4 * 60, focusMultiplier: 0.2 }))
  });

  /** Tolerant decode: missing or invalid keys fall back to the defaults. */
  function normalizeConfig(partial) {
    var out = {};
    var src = partial && typeof partial === 'object' ? partial : {};
    Object.keys(DEFAULT_CONFIG).forEach(function (key) {
      var value = src[key];
      out[key] = typeof value === 'number' && isFinite(value) ? value : DEFAULT_CONFIG[key];
    });
    return out;
  }

  /** Which preset (if any) a config equals — for the popup's segmented control. */
  function presetName(config) {
    var c = normalizeConfig(config);
    var names = Object.keys(PRESETS);
    for (var i = 0; i < names.length; i++) {
      var p = PRESETS[names[i]];
      var same = Object.keys(DEFAULT_CONFIG).every(function (k) { return p[k] === c[k]; });
      if (same) { return names[i]; }
    }
    return 'custom';
  }

  /** Swift's `rounded()` (to nearest, ties away from zero) for non-negative values. */
  function roundHalfAway(x) {
    return x < 0 ? -Math.round(-x) : Math.round(x);
  }

  /** DoomScrollConfig.limits(strict:). */
  function limits(config, strict) {
    var m = strict ? Math.min(Math.max(config.focusMultiplier, 0.05), 1) : 1;
    return {
      burst: Math.max(4, roundHalfAway(config.burstStrokes * m)),
      session: Math.max(8, roundHalfAway(config.sessionStrokes * m)),
      dwell: Math.max(60, config.dwellSeconds * m)
    };
  }

  var CALM = Object.freeze({ kind: 'calm' });

  /**
   * Watches scroll strokes on a feed surface and decides when you're doom-scrolling.
   * Times are in seconds (any epoch). Three rules, any one boots you:
   *   burst — too many downward strokes inside a short window (skimming)
   *   binge — too many strokes in one sitting, however slow (reels/shorts swiping)
   *   dwell — too much engaged time on the feed at all
   */
  function DoomScrollDetector(config, strict) {
    this.config = normalizeConfig(config || DEFAULT_CONFIG);
    this.strict = !!strict;
    this.reset();
  }

  DoomScrollDetector.prototype.reset = function () {
    this._strokeTimes = [];
    this._strokeWeights = [];
    this._sessionCount = 0;
    this._lastStroke = null;
    this._lastTick = null;
    this._engagedSeconds = 0;
  };

  /** One downward stroke. `screens` = how far it travelled in viewport heights. */
  DoomScrollDetector.prototype.stroke = function (time, screens) {
    if (screens === undefined) { screens = 1; }
    this._accrueEngagement(time);
    if (this._lastStroke !== null && time - this._lastStroke > this.config.sessionGapSeconds) {
      this._sessionCount = 0;
    }
    var weight = Math.min(Math.max(screens, 0.5), 3);
    this._strokeTimes.push(time);
    this._strokeWeights.push(weight);
    this._sessionCount += weight;
    this._lastStroke = time;
    this._lastTick = time;
    this._trimWindow(time);
    return this._evaluate();
  };

  /** Call every few seconds while the feed is on screen. */
  DoomScrollDetector.prototype.tick = function (time) {
    this._accrueEngagement(time);
    this._lastTick = time;
    this._trimWindow(time);
    return this._evaluate();
  };

  Object.defineProperty(DoomScrollDetector.prototype, 'progress', {
    get: function () {
      var l = limits(this.config, this.strict);
      var burst = sum(this._strokeWeights) / l.burst;
      var binge = this._sessionCount / l.session;
      var dwell = this._engagedSeconds / l.dwell;
      return Math.max(burst, binge, dwell);
    }
  });

  Object.defineProperty(DoomScrollDetector.prototype, 'engagedTime', {
    get: function () { return this._engagedSeconds; }
  });

  DoomScrollDetector.prototype._accrueEngagement = function (time) {
    // Time only counts while you're actively scrolling (a stroke within the session gap).
    if (this._lastStroke === null || this._lastTick === null) { return; }
    var activeUntil = this._lastStroke + this.config.sessionGapSeconds;
    var end = Math.min(time, activeUntil);
    if (end > this._lastTick) { this._engagedSeconds += end - this._lastTick; }
  };

  DoomScrollDetector.prototype._trimWindow = function (now) {
    var cutoff = now - this.config.burstWindowSeconds;
    while (this._strokeTimes.length && this._strokeTimes[0] < cutoff) {
      this._strokeTimes.shift();
      this._strokeWeights.shift();
    }
  };

  DoomScrollDetector.prototype._evaluate = function () {
    var l = limits(this.config, this.strict);
    if (sum(this._strokeWeights) >= l.burst) { return { kind: 'boot', reason: 'burst' }; }
    if (this._sessionCount >= l.session) { return { kind: 'boot', reason: 'binge' }; }
    if (this._engagedSeconds >= l.dwell) { return { kind: 'boot', reason: 'dwell' }; }
    var p = this.progress;
    if (p >= this.config.warnFraction) { return { kind: 'warn', fraction: Math.min(p, 1) }; }
    return CALM;
  };

  function sum(values) {
    var total = 0;
    for (var i = 0; i < values.length; i++) { total += values[i]; }
    return total;
  }

  // ───────────────────────────────── Site lists ─────────────────────────────────

  /** Blocklist.feedSites. */
  var FEED_SITES = Object.freeze([
    { name: 'Instagram', hosts: ['instagram.com'], shortFormPaths: ['/reels', '/reel', '/explore'],
      respondPath: '/direct/inbox/', safePaths: ['/direct', '/accounts', '/create'], allShortForm: false,
      workHosts: ['business.instagram.com', 'accountscenter.instagram.com', 'help.instagram.com'] },
    { name: 'YouTube', hosts: ['youtube.com', 'youtu.be'], shortFormPaths: ['/shorts'],
      respondPath: null, safePaths: ['/upload', '/account'], allShortForm: false },
    { name: 'TikTok', hosts: ['tiktok.com'], shortFormPaths: [],
      respondPath: '/messages', safePaths: ['/messages', '/upload', '/tiktokstudio', '/login', '/setting'], allShortForm: true },
    // Facebook's sign-in and app-login dialogs (Graph API Explorer, "Log in with Facebook")
    // are safe, so connecting a tool never hits the focus wall.
    { name: 'Facebook', hosts: ['facebook.com'], shortFormPaths: ['/reel', '/reels', '/watch', '/stories'],
      respondPath: '/messages/',
      safePaths: ['/messages', '/settings', '/adsmanager', '/ads/', '/business', '/events_manager',
        '/commerce_manager', '/billing_hub', '/ad_center', '/help', '/dialog', '/login', '/oauth',
        '/connect', '/checkpoint', '/recover', '/two_step_verification', '/auth', '/device',
        '/privacy', '/security', '/policies', '/legal'],
      allShortForm: false,
      workHosts: ['business.facebook.com', 'adsmanager.facebook.com', 'developers.facebook.com',
        'accountscenter.facebook.com'] },
    { name: 'X', hosts: ['x.com', 'twitter.com'], shortFormPaths: [],
      respondPath: '/messages', safePaths: ['/messages', '/compose', '/settings'], allShortForm: false },
    { name: 'Threads', hosts: ['threads.net', 'threads.com'], shortFormPaths: [],
      respondPath: null, safePaths: [], allShortForm: false },
    { name: 'Reddit', hosts: ['reddit.com'], shortFormPaths: [],
      respondPath: null, safePaths: ['/message', '/settings', '/submit'], allShortForm: false },
    // LinkedIn is a work tool with a feed bolted on: only the home feed and video are the scroll.
    { name: 'LinkedIn', hosts: ['linkedin.com'], shortFormPaths: ['/video', '/feed/videos'],
      respondPath: '/messaging/',
      safePaths: ['/messaging', '/in/', '/jobs', '/company', '/school', '/search', '/mynetwork',
        '/notifications', '/sales', '/talent', '/recruiter', '/campaignmanager', '/ad/',
        '/analytics', '/dashboard', '/post/', '/feed/update/', '/posts/', '/pulse/',
        '/newsletters', '/events', '/groups', '/learning', '/premium', '/settings',
        '/psettings', '/mypreferences', '/help', '/my-items', '/services', '/verify',
        '/checkpoint', '/login', '/uas', '/signup', '/authwall'],
      allShortForm: false,
      workHosts: ['business.linkedin.com', 'developer.linkedin.com', 'learn.linkedin.com'] },
    { name: 'Snapchat', hosts: ['snapchat.com'], shortFormPaths: ['/spotlight'],
      respondPath: null, safePaths: [], allShortForm: false },
    { name: 'Pinterest', hosts: ['pinterest.com'], shortFormPaths: [],
      respondPath: null, safePaths: [], allShortForm: false },
    { name: 'Twitch', hosts: ['twitch.tv'], shortFormPaths: [],
      respondPath: null, safePaths: [], allShortForm: false }
  ]);

  /** Blocklist.adultKeywords. */
  var ADULT_KEYWORDS = Object.freeze([
    'porn', 'xxx', 'hentai', 'xvideo', 'xnxx', 'xhamster', 'nsfw', 'onlyfans', 'camgirl',
    'redtube', 'youporn', 'brazzers', 'chaturbate', 'stripchat', 'livejasmin', 'rule34'
  ]);

  /** Blocklist.adultDomains. */
  var ADULT_DOMAINS = Object.freeze([
    'pornhub.com', 'xvideos.com', 'xnxx.com', 'xhamster.com', 'redtube.com', 'youporn.com',
    'tube8.com', 'spankbang.com', 'eporner.com', 'onlyfans.com', 'fansly.com', 'chaturbate.com',
    'stripchat.com', 'bongacams.com', 'cam4.com', 'livejasmin.com', 'myfreecams.com',
    'camsoda.com', 'brazzers.com', 'realitykings.com', 'bangbros.com', 'naughtyamerica.com',
    'porn.com', 'pornhd.com', 'hqporner.com', 'txxx.com', 'hclips.com', 'tnaflix.com',
    'empflix.com', 'motherless.com', 'fapello.com', 'rule34.xxx', 'rule34.paheal.net',
    'e-hentai.org', 'exhentai.org', 'nhentai.net', 'hanime.tv', 'hentaihaven.xxx', 'iwara.tv',
    'porntrex.com', 'beeg.com', 'sunporno.com', 'drtuber.com', 'nuvid.com', '4tube.com',
    'porntube.com', 'fuq.com', 'ixxx.com', 'thumbzilla.com', 'youjizz.com', 'keezmovies.com',
    'extremetube.com', 'spankwire.com', 'slutload.com', 'xtube.com', 'manyvids.com',
    'clips4sale.com', 'erome.com', 'thothub.to', 'coomer.su', 'kemono.su', 'simpcity.su',
    'pornpics.com', 'imagefap.com', 'literotica.com', 'sex.com', 'adultfriendfinder.com',
    'xxxbunker.com', 'pornone.com', '3movs.com', 'tubegalore.com', 'porngo.com',
    'perfectgirls.net', 'ok.xxx', 'vjav.com', 'javhd.com', 'missav.com', 'jable.tv',
    'supjav.com', 'xhamsterlive.com', 'pornhubpremium.com', 'modelhub.com', 'youporngay.com',
    'xvideos.red', 'xnxx.tv', 'sxyprn.com', 'porndig.com', 'pornktube.com', 'anysex.com',
    'hdzog.com', 'upornia.com', 'vxxx.com', 'redgifs.com', 'scrolller.com', 'f95zone.to'
  ]);

  function hostMatches(host, suffix) {
    return host === suffix || host.slice(-(suffix.length + 1)) === '.' + suffix;
  }

  /** Blocklist.FeedSite.matches(host:): a site's work hosts (Ads Manager…) are not the site. */
  function feedSiteForHost(host) {
    var h = String(host || '').toLowerCase();
    for (var i = 0; i < FEED_SITES.length; i++) {
      var site = FEED_SITES[i];
      if ((site.workHosts || []).some(function (w) { return hostMatches(h, w); })) { return null; }
      for (var j = 0; j < site.hosts.length; j++) {
        if (hostMatches(h, site.hosts[j])) { return site; }
      }
    }
    return null;
  }

  function feedSiteByName(name) {
    for (var i = 0; i < FEED_SITES.length; i++) {
      if (FEED_SITES[i].name === name) { return FEED_SITES[i]; }
    }
    return null;
  }

  function isSafePath(site, path) {
    // Facebook's dialogs also live under a Graph API version: /v19.0/dialog/oauth.
    var p = site.name === 'Facebook' ? path.replace(/^\/v\d+(\.\d+)?(?=\/)/, '') : path;
    return site.safePaths.some(function (prefix) { return p.indexOf(prefix) === 0; });
  }

  function isShortFormPath(site, path) {
    if (site.allShortForm) { return !isSafePath(site, path); }
    return site.shortFormPaths.some(function (p) { return path === p || path.indexOf(p + '/') === 0; });
  }

  /** Blocklist.isLinkedInFeed(path:): the home feed, the only scroll on LinkedIn. */
  function isLinkedInFeed(path) {
    return path === '' || path === '/' || path === '/feed' || path === '/feed/';
  }

  /** Blocklist.isFacebookFeed(path:): the News Feed and the groups feed. */
  function isFacebookFeed(path) {
    return path === '' || path === '/' || path === '/home.php' ||
      path === '/groups' || path === '/groups/' || path === '/groups/feed' || path === '/groups/feed/';
  }

  /** Blocklist.isFacebookVideo(path:): Watch, Reels, Stories and any page's videos. */
  function isFacebookVideo(path) {
    return /(^|\/)(watch|reel|reels|stories|videos|gaming)(\/|$)/.test(path);
  }

  /** Blocklist.normalizedSite: "https://www.Notion.so/x" → "notion.so"; null if not a host. */
  function normalizedSite(input) {
    var text = String(input || '').trim().toLowerCase();
    var scheme = text.indexOf('://');
    if (scheme !== -1) { text = text.slice(scheme + 3); }
    text = text.split(/[\/?#:]/)[0];
    if (text.indexOf('www.') === 0) { text = text.slice(4); }
    text = text.replace(/^\.+|\.+$/g, '');
    if (text.indexOf('.') === -1 || text.length > 253 || !/^[a-z0-9.-]+$/.test(text)) { return null; }
    if (text.split('.').some(function (part) { return part === ''; })) { return null; }
    return text;
  }

  /** Blocklist.isAllowed(host:allowedSites:). */
  function isAllowedHost(host, allowedSites) {
    var h = String(host || '').toLowerCase();
    return (allowedSites || []).some(function (site) { return hostMatches(h, site); });
  }

  function isAdultHost(host) {
    var h = String(host || '').toLowerCase();
    for (var i = 0; i < ADULT_DOMAINS.length; i++) {
      if (hostMatches(h, ADULT_DOMAINS[i])) { return true; }
    }
    return ADULT_KEYWORDS.some(function (k) { return h.indexOf(k) !== -1; });
  }

  // ───────────────────────────── Settings & app state ─────────────────────────────

  var DEFAULT_PREFS = Object.freeze({
    hideShortForm: true,
    instagramMessagesOnly: true,
    linkedInWorkOnly: true,
    facebookWorkOnly: true,
    guardEnabled: true,
    sensitivity: 'standard'
  });

  /** Seconds-since-1970 (SharedStore's date encoding) → ms, tolerant of null/strings. */
  function dateMs(value) {
    if (typeof value === 'number' && isFinite(value)) { return value * 1000; }
    if (typeof value === 'string' && value) {
      var parsed = Date.parse(value);
      return isNaN(parsed) ? null : parsed;
    }
    return null;
  }

  /**
   * TFSettings.adultFilterActive(now:): enabled, unless a turn-off request has waited out
   * its cool-off. `settings` is the app's TFSettings JSON (or null for defaults).
   */
  function adultFilterActive(settings, nowMs) {
    var s = settings || {};
    if (s.adultFilterEnabled === false) { return false; }
    var requested = dateMs(s.adultFilterOffRequestedAt);
    if (requested === null) { return true; }
    return nowMs < requested + coolOffHours(s) * 3600 * 1000;
  }

  function coolOffHours(settings) {
    var h = settings && typeof settings.adultFilterCoolOffHours === 'number' ? settings.adultFilterCoolOffHours : 24;
    return Math.min(Math.max(h, 1), 168);
  }

  /**
   * The browser's own turn-off request (made in the popup) combined with the app's.
   * Either one waiting out its cool-off turns the filter off here. Cancel = remove the request.
   */
  function adultFilterState(settings, localRequestMs, nowMs) {
    var appActive = adultFilterActive(settings, nowMs);
    var hours = coolOffHours(settings);
    var localOffAt = typeof localRequestMs === 'number' ? localRequestMs + hours * 3600 * 1000 : null;
    var localActive = localOffAt === null || nowMs < localOffAt;
    var appRequested = dateMs(settings && settings.adultFilterOffRequestedAt);
    var appOffAt = appRequested === null ? null : appRequested + hours * 3600 * 1000;
    var pending = [localOffAt, appOffAt].filter(function (t) { return t !== null && t > nowMs; });
    return {
      active: appActive && localActive,
      coolOffHours: hours,
      offAt: pending.length ? Math.min.apply(null, pending) : null,
      localRequestMs: typeof localRequestMs === 'number' ? localRequestMs : null
    };
  }

  /** Strict mode: a focus or think segment is running (or a system Focus asked for shields). */
  function isStrict(snapshot, nowMs) {
    if (!snapshot) { return false; }
    if (snapshot.systemFocusOn === true) { return true; }
    if (snapshot.mode !== 'focus' && snapshot.mode !== 'think') { return false; }
    // A segment forgotten overnight shouldn't lock the web forever.
    var started = dateMs(snapshot.modeStartedAt);
    return started === null || nowMs - started < 12 * 3600 * 1000;
  }

  /**
   * Everything a surface needs to behave: app settings win over local popup prefs.
   * `state` = { snapshot, settings, fetchedAt, source } from storage.local.tfState.
   */
  function effective(state, prefs, nowMs, localAdultRequestMs) {
    var p = Object.assign({}, DEFAULT_PREFS, prefs || {});
    var settings = state && state.settings ? state.settings : null;
    var snapshot = state && state.snapshot ? state.snapshot : null;
    var appManaged = !!settings;
    var doomScroll = settings && settings.doomScroll
      ? normalizeConfig(settings.doomScroll)
      : normalizeConfig(PRESETS[p.sensitivity] || DEFAULT_CONFIG);
    // Mirrors TFSettings.tone's default: Direct. Savage (strong language) is opt-in in the app.
    var tone = settings && (settings.tone === 'calm' || settings.tone === 'direct' || settings.tone === 'savage')
      ? settings.tone : 'direct';
    var strict = isStrict(snapshot, nowMs);
    return {
      appManaged: appManaged,
      tone: tone,
      hideShortForm: settings && typeof settings.hideShortForm === 'boolean' ? settings.hideShortForm : !!p.hideShortForm,
      instagramMessagesOnly: settings && typeof settings.instagramMessagesOnly === 'boolean'
        ? settings.instagramMessagesOnly : !!p.instagramMessagesOnly,
      linkedInWorkOnly: settings && typeof settings.linkedInWorkOnly === 'boolean'
        ? settings.linkedInWorkOnly : !!p.linkedInWorkOnly,
      facebookWorkOnly: settings && typeof settings.facebookWorkOnly === 'boolean'
        ? settings.facebookWorkOnly : !!p.facebookWorkOnly,
      allowedSites: (settings && Array.isArray(settings.allowedSites) ? settings.allowedSites : [])
        .map(normalizedSite).filter(Boolean),
      guardEnabled: p.guardEnabled !== false,
      doomScroll: doomScroll,
      strict: strict,
      task: currentTask(snapshot),
      mode: snapshot && snapshot.mode ? snapshot.mode : 'idle',
      adult: adultFilterState(settings, localAdultRequestMs, nowMs),
      customReminders: customReminders(settings)
    };
  }

  /** The task worth naming right now: the current one, or the next while resting/idle. */
  function currentTask(snapshot) {
    if (!snapshot) { return null; }
    var title = (snapshot.mode === 'focus' || snapshot.mode === 'think') ? snapshot.taskTitle : snapshot.nextTaskTitle;
    title = typeof title === 'string' ? title.trim() : '';
    return title || null;
  }

  // ─────────────────────────────── URL classification ───────────────────────────────

  /**
   * What to do with a URL.
   *   adult     → wall (only while the adult filter is active)
   *   shortform → shorts wall
   *   respond   → redirect to `redirect` (Instagram home → DMs, LinkedIn/Facebook feed → messages)
   *   cooldown  → booted earlier; wait it out
   *   strict    → focus is running; feeds are closed
   *   safe      → a feed site's messages/settings: leave alone (`feedless`: hide posts on the page)
   *   feed      → a feed: run the doom-scroll guard
   *   other     → not ours
   */
  function classify(url, eff, cooldowns, nowMs) {
    var u;
    try { u = new URL(url); } catch (e) { return { kind: 'other' }; }
    if (u.protocol !== 'http:' && u.protocol !== 'https:') { return { kind: 'other' }; }
    var host = u.hostname.toLowerCase();
    var path = u.pathname || '/';
    if (eff && eff.adult && eff.adult.active && isAdultHost(host)) { return { kind: 'adult', host: host }; }
    // Sites you always allow are never ours to block or guard.
    if (eff && isAllowedHost(host, eff.allowedSites)) { return { kind: 'other', host: host, allowed: true }; }
    var site = feedSiteForHost(host);
    if (!site) { return { kind: 'other', host: host }; }
    var base = { site: site.name, host: host, path: path };
    if (isSafePath(site, path)) { return Object.assign({ kind: 'safe' }, base); }
    if (eff && eff.hideShortForm && isShortFormPath(site, path)) { return Object.assign({ kind: 'shortform' }, base); }
    // Messages-only Instagram: the home feed and the story viewer land you in your DMs.
    if (eff && eff.instagramMessagesOnly && site.name === 'Instagram' &&
        (path === '/' || path === '' || path === '/stories' || path.indexOf('/stories/') === 0)) {
      return Object.assign({ kind: 'respond', redirect: u.origin + site.respondPath }, base);
    }
    // Work-only LinkedIn: the home feed lands you in Messaging; the rest of LinkedIn is safe above.
    if (eff && eff.linkedInWorkOnly && site.name === 'LinkedIn' && isLinkedInFeed(path)) {
      return Object.assign({ kind: 'respond', redirect: u.origin + site.respondPath }, base);
    }
    // Work-only Facebook: no feed, video or stories; pages, groups, Marketplace, events and
    // everything else stay open — unguarded, even in focus — with their posts hidden.
    if (eff && eff.facebookWorkOnly && site.name === 'Facebook') {
      if (isFacebookVideo(path)) { return Object.assign({ kind: 'shortform' }, base); }
      if (isFacebookFeed(path)) { return Object.assign({ kind: 'respond', redirect: u.origin + site.respondPath }, base); }
      // Search results share the feed's markup; keep them so you can find a page or group.
      return Object.assign({ kind: 'safe', feedless: path.indexOf('/search') !== 0 }, base);
    }
    var remaining = cooldownRemaining(cooldowns, site.name, nowMs);
    if (remaining > 0) { return Object.assign({ kind: 'cooldown', remainingMs: remaining }, base); }
    if (eff && eff.strict) { return Object.assign({ kind: 'strict' }, base); }
    return Object.assign({ kind: 'feed' }, base);
  }

  // ─────────────────────────────────── Cooldowns ───────────────────────────────────

  /** Minutes a boot-out locks a site. Longer when it happened during focus. */
  function cooldownMinutes(strict) {
    return strict ? 20 : 10;
  }

  /** Returns a new map with `siteName` locked until now + minutes. Never shortens a lock. */
  function setCooldown(map, siteName, nowMs, minutes) {
    var next = pruneCooldowns(map, nowMs);
    var until = nowMs + minutes * 60 * 1000;
    next[siteName] = Math.max(next[siteName] || 0, until);
    return next;
  }

  function cooldownRemaining(map, siteName, nowMs) {
    if (!map || !siteName) { return 0; }
    var until = map[siteName];
    return typeof until === 'number' && until > nowMs ? until - nowMs : 0;
  }

  function pruneCooldowns(map, nowMs) {
    var next = {};
    if (!map) { return next; }
    Object.keys(map).forEach(function (k) {
      if (typeof map[k] === 'number' && map[k] > nowMs) { next[k] = map[k]; }
    });
    return next;
  }

  // ───────────────────────────────── Your own words ─────────────────────────────────
  // Mirrors CustomReminders.swift and Copy.apply(_:to:task:). test/reminders.test.mjs checks.

  /** ReminderMoment raw values: the keys of the app's settings.customReminders. */
  var REMINDER_MOMENTS = Object.freeze([
    'restOver', 'stuck', 'longFocus', 'idle', 'paused',
    'bootOut', 'shield', 'budgetWarning', 'budgetSpent', 'passEnding'
  ]);
  /** CustomReminders.titleLimit: up to this many characters, custom text is the title. */
  var REMINDER_TITLE_LIMIT = 40;
  /** CustomReminders.noTask: what {task} becomes without a task. */
  var NO_TASK = 'your next task';

  /** settings.customReminders → { moment: trimmed text } for the moments that have text. */
  function customReminders(settings) {
    var out = {};
    var raw = settings && settings.customReminders;
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) { return out; }
    REMINDER_MOMENTS.forEach(function (key) {
      var text = typeof raw[key] === 'string' ? raw[key].trim() : '';
      if (text) { out[key] = text; }
    });
    return out;
  }

  /** CustomReminders.fill: {task} (any case) → the trimmed task title, or "your next task". */
  function fillTask(text, task) {
    var title = typeof task === 'string' ? task.trim() : '';
    // A function replacement, so "$&" and friends in a task title stay literal.
    return text.replace(/\{task\}/gi, function () { return title || NO_TASK; });
  }

  /** Characters as Swift counts them (grapheme clusters), where the browser can tell. */
  function charCount(text) {
    if (typeof Intl !== 'undefined' && typeof Intl.Segmenter === 'function') {
      var n = 0;
      var it = new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(text)[Symbol.iterator]();
      while (!it.next().done) { n += 1; }
      return n;
    }
    return Array.from(text).length;
  }

  /**
   * Copy.apply: no custom text → the built-in line. Otherwise fill in {task}; up to 40
   * characters becomes the title over the built-in body, longer becomes the body under
   * the tone's title.
   */
  function personalize(line, text, task) {
    var trimmed = typeof text === 'string' ? text.trim() : '';
    if (!trimmed) { return line; }
    var filled = fillTask(trimmed, task);
    if (charCount(filled) <= REMINDER_TITLE_LIMIT) { return { title: filled, body: line.body }; }
    return { title: line.title, body: filled };
  }

  // ───────────────────────────────────── Copy ─────────────────────────────────────

  /**
   * Copy.bootOut(site:task:). `reminders` is effective().customReminders (optional):
   * its `bootOut` text, if any, is applied.
   */
  function bootOut(tone, site, task, reminders) {
    return personalize(builtInBootOut(tone, site, task), reminders && reminders.bootOut, task);
  }

  function builtInBootOut(tone, site, task) {
    var place = site ? ' of ' + site : '';
    var back = task ? 'Back to “' + task + '”.' : 'Back to what matters.';
    switch (tone) {
      case 'calm': return { title: "That's enough scrolling", body: 'Taking you out' + place + '. ' + back };
      case 'savage': return { title: 'Wake the fuck up.', body: 'Doom-scroll detected. Booted out' + place + '. ' + back };
      default: return { title: "You're scrolling.", body: 'Booted out' + place + '. ' + back };
    }
  }

  /** The soft warning toast. */
  function warnLine(tone, task) {
    var back = task ? 'Back to “' + task + '”?' : 'Back to work?';
    switch (tone) {
      case 'calm': return { title: 'You’re scrolling a lot.', body: back };
      case 'savage': return { title: 'Still scrolling?', body: back };
      default: return { title: 'You’re scrolling.', body: back };
    }
  }

  /**
   * The blocked page, by reason. `reminders` (effective().customReminders, optional):
   * `shield` applies to the focus page, `bootOut` to the doom-scroll page.
   */
  function blockedCopy(reason, tone, site, task, reminders) {
    var back = task ? 'Back to “' + task + '”.' : 'Back to what matters.';
    switch (reason) {
      case 'adult':
        return { eyebrow: 'Adult content filter', title: 'Walled off.',
          body: 'This site is filtered on this device. Turning the filter off takes a cool-off period — that’s the point.' };
      case 'shortform':
        return { eyebrow: 'Short-form', title: 'Short-form is gone.',
          body: 'Reels, Shorts and TikTok don’t exist here anymore. ' + back };
      case 'focus': {
        var shield = personalize({
          title: tone === 'calm' ? 'Not right now.' : tone === 'savage' ? 'Wake up.' : 'Not now.',
          body: (site ? site + ' is closed while you focus. ' : 'Feeds are closed while you focus. ') + back
        }, reminders && reminders.shield, task);
        return { eyebrow: 'In focus', title: shield.title, body: shield.body };
      }
      case 'cooldown':
        return { eyebrow: 'Cooling down', title: tone === 'savage' ? 'Still no.' : 'Give it a minute.',
          body: (site ? site + ' reopens when the timer runs out. ' : 'This reopens when the timer runs out. ') + back };
      default: {
        var line = bootOut(tone, site, task, reminders);
        return { eyebrow: 'Doom-scroll guard', title: line.title, body: line.body };
      }
    }
  }

  var REASON_DETAIL = Object.freeze({
    burst: 'You were skimming fast.',
    binge: 'That was a lot of swipes in one sitting.',
    dwell: 'Too long on the feed.'
  });

  // ─────────────────────────────────── Formatting ───────────────────────────────────

  /** TFFormat.clock: "4:05", "1:04:05". */
  function clock(seconds) {
    var total = Math.floor(Math.max(0, seconds));
    var h = Math.floor(total / 3600);
    var m = Math.floor((total % 3600) / 60);
    var s = total % 60;
    var ss = s < 10 ? '0' + s : String(s);
    if (h > 0) { return h + ':' + (m < 10 ? '0' + m : m) + ':' + ss; }
    return m + ':' + ss;
  }

  /** Local calendar day key, for "boots today". */
  function dayKey(nowMs) {
    var d = new Date(nowMs);
    var mm = d.getMonth() + 1;
    var dd = d.getDate();
    return d.getFullYear() + '-' + (mm < 10 ? '0' + mm : mm) + '-' + (dd < 10 ? '0' + dd : dd);
  }

  /** Seconds on the current task, live (LiveSnapshot.taskElapsed). */
  function taskElapsed(snapshot, nowMs) {
    if (!snapshot) { return 0; }
    var before = typeof snapshot.taskFocusBefore === 'number' ? snapshot.taskFocusBefore : 0;
    var started = dateMs(snapshot.modeStartedAt);
    if (snapshot.mode === 'focus' && started !== null) { return before + Math.max(0, (nowMs - started) / 1000); }
    return before;
  }

  /**
   * The juggled tasks from a snapshot, in slot order, for the popup:
   * [{ id, title, current, waiting, waitingMinutes }].
   */
  function juggleItems(snapshot, nowMs) {
    if (!snapshot || !Array.isArray(snapshot.inPlay)) { return []; }
    var working = snapshot.mode === 'focus' || snapshot.mode === 'think';
    return snapshot.inPlay
      .filter(function (item) { return item && typeof item.id === 'string' && typeof item.title === 'string'; })
      .map(function (item) {
        var since = dateMs(item.waitingSince);
        return {
          id: item.id,
          title: item.title,
          current: working && item.id === snapshot.taskID,
          waiting: since !== null,
          waitingMinutes: since !== null ? Math.max(0, Math.floor((nowMs - since) / 60000)) : 0,
        };
      });
  }

  function modeLabel(mode) {
    switch (mode) {
      case 'focus': return 'Focus';
      case 'think': return 'Think';
      case 'rest': return 'Rest';
      default: return 'Idle';
    }
  }

  return {
    DEFAULT_CONFIG: DEFAULT_CONFIG,
    PRESETS: PRESETS,
    DEFAULT_PREFS: DEFAULT_PREFS,
    FEED_SITES: FEED_SITES,
    ADULT_DOMAINS: ADULT_DOMAINS,
    ADULT_KEYWORDS: ADULT_KEYWORDS,
    REASON_DETAIL: REASON_DETAIL,
    REMINDER_MOMENTS: REMINDER_MOMENTS,
    REMINDER_TITLE_LIMIT: REMINDER_TITLE_LIMIT,
    NO_TASK: NO_TASK,
    DoomScrollDetector: DoomScrollDetector,
    normalizeConfig: normalizeConfig,
    presetName: presetName,
    limits: limits,
    feedSiteForHost: feedSiteForHost,
    feedSiteByName: feedSiteByName,
    isSafePath: isSafePath,
    isLinkedInFeed: isLinkedInFeed,
    isFacebookFeed: isFacebookFeed,
    isFacebookVideo: isFacebookVideo,
    normalizedSite: normalizedSite,
    isAllowedHost: isAllowedHost,
    isShortFormPath: isShortFormPath,
    isAdultHost: isAdultHost,
    adultFilterActive: adultFilterActive,
    adultFilterState: adultFilterState,
    isStrict: isStrict,
    effective: effective,
    currentTask: currentTask,
    classify: classify,
    cooldownMinutes: cooldownMinutes,
    setCooldown: setCooldown,
    cooldownRemaining: cooldownRemaining,
    pruneCooldowns: pruneCooldowns,
    customReminders: customReminders,
    fillTask: fillTask,
    personalize: personalize,
    bootOut: bootOut,
    warnLine: warnLine,
    blockedCopy: blockedCopy,
    clock: clock,
    dayKey: dayKey,
    dateMs: dateMs,
    taskElapsed: taskElapsed,
    juggleItems: juggleItems,
    modeLabel: modeLabel
  };
});
