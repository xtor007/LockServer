#!/usr/bin/env python3
"""Offline MLP training pipeline for attendance-analysis justification scoring."""

from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import json
import math
import random
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict
from typing import List
from typing import Sequence

import numpy as np
import torch
from torch import nn


FEATURE_COLUMNS = [
    "z_s",
    "z_t",
    "f",
    "air_alert_minutes",
    "traffic_score",
    "power_score",
    "weather_score",
]
TARGET_COLUMN = "eta_nn_target"
OPTIONAL_COLUMNS = ["eta_nn_label_reason"]
REQUIRED_COLUMNS = FEATURE_COLUMNS + [TARGET_COLUMN]

DEFAULT_SPLIT_SEED = 20260428
DEFAULT_TRAINING_SEED = 20260428
DEFAULT_EPOCHS = 300
DEFAULT_BATCH_SIZE = 256
DEFAULT_PATIENCE = 40
DEFAULT_LEARNING_RATE = 0.01
DEFAULT_WEIGHT_DECAY = 1e-4
ACCURACY_TOLERANCE = 0.10

SPLIT_RATIOS = {
    "train": 0.70,
    "validation": 0.10,
    "test": 0.20,
}

SCRIPT_PATH = Path(__file__).resolve()
WORKSPACE_ROOT = SCRIPT_PATH.parents[4]
DATASET_PATH = WORKSPACE_ROOT / "attendance_mlp_dataset.csv"
TRAIN_SPLIT_PATH = WORKSPACE_ROOT / "attendance_mlp_train.csv"
VAL_SPLIT_PATH = WORKSPACE_ROOT / "attendance_mlp_val.csv"
TEST_SPLIT_PATH = WORKSPACE_ROOT / "attendance_mlp_test.csv"
SPLIT_METADATA_PATH = WORKSPACE_ROOT / "attendance_mlp_split_metadata.json"
ARTIFACTS_ROOT = WORKSPACE_ROOT / "mlp_artifacts"

TRAINING_COMMAND = str(SCRIPT_PATH)
TRAINING_COMMAND_RELATIVE = "LockServer/services/attendance-analysis-service/mlp/train_attendance_mlp.py"
RETRAIN_COMMAND = "LockServer/infrastructure/local/retrain-attendance-mlp.sh"


@dataclass(frozen=True)
class DatasetRow:
    source_row_number: int
    raw_values: Dict[str, str]
    features: np.ndarray
    target: float


@dataclass(frozen=True)
class LoadedDataset:
    rows: List[DatasetRow]
    invalid_rows: List[Dict[str, object]]
    fieldnames: List[str]
    dataset_sha256: str


