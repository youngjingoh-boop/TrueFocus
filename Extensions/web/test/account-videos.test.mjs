import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const core = require('../core.js');

const NOW = Date.UTC(2026, 9, 28, 9, 0, 0);
const eff = (overrides = {}) => Object.assign(core.effective(null, null, NOW, null), overrides);
const kind = (url, e, from = null) => core.classify(url, e, {}, NOW, { from }).kind;

test("Instagram: an account's reels and posts play, opened from the account", () => {
  const e = eff();
  assert.notEqual(kind('https://www.instagram.com/platinumtennisgc/reels/', e), 'shortform');
  assert.notEqual(kind('https://www.instagram.com/reel/C1abc/', e, '/platinumtennisgc/reels/'), 'shortform');
  assert.notEqual(kind('https://www.instagram.com/platinumtennisgc/reel/C1abc/', e, '/platinumtennisgc/'), 'shortform');
  assert.notEqual(kind('https://www.instagram.com/p/C1abc/', e, '/platinumtennisgc/'), 'shortform');
  // A link someone sent you, opened straight away.
  assert.notEqual(kind('https://www.instagram.com/reel/C1abc/', e, null), 'shortform');
});

test('Instagram: search stays open; the Reels tab, Explore and reels tapped in the feed are walled', () => {
  const e = eff();
  assert.notEqual(kind('https://www.instagram.com/explore/search/', e), 'shortform');
  assert.equal(kind('https://www.instagram.com/reels/C1abc/', e), 'shortform');
  assert.equal(kind('https://www.instagram.com/explore/', e), 'shortform');
  assert.equal(kind('https://www.instagram.com/reel/C1abc/', e, '/'), 'shortform');
  assert.equal(kind('https://www.instagram.com/reel/C1abc/', e, '/explore/'), 'shortform');
});

test("Facebook: a page's videos and reels play; Watch, Reels, Stories and feed reels are walled", () => {
  const e = eff({ workPlatforms: ['Facebook'] });
  assert.equal(kind('https://www.facebook.com/somepage/videos/123', e), 'safe');
  assert.equal(kind('https://www.facebook.com/reel/987', e, '/somepage'), 'safe');
  assert.equal(kind('https://www.facebook.com/watch/?v=123', e), 'safe');
  assert.equal(kind('https://www.facebook.com/watch/', e), 'shortform');
  assert.equal(kind('https://www.facebook.com/reel/987', e, '/'), 'shortform');
  assert.equal(kind('https://www.facebook.com/stories/1', e), 'shortform');
});

test('Instagram for work: an account reel is open in focus, with the check-in instead of a wall', () => {
  const e = eff({ strict: true, workPlatforms: ['Instagram'] });
  const v = core.classify('https://www.instagram.com/reel/C1abc/', e, {}, NOW, { from: '/platinumtennisgc/reels/' });
  assert.equal(v.kind, 'safe');
  assert.equal(v.work, true);
  assert.equal(v.feedless, false);
});

test('feed pages, where reel links are hidden', () => {
  const ig = core.feedSiteByName('Instagram');
  const fb = core.feedSiteByName('Facebook');
  for (const p of ['/', '/reels/', '/explore/']) assert.equal(core.isFeedPath(ig, p), true, p);
  for (const p of ['/platinumtennisgc/', '/platinumtennisgc/reels/', '/explore/search/', '/p/abc/']) {
    assert.equal(core.isFeedPath(ig, p), false, p);
  }
  for (const p of ['/', '/watch/', '/reels/']) assert.equal(core.isFeedPath(fb, p), true, p);
  assert.equal(core.isFeedPath(fb, '/somepage'), false);
});
