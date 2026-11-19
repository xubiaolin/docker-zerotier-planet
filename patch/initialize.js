'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { randomBytes, createHash } = require('node:crypto');
const { isIP } = require('node:net');
const { read, value, parseJson, legacyEnv, resolveSettings, validate } = require('./settings');
const { execFileSync } = require('node:child_process');

const one = '/var/lib/zerotier-one';
const config = '/app/config';
const dist = '/app/dist';
const ui = '/app/ztncui/src';
const builder = '/usr/local/bin/mkworld';
const idtool = '/usr/sbin/zerotier-idtool';
const pending = path.join(one, '.planet-init.pending');
const complete = path.join(config, '.planet-initialized');
const moonPath = path.join(one, 'moon.json');
const passwd = path.join(ui, 'etc/passwd');
const keyPath = path.join(config, 'file_server.key');
const published = path.join(dist, 'planet');
const controller = path.join(one, 'controller.d/network');
const envFile = path.join(ui, '.env');
const tokenFile = path.join(one, 'authtoken.secret');
const plan = new Map();

function requireState(condition, message) {
    if (!condition) throw new Error(message);
}

function entries(dir) {
    return fs.existsSync(dir) ? fs.readdirSync(dir) : [];
}

function checksum(data) {
    return createHash('sha256').update(data || '').digest('hex');
}

function planWrite(file, data) {
    plan.set(file, [checksum(read(file)), Buffer.from(data).toString('base64')]);
}

function add(file, data) {
    if (!read(file)?.length) planWrite(file, data);
}

function run(program, args, cwd) {
    try {
        return execFileSync(program, args, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });
    } catch {
        throw new Error(`${path.basename(program)} ${args[0] || '生成 planet'} 失败`);
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

// Each target is on its own Docker mount. Persist the complete, validated plan
// before the first rename so a killed process can replay the same credentials.
function atomicWrite(file, data) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = path.join(path.dirname(file), '.planet-write-' + randomBytes(12).toString('hex'));
    fs.writeFileSync(tmp, data, { mode: 0o600, flag: 'wx', flush: true });
    fs.renameSync(tmp, file);
    syncDirectory(path.dirname(file));
}

function allowedTarget(file) {
    const names = {
        [one]: ['identity.public', 'identity.secret', 'authtoken.secret', 'moon.json', 'planet', 'current.c25519', 'previous.c25519'],
        [config]: ['.planet-initialized', 'ip_addr4', 'ip_addr6', 'zerotier-one.port', 'ztncui.port', 'file_server.key', 'file_server.port'],
        [ui]: ['.env'],
        [path.join(ui, 'etc')]: ['default.passwd', 'passwd'],
        [dist]: ['planet'],
    };
    const dir = path.dirname(file);
    const name = path.basename(file);
    return names[dir]?.includes(name) ||
        ([dist, path.join(one, 'moons.d')].includes(dir) && /^[0-9a-f]{16}\.moon$/.test(name));
}

function publish(records) {
    for (const [file, before, encoded] of records) {
        requireState(allowedTarget(file), '初始化记录的目标文件异常');
        const saved = read(file);
        requireState(checksum(saved) === before || saved?.equals(Buffer.from(encoded, 'base64')), `初始化中断后文件已改变：${file}`);
    }
    // The daemon normally creates this directory. Create it inside the commit
    // so a first start interrupted before daemon startup is also retryable.
    fs.mkdirSync(path.join(one, 'controller.d/network'), { recursive: true });
    for (const [file, , encoded] of records) {
        const data = Buffer.from(encoded, 'base64');
        if (!read(file)?.equals(data)) atomicWrite(file, data);
    }
    fs.unlinkSync(pending);
    syncDirectory(one);
}

function prepareCredentials() {
    const existingUi = value(passwd);
    const downloadKey = value(keyPath);
    const isComplete = fs.existsSync(complete);
    const hasNetworks = entries(controller).length > 0;
    const served = Boolean(isComplete || downloadKey || hasNetworks);
    const hasIdentityEvidence = served || existingUi || entries(dist).length ||
        fs.existsSync(envFile) || entries(one).some(name =>
            !['authtoken.secret', 'zerotier-one.port'].includes(name) && !name.startsWith('.planet-write-'));

    let token = value(tokenFile) || legacyEnv().ZT_TOKEN;
    requireState(token || !served, `缺少控制器访问密钥 ${tokenFile} 和 ztncui 的 ZT_TOKEN`);
    token ||= randomBytes(24).toString('hex');
    requireState(!/[\r\n]/.test(token), `控制器访问密钥格式错误：${tokenFile}`);
    requireState(downloadKey || process.env.SECRET_KEY || !(isComplete || existingUi || hasNetworks),
        `缺少旧下载密钥 ${keyPath}`);
    requireState(existingUi || !served, `缺少原管理员密码文件 ${passwd}`);
    if (existingUi) {
        requireState(Object.values(parseJson(existingUi, passwd)).some(user => user && typeof user.hash === 'string'),
            `管理员密码文件无有效用户：${passwd}`);
    }
    if (served) requireState(fs.existsSync(controller), `缺少控制器网络目录 ${controller}`);

    add(tokenFile, token);
    add(keyPath, downloadKey || process.env.SECRET_KEY || randomBytes(24).toString('hex'));
    const defaultPasswd = fs.readFileSync('/opt/ztncui/etc.defaults/default.passwd');
    add(path.join(ui, 'etc/default.passwd'), defaultPasswd);
    add(passwd, defaultPasswd);
    return { served, hasIdentityEvidence, token };
}

