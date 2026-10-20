// content.js in a fake page: the route guard across SPA navigations, and how scrolling
// is counted.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadContent } from './content-harness.mjs';

const sum = (xs) => xs.reduce((a, b) => a + b, 0);

test('a wheel scroll is one stroke, not also a scroll-position stroke', async () => {
  // Instagram profile, messages-only off: a feed with the guard on.
  const page = loadContent('https://www.instagram.com/someone/', { tfPrefs: { instagramMessagesOnly: false } });
  await page.settle();
  // A trackpad fling: 12 wheel events of 100px, the page scrolling along with them.
  let top = 0;
  for (let i = 0; i < 12; i++) {
    page.dispatch('wheel', { deltaY: 100, deltaMode: 0 });
    top += 100;
    page.scrollTo(top);
    page.advance(16);
  }
  page.advance(400); // the burst ends
  assert.equal(page.strokes.length, 1, `strokes: ${page.strokes}`);
  assert.equal(sum(page.strokes), 1200 / 800);
});

test('scrolling an inner container with no gesture we saw still counts', async () => {
  const page = loadContent('https://www.instagram.com/someone/', { tfPrefs: { instagramMessagesOnly: false } });
  await page.settle();
  for (let top = 0; top <= 1600; top += 100) { page.scrollTo(top); page.advance(50); }
  assert.equal(sum(page.strokes), 2);
});

test('Instagram home in the SPA lands in the inbox once, and the inbox stays put', async () => {
  const page = loadContent('https://www.instagram.com/direct/inbox/');
  await page.settle();
  assert.deepEqual(page.replaced, []);
  page.navigate('/');
  page.advance(600);
  assert.deepEqual(page.replaced, ['https://www.instagram.com/direct/inbox/']);
});

test('work-only Facebook hides posts on pages, never in Messenger or search', async () => {
  const page = loadContent('https://www.facebook.com/messages/t/1');
  await page.settle();
  assert.ok(!page.classes().includes('tf-fb-feedless'));
  page.navigate('/acmebakery');
  page.advance(600);
  assert.ok(page.classes().includes('tf-fb-feedless'));
  page.navigate('/search/top/?q=acme');
  page.advance(600);
  assert.ok(!page.classes().includes('tf-fb-feedless'));
  page.navigate('/messages/t/2');
  page.advance(600);
  assert.ok(!page.classes().includes('tf-fb-feedless'));
  assert.deepEqual(page.replaced, []);
});

test('Business Suite never keeps the feedless class it starts with', async () => {
  const page = loadContent('https://business.facebook.com/latest/home');
  await page.settle();
  assert.ok(!page.classes().includes('tf-fb-feedless'));
});
