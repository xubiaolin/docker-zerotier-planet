'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');

const MOON_FILE = /^[0-9a-f]{16}\.moon$/;

function secureEqual(actual, expected) {
  const actualDigest = crypto.createHash('sha256').update(actual || '').digest();
  const expectedDigest = crypto.createHash('sha256').update(expected).digest();
  return crypto.timingSafeEqual(actualDigest, expectedDigest);
}

function bearerToken(header) {
  if (!header || !header.startsWith('Bearer ')) return '';
  return header.slice('Bearer '.length);
}

function isLoopback(address) {
  return address === '127.0.0.1' || address === '::1' || address === '::ffff:127.0.0.1';
}

function allowedFile(pathname) {
  const name = pathname.replace(/^\/+/, '');
  if (name === 'planet' || MOON_FILE.test(name)) return name;
  return null;
}

function createFileServer(options = {}) {
  const distPath = options.distPath || process.env.DIST_PATH || '/app/dist';
  const keyPath = options.keyPath || path.join(process.env.CONFIG_PATH || '/app/config', 'file_server.key');
  const secret = options.secret || fs.readFileSync(keyPath, 'utf8').trim();

  return http.createServer((request, response) => {
    const requestUrl = new URL(request.url, 'http://localhost');

    if (requestUrl.pathname === '/healthz') {
      if (!isLoopback(request.socket.remoteAddress)) {
        response.writeHead(404).end();
        return;
      }
      response.writeHead(200, { 'content-type': 'text/plain' }).end('ok');
      return;
    }

    if (request.method !== 'GET' && request.method !== 'HEAD') {
      response.writeHead(405, { allow: 'GET, HEAD', 'content-type': 'text/plain' }).end('Method Not Allowed');
      return;
    }

    const suppliedKey = bearerToken(request.headers.authorization) || requestUrl.searchParams.get('key') || '';
    if (!secureEqual(suppliedKey, secret)) {
      response.writeHead(401, { 'content-type': 'text/plain', 'www-authenticate': 'Bearer' }).end('Unauthorized');
      return;
    }

    const fileName = allowedFile(requestUrl.pathname);
    if (!fileName) {
      response.writeHead(404, { 'content-type': 'text/plain' }).end('Not Found');
      return;
    }

    const filePath = path.join(distPath, fileName);
    const flags = fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW;
    fs.open(filePath, flags, (error, descriptor) => {
      if (error) {
        const status = error.code === 'ENOENT' || error.code === 'ELOOP' ? 404 : 500;
        response.writeHead(status, { 'content-type': 'text/plain' }).end(status === 500 ? 'Server Error' : 'Not Found');
        return;
      }

      fs.fstat(descriptor, (statError, stat) => {
        if (statError || !stat.isFile()) {
          fs.close(descriptor, () => {});
          const status = statError ? 500 : 404;
          response.writeHead(status, { 'content-type': 'text/plain' }).end(status === 500 ? 'Server Error' : 'Not Found');
          return;
        }

        response.writeHead(200, {
          'cache-control': 'private, no-store',
          'content-disposition': `attachment; filename="${fileName}"`,
          'content-length': stat.size,
          'content-type': 'application/octet-stream',
          'x-content-type-options': 'nosniff',
        });
        if (request.method === 'HEAD') {
          fs.close(descriptor, () => {});
          response.end();
          return;
        }
        fs.createReadStream(filePath, { autoClose: true, fd: descriptor }).on('error', () => response.destroy()).pipe(response);
      });
    });
  });
}

function start() {
  const port = Number(process.env.FILE_SERVER_PORT || 3000);
  const server = createFileServer();
  server.listen(port, '0.0.0.0', () => {
    process.stdout.write(`${new Date().toISOString()} component=file-server level=info message=listening port=${port}\n`);
  });

  const shutdown = () => server.close(() => process.exit(0));
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

if (require.main === module) start();

module.exports = { allowedFile, createFileServer, secureEqual };
