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
PID_DIR="$RUNTIME_DIR/pids"
MYSQL_RUN_DIR="$RUNTIME_DIR/mysql-run"
OWN_MYSQL_MARKER="$RUNTIME_DIR/own-mysql"

stop_pid_file() {
  local pid_file="$1"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file")"
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$pid_file"
  fi
}

stop_pid_file "$PID_DIR/api-gateway.pid"
stop_pid_file "$PID_DIR/attendance-analysis-service.pid"
stop_pid_file "$PID_DIR/device-service.pid"
stop_pid_file "$PID_DIR/access-service.pid"
stop_pid_file "$PID_DIR/directory-service.pid"
stop_pid_file "$PID_DIR/auth-service.pid"

if [[ -f "$OWN_MYSQL_MARKER" && -f "$MYSQL_RUN_DIR/mysqld.pid" ]]; then
  MYSQL_PID="$(cat "$MYSQL_RUN_DIR/mysqld.pid")"
  if kill -0 "$MYSQL_PID" >/dev/null 2>&1; then
    kill "$MYSQL_PID" >/dev/null 2>&1 || true
  fi
  rm -f "$MYSQL_RUN_DIR/mysqld.pid"
fi

rm -f "$OWN_MYSQL_MARKER"
