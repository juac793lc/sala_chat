const path = require('path');
const fs = require('fs');
const initSqlJs = require('sql.js');

// Ruta del archivo SQLite (persistente en backend/)
const dbPath = path.join(__dirname, '..', '..', 'chat_data.db');

let SQL = null;
let db = null;

// Inicializar SQL.js de forma asíncrona
const initDb = async () => {
  if (SQL && db) return db; // Ya inicializado
  
  SQL = await initSqlJs();
  
  // Cargar base de datos existente o crear nueva
  let filebuffer = null;
  if (fs.existsSync(dbPath)) {
    filebuffer = fs.readFileSync(dbPath);
    console.log('📁 Cargando SQLite existente:', dbPath);
  } else {
    console.log('📁 Creando nueva SQLite:', dbPath);
  }
  
  db = new SQL.Database(filebuffer);
  
  // Inicializar esquema
  db.exec(`
    CREATE TABLE IF NOT EXISTS media (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      media_id TEXT UNIQUE,
      room_id TEXT,
      user_id TEXT,
      user_nombre TEXT,
      tipo TEXT,
      url TEXT,
      mime TEXT,
      size_bytes INTEGER,
      duration_seconds REAL,
      original_name TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_media_room_created ON media(room_id, created_at DESC);

    CREATE TABLE IF NOT EXISTS messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      message_id TEXT UNIQUE,
      room_id TEXT,
      user_id TEXT,
      user_nombre TEXT,
      text TEXT,
      media_id TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_messages_room_created ON messages(room_id, created_at DESC);

    CREATE TABLE IF NOT EXISTS map_markers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      marker_id TEXT UNIQUE,
      user_id TEXT,
      user_nombre TEXT,
      latitude REAL,
      longitude REAL,
      tipo_reporte TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      is_active INTEGER DEFAULT 1
    );

    CREATE INDEX IF NOT EXISTS idx_markers_active ON map_markers(is_active, created_at DESC);
  `);
  
  // Guardar cambios inmediatamente
  saveDb();
  
  console.log('✅ SQLite inicializado correctamente');
  return db;
};

// Guardar base de datos al archivo
const saveDb = () => {
  if (!db) return;
  const data = db.export();
  const buffer = Buffer.from(data);
  fs.writeFileSync(dbPath, buffer);
};

// Auto-guardar cada 5 segundos si hay cambios
setInterval(() => {
  if (db) saveDb();
}, 5000);

