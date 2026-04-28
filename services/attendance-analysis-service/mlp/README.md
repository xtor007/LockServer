# Attendance MLP Offline Training

This directory contains the standalone Python pipeline for the attendance-analysis MLP stage described in `Attendance_Analysis_Algorithm.md`.

## Fixed Model Contract

- input features:
  - `z_s`
  - `z_t`
  - `f`
  - `air_alert_minutes`
  - `traffic_score`
  - `power_score`
  - `weather_score`
- target:
  - `eta_nn_target`
- exact topology:
  - `7 -> 14 -> 8 -> 1`
- hidden activation:
  - `ReLU`
- output activation:
  - `sigmoid`

## Split Policy

- root dataset:
  - `/Users/khramchenko/Desktop/кпи/diplom/code/attendance_mlp_dataset.csv`
- deterministic split:
  - `70%` train
  - `10%` validation
  - `20%` test
- reusable split artifacts:
  - `/Users/khramchenko/Desktop/кпи/diplom/code/attendance_mlp_train.csv`
  - `/Users/khramchenko/Desktop/кпи/diplom/code/attendance_mlp_val.csv`
  - `/Users/khramchenko/Desktop/кпи/diplom/code/attendance_mlp_test.csv`
  - `/Users/khramchenko/Desktop/кпи/diplom/code/attendance_mlp_split_metadata.json`

## Normalization

- method:
  - z-score normalization
- fit scope:
  - training split only
- saved with each model version:
  - mean per feature
  - std per feature

## Accuracy Rule

The target is continuous in `[0, 1]`, so the pipeline reports deterministic tolerance-based accuracy instead of exact-match accuracy.

- metric name:
  - `tolerance_accuracy`
- default rule:
  - prediction is accurate when `abs(prediction - eta_nn_target) <= 0.10`

The tolerance is printed in the training summary and persisted in the model metadata.

## Commands

Materialize or refresh only the deterministic split:

```bash
python3 /Users/khramchenko/Desktop/кпи/diplom/code/LockServer/services/attendance-analysis-service/mlp/train_attendance_mlp.py split
```

Preview or apply a multiplicative rescale to `eta_nn_target` in the root dataset:

```bash
python3 /Users/khramchenko/Desktop/кпи/diplom/code/LockServer/services/attendance-analysis-service/mlp/rescale_attendance_mlp_targets.py --factor 1.2
python3 /Users/khramchenko/Desktop/кпи/diplom/code/LockServer/services/attendance-analysis-service/mlp/rescale_attendance_mlp_targets.py --factor 1.2 --write
```

Run retraining and persist a new artifact version:

```bash
python3 /Users/khramchenko/Desktop/кпи/diplom/code/LockServer/services/attendance-analysis-service/mlp/train_attendance_mlp.py retrain
```

Accepted feedback samples are not merged into validation or test.

- fixed base dataset:
  - still owns the deterministic `70/10/20` split
- accepted feedback:
  - is appended only to the training side during automatic retraining
  - never rewrites the fixed validation/test comparison slices

Convenience wrapper for repeated offline retraining:

```bash
/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/infrastructure/local/retrain-attendance-mlp.sh
```

To rebuild split artifacts before retraining:

```bash
/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/infrastructure/local/retrain-attendance-mlp.sh --recreate-splits
```

## Artifact Layout

Each retraining run creates a new versioned directory under:

- `/Users/khramchenko/Desktop/кпи/diplom/code/mlp_artifacts/`

Each version stores:

- `model.pt`
- `normalization.json`
- `metrics.json`
- `metadata.json`
- `training_history.json`

`mlp_artifacts/latest.json` points to the most recently created version metadata.
