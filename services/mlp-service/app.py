#!/usr/bin/env python3
"""Standalone internal HTTP service for attendance-analysis MLP inference."""

from __future__ import annotations

import importlib.util
import json
import logging
import os
import sys
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler
from http.server import ThreadingHTTPServer
from pathlib import Path
from typing import Any

from inference_runtime import AttendanceMLPInferenceRuntime
from inference_runtime import ArtifactLoadError
from inference_runtime import InferenceValidationError


LOGGER = logging.getLogger("attendance-mlp-service")
RUNTIME = AttendanceMLPInferenceRuntime()
SCRIPT_PATH = Path(__file__).resolve()
WORKSPACE_ROOT = SCRIPT_PATH.parents[3]
TRAINING_MODULE_PATH = (
    WORKSPACE_ROOT / "LockServer" / "services" / "attendance-analysis-service" / "mlp" / "train_attendance_mlp.py"
)
RETRAIN_LOCK = threading.Lock()


def load_training_module() -> Any:
    spec = importlib.util.spec_from_file_location("attendance_mlp_training", TRAINING_MODULE_PATH)
    if spec is None or spec.loader is None:
        raise ArtifactLoadError(f"Failed to load training module from {TRAINING_MODULE_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


TRAINING_MODULE = load_training_module()


class AttendanceMLPRequestHandler(BaseHTTPRequestHandler):
    server_version = "AttendanceMLPService/1.0"

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/validate":
            self._send_json(
                HTTPStatus.OK,
                {
                    "isValid": True,
                    **RUNTIME.model_info(),
                },
            )
            return

        if self.path == "/internal/mlp/model":
            self._send_json(HTTPStatus.OK, RUNTIME.model_info())
            return

        self._send_error_json(HTTPStatus.NOT_FOUND, "Route not found")

    def do_POST(self) -> None:  # noqa: N802
        if self.path == "/internal/mlp/infer":
            self._handle_infer()
            return

        if self.path == "/internal/mlp/retrain":
            self._handle_retrain()
            return

        self._send_error_json(HTTPStatus.NOT_FOUND, "Route not found")

    def _handle_infer(self) -> None:
        try:
            payload = self._read_json_body()
            items = payload.get("items")
            if not isinstance(items, list):
                raise InferenceValidationError("Request body must include an items array")
            response = RUNTIME.infer_batch(items)
        except InferenceValidationError as error:
            self._send_error_json(HTTPStatus.BAD_REQUEST, str(error))
            return
        except Exception as error:  # pragma: no cover - exercised in manual runtime verification
            LOGGER.exception("Inference request failed")
            self._send_error_json(HTTPStatus.INTERNAL_SERVER_ERROR, str(error))
            return

        self._send_json(HTTPStatus.OK, response)

    def _handle_retrain(self) -> None:
        try:
            payload = self._read_json_body()
            feedback_samples = payload.get("feedback_samples")
            if not isinstance(feedback_samples, list):
                raise InferenceValidationError("Request body must include a feedback_samples array")

            with RETRAIN_LOCK:
                training_summary = TRAINING_MODULE.train_with_feedback_samples(
                    feedback_samples=feedback_samples,
                    artifacts_root=RUNTIME.artifacts_root,
                )
                loaded = RUNTIME.reload_latest_artifact()
        except InferenceValidationError as error:
            self._send_error_json(HTTPStatus.BAD_REQUEST, str(error))
            return
        except Exception as error:  # pragma: no cover - exercised in manual runtime verification
            LOGGER.exception("Retraining request failed")
            self._send_error_json(HTTPStatus.INTERNAL_SERVER_ERROR, str(error))
            return

        LOGGER.info(
            "Retrained attendance MLP model %s with %s accepted feedback samples",
            loaded.model_version,
            training_summary["feedback_samples_count"],
        )
        self._send_json(
            HTTPStatus.OK,
            {
                "model_version": loaded.model_version,
                "artifact_id": loaded.artifact_id,
                "feedback_samples_count": training_summary["feedback_samples_count"],
            },
        )

    def log_message(self, format: str, *args: Any) -> None:
        LOGGER.info("%s - %s", self.address_string(), format % args)

    def _read_json_body(self) -> dict[str, Any]:
        content_length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(content_length)
        if not body:
            raise InferenceValidationError("Request body must not be empty")

        try:
            payload = json.loads(body)
        except json.JSONDecodeError as error:
            raise InferenceValidationError(f"Invalid JSON body: {error.msg}") from error

        if not isinstance(payload, dict):
            raise InferenceValidationError("JSON body must be an object")
        return payload

    def _send_json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
        response_body = json.dumps(payload, indent=2, sort_keys=True).encode("utf-8")
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(response_body)))
        self.end_headers()
        self.wfile.write(response_body)

    def _send_error_json(self, status: HTTPStatus, reason: str) -> None:
        self._send_json(
            status,
            {
                "error": reason,
                "status": status.value,
            },
        )


def main() -> int:
    host = os.environ.get("LOCKSERVER_MLP_BIND_HOST", "127.0.0.1")
    port = int(os.environ.get("LOCKSERVER_MLP_PORT", "8087"))

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    LOGGER.info(
        "Loaded attendance MLP artifact %s from %s",
        RUNTIME.loaded.model_version,
        RUNTIME.loaded.metadata_path,
    )

    server = ThreadingHTTPServer((host, port), AttendanceMLPRequestHandler)
    LOGGER.info("Attendance MLP service listening on http://%s:%s", host, port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:  # pragma: no cover - manual shutdown path
        LOGGER.info("Attendance MLP service shutting down")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ArtifactLoadError as error:
        logging.basicConfig(level=logging.ERROR, format="%(asctime)s %(levelname)s %(name)s %(message)s")
        LOGGER.error("Failed to start attendance MLP service: %s", error)
        raise SystemExit(1)
