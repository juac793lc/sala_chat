const express = require('express');
const router = express.Router();
const push = require('../controllers/pushController');

// Devolver clave pública VAPID para que el cliente se suscriba
router.get('/vapidPublicKey', push.getVapidPublicKey);

// Registrar suscripción
router.post('/subscribe', push.subscribe);

// Desregistrar suscripción
router.post('/unsubscribe', push.unsubscribe);

// Endpoint de prueba para enviar push a todas las subscripciones (dev)
router.post('/send-test', async (req, res) => {
  try {
    const { title = 'Test', body = 'Mensaje de prueba' } = req.body;
    const subs = await require('../config/sqlite_db').listPushSubscriptionsNear();
    const payload = { title, body, timestamp: Date.now() };
    // Reconstruir objeto subscription mínimo para web-push
    const rebuilt = subs.map(s => ({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }));
    const results = await push.sendPushToSubscriptions(rebuilt, payload);
    res.json({ sent: results.length, results });
  } catch (e) {
    console.error('❌ send-test error:', e.message || e);
    res.status(500).json({ error: 'internal' });
  }
});

module.exports = router;
