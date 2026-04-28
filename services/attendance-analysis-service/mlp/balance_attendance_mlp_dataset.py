#!/usr/bin/env python3
"""Balance attendance MLP dataset by oversampling smaller label buckets."""

from __future__ import annotations

import argparse
import csv
import random
from collections import Counter, defaultdict
from pathlib import Path


BALANCED_LABEL_ORDER = ["1", "0.7", "0.5", "0.3", "0"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Balance attendance MLP CSV dataset by appending oversampled rows."
    )
    parser.add_argument(
        "dataset",
        help="Path to the root attendance MLP CSV dataset.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Deterministic seed for oversampling.",
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Write the balanced dataset back to disk.",
    )
    return parser.parse_args()


def load_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def group_rows(rows: list[dict[str, str]]) -> dict[str, list[dict[str, str]]]:
    grouped: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        grouped[row["eta_nn_target"]].append(row)
    return grouped


def balance_rows(rows: list[dict[str, str]], seed: int) -> list[dict[str, str]]:
    grouped = group_rows(rows)
    target_count = max(len(grouped[label]) for label in BALANCED_LABEL_ORDER)
    rng = random.Random(seed)

    balanced_rows = list(rows)
    for label in BALANCED_LABEL_ORDER:
        source_rows = grouped[label]
        deficit = target_count - len(source_rows)
        if deficit <= 0:
            continue

        for copy_index in range(deficit):
            sampled = dict(rng.choice(source_rows))
            sampled["eta_nn_label_reason"] = (
                f"{sampled['eta_nn_label_reason']};balanced_clone=1;"
                f"balanced_label={label};balanced_copy_index={copy_index + 1}"
            )
            balanced_rows.append(sampled)

    return balanced_rows


def write_rows(path: Path, rows: list[dict[str, str]]) -> None:
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def print_summary(path: Path, rows: list[dict[str, str]]) -> None:
    counts = Counter(row["eta_nn_target"] for row in rows)
    total = len(rows)
    print(f"=== {path} ===")
    print(f"TOTAL\t{total}")
    for label in BALANCED_LABEL_ORDER:
        count = counts[label]
        share = (count / total * 100.0) if total else 0.0
        print(f"LABEL\t{label}\tcount={count}\tshare={share:.2f}%")


if __name__ == "__main__":
    args = parse_args()
    dataset_path = Path(args.dataset).resolve()
    source_rows = load_rows(dataset_path)
    balanced_rows = balance_rows(source_rows, seed=args.seed)
    if args.write:
        write_rows(dataset_path, balanced_rows)
    print_summary(dataset_path, balanced_rows)
