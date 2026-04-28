#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="${1:-$ROOT_DIR/infrastructure/local/.env.local}"

if [[ ! -f "$ENV_FILE" ]]; then
  ENV_FILE="$ROOT_DIR/infrastructure/local/.env.example"
fi

JQ_BIN="$(command -v jq || true)"
CURL_BIN="$(command -v curl || true)"

if [[ -z "$JQ_BIN" ]]; then
  echo "jq is required for attendance risk verification."
  exit 1
fi

if [[ -z "$CURL_BIN" ]]; then
  echo "curl is required for attendance risk verification."
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

GATEWAY_URL="http://127.0.0.1:${LOCKSERVER_GATEWAY_PORT}"
USER_ID="33333333-3333-3333-3333-333333333333"
CORRECTED_ETA="0.90"

MYSQL=(
  /usr/local/mysql/bin/mysql
  -h "$LOCKSERVER_DB_HOST"
  -P "$LOCKSERVER_DB_PORT"
  -u"$LOCKSERVER_DB_USER"
  -p"$LOCKSERVER_DB_PASSWORD"
  lockService
)

TOKEN="$("$CURL_BIN" -sS -u admin@lock.local:admin1234 "$GATEWAY_URL/auth/getToken" | "$JQ_BIN" -r '.auth')"
if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "Failed to obtain admin token."
  exit 1
fi

READY_DAY="$("${MYSQL[@]}" -N -s -e "
SELECT DATE_FORMAT(day, '%Y-%m-%d')
FROM attendance_analysis_results
WHERE user_id = UUID_TO_BIN('$USER_ID')
  AND status = 'ready_for_next_stage'
ORDER BY day
LIMIT 1
")"

STABLE_DAY="$("${MYSQL[@]}" -N -s -e "
SELECT DATE_FORMAT(day, '%Y-%m-%d')
FROM attendance_analysis_results
WHERE user_id = UUID_TO_BIN('$USER_ID')
  AND cluster_name = 'Stable Normal'
ORDER BY day
LIMIT 1
")"

OUTLIER_DAY="$("${MYSQL[@]}" -N -s -e "
SELECT DATE_FORMAT(day, '%Y-%m-%d')
FROM attendance_analysis_results
WHERE user_id = UUID_TO_BIN('$USER_ID')
  AND cluster_name = 'Technical Outlier'
ORDER BY day
LIMIT 1
")"

if [[ -z "$READY_DAY" || -z "$STABLE_DAY" || -z "$OUTLIER_DAY" ]]; then
  echo "Failed to locate ready/stable/outlier fixture days for risk verification."
  exit 1
fi

auth_post() {
  local path="$1"
  local body="$2"
  "$CURL_BIN" -sS -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$body" \
    "$GATEWAY_URL$path"
}

auth_get() {
  local path="$1"
  "$CURL_BIN" -sS -H "Authorization: Bearer $TOKEN" "$GATEWAY_URL$path"
}

echo "Checking automatic risk calculation after normal MLP flow..."
auth_post "/internal/attendance-analysis/observations/rebuild" "{\"userId\":\"$USER_ID\",\"day\":\"$READY_DAY\"}" | "$JQ_BIN" -e '
  .status == "signals_ready"
  and .result.clusteringStatus == "not_started"
  and .result.riskScore == null
  and .result.riskZone == null
' >/dev/null

auth_post "/internal/attendance-analysis/clustering/rebuild" "{\"userId\":\"$USER_ID\",\"day\":\"$READY_DAY\"}" | "$JQ_BIN" -e '
  .processedCount == 1
  and .clusteredCount == 1
  and .items[0].result.status == "ready_for_next_stage"
  and .items[0].result.etaNN == null
  and .items[0].result.riskScore == null
  and .items[0].result.riskZone == null
' >/dev/null

MLP_RUN="$(auth_post "/internal/attendance-analysis/mlp/run" "{\"userId\":\"$USER_ID\",\"day\":\"$READY_DAY\"}")"
echo "$MLP_RUN" | "$JQ_BIN" -e '
  .processedCount == 1
  and .inferredCount == 1
  and .items[0].result.etaNN != null
  and .items[0].result.riskScore != null
  and .items[0].result.riskZone != null
' >/dev/null
BASELINE_RISK="$(echo "$MLP_RUN" | "$JQ_BIN" -r '.items[0].result.riskScore')"

echo "Checking automatic risk recalculation after manual eta_nn correction..."
MLP_FEEDBACK="$(auth_post "/internal/attendance-analysis/mlp/feedback" "{\"userId\":\"$USER_ID\",\"day\":\"$READY_DAY\",\"etaNn\":$CORRECTED_ETA}")"
echo "$MLP_FEEDBACK" | "$JQ_BIN" -e --arg eta "$CORRECTED_ETA" --arg baseline "$BASELINE_RISK" '
  .result.etaNN == ($eta | tonumber)
  and .result.mlpStatus == "manually_corrected"
  and .result.riskScore != null
  and .result.riskScore != ($baseline | tonumber)
  and .result.riskZone != null
' >/dev/null

echo "Checking manual risk/run for one user + day..."
"${MYSQL[@]}" -e "
UPDATE attendance_analysis_results
SET risk_score = NULL, risk_zone = NULL
WHERE user_id = UUID_TO_BIN('$USER_ID')
  AND day = '${READY_DAY} 00:00:00'
"

