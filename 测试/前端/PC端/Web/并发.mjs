// Created by Jobs on 2026年11月18日，星期三.
// Run with Node.js; the DOM and transport fixtures never contact a real service.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import vm from 'node:vm';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(here, '../../../../代码/前端/PC端/Web');
const original = await fs.readFile(path.join(web, 'shop.js'), 'utf8');
const resources = Object.fromEntries(await Promise.all(['products.json', 'shop_strings.json'].map(async file => [file, JSON.parse(await fs.readFile(path.join(web, 'Assets', file), 'utf8'))])));
const product = resources['products.json'][0];
const order = (id = 'order10', version = 1) => ({ id, version, product_snapshot: structuredClone(product), amount_minor: product.price_minor, status: 'pending_payment', fulfillment_status: 'pending', editable: true });
const createBody = () => ({ product_id: product.id, product_version: product.version, requirements: 'Concurrency fixture', contact: 'fixture' });
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((ok, no) => { resolve = ok; reject = no; });
  return { promise, resolve, reject };
};

async function fixture() {
  const elements = new Map();
  const listeners = new Map();
  const timers = new Set();
  const calls = [];
  const element = selector => {
    if (!elements.has(selector)) elements.set(selector, {
      dataset: {}, files: [], open: false, disabled: false, hidden: true, textContent: '', innerHTML: '', closeCount: 0,
      querySelectorAll: () => [], setAttribute() {}, addEventListener() {},
      contains: () => false,
      showModal() { this.open = true; }, close() { this.open = false; this.closeCount++; },
    });
    return elements.get(selector);
  };
  const document = {
    documentElement: { lang: '', dataset: {} }, activeElement: null, hidden: false,
    querySelector: selector => selector.startsWith('#carousel') ? null : element(selector),
    querySelectorAll: () => [], addEventListener(name, handler) { listeners.set(name, handler); },
  };
  const context = vm.createContext({
    document, window: { addEventListener() {}, scrollTo() {} },
    location: { protocol: 'http:', origin: 'http://fixture.test', hash: '#orders' },
    localStorage: { getItem: () => null, setItem() {} },
    URL, AbortController, structuredClone, queueMicrotask, crypto: { randomUUID },
    matchMedia: () => ({ matches: true, addEventListener() {} }),
    Image: class {}, DOMParser: class {},
    FormData: class { constructor(target) { this.values = Object.entries(target.values ?? {}); } [Symbol.iterator]() { return this.values[Symbol.iterator](); } },
    setTimeout(fn, delay) { const timer = setTimeout(fn, delay); timers.add(timer); return timer; },
    clearTimeout(timer) { clearTimeout(timer); timers.delete(timer); },
    fetch(url, options) {
      if (String(url).startsWith('Assets/')) return Promise.resolve({ json: async () => structuredClone(resources[String(url).slice(7)]) });
      const response = deferred(); calls.push({ url: String(url), options, response }); return response.promise;
    },
  });
  // Only the evaluated test copy exposes state and omits automatic startup requests.
  const startup = 'render();refresh();';
  assert.ok(original.trimEnd().endsWith(startup), 'Update the fixture when the startup entry changes.');
  const source = original.slice(0, original.lastIndexOf(startup)) + 'render();\nreturn {state, request, mutate, refresh, logout, modal, settings, submit: data => submit(data)};';
  const app = await vm.runInContext('(async () => {\n' + source + '\n})()', context, { filename: 'shop-test-copy.js' });
  Object.assign(app.state, { user: { id: 'buyer', name: 'Fixture' }, token: 'fixture-token', live: true, source: 'live', orders: [order()] });
  const wait = async count => {
    for (let i = 0; i < 1000; i++) { if (calls.length >= count) return; await new Promise(resolve => setImmediate(resolve)); }
    throw new Error('Missing request ' + count + ', received ' + calls.map(c => c.url).join(', '));
  };
  const respond = (index, body, status = 200) => calls[index].response.resolve({ status, ok: status >= 200 && status < 300, json: async () => body });
  const finishRefresh = async (start, orders) => {
    await wait(start + 1); assert.ok(calls[start].url.endsWith('/shop-config')); respond(start, { demo_mode: true });
    await wait(start + 2); assert.ok(calls[start + 1].url.endsWith('/banners')); respond(start + 1, { banners: [] });
    await wait(start + 3); assert.ok(calls[start + 2].url.endsWith('/products')); respond(start + 2, { products: [product] });
    if (orders) { await wait(start + 4); assert.ok(calls[start + 3].url.endsWith('/shop-orders')); respond(start + 3, { orders }); }
  };
  return { app, calls, wait, respond, finishRefresh, element, listeners, dispose: () => { for (const timer of timers) clearTimeout(timer); } };
}

