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
EXTERNAL_CONTEXT_GATEWAY_URL="$GATEWAY_URL/internal/external-context"

SAMPLE_DAY="2026-04-24"
STABLE_USER_ID="33333333-3333-3333-3333-333333333333"
SPLIT_USER_ID="44444444-4444-4444-4444-444444444444"
SHORT_USER_ID="55555555-5555-5555-5555-555555555555"
EARLY_USER_ID="66666666-6666-6666-6666-666666666666"
NIGHT_USER_ID="77777777-7777-7777-7777-777777777777"

assert_true_json() {
  local response="$1"
  echo "$response" | jq -e '.isValid == true' >/dev/null
}

trusted_admin_headers=(
  -H "X-Lock-User-Id: 11111111-1111-1111-1111-111111111111"
  -H "X-Lock-User-Email: admin@lock.local"
  -H "X-Lock-User-Is-Admin: true"
)

echo "Checking service health..."
assert_true_json "$(curl -sS "$GATEWAY_URL/validate")"
assert_true_json "$(curl -sS "$AUTH_URL/validate")"
assert_true_json "$(curl -sS "$DIRECTORY_URL/validate")"
assert_true_json "$(curl -sS "$ACCESS_URL/validate")"
assert_true_json "$(curl -sS "$DEVICE_URL/validate")"
assert_true_json "$(curl -sS "$ATTENDANCE_URL/validate")"

echo "Requesting standard user token..."
USER_TOKEN_RESPONSE="$(curl -sS -u user@lock.local:user1234 "$GATEWAY_URL/auth/getToken")"
USER_AUTH="$(echo "$USER_TOKEN_RESPONSE" | jq -r '.auth')"
USER_REFRESH="$(echo "$USER_TOKEN_RESPONSE" | jq -r '.refresh')"

echo "Refreshing standard user token..."
REFRESH_RESPONSE="$(curl -sS -H "Authorization: Bearer $USER_REFRESH" "$GATEWAY_URL/auth/refresh")"
echo "$REFRESH_RESPONSE" | jq -e '.auth | length > 0' >/dev/null

echo "Verifying password reset flow..."
RESET_CODE="$(curl -sS -X POST -H "Content-Type: application/json" -d '{"email":"user@lock.local"}' "$GATEWAY_URL/auth/changePasswordEmail" | jq -r '.code')"
assert_true_json "$(curl -sS -u user@lock.local:$RESET_CODE -X POST -H "Content-Type: application/json" -d '{"password":"user1234"}' "$GATEWAY_URL/auth/changePassword")"

echo "Loading user-facing endpoints..."
curl -sS -H "Authorization: Bearer $USER_AUTH" "$GATEWAY_URL/info/" | jq -e '.email == "user@lock.local" and .workNormMinutes == 480' >/dev/null
curl -sS -H "Authorization: Bearer $USER_AUTH" -X POST -H "Content-Type: application/json" -d '{"valid":true,"id":null,"afterDate":null}' "$GATEWAY_URL/info/logs" | jq -e '.logs | length >= 400' >/dev/null
curl -sS -H "Authorization: Bearer $USER_AUTH" "$GATEWAY_URL/info/statistic" | jq -e '.averageTime >= 0' >/dev/null
curl -sS -H "Authorization: Bearer $USER_AUTH" "$GATEWAY_URL/open/open" | jq -e '.isSuccess == true' >/dev/null

echo "Checking verifier routes..."
[[ "$(curl -sS "$GATEWAY_URL/verifier/verifyCard?code=E28E892A")" == "1" ]]
[[ "$(curl -sS "$GATEWAY_URL/verifier/verifyFinger?code=1")" == "1" ]]

echo "Loading admin and sample-user tokens..."
ADMIN_TOKEN="$(curl -sS -u admin@lock.local:admin1234 "$GATEWAY_URL/auth/getToken" | jq -r '.auth')"
STABLE_TOKEN="$(curl -sS -u attendance.normal@lock.local:normal1234 "$GATEWAY_URL/auth/getToken" | jq -r '.auth')"
SHORT_TOKEN="$(curl -sS -u attendance.short@lock.local:short1234 "$GATEWAY_URL/auth/getToken" | jq -r '.auth')"
NIGHT_TOKEN="$(curl -sS -u attendance.night@lock.local:night1234 "$GATEWAY_URL/auth/getToken" | jq -r '.auth')"

echo "Checking seeded population shape..."
DIRECTORY_RESPONSE="$(curl -sS "$DIRECTORY_URL/internal/directory/employers")"
echo "$DIRECTORY_RESPONSE" | jq -e '.employers | map(select(.isAdmin == true)) | length == 1' >/dev/null
echo "$DIRECTORY_RESPONSE" | jq -e '.employers | map(select(.isAdmin == false)) | length >= 1000' >/dev/null
echo "$DIRECTORY_RESPONSE" | jq -e '
  [.employers[] | select(.isAdmin == false) | .workNormMinutes] as $norms
  | ($norms | index(240)) != null
  and ($norms | index(360)) != null
  and ($norms | index(480)) != null
' >/dev/null

echo "Checking admin-only user add/delete flow..."
TEMP_EMAIL="new.user.$(date +%s)@lock.local"
assert_true_json "$(curl -sS -X POST -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" -d "{\"id\":null,\"isAdmin\":false,\"name\":\"New\",\"surname\":\"User\",\"department\":\"Ops\",\"email\":\"$TEMP_EMAIL\",\"workNormMinutes\":480,\"hasCard\":null,\"hasFinger\":null}" "$GATEWAY_URL/command/add")"
TEMP_ID="$(curl -sS "$DIRECTORY_URL/internal/directory/employers" | jq -r --arg email "$TEMP_EMAIL" '.employers[] | select(.email == $email) | .id')"
if [[ -z "$TEMP_ID" || "$TEMP_ID" == "null" ]]; then
  echo "Failed to find the user created by /command/add."
  exit 1
