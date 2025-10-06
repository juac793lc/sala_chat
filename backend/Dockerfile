# Dockerfile para el backend Node.js
FROM node:20-alpine

WORKDIR /usr/src/app

# Copiar package.json y package-lock.json si existe
COPY package*.json ./

# Instalar dependencias
RUN npm ci --only=production

# Copiar el resto del backend
COPY . .

# Exponer puerto
EXPOSE 3001

# Comando de inicio
CMD ["node", "server.js"]
