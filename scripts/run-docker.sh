#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

if [[ ! -f .env ]]; then
  echo 'Missing .env. Copy .env.example to .env and set secure secrets first.' >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo 'Flutter was not found on PATH. Install Flutter before deploying.' >&2
  exit 1
fi

(
  cd frontend
  flutter pub get
  flutter build web --release
)

docker compose up -d --build
docker compose ps
echo
echo 'Saizhijian stack is starting at http://localhost:8000'
echo 'Use docker compose logs -f api worker beat to follow startup.'
