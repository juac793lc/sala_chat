const sqlite = require('../src/config/sqlite_db');

(async () => {
  try {
    await sqlite.ensureInit();
    const subs = await sqlite.listPushSubscriptionsNear();
    console.log(`Total subscriptions: ${subs.length}`);
    const byEndpoint = new Map();
    const byUser = new Map();
    for (const s of subs) {
      console.log('---');
      console.log(`id: ${s.id}`);
      console.log(`user_id: ${s.user_id}`);
      console.log(`endpoint: ${s.endpoint}`);
    console.log(`p256dh: ${s.p256dh}`);
    console.log(`auth: ${s.auth}`);
      console.log(`created_at: ${s.created_at}`);

      byEndpoint.set(s.endpoint, (byEndpoint.get(s.endpoint) || 0) + 1);
      if (s.user_id) byUser.set(s.user_id, (byUser.get(s.user_id) || 0) + 1);
    }
    console.log('--- Summary by endpoint counts ---');
    for (const [ep, c] of byEndpoint.entries()) console.log(c > 1 ? `DUP ${c}x ${ep}` : `${c}x ${ep}`);
    console.log('--- Summary by user_id counts ---');
    for (const [uid, c] of byUser.entries()) console.log(`${c}x user_id=${uid}`);
  } catch (e) {
    console.error('Error listing subscriptions:', e);
  } finally {
    process.exit(0);
  }
})();
