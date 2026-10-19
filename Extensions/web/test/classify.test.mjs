import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const core = require('../core.js');

const NOW = Date.UTC(2026, 9, 17, 9, 0, 0);
const sec = (ms) => ms / 1000;

function eff(overrides = {}, state = null, prefs = null, adultOff = null) {
  return Object.assign(core.effective(state, prefs, NOW, adultOff), overrides);
}

test('short-form paths are walled', () => {
  const e = eff();
  for (const url of [
    'https://www.instagram.com/reels/',
    'https://www.instagram.com/reel/C1abc/',
    'https://www.instagram.com/explore/',
    'https://www.youtube.com/shorts/abc123',
    'https://m.youtube.com/shorts/abc123',
    'https://www.tiktok.com/@someone/video/1',
    'https://www.tiktok.com/',
    'https://www.facebook.com/reel/123',
    'https://www.facebook.com/watch/?v=1',
    'https://www.snapchat.com/spotlight/xyz',
  ]) {
    assert.equal(core.classify(url, e, {}, NOW).kind, 'shortform', url);
  }
});

test('lookalike paths are not short-form', () => {
  const e = eff({ instagramMessagesOnly: false });
  assert.equal(core.classify('https://www.instagram.com/reelsmith/', e, {}, NOW).kind, 'feed');
  assert.equal(core.classify('https://www.youtube.com/watch?v=abc', e, {}, NOW).kind, 'feed');
  assert.equal(core.classify('https://www.youtube.com/shortsighted', e, {}, NOW).kind, 'feed');
});

test("Meta's business tools stay open while Facebook and Instagram are blocked", () => {
  const e = eff({ strict: true });
  const booted = { Facebook: NOW + 600000, Instagram: NOW + 600000 };
  for (const url of [
    'https://business.facebook.com/latest/home?asset_id=1',
    'https://business.facebook.com/settings/ad-accounts',
    'https://adsmanager.facebook.com/adsmanager/manage/campaigns?act=1',
    'https://www.facebook.com/adsmanager/manage/campaigns',
    'https://www.facebook.com/ads/library/?q=shoes',
    'https://www.facebook.com/events_manager2/list',
    'https://www.facebook.com/business/help/123',
    'https://accountscenter.instagram.com/',
  ]) {
    assert.ok(['safe', 'other'].includes(core.classify(url, e, booted, NOW).kind), url);
  }
  const classic = { facebookWorkOnly: false };
  assert.equal(core.classify('https://www.facebook.com/', eff({ ...classic, strict: true }), {}, NOW).kind, 'strict');
  assert.equal(core.classify('https://www.facebook.com/', eff(classic), booted, NOW).kind, 'cooldown');
  assert.equal(core.classify('https://www.facebook.com/reel/1', eff(), {}, NOW).kind, 'shortform');
  assert.equal(core.classify('https://www.instagram.com/', e, {}, NOW).kind, 'respond');
});

test('safe paths are left alone, even in focus', () => {
  const e = eff({ strict: true });
  assert.equal(core.classify('https://www.instagram.com/direct/inbox/', e, {}, NOW).kind, 'safe');
  assert.equal(core.classify('https://www.instagram.com/direct/t/123/', e, {}, NOW).kind, 'safe');
  assert.equal(core.classify('https://www.tiktok.com/messages', e, {}, NOW).kind, 'safe');
  assert.equal(core.classify('https://x.com/messages/123', e, {}, NOW).kind, 'safe');
  assert.equal(core.classify('https://www.linkedin.com/messaging/thread/1/', e, {}, NOW).kind, 'safe');
});

test('instagram messages-only sends the feed and stories to the inbox', () => {
  const e = eff();
  assert.deepEqual(core.classify('https://www.instagram.com/', e, {}, NOW),
    { kind: 'respond', redirect: 'https://www.instagram.com/direct/inbox/', site: 'Instagram', host: 'www.instagram.com', path: '/' });
  assert.equal(core.classify('https://www.instagram.com/stories/someone/123/', e, {}, NOW).kind, 'respond');
  assert.equal(core.classify('https://www.instagram.com/someone/', e, {}, NOW).kind, 'feed');
  assert.equal(core.classify('https://www.instagram.com/', eff({ instagramMessagesOnly: false }), {}, NOW).kind, 'feed');
});

test('hideShortForm off lets short-form through to the scroll guard', () => {
  const e = eff({ hideShortForm: false });
  assert.equal(core.classify('https://www.youtube.com/shorts/abc', e, {}, NOW).kind, 'feed');
});

