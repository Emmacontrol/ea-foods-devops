'use strict';

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { createServer } = require('../src/app');

let server;
let baseUrl;
const logged = [];
const realWrite = process.stdout.write.bind(process.stdout);

before(async () => {
  // Capture log lines written by the app (and still let the test runner write).
  process.stdout.write = (chunk, ...rest) => {
    if (String(chunk).includes('"service":"notify-svc"')) logged.push(JSON.parse(chunk));
    return realWrite(chunk, ...rest);
  };
  server = createServer();
  await new Promise((resolve) => server.listen(0, resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(() => {
  process.stdout.write = realWrite;
  server.close();
});

test('GET /health returns ok', async () => {
  const res = await fetch(`${baseUrl}/health`);
  assert.equal(res.status, 200);
  assert.equal((await res.json()).status, 'ok');
});

test('GET /notify returns sent', async () => {
  const res = await fetch(`${baseUrl}/notify`);
  assert.equal(res.status, 200);
  assert.equal((await res.json()).status, 'sent');
});

test('unknown path is 404, non-GET is 405', async () => {
  assert.equal((await fetch(`${baseUrl}/nope`)).status, 404);
  assert.equal((await fetch(`${baseUrl}/notify`, { method: 'POST' })).status, 405);
});

test('every request is logged as one JSON line', async () => {
  const before = logged.length;
  await fetch(`${baseUrl}/health`);
  const entry = logged.at(-1);
  assert.equal(logged.length, before + 1);
  assert.deepEqual([entry.path, entry.status, entry.message], ['/health', 200, 'request handled']);
});
