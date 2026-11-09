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
  var tab = null;

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
      // A paused task shows its time once there's something to show.
      var held = snapshot.taskFocusBefore || 0;
      timer.hidden = held < 60;
      timer.textContent = Core.clock(held);
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
    // The one rule, in words: what's closed right now and what isn't.
    $('rule').classList.toggle('on', !!eff.onTask);
    $('ruleText').textContent = eff.onTask
      ? 'On a task: feeds and Reels closed, messages open'
      : 'Off a task: all open · ' + (eff.lockOutAtLimit ? 'boot-out after ' : 'reminder after ') + eff.remindAfterMinutes + ' min';
    // "For work" switches go through the app when it's running, so they never lock.
    Core.WORK_PLATFORMS.forEach(function (name) {
      setSwitch('work' + name, eff.workPlatforms.indexOf(name) !== -1, false);
    });
    setSwitch('guardEnabled', eff.guardEnabled, false);
    $('managed').hidden = !managed;

    renderJuggle(snapshot, connected, now);
    $('waitBtn').hidden = !(connected && mode === 'focus');
    // Chrome Web Store Limited Use: say in the extension itself when the tab is being reported.
    var onIPhone = /iPhone|iPad|iPod/.test(navigator.userAgent || '');
    $('driftNote').hidden = !Core.driftNoteVisible(eff, state && state.settings, connected, onIPhone);

    renderSite(eff);
    renderSiteList(eff);
    renderAdult(eff.adult, state && state.settings, now);

    $('foot').textContent = eff.onTask ? 'Feeds open again when you pause, rest or stop.' : 'Feeds close when your next task starts.';
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

  // ─── Your own sites ───

  function currentSite() {
    return tab ? Core.pageSite(tab.url, api.runtime.getURL('')) : null;
  }

  function renderSite(eff) {
    var site = currentSite();
    $('site').hidden = !site;
    if (!site) return;
    var status = Core.siteStatus(site, eff);
    $('siteHost').textContent = site;
    $('siteLine').textContent = status.line;
    $('siteActions').hidden = status.rule === 'adult';
    setRuleButton($('siteAllow'), status.rule === 'allow', 'Always allowed', 'Always allow');
    setRuleButton($('siteBlock'), status.rule === 'block', 'Blocked on tasks', 'Block on tasks');
  }

  function setRuleButton(button, on, onText, offText) {
    button.classList.toggle('on', on);
    button.setAttribute('aria-pressed', on ? 'true' : 'false');
    button.textContent = on ? onText : offText;
  }

  function renderSiteList(eff) {
    var rows = eff.allowedSites.map(function (site) { return { site: site, rule: 'allow' }; })
      .concat(eff.blockedSites.map(function (site) { return { site: site, rule: 'block' }; }));
    $('sitesCount').textContent = rows.length ? String(rows.length) : '';
    var list = $('siteList');
    var key = JSON.stringify(rows);
    if (list.dataset.key === key) return; // the 1 s render loop shouldn't rebuild the list
    list.dataset.key = key;
    list.textContent = '';
    rows.forEach(function (row) {
      var li = document.createElement('li');
      var name = document.createElement('span');
      name.className = 'name';
      name.textContent = row.site;
      var tag = document.createElement('span');
      tag.className = 'tag ' + row.rule;
      tag.textContent = row.rule === 'allow' ? 'Always allowed' : 'Blocked on tasks';
      var remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'remove';
      remove.textContent = '\u00D7';
      remove.setAttribute('aria-label', (row.rule === 'allow' ? 'Stop allowing ' : 'Stop blocking ') + row.site);
      remove.addEventListener('click', function () { changeSite(row.site, 'none'); });
      li.append(name, tag, remove);
      list.appendChild(li);
    });
  }

  function showSiteProblem(text) {
    $('siteProblem').textContent = text || '';
    $('siteProblem').hidden = !text;
  }

  /** Sends a change to the app (through the background) and says so if it couldn't land. */
  function changeSite(site, rule) {
    showSiteProblem('');
    return send({ type: 'site', site: site, rule: rule }).then(function (reply) {
      if (reply && reply.ok) {
        reopenBlockedTab(site, rule);
        return true;
      }
      showSiteProblem(reply && reply.error === 'app not reachable'
        ? 'Open TruFocus on this Mac to change your sites.'
        : 'That didn\u2019t work. Try something like notion.so.');
      return false;
    });
  }

  /** Allowed from the page that stopped you: go straight to the site. */
  function reopenBlockedTab(site, rule) {
    if (rule !== 'allow' || !tab || !api.tabs || !api.tabs.update) return;
    if (String(tab.url || '').indexOf(api.runtime.getURL('')) !== 0) return;
    api.tabs.update(tab.id, { url: 'https://' + site + '/' });
    window.close();
  }

  function pressRule(rule) {
    var site = currentSite();
    if (!site) return;
    var eff = Core.effective(state, prefs, Date.now(), adultOff);
    var status = Core.siteStatus(site, eff);
    // Pressing the one that's on removes the entry behind it, which may be a parent domain.
    if (status.rule === rule) changeSite(status.entry || site, 'none');
    else changeSite(site, rule);
  }

  $('siteAllow').addEventListener('click', function () { pressRule('allow'); });
  $('siteBlock').addEventListener('click', function () { pressRule('block'); });

  $('siteForm').addEventListener('submit', function (e) {
    e.preventDefault();
    var rule = e.submitter && e.submitter.value === 'block' ? 'block' : 'allow';
    var site = Core.normalizedSite($('siteEntry').value);
    if (!site) {
      showSiteProblem('That doesn\u2019t look like a site. Try something like notion.so.');
      return;
    }
    changeSite(site, rule).then(function (ok) {
      if (ok) $('siteEntry').value = '';
    });
  });
  $('siteEntry').addEventListener('input', function () { showSiteProblem(''); });

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
      status.textContent = appDisabled ? 'Off — turned off in the TruFocus app' : 'Off';
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

  ['guardEnabled'].forEach(function (id) {
    $(id).addEventListener('change', function (e) {
      var change = {};
      change[id] = e.target.checked;
      savePrefs(change);
    });
  });

  Core.WORK_PLATFORMS.forEach(function (name) {
    $('work' + name).addEventListener('change', function (e) {
      send({ type: 'work', platform: name, open: e.target.checked });
    });
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

  // Host permissions let the popup read the active tab's address; nothing else is kept.
  if (api.tabs && api.tabs.query) {
    Promise.resolve(api.tabs.query({ active: true, currentWindow: true })).then(function (tabs) {
      tab = tabs && tabs[0] ? tabs[0] : null;
      render();
    }, function () { /* no tab to speak of */ });
  }

  send({ type: 'refresh' });
  setInterval(render, 1000);
})();
