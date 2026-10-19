// Runs content.js in a tiny fake page (no browser), so its event wiring can be tested.
//
//   const page = loadContent('https://www.instagram.com/someone/', { state, prefs });
//   page.dispatch('wheel', { deltaY: 120 });
//   page.advance(300);           // runs due timers
//   page.strokes                 // weights handed to the doom-scroll detector

import vm from 'node:vm';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { ROOT } from './generate-rules.mjs';

const CORE = readFileSync(join(ROOT, 'core.js'), 'utf8');
const CONTENT = readFileSync(join(ROOT, 'content.js'), 'utf8');

class FakeClassList {
  constructor() { this.set = new Set(); }
  add(c) { this.set.add(c); }
  remove(c) { this.set.delete(c); }
  contains(c) { return this.set.has(c); }
  toggle(c, force) {
    const on = force === undefined ? !this.set.has(c) : !!force;
    if (on) this.set.add(c); else this.set.delete(c);
    return on;
  }
}

class FakeElement {
  constructor(tag) {
    this.tagName = String(tag || 'div').toUpperCase();
    this.children = [];
    this.style = {};
    this.classList = new FakeClassList();
    this.attributes = {};
    this.listeners = {};
    this.textContent = '';
    this.scrollTop = 0;
    this.clientHeight = 800;
    this._html = '';
  }
  get className() { return [...this.classList.set].join(' '); }
  set className(v) { this.classList = new FakeClassList(); String(v).split(/\s+/).filter(Boolean).forEach((c) => this.classList.add(c)); }
  set innerHTML(v) { this._html = String(v); }
  get innerHTML() { return this._html; }
  setAttribute(k, v) { this.attributes[k] = String(v); }
  getAttribute(k) { return this.attributes[k] ?? null; }
  appendChild(child) { this.children.push(child); child.parentNode = this; return child; }
  addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); }
  attachShadow() { this.shadowRoot = new FakeElement('#shadow'); return this.shadowRoot; }
  focus() {}
  querySelector(selector) {
    const cls = selector.startsWith('.') ? selector.slice(1) : null;
    const tag = cls ? null : selector.toUpperCase();
    const walk = (node) => {
      for (const child of node.children) {
        if ((cls && child.classList.contains(cls)) || (tag && child.tagName === tag)) return child;
        const found = walk(child);
        if (found) return found;
      }
      return null;
    };
    const found = walk(this);
    if (found) return found;
    // Markup set through innerHTML: hand out the element it describes on first ask.
    if ((cls && this._html.includes(`class="${cls}"`)) || (tag && this._html.toUpperCase().includes(`<${tag}`))) {
      const el = new FakeElement(tag || 'div');
      if (cls) el.classList.add(cls);
      return this.appendChild(el);
    }
    return null;
  }
  querySelectorAll() { return []; }
}

/**
 * Loads core.js + content.js for `url`. `storage` is what storage.local holds.
 * Returns controls for events, time and navigation, and what the script did.
 */
