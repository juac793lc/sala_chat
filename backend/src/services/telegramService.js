const fetch = require('node-fetch');
const fs = require('fs');
const path = require('path');

// Nota: token embebido por petición del usuario para pruebas locales
let token = process.env.TELEGRAM_BOT_TOKEN || '';
if (!token) {
  token = '8483097946:AAGKnqi_llQ52SahHwzCiSFjgzAq4EKu8rc';
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
