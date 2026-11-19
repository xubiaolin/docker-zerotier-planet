'use strict';

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { createHash, timingSafeEqual } = require('node:crypto');

const secret = fs.readFileSync('/app/config/file_server.key', 'utf8').replace(/[\r\n]+$/, '');
if (!secret) throw new Error('file_server.key is empty');
const digest = value => createHash('sha256').update(value).digest();
const keyDigest = digest(secret);
const dist = fs.realpathSync('/app/dist');
const contentTypes = {
    '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json',
    '.png': 'image/png', '.jpg': 'image/jpg', '.gif': 'image/gif', '.svg': 'image/svg+xml',
    '.wav': 'audio/wav', '.mp4': 'video/mp4', '.woff': 'application/font-woff',
    '.ttf': 'application/font-ttf', '.eot': 'application/vnd.ms-fontobject',
    '.otf': 'application/font-otf', '.wasm': 'application/wasm',
};

async function download(req, res) {
    let url, requested;
    try {
        url = new URL(req.url, 'http://localhost');
        requested = decodeURIComponent(url.pathname);
    } catch {
        return res.writeHead(400).end();
    }
    if (!timingSafeEqual(digest(url.searchParams.get('key') || ''), keyDigest)) {
        return res.writeHead(401).end('Unauthorized');
    }
    if (req.method !== 'GET' && req.method !== 'HEAD') return res.writeHead(405).end();

    let handle;
    try {
        const file = await fs.promises.realpath(path.join(dist, requested));
        if (!file.startsWith(dist + path.sep)) return res.writeHead(404).end();
        handle = await fs.promises.open(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
        // Check the open descriptor too: a parent directory can be moved while
        // the request is in flight. Only serve regular files still below dist.
        const opened = await fs.promises.readlink('/proc/self/fd/' + handle.fd);
        const stat = await handle.stat();
        if (!opened.startsWith(dist + path.sep) || !stat.isFile()) return res.writeHead(404).end();
        res.writeHead(200, {
            'Content-Type': contentTypes[path.extname(requested).toLowerCase()] || 'application/octet-stream',
            'Content-Length': stat.size,
        });
        if (req.method === 'HEAD') return res.end();
        const stream = handle.createReadStream();
        handle = undefined; // The stream now owns the descriptor.
        stream.on('error', () => res.destroy());
        res.on('close', () => stream.destroy());
        stream.pipe(res);
    } catch {
        if (res.headersSent) res.destroy();
        else res.writeHead(404).end();
    } finally {
        if (handle) await handle.close();
    }
}

http.createServer(download).listen(Number(process.env.FILE_SERVER_PORT));
