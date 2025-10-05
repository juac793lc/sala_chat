const express = require('express');
const Joi = require('joi');
const { generateToken } = require('../middleware/auth');
const db = require('../config/memory_db');

const router = express.Router();

// Esquemas de validación
const joinSchema = Joi.object({
  username: Joi.string().min(2).max(30).required().regex(/^[a-zA-Z0-9_\s]+$/)
});

// Unirse al chat con solo nombre
router.post('/join', async (req, res) => {
  try {
    // Validar datos de entrada
    const { error, value } = joinSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ 
        error: 'Nombre inválido', 
        details: error.details[0].message 
      });
    }

    const { username } = value;

    // Verificar si el usuario ya existe
    let user = await db.findUserByUsername(username);
    let isNewUser = false;

    if (user) {
      // Si existe, actualizar como online
      user = await db.updateUser(user.id, {
        isOnline: true,
        lastSeen: new Date()
      });
      console.log(`🔄 Usuario reconectado: ${username}`);
    } else {
      // Crear nuevo usuario
      user = await db.createUser({ username });
      isNewUser = true;
      console.log(`👤 Nuevo usuario creado: ${username}`);
    }

    // Generar token con username incluido
    const token = generateToken(user.id, user.username);

    res.status(200).json({
      message: `¡Bienvenido${isNewUser ? '' : ' de vuelta'}, ${username}!`,
      token,
      user: {
        id: user.id,
        username: user.username,
        avatar: user.avatar,
        isOnline: user.isOnline,
        lastSeen: user.lastSeen
      },
      isNewUser
    });

    console.log(`🔐 Usuario conectado: ${username} (ID: ${user.id})`);

  } catch (error) {
    console.error('Error uniéndose al chat:', error);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
});

// Verificar token (endpoint para validar sesión)
router.get('/verify', async (req, res) => {
  try {
    const token = req.header('Authorization')?.replace('Bearer ', '');
    
    if (!token) {
      return res.status(401).json({ error: 'Token requerido' });
    }

    const jwt = require('jsonwebtoken');
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    const user = await db.findUserById(decoded.userId);
    
    if (!user) {
      return res.status(401).json({ error: 'Token inválido' });
    }

    res.json({
      valid: true,
      user: {
        id: user.id,
        username: user.username,
        avatar: user.avatar,
        isOnline: user.isOnline,
        lastSeen: user.lastSeen
      }
    });

  } catch (error) {
    res.status(401).json({ error: 'Token inválido' });
  }
});

// Obtener usuarios conectados
router.get('/users', async (req, res) => {
  try {
    const users = await db.getOnlineUsers();

    res.json({
      users: users.map(user => ({
        id: user.id,
        username: user.username,
        avatar: user.avatar,
        isOnline: user.isOnline,
        lastSeen: user.lastSeen
      })),
      count: users.length
    });

  } catch (error) {
    console.error('Error obteniendo usuarios:', error);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
});

// Logout (limpiar estado online)
router.post('/logout', async (req, res) => {
  try {
    const token = req.header('Authorization')?.replace('Bearer ', '');
    
    if (token) {
      const jwt = require('jsonwebtoken');
      try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        await db.updateUser(decoded.userId, {
          isOnline: false,
          socketId: '',
          lastSeen: new Date()
        });
      } catch (err) {
        // Token inválido, pero aún podemos hacer logout
      }
    }

    res.json({ message: 'Logout exitoso' });
  } catch (error) {
    res.status(500).json({ error: 'Error interno del servidor' });
  }
});

// Endpoint para obtener estadísticas del servidor
router.get('/stats', (req, res) => {
  const stats = db.getStats();
  res.json({
    ...stats,
    serverTime: new Date().toISOString()
  });
});

module.exports = router;