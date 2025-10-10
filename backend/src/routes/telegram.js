const express = require('express');
const router = express.Router();
const telegramStore = require('../config/telegram_store');
const telegramService = require('../services/telegramService');

// Registrar chat_id para userId (body: { userId, chatId })
router.post('/register', (req, res) => {
  try {
    const { userId, chatId } = req.body;
    if (!userId || !chatId) return res.status(400).json({ error: 'userId y chatId son requeridos' });
    // persistente (db)
    telegramStore.add(userId, chatId).then(() => {
      return res.json({ ok: true });
    }).catch(e => {
      console.error('telegram register error', e);
      return res.status(500).json({ error: e.message });
    });
  } catch (e) {
    console.error('telegram register error', e);
    return res.status(500).json({ error: e.message });
  }
});

// Endpoint para enviar notificación a un usuario (body: { userId, text })
router.post('/notify', async (req, res) => {
  try {
    const { userId, text } = req.body;
    if (!userId || !text) return res.status(400).json({ error: 'userId y text son requeridos' });
    let chatId = await telegramStore.getByUser(userId);
    let usedFallback = false;
    if (!chatId) {
      // intentar fallback desde env
      chatId = process.env.TELEGRAM_FALLBACK_CHAT_ID || null;
      // si no hay en env, intentar leer archivo de integracion
      if (!chatId) {
        try {
          const p = require('path').join(__dirname, '..', '..', 'telegram_integration.txt');
          const fs = require('fs');
          if (fs.existsSync(p)) {
            const content = fs.readFileSync(p, 'utf8').trim();
            // si el archivo contiene solo numeros (chat id) usarlo
            if (/^\d+$/.test(content)) chatId = content;
          }
        } catch (e) {
          console.error('read fallback chat id error', e);
        }
      }
      if (chatId) usedFallback = true;
    }

    if (!chatId) return res.status(404).json({ error: 'chat_id no encontrado para el userId' });

    if (usedFallback) console.log(`telegram notify: using fallback chatId=${chatId} for userId=${userId}`);
    const result = await telegramService.sendMessage(chatId, text);
    return res.json({ ok: true, result, usedFallback });
  } catch (e) {
    console.error('telegram notify error', e);
    return res.status(500).json({ error: e.message });
  }
});

// Listar registros (debug)
router.get('/list', (req, res) => {
  try {
    telegramStore.list().then(list => res.json(list)).catch(e => res.status(500).json({ error: e.message }));
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

module.exports = router;
