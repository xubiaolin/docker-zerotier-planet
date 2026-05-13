const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const repoRoot = path.resolve(__dirname, '..');
const ztncuiAdminPath = path.join(repoRoot, 'patch', 'ztncui_admin.js');

async function runAdminHelper({ files = {}, env = {} }) {
    const writes = new Map();
    const source = fs.readFileSync(ztncuiAdminPath, 'utf8');
    const mockFs = {
        readFileSync(filePath, encoding) {
            assert.equal(encoding, 'utf8');
            if (!Object.prototype.hasOwnProperty.call(files, filePath)) {
                const error = new Error(`ENOENT: no such file or directory, open '${filePath}'`);
                error.code = 'ENOENT';
                throw error;
            }
            return files[filePath];
        },
        mkdirSync() {},
        writeFileSync(filePath, content) {
            writes.set(filePath, content);
        },
    };
    const context = {
        console,
        process: {
            env,
            exit(code) {
                throw new Error(`process.exit(${code})`);
            },
        },
        require(moduleName) {
            if (moduleName === 'fs') {
                return mockFs;
            }
            if (moduleName === 'argon2' || moduleName === '/app/ztncui/src/node_modules/argon2') {
                return {
                    argon2i: 1,
                    hash: async (password) => `hash:${password}`,
                };
            }
            throw new Error(`Unexpected module: ${moduleName}`);
        },
    };

    vm.runInNewContext(source, context, { filename: ztncuiAdminPath });
    await new Promise((resolve) => setImmediate(resolve));
    return writes;
}

test('resetting the admin password preserves existing ztncui users', async () => {
    const passwdPath = '/app/ztncui/src/etc/passwd';
    const writes = await runAdminHelper({
        env: { ZTNCUI_ADMIN_PASSWORD: 'new-password' },
        files: {
            [passwdPath]: JSON.stringify({
                admin: {
                    name: 'admin',
                    pass_set: true,
                    hash: 'old-admin-hash',
                },
                operator: {
                    name: 'operator',
                    pass_set: true,
                    hash: 'operator-hash',
                },
            }),
        },
    });

    const users = JSON.parse(writes.get(passwdPath));
    assert.deepEqual(Object.keys(users).sort(), ['admin', 'operator']);
    assert.equal(users.admin.hash, 'hash:new-password');
    assert.equal(users.operator.hash, 'operator-hash');
});
