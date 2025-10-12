/* Copia del service worker para PWA - ubicado en web/ para Flutter dev */
self.addEventListener('push', function(event) {
  let data = {};
  try { data = event.data.json(); } catch (e) { data = { title: 'Notificación', body: event.data ? event.data.text() : '' }; }
  const title = data.title || 'Sala Chat';
  // Si el payload trae un marker y es tipo 'interes', preferir icono de estrella en el título
  let finalTitle = title;
  try {
    if (data.marker && (data.marker.tipoReporte === 'interes' || data.marker.tipoReporte === 'policia' || (data.title && data.title.toString().includes('⭐')))) {
      finalTitle = `⭐ ${title}`;
    }
  } catch (e) { /* ignore */ }

  const options = {
    body: data.body || '',
    data: data,
    icon: data.icon || '/icons/icon-192.png',
    badge: data.badge || '/icons/badge-72.png',
    // Intentar mantener la notificación visible hasta que el usuario la cierre
    requireInteraction: !!data.requireInteraction || true,
    // Si vienen instructions para renotify, usar tag para agrupar notificaciones; si no, no usar renotify
    renotify: !!data.renotify,
    tag: data.tag || (data.marker && data.marker.id) || `push-${Date.now()}`,
    // Vibración corta (solo en dispositivos que lo soporten)
    vibrate: data.vibrate || [100, 50, 100]
  };
  // Mostrar notificación y además notificar a todas las pestañas abiertas mediante postMessage
  event.waitUntil(
    (async function() {
      // Mostrar notificación al sistema
      await self.registration.showNotification(finalTitle, options);
      try {
        const allClients = await clients.matchAll({ includeUncontrolled: true, type: 'window' });
        for (const client of allClients) {
          // enviar el payload al contexto de la pestaña (será recibido por window.onmessage)
          client.postMessage({ type: 'push', payload: data });
        }
      } catch (e) {
        // Silenciar errores de postMessage para no romper la entrega
        console.error('Error broadcasting push to clients:', e);
      }
    })()
  );
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  const url = '/';
  event.waitUntil((async function() {
    try {
      const windowClients = await clients.matchAll({ type: 'window' });
      for (let i = 0; i < windowClients.length; i++) {
        const client = windowClients[i];
        // Intentar enfocar una pestaña existente
        if (client.url === url && 'focus' in client) {
          client.postMessage({ type: 'notificationclick', payload: event.notification.data });
          return client.focus();
        }
      }
      if (clients.openWindow) {
        const newClient = await clients.openWindow(url);
        if (newClient) newClient.postMessage({ type: 'notificationclick', payload: event.notification.data });
      }
    } catch (e) {
      console.error('Error handling notificationclick:', e);
    }
  })());
});
