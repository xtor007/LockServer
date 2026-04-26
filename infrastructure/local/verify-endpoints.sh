#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="${1:-$ROOT_DIR/infrastructure/local/.env.local}"

if [[ ! -f "$ENV_FILE" ]]; then
  ENV_FILE="$ROOT_DIR/infrastructure/local/.env.example"
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for verification."
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

GATEWAY_URL="http://127.0.0.1:${LOCKSERVER_GATEWAY_PORT}"
AUTH_URL="http://127.0.0.1:${LOCKSERVER_AUTH_PORT}"
DIRECTORY_URL="http://127.0.0.1:${LOCKSERVER_DIRECTORY_PORT}"
ACCESS_URL="http://127.0.0.1:${LOCKSERVER_ACCESS_PORT}"
DEVICE_URL="http://127.0.0.1:${LOCKSERVER_DEVICE_PORT}"
ATTENDANCE_URL="http://127.0.0.1:${LOCKSERVER_ATTENDANCE_ANALYSIS_PORT}"
ATTENDANCE_GATEWAY_URL="$GATEWAY_URL/internal/attendance-analysis"

ATTENDANCE_NORMAL_ID="33333333-3333-3333-3333-333333333333"
ATTENDANCE_SPLIT_ID="44444444-4444-4444-4444-444444444444"
ATTENDANCE_SHORT_ID="55555555-5555-5555-5555-555555555555"
ATTENDANCE_BROKEN_ID="66666666-6666-6666-6666-666666666666"
ATTENDANCE_NIGHT_ID="77777777-7777-7777-7777-777777777777"
ATTENDANCE_BATCH_DAY="2026-04-22"
ATTENDANCE_RESULTS_COUNT=10

assert_true_json() {
  local response="$1"
  echo "$response" | jq -e '.isValid == true' >/dev/null
}

echo "Checking service health..."
assert_true_json "$(curl -sS "$GATEWAY_URL/validate")"
assert_true_json "$(curl -sS "$AUTH_URL/validate")"
assert_true_json "$(curl -sS "$DIRECTORY_URL/validate")"
assert_true_json "$(curl -sS "$ACCESS_URL/validate")"
assert_true_json "$(curl -sS "$DEVICE_URL/validate")"
assert_true_json "$(curl -sS "$ATTENDANCE_URL/validate")"

echo "Requesting user token..."
USER_TOKEN_RESPONSE="$(curl -sS -u user@lock.local:user1234 "$GATEWAY_URL/auth/getToken")"
USER_AUTH="$(echo "$USER_TOKEN_RESPONSE" | jq -r '.auth')"
USER_REFRESH="$(echo "$USER_TOKEN_RESPONSE" | jq -r '.refresh')"

echo "Refreshing token..."
REFRESH_RESPONSE="$(curl -sS -H "Authorization: Bearer $USER_REFRESH" "$GATEWAY_URL/auth/refresh")"
echo "$REFRESH_RESPONSE" | jq -e '.auth | length > 0' >/dev/null

echo "Verifying password reset flow..."
RESET_CODE="$(curl -sS -X POST -H "Content-Type: application/json" -d '{"email":"user@lock.local"}' "$GATEWAY_URL/auth/changePasswordEmail" | jq -r '.code')"
assert_true_json "$(curl -sS -u user@lock.local:$RESET_CODE -X POST -H "Content-Type: application/json" -d '{"password":"user1234"}' "$GATEWAY_URL/auth/changePassword")"

echo "Loading user-facing endpoints..."
curl -sS -H "Authorization: Bearer $USER_AUTH" "$GATEWAY_URL/info/" | jq -e '.email == "user@lock.local" and .workNormMinutes == 480' >/dev/null
curl -sS -H "Authorization: Bearer $USER_AUTH" -X POST -H "Content-Type: application/json" -d '{"valid":true,"id":null,"afterDate":null}' "$GATEWAY_URL/info/logs" | jq -e '.logs | length >= 1' >/dev/null
curl -sS -H "Authorization: Bearer $USER_AUTH" "$GATEWAY_URL/info/statistic" | jq -e '.averageTime >= 0' >/dev/null
curl -sS -H "Authorization: Bearer $USER_AUTH" "$GATEWAY_URL/open/open" | jq -e '.isSuccess == true' >/dev/null