test('focus closes every feed', () => {
  const e = eff({ strict: true });
  assert.equal(core.classify('https://x.com/home', e, {}, NOW).kind, 'strict');
  assert.equal(core.classify('https://www.reddit.com/r/all', e, {}, NOW).kind, 'strict');
  assert.equal(core.classify('https://notion.so/page', e, {}, NOW).kind, 'other');
});

test('adult hosts are walled while the filter is active', () => {
  const e = eff();
  assert.equal(core.classify('https://www.pornhub.com/', e, {}, NOW).kind, 'adult');
  assert.equal(core.classify('https://de.xhamster.com/videos', e, {}, NOW).kind, 'adult');
  assert.equal(core.classify('https://some-random-porn-site.net/', e, {}, NOW).kind, 'adult');
  assert.equal(core.classify('https://github.com/', e, {}, NOW).kind, 'other');
  assert.equal(core.classify('https://www.essex.ac.uk/', e, {}, NOW).kind, 'other');
  const off = eff({ adult: { active: false } });
  assert.equal(core.classify('https://www.pornhub.com/', off, {}, NOW).kind, 'other');
});

test('non-http urls are ignored', () => {
  assert.equal(core.classify('about:blank', eff(), {}, NOW).kind, 'other');
  assert.equal(core.classify('not a url', eff(), {}, NOW).kind, 'other');
});

test('cooldowns lock a site, never shorten, and expire', () => {
  let map = core.setCooldown({}, 'Instagram', NOW, 10);
  assert.equal(core.cooldownRemaining(map, 'Instagram', NOW), 10 * 60 * 1000);
  assert.equal(core.classify('https://www.instagram.com/someone/', eff(), map, NOW).kind, 'cooldown');
  // DMs still work while cooling down.
  assert.equal(core.classify('https://www.instagram.com/direct/inbox/', eff(), map, NOW).kind, 'safe');
  map = core.setCooldown(map, 'Instagram', NOW, 5);
  assert.equal(core.cooldownRemaining(map, 'Instagram', NOW), 10 * 60 * 1000);
  const later = NOW + 11 * 60 * 1000;
  assert.equal(core.cooldownRemaining(map, 'Instagram', later), 0);
  assert.deepEqual(core.pruneCooldowns(map, later), {});
  assert.equal(core.cooldownMinutes(false), 10);
  assert.equal(core.cooldownMinutes(true), 20);
});

test('adult filter mirrors TFSettings.adultFilterActive', () => {
  assert.equal(core.adultFilterActive(null, NOW), true);
  assert.equal(core.adultFilterActive({ adultFilterEnabled: false }, NOW), false);
  const requested = sec(NOW - 23 * 3600 * 1000);
  assert.equal(core.adultFilterActive({ adultFilterOffRequestedAt: requested }, NOW), true);
  assert.equal(core.adultFilterActive({ adultFilterOffRequestedAt: sec(NOW - 25 * 3600 * 1000) }, NOW), false);
  assert.equal(core.adultFilterActive({ adultFilterOffRequestedAt: requested, adultFilterCoolOffHours: 1 }, NOW), false);
  // Cool-off is clamped to 1…168 hours like TFSettings.normalize().
  assert.equal(core.adultFilterActive({ adultFilterOffRequestedAt: sec(NOW - 2 * 3600 * 1000), adultFilterCoolOffHours: 0 }, NOW), false);
});

test('a local turn-off request is a cool-off, and cancelling restores the filter', () => {
  const pending = core.adultFilterState(null, NOW - 3600 * 1000, NOW);
  assert.equal(pending.active, true);
  assert.equal(pending.offAt, NOW + 23 * 3600 * 1000);
  const matured = core.adultFilterState(null, NOW - 25 * 3600 * 1000, NOW);
  assert.equal(matured.active, false);
  assert.equal(matured.offAt, null);
  const cancelled = core.adultFilterState(null, null, NOW);
  assert.equal(cancelled.active, true);
  assert.equal(cancelled.offAt, null);
  // The app's own pending request shows up as offAt too.
  const app = core.adultFilterState({ adultFilterOffRequestedAt: sec(NOW - 2 * 3600 * 1000) }, null, NOW);
  assert.equal(app.active, true);
  assert.equal(app.offAt, NOW + 22 * 3600 * 1000);
});

test('strict follows the snapshot, but not forever', () => {
  assert.equal(core.isStrict(null, NOW), false);
  assert.equal(core.isStrict({ mode: 'focus', modeStartedAt: sec(NOW - 600_000) }, NOW), true);
  assert.equal(core.isStrict({ mode: 'think', modeStartedAt: sec(NOW - 600_000) }, NOW), true);
  assert.equal(core.isStrict({ mode: 'rest', modeStartedAt: sec(NOW) }, NOW), false);
  assert.equal(core.isStrict({ mode: 'idle', systemFocusOn: true }, NOW), true);
  assert.equal(core.isStrict({ mode: 'focus', modeStartedAt: sec(NOW - 13 * 3600 * 1000) }, NOW), false);
});

