// Ruta legacy de chat basada en Mongo eliminada.
module.exports = {};
const express = require('express');
const Joi = require('joi');
const multer = require('multer');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const { auth, checkRoomPermission } = require('../middleware/auth');
const Room = require('../models/Room');
const Message = require('../models/Message');
const User = require('../models/User');

const router = express.Router();

// Configuración de multer para archivos
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, 'uploads/');
  },
  filename: (req, file, cb) => {
    const uniqueName = `${uuidv4()}${path.extname(file.originalname)}`;
    cb(null, uniqueName);
  }
});

const upload = multer({
  storage,
  limits: {
    fileSize: parseInt(process.env.MAX_FILE_SIZE) || 10485760 // 10MB por defecto
  },
  fileFilter: (req, file, cb) => {
    const allowedExtensions = process.env.ALLOWED_EXTENSIONS?.split(',') || 
      ['jpg', 'jpeg', 'png', 'gif', 'mp3', 'wav', 'ogg', 'mp4', 'avi'];
    
    const fileExtension = path.extname(file.originalname).slice(1).toLowerCase();
    
    if (allowedExtensions.includes(fileExtension)) {
      cb(null, true);
    } else {
      cb(new Error(`Tipo de archivo no permitido: ${fileExtension}`));
    }
  }
});

// Esquemas de validación
const createRoomSchema = Joi.object({
  name: Joi.string().trim().min(1).max(50).required(),
  description: Joi.string().trim().max(200).default(''),
  type: Joi.string().valid('public', 'private').default('public')
});

// === RUTAS DE SALAS ===

// Obtener todas las salas públicas
router.get('/rooms', auth, async (req, res) => {
  try {
    const { page = 1, limit = 20, search = '' } = req.query;
    
    const query = {
      type: 'public',
      ...(search && {
        $or: [
          { name: { $regex: search, $options: 'i' } },
          { description: { $regex: search, $options: 'i' } }
        ]
      })
    };

    const rooms = await Room.find(query)
      .populate('creator', 'username avatar')
      .sort({ lastActivity: -1 })
      .limit(limit * 1)
      .skip((page - 1) * limit);

    const total = await Room.countDocuments(query);

    res.json({
      rooms: rooms.map(room => ({
        ...room.toPublic(),
        creator: room.creator
      })),
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total,
        pages: Math.ceil(total / limit)
      }
    });

  } catch (error) {
    console.error('Error obteniendo salas:', error);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
});

// Obtener salas del usuario
router.get('/rooms/my', auth, async (req, res) => {
  try {
    const rooms = await Room.find({
      'members.user': req.user._id
    })
    .populate('creator', 'username avatar')
    .sort({ lastActivity: -1 });

    res.json({
      rooms: rooms.map(room => ({
        ...room.toPublic(),
        creator: room.creator,
        myRole: room.getUserRole(req.user._id)
      }))
    });

  } catch (error) {
    console.error('Error obteniendo mis salas:', error);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
});

// Crear nueva sala
router.post('/rooms', auth, async (req, res) => {
  try {
    const { error, value } = createRoomSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ 
        error: 'Datos inválidos', 
        details: error.details[0].message 
      });
    }

    const room = new Room({
      ...value,
      creator: req.user._id,
      members: [{
        user: req.user._id,
        joinedAt: new Date(),
        role: 'admin'
      }]
    });

    await room.save();
    await room.populate('creator', 'username avatar');

    // Agregar sala a la lista del usuario
    await User.findByIdAndUpdate(req.user._id, {
      $addToSet: { joinedRooms: room._id }
    });

    res.status(201).json({
      message: 'Sala creada exitosamente',
      room: {
        ...room.toPublic(),
        creator: room.creator,
        myRole: 'admin'
      }
    });

    console.log(`🏠 Nueva sala creada: ${room.name} por ${req.user.username}`);

  } catch (error) {
    console.error('Error creando sala:', error);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
});

