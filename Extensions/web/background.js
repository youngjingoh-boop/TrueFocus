/*
 * TrueFocus background (MV3 service worker, classic script).
 *
 * - Pulls the app's live state every ~30s: Safari asks the native extension handler
 *   (App Group), Chrome-family browsers ask the Mac app's loopback bridge.
 * - Turns the declarativeNetRequest rulesets on and off from the effective settings.
 * - Receives boot-outs from content scripts, counts them, and forwards them to the app.
 * - While a focus task runs, tells the Mac app which site the active tab is on (host and
 *   title only) so its drift guard can notice a wander away from the task.
 */
'use strict';

importScripts('core.js');

const api = globalThis.browser ?? globalThis.chrome;
const Core = globalThis.TFCore;

const BRIDGE = 'http://127.0.0.1:52525';
const NATIVE_APP = 'app.truefocus';
const IS_SAFARI = String(api.runtime.getURL('')).indexOf('safari-web-extension:') === 0;

const KEY = {
  state: 'tfState',
  prefs: 'tfPrefs',
  cooldowns: 'tfCooldowns',
  boots: 'tfBoots',
  adultOff: 'tfAdultOffRequest',
};

const ALARM = 'tf-refresh';
const STALE_MS = 15 * 1000;
/** Without contact for this long, forget the live snapshot (strict mode ends). */
const FORGET_SNAPSHOT_MS = 30 * 60 * 1000;

// ───────────────────────────────────── Storage ─────────────────────────────────────

async function load(keys) {
  return (await api.storage.local.get(keys)) || {};
}

async function loadAll() {
  const data = await load(Object.values(KEY));
  return {
    state: data[KEY.state] || null,
    prefs: data[KEY.prefs] || null,
    cooldowns: data[KEY.cooldowns] || {},
    boots: data[KEY.boots] || null,
    adultOff: typeof data[KEY.adultOff] === 'number' ? data[KEY.adultOff] : null,
  };
}

// ──────────────────────────────────── App state ────────────────────────────────────

async function fetchFromApp() {
  if (IS_SAFARI) {
    const reply = await api.runtime.sendNativeMessage(NATIVE_APP, { type: 'state' });
    if (!reply || typeof reply !== 'object') throw new Error('empty native reply');
    return { snapshot: reply.snapshot || null, settings: reply.settings || null, source: 'native' };
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 2500);
  try {
    const res = await fetch(BRIDGE + '/state', { cache: 'no-store', signal: controller.signal });
    if (!res.ok) throw new Error('bridge ' + res.status);
    const body = await res.json();
    return { snapshot: body.snapshot || null, settings: body.settings || null, source: 'bridge' };
  } finally {
    clearTimeout(timer);
  }
}

let inflight = null;

/** Fetches fresh state (deduplicated), stores it, and re-applies the rulesets. */
function refreshState() {
  if (inflight) return inflight;
  inflight = (async () => {
    const now = Date.now();
    let next;
    try {
      const fresh = await fetchFromApp();
      next = Object.assign(fresh, { fetchedAt: now, connected: true });
    } catch (error) {
      const prev = (await load(KEY.state))[KEY.state] || null;
      const recent = prev && prev.fetchedAt && now - prev.fetchedAt < FORGET_SNAPSHOT_MS;
      next = {
        snapshot: recent ? prev.snapshot : null,
        settings: prev ? prev.settings : null,
        fetchedAt: prev ? prev.fetchedAt : null,
        source: prev ? prev.source : null,
        connected: false,
      };
    }
    await api.storage.local.set({ [KEY.state]: next });
    await applyRulesets();
    return next;
  })().finally(() => { inflight = null; });
  return inflight;
}

// ──────────────────────────────────── Rulesets ────────────────────────────────────

const ADULT_RULESETS = ['adult', 'adult_keywords', 'safesearch'];
const SHORTFORM_RULESETS = ['shortform'];

