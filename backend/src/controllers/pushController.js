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
    console.warn('⚠️ Error enviando push:', e.statusCode || e.code || e.message || e);
    return false;
  }
}

// Enviar notificaciones a subscripciones cercanas: se espera una lista de subscription objects ya construidos
async function sendPushToSubscriptions(subscriptions, payload) {
  const results = [];
  for (const sub of subscriptions) {
    try {
      const ok = await sendPushToSubscription(sub, payload);
      results.push({ endpoint: sub.endpoint, ok });
    } catch (e) {
      results.push({ endpoint: sub.endpoint, ok: false, error: e.message || e });
    }
  }
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
