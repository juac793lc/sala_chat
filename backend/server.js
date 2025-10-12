const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const path = require('path');
require('dotenv').config();

const authRoutes = require('./src/routes/auth');
const mediaRoutes = require('./src/routes/media');
const { handleSocketConnection } = require('./src/controllers/socketController');
// Base de datos en memoria existente (usuarios/salas simples)
const db = require('./src/config/memory_db');
// Nuevo backend persistente SQLite para media y mensajes
const sqlite = require('./src/config/sqlite_db');
// Poller de Telegram (auto-registro de chat_id)
const telegramPoller = require('./src/services/telegramPoller');

const app = express();
// Cuando la app corre detrás de un proxy (Railway, Heroku, etc.)
// indicar un valor concreto de 'trust proxy' (1) en vez de `true` para
// evitar advertencias/errores de seguridad con express-rate-limit.
// Ver: https://express-rate-limit.github.io/ERR_ERL_PERMISSIVE_TRUST_PROXY/
app.set('trust proxy', 1);
const server = http.createServer(app);

// Configuración de Socket.IO con CORS
const io = socketIo(server, {
  cors: {
    origin: true, // Permitir todos los orígenes para desarrollo
    methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    credentials: true,
    allowedHeaders: ["Content-Type", "Authorization", "X-Requested-With"]
  }
});

// Middlewares de seguridad (ajustados para permitir reproducción de audio cross-origin en desarrollo)
app.use(helmet({
  crossOriginResourcePolicy: { policy: 'cross-origin' }, // permitir que navegadores consuman media desde otro puerto
  crossOriginEmbedderPolicy: false, // desactivar COEP para evitar bloquear decodificación
  contentSecurityPolicy: false, // simplificar en dev
  originAgentCluster: false,
}));
// Custom CORS reflector middleware
// Refleja el Origin recibido para que el navegador reciba Access-Control-Allow-Origin
// igual al Origin de la petición (útil en desarrollo/local). En producción es
// preferible usar una lista blanca de orígenes.
app.use((req, res, next) => {
  const origin = req.get('Origin') || req.get('origin') || '*';
  // Si el origen viene vacío (requests directas desde curl/servers), usamos '*'
  res.header('Access-Control-Allow-Origin', origin);
  res.header('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With, Accept');
  res.header('Access-Control-Allow-Credentials', 'true');
  // Forra OPTIONS preflight responses
  if (req.method === 'OPTIONS') {
    return res.sendStatus(204);
  }
  next();
});

// Rate limiting (se puede desactivar en despliegues temporales mediante SKIP_RATE_LIMIT=true)
if (process.env.SKIP_RATE_LIMIT !== 'true') {
  const limiter = rateLimit({
    windowMs: (process.env.RATE_LIMIT_WINDOW || 15) * 60 * 1000, // 15 minutos
    max: process.env.RATE_LIMIT_MAX_REQUESTS || 100,
    message: {
      error: 'Demasiadas peticiones, intenta de nuevo más tarde'
    }
  });
  app.use('/api/', limiter);
} else {
  console.warn('⚠️ SKIP_RATE_LIMIT=true -> express-rate-limit deshabilitado temporalmente');
}

// Middleware de logging para debug
app.use((req, res, next) => {
  console.log(`📝 ${new Date().toISOString()} - ${req.method} ${req.url}`);
  console.log(`🌍 Origin: ${req.get('Origin')}`);
  console.log(`� User-Agent: ${req.get('User-Agent')}`);
  next();
});

// Middleware específico para preflight requests
app.options('*', (req, res) => {
  console.log('🚀 Preflight OPTIONS request recibido');
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE,OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization, Content-Length, X-Requested-With');
  res.sendStatus(200);
});

