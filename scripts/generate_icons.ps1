# Genera los iconos para PWA desde assets/images/moto.png usando ImageMagick (convert)
# Requiere ImageMagick instalado y en PATH.
# Uso: .\scripts\generate_icons.ps1

$src = "assets/images/moto.png"
$destDir = "web/icons"

if (-not (Test-Path $src)) {
    Write-Error "No se encontró $src"
    exit 1
}

if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir | Out-Null
}

# Generar 192 y 512
magick convert $src -resize 192x192^ -gravity center -background none -extent 192x192 "$destDir/moto-192.png"
magick convert $src -resize 512x512^ -gravity center -background none -extent 512x512 "$destDir/moto-512.png"
# Generar maskable (simplemente copia si no se necesita recorte especial)
Copy-Item "$destDir/moto-192.png" "$destDir/moto-maskable-192.png" -Force
Copy-Item "$destDir/moto-512.png" "$destDir/moto-maskable-512.png" -Force

Write-Host "Iconos generados en $destDir"
