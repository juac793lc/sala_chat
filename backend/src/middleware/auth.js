const jwt = require('jsonwebtoken');

// Valor por defecto seguro para desarrollo si no existe la variable de entorno.
// En producción configure process.env.JWT_SECRET con un secreto fuerte.
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-change-me';

// Middleware de autenticación simplificado (sin base de datos)
const auth = async (req, res, next) => {
  try {
    const token = req.header('Authorization')?.replace('Bearer ', '');
    
    if (!token) {
      return res.status(401).json({ error: 'Acceso denegado. Token requerido.' });
    }

  const decoded = jwt.verify(token, JWT_SECRET);
    
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
    JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '24h' }
  );
};

// Exponer el secreto para que rutas/tests puedan reutilizarlo si es necesario
const getJwtSecret = () => JWT_SECRET;

module.exports = {
  auth,
  checkRoomPermission,
  generateToken,
  getJwtSecret
};