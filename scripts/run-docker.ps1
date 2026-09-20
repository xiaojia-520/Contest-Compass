$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $projectRoot

if (-not (Test-Path '.env')) {
    throw 'Missing .env. Copy .env.example to .env and set secure secrets first.'
}

$toolRoot = $projectRoot
if ($projectRoot -match '[^\x00-\x7F]') {
    $linkParent = Join-Path $env:TEMP 'saizhijian-tools'
    $linkRoot = Join-Path $linkParent 'workspace'
    New-Item -ItemType Directory -Force -Path $linkParent | Out-Null
    if (-not (Test-Path $linkRoot)) {
        New-Item -ItemType Junction -Path $linkRoot -Target $projectRoot | Out-Null
    }
    $toolRoot = $linkRoot
}

$flutter = Join-Path $toolRoot '.tools\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) {
    throw 'Flutter SDK was not found at .tools\flutter\bin\flutter.bat. Run scripts\setup.ps1 first.'
}
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
Push-Location (Join-Path $toolRoot 'frontend')
try {
    & $flutter pub get
    & $flutter build web --release
} finally {
    Pop-Location
}

docker compose up -d --build
docker compose ps
Write-Host ''
Write-Host 'Saizhijian stack is starting at http://localhost:8000' -ForegroundColor Cyan
Write-Host 'Use docker compose logs -f api worker beat to follow startup.' -ForegroundColor Yellow