// Middlewares para parsing
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Archivos estáticos para uploads con headers apropiados
// Nota: Los uploads se guardan bajo backend/src/uploads/<tipo>
// Por eso servimos la carpeta 'src/uploads'
const UPLOADS_REAL_PATH = path.join(__dirname, 'src', 'uploads');
console.log('📂 Static uploads path:', UPLOADS_REAL_PATH);
app.use('/uploads', (req, res, next) => {
  // Headers para archivos multimedia
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Range');
  res.header('Access-Control-Expose-Headers', 'Content-Length, Content-Range, Accept-Ranges');
  res.header('Accept-Ranges', 'bytes');
  
  // Configurar MIME types correctos para archivos multimedia
  if (req.url.endsWith('.wav') || (req.url.includes('audio_') && req.url.endsWith('.wav'))) {
    res.header('Content-Type', 'audio/wav');
  } else if (req.url.endsWith('.m4a') || (req.url.includes('audio_') && req.url.endsWith('.m4a'))) {
    res.header('Content-Type', 'audio/mp4');
  } else if (req.url.endsWith('.webm') || (req.url.includes('audio_') && req.url.endsWith('.webm'))) {
    res.header('Content-Type', 'audio/webm');
  } else if (req.url.endsWith('.mp3')) {
    res.header('Content-Type', 'audio/mpeg');
  } else if (req.url.endsWith('.jpg') || req.url.endsWith('.jpeg')) {
    res.header('Content-Type', 'image/jpeg');
  } else if (req.url.endsWith('.png')) {
    res.header('Content-Type', 'image/png');
  } else if (req.url.endsWith('.mp4')) {
    res.header('Content-Type', 'video/mp4');
  }
  
  console.log(`📥 Sirviendo archivo multimedia: ${req.url}`);
  next();
}, express.static(UPLOADS_REAL_PATH));

// Servir archivos estáticos de Flutter (para desarrollo)
app.use(express.static('../build/web'));

// Mostrar estadísticas de la base de datos en memoria
console.log('💾 Usando base de datos en memoria (usuarios/salas)');
console.log('�️ SQLite inicializado para media/messages persistentes');
console.log('�📊 Estadísticas iniciales memoria:', db.getStats());

// Rutas API
app.use('/api/auth', authRoutes);
app.use('/api/media', mediaRoutes);
app.use('/api/messages', require('./src/routes/messages'));
// Rutas para Web Push (PWA)
app.use('/api/push', require('./src/routes/push'));
// Rutas para integración con Telegram (notificaciones alternativas)
app.use('/api/telegram', require('./src/routes/telegram'));

// Ruta de health check
app.get('/health', (req, res) => {
  res.json({ 
    status: 'OK', 
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: process.env.NODE_ENV || 'development'
  });
});

// Manejo de conexiones Socket.IO
io.on('connection', (socket) => {
  console.log(`👤 Usuario conectado: ${socket.id}`);
  handleSocketConnection(socket, io);
});

// Middleware de manejo de errores
app.use((err, req, res, next) => {
  console.error('❌ Error:', err.stack);
  res.status(500).json({ 
    error: 'Error interno del servidor',
    message: process.env.NODE_ENV === 'development' ? err.message : 'Algo salió mal'
  });
});

// Manejo de rutas no encontradas
app.use('*', (req, res) => {
  res.status(404).json({ error: 'Ruta no encontrada' });
});

const PORT = process.env.PORT || 3001;

// Inicializar SQLite antes de arrancar el servidor
sqlite.ensureInit().then(() => {
  server.listen(PORT, () => {
    console.log(`🚀 Servidor corriendo en puerto ${PORT}`);
    console.log(`🔗 Socket.IO habilitado para chat en tiempo real`);
    console.log(`🌍 Entorno: ${process.env.NODE_ENV || 'development'}`);
    // Iniciar poller de Telegram si hay token
    if (process.env.TELEGRAM_BOT_TOKEN) {
      try {
        telegramPoller.start(5000);
      } catch (e) {
        console.warn('No se pudo iniciar telegramPoller:', e.message || e);
      }
    }
  });
}).catch(error => {
  console.error('❌ Error inicializando SQLite:', error);
  process.exit(1);
});