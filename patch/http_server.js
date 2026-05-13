const http = require('http');
const fs = require('fs');
const path = require('path');
const url = require('url');
const crypto = require('crypto');

const port = process.env.FILE_SERVER_PORT;
const DIST_PATH = path.resolve('/app/dist');
const CONFIG_PATH = '/app/config';
const secretKeyPath = path.join(CONFIG_PATH, 'file_server.key');
const placeholderKeys = new Set(['REPLACE_WITH_OPENSSL_RAND_HEX_32']);

function persistKey(secretKey) {
    fs.mkdirSync(CONFIG_PATH, { recursive: true });
    fs.writeFileSync(secretKeyPath, `${secretKey}\n`, { mode: 0o600 });
}

function readExistingKey() {
    try {
        return fs.readFileSync(secretKeyPath, 'utf8').trim();
    } catch (err) {
        if (err.code === 'ENOENT') {
            return '';
        }
        throw err;
    }
}

function loadSecretKey() {
    const configuredKey = (process.env.FILE_KEY || process.env.SECRET_KEY || '').trim();
    if (configuredKey && !placeholderKeys.has(configuredKey)) {
        persistKey(configuredKey);
        return configuredKey;
    }

    const existingKey = readExistingKey();
    if (existingKey) {
        return existingKey;
    }

    const generatedKey = crypto.randomBytes(32).toString('hex');
    persistKey(generatedKey);
    return generatedKey;
}

function timingSafeStringEqual(actual, expected) {
    const actualBuffer = Buffer.from(actual || '', 'utf8');
    const expectedBuffer = Buffer.from(expected || '', 'utf8');

    if (actualBuffer.length !== expectedBuffer.length) {
        return false;
    }

    return crypto.timingSafeEqual(actualBuffer, expectedBuffer);
}

function resolveDownloadPath(requestPath) {
    let pathname;

    try {
        pathname = decodeURIComponent(requestPath || '/');
    } catch (err) {
        return null;
    }

    if (pathname.includes('\0')) {
        return null;
    }

    const filePath = path.resolve(DIST_PATH, `.${pathname}`);
    if (filePath !== DIST_PATH && !filePath.startsWith(`${DIST_PATH}${path.sep}`)) {
        return null;
    }

    return filePath;
}

function sendText(res, statusCode, body) {
    res.writeHead(statusCode, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end(body);
}

const SECRET_KEY = loadSecretKey();
console.log(`FILE_KEY written to ${secretKeyPath}`);

const server = http.createServer((req, res) => {
    const method = req.method || 'GET';
    if (method !== 'GET' && method !== 'HEAD') {
        res.writeHead(405, { Allow: 'GET, HEAD' });
        return res.end();
    }

    const parsedUrl = url.parse(req.url, true);
    const key = parsedUrl.query.key;
    if (typeof key !== 'string' || !timingSafeStringEqual(key, SECRET_KEY)) {
        return sendText(res, 401, 'Unauthorized');
    }

    const filePath = resolveDownloadPath(parsedUrl.pathname);
    if (!filePath) {
        return sendText(res, 403, 'Forbidden');
    }

    let extname = String(path.extname(filePath)).toLowerCase();
    let mimeTypes = {
        '.html': 'text/html',
        '.js': 'text/javascript',
        '.css': 'text/css',
        '.json': 'application/json',
        '.png': 'image/png',
        '.jpg': 'image/jpg',
        '.gif': 'image/gif',
        '.svg': 'image/svg+xml',
        '.wav': 'audio/wav',
        '.mp4': 'video/mp4',
        '.woff': 'application/font-woff',
        '.ttf': 'application/font-ttf',
        '.eot': 'application/vnd.ms-fontobject',
        '.otf': 'application/font-otf',
        '.wasm': 'application/wasm'
    };
    let contentType = mimeTypes[extname] || 'application/octet-stream';

    fs.readFile(filePath, (err, content) => {
        if (err) {
            if (err.code === 'ENOENT') {
                return sendText(res, 404, '404 - File Not Found');
            }
            if (err.code === 'EISDIR') {
                return sendText(res, 403, 'Forbidden');
            }
            res.writeHead(500);
            return res.end(`Server Error: ${err.code}`);
        }

        res.writeHead(200, { 'Content-Type': contentType });
        if (method === 'HEAD') {
            return res.end();
        }
        return res.end(content);
    });
});

server.listen(port, () => {
    console.log(`Server running at http://0.0.0.0:${port}/`);
});
