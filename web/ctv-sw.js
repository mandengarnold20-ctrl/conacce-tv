// Conacce TV — réserve hors connexion (étape 4).
// - Les programmes de la chaîne (vidéos Cloudflare) sont téléchargés à l'avance, en arrière-plan,
//   puis lus depuis le téléphone : plus de coupure quand le réseau faiblit, lecture possible sans internet.
// - Les programmes qui ne sont plus prévus sont effacés pour libérer la place.
// - L'appli elle-même (pages, logo, polices) est gardée pour s'ouvrir même sans connexion.
// La régie (/admin/) et la base de données passent toujours par internet.

const VCACHE = 'ctv-video-v1';
const SCACHE = 'ctv-shell-v2';
const INDEX_URL = new URL('__ctv_index__', self.registration.scope).href;
const VIDEO_HOST = /(^|\.)videodelivery\.net$|\.cloudflarestream\.com$/;
const CDN_HOST = /(^|\.)gstatic\.com$|^fonts\.googleapis\.com$|^cdn\.jsdelivr\.net$/;

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(
  caches.keys().then((k) => Promise.all(k.filter((n) => n.startsWith('ctv-shell-') && n !== SCACHE).map((n) => caches.delete(n))))
    .then(() => self.clients.claim())
));

const uidOf = (u) => (u.pathname.match(/[0-9a-f]{32}/) || [])[0] || null;

// ── Index : quels fichiers appartiennent à quel programme ──
let index = null; // { progs: { [uid]: [urls] } }
async function loadIndex() {
  if (index) return index;
  try {
    const r = await (await caches.open(VCACHE)).match(INDEX_URL);
    index = r ? await r.json() : { progs: {} };
  } catch (e) { index = { progs: {} }; }
  if (!index.progs) index.progs = {};
  return index;
}
async function saveIndex() {
  const c = await caches.open(VCACHE);
  await c.put(INDEX_URL, new Response(JSON.stringify(index), { headers: { 'Content-Type': 'application/json' } }));
}

// ── Lecture ──
self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  let u;
  try { u = new URL(req.url); } catch (x) { return; }
  if (VIDEO_HOST.test(u.hostname)) { e.respondWith(videoFetch(req, u)); return; }
  if (u.origin === self.location.origin) {
    if (u.pathname.includes('/admin/') || u.pathname.endsWith('ctv-sw.js')) return;
    e.respondWith(networkFirst(req));
    return;
  }
  if (CDN_HOST.test(u.hostname)) e.respondWith(cacheFirst(req));
});

async function networkFirst(req) {
  const c = await caches.open(SCACHE);
  const fromCache = async () => {
    const hit = await c.match(req, { ignoreSearch: true });
    if (hit) return hit;
    if (req.mode === 'navigate') {
      return (await c.match(new URL('./', self.registration.scope).href, { ignoreSearch: true }))
        || (await c.match(new URL('index.html', self.registration.scope).href, { ignoreSearch: true }));
    }
    return null;
  };
  try {
    // Ouverture de l'appli : la page passe telle quelle (iPhone compris). Les fichiers de l'appli
    // sont toujours vérifiés auprès du site : une nouvelle version arrive dès l'ouverture.
    let net;
    if (req.mode === 'navigate') net = fetch(req);
    else net = fetch(req.url, { cache: 'no-cache', credentials: 'same-origin' }).catch(() => fetch(req));
    // Réseau très lent : au bout de 12 s, on ouvre la copie gardée (si elle existe).
    const r = await Promise.race([
      net,
      new Promise((res) => setTimeout(() => fromCache().then((h) => h && res(h)), 12000)),
    ]);
    if (r && r.ok && r.type === 'basic') c.put(req, r.clone()).catch(() => {});
    return r;
  } catch (e) {
    const hit = await fromCache();
    if (hit) return hit;
    return fetch(req);
  }
}
async function cacheFirst(req) {
  const c = await caches.open(SCACHE);
  const hit = await c.match(req);
  if (hit) return hit;
  const r = await fetch(req);
  if (r && (r.ok || r.type === 'opaque')) c.put(req, r.clone()).catch(() => {});
  return r;
}

function parseRange(h, size) {
  const m = /bytes=(\d*)-(\d*)/.exec(h || '');
  if (!m) return null;
  let a = m[1] === '' ? null : +m[1], b = m[2] === '' ? null : +m[2];
  if (a === null) { a = Math.max(0, size - b); b = size - 1; }
  if (b === null || b >= size) b = size - 1;
  return a <= b ? [a, b] : null;
}

async function videoFetch(req, u) {
  const c = await caches.open(VCACHE);
  const key = u.href;
  const range = req.headers.get('range');
  const isManifest = /\.m3u8$/.test(u.pathname);
  const hit = await c.match(key);
  if (hit && !isManifest) {
    if (!range) return hit;
    const blob = await hit.blob();
    const r = parseRange(range, blob.size);
    if (!r) return hit;
    return new Response(blob.slice(r[0], r[1] + 1), {
      status: 206,
      headers: {
        'Content-Type': hit.headers.get('Content-Type') || 'video/mp4',
        'Content-Range': `bytes ${r[0]}-${r[1]}/${blob.size}`,
        'Content-Length': String(r[1] - r[0] + 1),
        'Accept-Ranges': 'bytes',
      },
    });
  }
  try {
    const net = await fetch(req);
    // Les programmes prévus se gardent aussi pendant qu'on les regarde (la boucle repasse).
    if (net.ok && net.status === 200 && !range) {
      const idx = await loadIndex();
      const uid = uidOf(u);
      if (uid && idx.progs[uid]) {
        c.put(key, net.clone()).catch(() => {});
        if (!idx.progs[uid].includes(key)) { idx.progs[uid].push(key); }
      }
    }
    return net;
  } catch (e) {
    if (hit) return hit; // liste de lecture gardée : lecture hors connexion
    throw e;
  }
}

