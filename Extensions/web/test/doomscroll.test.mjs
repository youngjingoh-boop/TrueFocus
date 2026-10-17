// 1:1 port of DoomScrollTests in Packages/TrueFocusKit/Tests/TrueFocusKitTests.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { DoomScrollDetector, normalizeConfig, DEFAULT_CONFIG, limits } = require('../core.js');

const t0 = 3_000_000;
const calm = { kind: 'calm' };

test('slow reading is calm', () => {
  const detector = new DoomScrollDetector();
  let verdict = calm;
  // One stroke every 12 seconds for two minutes: reading an article.
  for (let i = 0; i < 10; i++) verdict = detector.stroke(t0 + i * 12);
  assert.deepEqual(verdict, calm);
});

test('fast skimming boots on burst', () => {
  const detector = new DoomScrollDetector();
  let verdict = calm;
  for (let i = 0; i < 25; i++) verdict = detector.stroke(t0 + i * 2);
  assert.deepEqual(verdict, { kind: 'boot', reason: 'burst' });
});

test('warns before booting', () => {
  const detector = new DoomScrollDetector();
  let sawWarn = false;
  for (let i = 0; i < 25; i++) {
    if (detector.stroke(t0 + i * 2).kind === 'warn') sawWarn = true;
  }
  assert.ok(sawWarn);
});

test('reels swiping boots on binge', () => {
  const detector = new DoomScrollDetector();
  let verdict = calm;
  // One swipe every 8 seconds never trips the burst rule, but 60 of them is a binge.
  let i = 0;
  while (i < 80) {
    verdict = detector.stroke(t0 + i * 8);
    if (verdict.kind === 'boot') break;
    i += 1;
  }
  assert.deepEqual(verdict, { kind: 'boot', reason: 'binge' });
  assert.equal(i, 59);
});

test('pause resets the sitting', () => {
  // Dwell is deliberately cumulative across sittings; isolate the binge rule.
  const detector = new DoomScrollDetector({ dwellSeconds: 3600 });
  for (let i = 0; i < 40; i++) detector.stroke(t0 + i * 8);
  // A two-minute pause ends the sitting.
  const resume = t0 + 40 * 8 + 120;
  let verdict = calm;
  for (let i = 0; i < 30; i++) verdict = detector.stroke(resume + i * 8);
  assert.notEqual(verdict.kind, 'boot', 'sitting should have reset after the pause');
});

test('dwell boots even at a gentle pace', () => {
  const detector = new DoomScrollDetector({ sessionStrokes: 1000, dwellSeconds: 300 });
  let verdict = calm;
  let t = t0;
  for (let n = 0; n < 40; n++) {
    verdict = detector.stroke(t);
    t += 10;
    verdict = detector.tick(t);
    if (verdict.kind === 'boot') break;
  }
  assert.deepEqual(verdict, { kind: 'boot', reason: 'dwell' });
  assert.ok(detector.engagedTime >= 300);
});

test('strict mode during focus is much faster', () => {
  const detector = new DoomScrollDetector(DEFAULT_CONFIG, true);
  let count = 0;
  for (let i = 0; i < 30; i++) {
    count = i + 1;
    if (detector.stroke(t0 + i * 3).kind === 'boot') break;
  }
  assert.equal(count, 8);
});

test('idle time does not count as dwell', () => {
  const detector = new DoomScrollDetector();
  detector.stroke(t0);
  detector.tick(t0 + 3600);
  assert.ok(Math.abs(detector.engagedTime - 45) < 0.001);
});

test('config decodes with missing keys', () => {
  const config = normalizeConfig({ burstStrokes: 10 });
  assert.equal(config.burstStrokes, 10);
  assert.equal(config.sessionStrokes, DEFAULT_CONFIG.sessionStrokes);
  assert.equal(normalizeConfig({ dwellSeconds: 'x' }).dwellSeconds, DEFAULT_CONFIG.dwellSeconds);
});

test('limits match DoomScrollConfig.limits(strict:)', () => {
  assert.deepEqual(limits(DEFAULT_CONFIG, false), { burst: 25, session: 60, dwell: 480 });
  // 25 × 0.3 = 7.5 rounds away from zero, like Swift's rounded().
  assert.deepEqual(limits(DEFAULT_CONFIG, true), { burst: 8, session: 18, dwell: 144 });
  assert.deepEqual(limits({ ...DEFAULT_CONFIG, burstStrokes: 5, sessionStrokes: 10, dwellSeconds: 100 }, true),
    { burst: 4, session: 8, dwell: 60 });
});

test('long flings weigh more, capped at three screens', () => {
  const detector = new DoomScrollDetector();
  detector.stroke(t0, 10);
  detector.stroke(t0 + 1, 0.1);
  assert.ok(Math.abs(detector.progress - 3.5 / 25) < 1e-9);
});
