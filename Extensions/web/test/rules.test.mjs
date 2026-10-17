// The DNR rulesets and manifest are valid, generated, and in step with Blocklist.swift.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { createRequire } from 'node:module';
import { buildRules, serialize, ROOT } from './generate-rules.mjs';

const require = createRequire(import.meta.url);
const core = require('../core.js');

const REPO = join(ROOT, '..', '..');
const BLOCKLIST = join(REPO, 'Packages/TrueFocusKit/Sources/TrueFocusKit/Blocklist.swift');
const manifest = JSON.parse(readFileSync(join(ROOT, 'manifest.json'), 'utf8'));

function swiftArray(source, name) {
  const match = source.match(new RegExp(`static let ${name}: \\[String\\] = \\[([\\s\\S]*?)\\]`));
  assert.ok(match, `${name} not found in Blocklist.swift`);
  return [...match[1].matchAll(/"([^"]*)"/g)].map((m) => m[1]);
}

test('committed rulesets equal the generator output', () => {
  for (const [file, rules] of Object.entries(buildRules())) {
    const onDisk = readFileSync(join(ROOT, file), 'utf8');
    assert.equal(onDisk, serialize(rules), `${file} is stale — run: node test/generate-rules.mjs`);
  }
});

test('every ruleset in the manifest is valid', () => {
  const resources = manifest.declarative_net_request.rule_resources;
  const ids = resources.map((r) => r.id);
  assert.equal(new Set(ids).size, ids.length, 'ruleset ids must be unique');
  for (const resource of resources) {
    const rules = JSON.parse(readFileSync(join(ROOT, resource.path), 'utf8'));
    assert.ok(Array.isArray(rules) && rules.length > 0, resource.path);
    const ruleIds = rules.map((r) => r.id);
    assert.equal(new Set(ruleIds).size, ruleIds.length, `${resource.path}: rule ids must be unique`);
    for (const rule of rules) {
      assert.ok(Number.isInteger(rule.id) && rule.id >= 1, `${resource.path}: bad id ${rule.id}`);
      assert.ok(Number.isInteger(rule.priority) && rule.priority >= 1);
      assert.ok(['block', 'redirect', 'allow', 'upgradeScheme', 'allowAllRequests', 'modifyHeaders'].includes(rule.action.type));
      const c = rule.condition;
      assert.ok(Array.isArray(c.resourceTypes) && c.resourceTypes.length, 'resourceTypes required');
      assert.ok(!(c.urlFilter && c.regexFilter), 'urlFilter and regexFilter are exclusive');
      if (c.regexFilter) assert.doesNotThrow(() => new RegExp(c.regexFilter));
      if (rule.action.type === 'redirect') {
        const r = rule.action.redirect;
        assert.ok(r.extensionPath || r.transform || r.url || r.regexSubstitution);
        if (r.extensionPath) {
          assert.ok(r.extensionPath.startsWith('/'));
          const file = r.extensionPath.slice(1).split(/[?#]/)[0];
          assert.ok(existsSync(join(ROOT, file)), `redirect target ${file} missing`);
          const war = manifest.web_accessible_resources.flatMap((w) => w.resources);
          assert.ok(war.includes(file), `${file} must be web-accessible`);
        }
      }
    }
  }
});

test('adult lists equal Blocklist.swift', () => {
  const swift = readFileSync(BLOCKLIST, 'utf8');
  const domains = swiftArray(swift, 'adultDomains');
  const keywords = swiftArray(swift, 'adultKeywords');
  assert.deepEqual([...core.ADULT_DOMAINS], domains);
  assert.deepEqual([...core.ADULT_KEYWORDS], keywords);
  const adult = JSON.parse(readFileSync(join(ROOT, 'rules_adult.json'), 'utf8'));
  for (const rule of adult) assert.deepEqual(new Set(rule.condition.requestDomains), new Set(domains));
  const kw = JSON.parse(readFileSync(join(ROOT, 'rules_adult_keywords.json'), 'utf8'));
  for (const keyword of keywords) {
    assert.ok(kw.some((r) => r.condition.regexFilter.endsWith(keyword)), `keyword ${keyword} missing`);
  }
});

test('feed sites equal Blocklist.feedSites', () => {
  const swift = readFileSync(BLOCKLIST, 'utf8');
  const block = swift.match(/static let feedSites: \[FeedSite\] = \[([\s\S]*?)\n    \]/)[1];
  const entries = block.split(/FeedSite\(/).slice(1);
  assert.equal(entries.length, core.FEED_SITES.length);
  const list = (entry, label) => {
    const m = entry.match(new RegExp(`${label}: \\[([^\\]]*)\\]`));
    return m ? [...m[1].matchAll(/"([^"]*)"/g)].map((x) => x[1]) : [];
  };
  entries.forEach((entry, index) => {
    const site = core.FEED_SITES[index];
    assert.equal(entry.match(/name: "([^"]+)"/)[1], site.name);
    assert.deepEqual(list(entry, 'hosts'), site.hosts, `${site.name} hosts`);
    assert.deepEqual(list(entry, 'shortFormPaths'), site.shortFormPaths, `${site.name} shortFormPaths`);
    assert.deepEqual(list(entry, 'safePaths'), site.safePaths, `${site.name} safePaths`);
    const respond = entry.match(/respondPath: "([^"]+)"/);
    assert.equal(respond ? respond[1] : null, site.respondPath, `${site.name} respondPath`);
    assert.equal(/allShortForm: true/.test(entry), site.allShortForm, `${site.name} allShortForm`);
  });
});

test('content scripts run on every feed host', () => {
  const matches = manifest.content_scripts[0].matches;
  for (const site of core.FEED_SITES) {
    for (const host of site.hosts) assert.ok(matches.includes(`*://*.${host}/*`), `${host} not matched`);
  }
});

test('every file the manifest references exists at the root', () => {
  const files = new Set([
    manifest.background.service_worker,
    manifest.action.default_popup,
    ...manifest.content_scripts.flatMap((c) => [...c.js, ...(c.css || [])]),
    ...manifest.web_accessible_resources.flatMap((w) => w.resources),
    ...manifest.declarative_net_request.rule_resources.map((r) => r.path),
  ]);
  for (const file of files) {
    assert.ok(!file.includes('/'), `${file}: keep the extension flat`);
    assert.ok(existsSync(join(ROOT, file)), `${file} missing`);
  }
  // Icons are generated separately; only check they're named consistently.
  for (const icon of [...Object.values(manifest.icons), ...Object.values(manifest.action.default_icon)]) {
    assert.match(icon, /^(icon|toolbar)-\d+\.png$/);
  }
});
