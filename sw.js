/* Service worker de DC EVENT COMMANDE.
   L'application tient dans un seul fichier : on le met en cache à
   l'installation, puis on sert le cache d'abord. Une fois installée sur le
   téléphone, elle fonctionne sans réseau — ce qui compte au dépôt.
   Changer CACHE à chaque nouvelle version pour forcer la mise à jour. */
const CACHE = 'dc-event-v1';
const FICHIERS = [
  './',
  './index.html',
  './manifest.webmanifest',
  './icone-192.png',
  './icone-512.png',
  './icone-maskable-512.png'
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(FICHIERS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(cles => Promise.all(cles.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  e.respondWith(
    caches.match(e.request).then(reponse => {
      if (reponse) return reponse;
      return fetch(e.request).then(reseau => {
        // On garde une copie des ressources de même origine pour les visites suivantes
        if (reseau.ok && new URL(e.request.url).origin === location.origin) {
          const copie = reseau.clone();
          caches.open(CACHE).then(c => c.put(e.request, copie));
        }
        return reseau;
      }).catch(() => caches.match('./index.html'));
    })
  );
});
