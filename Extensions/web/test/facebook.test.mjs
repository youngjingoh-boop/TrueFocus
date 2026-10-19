import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const core = require('../core.js');

const NOW = Date.UTC(2026, 9, 19, 9, 0, 0);
const eff = (overrides = {}, settings = null) =>
  Object.assign(core.effective(settings ? { settings } : null, null, NOW, null), overrides);
const kind = (url, e = eff(), cooldowns = {}) => core.classify(url, e, cooldowns, NOW).kind;

test('signing in with Facebook is never walled, work-only or not, even in focus', () => {
  for (const e of [eff({ strict: true }), eff({ strict: true, facebookWorkOnly: false })]) {
    for (const url of [
      'https://www.facebook.com/v19.0/dialog/oauth?client_id=1&redirect_uri=https%3A%2F%2Fdevelopers.facebook.com',
      'https://www.facebook.com/dialog/oauth?client_id=1',
      'https://www.facebook.com/login.php?next=x',
      'https://www.facebook.com/login/device-based/regular/login/',
      'https://www.facebook.com/checkpoint/1501092823525282/',
      'https://www.facebook.com/connect/login_success.html',
      'https://m.facebook.com/v20.0/dialog/oauth?client_id=1',
      'https://developers.facebook.com/tools/explorer/',
    ]) {
      assert.ok(['safe', 'other'].includes(kind(url, e)), url);
    }
  }
});

test('work-only Facebook: the News Feed opens Messenger', () => {
  for (const url of ['https://www.facebook.com/', 'https://www.facebook.com/home.php', 'https://m.facebook.com/?sk=h_chr',
    'https://www.facebook.com/groups/feed/']) {
    const v = core.classify(url, eff(), {}, NOW);
    assert.equal(v.kind, 'respond', url);
    assert.match(v.redirect, /\/messages\/$/);
  }
});

test('work-only Facebook: video and stories are walled, even with short-form hiding off', () => {
  for (const e of [eff(), eff({ hideShortForm: false })]) {
    for (const url of [
      'https://www.facebook.com/watch/?v=1',
      'https://www.facebook.com/reel/123',
      'https://www.facebook.com/stories/123/',
      'https://www.facebook.com/somepage/videos/456/',
      'https://www.facebook.com/gaming/feed',
    ]) {
      assert.equal(kind(url, e), 'shortform', url);
    }
  }
});

test('work-only Facebook: the rest stays open, unguarded, in focus and after a boot-out, posts hidden', () => {
  const e = eff({ strict: true });
  const booted = { Facebook: NOW + 600000 };
  for (const url of [
    'https://www.facebook.com/acmebakery',
    'https://www.facebook.com/profile.php?id=1',
    'https://www.facebook.com/groups/123/',
    'https://www.facebook.com/events/123/',
    'https://www.facebook.com/marketplace/item/1/',
    'https://www.facebook.com/somepage/posts/pfbid0abc',
  ]) {
    const v = core.classify(url, e, booted, NOW);
    assert.equal(v.kind, 'safe', url);
    assert.equal(v.feedless, true, url);
  }
  const search = core.classify('https://www.facebook.com/search/pages/?q=acme', e, booted, NOW);
  assert.equal(search.kind, 'safe');
  assert.equal(search.feedless, false);
  const messenger = core.classify('https://www.facebook.com/messages/t/1', e, booted, NOW);
  assert.equal(messenger.kind, 'safe');
  assert.ok(!messenger.feedless);
});

test('lookalike Facebook paths are not video', () => {
  assert.equal(core.isFacebookVideo('/videoshop'), false);
  assert.equal(core.isFacebookVideo('/watchmaker.co'), false);
  assert.equal(core.isFacebookFeed('/groups/123/'), false);
});

test('with work-only off, the Facebook feed is guarded like any feed', () => {
  assert.equal(kind('https://www.facebook.com/', eff({ facebookWorkOnly: false })), 'feed');
  assert.equal(kind('https://www.facebook.com/acmebakery', eff({ facebookWorkOnly: false, strict: true })), 'strict');
  assert.equal(kind('https://www.facebook.com/stories/1/', eff({ facebookWorkOnly: false })), 'shortform');
});

test('the app setting wins, and work-only is on by default', () => {
  assert.equal(eff().facebookWorkOnly, true);
  assert.equal(eff({}, { facebookWorkOnly: false }).facebookWorkOnly, false);
});
