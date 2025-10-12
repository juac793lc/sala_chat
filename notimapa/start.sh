#!/usr/bin/env bash
set -euo pipefail

# Root delegator script para Railpack/Railway
# Si existe el start.sh interno lo delega; si no, intenta ejecutar npm start en backend
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "$ROOT_DIR/sala_chat/start.sh" ]; then
  echo "[root start.sh] Delegando a sala_chat/start.sh"
  chmod +x "$ROOT_DIR/sala_chat/start.sh" || true
  exec "$ROOT_DIR/sala_chat/start.sh"
else
  echo "[root start.sh] start.sh interno no encontrado, intentando npm start en sala_chat/backend"
  if [ -f "$ROOT_DIR/sala_chat/backend/package.json" ]; then
    cd "$ROOT_DIR/sala_chat/backend"
    echo "[root start.sh] Ejecutando: npm run start (en sala_chat/backend)"
    exec npm run start
  else
    echo "[root start.sh] No se encontró start.sh ni package.json en sala_chat/backend; saliendo"
    exit 1
  fi
fi
