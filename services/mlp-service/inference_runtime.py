#!/usr/bin/env python3
"""Runtime loader and inference helpers for attendance-analysis MLP artifacts."""

from __future__ import annotations

import json
import math
import os
from dataclasses import dataclass
from datetime import datetime
from datetime import timezone
from pathlib import Path
from typing import Any

import numpy as np
import torch
from torch import nn


FEATURE_ORDER = [
    "z_s",
    "z_t",
    "f",
    "air_alert_minutes",
    "traffic_score",
    "power_score",
    "weather_score",
]

SCRIPT_PATH = Path(__file__).resolve()
WORKSPACE_ROOT = SCRIPT_PATH.parents[3]
DEFAULT_ARTIFACTS_ROOT = WORKSPACE_ROOT / "mlp_artifacts"
DEFAULT_LATEST_POINTER = DEFAULT_ARTIFACTS_ROOT / "latest.json"


class AttendanceMLP(nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.network = nn.Sequential(
            nn.Linear(7, 14),
            nn.ReLU(),
            nn.Linear(14, 8),
            nn.ReLU(),
            nn.Linear(8, 1),
            nn.Sigmoid(),
        )

    def forward(self, features: torch.Tensor) -> torch.Tensor:
        return self.network(features)


@dataclass(frozen=True)
class LoadedArtifact:
    model: AttendanceMLP
    model_version: str
    artifact_id: str
    feature_order: list[str]
    normalization_mean: np.ndarray
    normalization_std: np.ndarray
    metadata_path: Path
    model_path: Path
    normalization_path: Path


class ArtifactLoadError(RuntimeError):
    pass


class InferenceValidationError(ValueError):
    pass


class AttendanceMLPInferenceRuntime:
    def __init__(
        self,
        artifacts_root: Path | None = None,
        latest_pointer_path: Path | None = None,
    ) -> None:
        self.artifacts_root = Path(
            artifacts_root or os.environ.get("LOCKSERVER_MLP_ARTIFACTS_ROOT") or DEFAULT_ARTIFACTS_ROOT
        ).resolve()
        self.latest_pointer_path = Path(
            latest_pointer_path or os.environ.get("LOCKSERVER_MLP_LATEST_POINTER") or DEFAULT_LATEST_POINTER
        ).resolve()
        self.loaded = self._load_latest_artifact()

    def infer_batch(self, items: list[dict[str, Any]]) -> dict[str, Any]:
        if not items:
            raise InferenceValidationError("items must not be empty")

        feature_matrix = []
        request_ids: list[str] = []
        for item in items:
            request_id = item.get("request_id")
            if not isinstance(request_id, str) or not request_id:
                raise InferenceValidationError("each item must include a non-empty string request_id")

            features = item.get("features")
            if not isinstance(features, list) or len(features) != len(FEATURE_ORDER):
                raise InferenceValidationError("each item must include exactly 7 ordered feature values")

            parsed_features = []
            for value in features:
                if not isinstance(value, (int, float)) or not math.isfinite(float(value)):
                    raise InferenceValidationError("feature values must be finite numbers")
                parsed_features.append(float(value))

            request_ids.append(request_id)
            feature_matrix.append(parsed_features)

        raw_features = np.array(feature_matrix, dtype=np.float32)
        normalized_features = (raw_features - self.loaded.normalization_mean) / self.loaded.normalization_std
        normalized_features = normalized_features.astype(np.float32)

        with torch.no_grad():
            predictions = self.loaded.model(torch.from_numpy(normalized_features)).cpu().numpy().reshape(-1)

        timestamp = utc_now_iso()
        results = []
        for request_id, raw_values, normalized_values, prediction in zip(
            request_ids,
            raw_features.tolist(),
            normalized_features.tolist(),
            predictions.tolist(),
        ):
            eta_nn = float(min(max(prediction, 0.0), 1.0))
            results.append(
                {
                    "request_id": request_id,
                    "eta_nn": round(eta_nn, 6),
                    "model_version": self.loaded.model_version,
                    "diagnostics": {
                        "artifact_id": self.loaded.artifact_id,
                        "feature_order": list(self.loaded.feature_order),
                        "input_features": [round(float(value), 6) for value in raw_values],
                        "normalized_features": [round(float(value), 6) for value in normalized_values],
                        "inference_timestamp": timestamp,
                    },
                }
            )

        return {
            "model_version": self.loaded.model_version,
            "artifact_id": self.loaded.artifact_id,
            "feature_order": list(self.loaded.feature_order),
            "results": results,
        }

    def model_info(self) -> dict[str, Any]:
        return {
            "model_version": self.loaded.model_version,
            "artifact_id": self.loaded.artifact_id,
            "feature_order": list(self.loaded.feature_order),
            "metadata_path": str(self.loaded.metadata_path),
            "model_path": str(self.loaded.model_path),
            "normalization_path": str(self.loaded.normalization_path),
        }

    def _load_latest_artifact(self) -> LoadedArtifact:
        candidate_metadata_paths = self._candidate_metadata_paths()
        if not candidate_metadata_paths:
            raise ArtifactLoadError(
                f"No attendance MLP artifact metadata found under {self.artifacts_root}"
            )

        last_error: Exception | None = None
        for metadata_path in candidate_metadata_paths:
            try:
                return self._load_artifact_from_metadata(metadata_path)
            except Exception as error:  # pragma: no cover - exercised in manual runtime verification
                last_error = error

        raise ArtifactLoadError(f"Failed to load any valid attendance MLP artifact: {last_error}")

    def _candidate_metadata_paths(self) -> list[Path]:
        candidates: list[Path] = []

        if self.latest_pointer_path.exists():
            try:
                with self.latest_pointer_path.open("r", encoding="utf-8") as handle:
                    latest_pointer = json.load(handle)
                metadata_path = Path(latest_pointer["metadata_path"]).resolve()
                candidates.append(metadata_path)
            except Exception:
                pass

        scanned = sorted(
            self.artifacts_root.glob("*/metadata.json"),
            key=lambda path: path.parent.name,
            reverse=True,
        )
        for metadata_path in scanned:
            resolved = metadata_path.resolve()
            if resolved not in candidates:
                candidates.append(resolved)

        return candidates

    def _load_artifact_from_metadata(self, metadata_path: Path) -> LoadedArtifact:
        with metadata_path.open("r", encoding="utf-8") as handle:
            metadata = json.load(handle)

        feature_order = metadata.get("feature_order")
        if feature_order != FEATURE_ORDER:
            raise ArtifactLoadError(
                f"Unexpected feature order in {metadata_path}: {feature_order!r}"
            )

        metrics_files = metadata.get("metrics_files") or {}
        model_path = Path(metrics_files.get("model", "")).resolve()
        normalization_path = Path(
            (metadata.get("normalization_method") or {}).get("parameters_file", "")
        ).resolve()
        if not model_path.exists():
            raise ArtifactLoadError(f"Model file does not exist: {model_path}")
        if not normalization_path.exists():
            raise ArtifactLoadError(f"Normalization file does not exist: {normalization_path}")

        with normalization_path.open("r", encoding="utf-8") as handle:
            normalization = json.load(handle)
        if normalization.get("feature_columns") != FEATURE_ORDER:
            raise ArtifactLoadError(
                f"Normalization feature order mismatch in {normalization_path}"
            )

        checkpoint = load_torch_checkpoint(model_path)
        if checkpoint.get("feature_columns") != FEATURE_ORDER:
            raise ArtifactLoadError(f"Checkpoint feature order mismatch in {model_path}")

        architecture = checkpoint.get("architecture") or {}
        if architecture.get("input_neurons") != 7 or architecture.get("hidden_layers") != [14, 8] or architecture.get("output_neurons") != 1:
            raise ArtifactLoadError(f"Checkpoint architecture mismatch in {model_path}")

        checkpoint_normalization = checkpoint.get("normalization") or {}
        if checkpoint_normalization.get("method") != "z_score":
            raise ArtifactLoadError(f"Unsupported normalization method in {model_path}")

        normalization_mean = np.array(normalization.get("mean"), dtype=np.float32)
        normalization_std = np.array(normalization.get("std"), dtype=np.float32)
        checkpoint_mean = np.array(checkpoint_normalization.get("mean"), dtype=np.float32)
        checkpoint_std = np.array(checkpoint_normalization.get("std"), dtype=np.float32)

        if normalization_mean.shape != (7,) or normalization_std.shape != (7,):
            raise ArtifactLoadError(f"Normalization parameter shape mismatch in {normalization_path}")
        if np.allclose(normalization_mean, checkpoint_mean) is False or np.allclose(normalization_std, checkpoint_std) is False:
            raise ArtifactLoadError(f"Normalization metadata mismatch between {model_path} and {normalization_path}")

        model = AttendanceMLP()
        model.load_state_dict(checkpoint["state_dict"])
        model.eval()

        return LoadedArtifact(
            model=model,
            model_version=str(metadata["model_version_id"]),
            artifact_id=str(metadata["model_version_id"]),
            feature_order=list(feature_order),
            normalization_mean=normalization_mean,
            normalization_std=normalization_std,
            metadata_path=metadata_path.resolve(),
            model_path=model_path,
            normalization_path=normalization_path,
        )


def load_torch_checkpoint(model_path: Path) -> dict[str, Any]:
    try:
        return torch.load(model_path, map_location="cpu")
    except TypeError:
        return torch.load(model_path, map_location="cpu", weights_only=False)


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
