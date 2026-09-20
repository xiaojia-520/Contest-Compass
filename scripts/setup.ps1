param(
    [switch]$SkipIndex,
    [switch]$SkipFlutterBuild
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $projectRoot

if (-not (Test-Path '.env')) {
    $random = [byte[]]::new(48)
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($random)
    $jwtSecret = [Convert]::ToBase64String($random)
    $fernetBytes = [byte[]]::new(32)
    $rng.GetBytes($fernetBytes)
    $rng.Dispose()
    $fernetKey = [Convert]::ToBase64String($fernetBytes).Replace('+', '-').Replace('/', '_')
    $rootForEnv = $projectRoot.Replace('\', '/')
    @"
DATABASE_URL=postgresql+psycopg://saizhijian:saizhijian@127.0.0.1:5433/saizhijian
JWT_SECRET=$jwtSecret
ENCRYPTION_KEY=$fernetKey
COMPETITION_DB_PATH=$rootForEnv/saikr_competitions.db
EMBEDDING_MODEL_PATH=$rootForEnv/models/bge-small-zh-v1.5
QDRANT_URL=http://localhost:6333
QDRANT_COLLECTION=competitions_bge_small_zh_v15
CORS_ORIGINS=http://localhost:8080,http://127.0.0.1:8080,http://[::1]:8080
"@ | Set-Content -Encoding UTF8 '.env'
    Write-Host 'Generated .env with random JWT and encryption keys.' -ForegroundColor Green
}

docker compose up -d postgres
if (-not (Test-Path '.venv\Scripts\python.exe')) {
    py -3.11 -m venv .venv
}
& '.venv\Scripts\python.exe' -m pip install --upgrade pip
& '.venv\Scripts\python.exe' -m pip install -r 'backend\requirements.txt'

if (-not $SkipIndex) {
    & '.venv\Scripts\python.exe' 'backend\index_competitions.py'
}

if (-not $SkipFlutterBuild) {
    $toolRoot = $projectRoot
    if ($projectRoot -match '[^\x00-\x7F]') {
        $linkParent = Join-Path $env:TEMP 'saizhijian-tools'
        $linkRoot = Join-Path $linkParent 'workspace'
        New-Item -ItemType Directory -Force -Path $linkParent | Out-Null
        if (-not (Test-Path $linkRoot)) {
            New-Item -ItemType Junction -Path $linkRoot -Target $projectRoot | Out-Null
        }
        $toolRoot = $linkRoot
        Write-Host "Using ASCII build path: $toolRoot"
    }
    $flutter = Join-Path $toolRoot '.tools\flutter\bin\flutter.bat'
    if (-not (Test-Path $flutter)) {
        throw 'Flutter SDK was not found at .tools\flutter\bin\flutter.bat.'
    }
    $env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
    $env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
    Push-Location (Join-Path $toolRoot 'frontend')
    & $flutter pub get
    & $flutter build web --release
    Pop-Location
}

Write-Host ''
Write-Host 'Setup complete. Run scripts\run.ps1 and open http://localhost:8000' -ForegroundColor Cyan
