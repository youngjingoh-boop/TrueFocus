// One rule on every device: on a task feeds and Reels are closed and messages stay open;
// off a task everything opens, with a reminder after a while.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const core = require('../core.js');

const NOW = Date.UTC(2026, 10, 4, 9, 0, 0);
const focus = { mode: 'focus', modeStartedAt: NOW / 1000 - 60 };
const paused = { mode: 'idle', modeStartedAt: NOW / 1000 - 60, isPaused: true };
const settings = { hideShortForm: true, instagramMessagesOnly: true, facebookWorkOnly: true, linkedInWorkOnly: true };
const on = core.effective({ settings, snapshot: focus }, null, NOW, null);
const off = core.effective({ settings, snapshot: paused }, null, NOW, null);
const kind = (url, e, from = null) => core.classify(url, e, {}, NOW, { from }).kind;

test('on a task: Reels walled, feeds closed, messages open', () => {
  assert.equal(on.onTask, true);
  assert.equal(kind('https://www.instagram.com/reels/C1/', on), 'shortform');
  assert.equal(kind('https://www.instagram.com/someone/', on), 'strict');
  assert.equal(kind('https://www.instagram.com/direct/inbox/', on), 'safe');
  assert.equal(kind('https://www.facebook.com/messages/t/1', on), 'safe');
  assert.equal(kind('https://www.linkedin.com/messaging/', on), 'safe');
  assert.equal(kind('https://www.tiktok.com/messages', on), 'safe');
});

test('paused or off a task: everything opens, Reels included', () => {
  assert.equal(off.onTask, false);
  for (const url of ['https://www.instagram.com/reels/C1/', 'https://www.instagram.com/', 'https://www.instagram.com/explore/',
    'https://www.facebook.com/', 'https://www.facebook.com/watch/', 'https://www.linkedin.com/feed/',
    'https://www.youtube.com/shorts/abc']) {
    const k = kind(url, off);
    assert.ok(k === 'feed' || k === 'safe' || k === 'other', `${url} → ${k}`);
  }
});

test('a platform opened for work stays open on a task, Reels still walled', () => {
  const work = core.effective({ settings: Object.assign({ workPlatforms: ['Instagram'] }, settings), snapshot: focus }, null, NOW, null);
  assert.equal(kind('https://www.instagram.com/someone/', work), 'safe');
  assert.equal(kind('https://www.instagram.com/reels/C1/', work), 'shortform');
});

test('the reminder time comes from the app, and lock-out is opt-in', () => {
  assert.equal(core.effective({ settings: { scrollBudgetMinutes: 20 } }, null, NOW, null).remindAfterMinutes, 20);
  assert.equal(core.effective(null, null, NOW, null).remindAfterMinutes, 15);
  assert.equal(core.effective({ settings: {} }, null, NOW, null).lockOutAtLimit, false);
  assert.equal(core.effective({ settings: { lockOutAtLimit: true } }, null, NOW, null).lockOutAtLimit, true);
});

test('feed time reminds at the limit, then 5 minutes after "5 more min", and starts over each day', () => {
  let record = null;
  let reminded = null;
  for (let s = 0; s < 15 * 60; s += 3) {
    const step = core.feedTime(record, 'Instagram', 'd1', 3, 15);
    record = step.record;
    if (step.remind && reminded === null) reminded = s + 3;
  }
  assert.equal(reminded, 15 * 60);
  record = core.snoozeFeedTime(record, 'Instagram', 5);
  assert.equal(core.feedTime(record, 'Instagram', 'd1', 3, 15).remind, false);
  assert.equal(core.feedTime(record, 'Instagram', 'd1', 5 * 60, 15).remind, true);
  // Other sites count on their own; a new day starts from zero.
  assert.equal(core.feedTime(record, 'TikTok', 'd1', 3, 15).remind, false);
  assert.equal(core.feedTime(record, 'Instagram', 'd2', 3, 15).remind, false);
});
