'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { randomBytes } = require('node:crypto');
const { isIP } = require('node:net');
const { parseEnv } = require('node:util');

// The host mounts the deployment root read-only for its preflight probe.
const saved = require.main === module && process.env.DEPLOYMENT_DATA;
const one = saved ? saved + '/one' : '/var/lib/zerotier-one';
const config = saved ? saved + '/config' : '/app/config';
const ui = saved ? saved + '/ztncui/src' : '/app/ztncui/src';
const moonPath = one + '/moon.json';

function read(file) {
    try {
        if (!fs.lstatSync(file).isFile()) throw new Error(`需要普通文件 ${file}`);
        return fs.readFileSync(file);
    } catch (error) {
        if (error.code === 'ENOENT') return null;
        throw error;
    }
}

function value(file) {
    return read(file)?.toString().replace(/[\r\n]+$/, '');
}

function parseJson(data, file) {
    try {
        return JSON.parse(data);
    } catch {
        throw new Error(`JSON 格式无效：${file}`);
    }
}

function syncDirectory(directory) {
    const fd = fs.openSync(directory, 'r');
    try {
        fs.fsyncSync(fd);
    } finally {
        fs.closeSync(fd);
    }
}

function atomicWrite(file, data) {
    const directory = path.dirname(file);
    fs.mkdirSync(directory, { recursive: true });
    const tmp = path.join(directory, '.planet-write-' + randomBytes(12).toString('hex'));
    const fd = fs.openSync(tmp, 'wx', 0o600);
    try {
        try {
            fs.writeFileSync(fd, data, { flush: true });
        } finally {
            fs.closeSync(fd);
        }
        fs.renameSync(tmp, file);
    } catch (error) {
        try { fs.unlinkSync(tmp); } catch { /* Keep the original write error. */ }
        throw error;
    }
    syncDirectory(directory);
}

function legacyEnv() {
    return parseEnv(value(ui + '/.env') || '');
}

function canonicalPort(port) {
    const number = Number(port);
    if (!/^\d+$/.test(port) || number < 1 || number > 65535) {
        throw new Error('端口必须是 1 至 65535 之间的不同整数');
    }
    return String(number);
}

function validAddress(address, version) {
    if (isIP(address) !== version) return false;
    if (version === 4) return address !== '0.0.0.0';
    return !address.includes('%') && new URL(`http://[${address}]`).hostname !== '[::]';
}

function validate(settings, allowMissing = false) {
    const [zt, api, files, ipv4, ipv6] = settings;
    const ports = [zt, api, files].filter(Boolean).map(canonicalPort);
    if ((!allowMissing && ports.length !== 3) || new Set(ports).size !== ports.length) {
        throw new Error('端口必须是 1 至 65535 之间的不同整数');
    }
    if ((ipv4 && !validAddress(ipv4, 4)) || (ipv6 && !validAddress(ipv6, 6))) {
        throw new Error('IP 地址格式错误或无法通告');
    }
    if (!allowMissing && !ipv4 && !ipv6) throw new Error('请配置 IP_ADDR4 或 IP_ADDR6');
}

function readMoon() {
    const text = value(moonPath);
    return text ? parseJson(text, moonPath) : null;
}

function resolveSettings(moon = readMoon()) {
    const endpoints = moon ? moon.roots?.[0]?.stableEndpoints : [];
    if (!Array.isArray(endpoints)) throw new Error(`无效的 stableEndpoints：${moonPath}`);
    const stable = endpoints.map(endpoint => {
        const parts = typeof endpoint === 'string' ? endpoint.split('/') : [];
        const [address, port] = parts;
        const version = isIP(address);
        if (parts.length !== 2 || !version || !validAddress(address, version)) {
            throw new Error(`无效的 stableEndpoints：${moonPath}`);
        }
        return [address, canonicalPort(port)];
    });
    const old = legacyEnv();
    const get = name => value(config + '/' + name);
    const ports = [
        get('zerotier-one.port') || stable[0]?.[1] || old.ZT_ADDR?.split(':').pop() ||
            process.env.ZT_PORT || value(one + '/zerotier-one.port') || '',
        get('ztncui.port') || old.HTTP_PORT || process.env.API_PORT || '',
        get('file_server.port') || process.env.FILE_SERVER_PORT || '',
    ].map(port => port ? canonicalPort(port) : port);
    const addresses = [4, 6].map(version => {
        const saved = get('ip_addr' + version);
        const endpoint = stable.find(([ip]) => isIP(ip) === version);
        return saved || endpoint?.[0] || (saved ?? process.env['IP_ADDR' + version] ?? '');
    });
    const settings = [...ports, ...addresses];
    validate(settings, true);
    return settings;
}

if (require.main === module) {
    try {
        const args = process.argv.slice(2);
        if (!args.length) process.stdout.write(resolveSettings().join('\n') + '\n');
        else if (args.length === 6 && args[0] === 'validate') validate(args.slice(1));
        else throw new Error('用法：settings.js [validate ZT_PORT API_PORT FILE_PORT IPv4 IPv6]');
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}

module.exports = { read, value, parseJson, syncDirectory, atomicWrite, legacyEnv, resolveSettings, validate, canonicalPort };
