/* Service Worker de ejemplo para PWA - push notifications */
self.addEventListener('push', function(event) {
  let data = {};
  try { data = event.data.json(); } catch (e) { data = { title: 'Notificación', body: event.data ? event.data.text() : '' }; }
  const title = data.title || 'Sala Chat';
  const options = {
    body: data.body || '',
    data: data,
    icon: '/icons/icon-192.png',
    badge: '/icons/badge-72.png'
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  const url = '/';
  event.waitUntil(clients.matchAll({ type: 'window' }).then(windowClients => {
    for (let i = 0; i < windowClients.length; i++) {
      const client = windowClients[i];
      if (client.url === url && 'focus' in client) return client.focus();
    }
    if (clients.openWindow) return clients.openWindow(url);
  }));
});
