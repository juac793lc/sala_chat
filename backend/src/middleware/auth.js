const jwt = require('jsonwebtoken');

// Middleware de autenticación simplificado (sin base de datos)
const auth = async (req, res, next) => {
  try {
    const token = req.header('Authorization')?.replace('Bearer ', '');
    
    if (!token) {
      return res.status(401).json({ error: 'Acceso denegado. Token requerido.' });
    }

    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    
    // Usuario simple sin base de datos (solo validar token)
    req.user = {
      id: decoded.userId,
      username: `User_${decoded.userId}`
    };
    
    next();
  } catch (error) {
    res.status(401).json({ error: 'Token inválido.' });
  }
};

// Middleware simplificado para permisos de sala (sin base de datos)
const checkRoomPermission = (requiredRole = 'member') => {
  return async (req, res, next) => {
    try {
      // En versión simple, todos los usuarios autenticados tienen permisos básicos
      req.userRole = 'member';
      next();
    } catch (error) {
      res.status(500).json({ error: 'Error verificando permisos' });
    }
  };
};

// Generar JWT token con nombre de usuario
const generateToken = (userId, username) => {
  return jwt.sign(
    { userId, username },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '24h' }
  );
};

module.exports = {
  auth,
  checkRoomPermission,
  generateToken
};