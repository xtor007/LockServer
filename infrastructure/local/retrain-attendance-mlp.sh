#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PYTHON_SCRIPT="$ROOT_DIR/services/attendance-analysis-service/mlp/train_attendance_mlp.py"

python3 "$PYTHON_SCRIPT" retrain "$@"