@dataclass(frozen=True)
class SplitPaths:
    train: Path
    validation: Path
    test: Path
    metadata: Path


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


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Train the 7 -> 14 -> 8 -> 1 attendance-analysis MLP offline."
    )
    parser.add_argument(
        "command",
        nargs="?",
        default="retrain",
        choices=["split", "train", "retrain"],
        help="split: only materialize deterministic splits; train/retrain: train and save a new versioned artifact.",
    )
    parser.add_argument(
        "--dataset",
        default=str(DATASET_PATH),
        help="Path to the root attendance MLP CSV dataset.",
    )
    parser.add_argument(
        "--artifacts-dir",
        default=str(ARTIFACTS_ROOT),
        help="Directory where versioned model artifacts are stored.",
    )
    parser.add_argument(
        "--split-seed",
        type=int,
        default=DEFAULT_SPLIT_SEED,
        help="Deterministic seed for 70/10/20 split materialization.",
    )
    parser.add_argument(
        "--training-seed",
        type=int,
        default=DEFAULT_TRAINING_SEED,
        help="Deterministic seed for model initialization and batching.",
    )
    parser.add_argument(
        "--epochs",
        type=int,
        default=DEFAULT_EPOCHS,
        help="Maximum training epochs.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=DEFAULT_BATCH_SIZE,
        help="Mini-batch size for training.",
    )
    parser.add_argument(
        "--learning-rate",
        type=float,
        default=DEFAULT_LEARNING_RATE,
        help="Adam learning rate.",
    )
    parser.add_argument(
        "--weight-decay",
        type=float,
        default=DEFAULT_WEIGHT_DECAY,
        help="Adam weight decay.",
    )
    parser.add_argument(
        "--patience",
        type=int,
        default=DEFAULT_PATIENCE,
        help="Early-stopping patience based on validation loss.",
    )
    parser.add_argument(
        "--accuracy-tolerance",
        type=float,
        default=ACCURACY_TOLERANCE,
        help="Absolute-error tolerance used for reported accuracy on [0, 1] targets.",
    )
    parser.add_argument(
        "--recreate-splits",
        action="store_true",
        help="Force regeneration of split files and metadata before training.",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()

    dataset_path = Path(arguments.dataset).resolve()
    artifacts_root = Path(arguments.artifacts_dir).resolve()
    split_paths = SplitPaths(
        train=TRAIN_SPLIT_PATH,
        validation=VAL_SPLIT_PATH,
        test=TEST_SPLIT_PATH,
        metadata=SPLIT_METADATA_PATH,
    )

    loaded_dataset = load_dataset(dataset_path)

    split_metadata = ensure_splits(
        loaded_dataset=loaded_dataset,
        dataset_path=dataset_path,
        split_paths=split_paths,
        split_seed=arguments.split_seed,
        force_recreate=arguments.recreate_splits,
    )

    if arguments.command == "split":
        print_split_summary(split_metadata, loaded_dataset)
        return 0

    train_rows, validation_rows, test_rows = partition_rows_by_split(
        rows=loaded_dataset.rows,
        split_metadata=split_metadata,
    )

    training_summary = train_pipeline(
        train_rows=train_rows,
        validation_rows=validation_rows,
        test_rows=test_rows,
        dataset_path=dataset_path,
        artifacts_root=artifacts_root,
        split_metadata=split_metadata,
        invalid_rows=loaded_dataset.invalid_rows,
        training_seed=arguments.training_seed,
        epochs=arguments.epochs,
        batch_size=arguments.batch_size,
        learning_rate=arguments.learning_rate,
        weight_decay=arguments.weight_decay,
        patience=arguments.patience,
        accuracy_tolerance=arguments.accuracy_tolerance,
    )

    print_training_summary(training_summary)
    return 0


def load_dataset(dataset_path: Path) -> LoadedDataset:
    if dataset_path.exists() is False:
        raise FileNotFoundError(f"Dataset file does not exist: {dataset_path}")

    dataset_sha256 = sha256_file(dataset_path)
    with dataset_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError(f"Dataset file is missing a header row: {dataset_path}")
        fieldnames = list(reader.fieldnames)

        missing_columns = [column for column in REQUIRED_COLUMNS if column not in fieldnames]
        if missing_columns:
            raise ValueError(
                "Dataset is missing required columns: " + ", ".join(missing_columns)
            )

        rows: List[DatasetRow] = []
        invalid_rows: List[Dict[str, object]] = []

        for source_row_number, raw_row in enumerate(reader, start=2):
            parsed_row = parse_dataset_row(
                source_row_number=source_row_number,
                raw_row=raw_row,
            )
            if isinstance(parsed_row, DatasetRow):
                rows.append(parsed_row)
            else:
                invalid_rows.append(parsed_row)

    if rows:
        target_values = np.array([row.target for row in rows], dtype=np.float32)
        if np.any(target_values < 0.0) or np.any(target_values > 1.0):
            raise ValueError("Target values must stay inside [0, 1].")
    else:
        raise ValueError(f"Dataset contains no valid rows: {dataset_path}")

    return LoadedDataset(
        rows=rows,
        invalid_rows=invalid_rows,
        fieldnames=fieldnames,
        dataset_sha256=dataset_sha256,
    )


def parse_dataset_row(source_row_number: int, raw_row: Dict[str, str]) -> DatasetRow | Dict[str, object]:
    numeric_values: List[float] = []
    for column in FEATURE_COLUMNS:
        raw_value = raw_row.get(column, "")
        if raw_value == "":
            return invalid_row(source_row_number, f"missing feature {column}")
        try:
            parsed_value = float(raw_value)
        except ValueError:
            return invalid_row(source_row_number, f"invalid numeric feature {column}={raw_value!r}")
        if math.isfinite(parsed_value) is False:
            return invalid_row(source_row_number, f"non-finite feature {column}")
        numeric_values.append(parsed_value)

    raw_target = raw_row.get(TARGET_COLUMN, "")
    if raw_target == "":
        return invalid_row(source_row_number, f"missing target {TARGET_COLUMN}")

    try:
        target = float(raw_target)
    except ValueError:
        return invalid_row(source_row_number, f"invalid target {TARGET_COLUMN}={raw_target!r}")

    if math.isfinite(target) is False:
        return invalid_row(source_row_number, f"non-finite target {TARGET_COLUMN}")
    if target < 0.0 or target > 1.0:
        return invalid_row(source_row_number, f"target outside [0, 1]: {target}")

    return DatasetRow(
        source_row_number=source_row_number,
        raw_values=dict(raw_row),
        features=np.array(numeric_values, dtype=np.float32),
        target=target,
    )


def invalid_row(source_row_number: int, reason: str) -> Dict[str, object]:
    return {
        "source_row_number": source_row_number,
        "reason": reason,
    }


def ensure_splits(
    loaded_dataset: LoadedDataset,
    dataset_path: Path,
    split_paths: SplitPaths,
    split_seed: int,
    force_recreate: bool,
) -> Dict[str, object]:
    if force_recreate is False:
        existing_metadata = load_existing_split_metadata(
            split_paths=split_paths,
            dataset_path=dataset_path,
            dataset_sha256=loaded_dataset.dataset_sha256,
            expected_valid_rows=len(loaded_dataset.rows),
            split_seed=split_seed,
        )
        if existing_metadata is not None:
            return existing_metadata

    split_mapping = build_split_mapping(rows=loaded_dataset.rows, split_seed=split_seed)
    metadata = write_split_artifacts(
        loaded_dataset=loaded_dataset,
        dataset_path=dataset_path,
        split_paths=split_paths,
        split_seed=split_seed,
        split_mapping=split_mapping,
    )
    return metadata


def load_existing_split_metadata(
    split_paths: SplitPaths,
    dataset_path: Path,
    dataset_sha256: str,
    expected_valid_rows: int,
    split_seed: int,
) -> Dict[str, object] | None:
    required_paths = [
        split_paths.train,
        split_paths.validation,
        split_paths.test,
        split_paths.metadata,
    ]
    if any(path.exists() is False for path in required_paths):
        return None

    with split_paths.metadata.open("r", encoding="utf-8") as handle:
        metadata = json.load(handle)

    if metadata.get("dataset_path") != str(dataset_path):
        return None
    if metadata.get("dataset_sha256") != dataset_sha256:
        return None
    if metadata.get("split_seed") != split_seed:
        return None
    if metadata.get("valid_rows_count") != expected_valid_rows:
        return None
    if metadata.get("split_ratios") != SPLIT_RATIOS:
        return None

    split_files = metadata.get("split_files", {})
    expected_file_hashes = {
        "train": sha256_file(split_paths.train),
        "validation": sha256_file(split_paths.validation),
        "test": sha256_file(split_paths.test),
    }
    for split_name, file_hash in expected_file_hashes.items():
        split_file = split_files.get(split_name, {})
        if split_file.get("path") != str(getattr(split_paths, split_name)):
            return None
        if split_file.get("sha256") != file_hash:
            return None

    return metadata


def build_split_mapping(rows: Sequence[DatasetRow], split_seed: int) -> Dict[int, str]:
    row_numbers = [row.source_row_number for row in rows]
    shuffled_row_numbers = list(row_numbers)
    random.Random(split_seed).shuffle(shuffled_row_numbers)

    train_count = int(len(shuffled_row_numbers) * SPLIT_RATIOS["train"])
    validation_count = int(len(shuffled_row_numbers) * SPLIT_RATIOS["validation"])

    train_row_numbers = set(shuffled_row_numbers[:train_count])
    validation_row_numbers = set(
        shuffled_row_numbers[train_count:train_count + validation_count]
    )
    test_row_numbers = set(shuffled_row_numbers[train_count + validation_count:])

    split_mapping: Dict[int, str] = {}
    for row_number in train_row_numbers:
        split_mapping[row_number] = "train"
    for row_number in validation_row_numbers:
        split_mapping[row_number] = "validation"
    for row_number in test_row_numbers:
        split_mapping[row_number] = "test"

    if len(split_mapping) != len(rows):
        raise RuntimeError("Split mapping does not cover all valid rows.")
    return split_mapping


def write_split_artifacts(
    loaded_dataset: LoadedDataset,
    dataset_path: Path,
    split_paths: SplitPaths,
    split_seed: int,
    split_mapping: Dict[int, str],
) -> Dict[str, object]:
    grouped_rows: Dict[str, List[DatasetRow]] = {
        "train": [],
        "validation": [],
        "test": [],
    }
    for row in loaded_dataset.rows:
        grouped_rows[split_mapping[row.source_row_number]].append(row)

    write_split_csv(
        fieldnames=loaded_dataset.fieldnames,
        rows=grouped_rows["train"],
        output_path=split_paths.train,
    )
    write_split_csv(
        fieldnames=loaded_dataset.fieldnames,
        rows=grouped_rows["validation"],
        output_path=split_paths.validation,
    )
    write_split_csv(
        fieldnames=loaded_dataset.fieldnames,
        rows=grouped_rows["test"],
        output_path=split_paths.test,
    )

    split_files = {
        "train": {
            "path": str(split_paths.train),
            "rows": len(grouped_rows["train"]),
            "sha256": sha256_file(split_paths.train),
        },
        "validation": {
            "path": str(split_paths.validation),
            "rows": len(grouped_rows["validation"]),
            "sha256": sha256_file(split_paths.validation),
        },
        "test": {
            "path": str(split_paths.test),
            "rows": len(grouped_rows["test"]),
            "sha256": sha256_file(split_paths.test),
        },
    }

    metadata = {
        "version": 1,
        "created_at": utc_now_iso(),
        "dataset_path": str(dataset_path),
        "dataset_sha256": loaded_dataset.dataset_sha256,
        "valid_rows_count": len(loaded_dataset.rows),
        "invalid_rows_count": len(loaded_dataset.invalid_rows),
        "required_columns": REQUIRED_COLUMNS,
        "optional_columns": [
            column for column in OPTIONAL_COLUMNS if column in loaded_dataset.fieldnames
        ],
        "split_seed": split_seed,
        "split_ratios": SPLIT_RATIOS,
        "split_files": split_files,
        "split_assignments": {
            split_name: [row.source_row_number for row in grouped_rows[split_name]]
            for split_name in ["train", "validation", "test"]
        },
        "invalid_rows_preview": loaded_dataset.invalid_rows[:20],
    }

    write_json(split_paths.metadata, metadata)
    return metadata


def write_split_csv(fieldnames: Sequence[str], rows: Sequence[DatasetRow], output_path: Path) -> None:
    with output_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row.raw_values)


