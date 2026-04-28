#!/usr/bin/env python3
"""Rescale eta_nn_target values in the root attendance MLP dataset."""

from __future__ import annotations

import argparse
import csv
import math
import statistics
from pathlib import Path
from typing import Iterable
from typing import List


SCRIPT_PATH = Path(__file__).resolve()
WORKSPACE_ROOT = SCRIPT_PATH.parents[4]
DEFAULT_DATASET_PATH = WORKSPACE_ROOT / "attendance_mlp_dataset.csv"
TARGET_COLUMN = "eta_nn_target"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Multiply eta_nn_target values by a factor and clamp them into [0, 1]."
    )
    parser.add_argument(
        "--dataset",
        default=str(DEFAULT_DATASET_PATH),
        help="Path to the root attendance MLP CSV dataset.",
    )
    parser.add_argument(
        "--factor",
        type=float,
        required=True,
        help="Multiplicative factor applied to eta_nn_target before clamping.",
    )
    parser.add_argument(
        "--precision",
        type=int,
        default=4,
        help="Decimal places used when writing the scaled target back to CSV.",
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Persist scaled values back to the CSV. Without this flag the command is dry-run only.",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    dataset_path = Path(arguments.dataset).resolve()
    factor = arguments.factor
    precision = arguments.precision

    if factor <= 0:
        raise ValueError("Factor must be positive.")
    if precision < 0:
        raise ValueError("Precision must be non-negative.")

    rows, fieldnames = load_rows(dataset_path)
    before_values = parse_targets(rows)
    after_values = [clamp(value * factor) for value in before_values]

    print(f"Dataset: {dataset_path}")
    print(f"Rows: {len(rows)}")
    print(f"Factor: {factor}")
    print("Before:")
    print_summary(before_values)
    print("After:")
    print_summary(after_values)

    if arguments.write is False:
        print("Dry run only. Re-run with --write to persist the scaled targets.")
        return 0

    for row, value in zip(rows, after_values):
        row[TARGET_COLUMN] = format(value, f".{precision}f")

    with dataset_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print("Scaled targets were written back to the dataset.")
    return 0


def load_rows(dataset_path: Path) -> tuple[List[dict[str, str]], List[str]]:
    if dataset_path.exists() is False:
        raise FileNotFoundError(f"Dataset file does not exist: {dataset_path}")

    with dataset_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError(f"Dataset file is missing a header row: {dataset_path}")
        fieldnames = list(reader.fieldnames)
        if TARGET_COLUMN not in fieldnames:
            raise ValueError(f"Dataset file does not contain {TARGET_COLUMN}.")
        rows = list(reader)
    return rows, fieldnames


def parse_targets(rows: Iterable[dict[str, str]]) -> List[float]:
    values: List[float] = []
    for index, row in enumerate(rows, start=2):
        raw_value = row.get(TARGET_COLUMN, "")
        if raw_value == "":
            raise ValueError(f"Missing {TARGET_COLUMN} at CSV row {index}.")
        value = float(raw_value)
        if math.isfinite(value) is False:
            raise ValueError(f"Non-finite {TARGET_COLUMN} at CSV row {index}.")
        if value < 0 or value > 1:
            raise ValueError(f"{TARGET_COLUMN} outside [0,1] at CSV row {index}: {value}")
        values.append(value)
    if values:
        return values
    raise ValueError("Dataset contains no rows.")


def clamp(value: float) -> float:
    return min(max(value, 0.0), 1.0)


def print_summary(values: List[float]) -> None:
    sorted_values = sorted(values)
    total = len(sorted_values)
    average = sum(sorted_values) / total
    print(f"  avg={average:.6f}")
    print(f"  median={statistics.median(sorted_values):.6f}")
    print(f"  min={sorted_values[0]:.6f}")
    print(f"  p90={percentile(sorted_values, 0.90):.6f}")
    print(f"  p95={percentile(sorted_values, 0.95):.6f}")
    print(f"  max={sorted_values[-1]:.6f}")
    print(f"  >0.3={sum(value > 0.3 for value in sorted_values)}")
    print(f"  >0.5={sum(value > 0.5 for value in sorted_values)}")
    print(f"  >0.8={sum(value > 0.8 for value in sorted_values)}")


def percentile(sorted_values: List[float], quantile: float) -> float:
    if len(sorted_values) == 1:
        return sorted_values[0]
    index = (len(sorted_values) - 1) * quantile
    lower = math.floor(index)
    upper = math.ceil(index)
    if lower == upper:
        return sorted_values[lower]
    fraction = index - lower
    return sorted_values[lower] * (1 - fraction) + sorted_values[upper] * fraction


if __name__ == "__main__":
    raise SystemExit(main())
