const sqlite = require('../src/config/sqlite_db');
const { v4: uuidv4 } = require('uuid');

(async () => {
  try {
    const token = uuidv4();
    const userId = process.argv[2] || 'test-user-1';
    const expiresInSec = 600; // 10 min
    const expiresAt = new Date(Date.now() + expiresInSec * 1000).toISOString();

    const inserted = await sqlite.insertTelegramRegistrationToken(token, userId, expiresAt);
    console.log('Inserted token:', inserted ? inserted.token : null);
    const botUsername = process.env.TELEGRAM_BOT_USERNAME || 'notificamapa_bot';
    console.log('Deep-link:', `https://t.me/${botUsername}?start=${token}`);
    process.exit(0);
  } catch (e) {
    console.error('Error creating token', e);
    process.exit(1);
  }
})();