module.exports = {
  async countComentariosTexto(contenidoId) {
    const database = await initDb();
    const result = database.exec('SELECT COUNT(*) as total FROM messages WHERE room_id = ? AND (media_id IS NULL OR media_id = "")', [contenidoId]);
    return result.length > 0 && result[0].values.length > 0 ? result[0].values[0][0] : 0;
  },

  async countComentariosAudio(contenidoId) {
    const database = await initDb();
    const result = database.exec('SELECT COUNT(*) as total FROM messages WHERE room_id = ? AND media_id IS NOT NULL AND media_id != ""', [contenidoId]);
    return result.length > 0 && result[0].values.length > 0 ? result[0].values[0][0] : 0;
  },
  async ensureInit() {
    return await initDb();
  },
  
  async insertMedia(data) {
    const database = await initDb();
    // Migrar columna user_nombre si no existe
    try { database.exec('SELECT user_nombre FROM media LIMIT 1'); } catch (_) {
      try { database.exec('ALTER TABLE media ADD COLUMN user_nombre TEXT'); saveDb(); } catch (e) { console.warn('No se pudo agregar user_nombre:', e.message); }
    }
    const stmt = database.prepare(`INSERT INTO media (media_id, room_id, user_id, user_nombre, tipo, url, mime, size_bytes, duration_seconds, original_name)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
    stmt.run([data.media_id, data.room_id, data.user_id, data.user_nombre || null, data.tipo, data.url, data.mime, data.size_bytes, data.duration_seconds, data.original_name]);
    saveDb();
    
    const result = database.exec('SELECT * FROM media WHERE media_id = ?', [data.media_id]);
    return result.length > 0 && result[0].values.length > 0 ? this._rowToObject(result[0], 0) : null;
  },
  
  async getMediaByMediaId(media_id) {
    const database = await initDb();
    const result = database.exec('SELECT * FROM media WHERE media_id = ?', [media_id]);
    return result.length > 0 && result[0].values.length > 0 ? this._rowToObject(result[0], 0) : null;
  },
  
  async listMedia(roomId, limit = 50, offset = 0) {
    const database = await initDb();
    const result = database.exec('SELECT * FROM media WHERE room_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?', [roomId, limit, offset]);
    if (result.length === 0) return [];
    
    const rows = [];
    for (let i = 0; i < result[0].values.length; i++) {
      rows.push(this._rowToObject(result[0], i));
    }
    return rows;
  },
  
  async insertMessage(data) {
    const database = await initDb();
    // Migrar columna user_nombre si no existe
    try { database.exec('SELECT user_nombre FROM messages LIMIT 1'); } catch (_) {
      try { database.exec('ALTER TABLE messages ADD COLUMN user_nombre TEXT'); saveDb(); } catch (e) { console.warn('No se pudo agregar user_nombre a messages:', e.message); }
    }
    const stmt = database.prepare(`INSERT INTO messages (message_id, room_id, user_id, user_nombre, text, media_id)
     VALUES (?, ?, ?, ?, ?, ?)`);
    stmt.run([data.message_id, data.room_id, data.user_id, data.user_nombre || null, data.text, data.media_id]);
    saveDb();
    
    const result = database.exec('SELECT * FROM messages WHERE message_id = ?', [data.message_id]);
    return result.length > 0 && result[0].values.length > 0 ? this._rowToObject(result[0], 0) : null;
  },
  
  async getMessageById(message_id) {
    const database = await initDb();
    const result = database.exec('SELECT * FROM messages WHERE message_id = ?', [message_id]);
    return result.length > 0 && result[0].values.length > 0 ? this._rowToObject(result[0], 0) : null;
  },
  
  async listMessages(roomId, limit = 50, offset = 0) {
    const database = await initDb();
    const result = database.exec('SELECT * FROM messages WHERE room_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?', [roomId, limit, offset]);
    if (result.length === 0) return [];
    
    const rows = [];
    for (let i = 0; i < result[0].values.length; i++) {
      rows.push(this._rowToObject(result[0], i));
    }
    return rows;
  },

  // Funciones para marcadores del mapa
  async insertMarker(data) {
    const database = await initDb();
    const stmt = database.prepare(`INSERT INTO map_markers (marker_id, user_id, user_nombre, latitude, longitude, tipo_reporte)
     VALUES (?, ?, ?, ?, ?, ?)`);
    stmt.run([data.marker_id, data.user_id, data.user_nombre, data.latitude, data.longitude, data.tipo_reporte]);
    saveDb();
    
    const result = database.exec('SELECT * FROM map_markers WHERE marker_id = ?', [data.marker_id]);
    return result.length > 0 && result[0].values.length > 0 ? this._rowToObject(result[0], 0) : null;
  },

  async getAllActiveMarkers() {
    const database = await initDb();
    // Incluir columna calculada en milisegundos para evitar ambigüedades de parse de fecha en JS
    const result = database.exec(`SELECT 
        marker_id,
        user_id,
        user_nombre,
        latitude,
        longitude,
        tipo_reporte,
        is_active,
        created_at,
        (CAST(strftime('%s', created_at) AS INTEGER) * 1000) AS created_at_ms
      FROM map_markers 
      WHERE is_active = 1 
      ORDER BY created_at DESC`);
    if (result.length === 0) return [];
    
    const rows = [];
    for (let i = 0; i < result[0].values.length; i++) {
      rows.push(this._rowToObject(result[0], i));
    }
    return rows;
  },

  async deactivateMarker(marker_id) {
    const database = await initDb();
    const stmt = database.prepare('UPDATE map_markers SET is_active = 0 WHERE marker_id = ?');
    stmt.run([marker_id]);
    saveDb();
    return true;
  },

  async getMarkerById(marker_id) {
    const database = await initDb();
    const result = database.exec('SELECT * FROM map_markers WHERE marker_id = ?', [marker_id]);
    return result.length > 0 && result[0].values.length > 0 ? this._rowToObject(result[0], 0) : null;
  },
  
  _rowToObject(result, rowIndex) {
    const row = {};
    for (let i = 0; i < result.columns.length; i++) {
      row[result.columns[i]] = result.values[rowIndex][i];
    }
    return row;
  },
  
  // Cerrar y guardar al salir
  close() {
    if (db) {
      saveDb();
      db.close();
    }
  }
};