echo "Checking verifier routes..."
[[ "$(curl -sS "$GATEWAY_URL/verifier/verifyCard?code=E28E892A")" == "1" ]]
[[ "$(curl -sS "$GATEWAY_URL/verifier/verifyFinger?code=1")" == "1" ]]

echo "Loading admin endpoints..."
ADMIN_TOKEN="$(curl -sS -u admin@lock.local:admin1234 "$GATEWAY_URL/auth/getToken" | jq -r '.auth')"
ATTENDANCE_NORMAL_TOKEN="$(curl -sS -u attendance.normal@lock.local:normal1234 "$GATEWAY_URL/auth/getToken" | jq -r '.auth')"
curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$GATEWAY_URL/info/all" | jq -e '.employers | length >= 2' >/dev/null
curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$GATEWAY_URL/info/all" | jq -e '.employers[] | select(.employer.id == "33333333-3333-3333-3333-333333333333") | .employer.workNormMinutes == 480' >/dev/null

TEMP_EMAIL="new.user.$(date +%s)@lock.local"
assert_true_json "$(curl -sS -X POST -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" -d "{\"id\":null,\"isAdmin\":false,\"name\":\"New\",\"surname\":\"User\",\"department\":\"Ops\",\"email\":\"$TEMP_EMAIL\",\"workNormMinutes\":480,\"hasCard\":null,\"hasFinger\":null}" "$GATEWAY_URL/command/add")"

TEMP_ID="$(curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$GATEWAY_URL/info/all" | jq -r --arg email "$TEMP_EMAIL" '.employers[] | select(.employer.email == $email) | .employer.id')"
if [[ -z "$TEMP_ID" || "$TEMP_ID" == "null" ]]; then
  echo "Failed to find the user created by /command/add."
  exit 1
fi

curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$GATEWAY_URL/info/all" | jq -e --arg email "$TEMP_EMAIL" '.employers[] | select(.employer.email == $email) | .employer.workNormMinutes == 480' >/dev/null
assert_true_json "$(curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$GATEWAY_URL/command/delete?id=$TEMP_ID")"

echo "Checking attendance analysis bootstrap data..."
curl -sS "$DIRECTORY_URL/internal/directory/employers/$ATTENDANCE_NORMAL_ID" | jq -e '.workNormMinutes == 480' >/dev/null
curl -sS "$DIRECTORY_URL/internal/directory/employers/$ATTENDANCE_SPLIT_ID" | jq -e '.workNormMinutes == 480' >/dev/null
curl -sS "$DIRECTORY_URL/internal/directory/employers/$ATTENDANCE_SHORT_ID" | jq -e '.workNormMinutes == 480' >/dev/null
curl -sS "$DIRECTORY_URL/internal/directory/employers/$ATTENDANCE_BROKEN_ID" | jq -e '.workNormMinutes == 480' >/dev/null
curl -sS "$DIRECTORY_URL/internal/directory/employers/$ATTENDANCE_NIGHT_ID" | jq -e '.workNormMinutes == 480' >/dev/null

