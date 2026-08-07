'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { allowedFile, createFileServer, secureEqual } = require('../../container/file-server');

async function request(server, pathname, options = {}) {
  const address = server.address();
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        host: '127.0.0.1',
        port: address.port,
        path: pathname,
        method: options.method || 'GET',
        headers: options.headers || {},
      },
      (response) => {
        const chunks = [];
        response.on('data', (chunk) => chunks.push(chunk));
        response.on('end', () => resolve({ body: Buffer.concat(chunks), headers: response.headers, status: response.statusCode }));
      },
    );
    req.on('error', reject);
    req.end();
  });
}

async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'planet-file-server-'));
  const dist = path.join(root, 'dist');
  await fs.mkdir(dist);
  await fs.writeFile(path.join(dist, 'planet'), 'planet-data');
  await fs.writeFile(path.join(dist, '0123456789abcdef.moon'), 'moon-data');
  await fs.writeFile(path.join(root, 'secret'), 'do-not-serve');

  const server = createFileServer({ distPath: dist, secret: 'test-secret' });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => {
    await new Promise((resolve) => server.close(resolve));
    await fs.rm(root, { recursive: true, force: true });
  });
  return { dist, server };
}

test('only Planet and canonical Moon filenames are allowed', () => {
  assert.equal(allowedFile('/planet'), 'planet');
  assert.equal(allowedFile('/0123456789abcdef.moon'), '0123456789abcdef.moon');
  assert.equal(allowedFile('/other.txt'), null);
  assert.equal(allowedFile('/../../etc/passwd'), null);
  assert.equal(allowedFile('/ABCDEF0123456789.moon'), null);
});

test('secret comparison is constant-size and correct', () => {
  assert.equal(secureEqual('same', 'same'), true);
  assert.equal(secureEqual('different', 'same'), false);
  assert.equal(secureEqual('', 'same'), false);
});

test('rejects unauthenticated downloads', async (t) => {
  const { server } = await fixture(t);
  const response = await request(server, '/planet');
  assert.equal(response.status, 401);
});

test('accepts bearer and legacy query authentication', async (t) => {
  const { server } = await fixture(t);
  const bearer = await request(server, '/planet', { headers: { authorization: 'Bearer test-secret' } });
  const query = await request(server, '/0123456789abcdef.moon?key=test-secret');
  assert.equal(bearer.status, 200);
  assert.equal(bearer.body.toString(), 'planet-data');
  assert.equal(query.status, 200);
  assert.equal(query.body.toString(), 'moon-data');
});

test('rejects traversal, symlinks, and unsupported methods', async (t) => {
  const { dist, server } = await fixture(t);
  await fs.symlink('/etc/passwd', path.join(dist, 'fedcba9876543210.moon'));
  const traversal = await request(server, '/..%2fsecret?key=test-secret');
  const symlink = await request(server, '/fedcba9876543210.moon?key=test-secret');
  const post = await request(server, '/planet?key=test-secret', { method: 'POST' });
  assert.equal(traversal.status, 404);
  assert.equal(symlink.status, 404);
  assert.equal(post.status, 405);
});

test('supports HEAD and a loopback health check', async (t) => {
  const { server } = await fixture(t);
  const head = await request(server, '/planet?key=test-secret', { method: 'HEAD' });
  const health = await request(server, '/healthz');
  assert.equal(head.status, 200);
  assert.equal(head.body.length, 0);
  assert.equal(health.status, 200);
  assert.equal(health.body.toString(), 'ok');
});
