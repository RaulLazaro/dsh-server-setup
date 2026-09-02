'use strict';
// Reverse proxy core: HTTP + WebSocket with Basic Auth, Origin alignment,
// crypto.randomUUID polyfill injection (HTML), and DSH loopback trust patch (JS).
// Adapted from https://github.com/smanx/dsh-proxy (MIT license)
const http = require('http');
const os = require('os');
const httpProxy = require('http-proxy');
const crypto = require('crypto');

const AUTH_REALM = 'dsh-proxy';

// crypto.randomUUID polyfill.
// DSH frontend uses crypto.randomUUID() for rpcId, but this API is only available
// in secure contexts (HTTPS/localhost). When accessed via LAN IP, the page is a
// non-secure context and randomUUID is undefined → RPC requests fail → WebSocket
// can't establish. This polyfill injects a compatible implementation using
// getRandomValues() (available in non-secure contexts).
const POLYFILL = '<script>(function(){try{if(typeof crypto!=="undefined"&&crypto&&typeof crypto.randomUUID!=="function"){crypto.randomUUID=function(){var b=crypto.getRandomValues(new Uint8Array(16));b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;var h="";for(var i=0;i<16;i++){h+=b[i].toString(16).padStart(2,"0")}return h.slice(0,8)+"-"+h.slice(8,12)+"-"+h.slice(12,16)+"-"+h.slice(16,20)+"-"+h.slice(20)}}}catch(e){}})();</script>';

// DSH client loopback trust patch.
// The frontend checks location.hostname to determine if the browser is local.
// Non-loopback hosts get degraded behavior (memory-only mode, settings unavailable).
// Since hostname can't be faked via HTML injection, we patch the served JS to treat
// proxied connections as loopback, enabling full functionality.
const LOOPBACK_PATCHES = [
  {
    needle: 'isLoopback: pageLocation === void 0 || isLoopbackHostname(pageLocation.hostname),',
    replacement: 'isLoopback: true,',
  },
  {
    needle: 'connection.isLoopback ? "host" : "memory"',
    replacement: '"host"',
  },
];

function isJavaScriptContentType(ct) {
  return String(ct || '').toLowerCase().includes('javascript');
}

function patchClientScript(code) {
  let out = code;
  for (const { needle, replacement } of LOOPBACK_PATCHES) {
    if (!out.includes(needle)) continue;
    out = out.split(needle).join(replacement);
  }
  return out;
}

/**
 * Start the reverse proxy.
 * @param {object} opts
 * @param {number} opts.listenPort  Proxy listen port
 * @param {number} opts.dshPort     Upstream DSH port (127.0.0.1)
 * @param {string} [opts.username]  Basic Auth username (empty = no auth)
 * @param {string} [opts.password]  Basic Auth password (empty = no auth)
 * @returns {http.Server}
 */
