'use strict';

// Container HEALTHCHECK for an image with no shell or curl (distroless).
const http = require('node:http');

const req = http.get(`http://127.0.0.1:${process.env.PORT || 3000}/health`, { timeout: 2000 }, (res) => {
  process.exit(res.statusCode === 200 ? 0 : 1);
});
req.on('error', () => process.exit(1));
req.on('timeout', () => req.destroy());
