// "Always allowed" sites are never blocked by the extension, the network rules included.
// The adult filter still applies to them.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { buildRules } from './generate-rules.mjs';
import { loadContent } from './content-harness.mjs';

const require = createRequire(import.meta.url);
const core = require('../core.js');

const NOW = Date.UTC(2026, 9, 19, 9, 0, 0);

test('allowed sites get a network allow rule that outranks the short-form wall, not the adult filter', () => {
  const rules = buildRules();
  const allow = core.allowRules(['youtube.com', 'pornhub.com', 'youtube.com']);
  assert.equal(allow.length, 1);
  assert.equal(allow[0].action.type, 'allow');
  assert.deepEqual(allow[0].condition.requestDomains, ['youtube.com', 'pornhub.com']);
  assert.deepEqual(allow[0].condition.resourceTypes, ['main_frame']);
  const low = (file) => Math.min(...rules[file].map((r) => r.priority));
  const walls = rules['rules_shortform.json'].filter((r) => r.action.type === 'redirect');
  assert.ok(walls.every((r) => allow[0].priority > r.priority), 'beats every short-form redirect');
  for (const file of ['rules_adult.json', 'rules_adult_keywords.json', 'rules_safesearch.json']) {
    assert.ok(low(file) > allow[0].priority, `${file} still wins over an allowed site`);
  }
  assert.deepEqual(core.allowRules([]), []);
  assert.deepEqual(core.allowRules(undefined), []);
});

test('effective() feeds allowRules with the cleaned list', () => {
  const eff = core.effective({ settings: { allowedSites: ['https://www.YouTube.com/feed', 'nope'] } }, null, NOW, null);
  assert.deepEqual(core.allowRules(eff.allowedSites)[0].condition.requestDomains, ['youtube.com']);
});

test('an allowed site keeps its Shorts shelves', async () => {
  const state = { settings: { allowedSites: ['youtube.com'], hideShortForm: true } };
  const page = loadContent('https://www.youtube.com/', { tfState: state });
  await page.settle();
  assert.ok(!page.classes().includes('tf-hide-shorts'));
  const other = loadContent('https://www.youtube.com/', { tfState: { settings: { hideShortForm: true } } });
  await other.settle();
  assert.ok(other.classes().includes('tf-hide-shorts'));
});
