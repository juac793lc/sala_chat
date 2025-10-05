const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');

const router = express.Router();
const sqlite = require('../config/sqlite_db');

// Configurar multer para upload de archivos multimedia
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    const mediaType = req.body.mediaType || 'general';
    const uploadDir = path.join(__dirname, '../uploads', mediaType);
    
    // Crear directorio si no existe
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
      console.log(`📁 Directorio creado: ${uploadDir}`);
    }
    
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    const timestamp = Date.now();
    // Mantener la extensión original o usar .m4a para audio sin extensión
  let originalExt = path.extname(file.originalname);
  // Si llega sin extensión pero sabemos el mimetype, inferir
  if (!originalExt && file.mimetype === 'audio/webm') originalExt = '.webm';
  if (!originalExt && file.mimetype === 'audio/wav') originalExt = '.wav';
  if (!originalExt && file.mimetype === 'audio/mpeg') originalExt = '.mp3';
  if (!originalExt && file.mimetype === 'audio/mp4') originalExt = '.m4a';
  const extension = originalExt || (req.body.mediaType === 'audio' ? '.webm' : '.bin');
    const mediaType = req.body.mediaType || 'file';
    const filename = `${mediaType}_${timestamp}${extension}`;
    cb(null, filename);
  }
});

// Configuración de límites
const upload = multer({ 
  storage: storage,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB máximo
    fieldSize: 2 * 1024 * 1024   // 2MB para campos
  },
  fileFilter: function (req, file, cb) {
    // Filtros básicos de tipo de archivo
    const allowedTypes = {
  'audio': ['audio/wav', 'audio/mp4', 'audio/mpeg', 'audio/m4a', 'audio/webm', 'application/octet-stream'],
      'image': ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'application/octet-stream'],
      'video': ['video/mp4', 'video/webm', 'video/quicktime', 'application/octet-stream']
    };
    
    const mediaType = req.body.mediaType;
    console.log(`🔍 Validando archivo: ${file.originalname}, tipo: ${file.mimetype}, mediaType: ${mediaType}`);
    
    if (mediaType && allowedTypes[mediaType]) {
      const isAllowed = allowedTypes[mediaType].includes(file.mimetype) || 
                       file.mimetype.startsWith(mediaType + '/');
      if (isAllowed) {
        console.log(`✅ Archivo aceptado: ${file.mimetype} para ${mediaType}`);
        cb(null, true);
      } else {
        console.log(`❌ Archivo rechazado: ${file.mimetype} para ${mediaType}`);
        cb(new Error(`Tipo de archivo no permitido para ${mediaType}: ${file.mimetype}`));
      }
    } else {
      // Si no se especifica tipo, permitir cualquier archivo multimedia o octet-stream
      const isMultimedia = file.mimetype.startsWith('audio/') || 
                          file.mimetype.startsWith('image/') || 
                          file.mimetype.startsWith('video/') ||
                          file.mimetype === 'application/octet-stream';
      console.log(`🔍 Sin mediaType especificado, permitiendo multimedia: ${isMultimedia}`);
      cb(null, isMultimedia);
    }
  }
});

