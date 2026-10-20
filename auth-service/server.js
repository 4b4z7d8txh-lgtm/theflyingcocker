// -------------------------------------------------------------------------
// The Flying Cocker — single sign-on helper for the subdomains
// -------------------------------------------------------------------------
// A tiny server that runs on the VPS next to Nginx (127.0.0.1 only). It turns
// the Firebase login on www.theflyingcocker.co.uk into one secure cookie that
// is valid on every *.theflyingcocker.co.uk subdomain, and lets Nginx ask
// "is this visitor signed in?" before serving wf. / ob.
//
//   POST /auth/session   Called by the website right after sign-in, with the
//                        user's Firebase ID token. Sets the fc_session cookie.
//   POST /auth/logout    Clears the cookie (called on Sign out).
//   GET  /auth/verify    Used by Nginx `auth_request` on the subdomains:
//                          204 = signed in     -> let them in
//                          401 = not signed in -> send to the login page
//
// Every approved member gets the same access as on the main site; who is a
// member is still managed in Firebase console -> Authentication -> Users.
// -------------------------------------------------------------------------

'use strict';

const http = require('node:http');
const admin = require('firebase-admin');

const PORT = Number(process.env.PORT || 8787);
const COOKIE_NAME = 'fc_session';
const COOKIE_DOMAIN = process.env.COOKIE_DOMAIN || '.theflyingcocker.co.uk';
const ALLOWED_ORIGIN = process.env.ALLOWED_ORIGIN || 'https://www.theflyingcocker.co.uk';
// How long a sign-in stays valid on the server (Firebase allows 5 min – 14 days).
const SESSION_DAYS = Number(process.env.SESSION_DAYS || 5);

// Credentials come from GOOGLE_APPLICATION_CREDENTIALS (the service-account
// JSON file), set in the systemd unit.
admin.initializeApp({ credential: admin.credential.applicationDefault() });
const auth = admin.auth();

// Nginx asks /auth/verify on every request to a subdomain (including each
// image and script), so remember recent answers briefly instead of re-checking
// the same cookie hundreds of times a minute.
const VERIFY_CACHE_MS = 60 * 1000;
const verifyCache = new Map(); // cookie -> { claims, until }

function readCookie(req, name) {
  const header = req.headers.cookie || '';
  for (const part of header.split(';')) {
    const i = part.indexOf('=');
    if (i > -1 && part.slice(0, i).trim() === name) return part.slice(i + 1).trim();
  }
  return '';
}

function sessionCookie(value, maxAgeSeconds) {
  // No Max-Age on a real sign-in: like the website, it ends when the browser
  // closes. Max-Age=0 is used to delete it.
  return [
    `${COOKIE_NAME}=${value}`,
    `Domain=${COOKIE_DOMAIN}`,
    'Path=/',
    'HttpOnly',
    'Secure',
    'SameSite=Lax',
    ...(maxAgeSeconds === undefined ? [] : [`Max-Age=${maxAgeSeconds}`]),
  ].join('; ');
}

function send(res, status, body, headers = {}) {
  res.writeHead(status, { 'Cache-Control': 'no-store', ...headers });
  res.end(body === undefined ? undefined : JSON.stringify(body));
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => {
      data += chunk;
      if (data.length > 16 * 1024) { reject(new Error('too large')); req.destroy(); }
    });
    req.on('end', () => {
      try { resolve(JSON.parse(data || '{}')); } catch (e) { reject(e); }
    });
    req.on('error', reject);
  });
}

async function verifyCookie(cookie) {
  const hit = verifyCache.get(cookie);
  if (hit && hit.until > Date.now()) return hit.claims;
  const claims = await auth.verifySessionCookie(cookie, true /* honour revocations */);
  verifyCache.set(cookie, { claims, until: Date.now() + VERIFY_CACHE_MS });
  if (verifyCache.size > 500) verifyCache.delete(verifyCache.keys().next().value);
  return claims;
}

async function handle(req, res) {
  const path = (req.url || '').split('?')[0];

  if (req.method === 'GET' && path === '/auth/verify') {
    const cookie = readCookie(req, COOKIE_NAME);
    if (!cookie) return send(res, 401);
    let claims;
    try {
      claims = await verifyCookie(cookie);
    } catch (e) {
      return send(res, 401);
    }
    return send(res, 204, undefined, { 'X-Auth-Email': claims.email || '' });
  }

  // The two cookie-changing endpoints only accept calls from the website itself.
  if (req.method === 'POST' && req.headers.origin !== ALLOWED_ORIGIN) {
    return send(res, 403, { error: 'origin' });
  }

  if (req.method === 'POST' && path === '/auth/session') {
    let idToken;
    try {
      ({ idToken } = await readJson(req));
      if (typeof idToken !== 'string' || !idToken) throw new Error('missing');
    } catch (e) {
      return send(res, 400, { error: 'bad request' });
    }
    try {
      await auth.verifyIdToken(idToken, true);
      const value = await auth.createSessionCookie(idToken, {
        expiresIn: SESSION_DAYS * 24 * 60 * 60 * 1000,
      });
      return send(res, 200, { ok: true }, {
        'Content-Type': 'application/json',
        'Set-Cookie': sessionCookie(value),
      });
    } catch (e) {
      return send(res, 401, { error: 'invalid token' });
    }
  }

  if (req.method === 'POST' && path === '/auth/logout') {
    const cookie = readCookie(req, COOKIE_NAME);
    if (cookie) verifyCache.delete(cookie);
    return send(res, 204, undefined, { 'Set-Cookie': sessionCookie('', 0) });
  }

  return send(res, 404);
}

http.createServer((req, res) => {
  handle(req, res).catch((err) => {
    console.error(err);
    if (!res.headersSent) send(res, 500);
  });
}).listen(PORT, '127.0.0.1', () => {
  console.log(`fc-auth listening on 127.0.0.1:${PORT}`);
});
