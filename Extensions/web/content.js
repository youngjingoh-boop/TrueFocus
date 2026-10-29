/*
 * TruFocus content script (feed sites only, top frame, document_start).
 *
 * 1. Route guard — short-form, messages-only Instagram, work-only LinkedIn and Facebook,
 *    work mode for YouTube, Instagram and X (site open, feeds hidden),
 *    cooldowns and focus mode,
 *    re-checked on every SPA navigation.
 * 2. Doom-scroll guard — counts downward strokes (touch, wheel, keys, scroll fallback)
 *    through TFCore.DoomScrollDetector; warns, then boots you out.
 * 3. Work check-in — on a platform you've opened for work the same strokes feed
 *    TFCore.ScrollCheckIn, which asks "working or scrolling?" instead of booting you out.
 */
(function () {
  'use strict';

  if (window.top !== window) return;
  var api = globalThis.browser || globalThis.chrome;
  var Core = globalThis.TFCore;
  if (!api || !api.storage || !Core) return;

  var KEY = { state: 'tfState', prefs: 'tfPrefs', cooldowns: 'tfCooldowns', adultOff: 'tfAdultOffRequest' };
  var TICK_MS = 3000;
  var root = document.documentElement;

  // Hide short-form immediately; settings may switch it back off a few ms later.
  root.classList.add('tf-hide-shorts');
  if (/(^|\.)instagram\.com$/.test(location.hostname)) root.classList.add('tf-ig-dm-only');
  if (/(^|\.)facebook\.com$/.test(location.hostname) && !/^\/messages/.test(location.pathname)) {
    root.classList.add('tf-fb-feedless');
  }

  var state = null;
  var prefs = null;
  var cooldowns = {};
  var adultOff = null;
  var eff = Core.effective(null, null, Date.now(), null);

  var detector = null;
  var detectorKey = '';
  var guardOn = false;
  var checkinOn = false;
  var CHECKIN_KEY = 'tfCheckin';
  var checkin = loadCheckin();
  var leaving = false;
  var lastHref = location.href;
  // The page before this one on the same site: where a reel was opened from.
  var fromPath = (function () {
    try {
      var r = new URL(document.referrer);
      return r.hostname === location.hostname ? r.pathname : null;
    } catch (e) { return null; }
  })();
  var currentSite = null;

  // ───────────────────────────────── State ─────────────────────────────────

  function now() { return Date.now(); }

  function recompute() {
    eff = Core.effective(state, prefs, now(), adultOff);
    root.classList.toggle('tf-hide-shorts', !!eff.hideShortForm);
    root.classList.toggle('tf-ig-dm-only', !!eff.instagramMessagesOnly && /(^|\.)instagram\.com$/.test(location.hostname) &&
      eff.workPlatforms.indexOf('Instagram') === -1);
    evaluateRoute();
  }

  function loadState() {
    api.storage.local.get([KEY.state, KEY.prefs, KEY.cooldowns, KEY.adultOff]).then(function (data) {
      data = data || {};
      state = data[KEY.state] || null;
      prefs = data[KEY.prefs] || null;
      cooldowns = data[KEY.cooldowns] || {};
      adultOff = typeof data[KEY.adultOff] === 'number' ? data[KEY.adultOff] : null;
      recompute();
    }, function () { recompute(); });
  }

  api.storage.onChanged.addListener(function (changes, area) {
    if (area !== 'local') return;
    if (changes[KEY.state]) state = changes[KEY.state].newValue || null;
    if (changes[KEY.prefs]) prefs = changes[KEY.prefs].newValue || null;
    if (changes[KEY.cooldowns]) cooldowns = changes[KEY.cooldowns].newValue || {};
    if (changes[KEY.adultOff]) {
      var v = changes[KEY.adultOff].newValue;
      adultOff = typeof v === 'number' ? v : null;
    }
    recompute();
  });

  function send(message) {
    try {
      return Promise.resolve(api.runtime.sendMessage(message)).catch(function () { return null; });
    } catch (e) {
      return Promise.resolve(null);
    }
  }

  // ─────────────────────────────── Route guard ───────────────────────────────

  function blockedURL(reason, site, extra) {
    var params = new URLSearchParams();
    params.set('reason', reason);
    if (site) params.set('site', site);
    if (extra) Object.keys(extra).forEach(function (k) { params.set(k, extra[k]); });
    return api.runtime.getURL('blocked.html') + '?' + params.toString();
  }

  function leave(url) {
    if (leaving) return;
    leaving = true;
    stopGuard();
    pauseMedia();
    location.replace(url);
  }

  function evaluateRoute() {
    if (leaving) return;
    var verdict = Core.classify(location.href, eff, cooldowns, now(), { from: fromPath });
    currentSite = verdict.site || null;
    // Reel links and reel posts are hidden in feeds, never on an account's own page.
    var site = verdict.site ? Core.feedSiteByName(verdict.site) : null;
    root.classList.toggle('tf-feed-page', !!site && Core.isFeedPath(site, location.pathname));
    // Work-only Facebook and work-mode platforms: the page stays, its feeds go.
    var feedless = !!verdict.feedless;
    root.classList.toggle('tf-fb-feedless', feedless && verdict.site === 'Facebook');
    root.classList.toggle('tf-yt-feedless', feedless && verdict.site === 'YouTube');
    root.classList.toggle('tf-ig-feedless', feedless && verdict.site === 'Instagram');
    root.classList.toggle('tf-x-feedless', feedless && verdict.site === 'X');
    // Sites you always allow keep everything, Shorts shelves included.
    if (verdict.allowed) {
      root.classList.remove('tf-hide-shorts');
      root.classList.remove('tf-ig-dm-only');
    }
    // Opened for work: ask "working or scrolling?" instead of guarding.
    checkinOn = verdict.kind === 'safe' && !!verdict.work && !!eff.guardEnabled;
    if (checkinOn && checkin.asking) showCheckIn();
    if (!checkinOn) hideCheckIn();
    switch (verdict.kind) {
      case 'adult': return leave(api.runtime.getURL('wall.html'));
      case 'shortform': return leave(blockedURL('shortform', verdict.site));
      case 'respond': return leave(verdict.redirect);
      case 'cooldown': return leave(blockedURL('cooldown', verdict.site, { from: location.href }));
      case 'strict': return leave(blockedURL('focus', verdict.site, { from: location.href }));
      case 'feed': return startGuard();
      default: return stopGuard();
    }
  }

  function onPossibleNavigation() {
    if (location.href === lastHref) return;
    try { fromPath = new URL(lastHref).pathname; } catch (e) { fromPath = null; }
    lastHref = location.href;
    hideToast();
    evaluateRoute();
  }

  // SPA navigations: content scripts can't patch the page's own history, so watch for the
  // effects instead — popstate, the Navigation API where present, and a cheap poll.
  window.addEventListener('popstate', onPossibleNavigation, true);
  window.addEventListener('hashchange', onPossibleNavigation, true);
  try {
    if (window.navigation && window.navigation.addEventListener) {
      window.navigation.addEventListener('navigatesuccess', onPossibleNavigation);
      window.navigation.addEventListener('currententrychange', onPossibleNavigation);
    }
  } catch (e) { /* Navigation API unavailable */ }
  setInterval(onPossibleNavigation, 500);

  // ────────────────────────────── Doom-scroll guard ──────────────────────────────

  function startGuard() {
    if (!eff.guardEnabled) { stopGuard(); return; }
    var key = JSON.stringify(eff.doomScroll) + '|' + eff.strict;
    if (!detector || key !== detectorKey) {
      // Counts survive in-site navigations; a new config or strictness starts fresh.
      detector = new Core.DoomScrollDetector(eff.doomScroll, eff.strict);
      detectorKey = key;
    }
    guardOn = true;
  }

  function stopGuard() {
    guardOn = false;
    hideToast();
  }

  var lastDirectStroke = 0;
  var suppressFallbackUntil = 0;
  var fallbackTravel = 0;

  function viewport() {
    return Math.max(320, window.innerHeight || document.documentElement.clientHeight || 800);
  }

  /** Strokes count while the doom-scroll guard or the work check-in is on. */
  function watching() { return guardOn || checkinOn; }

  /** One downward stroke from a direct gesture (touch, wheel, key). */
  function stroke(screens) {
    if (!watching() || leaving) return;
    var t = now();
    lastDirectStroke = t;
    suppressFallbackUntil = t + 1500;
    fallbackTravel = 0;
    countStroke(t, screens);
  }

  /** A stroke inferred from scroll position alone (sites that scroll inner containers). */
  function fallbackStroke(screens) {
    if (!watching() || leaving) return;
    countStroke(now(), screens);
  }

  function countStroke(t, screens) {
    if (checkinOn) {
      checkin.stroke(t / 1000);
      saveCheckin();
    }
    if (guardOn && detector) handle(detector.stroke(t / 1000, screens));
  }

  function isTyping(target) {
    if (!target || target === document.body) return false;
    var tag = (target.tagName || '').toLowerCase();
    if (tag === 'input' || tag === 'textarea' || tag === 'select') return true;
    return !!target.isContentEditable;
  }

  // Touch: finger travels up ≥ 60px = content scrolls down.
  var touchStartY = null;
  document.addEventListener('touchstart', function (e) {
    if (!watching() || !e.touches || e.touches.length !== 1) { touchStartY = null; return; }
    touchStartY = e.touches[0].clientY;
  }, { capture: true, passive: true });

  document.addEventListener('touchend', function (e) {
    if (touchStartY === null || !e.changedTouches || !e.changedTouches.length) return;
    var travel = touchStartY - e.changedTouches[0].clientY;
    touchStartY = null;
    // A flick carries momentum: ~40% of the screen in finger travel moves about a screen.
    if (travel >= 60) stroke(travel / (viewport() * 0.4));
  }, { capture: true, passive: true });

  // Wheel: bursts separated by > 250ms; a burst of ≥ 200px downward is one stroke.
  var wheelTravel = 0;
  var wheelTimer = null;
  function endWheelBurst() {
    wheelTimer = null;
    if (wheelTravel >= 200) stroke(wheelTravel / viewport());
    wheelTravel = 0;
  }
  document.addEventListener('wheel', function (e) {
    if (!watching()) return;
    var unit = e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? viewport() : 1;
    var dy = e.deltaY * unit;
    if (dy <= 0) {
      // Scrolling back up isn't consuming new content; it ends the burst without counting.
      wheelTravel = 0;
      return;
    }
    wheelTravel += dy;
    // We see this gesture directly; the scroll it causes mustn't count a second time.
    suppressFallbackUntil = now() + 1500;
    fallbackTravel = 0;
    // A long continuous glide is chunked so it can't masquerade as a single stroke.
    if (wheelTravel >= viewport() * 2.5) {
      stroke(2.5);
      wheelTravel = 0;
    }
    if (wheelTimer) clearTimeout(wheelTimer);
    wheelTimer = setTimeout(endWheelBurst, 250);
  }, { capture: true, passive: true });

  // Keys: Space, PageDown and j are page-sized strokes; held ArrowDown counts every 400ms.
  var lastArrow = 0;
  document.addEventListener('keydown', function (e) {
    if (!watching() || e.metaKey || e.ctrlKey || e.altKey || e.isComposing || isTyping(e.target)) return;
    if ((e.key === ' ' && !e.shiftKey) || e.key === 'PageDown' || e.key === 'j') {
      if (!e.repeat || now() - lastDirectStroke > 400) stroke(1);
    } else if (e.key === 'ArrowDown') {
      if (!e.repeat || now() - lastArrow > 400) {
        lastArrow = now();
        stroke(0.5);
      }
    }
  }, true);

  // Scroll-position fallback: catches scrolling we didn't see as a gesture.
  var lastTops = new WeakMap();
  document.addEventListener('scroll', function (e) {
    if (!watching()) return;
    var target = e.target === document ? (document.scrollingElement || document.documentElement) : e.target;
    if (!target || typeof target.scrollTop !== 'number') return;
    var top = target.scrollTop;
    var prev = lastTops.has(target) ? lastTops.get(target) : top;
    lastTops.set(target, top);
    var delta = top - prev;
    if (now() < suppressFallbackUntil) { fallbackTravel = 0; return; }
    if (delta > 0) {
      fallbackTravel += delta;
      if (fallbackTravel >= viewport()) {
        var screens = fallbackTravel / viewport();
        fallbackTravel = 0;
        fallbackStroke(screens);
      }
    }
  }, { capture: true, passive: true });

  setInterval(function () {
    if (!guardOn || !detector || leaving || document.visibilityState !== 'visible') return;
    handle(detector.tick(now() / 1000));
  }, TICK_MS);

  setInterval(function () {
    if (!checkinOn || leaving || document.visibilityState !== 'visible') return;
    if (checkin.tick(now() / 1000)) showCheckIn();
    saveCheckin();
  }, TICK_MS);

  // The count survives reloads within the tab (sessionStorage is per tab and per site).
  function loadCheckin() {
    try {
      return new Core.ScrollCheckIn(JSON.parse(sessionStorage.getItem(CHECKIN_KEY) || 'null'));
    } catch (e) {
      return new Core.ScrollCheckIn();
    }
  }

  function saveCheckin() {
    try { sessionStorage.setItem(CHECKIN_KEY, JSON.stringify(checkin)); } catch (e) { /* storage off */ }
  }

  function handle(verdict) {
    if (!verdict || leaving) return;
    if (verdict.kind === 'warn') showToast(verdict.fraction);
    else if (verdict.kind === 'boot') boot(verdict.reason);
  }

  // ─────────────────────────────────── Boot ───────────────────────────────────

  function boot(reason) {
    if (leaving) return;
    leaving = true;
    guardOn = false;
    hideToast();
    pauseMedia();
    var site = currentSite;
    var strict = !!eff.strict;
    var minutes = Core.cooldownMinutes(strict);
    var line = Core.bootOut(eff.tone, site, eff.task, eff.customReminders);

    api.storage.local.get(KEY.cooldowns).then(function (data) {
      var map = Core.setCooldown((data && data[KEY.cooldowns]) || {}, site, now(), minutes);
      return api.storage.local.set({ [KEY.cooldowns]: map });
    }).catch(function () {});
    send({ type: 'boot', site: site, reason: reason, strict: strict });

    var from = location.href;
    showBootOverlay(line, reason, function () {
      location.replace(blockedURL('doomscroll', site, { why: reason, from: from }));
    });
  }

  function pauseMedia() {
    try {
      var media = document.querySelectorAll('video, audio');
      for (var i = 0; i < media.length; i++) { try { media[i].pause(); } catch (e) { /* ignore */ } }
    } catch (e) { /* ignore */ }
  }

  // ─────────────────────────────────── UI ───────────────────────────────────

  var FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Geist", system-ui, "Segoe UI", sans-serif';

  function mount(id, css) {
    var host = document.getElementById(id);
    if (host) return host.shadowRoot;
    host = document.createElement('tf-overlay');
    host.id = id;
    host.style.cssText = 'all: initial; position: fixed; z-index: 2147483647; inset: auto; pointer-events: none;';
    var shadow = host.attachShadow({ mode: 'open' });
    var style = document.createElement('style');
    style.textContent = css;
    shadow.appendChild(style);
    (document.body || document.documentElement).appendChild(host);
    return shadow;
  }

  var TOAST_CSS = [
    ':host { all: initial; }',
    '.toast { position: fixed; left: 50%; bottom: max(20px, env(safe-area-inset-bottom)); transform: translate(-50%, 24px);',
    '  width: min(440px, calc(100vw - 24px)); box-sizing: border-box; padding: 14px 14px 14px 18px; border-radius: 20px;',
    '  display: flex; align-items: center; gap: 14px; pointer-events: auto; opacity: 0;',
    '  background: rgba(14, 14, 16, 0.78); color: #F4F3EE; font-family: ' + FONT + ';',
    '  -webkit-backdrop-filter: blur(24px) saturate(180%); backdrop-filter: blur(24px) saturate(180%);',
    '  box-shadow: 0 18px 50px rgba(0,0,0,.35), inset 0 0 0 1px rgba(255,255,255,.08);',
    '  transition: opacity .28s ease, transform .38s cubic-bezier(.2,.9,.2,1); overflow: hidden; }',
    '.toast.on { opacity: 1; transform: translate(-50%, 0); }',
    '.dot { width: 8px; height: 8px; border-radius: 50%; background: #FF5A1F; flex: none; box-shadow: 0 0 0 4px rgba(255,90,31,.18); }',
    '.text { flex: 1; min-width: 0; }',
    '.title { font-size: 14px; font-weight: 600; letter-spacing: -0.01em; }',
    '.body { font-size: 13px; color: rgba(244,243,238,.62); margin-top: 2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }',
    // The primary action is Ember with an Ink label, as on the boot-out page and the shield.
    'button { all: unset; cursor: pointer; flex: none; font: 600 13px ' + FONT + '; color: #050506; background: #FF5A1F;',
    '  padding: 9px 14px; border-radius: 999px; transition: transform .15s ease; }',
    'button:active { transform: scale(.96); }',
    '.meter { position: absolute; left: 0; bottom: 0; height: 2px; background: #FF5A1F; transition: width .4s ease; }'
  ].join('\n');

  var toastTimer = null;
  var lastToastAt = 0;

  function showToast(fraction) {
    var shadow = mount('tf-toast', TOAST_CSS);
    var el = shadow.querySelector('.toast');
    var t = now();
    if (!el) {
      el = document.createElement('div');
      el.className = 'toast';
      el.setAttribute('role', 'status');
      el.innerHTML = '<span class="dot"></span><div class="text"><div class="title"></div><div class="body"></div></div>' +
        '<button type="button">Back to work</button><div class="meter"></div>';
      el.querySelector('button').addEventListener('click', function () {
        send({ type: 'closeTab' }).then(function (r) {
          if (!r || !r.ok) history.length > 1 ? history.back() : location.replace('about:blank');
        });
      });
      shadow.appendChild(el);
    } else if (el.classList.contains('on') === false && t - lastToastAt < 15000) {
      return;
    }
    var line = Core.warnLine(eff.tone, eff.task);
    el.querySelector('.title').textContent = line.title;
    el.querySelector('.body').textContent = line.body;
    el.querySelector('.meter').style.width = Math.round(Math.min(1, fraction) * 100) + '%';
    if (!el.classList.contains('on')) {
      lastToastAt = t;
      requestAnimationFrame(function () { el.classList.add('on'); });
    }
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(hideToast, 6000);
  }

  function hideToast() {
    var host = document.getElementById('tf-toast');
    if (!host || !host.shadowRoot) return;
    var el = host.shadowRoot.querySelector('.toast');
    if (el) el.classList.remove('on');
  }

  // "Working or scrolling?" — stays until answered; the page keeps working underneath.
  var CHECKIN_CSS = TOAST_CSS + '\n' + [
    '.toast { align-items: flex-start; flex-wrap: wrap; padding: 16px 16px 14px 18px; }',
    '.toast .dot { margin-top: 6px; }',
    '.body { white-space: normal; }',
    '.actions { display: flex; gap: 8px; width: 100%; justify-content: flex-end; margin-top: 4px; }',
    'button.quiet { color: #F4F3EE; background: rgba(255,255,255,.10); }'
  ].join('\n');

  function showCheckIn() {
    var shadow = mount('tf-checkin', CHECKIN_CSS);
    var el = shadow.querySelector('.toast');
    if (!el) {
      el = document.createElement('div');
      el.className = 'toast';
      el.setAttribute('role', 'alertdialog');
      el.setAttribute('aria-live', 'assertive');
      el.innerHTML = '<span class="dot"></span><div class="text"><div class="title"></div><div class="body"></div></div>' +
        '<div class="actions"><button type="button" class="quiet" data-act="working"></button>' +
        '<button type="button" data-act="back"></button></div>';
      el.querySelector('[data-act="working"]').addEventListener('click', function () {
        checkin.working();
        saveCheckin();
        hideCheckIn();
      });
      el.querySelector('[data-act="back"]').addEventListener('click', function () {
        checkin = new Core.ScrollCheckIn();
        saveCheckin();
        hideCheckIn();
        pauseMedia();
        send({ type: 'closeTab' }).then(function (r) {
          if (!r || !r.ok) history.length > 1 ? history.back() : location.replace('about:blank');
        });
      });
      shadow.appendChild(el);
    }
    var copy = Core.checkInCopy(currentSite, eff.task, checkin.minutes);
    el.querySelector('.title').textContent = copy.title;
    el.querySelector('.body').textContent = copy.body;
    el.querySelector('[data-act="working"]').textContent = copy.working;
    el.querySelector('[data-act="back"]').textContent = copy.back;
    if (!el.classList.contains('on')) requestAnimationFrame(function () { el.classList.add('on'); });
  }

  function hideCheckIn() {
    var host = document.getElementById('tf-checkin');
    if (!host || !host.shadowRoot) return;
    var el = host.shadowRoot.querySelector('.toast');
    if (el) el.classList.remove('on');
  }

  var BOOT_CSS = [
    ':host { all: initial; }',
    '.boot { position: fixed; inset: 0; pointer-events: auto; background: #050506; color: #F4F3EE; font-family: ' + FONT + ';',
    '  display: flex; flex-direction: column; justify-content: center; padding: max(28px, 7vw); box-sizing: border-box;',
    '  opacity: 0; transition: opacity .32s ease; overflow: hidden; }',
    '.boot.on { opacity: 1; }',
    '.eyebrow { display: flex; align-items: center; gap: 10px; font-size: 11px; font-weight: 600; letter-spacing: .16em;',
    '  text-transform: uppercase; color: #FF7A45; }',
    '.eyebrow i { width: 8px; height: 8px; border-radius: 50%; background: #FF5A1F; display: block; }',
    'h1 { margin: 22px 0 0; font-weight: 200; font-size: clamp(44px, 9.5vw, 132px); line-height: .98; letter-spacing: -0.035em; }',
    'p { margin: 26px 0 0; max-width: 34em; font-size: clamp(16px, 1.6vw, 21px); line-height: 1.45; color: rgba(244,243,238,.66); }',
    '.why { color: rgba(244,243,238,.5); font-size: 14px; margin-top: 10px; }',
    '.count { position: absolute; right: max(28px, 7vw); bottom: max(24px, 5vw); font-weight: 100; font-size: clamp(72px, 16vw, 220px);',
    '  line-height: 1; font-variant-numeric: tabular-nums; color: rgba(244,243,238,.14); }'
  ].join('\n');

  function showBootOverlay(line, reason, done) {
    var shadow = mount('tf-boot', BOOT_CSS);
    var host = document.getElementById('tf-boot');
    host.style.inset = '0';
    var el = document.createElement('div');
    el.className = 'boot';
    el.setAttribute('role', 'alertdialog');
    el.setAttribute('aria-live', 'assertive');
    var eyebrow = document.createElement('div');
    eyebrow.className = 'eyebrow';
    eyebrow.innerHTML = '<i></i>';
    eyebrow.appendChild(document.createTextNode('Doom-scroll guard'));
    var h1 = document.createElement('h1');
    h1.textContent = line.title;
    var p = document.createElement('p');
    p.textContent = line.body;
    var why = document.createElement('div');
    why.className = 'why';
    why.textContent = Core.REASON_DETAIL[reason] || '';
    var count = document.createElement('div');
    count.className = 'count';
    count.textContent = '3';
    el.appendChild(eyebrow);
    el.appendChild(h1);
    el.appendChild(p);
    el.appendChild(why);
    el.appendChild(count);
    shadow.appendChild(el);
    requestAnimationFrame(function () { el.classList.add('on'); });

    // Swallow input underneath while the countdown runs.
    ['wheel', 'touchmove', 'keydown'].forEach(function (type) {
      window.addEventListener(type, function (e) { e.stopPropagation(); }, { capture: true });
    });

    var n = 3;
    var timer = setInterval(function () {
      n -= 1;
      if (n <= 0) {
        clearInterval(timer);
        done();
      } else {
        count.textContent = String(n);
      }
    }, 1000);
  }

  // ───────────────────────────────── Start ─────────────────────────────────

  loadState();
  // Ask for a fresh read of the app's state; storage.onChanged delivers it.
  send({ type: 'state' });
})();
