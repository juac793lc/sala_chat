const express = require('express');
const router = express.Router();
const telegramStore = require('../config/telegram_store');
const telegramService = require('../services/telegramService');
const sqlite = require('../config/sqlite_db');
const fs = require('fs');
const path = require('path');
const { auth } = require('../middleware/auth');
const { v4: uuidv4 } = require('uuid');

// BOT secret header to protect confirm endpoint
const BOT_SECRET = process.env.BOT_SECRET || 'dev-bot-secret';

// Helper: resolver chat id de fallback (env var -> archivo). Preferir IDs negativos (grupos).
async function resolveFallbackChatId() {
  let chatId = process.env.TELEGRAM_FALLBACK_CHAT_ID || null;
  if (chatId) return chatId;
  try {
    const p = require('path').join(__dirname, '..', '..', 'telegram_integration.txt');
    const fs = require('fs');
    if (fs.existsSync(p)) {
      const content = fs.readFileSync(p, 'utf8').trim();
      // 1) intentar encontrar IDs de grupo (negativos)
      const neg = content.match(/-\d+/);
      if (neg) return neg[0];
      // 2) buscar cualquier número largo que podría ser chat id (tomar el último número en el archivo)
      const all = content.match(/\d+/g);
      if (all && all.length) return all[all.length - 1];
    }
  } catch (e) {
    console.error('resolveFallbackChatId read error', e);
  }
  return null;
}

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

// Nuevo endpoint: generar token efimero y devolver deep-link
// Requiere autenticación (para saber user_id)
router.post('/register-request', auth, async (req, res) => {
  try {
    const userId = req.user && req.user.id;
    if (!userId) return res.status(400).json({ error: 'userId no disponible' });

    const token = uuidv4();
    const expiresInSec = parseInt(process.env.TELEGRAM_TOKEN_EXPIRES_SEC || '600', 10); // 10 min default
    const expiresAt = new Date(Date.now() + expiresInSec * 1000).toISOString();

    await sqlite.insertTelegramRegistrationToken(token, userId, expiresAt);

    const botUsername = process.env.TELEGRAM_BOT_USERNAME || 'YOUR_BOT_USERNAME';
    const link = `https://t.me/${botUsername}?start=${token}`;
    return res.json({ ok: true, link, expiresInSec });
  } catch (e) {
    console.error('register-request error', e);
    return res.status(500).json({ error: e.message });
  }
});

// Endpoint que el bot llamará al recibir /start <token>
// Protegido por header X-BOT-SECRET (simple shared secret)
router.post('/register-confirm', async (req, res) => {
  try {
    // Debug: log incoming confirm attempts to a file so we can inspect headers/body
    try {
      const logDir = path.join(__dirname, '..', '..', 'logs');
      if (!fs.existsSync(logDir)) fs.mkdirSync(logDir, { recursive: true });
      const logPath = path.join(logDir, 'telegram_confirm.log');
      const entry = { ts: new Date().toISOString(), headers: req.headers, body: req.body };
      fs.appendFileSync(logPath, JSON.stringify(entry) + '\n');
    } catch (e) {
      console.warn('Could not write telegram confirm log:', e && e.message);
    }

    const secret = req.header('X-BOT-SECRET');
    if (!secret || secret !== BOT_SECRET) return res.status(401).json({ error: 'Unauthorized' });

    const { token, chat_id } = req.body || {};
    if (!token || !chat_id) return res.status(400).json({ error: 'token y chat_id son requeridos' });

    const consumed = await sqlite.consumeTelegramRegistrationToken(token);
    if (!consumed) return res.status(404).json({ error: 'Token no encontrado' });
    if (consumed.expired) return res.status(410).json({ error: 'Token expirado' });

    // Asociar chat_id al user_id
    const userId = consumed.user_id;
    await sqlite.insertTelegramRegistrationForUser(userId, chat_id.toString());

    return res.json({ ok: true, userId, chat_id });
  } catch (e) {
    console.error('register-confirm error', e);
    return res.status(500).json({ error: e.message });
  }
});

// Endpoint legacy /notify: por compatibilidad, ahora fuerza envío al grupo/fallback
// (body: { userId?, text }) — el userId se ignora y el mensaje se envía siempre al chat de fallback
router.post('/notify', async (req, res) => {
  try {
    const { text } = req.body;
    if (!text) return res.status(400).json({ error: 'text es requerido' });

    // Resolver chatId de fallback (env var -> archivo). Preferimos ids negativos (grupos)
    const chatId = await resolveFallbackChatId();
    if (!chatId) return res.status(500).json({ error: 'No hay chat_id de fallback configurado' });

    console.log(`telegram notify: forced to fallback chatId=${chatId}`);
    const result = await telegramService.sendMessage(chatId, text);
    // Loguear respuesta de Telegram para debugging
    try {
      console.log('telegram sendMessage result:', JSON.stringify(result));
      if (result && result.ok === false) console.warn('Telegram API error:', result.description || result);
    } catch (e) { /* ignore stringify errors */ }
    return res.json({ ok: true, result, forcedFallback: true });
  } catch (e) {
    console.error('telegram notify error', e);
    return res.status(500).json({ error: e.message });
  }
});

// Endpoint para enviar un broadcast solo al grupo/fallback (body: { text })
router.post('/broadcast', async (req, res) => {
  try {
    const { text } = req.body;
    if (!text) return res.status(400).json({ error: 'text es requerido' });

    // Resolver chat id de fallback usando helper (prioriza IDs de grupos negativos)
    const chatId = await resolveFallbackChatId();
    if (!chatId) return res.status(500).json({ error: 'No hay chat_id de fallback configurado' });

    console.log(`telegram broadcast: resolved fallback chatId=${chatId}`);
    const result = await telegramService.sendMessage(chatId, text);
    try { console.log('telegram sendMessage result:', JSON.stringify(result)); } catch (e) {}
    return res.json({ ok: true, result });
  } catch (e) {
    console.error('telegram broadcast error', e);
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
