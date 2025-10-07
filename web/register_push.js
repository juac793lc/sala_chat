// register_push.js - helper para registrar service worker y suscribirse a Push
async function registerAndSubscribe(vapidPublicKey) {
  if (!('serviceWorker' in navigator)) throw new Error('Service Worker no soportado');
  if (!('PushManager' in window)) throw new Error('Push API no soportada');

  const registration = await navigator.serviceWorker.register('/push_worker.js');
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') throw new Error('Permiso de notificaciones denegado');

  // Convertir clave VAPID base64url a Uint8Array
  function urlBase64ToUint8Array(base64String) {
    const padding = '='.repeat((4 - base64String.length % 4) % 4);
    const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    const rawData = window.atob(base64);
    const outputArray = new Uint8Array(rawData.length);
    for (let i = 0; i < rawData.length; ++i) {
      outputArray[i] = rawData.charCodeAt(i);
    }
    return outputArray;
  }

  const sub = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(vapidPublicKey)
  });

  // Devolver el objeto de suscripción serializable
  return sub.toJSON();
}

// Exponer la función globalmente para que Dart pueda llamarla
window.registerAndSubscribe = registerAndSubscribe;
