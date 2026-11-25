'use strict';

const http = require('node:http');

const SERVICE = 'notify-svc';
const VERSION = process.env.APP_VERSION || 'dev';

// One JSON object per line on stdout: CloudWatch Logs Insights can query fields directly.
function log(level, message, fields = {}) {
  process.stdout.write(
    `${JSON.stringify({ time: new Date().toISOString(), level, service: SERVICE, message, ...fields })}\n`,
  );
}

function route(method, pathname) {
  if (method !== 'GET') return [405, { error: 'method not allowed' }];
  if (pathname === '/health') return [200, { status: 'ok', service: SERVICE, version: VERSION }];
  // The ALB forwards /notify and /notify/* unchanged.
  if (pathname === '/notify' || pathname === '/notify/') {
    return [200, { status: 'sent', message: 'Notification dispatched (stub)' }];
  }
  return [404, { error: 'not found' }];
}

function createServer() {
  return http.createServer((req, res) => {
    const started = process.hrtime.bigint();
    const { pathname } = new URL(req.url, 'http://localhost');
    const [status, body] = route(req.method, pathname);

    // x-app-version lets the deploy smoke test confirm which release is serving traffic.
    res.writeHead(status, { 'content-type': 'application/json', 'x-app-version': VERSION });
    res.end(JSON.stringify(body));

    // Requirement: log a message for every request.
    log('info', 'request handled', {
      method: req.method,
      path: pathname,
      status,
      duration_ms: Number(process.hrtime.bigint() - started) / 1e6,
    });
  });
}

module.exports = { createServer, log };
