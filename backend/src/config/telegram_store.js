// Wrapper persistente para mapear userId -> chat_id usando SQLite (sql.js)
const db = require('./sqlite_db');

class TelegramStorePersistent {
  async add(userId, chatId) {
    if (!userId || !chatId) return false;
    try {
      await db.insertTelegramRegistration(userId.toString(), chatId.toString());
      return true;
    } catch (e) {
      console.warn('telegram_store add error', e.message);
      return false;
    }
  }

  async getByUser(userId) {
    if (!userId) return null;
    try {
      return await db.getTelegramChatIdByUser(userId.toString());
    } catch (e) {
      console.warn('telegram_store getByUser error', e.message);
      return null;
    }
  }

  async list() {
    try {
      return await db.listTelegramRegistrations();
    } catch (e) {
      console.warn('telegram_store list error', e.message);
      return [];
    }
  }
}

module.exports = new TelegramStorePersistent();
