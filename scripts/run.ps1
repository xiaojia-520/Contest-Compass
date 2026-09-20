param(
    [int]$Port = 8000
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $projectRoot

if (-not (Test-Path '.env')) {
    throw 'Missing .env. Run scripts\setup.ps1 first.'
}
if (-not (Test-Path '.venv\Scripts\python.exe')) {
    throw 'Missing Python virtual environment. Run scripts\setup.ps1 first.'
}

docker compose up -d postgres redis
& '.venv\Scripts\python.exe' -m alembic -c 'alembic.ini' upgrade head
Write-Host "Saizhijian is listening on IPv6 port $Port." -ForegroundColor Cyan
Write-Host "Local URL: http://localhost:$Port"
Write-Host 'Configure a domain and HTTPS before public access. Never send real API keys over plain HTTP.' -ForegroundColor Yellow
& '.venv\Scripts\python.exe' -m uvicorn app.main:app --app-dir backend --host '::' --port $Port