let passed = 0;
async function test(name, run) {
  const f = await fixture();
  try { await run(f); passed++; console.log('PASS ' + name); }
  finally { f.dispose(); }
}

await test('write intent freezes before the request and rejects concurrent submission', async f => {
  const first = f.app.mutate('/shop-orders', createBody());
  await f.wait(1);
  assert.ok(f.app.state.pending?.key);
  assert.equal(f.app.state.pending.key, f.calls[0].options.headers['Idempotency-Key']);
  await assert.rejects(f.app.mutate('/shop-orders', createBody()), error => error.status === 409);
  assert.equal(f.calls.length, 1);
  f.respond(0, { order: order() }); await first;
  assert.equal(f.app.state.pending, null);
});

await test('unknown write keeps its original key and refuses a different intent', async f => {
  const body = createBody();
  const first = f.app.mutate('/shop-orders', body);
  await f.wait(1); f.calls[0].response.reject(new TypeError('Fixture timeout'));
  await assert.rejects(first);
  const key = f.app.state.pending.key;
  await assert.rejects(f.app.mutate('/shop-orders', { ...body, requirements: 'Different intent' }));
  assert.equal(f.calls.length, 1);
  const retry = f.app.mutate('/shop-orders', body);
  await f.wait(2); assert.equal(f.calls[1].options.headers['Idempotency-Key'], key);
  f.respond(1, { order: order() }); await retry;
  assert.equal(f.app.state.pending, null);
});

await test('a newer refresh wins even when an older refresh finishes last', async f => {
  const old = f.app.refresh(); await f.wait(1);
  const latest = f.app.refresh(); await f.finishRefresh(1, [order('latest', 3)]); await latest;
  f.respond(0, { demo_mode: false }); await old;
  assert.equal(f.app.state.orders[0].id, 'latest');
});

await test('a refresh started before a write cannot replace its confirmed order', async f => {
  const old = f.app.refresh(); await f.wait(1);
  const write = f.app.mutate('/shop-orders/order10/actions', { action: 'pay', expected_version: 1 }); await f.wait(2);
  f.respond(1, { order: order('order10', 2) }); await write;
  f.respond(0, { demo_mode: true }); await old;
  assert.equal(f.app.state.orders[0].version, 2);
});

await test('a refresh started during a write cannot apply an older order version', async f => {
  const write = f.app.mutate('/shop-orders/order10/actions', { action: 'pay', expected_version: 1 }); await f.wait(1);
  const reading = f.app.refresh();
  await f.wait(2); f.respond(1, { demo_mode: true });
  await f.wait(3); f.respond(2, { banners: [] });
  await f.wait(4); f.respond(3, { products: [product] });
  await f.wait(5); f.respond(0, { order: order('order10', 2) }); await write;
  f.respond(4, { orders: [order('order10', 1)] }); await reading;
  assert.equal(f.app.state.orders[0].version, 2);
});

await test('logout drops late writes without unlocking a newer session write', async f => {
  const old = f.app.mutate('/shop-orders', createBody()); const oldFailure = assert.rejects(old);
  await f.wait(1); f.app.logout();
  Object.assign(f.app.state, { user: { id: 'new-buyer', name: 'New fixture' }, token: 'new-token', live: true, source: 'live' });
  const current = f.app.mutate('/shop-orders', createBody()); await f.wait(2);
  f.respond(0, { order: order('old-account') }); await oldFailure;
  await assert.rejects(f.app.mutate('/shop-orders', createBody()), error => error.status === 409);
  f.respond(1, { order: order('new-account') }); await current;
  assert.equal(f.app.state.orders.length, 1); assert.equal(f.app.state.orders[0].id, 'new-account');
});