test('app settings win over local prefs', () => {
  const state = {
    snapshot: { mode: 'focus', taskTitle: '  Ship the deck ', modeStartedAt: sec(NOW - 60_000) },
    settings: { tone: 'calm', hideShortForm: false, instagramMessagesOnly: false, doomScroll: { burstStrokes: 15, sessionStrokes: 35, dwellSeconds: 240, focusMultiplier: 0.2 } },
  };
  const e = core.effective(state, { hideShortForm: true, sensitivity: 'gentle' }, NOW, null);
  assert.equal(e.appManaged, true);
  assert.equal(e.tone, 'calm');
  assert.equal(e.hideShortForm, false);
  assert.equal(e.instagramMessagesOnly, false);
  assert.equal(core.presetName(e.doomScroll), 'ruthless');
  assert.equal(e.strict, true);
  assert.equal(e.task, 'Ship the deck');

  const local = core.effective(null, { hideShortForm: false, sensitivity: 'gentle', guardEnabled: false }, NOW, null);
  assert.equal(local.appManaged, false);
  assert.equal(local.tone, 'direct');
  assert.equal(local.hideShortForm, false);
  assert.equal(local.guardEnabled, false);
  assert.equal(core.presetName(local.doomScroll), 'gentle');
});

test('the task named is the current one, or the next while resting', () => {
  assert.equal(core.currentTask({ mode: 'rest', taskTitle: 'Old', nextTaskTitle: 'Next one' }), 'Next one');
  assert.equal(core.currentTask({ mode: 'think', taskTitle: 'Pricing' }), 'Pricing');
  assert.equal(core.currentTask({ mode: 'idle' }), null);
});

test('copy mirrors Copy.bootOut in every tone', () => {
  assert.deepEqual(core.bootOut('savage', 'Instagram', 'Deck'),
    { title: 'Wake the fuck up.', body: 'Doom-scroll detected. Booted out of Instagram. Back to “Deck”.' });
  assert.deepEqual(core.bootOut('direct', null, null), { title: "You're scrolling.", body: 'Booted out. Back to what matters.' });
  assert.deepEqual(core.bootOut('calm', 'X', 'Deck'), { title: "That's enough scrolling", body: 'Taking you out of X. Back to “Deck”.' });
  for (const reason of ['adult', 'shortform', 'focus', 'cooldown', 'doomscroll']) {
    for (const tone of ['calm', 'direct', 'savage']) {
      const copy = core.blockedCopy(reason, tone, 'Instagram', 'Deck');
      assert.ok(copy.title && copy.body && copy.eyebrow, `${reason}/${tone}`);
    }
  }
});

test('formatting matches TFFormat', () => {
  assert.equal(core.clock(0), '0:00');
  assert.equal(core.clock(65), '1:05');
  assert.equal(core.clock(3725), '1:02:05');
  assert.equal(core.taskElapsed({ mode: 'focus', taskFocusBefore: 60, modeStartedAt: sec(NOW - 30_000) }, NOW), 90);
  assert.equal(core.taskElapsed({ mode: 'think', taskFocusBefore: 60, modeStartedAt: sec(NOW - 30_000) }, NOW), 60);
});

test('juggled tasks come out in slot order with the current one and waits marked', () => {
  const snapshot = {
    mode: 'focus',
    taskID: 'A',
    inPlay: [
      { id: 'A', title: 'Submit the application' },
      { id: 'B', title: 'Fix the PDF', waitingSince: (NOW - 12 * 60000) / 1000 },
      { id: 'C', title: 'Reply to Ben' },
      { id: 7, title: 'broken' },
    ],
  };
  assert.deepEqual(core.juggleItems(snapshot, NOW), [
    { id: 'A', title: 'Submit the application', current: true, waiting: false, waitingMinutes: 0 },
    { id: 'B', title: 'Fix the PDF', current: false, waiting: true, waitingMinutes: 12 },
    { id: 'C', title: 'Reply to Ben', current: false, waiting: false, waitingMinutes: 0 },
  ]);
  assert.equal(core.juggleItems(Object.assign({}, snapshot, { mode: 'rest' }), NOW)[0].current, false);
  assert.deepEqual(core.juggleItems(null, NOW), []);
  assert.deepEqual(core.juggleItems({ mode: 'idle' }, NOW), []);
});