def partition_rows_by_split(
    rows: Sequence[DatasetRow],
    split_metadata: Dict[str, object],
) -> tuple[List[DatasetRow], List[DatasetRow], List[DatasetRow]]:
    split_assignments = split_metadata["split_assignments"]
    split_sets = {
        split_name: set(split_assignments[split_name])
        for split_name in ["train", "validation", "test"]
    }

    grouped_rows = {
        "train": [],
        "validation": [],
        "test": [],
    }
    for row in rows:
        if row.source_row_number in split_sets["train"]:
            grouped_rows["train"].append(row)
        elif row.source_row_number in split_sets["validation"]:
            grouped_rows["validation"].append(row)
        elif row.source_row_number in split_sets["test"]:
            grouped_rows["test"].append(row)
        else:
            raise RuntimeError(f"Row {row.source_row_number} is missing from split assignments.")

    return (
        grouped_rows["train"],
        grouped_rows["validation"],
        grouped_rows["test"],
    )


def train_pipeline(
    train_rows: Sequence[DatasetRow],
    validation_rows: Sequence[DatasetRow],
    test_rows: Sequence[DatasetRow],
    dataset_path: Path,
    artifacts_root: Path,
    split_metadata: Dict[str, object],
    invalid_rows: Sequence[Dict[str, object]],
    training_seed: int,
    epochs: int,
    batch_size: int,
    learning_rate: float,
    weight_decay: float,
    patience: int,
    accuracy_tolerance: float,
) -> Dict[str, object]:
    if accuracy_tolerance <= 0.0:
        raise ValueError("Accuracy tolerance must be positive.")

    set_deterministic_seed(training_seed)

    train_features, train_targets = rows_to_numpy(train_rows)
    validation_features, validation_targets = rows_to_numpy(validation_rows)
    test_features, test_targets = rows_to_numpy(test_rows)

    normalizer = fit_normalizer(train_features)

    train_features_normalized = apply_normalizer(train_features, normalizer)
    validation_features_normalized = apply_normalizer(validation_features, normalizer)
    test_features_normalized = apply_normalizer(test_features, normalizer)

    train_features_tensor = torch.from_numpy(train_features_normalized)
    train_targets_tensor = torch.from_numpy(train_targets.reshape(-1, 1))
    validation_features_tensor = torch.from_numpy(validation_features_normalized)
    validation_targets_tensor = torch.from_numpy(validation_targets.reshape(-1, 1))
    test_features_tensor = torch.from_numpy(test_features_normalized)
    test_targets_tensor = torch.from_numpy(test_targets.reshape(-1, 1))

    model = AttendanceMLP()
    optimizer = torch.optim.Adam(
        model.parameters(),
        lr=learning_rate,
        weight_decay=weight_decay,
    )
    loss_function = nn.MSELoss()

    best_state = copy.deepcopy(model.state_dict())
    best_validation_loss = float("inf")
    best_epoch = 0
    epochs_without_improvement = 0
    epoch_history: List[Dict[str, float]] = []
    generator = torch.Generator().manual_seed(training_seed)

    for epoch in range(1, epochs + 1):
        model.train()
        permutation = torch.randperm(train_features_tensor.size(0), generator=generator)
        batch_losses = []

        for start_index in range(0, train_features_tensor.size(0), batch_size):
            batch_indices = permutation[start_index:start_index + batch_size]
            batch_features = train_features_tensor[batch_indices]
            batch_targets = train_targets_tensor[batch_indices]

            optimizer.zero_grad()
            batch_predictions = model(batch_features)
            loss = loss_function(batch_predictions, batch_targets)
            loss.backward()
            optimizer.step()
            batch_losses.append(loss.item())

        validation_metrics = evaluate_model(
            model=model,
            features=validation_features_tensor,
            targets=validation_targets_tensor,
            accuracy_tolerance=accuracy_tolerance,
        )

        epoch_record = {
            "epoch": epoch,
            "training_loss": float(np.mean(batch_losses)),
            "validation_loss": validation_metrics["loss"],
            "validation_mae": validation_metrics["mae"],
            "validation_rmse": validation_metrics["rmse"],
            "validation_accuracy": validation_metrics["accuracy"],
        }
        epoch_history.append(epoch_record)

        if validation_metrics["loss"] + 1e-12 < best_validation_loss:
            best_validation_loss = validation_metrics["loss"]
            best_epoch = epoch
            best_state = copy.deepcopy(model.state_dict())
            epochs_without_improvement = 0
        else:
            epochs_without_improvement += 1

        if epochs_without_improvement >= patience:
            break

    model.load_state_dict(best_state)

    training_metrics = evaluate_model(
        model=model,
        features=train_features_tensor,
        targets=train_targets_tensor,
        accuracy_tolerance=accuracy_tolerance,
    )
    validation_metrics = evaluate_model(
        model=model,
        features=validation_features_tensor,
        targets=validation_targets_tensor,
        accuracy_tolerance=accuracy_tolerance,
    )
    test_metrics = evaluate_model(
        model=model,
        features=test_features_tensor,
        targets=test_targets_tensor,
        accuracy_tolerance=accuracy_tolerance,
    )

    version_id = make_version_id(dataset_path)
    version_directory = artifacts_root / version_id
    version_directory.mkdir(parents=True, exist_ok=False)

    model_path = version_directory / "model.pt"
    normalization_path = version_directory / "normalization.json"
    metrics_path = version_directory / "metrics.json"
    metadata_path = version_directory / "metadata.json"
    history_path = version_directory / "training_history.json"

    checkpoint = {
        "state_dict": model.state_dict(),
        "feature_columns": FEATURE_COLUMNS,
        "target_column": TARGET_COLUMN,
        "architecture": {
            "input_neurons": 7,
            "hidden_layers": [14, 8],
            "output_neurons": 1,
            "hidden_activation": "relu",
            "output_activation": "sigmoid",
        },
        "normalization": {
            "method": "z_score",
            "mean": normalizer["mean"].tolist(),
            "std": normalizer["std"].tolist(),
        },
    }
    torch.save(checkpoint, model_path)

    normalization_payload = {
        "method": "z_score",
        "feature_columns": FEATURE_COLUMNS,
        "fitted_on_split": "train",
        "mean": normalizer["mean"].tolist(),
        "std": normalizer["std"].tolist(),
        "std_replacement_rule": "0 values are replaced with 1.0 to avoid division by zero.",
    }
    write_json(normalization_path, normalization_payload)

    metrics_payload = {
        "loss_name": "mean_squared_error",
        "accuracy_definition": {
            "name": "tolerance_accuracy",
            "absolute_error_threshold": accuracy_tolerance,
            "description": "Prediction counts as accurate when absolute error is less than or equal to the threshold.",
        },
        "training": training_metrics,
        "validation": validation_metrics,
        "test": test_metrics,
    }
    write_json(metrics_path, metrics_payload)
    write_json(history_path, epoch_history)

    split_files = split_metadata["split_files"]
    metadata = {
        "model_version_id": version_id,
        "created_at": utc_now_iso(),
        "dataset_file_used": str(dataset_path),
        "dataset_sha256": sha256_file(dataset_path),
        "split_metadata_used": str(SPLIT_METADATA_PATH),
        "split_metadata_sha256": sha256_file(SPLIT_METADATA_PATH),
        "split_files_used": {
            "train": split_files["train"]["path"],
            "validation": split_files["validation"]["path"],
            "test": split_files["test"]["path"],
        },
        "feature_list": FEATURE_COLUMNS,
        "feature_order": FEATURE_COLUMNS,
        "target_definition": {
            "column": TARGET_COLUMN,
            "meaning": "Contextual justification coefficient eta_nn in range [0, 1].",
        },
        "architecture": {
            "input_neurons": 7,
            "hidden_layers": [14, 8],
            "output_neurons": 1,
            "topology": "7 -> 14 -> 8 -> 1",
            "hidden_activation": "relu",
            "output_activation": "sigmoid",
        },
        "normalization_method": {
            "name": "z_score",
            "fit_split": "train",
            "parameters_file": str(normalization_path),
        },
        "training_configuration": {
            "training_seed": training_seed,
            "split_seed": split_metadata["split_seed"],
            "epochs_requested": epochs,
            "epochs_completed": len(epoch_history),
            "best_epoch": best_epoch,
            "batch_size": batch_size,
            "learning_rate": learning_rate,
            "weight_decay": weight_decay,
            "patience": patience,
            "loss_name": "mean_squared_error",
        },
        "metrics_files": {
            "metrics": str(metrics_path),
            "training_history": str(history_path),
            "model": str(model_path),
        },
        "training_metrics": training_metrics,
        "validation_metrics": validation_metrics,
        "test_metrics": test_metrics,
        "accuracy_definition": metrics_payload["accuracy_definition"],
        "dataset_summary": {
            "valid_rows_count": split_metadata["valid_rows_count"],
            "invalid_rows_count": len(invalid_rows),
            "invalid_rows_preview": list(invalid_rows[:20]),
        },
        "manual_retraining_commands": {
            "wrapper_script": RETRAIN_COMMAND,
            "python_command": f"python3 {TRAINING_COMMAND_RELATIVE} retrain",
        },
    }
    write_json(metadata_path, metadata)

    latest_metadata = {
        "model_version_id": version_id,
        "metadata_path": str(metadata_path),
        "updated_at": utc_now_iso(),
    }
    write_json(artifacts_root / "latest.json", latest_metadata)

    return {
        "model_version_id": version_id,
        "artifact_directory": str(version_directory),
        "dataset_path": str(dataset_path),
        "split_metadata_path": str(SPLIT_METADATA_PATH),
        "training_metrics": training_metrics,
        "validation_metrics": validation_metrics,
        "test_metrics": test_metrics,
        "accuracy_tolerance": accuracy_tolerance,
        "normalization_path": str(normalization_path),
        "metadata_path": str(metadata_path),
        "model_path": str(model_path),
        "best_epoch": best_epoch,
        "epochs_completed": len(epoch_history),
    }


