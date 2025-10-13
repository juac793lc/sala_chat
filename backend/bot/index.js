const { Telegraf, Markup } = require('telegraf');
const fetch = require('node-fetch');

const fs = require('fs');
const path = require('path');
const os = require('os');

let BOT_TOKEN = process.env.BOT_TOKEN || '';
if (!BOT_TOKEN) {
  try {
    const p = path.join(__dirname, '..', '..', 'telegram_integration.txt');
    if (fs.existsSync(p)) {
      const content = fs.readFileSync(p, 'utf8').trim();
      const lines = content.split(/\r?\n/).map(l => l.trim()).filter(Boolean);
      // Buscar una línea que parezca token (contiene ':' y longitud razonable)
      const tokenLine = lines.find(l => l.includes(':') && l.length > 10);
      if (tokenLine) BOT_TOKEN = tokenLine;
    }
  } catch (e) {
    console.warn('No se pudo leer telegram_integration.txt para token:', e.message || e);
  }
}
const BACKEND = process.env.BACKEND_URL || 'http://localhost:3001';
const BOT_SECRET = process.env.BOT_SECRET || 'dev-bot-secret';

if (!BOT_TOKEN) {
  console.error('BOT_TOKEN no configurado. Define BOT_TOKEN en env.');
  process.exit(1);
}

const bot = new Telegraf(BOT_TOKEN);

bot.start(async (ctx) => {
  try {
    const token = ctx.startPayload; // deep-link token
    // Log start events for debugging
    try {
      const logDir = path.join(__dirname, '..', '..', 'logs');
      if (!fs.existsSync(logDir)) fs.mkdirSync(logDir, { recursive: true });
      const logPath = path.join(logDir, 'bot_activity.log');
      const entry = { ts: new Date().toISOString(), type: 'start', chat: ctx.chat && ctx.chat.id, from: ctx.from && ctx.from.id, payload: token };
      fs.appendFileSync(logPath, JSON.stringify(entry) + os.EOL);
    } catch (e) { console.warn('bot log write error', e && e.message); }
    if (!token) {
      return ctx.reply('Bienvenido. Para registrarte, usa el enlace desde la aplicación.');
    }

    // Mostrar mensaje con botón Confirmar y mostrar token (debug-friendly)
    const msgText = `Token detectado: ${token}\nPresiona confirmar para vincular tu cuenta con NotiMapa.`;
    await ctx.reply(msgText, Markup.inlineKeyboard([
      Markup.button.callback('Confirmar ✅', `CONFIRM_${token}`),
      Markup.button.callback('Cancelar ❌', `CANCEL_${token}`)
    ]));
  } catch (e) {
    console.error('start handler error', e);
    ctx.reply('Error interno en el bot. Intenta más tarde.');
  }
});

bot.on('callback_query', async (ctx) => {
  try {
    const data = ctx.callbackQuery.data || '';
    // Log callback queries for debugging
    try {
      const logDir = path.join(__dirname, '..', '..', 'logs');
      if (!fs.existsSync(logDir)) fs.mkdirSync(logDir, { recursive: true });
      const logPath = path.join(logDir, 'bot_activity.log');
      const entry = { ts: new Date().toISOString(), type: 'callback_query', chat: ctx.chat && ctx.chat.id, from: ctx.from && ctx.from.id, data };
      fs.appendFileSync(logPath, JSON.stringify(entry) + os.EOL);
    } catch (e) { console.warn('bot log write error', e && e.message); }
    if (data.startsWith('CONFIRM_')) {
      const token = data.slice('CONFIRM_'.length);
      // Llamar backend para confirmar
      const resp = await fetch(`${BACKEND}/api/telegram/register-confirm`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-BOT-SECRET': BOT_SECRET },
        body: JSON.stringify({ token, chat_id: ctx.chat.id })
      });
      if (resp.ok) {
        await ctx.answerCbQuery('Registro confirmado');
        await ctx.editMessageText('Registro confirmado ✅. Recibirás notificaciones cercanas.');
      } else {
        const j = await resp.json().catch(() => ({}));
        await ctx.answerCbQuery('No se pudo confirmar');
        await ctx.editMessageText(`No fue posible confirmar: ${j.error || resp.statusText}`);
      }
    } else if (data.startsWith('CANCEL_')) {
      await ctx.answerCbQuery('Cancelado');
      await ctx.editMessageText('Registro cancelado.');
    } else {
      await ctx.answerCbQuery();
    }
  } catch (e) {
    console.error('callback_query error', e);
    try { await ctx.answerCbQuery('Error interno'); } catch (_) {}
  }
});

bot.launch().then(() => console.log('Bot Telegraf iniciado')).catch(e => console.error('Error lanzando bot', e));

// Graceful shutdown
process.once('SIGINT', () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));