// Obtener detalles de una sala
router.get('/rooms/:roomId', auth, async (req, res) => {
  try {
    const { roomId } = req.params;
    
    const room = await Room.findById(roomId)
      .populate('creator', 'username avatar')
      .populate('members.user', 'username avatar isOnline lastSeen');

    if (!room) {
      return res.status(404).json({ error: 'Sala no encontrada' });
    }

    // Verificar si es miembro o si es sala pública
    const isMember = room.isMember(req.user._id);
    if (!isMember && room.type === 'private') {
      return res.status(403).json({ error: 'No tienes acceso a esta sala privada' });
    }

    res.json({
      ...room.toPublic(),
      creator: room.creator,
      members: room.members,
      isMember,
      myRole: isMember ? room.getUserRole(req.user._id) : null
    });

  } catch (error) {
    console.error('Error obteniendo detalles de sala:', error);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
});

// === RUTAS DE MENSAJES ===

// Obtener mensajes de una sala
router.get('/rooms/:roomId/messages', auth, checkRoomPermission('member'), async (req, res) => {
  try {
    const { roomId } = req.params;
    const { page = 1, limit = 50 } = req.query;

    const messages = await Message.find({
      room: roomId,
      isDeleted: false
    })
    .populate('sender', 'username avatar')
    .populate('replyTo', 'content sender type')
    .sort({ createdAt: -1 })
    .limit(limit * 1)
    .skip((page - 1) * limit);

    const total = await Message.countDocuments({
      room: roomId,
      isDeleted: false
    });

    res.json({
      messages: messages.reverse().map(msg => msg.toPublic()),
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total,
        pages: Math.ceil(total / limit)
      }
    });

  } catch (error) {
    console.error('Error obteniendo mensajes:', error);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
});

// Subir archivo multimedia
router.post('/upload', auth, upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No se subió ningún archivo' });
    }

    const fileUrl = `/uploads/${req.file.filename}`;
    
    res.json({
      message: 'Archivo subido exitosamente',
      file: {
        url: fileUrl,
        originalName: req.file.originalname,
        filename: req.file.filename,
        size: req.file.size,
        mimeType: req.file.mimetype
      }
    });

  } catch (error) {
    console.error('Error subiendo archivo:', error);
    res.status(500).json({ error: 'Error subiendo archivo' });
  }
});

// Unirse a una sala pública
router.post('/rooms/:roomId/join', auth, async (req, res) => {
  try {
    const { roomId } = req.params;
    
    const room = await Room.findById(roomId);
    if (!room) {
      return res.status(404).json({ error: 'Sala no encontrada' });
    }

    if (room.type === 'private') {
      return res.status(403).json({ error: 'No puedes unirte a una sala privada' });
    }

    if (room.isMember(req.user._id)) {
      return res.status(400).json({ error: 'Ya eres miembro de esta sala' });
    }

    // Verificar límite de miembros
    if (room.members.length >= room.settings.maxMembers) {
      return res.status(400).json({ error: 'La sala está llena' });
    }

    // Agregar como miembro
    room.members.push({
      user: req.user._id,
      joinedAt: new Date(),
      role: 'member'
    });

    await room.save();

    // Actualizar lista de salas del usuario
    await User.findByIdAndUpdate(req.user._id, {
      $addToSet: { joinedRooms: roomId }
    });

    res.json({
      message: 'Te uniste exitosamente a la sala',
      room: room.toPublic()
    });

    console.log(`➕ ${req.user.username} se unió a la sala: ${room.name}`);

  } catch (error) {
    console.error('Error uniéndose a sala:', error);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
});

// Salir de una sala
router.post('/rooms/:roomId/leave', auth, checkRoomPermission('member'), async (req, res) => {
  try {
    const { roomId } = req.params;
    const room = req.room;

    // No permitir que el creador salga si es el único admin
    const userRole = room.getUserRole(req.user._id);
    const adminCount = room.members.filter(m => m.role === 'admin').length;
    
    if (userRole === 'admin' && adminCount === 1) {
      return res.status(400).json({ 
        error: 'No puedes salir siendo el único administrador. Transfiere la administración primero.' 
      });
    }

    // Remover de la sala
    room.members = room.members.filter(
      member => member.user.toString() !== req.user._id.toString()
    );

    await room.save();

    // Remover de la lista de salas del usuario
    await User.findByIdAndUpdate(req.user._id, {
      $pull: { joinedRooms: roomId }
    });

    res.json({ message: 'Saliste exitosamente de la sala' });

    console.log(`➖ ${req.user.username} salió de la sala: ${room.name}`);

  } catch (error) {
    console.error('Error saliendo de sala:', error);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
});

module.exports = router;