NotiMapa Telegram Bot
=====================

Pequeño bot Telegraf que ayuda a confirmar el registro del usuario cuando abre el deep-link desde la app.

Variables de entorno necesarias:

- BOT_TOKEN: token del bot (ej: 123456:ABC...)
- BOT_SECRET: secreto compartido con el backend (por defecto 'dev-bot-secret')
- BACKEND_URL: url del backend (por defecto http://localhost:3001)

Instalar y ejecutar:

```bash
cd backend/bot
npm install
npm start
```

El bot responderá a `/start <token>` mostrando un botón "Confirmar" que llamará a
`POST /api/telegram/register-confirm` en tu backend.
