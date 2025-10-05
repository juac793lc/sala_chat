# 📡 **Servidor Node.js para Archivos Multimedia**

## 🚀 **Endpoints Necesarios**

### 1. **POST /api/upload-media**
Recibe archivos multimedia desde el cliente Flutter.

```javascript
const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

const app = express();

// Configurar multer para upload de archivos
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    const mediaType = req.body.mediaType || 'general';
    const uploadDir = path.join(__dirname, 'uploads', mediaType);
    
    // Crear directorio si no existe
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    const timestamp = Date.now();
    const extension = path.extname(file.originalname);
    const mediaType = req.body.mediaType || 'file';
    cb(null, `${mediaType}_${timestamp}${extension}`);
  }
});

const upload = multer({ storage: storage });

app.post('/api/upload-media', upload.single('file'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No se recibió archivo' });
    }

    const fileUrl = `${req.protocol}://${req.get('host')}/uploads/${req.body.mediaType}/${req.file.filename}`;
    
    res.status(201).json({
      url: fileUrl,
      fileName: req.file.filename,
      fileId: Date.now().toString(),
      fileSize: req.file.size,
      mimeType: req.file.mimetype,
      uploadedAt: new Date().toISOString()
    });
  } catch (error) {
    console.error('Error en upload:', error);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
});
```

### 2. **GET /uploads/:type/:filename**
Sirve los archivos multimedia.

```javascript
// Servir archivos estáticos
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Middleware para logs
app.use('/uploads', (req, res, next) => {
  console.log(`📥 Descargando: ${req.path}`);
  next();
});
```

### 3. **Estructura de Carpetas del Servidor**
```
servidor/
├── uploads/
│   ├── audio/
│   │   ├── audio_1696348822000.m4a
│   │   └── audio_1696348855000.m4a
│   ├── image/
│   │   ├── img_1696348822000.jpg
│   │   └── img_1696348855000.png
│   └── video/
│       ├── vid_1696348822000.mp4
│       └── vid_1696348855000.mp4
├── server.js
└── package.json
```

## 🔧 **Configuración Rápida**

### **package.json**
```json
{
  "name": "sala-chat-server",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.0",
    "multer": "^1.4.5",
    "socket.io": "^4.7.0",
    "cors": "^2.8.5"
  }
}
```

### **Instalar y ejecutar:**
```bash
npm install
node server.js
```

## 🔄 **Flujo Completo**

1. **Cliente Flutter graba audio** → archivo temporal
2. **MediaStorageService.saveAudio()** → guarda permanente local
3. **UploadService.uploadAudio()** → envía al servidor
4. **Servidor guarda** → `/uploads/audio/audio_123.m4a`
5. **Servidor responde** → `{"url": "http://server.com/uploads/audio/audio_123.m4a"}`
6. **Cliente crea comentario** → con URL del servidor
7. **Otros clientes reciben** → comentario con URL
8. **AudioPlaylistService reproduce** → desde URL del servidor

## ✅ **Ventajas Implementadas**

- ✅ **Archivos persistentes** (no se pierden al cerrar app)
- ✅ **Historial completo** (todos ven todos los audios)
- ✅ **Almacenamiento organizado** (como WhatsApp)
- ✅ **URLs de servidor** (acceso desde cualquier cliente)
- ✅ **Reproducción automática** con animaciones sincronizadas
- ✅ **Compatibilidad** (maneja URLs, archivos locales, blob URLs)

## 🎯 **¿Qué Falta?**

Solo implementar el **servidor Node.js** con los endpoints mostrados arriba. El cliente Flutter ya está listo para usarlo.