#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="${1:-$ROOT_DIR/infrastructure/local/.env.local}"

if [[ ! -f "$ENV_FILE" ]]; then
  ENV_FILE="$ROOT_DIR/infrastructure/local/.env.example"
fi

set -a
source "$ENV_FILE"
set +a

GATEWAY_URL="http://127.0.0.1:${LOCKSERVER_GATEWAY_PORT}"
DAY="2026-04-24"
STABLE_USER="33333333-3333-3333-3333-333333333333"
SHORT_USER="55555555-5555-5555-5555-555555555555"

MYSQL=(
  /usr/local/mysql/bin/mysql
  -h "$LOCKSERVER_DB_HOST"
  -P "$LOCKSERVER_DB_PORT"
  -u"$LOCKSERVER_DB_USER"
  -p"$LOCKSERVER_DB_PASSWORD"
  lockService
)

ADMIN_TOKEN="$(curl -sS -u admin@lock.local:admin1234 "$GATEWAY_URL/auth/getToken" | jq -r '.auth')"
if [[ -z "$ADMIN_TOKEN" || "$ADMIN_TOKEN" == "null" ]]; then
  echo "Failed to obtain admin token."
  exit 1
fi

echo "Checking clustering model persistence..."
MODEL_INFO="$("${MYSQL[@]}" -N -s -e "SELECT COUNT(*), MAX(model_version) FROM attendance_clustering_models")"
MODEL_COUNT="${MODEL_INFO%%	*}"
MODEL_VERSION="${MODEL_INFO##*	}"
if [[ "$MODEL_COUNT" -lt 1 || "$MODEL_VERSION" == "NULL" ]]; then
  echo "Clustering model was not persisted."
  exit 1
fi
echo "Model count: $MODEL_COUNT, latest version: $MODEL_VERSION"

echo "Checking that seeded results already expose clustering output..."
curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$GATEWAY_URL/internal/attendance-analysis/users/$STABLE_USER/results" | jq -e \
  '
  any(.results[]; .clusterName != null
    and .clusterModelVersion != null
    and .clusterDistance != null
    and .clusteringStatus != "not_started"
    and .clusteringStatus != "not_applicable"
  )' >/dev/null

STABLE_TARGET_INFO="$("${MYSQL[@]}" -N -s -e "
SELECT BIN_TO_UUID(user_id), DATE_FORMAT(day, '%Y-%m-%d')
FROM attendance_analysis_results
WHERE cluster_name='Stable Normal'
LIMIT 1
")"

STABLE_TARGET_USER="${STABLE_TARGET_INFO%%	*}"
STABLE_TARGET_DAY="${STABLE_TARGET_INFO##*	}"

if [[ -z "$STABLE_TARGET_USER" || -z "$STABLE_TARGET_DAY" ]]; then
  echo "Failed to find an already clustered Stable Normal row."
  exit 1
fi

echo "Checking clustering rebuild assigns stable row..."
curl -sS -X POST -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d "{\"userId\":\"$STABLE_TARGET_USER\",\"day\":\"$STABLE_TARGET_DAY\"}" \
  "$GATEWAY_URL/internal/attendance-analysis/clustering/rebuild" | jq -e '
  .processedCount == 1
  and .clusteredCount == 1
  and .skippedCount == 0
  and .modelVersion >= 1
  and (.items | length == 1)
  and .items[0].wasClustered == true
  and .items[0].result.clusterName == "Stable Normal"
  and .items[0].result.clusterScore == 0
  and .items[0].result.clusterModelVersion == .modelVersion
  and .items[0].result.status == "clustering_terminal_stable_normal"
  and .items[0].result.clusteringStatus == "stable_normal_terminal"
' >/dev/null

echo "Checking stable-user result surface..."
curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$GATEWAY_URL/internal/attendance-analysis/users/$STABLE_TARGET_USER/results" | jq -e \
  --arg day "$STABLE_TARGET_DAY" '
  any(.results[]; .day == $day
    and .clusterName == "Stable Normal"
    and .clusterScore == 0
    and .clusterModelVersion != null
    and .clusterDistance != null
    and .clusteringStatus == "stable_normal_terminal"
    and .status == "clustering_terminal_stable_normal"
  )' >/dev/null

echo "Checking run skips already clustered row..."
curl -sS -X POST -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d "{\"userId\":\"$STABLE_TARGET_USER\",\"day\":\"$STABLE_TARGET_DAY\"}" \
  "$GATEWAY_URL/internal/attendance-analysis/clustering/run" | jq -e '
  .processedCount == 1
  and .clusteredCount == 0
  and .skippedCount == 1
  and .modelVersion >= 1
  and (.items | length == 1)
  and .items[0].wasClustered == false
