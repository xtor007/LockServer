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
curl -sS -H "Authorization: Bearer $USER_AUTH" "$GATEWAY_URL/info/" | jq -e '.email == "user@lock.local"' >/dev/null
curl -sS -H "Authorization: Bearer $USER_AUTH" -X POST -H "Content-Type: application/json" -d '{"valid":true,"id":null,"afterDate":null}' "$GATEWAY_URL/info/logs" | jq -e '.logs | length >= 1' >/dev/null
curl -sS -H "Authorization: Bearer $USER_AUTH" "$GATEWAY_URL/info/statistic" | jq -e '.averageTime >= 0' >/dev/null
curl -sS -H "Authorization: Bearer $USER_AUTH" "$GATEWAY_URL/open/open" | jq -e '.isSuccess == true' >/dev/null

echo "Checking verifier routes..."
[[ "$(curl -sS "$GATEWAY_URL/verifier/verifyCard?code=E28E892A")" == "1" ]]
[[ "$(curl -sS "$GATEWAY_URL/verifier/verifyFinger?code=1")" == "1" ]]

echo "Loading admin endpoints..."
ADMIN_TOKEN="$(curl -sS -u admin@lock.local:admin1234 "$GATEWAY_URL/auth/getToken" | jq -r '.auth')"
curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$GATEWAY_URL/info/all" | jq -e '.employers | length >= 2' >/dev/null

TEMP_EMAIL="new.user.$(date +%s)@lock.local"
assert_true_json "$(curl -sS -X POST -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" -d "{\"id\":null,\"isAdmin\":false,\"name\":\"New\",\"surname\":\"User\",\"department\":\"Ops\",\"email\":\"$TEMP_EMAIL\",\"hasCard\":null,\"hasFinger\":null}" "$GATEWAY_URL/command/add")"

TEMP_ID="$(curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$GATEWAY_URL/info/all" | jq -r --arg email "$TEMP_EMAIL" '.employers[] | select(.employer.email == $email) | .employer.id')"
if [[ -z "$TEMP_ID" || "$TEMP_ID" == "null" ]]; then
  echo "Failed to find the user created by /command/add."
  exit 1
fi

assert_true_json "$(curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$GATEWAY_URL/command/delete?id=$TEMP_ID")"

echo "All endpoint checks passed through the gateway."
