import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const core = require('../core.js');

const NOW = Date.UTC(2026, 9, 19, 9, 0, 0);
const working = {
  snapshot: { mode: 'focus', modeStartedAt: NOW / 1000 - 600, taskID: 'A', taskTitle: 'ScaleMaster marketing' },
  settings: { macDriftGuard: true },
  fetchedAt: NOW,
};
const eff = (state) => core.effective(state, null, NOW, null);

test('the active tab is reported as host and title while a focus task runs', () => {
  const report = core.tabActivity('https://www.gangnam-clinic.co.kr/price?x=1', '  가슴성형 비용  ', eff(working), working.settings);
  assert.deepEqual(report, { host: 'gangnam-clinic.co.kr', title: '가슴성형 비용' });
});

test('nothing is reported outside focus, for browser pages, or with the guard off', () => {
  const resting = Object.assign({}, working, { snapshot: Object.assign({}, working.snapshot, { mode: 'rest' }) });
  assert.equal(core.tabActivity('https://docs.google.com/', 'Doc', eff(resting), working.settings), null);
  assert.equal(core.tabActivity('https://docs.google.com/', 'Doc', eff(null), null), null);
  assert.equal(core.tabActivity('chrome://newtab/', 'New Tab', eff(working), working.settings), null);
  assert.equal(core.tabActivity('https://docs.google.com/', 'Doc', eff(working), { macDriftGuard: false }), null);
});

test('titles are capped', () => {
  const report = core.tabActivity('https://example.com/', 'x'.repeat(500), eff(working), working.settings);
  assert.equal(report.title.length, 200);
});