async function applyRulesets() {
  const all = await loadAll();
  const eff = Core.effective(all.state, all.prefs, Date.now(), all.adultOff);
  const want = {};
  ADULT_RULESETS.forEach((id) => { want[id] = eff.adult.active; });
  SHORTFORM_RULESETS.forEach((id) => { want[id] = eff.hideShortForm; });

  const dnr = api.declarativeNetRequest;
  if (!dnr || !dnr.updateEnabledRulesets) return eff;

  let enabled = null;
  try {
    enabled = await dnr.getEnabledRulesets();
  } catch (error) {
    enabled = null;
  }
  const enable = [];
  const disable = [];
  Object.keys(want).forEach((id) => {
    const isOn = enabled ? enabled.indexOf(id) !== -1 : null;
    if (want[id] && isOn !== true) enable.push(id);
    if (!want[id] && isOn !== false) disable.push(id);
  });
  await applyAllowedSites(dnr, eff);
  if (!enable.length && !disable.length) return eff;
  try {
    await dnr.updateEnabledRulesets({ enableRulesetIds: enable, disableRulesetIds: disable });
  } catch (error) {
    // One at a time, so a ruleset this engine rejects can't hold the others hostage.
    for (const id of enable) {
      try { await dnr.updateEnabledRulesets({ enableRulesetIds: [id] }); } catch (e) { /* unsupported here */ }
    }
    for (const id of disable) {
      try { await dnr.updateEnabledRulesets({ disableRulesetIds: [id] }); } catch (e) { /* already off */ }
    }
  }
  return eff;
}

/** "Always allowed" sites pass the short-form wall too (never the adult filter). */
async function applyAllowedSites(dnr, eff) {
  if (!dnr.updateDynamicRules || !dnr.getDynamicRules) return;
  try {
    const want = Core.allowRules(eff.allowedSites);
    const have = await dnr.getDynamicRules();
    const domains = (rules) => JSON.stringify(rules.map((r) => (r.condition.requestDomains || []).slice().sort()));
    if (have.length === want.length && domains(have) === domains(want)) return;
    await dnr.updateDynamicRules({ removeRuleIds: have.map((r) => r.id), addRules: want });
  } catch (error) {
    /* dynamic rules unsupported here */
  }
}

// ───────────────────────────────────── Boots ─────────────────────────────────────

async function recordBoot(message) {
  const now = Date.now();
  const all = await loadAll();
  const today = Core.dayKey(now);
  const boots = all.boots && all.boots.day === today ? all.boots : { day: today, count: 0 };
  boots.count += 1;
  await api.storage.local.set({ [KEY.boots]: boots });

  const payload = { type: 'boot', site: message.site || null, reason: message.reason || null };
  try {
    if (IS_SAFARI) {
      await api.runtime.sendNativeMessage(NATIVE_APP, payload);
    } else {
      await fetch(BRIDGE + '/boot', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ site: payload.site, reason: payload.reason }),
      });
    }
  } catch (error) {
    // The app isn't reachable; the local count still stands.
  }
  return boots;
}

// ─────────────────────────────────── Commands ───────────────────────────────────

const COMMANDS = new Set(['switchTo', 'wait']);

/** Juggling from the popup: switch to a juggled task, or park the current one as waiting. */
async function sendCommand(message) {
  const kind = message && message.kind;
  if (!COMMANDS.has(kind)) return { ok: false, error: 'unknown command' };
  const payload = { kind, taskID: typeof message.taskID === 'string' ? message.taskID : null };
  try {
    if (IS_SAFARI) {
      await api.runtime.sendNativeMessage(NATIVE_APP, Object.assign({ type: 'command' }, payload));
    } else {
      const res = await fetch(BRIDGE + '/command', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      if (!res.ok) throw new Error('bridge ' + res.status);
    }
  } catch (error) {
    return { ok: false, error: 'app not reachable' };
  }
  // The app applies it within a moment; pull the new state so the popup follows.
  setTimeout(() => refreshState(), 400);
  return { ok: true };
}

// ──────────────────────────────────── Activity ────────────────────────────────────

let lastActivity = null;

/** Reports the focused window's active tab to the app, when it changed or every 10s. */
async function reportActiveTab() {
  if (!api.tabs || !api.tabs.query) return;
  const all = await loadAll();
  const eff = Core.effective(all.state, all.prefs, Date.now(), all.adultOff);
  let tab;
  try {
    [tab] = await api.tabs.query({ active: true, lastFocusedWindow: true });
  } catch (error) {
    return;
  }
  const settings = all.state && all.state.settings;
  const report = tab ? Core.tabActivity(tab.url, tab.title, eff, settings, tab.incognito === true) : null;
  if (!report) return;
  const key = report.host + '\n' + report.title;
  const now = Date.now();
  if (lastActivity && lastActivity.key === key && now - lastActivity.at < 10 * 1000) return;
  lastActivity = { key, at: now };
  try {
    if (IS_SAFARI) {
      await api.runtime.sendNativeMessage(NATIVE_APP, Object.assign({ type: 'activity' }, report));
    } else {
      await fetch(BRIDGE + '/activity', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(report),
      });
    }
  } catch (error) {
    // The app isn't reachable; nothing to do.
  }
}

