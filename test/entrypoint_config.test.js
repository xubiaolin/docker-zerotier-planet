const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const repoRoot = path.resolve(__dirname, '..');
const entrypointPath = path.join(repoRoot, 'patch', 'entrypoint.sh');

function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

function makeFixture() {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'entrypoint-config-'));
    const appPath = path.join(root, 'app');
    const backupPath = path.join(root, 'bak');
    const zeroTierPath = path.join(root, 'one');

    fs.mkdirSync(path.join(backupPath, 'zerotier-one'), { recursive: true });
    fs.mkdirSync(path.join(backupPath, 'ztncui', 'src'), { recursive: true });
    fs.mkdirSync(path.join(appPath, 'config'), { recursive: true });

    fs.writeFileSync(
        path.join(backupPath, 'zerotier-one', 'zerotier-idtool'),
        `#!/bin/sh
set -eu
case "$1" in
  generate)
    printf 'identity-secret\\n' > "$2"
    printf 'identity-public\\n' > "$3"
    ;;
  initmoon)
    printf '%s\\n' '{"worldType":"moon","id":"1","roots":[{"stableEndpoints":[]}]}'
    ;;
  genmoon)
    if grep -q '8eac90a' "$2"; then
      printf 'planet\\n' > 0000000008eac90a.moon
    else
      printf 'moon\\n' > 0000000000000001.moon
    fi
    ;;
  *)
    exit 2
    ;;
esac
`,
        { mode: 0o755 }
    );

    return { root, appPath, backupPath, zeroTierPath };
}

function writeTestEntrypoint(fixture) {
    const source = fs.readFileSync(entrypointPath, 'utf8');
    const testSource = source
        .replace('ZEROTIER_PATH="/var/lib/zerotier-one"', `ZEROTIER_PATH=${shellQuote(fixture.zeroTierPath)}`)
        .replace('APP_PATH="/app"', `APP_PATH=${shellQuote(fixture.appPath)}`)
        .replace('BACKUP_PATH="/bak"', `BACKUP_PATH=${shellQuote(fixture.backupPath)}`)
        .replace(/\nstart_services\n?$/, '\n: # start_services skipped by test harness\n');
    const testEntrypointPath = path.join(fixture.root, 'entrypoint.sh');
    fs.writeFileSync(testEntrypointPath, testSource, { mode: 0o755 });
    return testEntrypointPath;
}

function createExistingZeroTier(fixture, moonJson) {
    const existingMoonJson =
        moonJson || {
            worldType: 'moon',
            id: '1',
            roots: [{ stableEndpoints: ['203.0.113.10/12345'] }],
        };
    fs.mkdirSync(fixture.zeroTierPath, { recursive: true });
    fs.copyFileSync(
        path.join(fixture.backupPath, 'zerotier-one', 'zerotier-idtool'),
        path.join(fixture.zeroTierPath, 'zerotier-idtool')
    );
    fs.chmodSync(path.join(fixture.zeroTierPath, 'zerotier-idtool'), 0o755);
    fs.writeFileSync(path.join(fixture.zeroTierPath, 'authtoken.secret'), 'current-token\n');
    fs.writeFileSync(path.join(fixture.zeroTierPath, 'moon.json'), JSON.stringify(existingMoonJson));
}

function createExistingZtncui(fixture, envText = '') {
    const srcPath = path.join(fixture.appPath, 'ztncui', 'src');
    fs.mkdirSync(srcPath, { recursive: true });
    fs.writeFileSync(path.join(srcPath, '.env'), envText);
}

function runEntrypoint(fixture, env = {}) {
    const script = writeTestEntrypoint(fixture);
    execFileSync('sh', [script], {
        cwd: fixture.root,
        env: {
            ...process.env,
            ZT_PORT: '12345',
            API_PORT: '4444',
            FILE_SERVER_PORT: '4000',
            IP_ADDR4: '203.0.113.10',
            IP_ADDR6: '',
            ...env,
        },
        stdio: ['ignore', 'pipe', 'pipe'],
    });
}

