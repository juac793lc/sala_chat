<#
scripts/redeploy.ps1

Uso: Ejecuta un redeploy del servicio ligado en Railway y muestra logs en tiempo real.
Este script asume que ya hiciste `railway link` y que estás logueado (railway login).

Ejemplo:
  PowerShell> .\scripts\redeploy.ps1

Opciones:
  -TailLogs : Si se pasa, hace 'railway logs --tail' tras el redeploy (por defecto true)
#>

[CmdletBinding()]
param(
    [switch]$TailLogs = $true
)

Write-Host "Iniciando redeploy en Railway..." -ForegroundColor Cyan

try {
    # Ejecutar redeploy de la última imagen
    $redeploy = railway redeploy 2>&1
    Write-Host $redeploy

    if ($TailLogs) {
        Write-Host "Mostrando logs en tiempo real (Ctrl+C para salir)..." -ForegroundColor Yellow
        # Mostrar logs en tail
        railway logs --tail
    } else {
        Write-Host "Redeploy completado. Ejecuta 'railway logs --tail' para ver logs." -ForegroundColor Green
    }
} catch {
    Write-Host "Error ejecutando redeploy: $_" -ForegroundColor Red
    exit 1
}