export function loadContent(url, storage = {}) {
  let clock = Date.UTC(2026, 9, 19, 9, 0, 0);
  const timers = [];
  let timerId = 0;
  const schedule = (fn, ms, repeat) => {
    const id = ++timerId;
    timers.push({ id, fn, at: clock + Math.max(0, ms || 0), every: repeat ? Math.max(1, ms || 0) : 0 });
    return id;
  };
  const clear = (id) => {
    const i = timers.findIndex((t) => t.id === id);
    if (i !== -1) timers.splice(i, 1);
  };

  const RealDate = Date;
  class FakeDate extends RealDate {
    constructor(...args) { super(...(args.length ? args : [clock])); }
    static now() { return clock; }
  }

  const docListeners = {};
  const winListeners = {};
  const html = new FakeElement('html');
  const body = new FakeElement('body');
  html.appendChild(body);
  const elementsById = new Map();
  const replaced = [];
  const messages = [];
  const storageListeners = [];
  const data = JSON.parse(JSON.stringify(storage));

  let current = new URL(url);
  const location = {
    get href() { return current.href; },
    get hostname() { return current.hostname; },
    get pathname() { return current.pathname; },
    get origin() { return current.origin; },
    replace(next) { replaced.push(String(next)); },
  };

  const document = {
    documentElement: html,
    body,
    get scrollingElement() { return html; },
    visibilityState: 'visible',
    addEventListener(type, fn) { (docListeners[type] ||= []).push(fn); },
    createElement(tag) {
      const el = new FakeElement(tag);
      return el;
    },
    createTextNode(text) { const el = new FakeElement('#text'); el.textContent = text; return el; },
    getElementById(id) { return elementsById.get(id) || null; },
  };
  // mount() looks overlays up by id after appending them to the body.
  const append = body.appendChild.bind(body);
  body.appendChild = (child) => { if (child.id) elementsById.set(child.id, child); return append(child); };
  html.appendChild = (child) => { if (child.id) elementsById.set(child.id, child); return FakeElement.prototype.appendChild.call(html, child); };

  const api = {
    storage: {
      local: {
        get(keys) {
          const list = Array.isArray(keys) ? keys : [keys];
          const out = {};
          for (const k of list) if (k in data) out[k] = JSON.parse(JSON.stringify(data[k]));
          return Promise.resolve(out);
        },
        set(values) {
          const changes = {};
          for (const [k, v] of Object.entries(values)) {
            changes[k] = { oldValue: data[k], newValue: v };
            data[k] = v;
          }
          storageListeners.forEach((fn) => fn(changes, 'local'));
          return Promise.resolve();
        },
      },
      onChanged: { addListener(fn) { storageListeners.push(fn); } },
    },
    runtime: {
      sendMessage(message) { messages.push(message); return Promise.resolve(null); },
      getURL(path) { return 'chrome-extension://tf/' + path; },
    },
  };

  const sandbox = {
    Date: FakeDate,
    URL,
    URLSearchParams,
    Promise,
    WeakMap,
    console,
    document,
    location,
    history: { length: 1, back() {} },
    chrome: api,
    innerHeight: 800,
    setTimeout: (fn, ms) => schedule(fn, ms, false),
    clearTimeout: clear,
    setInterval: (fn, ms) => schedule(fn, ms, true),
    clearInterval: clear,
    requestAnimationFrame: (fn) => schedule(fn, 16, false),
    addEventListener(type, fn) { (winListeners[type] ||= []).push(fn); },
  };
  sandbox.window = sandbox;
  sandbox.top = sandbox;
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(CORE, sandbox, { filename: 'core.js' });

  // Watch what the detector is fed.
  const strokes = [];
  const proto = sandbox.TFCore.DoomScrollDetector.prototype;
  const realStroke = proto.stroke;
  proto.stroke = function (time, screens) {
    strokes.push(screens === undefined ? 1 : screens);
    return realStroke.call(this, time, screens);
  };

  vm.runInContext(CONTENT, sandbox, { filename: 'content.js' });

  const page = {
    strokes,
    replaced,
    messages,
    storage: data,
    html,
    get now() { return clock; },
    /** Lets pending promise callbacks (storage reads) run. */
    async settle() { for (let i = 0; i < 5; i++) await Promise.resolve(); },
    /** Moves the clock forward, running every timer that comes due, in order. */
    advance(ms) {
      const end = clock + ms;
      for (;;) {
        timers.sort((a, b) => a.at - b.at || a.id - b.id);
        const next = timers[0];
        if (!next || next.at > end) break;
        clock = next.at;
        if (next.every) next.at += next.every; else timers.shift();
        next.fn();
      }
      clock = end;
    },
    /** Fires a document-level event (capture listeners run in registration order). */
    dispatch(type, init = {}) {
      const event = Object.assign({ type, target: document, stopPropagation() {}, preventDefault() {} }, init);
      (docListeners[type] || []).forEach((fn) => fn(event));
    },
    /** Scrolls the page to `top` and fires the scroll event. */
    scrollTo(top) {
      html.scrollTop = top;
      page.dispatch('scroll', { target: document });
    },
    /** An in-page (SPA) navigation: the URL changes without a reload. */
    navigate(next) {
      current = new URL(next, current);
    },
    classes() { return [...html.classList.set]; },
  };
  return page;
}