await test('changing the service ignores the old response and clears the old intent', async f => {
  const old = f.app.mutate('/shop-orders', createBody()); const oldFailure = assert.rejects(old);
  await f.wait(1); f.app.settings();
  const setting = f.app.submit({ api: 'http://next-fixture.test/api/v1', timeout: '1500', language: 'en', theme: 'dark' });
  await f.wait(2); assert.ok(f.calls[1].url.startsWith('http://next-fixture.test/'));
  f.respond(0, { order: order('old-service') }); await oldFailure;
  await f.finishRefresh(1); await setting;
  assert.equal(f.app.state.user, null); assert.equal(f.app.state.pending, null); assert.equal(f.app.state.orders.length, 0);
});

for (const fails of [false, true]) await test('a replaced form survives the old form ' + (fails ? 'failure' : 'success'), async f => {
  const oldResult = deferred();
  f.app.modal('buy', '', () => oldResult.promise);
  const submission = f.element('#form').onsubmit({ preventDefault() {}, target: { values: {} } });
  assert.equal(f.element('#submit').disabled, true);
  f.app.modal('settings', '', async () => true);
  assert.equal(f.element('#submit').disabled, false);
  if (fails) oldResult.reject(new Error('Old form error')); else oldResult.resolve(true);
  await submission;
  assert.equal(f.element('#modal').open, true); assert.equal(f.element('#modal').closeCount, 0);
  assert.equal(f.element('#form-error').textContent, ''); assert.equal(f.element('#submit').disabled, false);
});

await test('401 revokes the session even when its body is malformed JSON', async f => {
  const read = f.app.request('/shop-orders'); const failure = assert.rejects(read);
  await f.wait(1);
  f.calls[0].response.resolve({ status: 401, ok: false, json: async () => { throw new Error('Malformed fixture JSON'); } });
  await failure;
  assert.equal(f.app.state.user, null); assert.equal(f.app.state.token, ''); assert.equal(f.app.state.orders.length, 0); assert.equal(f.app.state.pending, null);
});

await test('an action rejects another order whose ID merely shares its prefix', async f => {
  const write = f.app.mutate('/shop-orders/order10/actions', { action: 'pay', expected_version: 1 });
  const failure = assert.rejects(write);
  await f.wait(1); f.respond(0, { order: order('order1', 2) }); await failure;
  assert.ok(f.app.state.pending); assert.equal(f.app.state.orders[0].id, 'order10');
});

await test('an action requires the server to confirm a version increase', async f => {
  const write = f.app.mutate('/shop-orders/order10/actions', { action: 'pay', expected_version: 1 });
  const failure = assert.rejects(write);
  await f.wait(1); f.respond(0, { order: order('order10', 1) }); await failure;
  assert.ok(f.app.state.pending); assert.equal(f.app.state.orders[0].version, 1);
});

await test('a new order confirms the product selected in the original request', async f => {
  const write = f.app.mutate('/shop-orders', createBody());
  const failure = assert.rejects(write);
  await f.wait(1);
  const wrongProduct = order(); wrongProduct.product_snapshot.id = 'another-product';
  f.respond(0, { order: wrongProduct }); await failure;
  assert.ok(f.app.state.pending);
});

await test('profile updates use PUT and keep the authenticated user ID', async f => {
  await f.listeners.get('click')({ target: { closest: () => ({ dataset: { action: 'profile' } }) } });
  const update = f.app.submit({ username: 'New fixture name' });
  await f.wait(1);
  assert.ok(f.calls[0].url.endsWith('/auth/profile'));
  assert.equal(f.calls[0].options.method, 'PUT');
  assert.equal(JSON.parse(f.calls[0].options.body).username, 'New fixture name');
  f.respond(0, { user: { id: 'buyer', name: 'New fixture name', username: 'New fixture name' } });
  await update;
  assert.equal(f.app.state.user.id, 'buyer'); assert.equal(f.app.state.user.name, 'New fixture name');
});

console.log(`PASS ${passed} Web concurrency and response-validation scenarios; no network or persistent browser state used.`);
