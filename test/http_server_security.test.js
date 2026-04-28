const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');

const {
    createFileServer,
    generateSecret,
    resolveArtifactPath,
} = require('../patch/http_server');

function makeFixture() {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'http-server-security-'));
    const distPath = path.join(root, 'dist');
    const configPath = path.join(root, 'config');
    fs.mkdirSync(distPath, { recursive: true });
    fs.mkdirSync(configPath, { recursive: true });
    fs.writeFileSync(path.join(distPath, 'planet'), 'planet-content');
    fs.writeFileSync(path.join(distPath, 'earth.moon'), 'moon-content');
    fs.writeFileSync(path.join(configPath, 'file_server.key'), 'outside-secret');
    return {
        root,
        distPath,
        secretKeyPath: path.join(configPath, 'file_server.key'),
    };
}

function closeServer(server) {
    return new Promise((resolve, reject) => {
        server.close((error) => (error ? reject(error) : resolve()));
    });
}

function listen(server) {
    return new Promise((resolve) => {
        server.listen(0, '127.0.0.1', () => {
            resolve(server.address().port);
        });
    });
}

function request(port, requestPath, options = {}) {
    return new Promise((resolve, reject) => {
        const req = http.request(
            {
                host: '127.0.0.1',
                port,
                path: requestPath,
                method: options.method || 'GET',
                headers: options.headers || {},
            },
            (res) => {
                const chunks = [];
                res.on('data', (chunk) => chunks.push(chunk));
                res.on('end', () => {
                    resolve({
                        statusCode: res.statusCode,
                        headers: res.headers,
                        body: Buffer.concat(chunks).toString('utf8'),
                    });
                });
            }
        );
        req.on('error', reject);
        req.end();
    });
}

test('unauthenticated request returns 401', async () => {
    const fixture = makeFixture();
    const { server, secretKey } = createFileServer({ ...fixture, warn: false });
    const port = await listen(server);
    try {
        const response = await request(port, '/planet');
        assert.equal(response.statusCode, 401);
        assert.equal(response.body, 'Unauthorized');
        assert.ok(secretKey);
    } finally {
        await closeServer(server);
    }
});

test('Authorization bearer token can download allowed planet artifact', async () => {
    const fixture = makeFixture();
    const secretKey = 'test-secret';
    const { server } = createFileServer({ ...fixture, secretKey, warn: false });
    const port = await listen(server);
    try {
        const response = await request(port, '/planet', {
            headers: { Authorization: `Bearer ${secretKey}` },
        });
        assert.equal(response.statusCode, 200);
        assert.equal(response.body, 'planet-content');
        assert.equal(response.headers['cache-control'], 'no-store');
        assert.equal(response.headers['x-content-type-options'], 'nosniff');
    } finally {
        await closeServer(server);
    }
});

test('X-File-Server-Key header can download allowed moon artifacts', async () => {
    const fixture = makeFixture();
    const secretKey = 'test-secret';
    const { server } = createFileServer({ ...fixture, secretKey, warn: false });
    const port = await listen(server);
    try {
        const response = await request(port, '/earth.moon', {
            headers: { 'X-File-Server-Key': secretKey },
        });
        assert.equal(response.statusCode, 200);
        assert.equal(response.body, 'moon-content');
    } finally {
        await closeServer(server);
    }
});

test('HEAD succeeds without a response body', async () => {
    const fixture = makeFixture();
    const secretKey = 'test-secret';
    const { server } = createFileServer({ ...fixture, secretKey, warn: false });
    const port = await listen(server);
    try {
        const response = await request(port, '/planet', {
            method: 'HEAD',
            headers: { Authorization: `Bearer ${secretKey}` },
        });
        assert.equal(response.statusCode, 200);
        assert.equal(response.body, '');
    } finally {
        await closeServer(server);
    }
});

test('unsupported methods return 405', async () => {
    const fixture = makeFixture();
    const secretKey = 'test-secret';
    const { server } = createFileServer({ ...fixture, secretKey, warn: false });
    const port = await listen(server);
    try {
        const response = await request(port, '/planet', {
            method: 'POST',
            headers: { Authorization: `Bearer ${secretKey}` },
        });
        assert.equal(response.statusCode, 405);
        assert.equal(response.headers.allow, 'GET, HEAD');
    } finally {
        await closeServer(server);
    }
});

test('query-string auth is rejected by default', async () => {
    const fixture = makeFixture();
    const secretKey = 'test-secret';
    const { server } = createFileServer({ ...fixture, secretKey, warn: false });
    const port = await listen(server);
    try {
        const response = await request(port, `/planet?key=${secretKey}`);
        assert.equal(response.statusCode, 401);
    } finally {
        await closeServer(server);
    }
});

test('query-string auth only works with explicit compatibility flag', async () => {
    const fixture = makeFixture();
    const secretKey = 'test-secret';
    const warnings = [];
    const { server } = createFileServer({
        ...fixture,
        secretKey,
        allowQueryKey: true,
        warn: (message) => warnings.push(message),
    });
    const port = await listen(server);
    try {
        const response = await request(port, `/planet?key=${secretKey}`);
        assert.equal(response.statusCode, 200);
        assert.equal(response.body, 'planet-content');
        assert.match(warnings[0], /deprecated insecure query-string/);
    } finally {
        await closeServer(server);
    }
});

test('raw and encoded traversal attempts never read outside dist', async () => {
    const fixture = makeFixture();
    const secretKey = 'test-secret';
    const { server } = createFileServer({ ...fixture, secretKey, warn: false });
    const port = await listen(server);
    const headers = { Authorization: `Bearer ${secretKey}` };
    try {
        for (const requestPath of [
            '/../config/file_server.key',
            '/%2e%2e/config/file_server.key',
            '/..%2f..%2fetc%2fpasswd',
            '//../planet',
            '/planet/../file_server.key',
            '/bad%ZZpath',
        ]) {
            const response = await request(port, requestPath, { headers });
            assert.notEqual(response.statusCode, 200, requestPath);
            assert.notEqual(response.body, 'outside-secret', requestPath);
            assert.doesNotMatch(response.body, /outside-secret/, requestPath);
        }
    } finally {
        await closeServer(server);
    }
});

test('only planet and dot-moon artifacts are allowed', () => {
    const fixture = makeFixture();
    assert.equal(resolveArtifactPath('/planet', fixture.distPath).ok, true);
    assert.equal(resolveArtifactPath('/earth.moon', fixture.distPath).ok, true);
    assert.equal(resolveArtifactPath('/moon.txt', fixture.distPath).ok, false);
    assert.equal(resolveArtifactPath('/subdir/planet', fixture.distPath).ok, false);
    assert.equal(resolveArtifactPath('/.hidden.moon', fixture.distPath).ok, false);
});

test('generated key is 256-bit hex and key file is 0600', () => {
    const fixture = makeFixture();
    fs.rmSync(fixture.secretKeyPath, { force: true });
    const { server, secretKey } = createFileServer({ ...fixture, warn: false });
    server.close();

    assert.match(secretKey, /^[a-f0-9]{64}$/);
    assert.equal(generateSecret().length, 64);
    assert.equal(fs.readFileSync(fixture.secretKeyPath, 'utf8'), secretKey);
    assert.equal(fs.statSync(fixture.secretKeyPath).mode & 0o777, 0o600);
});