test('existing ztncui .env is refreshed when API_PORT or ZT_PORT changes', () => {
    const fixture = makeFixture();
    createExistingZeroTier(fixture);
    createExistingZtncui(
        fixture,
        [
            'HTTP_PORT=3443',
            'NODE_ENV=production',
            'HTTP_ALL_INTERFACES=true',
            'ZT_ADDR=localhost:9994',
            'ZT_TOKEN=old-token',
            '',
        ].join('\n')
    );

    runEntrypoint(fixture);

    const envText = fs.readFileSync(path.join(fixture.appPath, 'ztncui', 'src', '.env'), 'utf8');
    assert.match(envText, /^HTTP_PORT=4444$/m);
    assert.match(envText, /^ZT_ADDR=localhost:12345$/m);
    assert.match(envText, /^ZT_TOKEN=current-token$/m);
});

test('existing world files are rebuilt when endpoint settings change', () => {
    const fixture = makeFixture();
    createExistingZeroTier(fixture, {
        worldType: 'moon',
        id: '1',
        roots: [{ stableEndpoints: ['198.51.100.2/9994'] }],
    });
    createExistingZtncui(fixture);
    fs.mkdirSync(path.join(fixture.appPath, 'dist'), { recursive: true });
    fs.writeFileSync(path.join(fixture.appPath, 'dist', 'planet'), 'old-planet\n');

    runEntrypoint(fixture);

    const moonJson = JSON.parse(fs.readFileSync(path.join(fixture.zeroTierPath, 'moon.json'), 'utf8'));
    assert.deepEqual(moonJson.roots[0].stableEndpoints, ['203.0.113.10/12345']);
    assert.equal(fs.readFileSync(path.join(fixture.appPath, 'dist', 'planet'), 'utf8'), 'planet\n');
});

test('file-server port config tracks FILE_SERVER_PORT on every start', () => {
    const fixture = makeFixture();
    createExistingZeroTier(fixture);
    createExistingZtncui(fixture);
    fs.writeFileSync(path.join(fixture.appPath, 'config', 'file_server.port'), '3000\n');

    runEntrypoint(fixture);

    assert.equal(fs.readFileSync(path.join(fixture.appPath, 'config', 'file_server.port'), 'utf8'), '4000\n');
});

test('default Compose file keeps plaintext HTTP local without the public HTTP override', () => {
    const compose = fs.readFileSync(path.join(repoRoot, 'compose.yaml'), 'utf8');
    assert.doesNotMatch(compose, /\$\{HOST_BIND_IP:-127\.0\.0\.1\}:\$\{API_PORT:-3443\}:\$\{API_PORT:-3443\}/);
    assert.doesNotMatch(compose, /\$\{HOST_BIND_IP:-127\.0\.0\.1\}:\$\{FILE_SERVER_PORT:-3000\}:\$\{FILE_SERVER_PORT:-3000\}/);
    assert.match(compose, /127\.0\.0\.1:\$\{API_PORT:-3443\}:\$\{API_PORT:-3443\}/);
    assert.match(compose, /127\.0\.0\.1:\$\{FILE_SERVER_PORT:-3000\}:\$\{FILE_SERVER_PORT:-3000\}/);

    const publicOverride = fs.readFileSync(path.join(repoRoot, 'compose.public-http.yaml'), 'utf8');
    assert.match(publicOverride, /PUBLIC_HTTP: "true"/);
    assert.match(publicOverride, /\$\{HOST_BIND_IP:-0\.0\.0\.0\}:\$\{API_PORT:-3443\}:\$\{API_PORT:-3443\}/);
    assert.match(publicOverride, /\$\{HOST_BIND_IP:-0\.0\.0\.0\}:\$\{FILE_SERVER_PORT:-3000\}:\$\{FILE_SERVER_PORT:-3000\}/);
});
