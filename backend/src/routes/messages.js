const express = require('express');
const { v4: uuidv4 } = require('uuid');
const sqlite = require('../config/sqlite_db');

const router = express.Router();

// POST /api/messages - crear mensaje (texto o referenciando media)
router.post('/', async (req, res) => {
  try {
    const { roomId, userId, text = '', mediaId } = req.body;
    if (!roomId || !userId) {
      return res.status(400).json({ error: 'roomId y userId son requeridos' });
    }
    const message_id = uuidv4();
    const record = await sqlite.insertMessage({
      message_id,
      room_id: roomId,
      user_id: userId,
      text,
      media_id: mediaId || null
    });
    return res.status(201).json({ message: record });
  } catch (err) {
    console.error('❌ Error creando mensaje:', err);
    return res.status(500).json({ error: 'Error interno creando mensaje' });
  }
});

// GET /api/messages?roomId=xxx&limit=50&offset=0
router.get('/', async (req, res) => {
  try {
    const roomId = req.query.roomId;
    if (!roomId) {
      return res.status(400).json({ error: 'roomId es requerido' });
    }
    const limit = Math.min(parseInt(req.query.limit) || 50, 100);
    const offset = parseInt(req.query.offset) || 0;
    const rows = await sqlite.listMessages(roomId, limit, offset);
    // Enriquecer con user_nombre -> username si existe
    const enriched = rows.map(r => ({
      ...r,
      user_nombre: r.user_nombre || r.user_id // fallback
    }));
    return res.json({ roomId, count: enriched.length, items: enriched });
  } catch (err) {
    console.error('❌ Error listando mensajes:', err);
    return res.status(500).json({ error: 'Error interno listando mensajes' });
  }
});

module.exports = router;
