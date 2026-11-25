'use strict';

const { createServer, log } = require('./app');

const port = Number(process.env.PORT || 3000);
const server = createServer();

server.listen(port, () => log('info', 'server started', { port }));

// ECS sends SIGTERM on deploy/scale-in, then SIGKILL after stopTimeout.
// Stop accepting new connections and let in-flight requests finish.
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => {
    log('info', 'shutting down', { signal });
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 10_000).unref();
  });
}
