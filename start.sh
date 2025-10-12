#!/usr/bin/env bash
set -euo pipefail

# Script de arranque para Railpack / Railway
# Entra al directorio backend, instala dependencias y ejecuta el comando disponible.

cd "$(dirname "$0")/backend"

echo "[start.sh] Instalando dependencias en backend..."
if [ -f package-lock.json ] || [ -f yarn.lock ]; then
  npm ci --silent || npm install --silent
else
  npm install --silent
fi

echo "[start.sh] Buscando script de arranque (start / dev)..."
# Si existe script start -> npm run start, si no existe dev -> npm run dev, si no -> node index.js
if npm run | grep -q "start"; then
  echo "[start.sh] Ejecutando: npm run start"
  npm run start
elif npm run | grep -q "dev"; then
  echo "[start.sh] Ejecutando: npm run dev"
  npm run dev
else
  echo "[start.sh] Ningún script start/dev detectado, intentando node index.js"
  node index.js
fi