function startProxy({ listenPort, dshPort, username = '', password = '', host = '0.0.0.0' }) {
  const TARGET_ORIGIN = `http://127.0.0.1:${dshPort}`;
  const AUTH_USER = String(username);
  const AUTH_PASS = String(password);

  // Public static paths served without auth (PWA manifest, icons).
  // Browsers fetching <link rel="manifest"> don't send Basic Auth credentials,
  // so these paths must be whitelisted to avoid 401 errors.
  const PUBLIC_PATHS = new Set(['/manifest.webmanifest', '/favicon.svg', '/favicon.ico']);

  function safeEqual(a, b) {
    const ba = Buffer.from(String(a));
    const bb = Buffer.from(String(b));
    return ba.length === bb.length && crypto.timingSafeEqual(ba, bb);
  }

  function checkAuth(req) {
    if (!AUTH_USER || !AUTH_PASS) return true;
    const m = /^Basic\s+(.+)$/i.exec(req.headers.authorization || '');
    if (!m) return false;
    let decoded;
    try {
      decoded = Buffer.from(m[1], 'base64').toString('utf8');
    } catch {
      return false;
    }
    const i = decoded.indexOf(':');
    if (i === -1) return false;
    return safeEqual(decoded.slice(0, i), AUTH_USER) && safeEqual(decoded.slice(i + 1), AUTH_PASS);
  }

  function rejectUnauthorized(res) {
    res.writeHead(401, {
      'WWW-Authenticate': `Basic realm="${AUTH_REALM}"`,
      'Content-Type': 'text/plain; charset=utf-8',
    });
    res.end('401 Unauthorized');
  }

  function rejectUpgrade(socket) {
    socket.end(`HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm="${AUTH_REALM}"\r\nConnection: close\r\n\r\n`);
  }

  const proxy = httpProxy.createProxyServer({
    target: TARGET_ORIGIN,
    ws: true,
    changeOrigin: true,
  });

  // HTML: inject randomUUID polyfill; JS: apply loopback trust patch.
  proxy.on('proxyRes', (proxyRes, req, res) => {
    const ct = String(proxyRes.headers['content-type'] || '');
    if (proxyRes.headers['content-encoding']) return;
    if (ct.includes('text/html')) {
      delete proxyRes.headers['content-length'];
      res.removeHeader('content-length');
      let injected = false;
      const origWrite = res.write.bind(res);
      res.write = function (chunk, ...rest) {
        if (!injected) {
          injected = true;
          let str = Buffer.isBuffer(chunk) ? chunk.toString('utf8') : String(chunk);
          const i = str.toLowerCase().indexOf('<head');
          if (i !== -1) {
            const e = str.indexOf('>', i);
            str = e !== -1 ? str.slice(0, e + 1) + POLYFILL + str.slice(e + 1) : POLYFILL + str;
          } else {
            str = POLYFILL + str;
          }
          chunk = Buffer.from(str);
        }
        return origWrite(chunk, ...rest);
      };
      return;
    }
    if (!isJavaScriptContentType(ct)) return;
    delete proxyRes.headers['content-length'];
    res.removeHeader('content-length');
    const chunks = [];
    const capture = (chunk) => {
      const part =
        typeof chunk === 'string'
          ? Buffer.from(chunk, 'utf8')
          : ArrayBuffer.isView(chunk) || chunk instanceof ArrayBuffer
            ? Buffer.from(chunk)
            : null;
      if (part !== null) chunks.push(part);
    };
    const origWrite = res.write.bind(res);
    const origEnd = res.end.bind(res);
    let ended = false;
    res.write = function (chunk) {
      capture(chunk);
      return true;
    };
    res.end = function (chunk, ...rest) {
      if (ended) return;
      ended = true;
      if (chunk !== undefined && chunk !== null && typeof chunk !== 'function') capture(chunk);
      const callback = [chunk, ...rest].find((arg) => typeof arg === 'function');
      const out = Buffer.from(patchClientScript(Buffer.concat(chunks).toString('utf8')));
      return callback === undefined ? origEnd(out) : origEnd(out, callback);
    };
  });

  // Align Origin header with target to pass DSH's same-origin checks.
  function alignOrigin(req) {
    if (req.headers.origin) req.headers.origin = TARGET_ORIGIN;
  }

  const server = http.createServer((req, res) => {
    const pathname = new URL(req.url ?? '/', 'http://proxy').pathname;
    if (!PUBLIC_PATHS.has(pathname) && !checkAuth(req)) {
      rejectUnauthorized(res);
      return;
    }
    alignOrigin(req);
    proxy.web(req, res);
  });

  server.on('upgrade', (req, socket, head) => {
    if (!checkAuth(req)) {
      rejectUpgrade(socket);
      return;
    }
    alignOrigin(req);
    proxy.ws(req, socket, head);
  });

  server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
      console.error(`Error: port ${listenPort} is already in use.`);
    } else if (err.code === 'EACCES') {
      console.error(`Error: no permission to listen on port ${listenPort}.`);
    } else {
      console.error(`Proxy failed to start: ${err.message}`);
    }
    process.exitCode = 1;
  });

  server.listen(listenPort, host, () => {
    const authText = AUTH_USER && AUTH_PASS ? `Basic Auth enabled (user: ${AUTH_USER})` : 'No auth';
    console.log(`Proxy listening on 0.0.0.0:${listenPort} → ${TARGET_ORIGIN} (${authText})`);
    console.log(`Local:    http://127.0.0.1:${listenPort}`);
    const nets = os.networkInterfaces();
    const ips = [];
    for (const name of Object.keys(nets)) {
      for (const net of nets[name] || []) {
        if (net.family === 'IPv4' && !net.internal) ips.push(net.address);
      }
    }
    for (const ip of ips) console.log(`Network:  http://${ip}:${listenPort}`);
  });

  return server;
}

module.exports = { startProxy };
