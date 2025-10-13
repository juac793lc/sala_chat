(async function(){
  try {
    const sqlite = require('./src/config/sqlite_db');
    const { randomUUID } = require('crypto');
    const token = randomUUID();
    const userId = 'test-user-e2e';
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    const res = await sqlite.insertTelegramRegistrationToken(token, userId, expiresAt);
    console.log('TOKEN_CREATED:' + token);
    process.exit(0);
  } catch (e) {
    console.error('ERR_CREATING_TOKEN', e && e.message ? e.message : e);
    process.exit(1);
  }
})();