' >/dev/null

echo "Checking observation rebuild resets clustering state..."
curl -sS -X POST -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d "{\"userId\":\"$STABLE_TARGET_USER\",\"day\":\"$STABLE_TARGET_DAY\"}" \
  "$GATEWAY_URL/internal/attendance-analysis/observations/rebuild" | jq -e '
  .status == "signals_ready"
  and .result.status == "signals_ready"
  and .result.clusteringStatus == "not_started"
  and .result.clusterName == null
' >/dev/null

echo "Checking clustering rebuild reassigns stable row..."
curl -sS -X POST -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d "{\"userId\":\"$STABLE_TARGET_USER\",\"day\":\"$STABLE_TARGET_DAY\"}" \
  "$GATEWAY_URL/internal/attendance-analysis/clustering/rebuild" | jq -e '
  .processedCount == 1
  and .clusteredCount == 1
  and .skippedCount == 0
  and .modelVersion >= 1
  and (.items | length == 1)
  and .items[0].wasClustered == true
  and .items[0].result.clusterName == "Stable Normal"
  and .items[0].result.clusterScore == 0
  and .items[0].result.clusterModelVersion == .modelVersion
  and .items[0].result.status == "clustering_terminal_stable_normal"
  and .items[0].result.clusteringStatus == "stable_normal_terminal"
' >/dev/null

echo "Checking non-terminal clustered row..."
READY_TARGET_INFO="$("${MYSQL[@]}" -N -s -e "
SELECT BIN_TO_UUID(user_id), DATE_FORMAT(day, '%Y-%m-%d')
FROM attendance_analysis_results
WHERE status='ready_for_next_stage'
LIMIT 1
")"

READY_TARGET_USER="${READY_TARGET_INFO%%	*}"
READY_TARGET_DAY="${READY_TARGET_INFO##*	}"

if [[ -z "$READY_TARGET_USER" || -z "$READY_TARGET_DAY" ]]; then
  echo "Failed to find a ready_for_next_stage row."
  exit 1
fi

curl -sS -H "Authorization: Bearer $ADMIN_TOKEN" "$GATEWAY_URL/internal/attendance-analysis/users/$READY_TARGET_USER/results" | jq -e \
  --arg day "$READY_TARGET_DAY" '
  any(.results[]; .day == $day
    and .clusterName != "Stable Normal"
    and .clusterScore != null
    and .status == "ready_for_next_stage"
    and .clusteringStatus == "ready_for_next_stage"
  )' >/dev/null

echo "Injecting one technical outlier on a generated user..."
OUTLIER_USER="$("${MYSQL[@]}" -N -s -e "
SELECT BIN_TO_UUID(user_id)
FROM attendance_analysis_results
WHERE day='${DAY} 00:00:00'
  AND z_s IS NOT NULL
  AND user_id NOT IN (
    UUID_TO_BIN('22222222-2222-2222-2222-222222222222'),
    UUID_TO_BIN('33333333-3333-3333-3333-333333333333'),
    UUID_TO_BIN('44444444-4444-4444-4444-444444444444'),
    UUID_TO_BIN('55555555-5555-5555-5555-555555555555'),
    UUID_TO_BIN('66666666-6666-6666-6666-666666666666'),
    UUID_TO_BIN('77777777-7777-7777-7777-777777777777')
  )
LIMIT 1
")"

if [[ -z "$OUTLIER_USER" ]]; then
  echo "Failed to select a generated user for outlier verification."
  exit 1
fi

"${MYSQL[@]}" -e "
UPDATE attendance_analysis_results
SET
  status='signals_ready',
  cluster_name=NULL,
  cluster_score=NULL,
  cluster_weight=NULL,
  cluster_model_version=NULL,
  cluster_distance=NULL,
  clustering_status='not_started',
  z_s=-12,
  z_t=12,
  f=1
WHERE user_id=UUID_TO_BIN('$OUTLIER_USER')
  AND day='${DAY} 00:00:00'
"

curl -sS -X POST -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d "{\"userId\":\"$OUTLIER_USER\",\"day\":\"$DAY\"}" \
  "$GATEWAY_URL/internal/attendance-analysis/clustering/rebuild" | jq -e '
  .processedCount == 1
  and .clusteredCount == 1
  and (.items | length == 1)
  and .items[0].wasClustered == true
  and .items[0].result.status == "clustering_technical_outlier"
  and .items[0].result.clusterName == "Technical Outlier"
  and .items[0].result.clusteringStatus == "technical_outlier"
  and .items[0].result.clusterDistance != null
  and .items[0].result.clusterScore == null
' >/dev/null

echo "Attendance clustering runtime checks passed."
