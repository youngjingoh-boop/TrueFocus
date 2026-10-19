/* TrueFocus — renders blocked.html / wall.html / shorts.html. */
(function () {
  'use strict';

  var api = globalThis.browser || globalThis.chrome;
  var Core = globalThis.TFCore;
  var KEY = { state: 'tfState', prefs: 'tfPrefs', cooldowns: 'tfCooldowns', adultOff: 'tfAdultOffRequest' };

  var params = new URLSearchParams(location.search);
  var reason = params.get('reason') || document.body.getAttribute('data-reason') || 'doomscroll';
  var siteName = params.get('site') || null;
  var why = params.get('why') || null;
  document.body.setAttribute('data-reason', reason);

  var state = null;
  var prefs = null;
  var cooldowns = {};
  var adultOff = null;

  function $(id) { return document.getElementById(id); }

  function setText(id, text) {
    var el = $(id);
    if (el && el.textContent !== text) el.textContent = text;
  }

  function show(id, visible) {
    var el = $(id);
    if (el) el.hidden = !visible;
  }

  function respondURL(site) {
    if (!site || !site.respondPath) return null;
    var host = site.name === 'X' ? 'x.com' : 'www.' + site.hosts[0];
    return 'https://' + host + site.respondPath;
  }

  function render() {
    var now = Date.now();
    var eff = Core.effective(state, prefs, now, adultOff);
    var copy = Core.blockedCopy(reason, eff.tone, siteName, eff.task, eff.customReminders);
    setText('eyebrow', copy.eyebrow);
    setText('title', copy.title);
    setText('lede', copy.body);
    document.title = copy.title + ' — TruFocus';

    var detail = why && Core.REASON_DETAIL[why] ? Core.REASON_DETAIL[why] : '';
    setText('detail', detail);
    show('detail', !!detail);

    var snapshot = state && state.snapshot;
    setText('task', eff.task ? Core.modeLabel(eff.mode) + ' · ' + eff.task : '');

    // The big numerals: how long until the site reopens, or how long you've been focused.
    var remaining = Core.cooldownRemaining(cooldowns, siteName, now);
    if ((reason === 'cooldown' || reason === 'doomscroll') && siteName) {
      show('figure', true);
      if (remaining > 0) {
        setText('numerals', Core.clock(remaining / 1000));
        setText('caption', 'until ' + siteName + ' reopens');
      } else {
        setText('numerals', '0:00');
        setText('caption', siteName + ' is open again');
      }
    } else if (reason !== 'adult' && eff.strict && snapshot) {
      show('figure', true);
      setText('numerals', Core.clock(Core.taskElapsed(snapshot, now)));
      setText('caption', eff.mode === 'think' ? 'thinking it through' : 'in focus');
    } else {
      show('figure', false);
    }

    var site = siteName ? Core.feedSiteByName(siteName) : null;
    var reply = reason === 'adult' || reason === 'shortform' ? null : respondURL(site);
    var link = $('respond');
    if (reply) {
      link.href = reply;
      link.textContent = 'Reply to messages';
    }
    show('respond', !!reply);
  }

  function load() {
    return api.storage.local.get([KEY.state, KEY.prefs, KEY.cooldowns, KEY.adultOff]).then(function (data) {
      data = data || {};
      state = data[KEY.state] || null;
      prefs = data[KEY.prefs] || null;
      cooldowns = data[KEY.cooldowns] || {};
      adultOff = typeof data[KEY.adultOff] === 'number' ? data[KEY.adultOff] : null;
      render();
    });
  }

  function backToWork() {
    var fallback = function () {
      if (history.length > 1) history.back();
      else location.replace('about:blank');
    };
    try {
      Promise.resolve(api.runtime.sendMessage({ type: 'closeTab' })).then(function (r) {
        if (!r || !r.ok) fallback();
      }, fallback);
    } catch (e) {
      fallback();
    }
  }

  $('back').addEventListener('click', backToWork);

  if (api && api.storage) {
    api.storage.onChanged.addListener(function (changes, area) {
      if (area !== 'local') return;
      if (changes[KEY.state]) state = changes[KEY.state].newValue || null;
      if (changes[KEY.prefs]) prefs = changes[KEY.prefs].newValue || null;
      if (changes[KEY.cooldowns]) cooldowns = changes[KEY.cooldowns].newValue || {};
      if (changes[KEY.adultOff]) {
        var v = changes[KEY.adultOff].newValue;
        adultOff = typeof v === 'number' ? v : null;
      }
      render();
    });
    load().catch(render);
    try {
      Promise.resolve(api.runtime.sendMessage({ type: 'state' })).catch(function () { /* background asleep */ });
    } catch (e) { /* background asleep */ }
  } else {
    render();
  }

  setInterval(render, 1000);
  $('back').focus({ preventScroll: true });
})();