fi
assert_true_json "$(curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$GATEWAY_URL/command/delete?id=$TEMP_ID")"

echo "Re-materializing attendance fixture..."
"$ROOT_DIR/infrastructure/local/materialize-attendance-analysis-fixture.sh" "$ENV_FILE" >/dev/null

echo "Checking sample attendance users..."
for user_id in "$STABLE_USER_ID" "$SPLIT_USER_ID" "$SHORT_USER_ID" "$EARLY_USER_ID" "$NIGHT_USER_ID"; do
  curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$user_id/observations" | jq -e '.observations | length >= 200' >/dev/null
  curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$user_id/results" | jq -e '.results | length >= 200 and all(.status == "signals_ready")' >/dev/null
done

curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$STABLE_USER_ID/results" | jq -e \
  --arg day "$SAMPLE_DAY" \
  'any(.results[]; .day == $day and .historyDaysUsed == 3 and .zS != null and .zT != null and .f != null and .detailsJson.airAlertIntervals != null and .detailsJson.trafficScore != null and .detailsJson.powerScore != null and .detailsJson.weatherScore != null and .detailsJson.weatherContext != null)' >/dev/null

curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$SPLIT_USER_ID/observations" | jq -e \
  'any(.observations[]; .sessionsCount > 1 and .breakMinutes > 0)' >/dev/null

curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$SHORT_USER_ID/results" | jq -e \
  'any(.results[]; .f != null and .f > 0)' >/dev/null

curl -sS "$DIRECTORY_URL/internal/directory/employers/$EARLY_USER_ID" | jq -e '.workNormMinutes == 240' >/dev/null
curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$EARLY_USER_ID/observations" | jq -e \
  'any(.observations[]; .firstEntryTime != null and (.firstEntryTime[11:13] | tonumber) < 8)' >/dev/null

curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$NIGHT_USER_ID/observations" | jq -e \
  'any(.observations[]; .firstEntryTime != null and (.firstEntryTime[11:13] | tonumber) >= 17)' >/dev/null
curl -sS "${trusted_admin_headers[@]}" "$ACCESS_URL/internal/access/users/$NIGHT_USER_ID/logs" | jq -e '
  .logs as $logs
  | any(range(0; ($logs | length) - 1); $logs[.].isOn == true and $logs[. + 1].isOn == false and ($logs[.].time[0:10] != $logs[. + 1].time[0:10]))
' >/dev/null

echo "Checking batch rebuild and access rules..."
curl -sS -X POST -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" -d "{\"day\":\"$SAMPLE_DAY\"}" "$ATTENDANCE_GATEWAY_URL/observations/rebuild-all" | jq -e \
  --arg day "$SAMPLE_DAY" \
  '.day == $day and .processedCount >= 1000 and (.items | length >= 1000) and any(.items[]; .result.userId == "33333333-3333-3333-3333-333333333333" and .status == "signals_ready")' >/dev/null

curl -sS -H "Authorization: Bearer $STABLE_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$STABLE_USER_ID/observations/$SAMPLE_DAY" | jq -e '.workedMinutes > 0' >/dev/null
curl -sS -H "Authorization: Bearer $SHORT_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$SHORT_USER_ID/results" | jq -e '.results | length >= 200' >/dev/null
curl -sS -H "Authorization: Bearer $NIGHT_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$NIGHT_USER_ID/results" | jq -e '.results | length >= 200' >/dev/null
[[ "$(curl -sS -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $STABLE_TOKEN" "$ATTENDANCE_GATEWAY_URL/users/$SPLIT_USER_ID/observations/$SAMPLE_DAY")" == "403" ]]
[[ "$(curl -sS -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $STABLE_TOKEN" -H "Content-Type: application/json" -d "{\"userId\":\"$STABLE_USER_ID\",\"day\":\"$SAMPLE_DAY\"}" "$ATTENDANCE_GATEWAY_URL/observations/rebuild")" == "403" ]]
[[ "$(curl -sS -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $STABLE_TOKEN" -H "Content-Type: application/json" -d "{\"day\":\"$SAMPLE_DAY\"}" "$ATTENDANCE_GATEWAY_URL/observations/rebuild-all")" == "403" ]]
[[ "$(curl -sS -o /dev/null -w "%{http_code}" "$ACCESS_URL/internal/access/users/$STABLE_USER_ID/logs")" == "401" ]]
[[ "$(curl -sS -o /dev/null -w "%{http_code}" -H "X-Lock-User-Id: $STABLE_USER_ID" -H "X-Lock-User-Email: attendance.normal@lock.local" -H "X-Lock-User-Is-Admin: false" "$ACCESS_URL/internal/access/users/$SPLIT_USER_ID/logs")" == "403" ]]

echo "Checking external-context read endpoints..."
curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$EXTERNAL_CONTEXT_GATEWAY_URL/$SAMPLE_DAY" | jq -e '
  .day == "'"$SAMPLE_DAY"'"
  and (.contexts | length == 4)
  and any(.contexts[]; .factor == "air_alerts" and (.intervals | length) >= 1)
  and any(.contexts[]; .factor == "traffic" and (.values | length) >= 1)
  and any(.contexts[]; .factor == "power_availability" and (.values | length) >= 1)
  and any(.contexts[]; .factor == "weather" and (.values | length) >= 1)
' >/dev/null

echo "All endpoint checks passed through the gateway and attendance-analysis service."