// ── Téléchargement à l'avance ──
let planId = 0;
let status = { ready: 0, total: 0, mb: 0, busy: false, current: '' };

function broadcast() {
  self.clients.matchAll({ includeUncontrolled: true }).then((cs) => cs.forEach((cl) => cl.postMessage({ type: 'ctv-offline', status })));
}

function attr(line, name) {
  const m = new RegExp(name + '="([^"]+)"').exec(line);
  return m ? m[1] : null;
}

async function getText(c, url) {
  const r = await fetch(url, { mode: 'cors', credentials: 'omit' });
  if (!r.ok) throw new Error('HTTP ' + r.status);
  await c.put(url, r.clone());
  return r.text();
}

// Toutes les adresses à garder pour un programme : liste principale, liste de la qualité choisie,
// son, segments vidéo.
async function collect(c, master) {
  const urls = [master];
  const text = await getText(c, master);
  const lines = text.split(/\r?\n/);
  const media = [];
  let best = null, bestBw = Infinity;
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i].trim();
    if (l.startsWith('#EXT-X-STREAM-INF')) {
      const bw = +((/BANDWIDTH=(\d+)/.exec(l) || [])[1] || 0);
      const next = (lines[i + 1] || '').trim();
      // Qualité téléphone : la plus proche de 1,5 Mb/s (≈ 480p).
      const d = Math.abs(bw - 1500000);
      if (next && !next.startsWith('#') && d < bestBw) { bestBw = d; best = new URL(next, master).href; }
    } else if (l.startsWith('#EXT-X-MEDIA') && /TYPE=AUDIO/.test(l)) {
      const uri = attr(l, 'URI');
      if (uri && !media.some((x) => x.audio)) media.push({ url: new URL(uri, master).href, audio: true });
    }
  }
  if (best) media.unshift({ url: best });
  if (!best && !media.length) media.push({ url: master, self: true });
  for (const m of media) {
    const t = m.self ? text : await getText(c, m.url);
    if (!m.self) urls.push(m.url);
    for (const raw of t.split(/\r?\n/)) {
      const l = raw.trim();
      if (!l) continue;
      if (l.startsWith('#EXT-X-MAP')) { const uri = attr(l, 'URI'); if (uri) urls.push(new URL(uri, m.url).href); continue; }
      if (l.startsWith('#')) continue;
      urls.push(new URL(l, m.url).href);
    }
  }
  return [...new Set(urls)];
}

async function plan(items, myId) {
  const c = await caches.open(VCACHE);
  const idx = await loadIndex();
  const keep = new Set(items.map((it) => uidOf(new URL(it.url))).filter(Boolean));
  // Nettoyage : programmes qui ne sont plus prévus.
  for (const uid of Object.keys(idx.progs)) {
    if (keep.has(uid)) continue;
    for (const url of idx.progs[uid]) await c.delete(url).catch(() => {});
    delete idx.progs[uid];
  }
  for (const uid of keep) if (!idx.progs[uid]) idx.progs[uid] = [];
  await saveIndex();
  status = { ready: 0, total: items.length, mb: 0, busy: true, current: '' };
  broadcast();
  for (const it of items) {
    if (myId !== planId) return;
    const uid = uidOf(new URL(it.url));
    if (!uid) continue;
    status.current = it.title || '';
    broadcast();
    try {
      // Place disponible : on s'arrête avant de remplir le téléphone.
      if (self.navigator.storage && self.navigator.storage.estimate) {
        const est = await self.navigator.storage.estimate();
        if (est.quota && est.usage > est.quota * 0.8) break;
      }
      const urls = await collect(c, it.url);
      for (const url of urls) {
        if (myId !== planId) return;
        if (/\.m3u8(\?|$)/.test(url)) continue; // déjà rangées par collect()
        if (await c.match(url)) continue;
        const r = await fetch(url, { mode: 'cors', credentials: 'omit' });
        if (!r.ok) throw new Error('HTTP ' + r.status);
        status.mb += (+r.headers.get('Content-Length') || 0) / 1048576;
        await c.put(url, r); // rangé directement, sans tout charger en mémoire
      }
      // Ce qui avait été gardé pour ce programme dans une autre qualité est effacé.
      const want = new Set(urls);
      for (const old of idx.progs[uid] || []) if (!want.has(old)) await c.delete(old).catch(() => {});
      idx.progs[uid] = urls;
      await saveIndex();
      status.ready++;
      broadcast();
    } catch (e) {
      // Pas de réseau ou programme pas encore prêt : on réessaiera au prochain plan.
      // (Déjà téléchargé lors d'une visite précédente : il compte comme prêt.)
      if (idx.progs[uid] && idx.progs[uid].length > 3) { status.ready++; broadcast(); }
    }
  }
  status.busy = false;
  status.current = '';
  broadcast();
}

self.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.type === 'ctv-plan' && Array.isArray(d.items)) {
    const myId = ++planId;
    e.waitUntil(plan(d.items, myId));
  } else if (d.type === 'ctv-status') {
    broadcast();
  }
});
