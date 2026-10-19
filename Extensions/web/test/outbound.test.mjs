// Pages that only pass you on (link shims) or that are work tools on a feed site's domain
// must never be treated as the feed.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { ROOT } from './generate-rules.mjs';

const require = createRequire(import.meta.url);
const core = require('../core.js');

const NOW = Date.UTC(2026, 9, 19, 9, 0, 0);
const eff = (overrides = {}) => Object.assign(core.effective(null, null, NOW, null), overrides);
const kind = (url, e, cooldowns = {}) => core.classify(url, e, cooldowns, NOW).kind;
const open = (k) => k === 'safe' || k === 'other';

test('a link opened from Instagram DMs or Messenger goes through, even in focus', () => {
  const booted = { Instagram: NOW + 600000, Facebook: NOW + 600000, LinkedIn: NOW + 600000 };
  for (const e of [eff({ strict: true }), eff({ strict: true, instagramMessagesOnly: false, facebookWorkOnly: false })]) {
    for (const url of [
      'https://l.instagram.com/?u=https%3A%2F%2Fexample.com%2Fdoc&e=AT0',
      'https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2F&h=AT0',
      'https://lm.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2F',
      'https://www.linkedin.com/safety/go?url=https%3A%2F%2Fexample.com&trk=flagship-messaging-web',
      'https://www.linkedin.com/redir/redirect?url=https%3A%2F%2Fexample.com',
    ]) {
      assert.ok(open(kind(url, e, booted)), url);
      // Never "respond": that would send the link to a messages page that doesn't exist there.
      assert.notEqual(core.classify(url, e, booted, NOW).kind, 'respond', url);
    }
  }
});

test("YouTube's upload page opens in Studio, and Studio stays open in focus", () => {
  const e = eff({ strict: true });
  assert.equal(kind('https://www.youtube.com/upload', e), 'safe');
  assert.ok(open(kind('https://studio.youtube.com/channel/UC123/videos/upload?d=ud', e, { YouTube: NOW + 600000 })));
  assert.equal(kind('https://www.youtube.com/watch?v=1', e), 'strict');
});

test("TikTok's ads and business tools and its sign-in are not short-form", () => {
  const e = eff({ strict: true });
  for (const url of [
    'https://ads.tiktok.com/i18n/dashboard?aadvid=1',
    'https://business.tiktok.com/manage/overview?org_id=1',
    'https://developers.tiktok.com/apps/',
    'https://seller-us.tiktok.com/homepage',
    'https://www.tiktok.com/v2/auth/authorize/?client_key=abc&scope=user.info.basic',
    'https://www.tiktok.com/auth/authorize/?client_key=abc',
  ]) {
    assert.ok(open(kind(url, e)), url);
  }
  assert.equal(kind('https://www.tiktok.com/foryou', e), 'shortform');
  assert.equal(kind('https://www.tiktok.com/@someone/video/1', e), 'shortform');
});

test("the TikTok wall's network rules let the same pages through", () => {
  const rules = JSON.parse(readFileSync(join(ROOT, 'rules_shortform.json'), 'utf8'));
  // A tiny urlFilter matcher: enough for "||host/path" and "||host^".
  const matches = (filter, url) => {
    const u = new URL(url);
    const m = filter.match(/^\|\|([^/^]+)(\/[^^]*)?(\^)?$/);
    if (!m) return false;
    const [, host, path = '', sep] = m;
    if (!(u.hostname === host || u.hostname.endsWith('.' + host))) return false;
    const rest = u.pathname + u.search;
    if (!rest.startsWith(path || '/') && path) return false;
    if (sep && path) { const next = rest.charAt(path.length); return next === '' || /[^\w.%-]/.test(next); }
    return true;
  };
  const verdict = (url) => {
    const hits = rules.filter((r) => matches(r.condition.urlFilter, url));
    if (!hits.length) return 'none';
    const top = Math.max(...hits.map((r) => r.priority));
    return hits.some((r) => r.priority === top && r.action.type === 'allow') ? 'allow' : 'redirect';
  };
  assert.equal(verdict('https://www.tiktok.com/foryou'), 'redirect');
  for (const url of ['https://ads.tiktok.com/i18n/dashboard', 'https://business.tiktok.com/manage',
    'https://www.tiktok.com/v2/auth/authorize/?client_key=1']) {
    assert.notEqual(verdict(url), 'redirect', url);
  }
});

test('"respond" lands in a messages page that exists, from any subdomain', () => {
  const e = eff();
  const cases = {
    'https://www.instagram.com/': 'https://www.instagram.com/direct/inbox/',
    'https://instagram.com/': 'https://instagram.com/direct/inbox/',
    'https://m.facebook.com/?sk=h_chr': 'https://m.facebook.com/messages/',
    'https://web.facebook.com/': 'https://web.facebook.com/messages/',
    'https://www.linkedin.com/feed/': 'https://www.linkedin.com/messaging/',
    // Not app hosts: there's no inbox on them, so go to the site's own.
    'https://about.instagram.com/': 'https://www.instagram.com/direct/inbox/',
    'https://de-de.facebook.com/': 'https://www.facebook.com/messages/',
    'https://about.linkedin.com/': 'https://www.linkedin.com/messaging/',
  };
  for (const [url, redirect] of Object.entries(cases)) {
    const v = core.classify(url, e, {}, NOW);
    assert.equal(v.kind, 'respond', url);
    assert.equal(v.redirect, redirect, url);
    // And the landing page is safe, so it never redirects again.
    assert.equal(core.classify(redirect, e, {}, NOW).kind, 'safe', redirect);
  }
});
