// Builds the declarativeNetRequest rulesets from core.js's lists.
//
//   node test/generate-rules.mjs        # rewrites rules_*.json at the extension root
//
// test/rules.test.mjs checks the committed files equal what this produces.

import { createRequire } from 'node:module';
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const require = createRequire(import.meta.url);
const core = require('../core.js');

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

const WALL = '/wall.html';
const SHORTS = '/shorts.html';

const GOOGLE_DOMAINS = [
  'google.com', 'google.co.uk', 'google.ca', 'google.com.au', 'google.de', 'google.fr', 'google.es',
  'google.it', 'google.nl', 'google.co.jp', 'google.co.kr', 'google.com.br', 'google.co.in', 'google.com.mx',
];

// The adult filter outranks everything else, "Always allowed" sites included (their
// dynamic allow rule is priority 2, see core.allowRules).
const ADULT_PRIORITY = 3;

function redirectTo(extensionPath) {
  return { type: 'redirect', redirect: { extensionPath } };
}

export function buildRules() {
  // Adult domains: one redirect rule for pages, one block rule for embeds.
  const adult = [
    {
      id: 1,
      priority: ADULT_PRIORITY,
      action: redirectTo(WALL),
      condition: { requestDomains: [...core.ADULT_DOMAINS], resourceTypes: ['main_frame'] },
    },
    {
      id: 2,
      priority: ADULT_PRIORITY,
      action: { type: 'block' },
      condition: { requestDomains: [...core.ADULT_DOMAINS], resourceTypes: ['sub_frame'] },
    },
  ];

  // Keywords anywhere in the hostname. Regex rules live in their own ruleset so an engine
  // that rejects them doesn't take the domain list down with it.
  const adultKeywords = [];
  core.ADULT_KEYWORDS.forEach((keyword, index) => {
    const regexFilter = `^https?://[^/?#]*${keyword}`;
    adultKeywords.push({
      id: index + 1,
      priority: ADULT_PRIORITY,
      action: redirectTo(WALL),
      condition: { regexFilter, isUrlFilterCaseSensitive: false, resourceTypes: ['main_frame'] },
    });
    adultKeywords.push({
      id: index + 101,
      priority: ADULT_PRIORITY,
      action: { type: 'block' },
      condition: { regexFilter, isUrlFilterCaseSensitive: false, resourceTypes: ['sub_frame'] },
    });
  });

  // Short-form video. Top-level navigations only; the content script covers SPA routes.
  const shortformFilters = [];
  for (const site of core.FEED_SITES) {
    if (site.allShortForm) continue;
    for (const host of site.hosts) {
      for (const path of site.shortFormPaths) shortformFilters.push(`||${host}${path}^`);
    }
  }
  const shortform = shortformFilters.map((urlFilter, index) => ({
    id: index + 1,
    priority: 1,
    action: redirectTo(SHORTS),
    condition: { urlFilter, resourceTypes: ['main_frame'] },
  }));
  // Pages under a wall that stay open: Instagram search, a single Facebook Watch video.
  let openId = 50;
  for (const site of core.FEED_SITES) {
    for (const host of site.hosts) {
      for (const path of site.shortFormOpen || []) {
        shortform.push({
          id: openId++,
          priority: 2,
          action: { type: 'allow' },
          condition: { urlFilter: `||${host}${path}`, resourceTypes: ['main_frame'] },
        });
      }
    }
  }
  // Whole-site short-form (TikTok), with its safe paths punched back out at higher priority.
  let nextId = 100;
  for (const site of core.FEED_SITES) {
    if (!site.allShortForm) continue;
    for (const host of site.hosts) {
      shortform.push({
        id: nextId++,
        priority: 1,
        action: redirectTo(SHORTS),
        condition: { urlFilter: `||${host}^`, resourceTypes: ['main_frame'] },
      });
      for (const path of site.safePaths) {
        shortform.push({
          id: nextId++,
          priority: 2,
          action: { type: 'allow' },
          condition: { urlFilter: `||${host}${path}`, resourceTypes: ['main_frame'] },
        });
      }
    }
    // Its work tools (TikTok Ads Manager…) live on subdomains the wall would catch.
    for (const host of site.workHosts || []) {
      shortform.push({
        id: nextId++,
        priority: 2,
        action: { type: 'allow' },
        condition: { urlFilter: `||${host}^`, resourceTypes: ['main_frame'] },
      });
    }
  }

  // SafeSearch everywhere. Kept separate: queryTransform support varies between engines.
  const safeSearch = [
    {
      id: 1,
      priority: ADULT_PRIORITY,
      action: { type: 'redirect', redirect: { transform: { queryTransform: { addOrReplaceParams: [{ key: 'safe', value: 'active' }] } } } },
      condition: { requestDomains: GOOGLE_DOMAINS, urlFilter: '/search?', resourceTypes: ['main_frame'] },
    },
    {
      id: 2,
      priority: ADULT_PRIORITY,
      action: { type: 'redirect', redirect: { transform: { queryTransform: { addOrReplaceParams: [{ key: 'adlt', value: 'strict' }] } } } },
      condition: { requestDomains: ['bing.com'], urlFilter: '/search?', resourceTypes: ['main_frame'] },
    },
    {
      id: 3,
      priority: ADULT_PRIORITY,
      action: { type: 'redirect', redirect: { transform: { queryTransform: { addOrReplaceParams: [{ key: 'kp', value: '1' }] } } } },
      condition: { requestDomains: ['duckduckgo.com'], urlFilter: 'q=', resourceTypes: ['main_frame'] },
    },
  ];

  return {
    'rules_adult.json': adult,
    'rules_adult_keywords.json': adultKeywords,
    'rules_shortform.json': shortform,
    'rules_safesearch.json': safeSearch,
  };
}

export function serialize(rules) {
  return JSON.stringify(rules, null, 2) + '\n';
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  for (const [file, rules] of Object.entries(buildRules())) {
    writeFileSync(join(ROOT, file), serialize(rules));
    console.log(`wrote ${file} (${rules.length} rules)`);
  }
}
