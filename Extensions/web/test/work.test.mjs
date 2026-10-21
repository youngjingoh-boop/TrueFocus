import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const core = require('../core.js');

const NOW = Date.UTC(2026, 9, 21, 9, 0, 0);
const eff = (overrides = {}, settings = null) =>
  Object.assign(core.effective(settings ? { settings } : null, null, NOW, null), overrides);
const verdict = (url, e) => core.classify(url, e, {}, NOW);

test('without work mode, YouTube and Instagram pages are walled in focus', () => {
  const e = eff({ strict: true });
  assert.equal(verdict('https://www.youtube.com/watch?v=abc', e).kind, 'strict');
  assert.equal(verdict('https://www.instagram.com/someprospect/', e).kind, 'strict');
  assert.equal(verdict('https://x.com/someprospect', e).kind, 'strict');
});

test('YouTube for work: watching, searching and channels stay open in focus, with feeds hidden', () => {
  const e = eff({ strict: true, workPlatforms: ['YouTube'] });
  for (const url of ['https://www.youtube.com/watch?v=abc', 'https://www.youtube.com/results?search_query=onboarding',
    'https://www.youtube.com/@somechannel', 'https://www.youtube.com/']) {
    const v = verdict(url, e);
    assert.equal(v.kind, 'safe', url);
    assert.equal(v.feedless, true, url);
  }
});

test('YouTube for work still walls Shorts', () => {
  const e = eff({ strict: true, workPlatforms: ['YouTube'] });
  assert.equal(verdict('https://www.youtube.com/shorts/xyz', e).kind, 'shortform');
});

test('Instagram for work: profiles and posts open; home hides its feed; Reels stay walled', () => {
  const e = eff({ strict: true, workPlatforms: ['Instagram'], instagramMessagesOnly: false });
  const profile = verdict('https://www.instagram.com/someprospect/', e);
  assert.equal(profile.kind, 'safe');
  assert.equal(profile.feedless, false);
  assert.equal(verdict('https://www.instagram.com/p/C1abc/', e).kind, 'safe');
  const home = verdict('https://www.instagram.com/', e);
  assert.equal(home.kind, 'safe');
  assert.equal(home.feedless, true);
  assert.equal(verdict('https://www.instagram.com/reels/', e).kind, 'shortform');
});

test('Instagram for work keeps messages-only home when that is on', () => {
  const e = eff({ strict: true, workPlatforms: ['Instagram'] });
  assert.equal(verdict('https://www.instagram.com/', e).kind, 'respond');
});

test('X for work: profiles open; the home timeline hides its feed', () => {
  const e = eff({ strict: true, workPlatforms: ['X'] });
  const profile = verdict('https://x.com/someprospect', e);
  assert.equal(profile.kind, 'safe');
  assert.equal(profile.feedless, false);
  assert.equal(verdict('https://x.com/home', e).feedless, true);
});

test('work platforms come from the app settings and ignore unknown names', () => {
  const e = eff({}, { workPlatforms: ['YouTube', 'Instagram', 'Nonsense'] });
  assert.deepEqual(e.workPlatforms, ['YouTube', 'Instagram']);
  assert.deepEqual(eff().workPlatforms, []);
});
