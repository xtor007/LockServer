#!/usr/bin/env python3
"""Relabel attendance MLP datasets into five discrete justification levels."""

from __future__ import annotations

import argparse
import csv
import random
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path


LABEL_STRINGS = {
    1.0: "1",
    0.7: "0.7",
    0.5: "0.5",
    0.3: "0.3",
    0.0: "0",
}


@dataclass(frozen=True)
class LabelInputs:
    duration_need: float
    start_need: float
    duration_context: float
    start_context: float
    air_pre: float
    air_gap: float
    air_total: float
    traffic: float
    power: float
    weather: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Relabel attendance MLP CSV datasets into five discrete target values."
    )
    parser.add_argument(
        "paths",
        nargs="+",
        help="CSV dataset paths to relabel in-place.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Seed used for deterministic sample selection in the summary.",
    )
    parser.add_argument(
        "--samples-per-label",
        type=int,
        default=3,
        help="How many sample rows to print for each label.",
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Write relabeled targets back to the provided CSV files.",
    )
    return parser.parse_args()


def parse_reason(reason: str) -> LabelInputs:
    values: dict[str, str] = {}
    for chunk in reason.split(";"):
        if "=" not in chunk:
            continue
        key, value = chunk.split("=", 1)
        values[key] = value

    return LabelInputs(
        duration_need=float(values["duration_need"]),
        start_need=float(values["start_need"]),
        duration_context=float(values["duration_context"]),
        start_context=float(values["start_context"]),
        air_pre=float(values["air_pre"]),
        air_gap=float(values["air_gap"]),
        air_total=float(values["air_total"]),
        traffic=float(values["traffic"]),
        power=float(values["power"]),
        weather=float(values["weather"]),
    )


def assign_label(inputs: LabelInputs) -> tuple[float, str, float]:
    total_need = inputs.duration_need + inputs.start_need
    if total_need <= 0.0001:
        return 1.0, "no_meaningful_deviation", 1.0

    coverage = (
        inputs.duration_need * inputs.duration_context +
        inputs.start_need * inputs.start_context
    ) / total_need

    # Tiny deviations are treated as effectively justified by default.
    if inputs.duration_need <= 0.15 and inputs.start_need <= 0.20:
        return 1.0, "minor_deviation_auto_high", coverage

    # Direct duration loss covered by time outside work during alerts.
    if (
        inputs.duration_need >= 0.25 and
        inputs.start_need <= 0.20 and
        inputs.duration_context >= 0.80
    ):
        return 1.0, "duration_loss_directly_covered", coverage

    # Direct start-time problem covered by arrival factors with little duration loss.
    if (
        inputs.start_need >= 0.25 and
        inputs.duration_need <= 0.20 and
        inputs.start_context >= 0.80
    ):
        return 1.0, "late_start_directly_covered", coverage

    # Strong duration deficit with no direct duration explanation stays unjustified.
    if (
        inputs.duration_need >= 0.25 and
        inputs.start_need <= 0.20 and
        inputs.duration_context < 0.15
    ):
        return 0.0, "duration_loss_uncovered", coverage

    # Mixed cases are bucketed by how much of the deviation is actually covered.
    if coverage >= 0.70:
        return 0.7, "strong_context_cover", coverage
    if coverage >= 0.35:
        return 0.5, "medium_context_cover", coverage
    if coverage > 0.0:
        return 0.3, "weak_context_cover", coverage
    return 0.0, "uncovered_deviation", coverage


def make_reason(label: float, rule: str, coverage: float, inputs: LabelInputs) -> str:
    return (
        f"rule={rule};label={LABEL_STRINGS[label]};coverage={coverage:.4f};"
        f"duration_need={inputs.duration_need:.4f};start_need={inputs.start_need:.4f};"
        f"duration_context={inputs.duration_context:.4f};start_context={inputs.start_context:.4f};"
        f"air_pre={inputs.air_pre:.0f};air_gap={inputs.air_gap:.0f};air_total={inputs.air_total:.0f};"
        f"traffic={inputs.traffic:.4f};power={inputs.power:.4f};weather={inputs.weather:.4f}"
    )


def relabel_file(path: Path) -> tuple[list[dict[str, str]], Counter[float]]:
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))

    counts: Counter[float] = Counter()
    for row in rows:
        inputs = parse_reason(row["eta_nn_label_reason"])
        label, rule, coverage = assign_label(inputs)
        row["eta_nn_target"] = LABEL_STRINGS[label]
        row["eta_nn_label_reason"] = make_reason(label, rule, coverage, inputs)
        counts[label] += 1

    if rows and args.write:
        with path.open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)

    return rows, counts


def print_summary(path: Path, rows: list[dict[str, str]], seed: int, samples_per_label: int) -> None:
    print(f"=== {path} ===")
    total = len(rows)
    counts = Counter(float(row["eta_nn_target"]) for row in rows)
    for label in (1.0, 0.7, 0.5, 0.3, 0.0):
        count = counts[label]
        share = (count / total * 100.0) if total else 0.0
        print(f"LABEL\t{LABEL_STRINGS[label]}\tcount={count}\tshare={share:.2f}%")

    rng = random.Random(seed)
    by_label: dict[float, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        by_label[float(row["eta_nn_target"])].append(row)

    for label in (1.0, 0.7, 0.5, 0.3, 0.0):
        bucket = by_label[label]
        if not bucket:
            continue
        sample_size = min(samples_per_label, len(bucket))
        print(f"SAMPLES\t{LABEL_STRINGS[label]}")
        for sample in rng.sample(bucket, sample_size):
            print(
                "ROW\t"
                f"z_s={sample['z_s']}\t"
                f"z_t={sample['z_t']}\t"
                f"f={sample['f']}\t"
                f"air_alert_minutes={sample['air_alert_minutes']}\t"
                f"traffic_score={sample['traffic_score']}\t"
                f"power_score={sample['power_score']}\t"
                f"weather_score={sample['weather_score']}\t"
                f"eta_nn_target={sample['eta_nn_target']}\t"
                f"reason={sample['eta_nn_label_reason']}"
            )


if __name__ == "__main__":
    args = parse_args()
    for raw_path in args.paths:
        path = Path(raw_path)
        rows, _ = relabel_file(path)
        print_summary(path, rows, seed=args.seed, samples_per_label=args.samples_per_label)