function prepareIdentity(work, execId, hasIdentityEvidence) {
    const secretPath = path.join(one, 'identity.secret');
    const localSecret = value(secretPath);
    if (localSecret) {
        fs.writeFileSync(path.join(work, 'identity.secret'), localSecret);
    } else {
        requireState(!hasIdentityEvidence, `缺少原节点身份 ${secretPath}`);
        execId('generate', 'identity.secret', 'identity.public');
        add(secretPath, fs.readFileSync(path.join(work, 'identity.secret')));
    }
    requireState(/^[a-f0-9]{10}:0:[a-f0-9]{128}:[a-f0-9]{128}$/i.test(
        fs.readFileSync(path.join(work, 'identity.secret'), 'utf8').trim()), 'identity.secret 私钥格式错误');
    execId('validate', 'identity.secret');
    const identity = execId('getpublic', 'identity.secret').toString().trim();
    const publicPath = path.join(one, 'identity.public');
    requireState(!value(publicPath) || value(publicPath) === identity, 'identity.public 与原私钥不匹配');
    add(publicPath, identity);
    fs.writeFileSync(path.join(work, 'identity.public'), identity);
    // idtool validate verifies the address and public identity. Check that the
    // private signing key still matches before launching the controller.
    const signature = execId('sign', 'identity.secret', 'identity.public').toString();
    execId('verify', 'identity.public', 'identity.public', signature);
    return identity;
}

function prepareEndpoints(work, moon, token) {
    const [ztPort, apiPort, filePort, ipv4, ipv6] = resolveSettings(moon);
    const ports = [ztPort || '9994', apiPort || '3443', filePort || '3000'];
    const addresses = [ipv4, ipv6];
    if (!moon.roots[0].stableEndpoints.length) {
        for (const [index, version] of [4, 6].entries()) {
            if (addresses[index]) continue;
            try {
                const ip = run('curl', ['-fsS', '--max-time', '5', `https://ipv${version}.icanhazip.com/`], work).toString().trim();
                if (isIP(ip) === version) addresses[index] = ip;
            } catch { /* The host may have only one address family. */ }
        }
        moon.roots[0].stableEndpoints = addresses.filter(Boolean).map(ip => ip + '/' + ports[0]);
    }
    validate([...ports, ...addresses]);
    for (const [name, v] of Object.entries({
        'zerotier-one.port': ports[0], 'ztncui.port': ports[1], 'file_server.port': ports[2],
        ip_addr4: addresses[0], ip_addr6: addresses[1],
    })) add(path.join(config, name), v + '\n');
    add(envFile, `HTTP_PORT=${ports[1]}\nHTTP_ALL_INTERFACES=true\nNODE_ENV=production\nZT_ADDR=127.0.0.1:${ports[0]}\nZT_TOKEN=${token}\n`);
}

function prepareKeys(work, execWorld, previous, current, planetCopy, served) {
    const keyFiles = ['previous.c25519', 'current.c25519'];
    if (!previous?.length && !current?.length) {
        requireState(!planetCopy && !served, '缺少原 Planet 签名密钥 previous.c25519 和 current.c25519');
        execWorld('--new-keys');
    } else {
        requireState((!previous?.length || previous.length === 128) && (!current?.length || current.length === 128),
            'Planet 签名密钥长度错误');
        fs.writeFileSync(path.join(work, keyFiles[0]), previous?.length ? previous : current);
        fs.writeFileSync(path.join(work, keyFiles[1]), current?.length ? current : previous);
        if (!previous?.length || !current?.length) {
            requireState(planetCopy, '缺少可用于验证待恢复签名密钥的 Planet');
            execWorld('--verify-key-copy', planetCopy);
        } else if (planetCopy) {
            execWorld('--verify-keys', planetCopy);
        }
    }
    for (const name of keyFiles) add(path.join(one, name), fs.readFileSync(path.join(work, name)));
}

