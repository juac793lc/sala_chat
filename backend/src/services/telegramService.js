const fetch = require('node-fetch');
const fs = require('fs');
const path = require('path');

// Nota: token embebido por petición del usuario para pruebas locales
// Leer token de entorno o, si no existe, desde el archivo de integración (telegram_integration.txt)
let token = process.env.TELEGRAM_BOT_TOKEN || '';
if (!token) {
  try {
    const p = path.join(__dirname, '..', '..', 'telegram_integration.txt');
    if (fs.existsSync(p)) {
      const content = fs.readFileSync(p, 'utf8').trim();
      // Buscar una linea que parezca token (contiene ':' y al menos 10 caracteres)
      const lines = content.split(/\r?\n/).map(l => l.trim()).filter(Boolean);
      const tokenLine = lines.find(l => l.includes(':') && l.length > 10);
      if (tokenLine) token = tokenLine;
    }
  } catch (e) {
    console.warn('No se pudo leer telegram_integration.txt para token:', e.message || e);
  }
}

async function sendMessage(chatId, text) {
  if (!token) throw new Error('Telegram token not configured');
  const url = `https://api.telegram.org/bot${token}/sendMessage`;
  const body = { chat_id: chatId, text, parse_mode: 'HTML', disable_web_page_preview: true };
  try {
    console.log(`telegramService: sending to ${chatId}`);
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
    const json = await res.json();
    console.log('telegramService: response', JSON.stringify(json));
    return json;
  } catch (e) {
    console.error('telegramService sendMessage error', e.message || e);
    throw e;
  }
}

module.exports = { sendMessage };