if (api.tabs) {
  api.tabs.onActivated.addListener(() => { reportActiveTab(); });
  api.tabs.onUpdated.addListener((tabId, change, tab) => {
    if (tab && tab.active && (change.url || change.title)) reportActiveTab();
  });
}
if (api.windows && api.windows.onFocusChanged) {
  api.windows.onFocusChanged.addListener(() => { reportActiveTab(); });
}

// ──────────────────────────────────── Messages ────────────────────────────────────

async function handle(message, sender) {
  switch (message && message.type) {
    case 'state': {
      const { state } = await loadAll();
      if (!state || !state.fetchedAt || Date.now() - state.fetchedAt > STALE_MS) return refreshState();
      return state;
    }
    case 'refresh':
      return refreshState();
    case 'boot':
      return { ok: true, boots: await recordBoot(message) };
    case 'command':
      return sendCommand(message);
    case 'closeTab': {
      const tabId = sender && sender.tab && sender.tab.id;
      if (typeof tabId === 'number' && api.tabs && api.tabs.remove) {
        await api.tabs.remove(tabId);
        return { ok: true };
      }
      return { ok: false };
    }
    case 'prefs': {
      const { prefs } = await loadAll();
      const next = Object.assign({}, Core.DEFAULT_PREFS, prefs || {}, message.prefs || {});
      await api.storage.local.set({ [KEY.prefs]: next });
      await applyRulesets();
      return { ok: true, prefs: next };
    }
    case 'adultOff': {
      // A request starts a cool-off; it is not a lock. Cancel removes it.
      if (message.action === 'request') {
        const { adultOff } = await loadAll();
        if (adultOff === null) await api.storage.local.set({ [KEY.adultOff]: Date.now() });
      } else if (message.action === 'cancel' || message.action === 'restore') {
        await api.storage.local.remove(KEY.adultOff);
      }
      const eff = await applyRulesets();
      return { ok: true, adult: eff.adult };
    }
    default:
      return { ok: false, error: 'unknown message' };
  }
}

api.runtime.onMessage.addListener((message, sender, sendResponse) => {
  handle(message, sender).then(
    (result) => sendResponse(result),
    (error) => sendResponse({ ok: false, error: String(error) })
  );
  return true;
});

// ──────────────────────────────────── Lifecycle ────────────────────────────────────

/** Creates the refresh alarm once; re-creating it on every wake would keep pushing it back. */
async function ensureAlarm() {
  try {
    const existing = await api.alarms.get(ALARM);
    if (existing) return;
  } catch (error) {
    /* get() unsupported: fall through and create */
  }
  try {
    api.alarms.create(ALARM, { periodInMinutes: 0.5 });
  } catch (error) {
    /* alarms unavailable */
  }
}

api.runtime.onInstalled.addListener(() => {
  ensureAlarm();
  refreshState();
});

if (api.runtime.onStartup) {
  api.runtime.onStartup.addListener(() => {
    ensureAlarm();
    refreshState();
  });
}

api.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name !== ALARM) return;
  refreshState().then(() => reportActiveTab());
  // Expired cooldowns are pruned so storage doesn't grow.
  loadAll().then(({ cooldowns }) => {
    const pruned = Core.pruneCooldowns(cooldowns, Date.now());
    if (Object.keys(pruned).length !== Object.keys(cooldowns).length) {
      api.storage.local.set({ [KEY.cooldowns]: pruned });
    }
  });
});

// A worker woken by an event also re-checks state, in case the alarm was lost.
ensureAlarm();
refreshState();
