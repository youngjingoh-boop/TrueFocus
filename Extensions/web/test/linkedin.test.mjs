import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const core = require('../core.js');

const NOW = Date.UTC(2026, 9, 19, 9, 0, 0);
const eff = (overrides = {}, settings = null) =>
  Object.assign(core.effective(settings ? { settings } : null, null, NOW, null), overrides);

test('work-only LinkedIn: the home feed opens Messaging', () => {
  for (const url of ['https://www.linkedin.com/', 'https://www.linkedin.com/feed/', 'https://linkedin.com/feed']) {
    const v = core.classify(url, eff(), {}, NOW);
    assert.equal(v.kind, 'respond', url);
    assert.match(v.redirect, /\/messaging\/$/);
  }
});

test('LinkedIn video is walled like Reels', () => {
  assert.equal(core.classify('https://www.linkedin.com/video/', eff(), {}, NOW).kind, 'shortform');
  assert.equal(core.classify('https://www.linkedin.com/feed/videos/', eff(), {}, NOW).kind, 'shortform');
});

test('the LinkedIn you work in stays open, unguarded, even during focus and after a boot-out', () => {
  const e = eff({ strict: true });
  const booted = { LinkedIn: NOW + 600000 };
  for (const url of [
    'https://www.linkedin.com/messaging/thread/2-abc/',
    'https://www.linkedin.com/in/someone/',
    'https://www.linkedin.com/search/results/people/?keywords=founder',
    'https://www.linkedin.com/mynetwork/',
    'https://www.linkedin.com/jobs/view/123/',
    'https://www.linkedin.com/company/acme/',
    'https://www.linkedin.com/sales/home',
    'https://www.linkedin.com/talent/hire/1',
    'https://www.linkedin.com/campaignmanager/accounts/1/campaigns',
    'https://www.linkedin.com/feed/update/urn:li:activity:123/',
    'https://www.linkedin.com/posts/someone_post-activity-123',
    'https://www.linkedin.com/pulse/an-article/',
    'https://www.linkedin.com/notifications/',
    'https://business.linkedin.com/marketing-solutions',
  ]) {
    assert.ok(['safe', 'other'].includes(core.classify(url, e, booted, NOW).kind), url);
  }
});

test('with work-only off, the LinkedIn feed is guarded like any feed', () => {
  assert.equal(core.classify('https://www.linkedin.com/feed/', eff({ linkedInWorkOnly: false }), {}, NOW).kind, 'feed');
  assert.equal(core.classify('https://www.linkedin.com/feed/', eff({ linkedInWorkOnly: false, strict: true }), {}, NOW).kind, 'strict');
});

test('the app setting wins, and work-only is on by default', () => {
  assert.equal(eff().linkedInWorkOnly, true);
  assert.equal(eff({}, { linkedInWorkOnly: false }).linkedInWorkOnly, false);
});

test('always-allowed sites are never blocked or guarded; the adult filter still applies', () => {
  const e = eff({ strict: true }, { allowedSites: ['https://www.Reddit.com/r/swift', 'not a site', 'pornhub.com'] });
  assert.deepEqual(e.allowedSites, ['reddit.com', 'pornhub.com']);
  assert.equal(core.classify('https://old.reddit.com/r/swift/', e, { Reddit: NOW + 600000 }, NOW).kind, 'other');
  assert.equal(core.classify('https://www.reddit.com/', e, {}, NOW).kind, 'other');
  assert.equal(core.classify('https://www.pornhub.com/', e, {}, NOW).kind, 'adult');
  assert.equal(core.classify('https://www.instagram.com/', e, {}, NOW).kind, 'respond');
});

test('site names are normalised the same way as the app', () => {
  assert.equal(core.normalizedSite('https://www.LinkedIn.com/feed/?x=1'), 'linkedin.com');
  assert.equal(core.normalizedSite('notion.so'), 'notion.so');
  assert.equal(core.normalizedSite('app.slack.com:443'), 'app.slack.com');
  assert.equal(core.normalizedSite('localhost'), null);
  assert.equal(core.normalizedSite('two words.com'), null);
  assert.equal(core.normalizedSite('a..b.com'), null);
});