def rows_to_numpy(rows: Sequence[DatasetRow]) -> tuple[np.ndarray, np.ndarray]:
    features = np.stack([row.features for row in rows]).astype(np.float32)
    targets = np.array([row.target for row in rows], dtype=np.float32)
    return features, targets


def fit_normalizer(features: np.ndarray) -> Dict[str, np.ndarray]:
    mean = features.mean(axis=0)
    std = features.std(axis=0)
    std = np.where(std == 0.0, 1.0, std)
    return {
        "mean": mean.astype(np.float32),
        "std": std.astype(np.float32),
    }


def apply_normalizer(features: np.ndarray, normalizer: Dict[str, np.ndarray]) -> np.ndarray:
    normalized = (features - normalizer["mean"]) / normalizer["std"]
    return normalized.astype(np.float32)


def evaluate_model(
    model: AttendanceMLP,
    features: torch.Tensor,
    targets: torch.Tensor,
    accuracy_tolerance: float,
) -> Dict[str, float]:
    model.eval()
    with torch.no_grad():
        predictions = model(features)
        loss = nn.functional.mse_loss(predictions, targets)
        absolute_errors = torch.abs(predictions - targets)
        mae = torch.mean(absolute_errors)
        rmse = torch.sqrt(torch.mean(torch.square(predictions - targets)))
        accuracy = torch.mean((absolute_errors <= accuracy_tolerance).float())

    return {
        "loss": round(float(loss.item()), 6),
        "mae": round(float(mae.item()), 6),
        "rmse": round(float(rmse.item()), 6),
        "accuracy": round(float(accuracy.item()), 6),
        "count": int(targets.size(0)),
    }


