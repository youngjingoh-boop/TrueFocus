// Your own sites: "Always allowed" and "Blocked on tasks", the same lists on every surface.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { loadContent } from './content-harness.mjs';

const require = createRequire(import.meta.url);
const core = require('../core.js');

const NOW = Date.UTC(2026, 10, 9, 9, 0, 0);
const onTask = { mode: 'focus', modeStartedAt: NOW / 1000 - 60 };
const eff = (settings, snapshot) => core.effective({ settings, snapshot }, null, NOW, null);

test('a blocked site closes whole on a task, messages included, and opens off it', () => {
  const settings = { blockedSites: ['linkedin.com'], allowedSites: [] };
  const verdict = core.classify('https://www.linkedin.com/messaging/', eff(settings, onTask), {}, NOW);
  assert.equal(verdict.kind, 'strict');
  assert.equal(verdict.custom, true);
  assert.equal(verdict.site, 'linkedin.com');
  assert.notEqual(core.classify('https://www.linkedin.com/messaging/', eff(settings, null), {}, NOW).kind, 'strict');
});

test('a site that was never a feed site can be blocked', () => {
  const verdict = core.classify('https://news.ycombinator.com/', eff({ blockedSites: ['ycombinator.com'] }, onTask), {}, NOW);
  assert.equal(verdict.kind, 'strict');
  assert.equal(core.classify('https://notycombinator.com/', eff({ blockedSites: ['ycombinator.com'] }, onTask), {}, NOW).kind, 'other');
});

test('allowed beats blocked, and the adult filter beats both', () => {
  const settings = { allowedSites: ['docs.example.com', 'pornhub.com'], blockedSites: ['example.com', 'pornhub.com'] };
  assert.equal(core.classify('https://docs.example.com/', eff(settings, onTask), {}, NOW).allowed, true);
  assert.equal(core.classify('https://www.example.com/', eff(settings, onTask), {}, NOW).custom, true);
  assert.equal(core.classify('https://pornhub.com/', eff(settings, onTask), {}, NOW).kind, 'adult');
});

test('network rules: block rules exist only on a task and lose a tie to allow', () => {
  const settings = { allowedSites: ['docs.example.com'], blockedSites: ['example.com', 'reddit.com'] };
  const off = core.siteRules(eff(settings, null));
  assert.deepEqual(off.map((r) => r.action.type), ['allow']);
  const on = core.siteRules(eff(settings, onTask));
  assert.deepEqual(on.map((r) => r.action.type), ['allow', 'redirect', 'redirect']);
  assert.equal(new Set(on.map((r) => r.id)).size, on.length);
  assert.equal(on[1].priority, on[0].priority);
  assert.equal(on[1].action.redirect.extensionPath, '/blocked.html?reason=focus&site=example.com');
  assert.deepEqual(on[2].condition, { requestDomains: ['reddit.com'], resourceTypes: ['main_frame'] });
});

test('only a real change rewrites the rules', () => {
  const a = core.siteRules(eff({ allowedSites: ['a.com', 'b.com'], blockedSites: ['c.com'] }, onTask));
  const reversed = JSON.parse(JSON.stringify(a)).reverse();
  reversed.find((r) => r.action.type === 'allow').condition.requestDomains.reverse();
  assert.equal(core.sameSiteRules(reversed, a), true);
  const off = core.siteRules(eff({ allowedSites: ['a.com', 'b.com'], blockedSites: ['c.com'] }, null));
  assert.equal(core.sameSiteRules(off, a), false);
});

test('a site sits on one list or neither', () => {
  const lists = { allowedSites: ['a.com'], blockedSites: ['b.com'] };
  assert.deepEqual(core.withSiteRule(lists, 'a.com', 'block'), { allowedSites: [], blockedSites: ['b.com', 'a.com'] });
  assert.deepEqual(core.withSiteRule(lists, 'b.com', 'allow'), { allowedSites: ['a.com', 'b.com'], blockedSites: [] });
  assert.deepEqual(core.withSiteRule(lists, 'a.com', 'none'), { allowedSites: [], blockedSites: ['b.com'] });
  assert.deepEqual(core.withSiteRule(null, 'a.com', 'allow'), { allowedSites: ['a.com'], blockedSites: [] });
});

test('without the app, the extension keeps its own lists; with it, the app wins', () => {
  const prefs = { allowedSites: ['mine.com'], blockedSites: ['nope.com'] };
  const alone = core.effective(null, prefs, NOW, null);
  assert.deepEqual(alone.allowedSites, ['mine.com']);
  assert.deepEqual(alone.blockedSites, ['nope.com']);
  const paired = core.effective({ settings: { allowedSites: ['app.com'], blockedSites: [] } }, prefs, NOW, null);
  assert.deepEqual(paired.allowedSites, ['app.com']);
  assert.deepEqual(paired.blockedSites, []);
});

test('which site a tab is on', () => {
  const base = 'chrome-extension://abc/';
  assert.equal(core.pageSite('https://www.LinkedIn.com/feed/', base), 'linkedin.com');
  assert.equal(core.pageSite(base + 'blocked.html?reason=focus&site=reddit.com', base), 'reddit.com');
  // A built-in feed block names the platform, not a site.
  assert.equal(core.pageSite(base + 'blocked.html?reason=focus&site=Instagram', base), null);
  assert.equal(core.pageSite(base + 'popup.html', base), null);
  assert.equal(core.pageSite('chrome://extensions/', base), null);
  assert.equal(core.pageSite(undefined, base), null);
});

test('the popup says plainly when a site is not TruFocus\'s doing', () => {
  const allowed = core.siteStatus('linkedin.com', eff({ allowedSites: ['linkedin.com'] }, onTask));
  assert.equal(allowed.rule, 'allow');
  assert.match(allowed.line, /never blocks/);
  assert.match(allowed.line, /your network/);
  assert.equal(core.siteStatus('uk.linkedin.com', eff({ allowedSites: ['linkedin.com'] }, onTask)).entry, 'linkedin.com');

  assert.match(core.siteStatus('notion.so', eff({}, onTask)).line, /isn.t blocking/);
  assert.match(core.siteStatus('reddit.com', eff({}, onTask)).line, /feed is closed/);
  assert.match(core.siteStatus('reddit.com', eff({ blockedSites: ['reddit.com'] }, onTask)).line, /Closed while/);
  assert.match(core.siteStatus('reddit.com', eff({ blockedSites: ['reddit.com'] }, null)).line, /Open now/);
  assert.equal(core.siteStatus('pornhub.com', eff({}, null)).rule, 'adult');
});

test('a blocked feed site leaves for the blocked page, named by its host', async () => {
  const state = { settings: { blockedSites: ['reddit.com'] }, snapshot: { mode: 'focus', modeStartedAt: Date.now() / 1000 } };
  const page = loadContent('https://www.reddit.com/message/inbox', { tfState: state });
  await page.settle();
  assert.match(page.replaced[0], /blocked\.html\?reason=focus&site=reddit\.com/);
});
