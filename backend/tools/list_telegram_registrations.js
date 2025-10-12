const db = require('../src/config/sqlite_db');

(async () => {
  try {
    const regs = await db.listTelegramRegistrations();
    console.log('=== telegram_registrations ===');
    console.log(JSON.stringify(regs, null, 2));
    process.exit(0);
  } catch (err) {
    console.error('Error al listar telegram_registrations:', err);
    process.exit(2);
  }
})();
