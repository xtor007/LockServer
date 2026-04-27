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
ATTENDANCE_GATEWAY_URL="$GATEWAY_URL/internal/attendance-analysis"
EXTERNAL_CONTEXT_URL="http://127.0.0.1:${LOCKSERVER_EXTERNAL_CONTEXT_PORT}"
ATTENDANCE_FIXTURE_DAYS=(
  "2026-04-06"
  "2026-04-07"
  "2026-04-08"
  "2026-04-09"
  "2026-04-10"
  "2026-04-13"
  "2026-04-14"
  "2026-04-15"
  "2026-04-16"
  "2026-04-17"
  "2026-04-20"
  "2026-04-21"
  "2026-04-22"
)

ADMIN_TOKEN="$(curl -sS -u admin@lock.local:admin1234 "$GATEWAY_URL/auth/getToken" | jq -r '.auth')"
if [[ -z "$ADMIN_TOKEN" || "$ADMIN_TOKEN" == "null" ]]; then
  echo "Failed to obtain admin token for attendance materialization."
  exit 1
fi

echo "Materializing attendance-analysis fixture..."
for day in "${ATTENDANCE_FIXTURE_DAYS[@]}"; do
  curl -sS -X POST \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"day\":\"$day\"}" \
    "$ATTENDANCE_GATEWAY_URL/observations/rebuild-all" \
    | jq -e --arg day "$day" '.day == $day and .processedCount >= 7 and (.items | all(.status == "signals_ready" or .status == "insufficient_history"))' >/dev/null
done

TODAY_UTC="$(date -u +%F)"
TODAY_SAMPLE_ARRIVAL_TIME="${TODAY_UTC}T08:00:00Z"

echo "Materializing current external-context sample for $TODAY_UTC..."
if [[ -n "${LOCKSERVER_EXTERNAL_CONTEXT_PTV_API_KEY:-}" ]]; then
  if ! curl -sS -X POST \
    -H "Content-Type: application/json" \
    -d "{\"day\":\"$TODAY_UTC\",\"arrivalTime\":\"$TODAY_SAMPLE_ARRIVAL_TIME\"}" \
    "$EXTERNAL_CONTEXT_URL/internal/external-context/traffic/resolve" \
    | jq -e '.trafficScore != null' >/dev/null; then
    echo "Warning: failed to materialize current traffic sample."
  fi
fi

if ! curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"day\":\"$TODAY_UTC\",\"arrivalTime\":\"$TODAY_SAMPLE_ARRIVAL_TIME\"}" \
  "$EXTERNAL_CONTEXT_URL/internal/external-context/power/resolve" \
  | jq -e 'has("powerScore")' >/dev/null; then
  echo "Warning: failed to materialize current power sample."
fi

if ! curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"day\":\"$TODAY_UTC\",\"arrivalTime\":\"$TODAY_SAMPLE_ARRIVAL_TIME\"}" \
  "$EXTERNAL_CONTEXT_URL/internal/external-context/weather/resolve" \
  | jq -e 'has("weatherScore")' >/dev/null; then
  echo "Warning: failed to materialize current weather sample."
fi

echo "Attendance-analysis fixture is materialized."
