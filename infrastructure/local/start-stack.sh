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

RUNTIME_DIR="${LOCKSERVER_RUNTIME_DIR:-/tmp/lockserver-microservices}"
MYSQL_DATA_DIR="$RUNTIME_DIR/mysql-data"
MYSQL_RUN_DIR="$RUNTIME_DIR/mysql-run"
MYSQL_SOCKET="$RUNTIME_DIR/mysql.sock"
LOG_DIR="$ROOT_DIR/infrastructure/local/logs"
PID_DIR="$RUNTIME_DIR/pids"
OWN_MYSQL_MARKER="$RUNTIME_DIR/own-mysql"

mkdir -p "$LOG_DIR" "$PID_DIR"

"$ROOT_DIR/infrastructure/local/stop-stack.sh" "$ENV_FILE" >/dev/null 2>&1 || true

rm -f "$OWN_MYSQL_MARKER"

if /usr/local/mysql/bin/mysqladmin ping -h "$LOCKSERVER_DB_HOST" -P "$LOCKSERVER_DB_PORT" -uroot -p"$LOCKSERVER_DB_PASSWORD" >/dev/null 2>&1; then
  /usr/local/mysql/bin/mysql -h "$LOCKSERVER_DB_HOST" -P "$LOCKSERVER_DB_PORT" -uroot -p"$LOCKSERVER_DB_PASSWORD" -e "
  DROP DATABASE IF EXISTS lockService;
  CREATE DATABASE lockService CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
  FLUSH PRIVILEGES;"
else
  rm -rf "$MYSQL_DATA_DIR" "$MYSQL_RUN_DIR"
  mkdir -p "$MYSQL_DATA_DIR" "$MYSQL_RUN_DIR"

  /usr/local/mysql/bin/mysqld --initialize-insecure --basedir=/usr/local/mysql --datadir="$MYSQL_DATA_DIR"
  /usr/local/mysql/bin/mysqld \
    --daemonize \
    --basedir=/usr/local/mysql \
    --datadir="$MYSQL_DATA_DIR" \
    --socket="$MYSQL_SOCKET" \
    --pid-file="$MYSQL_RUN_DIR/mysqld.pid" \
    --port="$LOCKSERVER_DB_PORT" \
    --bind-address="$LOCKSERVER_DB_HOST" \
    --mysqlx=0 \
    --log-error="$MYSQL_RUN_DIR/mysqld.err"

  sleep 2

  /usr/local/mysql/bin/mysql --socket="$MYSQL_SOCKET" -uroot -e "
  ALTER USER 'root'@'localhost' IDENTIFIED BY '${LOCKSERVER_DB_PASSWORD}';
  CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '${LOCKSERVER_DB_PASSWORD}';
  GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
  CREATE DATABASE IF NOT EXISTS lockService CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
  FLUSH PRIVILEGES;"
  touch "$OWN_MYSQL_MARKER"
fi

cd "$ROOT_DIR"
env HOME=/tmp/codex-home CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift build >/dev/null
BIN_DIR="$(env HOME=/tmp/codex-home CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift build --show-bin-path)"

start_service() {
  local name="$1"
  local binary="$2"
  local log_file="$LOG_DIR/$name.log"
  local pid_file="$PID_DIR/$name.pid"

  "$BIN_DIR/$binary" serve --env development >"$log_file" 2>&1 &
  echo "$!" >"$pid_file"
}

wait_for_url() {
  local url="$1"
  for _ in {1..180}; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

start_service "auth-service" "AuthService"
start_service "directory-service" "DirectoryService"
start_service "access-service" "AccessService"
start_service "device-service" "DeviceService"
start_service "attendance-analysis-service" "AttendanceAnalysisService"
start_service "external-context-service" "ExternalContextService"
start_service "api-gateway" "App"

wait_for_url "http://127.0.0.1:${LOCKSERVER_AUTH_PORT}/validate"
wait_for_url "http://127.0.0.1:${LOCKSERVER_DIRECTORY_PORT}/validate"
wait_for_url "http://127.0.0.1:${LOCKSERVER_ACCESS_PORT}/validate"
wait_for_url "http://127.0.0.1:${LOCKSERVER_DEVICE_PORT}/validate"
wait_for_url "http://127.0.0.1:${LOCKSERVER_ATTENDANCE_ANALYSIS_PORT}/validate"
wait_for_url "http://127.0.0.1:${LOCKSERVER_EXTERNAL_CONTEXT_PORT}/validate"
wait_for_url "http://127.0.0.1:${LOCKSERVER_GATEWAY_PORT}/validate"

if [[ "${LOCKSERVER_SKIP_ATTENDANCE_FIXTURE_MATERIALIZATION:-0}" == "1" ]]; then
  echo "Skipping attendance-analysis fixture materialization because LOCKSERVER_SKIP_ATTENDANCE_FIXTURE_MATERIALIZATION=1."
else
  if ! "$ROOT_DIR/infrastructure/local/materialize-attendance-analysis-fixture.sh" "$ENV_FILE"; then
    echo "Warning: attendance-analysis fixture materialization finished with errors."
  fi
fi

echo "LockServer microservices are running."
echo "Gateway: http://127.0.0.1:${LOCKSERVER_GATEWAY_PORT}"
echo "Logs: $LOG_DIR"
echo "Keep this process running while you use the stack. Stop it with Ctrl-C or ./infrastructure/local/stop-stack.sh."

cleanup() {
  "$ROOT_DIR/infrastructure/local/stop-stack.sh" "$ENV_FILE" >/dev/null 2>&1 || true
}

trap cleanup INT TERM

wait
