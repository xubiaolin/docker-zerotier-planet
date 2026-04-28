const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const DEFAULT_PORT = process.env.FILE_SERVER_PORT || 3000;
const DEFAULT_HOST = process.env.FILE_SERVER_HOST || undefined;
const DEFAULT_DIST_PATH = process.env.DIST_PATH || '/app/dist';
const DEFAULT_SECRET_KEY_PATH = process.env.FILE_KEY_PATH || '/app/config/file_server.key';
const KEY_BYTES = 32;

function getConfiguredSecret(env = process.env) {
    return env.FILE_KEY || env.SECRET_KEY || null;
}

function generateSecret() {
    return crypto.randomBytes(KEY_BYTES).toString('hex');
}

function writeSecretKeyFile(secretKey, secretKeyPath) {
    fs.mkdirSync(path.dirname(secretKeyPath), { recursive: true });
    fs.writeFileSync(secretKeyPath, secretKey, { mode: 0o600 });
    fs.chmodSync(secretKeyPath, 0o600);
}

function normalizeBoolean(value) {
    return String(value || '').toLowerCase() === 'true';
}

function timingSafeEqualString(actual, expected) {
    if (typeof actual !== 'string' || typeof expected !== 'string') {
        return false;
    }

    const actualBuffer = Buffer.from(actual);
    const expectedBuffer = Buffer.from(expected);
    return actualBuffer.length === expectedBuffer.length && crypto.timingSafeEqual(actualBuffer, expectedBuffer);
}

function extractBearerToken(headerValue) {
    if (!headerValue) {
        return null;
    }

    const match = /^Bearer\s+(.+)$/i.exec(headerValue.trim());
    return match ? match[1] : null;
}

function getRequestKey(req, requestUrl, allowQueryKey) {
    const authorizationKey = extractBearerToken(req.headers.authorization);
    if (authorizationKey) {
        return authorizationKey;
    }

    const headerKey = req.headers['x-file-server-key'];
    if (typeof headerKey === 'string' && headerKey) {
        return headerKey;
    }

    if (allowQueryKey) {
        return requestUrl.searchParams.get('key');
    }

    return null;
}

function isAllowedArtifact(fileName) {
    return fileName === 'planet' || /^[A-Za-z0-9][A-Za-z0-9._-]*\.moon$/.test(fileName);
}

function resolveArtifactPath(requestPathname, distPath) {
    let decodedPathname;
    try {
        decodedPathname = decodeURIComponent(requestPathname);
    } catch (error) {
        return { ok: false, statusCode: 403 };
    }

    if (decodedPathname.includes('\0') || decodedPathname.includes('\\')) {
        return { ok: false, statusCode: 403 };
    }

    const withoutLeadingSlash = decodedPathname.replace(/^\/+/, '');
    const normalized = path.posix.normalize(withoutLeadingSlash);

    if (
        !normalized ||
        normalized === '.' ||
        normalized.startsWith('../') ||
        normalized === '..' ||
        path.posix.isAbsolute(normalized) ||
        normalized.includes('/')
    ) {
        return { ok: false, statusCode: 403 };
    }

    if (!isAllowedArtifact(normalized)) {
        return { ok: false, statusCode: 403 };
    }

    const resolvedDistPath = path.resolve(distPath);
    const filePath = path.resolve(resolvedDistPath, normalized);
    if (filePath !== resolvedDistPath && !filePath.startsWith(resolvedDistPath + path.sep)) {
        return { ok: false, statusCode: 403 };
    }

    return { ok: true, filePath };
}

function sendText(res, statusCode, body, extraHeaders = {}) {
    res.writeHead(statusCode, {
        'Content-Type': 'text/plain; charset=utf-8',
        'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff',
        ...extraHeaders,
    });
    res.end(body);
}

function createFileServer(options = {}) {
    const env = options.env || process.env;
    const distPath = options.distPath || env.DIST_PATH || DEFAULT_DIST_PATH;
    const secretKeyPath = options.secretKeyPath || env.FILE_KEY_PATH || DEFAULT_SECRET_KEY_PATH;
    const secretKey = options.secretKey || getConfiguredSecret(env) || generateSecret();
    const allowQueryKey = options.allowQueryKey !== undefined ? options.allowQueryKey : normalizeBoolean(env.ALLOW_QUERY_FILE_KEY);

    writeSecretKeyFile(secretKey, secretKeyPath);

    if (allowQueryKey && options.warn !== false) {
        const warn = options.warn || console.warn;
        warn('WARNING: ALLOW_QUERY_FILE_KEY=true enables deprecated insecure query-string file-server auth. Use Authorization: Bearer instead.');
    }

    const server = http.createServer((req, res) => {
        let requestUrl;
        try {
            requestUrl = new URL(req.url, 'http://file-server.local');
        } catch (error) {
            return sendText(res, 400, 'Bad Request');
        }

        if (req.method !== 'GET' && req.method !== 'HEAD') {
            return sendText(res, 405, 'Method Not Allowed', { Allow: 'GET, HEAD' });
        }

        const requestKey = getRequestKey(req, requestUrl, allowQueryKey);
        if (!timingSafeEqualString(requestKey, secretKey)) {
            return sendText(res, 401, 'Unauthorized');
        }

        const rawPathname = String(req.url || '').split(/[?#]/, 1)[0];
        const resolved = resolveArtifactPath(rawPathname, distPath);
        if (!resolved.ok) {
            return sendText(res, resolved.statusCode, 'Forbidden');
        }

        fs.readFile(resolved.filePath, (err, content) => {
            if (err) {
                if (err.code === 'ENOENT') {
                    return sendText(res, 404, 'Not Found');
                }

                return sendText(res, 500, 'Server Error');
            }

            res.writeHead(200, {
                'Content-Type': 'application/octet-stream',
                'Cache-Control': 'no-store',
                'X-Content-Type-Options': 'nosniff',
            });

            if (req.method === 'HEAD') {
                return res.end();
            }

            return res.end(content);
        });
    });

    return { server, secretKey, secretKeyPath, distPath, allowQueryKey };
}

function startServer(options = {}) {
    const port = options.port || process.env.FILE_SERVER_PORT || DEFAULT_PORT;
    const host = options.host !== undefined ? options.host : DEFAULT_HOST;
    const fileServer = createFileServer(options);

    fileServer.server.listen(port, host, () => {
        const boundHost = host || '0.0.0.0';
        console.log(`File server listening on ${boundHost}:${port} with header-based auth`);
    });

    return fileServer;
}

if (require.main === module) {
    startServer();
}

module.exports = {
    KEY_BYTES,
    createFileServer,
    extractBearerToken,
    generateSecret,
    isAllowedArtifact,
    resolveArtifactPath,
    startServer,
    timingSafeEqualString,
    writeSecretKeyFile,
};
