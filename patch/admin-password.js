'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { randomBytes } = require('node:crypto');
const argon2 = require('/opt/ztncui/src/node_modules/argon2');
const { read, parseJson, syncDirectory, atomicWrite } = require('./settings');

const passwd = '/app/ztncui/src/etc/passwd';
const initialPassword = '/app/config/.initial-admin-password';

async function newAdmin() {
    const password = randomBytes(24).toString('base64url');
    const admin = { name: 'admin', pass_set: false, hash: await argon2.hash(password) };
    return { admin, password };
}

function removeInitial() {
    try {
        fs.unlinkSync(initialPassword);
    } catch (error) {
        if (error.code === 'ENOENT') return false;
        throw error;
    }
    syncDirectory(path.dirname(initialPassword));
    return true;
}

async function initial() {
    const saved = read(initialPassword);
    if (!saved) return;
    const password = saved.toString().trimEnd();
    const current = read(passwd);
    const admin = parseJson(current, passwd)?.admin;
    const matches = admin && await argon2.verify(admin.hash, password);
    if (removeInitial() && matches && read(passwd)?.equals(current)) {
        process.stdout.write(password + '\n');
    }
}

async function reset() {
    const { admin, password } = await newAdmin();
    const users = parseJson(read(passwd), passwd);
    if (!users || typeof users !== 'object' || Array.isArray(users)) {
        throw new Error('管理员密码文件格式错误');
    }
    atomicWrite(passwd, JSON.stringify({ ...users, admin }));
    process.stdout.write(password + '\n');
    try {
        removeInitial();
    } catch (error) {
        console.error('无法清理原首次密码文件：' + error.message);
    }
}

if (require.main === module) {
    (async () => {
        const [command] = process.argv.slice(2);
        if (command === 'initial') await initial();
        else if (command === 'reset') await reset();
        else throw new Error('用法：admin-password.js initial | reset');
    })().catch(error => {
        console.error(error.message);
        process.exitCode = 1;
    });
}

module.exports = { newAdmin, passwd, initialPassword };
