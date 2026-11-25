// Réserve hors connexion mise en pause : ce fichier retire l'ancien module des téléphones
// (il ne touche plus à aucune page ni vidéo) puis se désinstalle.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(
  caches.keys()
    .then((k) => Promise.all(k.filter((n) => n.startsWith('ctv-')).map((n) => caches.delete(n))))
    .then(() => self.registration.unregister())
    .then(() => self.clients.matchAll({ type: 'window' }))
    .then((cs) => cs.forEach((c) => { try { c.navigate(c.url); } catch (x) {} }))
));
