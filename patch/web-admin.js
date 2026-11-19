'use strict';

const { randomBytes, timingSafeEqual } = require('node:crypto');

function csrf(req, res, next) {
    const safe = req.method === 'GET' || req.method === 'HEAD' || req.method === 'OPTIONS';
    if (safe) {
        if (req.method === 'GET' && (req.session.user || /^\/login\/?$/i.test(req.path))) {
            req.session.csrf ??= randomBytes(32).toString('base64url');
        }
    } else {
        const sent = req.get('X-CSRF-Token') || req.body?._csrf;
        const expected = req.session.csrf;
        if (typeof sent !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(sent) || !expected ||
            !timingSafeEqual(Buffer.from(sent), Buffer.from(expected))) {
            return res.status(403).send('Invalid form token. Reload the page and try again.');
        }
    }
    res.locals.csrfToken = req.session.csrf;
    next();
}

function asyncRoute(handler) {
    return (req, res, next) => Promise.resolve(handler(req, res, next)).catch(next);
}

module.exports = { csrf, asyncRoute };
