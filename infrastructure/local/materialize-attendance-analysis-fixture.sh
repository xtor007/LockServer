#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="${1:-$ROOT_DIR/infrastructure/local/.env.local}"

if [[ ! -f "$ENV_FILE" ]]; then
  ENV_FILE="$ROOT_DIR/infrastructure/local/.env.example"
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for attendance materialization."
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

GATEWAY_URL="http://127.0.0.1:${LOCKSERVER_GATEWAY_PORT}"
ROOT_BUILD_DIR="$ROOT_DIR"

echo "Materializing attendance-analysis fixture..."
env HOME=/tmp/codex-home CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift build >/dev/null
BIN_DIR="$(env HOME=/tmp/codex-home CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift build --show-bin-path)"
"$BIN_DIR/AttendanceAnalysisService" materialize-fixture --env development >/dev/null

ADMIN_TOKEN="$(curl -sS -u admin@lock.local:admin1234 "$GATEWAY_URL/auth/getToken" | jq -r '.auth')"
if [[ -z "$ADMIN_TOKEN" || "$ADMIN_TOKEN" == "null" ]]; then
  echo "Failed to obtain admin token for attendance materialization verification."
  exit 1
fi

curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$GATEWAY_URL/internal/attendance-analysis/users/33333333-3333-3333-3333-333333333333/results" \
  | jq -e '.results | length >= 200 and all(.status == "signals_ready")' >/dev/null

echo "Attendance-analysis fixture is materialized."
