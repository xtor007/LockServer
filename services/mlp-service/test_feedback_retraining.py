from __future__ import annotations

import csv
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
TRAINING_MODULE_PATH = (
    SCRIPT_DIR.parent / "attendance-analysis-service" / "mlp" / "train_attendance_mlp.py"
)
INFERENCE_RUNTIME_PATH = SCRIPT_DIR / "inference_runtime.py"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


TRAINING_MODULE = load_module(TRAINING_MODULE_PATH, "attendance_mlp_training_test")
INFERENCE_RUNTIME_MODULE = load_module(INFERENCE_RUNTIME_PATH, "attendance_mlp_runtime_test")


class AttendanceMLPFeedbackRetrainingTests(unittest.TestCase):
    def test_feedback_samples_create_new_artifact_and_reload_runtime(self) -> None:
        with tempfile.TemporaryDirectory() as temp_directory:
            temp_root = Path(temp_directory)
            dataset_path = temp_root / "attendance_mlp_dataset.csv"
            artifacts_root = temp_root / "mlp_artifacts"
            split_paths = TRAINING_MODULE.SplitPaths(
                train=temp_root / "attendance_mlp_train.csv",
                validation=temp_root / "attendance_mlp_val.csv",
                test=temp_root / "attendance_mlp_test.csv",
                metadata=temp_root / "attendance_mlp_split_metadata.json",
            )
            self.write_dataset(dataset_path)

            summary_one = TRAINING_MODULE.train_with_feedback_samples(
                feedback_samples=self.feedback_samples(0.62),
                dataset_path=dataset_path,
                artifacts_root=artifacts_root,
                split_paths=split_paths,
                epochs=6,
                patience=2,
                batch_size=4,
            )
            self.assertEqual(summary_one["feedback_samples_count"], 2)

            metadata_one = json.loads(Path(summary_one["metadata_path"]).read_text(encoding="utf-8"))
            self.assertEqual(metadata_one["feedback_training_summary"]["count"], 2)
            self.assertEqual(metadata_one["feedback_training_summary"]["source_model_versions"], ["attendance-mlp-seed"])
            self.assertEqual(metadata_one["split_metadata_used"], str(split_paths.metadata))

            runtime = INFERENCE_RUNTIME_MODULE.AttendanceMLPInferenceRuntime(
                artifacts_root=artifacts_root,
                latest_pointer_path=artifacts_root / "latest.json",
            )
            first_version = runtime.model_info()["model_version"]
            self.assertEqual(first_version, summary_one["model_version_id"])

            summary_two = TRAINING_MODULE.train_with_feedback_samples(
                feedback_samples=self.feedback_samples(0.68),
                dataset_path=dataset_path,
                artifacts_root=artifacts_root,
                split_paths=split_paths,
                epochs=6,
                patience=2,
                batch_size=4,
            )
            reloaded = runtime.reload_latest_artifact()

            self.assertNotEqual(summary_one["model_version_id"], summary_two["model_version_id"])
            self.assertEqual(reloaded.model_version, summary_two["model_version_id"])
            self.assertEqual(runtime.model_info()["model_version"], summary_two["model_version_id"])

    def write_dataset(self, dataset_path: Path) -> None:
        fieldnames = [
            "z_s",
            "z_t",
            "f",
            "air_alert_minutes",
            "traffic_score",
            "power_score",
            "weather_score",
            "eta_nn_target",
            "eta_nn_label_reason",
        ]
        rows = []
        for index in range(12):
            rows.append(
                {
                    "z_s": f"{-1.8 + 0.22 * index:.4f}",
                    "z_t": f"{0.5 + 0.18 * index:.4f}",
                    "f": f"{0.1 + 0.03 * (index % 5):.4f}",
                    "air_alert_minutes": str(10 + index * 4),
                    "traffic_score": f"{1.2 + 0.15 * index:.4f}",
                    "power_score": f"{float(index % 2):.1f}",
                    "weather_score": f"{0.1 + 0.05 * (index % 4):.4f}",
                    "eta_nn_target": f"{0.2 + 0.04 * index:.4f}",
                    "eta_nn_label_reason": f"seed_row={index}",
                }
            )

        with dataset_path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)

    def feedback_samples(self, target_base: float) -> list[dict[str, object]]:
        return [
            {
                "sample_id": "feedback-1",
                "source_model_version": "attendance-mlp-seed",
                "z_s": -1.15,
                "z_t": 1.8,
                "f": 0.4,
                "air_alert_minutes": 85,
                "traffic_score": 3.4,
                "power_score": 1.0,
                "weather_score": 0.6,
                "eta_nn_target": target_base,
            },
            {
                "sample_id": "feedback-2",
                "source_model_version": "attendance-mlp-seed",
                "z_s": -0.95,
                "z_t": 1.4,
                "f": 0.35,
                "air_alert_minutes": 64,
                "traffic_score": 2.9,
                "power_score": 0.0,
                "weather_score": 0.5,
                "eta_nn_target": round(target_base - 0.07, 2),
            },
        ]


if __name__ == "__main__":
    unittest.main()