// POST /api/media/upload - Subir archivo multimedia
router.post('/upload', upload.single('file'), (req, res) => {
  try {
    console.log('📤 Nuevo upload recibido');
    console.log('📋 Body:', req.body);
    console.log('📁 File:', req.file);
    
    if (!req.file) {
      return res.status(400).json({ 
        error: 'No se recibió archivo',
        details: 'Debe enviar un archivo en el campo "file"'
      });
    }

    // Construir URL completa del archivo
    const protocol = req.protocol;
    const host = req.get('host');
    const mediaType = req.body.mediaType || 'general';
    const fileUrl = `${protocol}://${host}/uploads/${mediaType}/${req.file.filename}`;
    
    // Generar respuesta
    const media_id = uuidv4();
    const durationSeconds = parseFloat(req.body.durationSeconds) || null;
    const roomId = req.body.roomId || null;
    const userId = req.body.userId || null;
    const userNombre = req.body.userNombre || req.body.userName || null;
    // Insertar metadata en SQLite
    sqlite.insertMedia({
      media_id,
      room_id: roomId,
      user_id: userId,
      user_nombre: userNombre,
      tipo: mediaType,
      url: fileUrl,
      mime: req.file.mimetype,
      size_bytes: req.file.size,
      duration_seconds: durationSeconds,
      original_name: req.body.originalName || req.file.originalname
    }).then(() => {
      console.log('✅ Metadata insertada en SQLite para', media_id);
    }).catch(e => {
      console.error('⚠️ Error insertando en media sqlite (continuando):', e.message);
    });

    const response = {
      mediaId: media_id,
      url: fileUrl,
      fileName: req.file.filename,
      fileSize: req.file.size,
      mimeType: req.file.mimetype,
      uploadedAt: new Date().toISOString(),
      mediaType: mediaType,
      roomId: roomId,
      userId: userId,
      userNombre: userNombre,
      durationSeconds: durationSeconds,
      originalName: req.body.originalName || req.file.originalname
    };

    console.log('✅ Upload exitoso:', response.url);
    console.log('📊 Detalles:', {
      size: `${(req.file.size / 1024).toFixed(2)} KB`,
      type: req.file.mimetype,
      path: req.file.path
    });
    
    res.status(201).json(response);
    
  } catch (error) {
    console.error('❌ Error en upload:', error);
    res.status(500).json({ 
      error: 'Error interno del servidor',
      message: error.message,
      details: 'Error procesando el archivo'
    });
  }
});

// GET /api/media/info/:type/:filename - Obtener información de archivo
router.get('/info/:type/:filename', (req, res) => {
  try {
    const { type, filename } = req.params;
    const filePath = path.join(__dirname, '../uploads', type, filename);
    
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ error: 'Archivo no encontrado' });
    }
    
    const stats = fs.statSync(filePath);
    const info = {
      filename: filename,
      size: stats.size,
      type: type,
      created: stats.birthtime,
      modified: stats.mtime,
      url: `${req.protocol}://${req.get('host')}/uploads/${type}/${filename}`
    };
    
    res.json(info);
    
  } catch (error) {
    console.error('❌ Error obteniendo info de archivo:', error);
    res.status(500).json({ error: 'Error obteniendo información del archivo' });
  }
});

// DELETE /api/media/:type/:filename - Eliminar archivo
router.delete('/:type/:filename', (req, res) => {
  try {
    const { type, filename } = req.params;
    const filePath = path.join(__dirname, '../uploads', type, filename);
    
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ error: 'Archivo no encontrado' });
    }
    
    fs.unlinkSync(filePath);
    console.log('🗑️ Archivo eliminado:', filePath);
    
    res.json({ 
      message: 'Archivo eliminado correctamente',
      filename: filename 
    });
    
  } catch (error) {
    console.error('❌ Error eliminando archivo:', error);
    res.status(500).json({ error: 'Error eliminando archivo' });
  }
});

// GET /api/media/list/:type - Listar archivos por tipo
router.get('/list/:type', (req, res) => {
  try {
    const { type } = req.params;
    const uploadDir = path.join(__dirname, '../uploads', type);
    
    if (!fs.existsSync(uploadDir)) {
      return res.json({ files: [], count: 0 });
    }
    
    const files = fs.readdirSync(uploadDir).map(filename => {
      const filePath = path.join(uploadDir, filename);
      const stats = fs.statSync(filePath);
      return {
        filename: filename,
        size: stats.size,
        created: stats.birthtime,
        url: `${req.protocol}://${req.get('host')}/uploads/${type}/${filename}`
      };
    });
    
    res.json({ 
      files: files,
      count: files.length,
      type: type
    });
    
  } catch (error) {
    console.error('❌ Error listando archivos:', error);
    res.status(500).json({ error: 'Error listando archivos' });
  }
});

// GET /api/media/by-room/:roomId?limit=50&offset=0
router.get('/by-room/:roomId', async (req, res) => {
  try {
    const { roomId } = req.params;
    const limit = Math.min(parseInt(req.query.limit) || 50, 100);
    const offset = parseInt(req.query.offset) || 0;
    const rows = await sqlite.listMedia(roomId, limit, offset);
    return res.json({ roomId, count: rows.length, items: rows });
  } catch (err) {
    console.error('❌ Error listando media por room:', err);
    return res.status(500).json({ error: 'Error interno listando media' });
  }
});

module.exports = router;