def set_deterministic_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if hasattr(torch, "use_deterministic_algorithms"):
        torch.use_deterministic_algorithms(True)


def make_version_id(dataset_path: Path) -> str:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    dataset_hash = sha256_file(dataset_path)[:8]
    return f"attendance-mlp-{timestamp}-{dataset_hash}"


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def print_split_summary(split_metadata: Dict[str, object], loaded_dataset: LoadedDataset) -> None:
    print("Deterministic split is ready.")
    print(f"Dataset: {DATASET_PATH}")
    print(f"Dataset SHA256: {loaded_dataset.dataset_sha256}")
    print(f"Valid rows: {split_metadata['valid_rows_count']}")
    print(f"Invalid rows skipped explicitly: {len(loaded_dataset.invalid_rows)}")
    print(
        "Split rows: "
        f"train={split_metadata['split_files']['train']['rows']}, "
        f"validation={split_metadata['split_files']['validation']['rows']}, "
        f"test={split_metadata['split_files']['test']['rows']}"
    )
    print(f"Split metadata: {SPLIT_METADATA_PATH}")


def print_training_summary(training_summary: Dict[str, object]) -> None:
    print("Attendance MLP offline training completed.")
    print(f"Model version: {training_summary['model_version_id']}")
    print(f"Artifact directory: {training_summary['artifact_directory']}")
    print(f"Split metadata: {training_summary['split_metadata_path']}")
    print(f"Model file: {training_summary['model_path']}")
    print(f"Metadata file: {training_summary['metadata_path']}")
    print(f"Normalization file: {training_summary['normalization_path']}")
    print(
        "Accuracy definition: tolerance_accuracy with absolute error <= "
        f"{training_summary['accuracy_tolerance']:.2f}"
    )
    print(
        "Training metrics: "
        f"loss={training_summary['training_metrics']['loss']:.6f}, "
        f"mae={training_summary['training_metrics']['mae']:.6f}, "
        f"rmse={training_summary['training_metrics']['rmse']:.6f}, "
        f"accuracy={training_summary['training_metrics']['accuracy'] * 100:.2f}%"
    )
    print(
        "Validation metrics: "
        f"loss={training_summary['validation_metrics']['loss']:.6f}, "
        f"mae={training_summary['validation_metrics']['mae']:.6f}, "
        f"rmse={training_summary['validation_metrics']['rmse']:.6f}, "
        f"accuracy={training_summary['validation_metrics']['accuracy'] * 100:.2f}%"
    )
    print(
        "Test metrics: "
        f"loss={training_summary['test_metrics']['loss']:.6f}, "
        f"mae={training_summary['test_metrics']['mae']:.6f}, "
        f"rmse={training_summary['test_metrics']['rmse']:.6f}, "
        f"accuracy={training_summary['test_metrics']['accuracy'] * 100:.2f}%"
    )
    print(
        "Final accuracy summary: "
        f"train={training_summary['training_metrics']['accuracy'] * 100:.2f}%, "
        f"validation={training_summary['validation_metrics']['accuracy'] * 100:.2f}%, "
        f"test={training_summary['test_metrics']['accuracy'] * 100:.2f}%"
    )


if __name__ == "__main__":
    raise SystemExit(main())
