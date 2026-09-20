param(
    [string]$ApiBaseUrl = "",
    [switch]$SkipWeb,
    [switch]$SkipAndroid,
    [switch]$SkipWindows
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$flutter = Join-Path $projectRoot '.tools\flutter\bin\flutter.bat'
$frontend = Join-Path $projectRoot 'frontend'

if (-not (Test-Path -LiteralPath $flutter)) {
    throw 'Flutter SDK was not found. Run scripts\setup.ps1 first.'
}

Push-Location $frontend
try {
    & $flutter pub get
    $define = "--dart-define=API_BASE_URL=$ApiBaseUrl"
    if (-not $SkipWeb) {
        & $flutter build web --release $define
        if ($LASTEXITCODE -ne 0) { throw 'Flutter Web build failed.' }
    }
    if (-not $SkipAndroid) {
        & $flutter build apk --release --split-per-abi $define
        if ($LASTEXITCODE -ne 0) { throw 'Android APK build failed.' }
        & $flutter build appbundle --release $define
        if ($LASTEXITCODE -ne 0) { throw 'Android AAB build failed.' }
    }
    if (-not $SkipWindows) {
        & $flutter build windows --release $define
        if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }

        $iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
        if ($iscc) {
            $env:APP_VERSION = ((Get-Content pubspec.yaml | Select-String '^version:').Line -replace '^version:\s*', '' -replace '\+.*$', '')
            & $iscc.Source (Join-Path $projectRoot 'installer\windows\saizhijian.iss')
            if ($LASTEXITCODE -ne 0) { throw 'Inno Setup build failed.' }
        } else {
            Write-Warning 'ISCC.exe was not found; skipping the Windows installer.'
        }
    }
} finally {
    Pop-Location
}
