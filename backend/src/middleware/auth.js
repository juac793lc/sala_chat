const jwt = require('jsonwebtoken');

// Valor por defecto seguro para desarrollo si no existe la variable de entorno.
// En producción configure process.env.JWT_SECRET con un secreto fuerte.
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-change-me';

// Middleware de autenticación simplificado (sin base de datos)
const auth = async (req, res, next) => {
  try {
    // First, allow a super-user secret header to bypass token auth for full super-user actions
    const providedSuper = req.header('X-Super-User') || req.header('x-super-user');
    const SUPER_SECRET = process.env.SUPER_USER_SECRET || null;
    if (SUPER_SECRET && providedSuper && providedSuper === SUPER_SECRET) {
      req.user = {
        id: 'super_user',
        username: 'super_user',
        isAdmin: true,
        isSuper: true
      };
      return next();
    }

    // Next, allow an admin PIN header to bypass token auth for admin actions
    const providedPin = req.header('X-Admin-Pin') || req.header('x-admin-pin');
    const ADMIN_PIN = process.env.ADMIN_PIN || null;
    if (ADMIN_PIN && providedPin && providedPin === ADMIN_PIN) {
      // Treat as an admin user (no JWT required)
      req.user = {
        id: 'admin_pin',
        username: 'admin',
        isAdmin: true
      };
      return next();
    }

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