cURL_CHECK_ADMIN_HEADERS=(-H "X-Lock-User-Id: 11111111-1111-1111-1111-111111111111" -H "X-Lock-User-Email: admin@lock.local" -H "X-Lock-User-Is-Admin: true")
curl -sS -H "X-Lock-User-Id: $ATTENDANCE_NORMAL_ID" -H "X-Lock-User-Email: attendance.normal@lock.local" -H "X-Lock-User-Is-Admin: false" "$ACCESS_URL/internal/access/users/$ATTENDANCE_NORMAL_ID/logs" | jq -e '.logs | length == 26' >/dev/null
curl -sS "${cURL_CHECK_ADMIN_HEADERS[@]}" "$ACCESS_URL/internal/access/users/$ATTENDANCE_SPLIT_ID/logs" | jq -e '.logs | length == 28' >/dev/null
curl -sS "${cURL_CHECK_ADMIN_HEADERS[@]}" "$ACCESS_URL/internal/access/users/$ATTENDANCE_SHORT_ID/logs" | jq -e '.logs | length == 26' >/dev/null
curl -sS "${cURL_CHECK_ADMIN_HEADERS[@]}" "$ACCESS_URL/internal/access/users/$ATTENDANCE_BROKEN_ID/logs" | jq -e '.logs | length == 26' >/dev/null
curl -sS "${cURL_CHECK_ADMIN_HEADERS[@]}" "$ACCESS_URL/internal/access/users/$ATTENDANCE_NIGHT_ID/logs" | jq -e '.logs | length == 26' >/dev/null
[[ "$(curl -sS -o /dev/null -w "%{http_code}" "$ACCESS_URL/internal/access/users/$ATTENDANCE_NORMAL_ID/logs")" == "401" ]]
[[ "$(curl -sS -o /dev/null -w "%{http_code}" -H "X-Lock-User-Id: $ATTENDANCE_NORMAL_ID" -H "X-Lock-User-Email: attendance.normal@lock.local" -H "X-Lock-User-Is-Admin: false" "$ACCESS_URL/internal/access/users/$ATTENDANCE_SPLIT_ID/logs")" == "403" ]]

echo "Materializing attendance-analysis fixture..."
"$ROOT_DIR/infrastructure/local/materialize-attendance-analysis-fixture.sh" "$ENV_FILE" >/dev/null

