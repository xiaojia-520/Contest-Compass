$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $projectRoot

if (-not (Test-Path '.venv\Scripts\python.exe')) {
    throw 'Run scripts\setup.ps1 first.'
}
& '.venv\Scripts\python.exe' 'backend\index_competitions.py'
