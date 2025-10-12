const db = require('../src/config/sqlite_db');

(async () => {
  try {
    const database = await db.ensureInit();
    const res = database.exec('SELECT id, token, user_id, expires_at, created_at FROM telegram_registration_tokens ORDER BY created_at DESC');
    const rows = [];
    if (res.length > 0) {
      for (let i = 0; i < res[0].values.length; i++) {
        const obj = {};
        for (let c = 0; c < res[0].columns.length; c++) obj[res[0].columns[c]] = res[0].values[i][c];
        rows.push(obj);
      }
    }
    console.log('=== telegram_registration_tokens ===');
    console.log(JSON.stringify(rows, null, 2));
    process.exit(0);
  } catch (err) {
    console.error('Error al listar telegram_registration_tokens:', err);
    process.exit(2);
  }
})();