run_attendance_case() {
  local user_id="$1"
  local day="$2"
  local expected_status="$3"
  local expected_worked="$4"
  local expected_break="$5"
  local expected_sessions="$6"
  local expected_anomaly="$7"
  local expected_reason="$8"

  curl -sS -X POST -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" -d "{\"userId\":\"$user_id\",\"day\":\"$day\"}" "$ATTENDANCE_GATEWAY_URL/observations/rebuild" | jq -e --arg status "$expected_status" '.status == $status' >/dev/null

  curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$user_id/observations/$day" | jq -e \
    --argjson worked "$expected_worked" \
    --argjson breakMinutes "$expected_break" \
    --argjson sessions "$expected_sessions" \
    --argjson anomaly "$expected_anomaly" \
    '.workedMinutes == $worked and .breakMinutes == $breakMinutes and .sessionsCount == $sessions and .isTechnicalAnomaly == $anomaly' >/dev/null

  if [[ -n "$expected_reason" ]]; then
    curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$user_id/observations/$day" | jq -e --arg reason "$expected_reason" '.anomalyReason == $reason' >/dev/null
  else
    curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$user_id/observations/$day" | jq -e '.anomalyReason == null' >/dev/null
  fi

  curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$user_id/results" | jq -e \
    --arg day "$day" \
    --arg status "$expected_status" \
    '.results | map(select(.day == $day and .status == $status)) | length == 1' >/dev/null
}

run_attendance_case "$ATTENDANCE_NORMAL_ID" "2026-04-22" "signals_ready" 510 0 1 false ""
run_attendance_case "$ATTENDANCE_SPLIT_ID" "2026-04-22" "signals_ready" 495 60 2 false ""
run_attendance_case "$ATTENDANCE_SHORT_ID" "2026-04-22" "signals_ready" 330 0 1 false ""
run_attendance_case "$ATTENDANCE_BROKEN_ID" "2026-04-22" "signals_ready" 485 0 1 false ""
run_attendance_case "$ATTENDANCE_NIGHT_ID" "2026-04-22" "signals_ready" 225 0 1 false ""

curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$ATTENDANCE_NORMAL_ID/results" | jq -e \
  --argjson count "$ATTENDANCE_RESULTS_COUNT" \
  '.results | length == $count and all(.status == "signals_ready") and any(.day == "2026-04-22" and .historyDaysUsed == 3 and .f == 0 and .zS != null and .zT != null and .detailsJson.historyDaysUsed == 3 and (.detailsJson.baselineHistoryDays | length) == 3)' >/dev/null

curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$ATTENDANCE_SPLIT_ID/results" | jq -e \
  --argjson count "$ATTENDANCE_RESULTS_COUNT" \
  '.results | length == $count and any(.day == "2026-04-22" and .status == "signals_ready" and .historyDaysUsed == 3 and .stddevStartMinutes > 20 and .zS != null and .zT != null)' >/dev/null

curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$ATTENDANCE_SHORT_ID/results" | jq -e \
  --argjson count "$ATTENDANCE_RESULTS_COUNT" \
  '.results | length == $count and any(.day == "2026-04-22" and .status == "signals_ready" and .historyDaysUsed == 3 and .f == 0.6667 and .detailsJson.deficitHistoryDaysCount == 2 and .zS != null and .zT != null)' >/dev/null

curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$ATTENDANCE_BROKEN_ID/results" | jq -e \
  --argjson count "$ATTENDANCE_RESULTS_COUNT" \
  '.results | length == $count and all(.status == "signals_ready") and any(.day == "2026-04-22" and .f == 0 and .zS != null and .detailsJson.anomalyReasons == [])' >/dev/null

curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$ATTENDANCE_NIGHT_ID/results" | jq -e \
  --argjson count "$ATTENDANCE_RESULTS_COUNT" \
  '.results | length == $count and any(.day == "2026-04-22" and .status == "signals_ready" and .historyDaysUsed == 3 and .f == 0 and .zS != null and .zT != null)' >/dev/null

curl -sS -X POST -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" -d "{\"day\":\"$ATTENDANCE_BATCH_DAY\"}" "$ATTENDANCE_GATEWAY_URL/observations/rebuild-all" | jq -e \
  --arg batchDay "$ATTENDANCE_BATCH_DAY" \
  '.day == $batchDay and .processedCount >= 7 and (.items | all(.status == "signals_ready")) and (.items | map(select(.result.userId == "22222222-2222-2222-2222-222222222222" and .status == "signals_ready")) | length == 1)' >/dev/null

curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/22222222-2222-2222-2222-222222222222/observations/$ATTENDANCE_BATCH_DAY" | jq -e '.workedMinutes == 485 and .sessionsCount == 1 and .isTechnicalAnomaly == false' >/dev/null
curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/22222222-2222-2222-2222-222222222222/results" | jq -e \
  --argjson count "$ATTENDANCE_RESULTS_COUNT" \
  '.results | length == $count and any(.day == "2026-04-22" and .status == "signals_ready" and .historyDaysUsed == 3)' >/dev/null
curl -sS -H "Authorization: Bearer $ATTENDANCE_NORMAL_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$ATTENDANCE_NORMAL_ID/observations/2026-04-22" | jq -e '.workedMinutes == 510' >/dev/null
curl -sS -H "Authorization: Bearer $ATTENDANCE_NORMAL_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$ATTENDANCE_NORMAL_ID/results" | jq -e --argjson count "$ATTENDANCE_RESULTS_COUNT" '.results | length == $count and any(.day == "2026-04-22" and .status == "signals_ready")' >/dev/null
[[ "$(curl -sS -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ATTENDANCE_NORMAL_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$ATTENDANCE_SPLIT_ID/observations/2026-04-22")" == "403" ]]
[[ "$(curl -sS -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $ATTENDANCE_NORMAL_TOKEN" -H "Content-Type: application/json" -d "{\"userId\":\"$ATTENDANCE_NORMAL_ID\",\"day\":\"2026-04-22\"}" "$ATTENDANCE_GATEWAY_URL/observations/rebuild")" == "403" ]]
[[ "$(curl -sS -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $ATTENDANCE_NORMAL_TOKEN" -H "Content-Type: application/json" -d "{\"day\":\"$ATTENDANCE_BATCH_DAY\"}" "$ATTENDANCE_GATEWAY_URL/observations/rebuild-all")" == "403" ]]

echo "All endpoint checks passed through the gateway and attendance-analysis service."