function prepare(work) {
    const execId = (...args) => run(idtool, args, work);
    const execWorld = (...args) => run(builder, args, work);
    const { served, hasIdentityEvidence, token } = prepareCredentials();
    const identity = prepareIdentity(work, execId, hasIdentityEvidence);
    const nodeId = identity.split(':')[0];
    requireState(!value(complete) || value(complete) === nodeId, '配置目录中的节点标识与私钥不匹配');
    const moonName = nodeId.padStart(16, '0') + '.moon';
    const moonCopies = [path.join(dist, moonName), path.join(one, 'moons.d', moonName), path.join(one, moonName)];
    const moonCopy = moonCopies.find(file => read(file)?.length);
    const moonText = value(moonPath);
    let moon = moonText && parseJson(moonText, moonPath);
    const prev = path.join(one, 'previous.c25519');
    const curr = path.join(one, 'current.c25519');
    const previous = read(prev);
    const current = read(curr);
    const isOwnWorld = (world, type) => world.worldType === type &&
        world.id === (type === 'planet' ? 149604618 : parseInt(nodeId, 16)) &&
        world.roots.some(root => root.identity === identity);
    const inspect = file => JSON.parse(execWorld('--inspect', file));
    // Legacy images contain the public Earth planet in one/planet. Only an
    // inspected world for this identity can restore the published private file.
    const localPlanet = path.join(one, 'planet');
    const worldBin = path.join(one, 'world.bin');
    let planetCopy;
    for (const file of [published, worldBin, localPlanet]) {
        if (!read(file)?.length) continue;
        if (isOwnWorld(inspect(file), 'planet')) {
            planetCopy = file;
            break;
        }
        requireState(file === localPlanet, `Planet 与原节点身份不匹配：${file}`);
    }
    requireState(moon || !(served || planetCopy || moonCopy || previous?.length || current?.length),
        `缺少原 Moon 签名材料 ${moonPath}`);
    // The old Dockerfile copied the builder's identity, stock Planet and tools
    // into the volume before replacing that identity. An interruption before
    // initmoon leaves no proof that this private key belongs to the instance.
    requireState(moon || !(fs.existsSync(path.join(one, 'mkworld')) && fs.existsSync(localPlanet)),
        '旧镜像仅留下构建阶段的身份与工具，无法确认节点私钥来源');
    if (!moon) moon = JSON.parse(execId('initmoon', 'identity.public'));
    requireState(moon.worldType === 'moon' && parseInt(moon.id, 16) === parseInt(nodeId, 16) &&
        moon.roots?.[0]?.identity === identity &&
        ['signingKey', 'signingKey_SECRET', 'updatesMustBeSignedBy'].every(k => /^[0-9a-f]{128}$/i.test(moon[k])),
        `Moon 签名材料或节点身份异常：${moonPath}`);

    const hadNoEndpoints = !moon.roots[0].stableEndpoints?.length;
    prepareEndpoints(work, moon, token);
    const configuredMoon = JSON.stringify(moon, null, 2);
    fs.writeFileSync(path.join(work, 'moon.json'), configuredMoon);
    if (!moonText) add(moonPath, configuredMoon);
    else if (hadNoEndpoints) {
        requireState(!served && !planetCopy && !moonCopy, `Moon 已发布但缺少 stableEndpoints：${moonPath}`);
        planWrite(moonPath, configuredMoon);
    }

    prepareKeys(work, execWorld, previous, current, planetCopy, served);
    if (!planetCopy) {
        execWorld();
        planetCopy = path.join(work, 'world.bin');
        requireState(isOwnWorld(inspect(planetCopy), 'planet'), 'Planet 生成结果无效');
    }
    add(published, fs.readFileSync(planetCopy));
    add(localPlanet, fs.readFileSync(planetCopy));
    const sourceMoon = moonCopy || path.join(work, moonName);
    if (!moonCopy) execId('genmoon', 'moon.json');
    for (const file of new Set([sourceMoon, ...moonCopies.slice(0, 2)])) {
        if (!read(file)?.length) continue;
        requireState(isOwnWorld(inspect(file), 'moon'), `Moon 与原节点身份不匹配：${file}`);
        execWorld(moonCopy ? '--verify-moon' : '--verify-new-moon', file);
    }
    for (const file of moonCopies.slice(0, 2)) add(file, fs.readFileSync(sourceMoon));

    add(complete, nodeId + '\n');
}

function initialize() {
    if (fs.existsSync(pending)) publish(parseJson(read(pending), pending));
    const work = fs.mkdtempSync(path.join(os.tmpdir(), 'planet-init-'));
    try {
        prepare(work);
        if (plan.size) {
            const records = Array.from(plan, ([file, change]) => [file, ...change]);
            atomicWrite(pending, JSON.stringify(records));
            publish(records);
        }
    } finally {
        fs.rmSync(work, { recursive: true, force: true });
    }
}

process.umask(0o077);
try {
    initialize();
} catch (error) {
    console.error('初始化停止。' + error.message + '。请检查挂载目录，必要时从同一实例备份还原后重试。');
    process.exitCode = 1;
}
