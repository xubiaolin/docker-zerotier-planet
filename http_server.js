const http = require('http');
const fs = require('fs');
const path = require('path');
const url = require('url');
const crypto = require('crypto');
const port = process.env.FILE_SERVER_PORT;

const SECRET_KEY = process.env.SECRET_KEY || crypto.randomBytes(8).toString('hex');
const APP_PATH='/app'
const DIST_PATH = '/app/dist'

// write to file
const secretKeyPath = '/app/config/file_server.key';
fs.writeFile(secretKeyPath, SECRET_KEY, (err) => {
    if (err) {
        console.error('Error writing SECRET_KEY to file:', err);
    } else {
        console.log(`SECRET_KEY written to ${secretKeyPath}`);
    }
});

const server = http.createServer((req, res) => {
    const parsedUrl = url.parse(req.url, true);

    // check key
    const key = parsedUrl.query.key;
    if (!key || key !== SECRET_KEY) {
        res.writeHead(401, { 'Content-Type': 'text/plain' });
        return res.end('Unauthorized');
    }

    let filePath = path.join(DIST_PATH, parsedUrl.pathname);
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
            if (err.code == 'ENOENT') {
                res.writeHead(404, { 'Content-Type': 'text/html' });
                res.end("404 - File Not Found");
            } else {
                res.writeHead(500);
                res.end(`Server Error: ${err.code}`);
            }
        } else {
            res.writeHead(200, { 'Content-Type': contentType });
            res.end(content, 'utf-8');
        }
    });
});

server.listen(port, () => {
    console.log(`Server running at http://localhost:${port}/`);
});
