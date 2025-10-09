const webpush = require('web-push');
const { v4: uuidv4 } = require('uuid');
const sqlite = require('../config/sqlite_db');

// Generar claves VAPID dev si no existen en env
let VAPID_PUBLIC = process.env.VAPID_PUBLIC || null;
let VAPID_PRIVATE = process.env.VAPID_PRIVATE || null;

if (!VAPID_PUBLIC || !VAPID_PRIVATE) {
  // Generar claves dev (no seguras para producción)
  try {
    const keys = webpush.generateVAPIDKeys();
    VAPID_PUBLIC = keys.publicKey;
    VAPID_PRIVATE = keys.privateKey;
    console.log('🔐 VAPID dev keys generadas automáticamente (usar propias en producción)');
  } catch (e) {
    console.error('❌ No se pudieron generar claves VAPID:', e.message || e);
  }
}

webpush.setVapidDetails(
  'mailto:dev@sala-chat.local',
  VAPID_PUBLIC,
  VAPID_PRIVATE
);

async function getVapidPublicKey(req, res) {
  res.json({ publicKey: VAPID_PUBLIC });
}

async function subscribe(req, res) {
  try {
    const { subscription, userId } = req.body;
    if (!subscription || !subscription.endpoint) return res.status(400).json({ error: 'subscription missing' });
    await sqlite.insertPushSubscription({ user_id: userId || null, endpoint: subscription.endpoint, p256dh: subscription.keys?.p256dh || null, auth: subscription.keys?.auth || null });
    res.json({ success: true });
  } catch (e) {
    console.error('❌ subscribe error:', e.message || e);
    res.status(500).json({ error: 'internal' });
  }
}

async function unsubscribe(req, res) {
  try {
    const { endpoint } = req.body;
    if (!endpoint) return res.status(400).json({ error: 'endpoint missing' });
    await sqlite.removePushSubscription(endpoint);
    res.json({ success: true });
  } catch (e) {
    console.error('❌ unsubscribe error:', e.message || e);
    res.status(500).json({ error: 'internal' });
  }
}

// Enviar push a una subscription (objeto subscription como en Push API)
async function sendPushToSubscription(subscription, payload) {
  try {
    await webpush.sendNotification(subscription, JSON.stringify(payload));
    return true;
  } catch (e) {
    // 410 Gone o 404 indicarían que la suscripción no es válida
    const status = e.statusCode || e.code || (e && e.body && e.body.status) || null;
    console.warn('⚠️ Error enviando push:', status || e.message || e);
    try {
      if (status === 410 || status === 404 || status === 403) {
        // Intentar extraer endpoint del objeto subscription para eliminar
        const endpoint = subscription && subscription.endpoint ? subscription.endpoint : null;
        if (endpoint) {
          console.log('🧹 Eliminando suscripción inválida:', endpoint);
          await sqlite.removePushSubscription(endpoint);
        }
      }
    } catch (cleanupErr) {
      console.warn('⚠️ Error limpiando suscripción inválida:', cleanupErr.message || cleanupErr);
    }
    return false;
  }
}

// Enviar notificaciones a subscripciones cercanas: se espera una lista de subscription objects ya construidos
async function sendPushToSubscriptions(subscriptions, payload) {
  const results = [];
  // Deduplicate: prefer one subscription per p256dh (client key) and fall back to endpoint
  const seenEndpoints = new Set();
  const seenKeys = new Set();
  const uniqueSubs = [];

  // First pass: prefer unique p256dh
  for (const sub of subscriptions) {
    if (!sub || !sub.endpoint) continue;
    const key = sub.keys && sub.keys.p256dh ? sub.keys.p256dh : null;
    if (key) {
      if (seenKeys.has(key)) continue; // already have a subscription for this client key
      seenKeys.add(key);
      seenEndpoints.add(sub.endpoint);
      uniqueSubs.push(sub);
    }
  }

  // Second pass: add remaining subscriptions by endpoint if not already included
  for (const sub of subscriptions) {
    if (!sub || !sub.endpoint) continue;
    if (seenEndpoints.has(sub.endpoint)) continue;
    seenEndpoints.add(sub.endpoint);
    uniqueSubs.push(sub);
  }

  if (uniqueSubs.length !== subscriptions.length) {
    console.log(`🔍 PushController: reducidas ${subscriptions.length - uniqueSubs.length} suscripciones para evitar duplicados (endpoint/p256dh)`);
  }

  for (const sub of uniqueSubs) {
    try {
      const ok = await sendPushToSubscription(sub, payload);
      results.push({ endpoint: sub.endpoint, ok });
    } catch (e) {
      results.push({ endpoint: sub.endpoint, ok: false, error: e.message || e });
    }
  }
  console.log(`📬 PushController: enviados ${results.filter(r=>r.ok).length}/${results.length} pushes únicos`);
  return results;
}

module.exports = {
  getVapidPublicKey,
  subscribe,
  unsubscribe,
  sendPushToSubscription,
  sendPushToSubscriptions,
  VAPID_PUBLIC,
  VAPID_PRIVATE
};
