# deploy_railway.ps1 - Script para desplegar el repo actual a Railway
# Uso: abrir PowerShell en la carpeta del repo y ejecutar: .\deploy_railway.ps1  (o con parámetro de branch)

param(
    [string]$Branch = 'main'
)

Write-Host "Ruta de trabajo: $PWD"
Write-Host "Actualizando repo local (branch: $Branch)..."

git fetch origin
git checkout $Branch
git pull origin $Branch

# Comprobar Railway CLI
try {
    $railwayVersion = railway --version 2>$null
} catch {
    $railwayVersion = $null
}

if (-not $railwayVersion) {
    Write-Host "railway CLI no detectada. Instala con: npm install -g railway" -ForegroundColor Yellow
    exit 1
}

Write-Host "railway CLI detectada: $railwayVersion"

Write-Host "Asegúrate de haber hecho 'railway login' previamente. Si no, ejecuta: railway login" -ForegroundColor Cyan

# Intentar linkear si no existe archivo .railway
if (-not (Test-Path -Path ".railway")) {
    Write-Host ".railway no encontrada. Ejecutando 'railway link' (sigue los prompts)..." -ForegroundColor Yellow
    railway link
}

Write-Host "Desplegando con 'railway up'..." -ForegroundColor Green
railway up

Write-Host "Despliegue terminado (o en progreso). Revisa logs con: railway logs" -ForegroundColor Green
Write-Host "Comprueba la URL pública en el dashboard de Railway o con: railway status" -ForegroundColor Cyan

Write-Host "Comprobación rápida de endpoint (reemplaza <URL> si la conoces):"
Write-Host "curl -i https://<tu-servicio>.up.railway.app/health" -ForegroundColor Magenta
