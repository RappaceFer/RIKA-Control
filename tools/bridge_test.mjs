// Mock tests: no connection to FIRENET or a real stove.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';
const dart = fs.readFileSync(new URL('../lib/firenet_bridge.dart', import.meta.url), 'utf8');
const script = dart.match(/controller\.runJavaScript\('''([\s\S]*?)'''\)/)[1];
const discovery = dart.match(/runJavaScriptReturningResult\(r'''([\s\S]*?)'''\)/)[1];
async function run(cfg, fetcher, host = 'www.rika-firenet.com') {
  const messages = [];
  await vm.runInNewContext(script.replace('$config', JSON.stringify(cfg)), {
    AbortController, setTimeout, clearTimeout,
    location: {protocol: 'https:', hostname: host}, fetch: fetcher,
    RikaBridgeV5: {postMessage: value => messages.push(JSON.parse(value))},
  });
  return messages;
}
const cfg = {id: 'nonce-test', path: '/api/client/12345678/controls', method: 'POST',
  body: {revision: 100, targetTemperature: '22.2', operatingMode: 2, onOff: false, debug0: 0}};
test('POST sends JSON exactly once, decimal preserved, same-origin cookies', async () => {
  let count = 0;
  const messages = await run(cfg, async (path, options) => {
    count++;
    assert.equal(path, cfg.path); assert.equal(options.method, 'POST');
    assert.equal(options.credentials, 'same-origin');
    assert.equal(options.headers['Content-Type'], 'application/json');
    assert.deepEqual(JSON.parse(options.body), cfg.body);
    return {headers: {get: () => null}, status: 200, text: async () => 'OK'};
  });
  assert.equal(count, 1);
  assert.deepEqual(messages, [{id: 'nonce-test', status: 200, body: 'OK', retryAfter: null}]);
});
test('GET does not attach a command body', async () => {
  await run({...cfg, method: 'GET', path: '/api/client/12345678/status', body: null}, async (_, options) => {
    assert.equal(options.body, undefined); assert.equal(options.cache, 'no-store');
    return {headers: {get: () => null}, status: 200, text: async () => '{}'};
  });
});
test('wrong origin performs no network request', async () => {
  let count = 0;
  const result = await run(cfg, async () => { count++; }, 'rika-firenet.com.evil.test');
  assert.equal(count, 0); assert.equal(result[0].error, 'network');
});
test('HTTP rejection preserves status instead of fabricating OK', async () => {
  const result = await run(cfg, async () => ({headers: {get: () => null}, status: 422, text: async () => 'invalid temperature'}));
  assert.equal(result[0].status, 422); assert.equal(result[0].body, 'invalid temperature');
});
test('network exception is not retried', async () => {
  let count = 0;
  const result = await run(cfg, async () => { count++; throw new Error('offline'); });
  assert.equal(count, 1); assert.equal(result[0].error, 'network');
});
function discover(pathname, paths) {
  return JSON.parse(vm.runInNewContext(discovery, {
    location: {pathname}, document: {querySelectorAll: () => paths.map(path => ({pathname: path}))},
  }));
}
test('selected stove page keeps leading zeroes', () => {
  assert.equal(discover('/web/stove/00123456', []), '00123456');
});
test('single distinct stove is discovered', () => {
  assert.equal(discover('/web/summary', ['/web/stove/12345678', '/web/stove/12345678']), '12345678');
});
test('multiple stoves require explicit selection', () => {
  assert.equal(discover('/web/summary', ['/web/stove/12345678', '/web/stove/99999999']), null);
});
test('429 forwards Retry-After, without retrying the command', async () => {
  let count = 0;
  const result = await run(cfg, async () => {
    count++;
    return {status: 429, headers: {get: name => name === 'Retry-After' ? '120' : null}, text: async () => 'slow down'};
  });
  assert.equal(count, 1); assert.equal(result[0].status, 429); assert.equal(result[0].retryAfter, '120');
});
