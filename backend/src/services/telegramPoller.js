const fetch = require('node-fetch');
const fs = require('fs');
const path = require('path');
const telegramStore = require('../config/telegram_store');
const db = require('../config/sqlite_db');

// Nota: token embebido por petición del usuario para pruebas locales
let token = process.env.TELEGRAM_BOT_TOKEN || '';
if (!token) token = '8483097946:AAGKnqi_llQ52SahHwzCiSFjgzAq4EKu8rc';
let offset = 0;
let running = false;

async function handleUpdate(update) {
  try {
    if (!update.message) return;
    const msg = update.message;
    const chatId = msg.chat && (msg.chat.id || msg.chat.id === 0) ? msg.chat.id : null;
    const text = (msg.text || '').trim();
    if (!chatId || !text) return;

    // soportar '/register user_1' o 'register user_1'
    const m = text.match(/^\/?register\s+(\S+)$/i);
    if (m) {
      const userId = m[1];
      console.log(`📥 Telegram register request: userId=${userId} chatId=${chatId}`);
      await db.insertTelegramRegistration(userId.toString(), chatId.toString());
      // responder al usuario confirmando
      try {
        await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ chat_id: chatId, text: `Registro completado para userId: ${userId}` })
        });
      } catch (e) { console.warn('No se pudo enviar confirmación a Telegram:', e.message); }
    }
  } catch (e) {
    console.warn('Error procesando update de Telegram:', e.message || e);
  }
}

async function pollOnce() {
  if (!token) return;
  try {
    const res = await fetch(`https://api.telegram.org/bot${token}/getUpdates?offset=${offset}&timeout=10`);
    const data = await res.json();
    if (!data || !data.result) return;
    for (const update of data.result) {
      try {
        if (update.update_id) offset = Math.max(offset, update.update_id + 1);
        await handleUpdate(update);
      } catch (e) { console.warn('Error handleUpdate:', e.message || e); }
    }
  } catch (e) {
    console.warn('Error polling Telegram getUpdates:', e.message || e);
  }
}

function start(intervalMs = 5000) {
  if (!token) {
    console.warn('Telegram token no configurado; poller no arrancará');
    return;
  }
  if (running) return;
  running = true;
  console.log('🔁 Iniciando Telegram poller...');
  // ejecutar inmediatamente y luego intervalo
  (async () => {
    await pollOnce();
    const timer = setInterval(async () => {
      await pollOnce();
    }, intervalMs);
    // conservar referencia si se necesita stop (no expuesto ahora)
    pollerTimer = timer;
  })();
}

function stop() {
  running = false;
  if (typeof pollerTimer !== 'undefined') clearInterval(pollerTimer);
}

module.exports = { start, stop };
