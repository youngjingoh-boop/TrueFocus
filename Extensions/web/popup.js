/* TrueFocus popup. */
(function () {
  'use strict';

  var api = globalThis.browser || globalThis.chrome;
  var Core = globalThis.TFCore;
  var KEY = { state: 'tfState', prefs: 'tfPrefs', boots: 'tfBoots', adultOff: 'tfAdultOffRequest' };

  var state = null;
  var prefs = null;
  var boots = null;
  var adultOff = null;
  var confirming = false;

  function $(id) { return document.getElementById(id); }

  function send(message) {
    try {
      return Promise.resolve(api.runtime.sendMessage(message)).catch(function () { return null; });
    } catch (e) {
      return Promise.resolve(null);
    }
  }

  function formatWhen(ms) {
    var d = new Date(ms);
    var sameDay = new Date().toDateString() === d.toDateString();
    var time = d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    if (sameDay) return 'today at ' + time;
    return d.toLocaleDateString([], { weekday: 'short' }) + ' at ' + time;
  }

  function render() {
    var now = Date.now();
    var eff = Core.effective(state, prefs, now, adultOff);
    var snapshot = state && state.snapshot;
    var connected = !!(state && state.connected);

    // Connection
    $('conn').classList.toggle('on', connected);
    $('connText').textContent = connected
      ? (state.source === 'native' ? 'Connected' : 'Connected to Mac')
      : (state && state.settings ? 'App not reachable' : 'Not connected');

    // Now
    var mode = eff.mode;
    // Paused: idle with the task held (and its clock frozen) until you resume in the app.
    var paused = mode === 'idle' && !!(snapshot && snapshot.pausedAt && !snapshot.dayEnded);
    $('now').setAttribute('data-mode', mode);
    $('mode').textContent = paused ? 'Paused'
      : mode === 'idle' && snapshot && snapshot.dayEnded ? 'Shut down' : Core.modeLabel(mode);
    var title;
    if (mode === 'focus' || mode === 'think') title = eff.task || 'Focusing';
    else if (mode === 'rest') title = eff.task ? 'Next: ' + eff.task : 'Micro-rest';
    else if (paused) title = eff.task || 'Paused';
    else title = eff.task ? 'Next: ' + eff.task : 'Nothing running';
    $('task').textContent = title;

    var timer = $('timer');
    if (snapshot && mode === 'focus') {
      timer.hidden = false;
      timer.textContent = Core.clock(Core.taskElapsed(snapshot, now));
    } else if (snapshot && mode === 'rest' && snapshot.plannedRestEnd) {
      var left = (Core.dateMs(snapshot.plannedRestEnd) - now) / 1000;
      timer.hidden = false;
      timer.textContent = left >= 0 ? Core.clock(left) : '+' + Core.clock(-left);
    } else if (paused) {
      timer.hidden = false;
      timer.textContent = Core.clock(snapshot.taskFocusBefore || 0);
    } else if (snapshot && mode === 'think') {
      var started = Core.dateMs(snapshot.modeStartedAt);
      timer.hidden = started === null;
      if (started !== null) timer.textContent = Core.clock((now - started) / 1000);
    } else {
      timer.hidden = true;
    }

    var localBoots = boots && boots.day === Core.dayKey(now) ? boots.count : 0;
    var bootCount = Math.max(localBoots, snapshot && typeof snapshot.bootsToday === 'number' ? snapshot.bootsToday : 0);
    var meta = [];
    if (snapshot && snapshot.plannedToday) meta.push(snapshot.doneToday + ' of ' + snapshot.plannedToday + ' done');
    if (snapshot && snapshot.chain > 1) meta.push('Chain ' + snapshot.chain);
    meta.push(bootCount === 1 ? '1 boot-out today' : bootCount + ' boot-outs today');
    $('meta').textContent = meta.join(' · ');

    // Guard toggles. App settings win; then the controls show the app's values, locked.
    var managed = eff.appManaged;
    setSwitch('hideShortForm', eff.hideShortForm, managed);
    setSwitch('instagramMessagesOnly', eff.instagramMessagesOnly, managed);
    setSwitch('guardEnabled', eff.guardEnabled, false);
    var preset = Core.presetName(eff.doomScroll);
    Array.prototype.forEach.call($('sensitivity').querySelectorAll('button'), function (b) {
      b.setAttribute('aria-checked', String(b.getAttribute('data-value') === preset));
      b.disabled = managed;
    });
    $('managed').hidden = !managed;

    renderJuggle(snapshot, connected, now);
    $('waitBtn').hidden = !(connected && mode === 'focus');

    renderAdult(eff.adult, state && state.settings, now);

    $('foot').textContent = eff.strict ? 'Feeds are closed while you focus.' : 'Short-form is gone. Feeds are on a timer.';
  }

  function renderJuggle(snapshot, connected, now) {
    var items = Core.juggleItems(snapshot, now);
    var section = $('juggle');
    section.hidden = items.length < 2;
    if (section.hidden) return;
    var limit = state && state.settings && state.settings.juggleLimit;
    $('juggleCount').textContent = items.length + (limit ? ' of ' + limit : '');
    var list = $('juggleList');
    var key = JSON.stringify(items.map(function (i) { return [i.id, i.title, i.current, i.waiting, i.waitingMinutes]; }));
    if (list.dataset.key === key) return; // the 1 s render loop shouldn't rebuild the list
    list.dataset.key = key;
    list.textContent = '';
    items.forEach(function (item) {
      var li = document.createElement('li');
      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'juggle-item' + (item.current ? ' current' : '') + (item.waiting ? ' waiting' : '');
      button.disabled = item.current || !connected;
      var glyph = document.createElement('span');
      glyph.className = 'glyph';
      glyph.textContent = item.current ? '' : item.waiting ? '⏳' : '⇄';
      var title = document.createElement('span');
      title.className = 'title';
      title.textContent = item.title;
      var tail = document.createElement('span');
      tail.className = 'tail';
      tail.textContent = item.current ? 'now' : item.waiting ? 'waiting ' + item.waitingMinutes + 'm' : 'switch';
      button.append(glyph, title, tail);
      button.title = item.current ? 'You’re on this one' : 'Switch to this task';
      button.addEventListener('click', function () {
        send({ type: 'command', kind: 'switchTo', taskID: item.id });
      });
      li.appendChild(button);
      list.appendChild(li);
    });
  }

  function renderAdult(adult, settings, now) {
    var status = $('adultStatus');
    var action = $('adultAction');
    var appDisabled = settings && settings.adultFilterEnabled === false;
    var hours = adult.coolOffHours;
    $('adultExplain').textContent = 'It turns off ' + hours + (hours === 1 ? ' hour' : ' hours') +
      ' after you ask, so the decision is never made in a weak moment. You can cancel any time before then.';
    $('adultStart').textContent = 'Start ' + hours + '-hour cool-off';

    if (!adult.active) {
      confirming = false;
      status.textContent = appDisabled ? 'Off — turned off in the TrueFocus app' : 'Off';
      action.hidden = appDisabled || adult.localRequestMs === null;
      action.textContent = 'Turn back on';
      action.dataset.action = 'restore';
    } else if (adult.offAt) {
      confirming = false;
      status.textContent = 'On · turns off ' + formatWhen(adult.offAt);
      // Only a request made here can be cancelled here; the app's lives in the app.
      action.hidden = adult.localRequestMs === null;
      action.textContent = 'Cancel';
      action.dataset.action = 'cancel';
    } else {
      status.textContent = 'On';
      action.hidden = confirming;
      action.textContent = 'Turn off…';
      action.dataset.action = 'ask';
    }
    $('adultConfirm').hidden = !confirming;
  }

  function setSwitch(id, value, disabled) {
    var el = $(id);
    el.checked = !!value;
    el.disabled = !!disabled;
  }

  function savePrefs(change) {
    prefs = Object.assign({}, Core.DEFAULT_PREFS, prefs || {}, change);
    render();
    send({ type: 'prefs', prefs: change });
  }

  ['hideShortForm', 'instagramMessagesOnly', 'guardEnabled'].forEach(function (id) {
    $(id).addEventListener('change', function (e) {
      var change = {};
      change[id] = e.target.checked;
      savePrefs(change);
    });
  });

  $('sensitivity').addEventListener('click', function (e) {
    var button = e.target.closest('button[data-value]');
    if (!button || button.disabled) return;
    savePrefs({ sensitivity: button.getAttribute('data-value') });
  });

  $('adultAction').addEventListener('click', function () {
    var action = $('adultAction').dataset.action;
    if (action === 'ask') {
      confirming = true;
      render();
    } else if (action === 'cancel' || action === 'restore') {
      send({ type: 'adultOff', action: action });
    }
  });
  $('waitBtn').addEventListener('click', function () {
    send({ type: 'command', kind: 'wait' });
  });

  $('adultKeep').addEventListener('click', function () {
    confirming = false;
    render();
  });
  $('adultStart').addEventListener('click', function () {
    confirming = false;
    send({ type: 'adultOff', action: 'request' });
  });

  api.storage.onChanged.addListener(function (changes, area) {
    if (area !== 'local') return;
    if (changes[KEY.state]) state = changes[KEY.state].newValue || null;
    if (changes[KEY.prefs]) prefs = changes[KEY.prefs].newValue || null;
    if (changes[KEY.boots]) boots = changes[KEY.boots].newValue || null;
    if (changes[KEY.adultOff]) {
      var v = changes[KEY.adultOff].newValue;
      adultOff = typeof v === 'number' ? v : null;
    }
    render();
  });

  api.storage.local.get([KEY.state, KEY.prefs, KEY.boots, KEY.adultOff]).then(function (data) {
    data = data || {};
    state = data[KEY.state] || null;
    prefs = data[KEY.prefs] || null;
    boots = data[KEY.boots] || null;
    adultOff = typeof data[KEY.adultOff] === 'number' ? data[KEY.adultOff] : null;
    render();
  }, render);

  send({ type: 'refresh' });
  setInterval(render, 1000);
})();