auth_post "/internal/attendance-analysis/risk/run" "{\"userId\":\"$USER_ID\",\"day\":\"$READY_DAY\"}" | "$JQ_BIN" -e '
  .processedCount == 1
  and .calculatedCount == 1
  and .items[0].wasCalculated == true
  and .items[0].result.riskScore != null
  and .items[0].result.riskZone != null
' >/dev/null

ELIGIBLE_DAY_COUNT="$("${MYSQL[@]}" -N -s -e "
SELECT COUNT(*)
FROM attendance_analysis_results
WHERE day = '${READY_DAY} 00:00:00'
  AND status = 'ready_for_next_stage'
")"

echo "Checking manual risk/run for the whole day..."
"${MYSQL[@]}" -e "
UPDATE attendance_analysis_results
SET risk_score = NULL, risk_zone = NULL
WHERE day = '${READY_DAY} 00:00:00'
  AND status = 'ready_for_next_stage'
"

auth_post "/internal/attendance-analysis/risk/run" "{\"day\":\"$READY_DAY\"}" | "$JQ_BIN" -e --argjson eligible "$ELIGIBLE_DAY_COUNT" '
  .calculatedCount == $eligible
  and ([.items[] | select(.status == "ready_for_next_stage" and .result.riskScore == null)] | length) == 0
' >/dev/null

echo "Checking manual risk/rebuild for one user + day..."
"${MYSQL[@]}" -e "
UPDATE attendance_analysis_results
SET risk_score = 0, risk_zone = 'green'
WHERE user_id = UUID_TO_BIN('$USER_ID')
  AND day = '${READY_DAY} 00:00:00'
"

auth_post "/internal/attendance-analysis/risk/rebuild" "{\"userId\":\"$USER_ID\",\"day\":\"$READY_DAY\"}" | "$JQ_BIN" -e '
  .processedCount == 1
  and .calculatedCount == 1
  and .items[0].result.riskScore != 0
  and .items[0].result.riskZone != "green"
' >/dev/null

echo "Checking manual risk/rebuild for the whole day..."
"${MYSQL[@]}" -e "
UPDATE attendance_analysis_results
SET risk_score = 0, risk_zone = 'green'
WHERE day = '${READY_DAY} 00:00:00'
  AND status = 'ready_for_next_stage'
"

auth_post "/internal/attendance-analysis/risk/rebuild" "{\"day\":\"$READY_DAY\"}" | "$JQ_BIN" -e --arg userId "$USER_ID" --argjson eligible "$ELIGIBLE_DAY_COUNT" '
  .calculatedCount == $eligible
  and ([.items[] | select(.status == "ready_for_next_stage" and .result.riskScore == null)] | length) == 0
  and ([.items[] | select(.userId == $userId)][0].result.riskZone) != "green"
' >/dev/null

echo "Checking user-level risk read endpoint and non-applicable rows..."
USER_RISK="$(auth_get "/internal/attendance-analysis/risk/user/$USER_ID")"
echo "$USER_RISK" | "$JQ_BIN" -e --arg readyDay "$READY_DAY" --arg stableDay "$STABLE_DAY" --arg outlierDay "$OUTLIER_DAY" '
  any(.items[]; .day == $readyDay and .workDeltaMinutes != null and .cluster != null and .etaNN != null and .riskScore != null and .riskZone != null)
  and any(.items[]; .day == $stableDay and .cluster == "Stable Normal" and .riskScore == null and .riskZone == null)
  and any(.items[]; .day == $outlierDay and .cluster == "Technical Outlier" and .riskScore == null and .riskZone == null)
' >/dev/null

echo "Checking date-level risk read endpoint..."
auth_get "/internal/attendance-analysis/risk/day/$READY_DAY" | "$JQ_BIN" -e --arg userId "$USER_ID" '
  (.items | length) > 0
  and any(.items[]; .user.id == $userId and .workDeltaMinutes != null and .cluster != null and .etaNN != null and .riskScore != null and .riskZone != null)
' >/dev/null

echo "Checking current /results surface includes risk..."
auth_get "/internal/attendance-analysis/users/$USER_ID/results" | "$JQ_BIN" -e --arg readyDay "$READY_DAY" '
  any(.results[]; .day == $readyDay and .riskScore != null and .riskZone != null)
' >/dev/null

echo "Checking whole-database risk materialization state..."
READY_TOTAL="$("${MYSQL[@]}" -N -s -e "
SELECT COUNT(*)
FROM attendance_analysis_results
WHERE status = 'ready_for_next_stage'
")"
READY_MISSING_RISK="$("${MYSQL[@]}" -N -s -e "
SELECT COUNT(*)
FROM attendance_analysis_results
WHERE status = 'ready_for_next_stage'
  AND (risk_score IS NULL OR risk_zone IS NULL)
")"
NON_READY_WITH_RISK="$("${MYSQL[@]}" -N -s -e "
SELECT COUNT(*)
FROM attendance_analysis_results
WHERE status != 'ready_for_next_stage'
  AND (risk_score IS NOT NULL OR risk_zone IS NOT NULL)
")"

if [[ "$READY_TOTAL" -le 0 ]]; then
  echo "Expected at least one ready_for_next_stage row."
  exit 1
fi

if [[ "$READY_MISSING_RISK" -ne 0 ]]; then
  echo "Found ready_for_next_stage rows without risk: $READY_MISSING_RISK"
  exit 1
fi

if [[ "$NON_READY_WITH_RISK" -ne 0 ]]; then
  echo "Found non-ready rows with fake risk: $NON_READY_WITH_RISK"
  exit 1
fi

echo "Attendance risk runtime checks passed."
