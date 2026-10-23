import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const core = require('../core.js');

const NOW = Date.UTC(2026, 9, 23, 9, 0, 0);
const eff = (overrides = {}) => Object.assign(core.effective(null, null, NOW, null), overrides);
const verdict = (url, e) => core.classify(url, e, {}, NOW);

/** Strokes every `every` s for `seconds`, ticking every second. Returns when it asked. */
function scroll(c, from, seconds, every = 4) {
  let next = from;
  let asked = null;
  for (let t = from; t <= from + seconds; t += 1) {
    if (t >= next) { c.stroke(t); next += every; }
    if (c.tick(t) && asked === null) asked = t;
  }
  return asked;
}

test('check-in asks after two minutes of scrolling', () => {
  const c = new core.ScrollCheckIn();
  const asked = scroll(c, 0, 200);
  assert.ok(Math.abs(asked - 120) <= 2, String(asked));
  assert.equal(c.asking, true);
  assert.equal(c.minutes, 2);
});

test('check-in: reading without scrolling does not count', () => {
  const c = new core.ScrollCheckIn();
  c.stroke(0);
  for (let t = 0; t <= 240; t += 3) assert.equal(c.tick(t), false);
  assert.equal(c.scrolled, core.CHECKIN.activeWindow);
});

test('check-in: "Working" quiets it for five more minutes, and it asks once until answered', () => {
  const c = new core.ScrollCheckIn();
  scroll(c, 0, 125);
  assert.equal(scroll(c, 126, 200), null);
  c.working();
  const asked = scroll(c, 330, 400);
  assert.ok(Math.abs(asked - 330 - 300) <= 4, String(asked));
  assert.equal(c.minutes, 5);
});

test('check-in survives a reload through JSON', () => {
  const c = new core.ScrollCheckIn();
  scroll(c, 0, 125);
  const back = new core.ScrollCheckIn(JSON.parse(JSON.stringify(c)));
  assert.equal(back.asking, true);
  assert.equal(back.scrolled, c.scrolled);
});

test('Facebook for work: pages, posting and composer stay whole in focus; only the News Feed is hidden', () => {
  const e = eff({ strict: true, workPlatforms: ['Facebook'] });
  for (const url of ['https://www.facebook.com/mybusinesspage', 'https://www.facebook.com/pages/create',
    'https://www.facebook.com/groups/1234/', 'https://www.facebook.com/profile.php?id=1']) {
    const v = verdict(url, e);
    assert.equal(v.kind, 'safe', url);
    assert.equal(v.work, true, url);
    assert.equal(v.feedless, false, url);
  }
  const home = verdict('https://www.facebook.com/', e);
  assert.equal(home.kind, 'safe');
  assert.equal(home.feedless, true);
  assert.equal(verdict('https://www.facebook.com/reel/123', e).kind, 'shortform');
});

test('Instagram for work beats messages-only: home stays put with its feed hidden', () => {
  const e = eff({ workPlatforms: ['Instagram'], instagramMessagesOnly: true });
  const home = verdict('https://www.instagram.com/', e);
  assert.equal(home.kind, 'safe');
  assert.equal(home.feedless, true);
  assert.equal(verdict('https://www.instagram.com/explore/search/', e).kind === 'respond', false);
});

test('check-in copy names the site and the task', () => {
  const copy = core.checkInCopy('Facebook', 'Launch ad', 2);
  assert.equal(copy.title, 'Working or scrolling?');
  assert.match(copy.body, /2 minutes of scrolling on Facebook\. You’re on “Launch ad”\./);
});
