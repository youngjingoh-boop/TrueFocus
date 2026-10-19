// The default tone and "Your own words" (settings.customReminders), in step with
// CustomReminders.swift and Copy.apply(_:to:task:).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createRequire } from 'node:module';
import { ROOT } from './generate-rules.mjs';

const require = createRequire(import.meta.url);
const core = require('../core.js');

const NOW = Date.UTC(2026, 9, 17, 9, 0, 0);
const SWIFT = readFileSync(join(ROOT, '../..', 'Packages/TrueFocusKit/Sources/TrueFocusKit/CustomReminders.swift'), 'utf8');

const withReminders = (customReminders, extra = {}) =>
  core.effective({ settings: Object.assign({ tone: 'direct', customReminders }, extra) }, null, NOW, null);

test('the default tone is direct, with or without the app', () => {
  assert.equal(core.effective(null, null, NOW, null).tone, 'direct');
  assert.equal(core.effective({ settings: {} }, null, NOW, null).tone, 'direct');
  assert.equal(core.effective({ settings: { tone: 'loud' } }, null, NOW, null).tone, 'direct');
  assert.equal(core.effective({ settings: { tone: 'savage' } }, null, NOW, null).tone, 'savage');
  // An unknown tone reads as Direct, never Savage.
  assert.equal(core.bootOut(undefined, null, null).title, "You're scrolling.");
  assert.equal(core.blockedCopy('focus', undefined, null, null).title, 'Not now.');
  assert.equal(core.warnLine(undefined, null).title, 'You’re scrolling.');
});

test('custom reminders are read from the app settings, cleaned', () => {
  assert.deepEqual(core.effective(null, null, NOW, null).customReminders, {});
  assert.deepEqual(withReminders(undefined).customReminders, {}, 'settings from before the field existed');
  assert.deepEqual(withReminders('nope').customReminders, {});
  assert.deepEqual(withReminders(['bootOut']).customReminders, {});
  assert.deepEqual(
    withReminders({ bootOut: '  Out you go.  ', shield: '   ', stuck: 42, someday: 'x', restOver: 'Up.' }).customReminders,
    { bootOut: 'Out you go.', restOver: 'Up.' });
});

test('short custom text becomes the boot-out title; the body stays built in', () => {
  const reminders = withReminders({ bootOut: 'Out of {task}.' }).customReminders;
  assert.deepEqual(core.bootOut('direct', 'Instagram', 'Deck', reminders),
    { title: 'Out of Deck.', body: 'Booted out of Instagram. Back to “Deck”.' });
  assert.deepEqual(core.bootOut('savage', null, null, reminders),
    { title: 'Out of your next task.', body: 'Doom-scroll detected. Booted out. Back to what matters.' });
});

test('long custom text becomes the body under the tone title', () => {
  const text = 'Close the feed, take a breath, and open the deck before you lose the thread.';
  assert.ok(text.length > core.REMINDER_TITLE_LIMIT);
  assert.deepEqual(core.bootOut('calm', 'X', 'Deck', { bootOut: text }),
    { title: "That's enough scrolling", body: text });
  // The limit is 40 characters, counted after {task} is filled in.
  const forty = 'a'.repeat(40);
  assert.equal(core.bootOut('direct', null, null, { bootOut: forty }).title, forty);
  assert.equal(core.bootOut('direct', null, null, { bootOut: forty + 'b' }).body, forty + 'b');
  const filled = core.bootOut('direct', null, 'Rewrite the onboarding emails for the beta', { bootOut: 'Back to {task}' });
  assert.equal(filled.title, "You're scrolling.");
  assert.equal(filled.body, 'Back to Rewrite the onboarding emails for the beta');
  // Emoji count as one character each, as in Swift.
  assert.equal(core.bootOut('direct', null, null, { bootOut: '👩‍💻'.repeat(40) }).title, '👩‍💻'.repeat(40));
});

test('{task} is filled in literally, in any case', () => {
  assert.equal(core.fillTask('Back to {task}.', '  Deck  '), 'Back to Deck.');
  assert.equal(core.fillTask('Back to {task}.', null), 'Back to your next task.');
  assert.equal(core.fillTask('Back to {task}.', '   '), 'Back to your next task.');
  assert.equal(core.fillTask('{Task} and {TASK}', 'Deck'), 'Deck and Deck');
  assert.equal(core.fillTask('Back to {task}', 'Pay $& $1 invoices'), 'Back to Pay $& $1 invoices');
});

test('without custom text every line is exactly the built-in one', () => {
  for (const tone of ['calm', 'direct', 'savage']) {
    const builtIn = core.bootOut(tone, 'Instagram', 'Deck');
    assert.deepEqual(core.bootOut(tone, 'Instagram', 'Deck', {}), builtIn);
    assert.deepEqual(core.bootOut(tone, 'Instagram', 'Deck', { bootOut: '  ' }), builtIn);
    assert.deepEqual(core.bootOut(tone, 'Instagram', 'Deck', withReminders({}).customReminders), builtIn);
  }
});

test('the blocked page uses bootOut for doom-scroll and shield for focus', () => {
  const reminders = withReminders({ bootOut: 'Feed closed. {task}.', shield: 'Not during {task}.' }).customReminders;
  const doom = core.blockedCopy('doomscroll', 'direct', 'Instagram', 'Deck', reminders);
  assert.deepEqual(doom, { eyebrow: 'Doom-scroll guard', title: 'Feed closed. Deck.', body: 'Booted out of Instagram. Back to “Deck”.' });
  const focus = core.blockedCopy('focus', 'savage', 'Instagram', 'Deck', reminders);
  assert.deepEqual(focus, { eyebrow: 'In focus', title: 'Not during Deck.', body: 'Instagram is closed while you focus. Back to “Deck”.' });
  // Other pages keep their own words.
  for (const reason of ['adult', 'shortform', 'cooldown']) {
    assert.deepEqual(core.blockedCopy(reason, 'direct', 'Instagram', 'Deck', reminders),
      core.blockedCopy(reason, 'direct', 'Instagram', 'Deck'), reason);
  }
});

test('moment keys and limits mirror CustomReminders.swift', () => {
  const enumBody = SWIFT.match(/enum ReminderMoment[^{]*\{([\s\S]*?)public var label/);
  assert.ok(enumBody, 'ReminderMoment not found');
  const cases = [...enumBody[1].matchAll(/case (\w+)/g)].map((m) => m[1]);
  assert.deepEqual([...core.REMINDER_MOMENTS], cases);

  const structBody = SWIFT.match(/struct CustomReminders[^{]*\{([\s\S]*?)public static let/);
  assert.ok(structBody, 'CustomReminders not found');
  const fields = [...structBody[1].matchAll(/public var (\w+): String\?/g)].map((m) => m[1]);
  assert.deepEqual([...core.REMINDER_MOMENTS], fields);

  assert.equal(Number(SWIFT.match(/titleLimit = (\d+)/)[1]), core.REMINDER_TITLE_LIMIT);
  assert.equal(SWIFT.match(/noTask = "([^"]+)"/)[1], core.NO_TASK);
  assert.match(SWIFT, /taskPlaceholder = "\{task\}"/);
});
