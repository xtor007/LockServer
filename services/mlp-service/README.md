# Attendance MLP Inference Service

`mlp-service` is a standalone internal Python service for runtime inference of the attendance-analysis MLP model.

## Responsibilities

- load the latest trained artifact from `mlp_artifacts/`
- validate model metadata, feature order, architecture, and normalization
- accept ordered 7-feature vectors
- return `eta_nn`, `model_version`, and compact inference diagnostics

## Routes

- `GET /validate`
  - health check with loaded model metadata
- `GET /internal/mlp/model`
  - current loaded artifact info
- `POST /internal/mlp/infer`
  - batch inference endpoint
- `POST /internal/mlp/retrain`
  - retrain on top of the fixed base dataset plus accepted feedback samples
  - reload the newest artifact immediately after successful training

Request shape:

```json
{
  "items": [
    {
      "request_id": "row-1",
      "features": [-1.44, 3.57, 0.39, 106, 4.17, 0.0, 0.7]
    }
  ]
}
```

The feature order is fixed:

1. `z_s`
2. `z_t`
3. `f`
4. `air_alert_minutes`
5. `traffic_score`
6. `power_score`
7. `weather_score`

Retraining request shape:

```json
{
  "feedback_samples": [
    {
      "sample_id": "sample-1",
      "z_s": -1.44,
      "z_t": 3.57,
      "f": 0.39,
      "air_alert_minutes": 106,
      "traffic_score": 4.17,
      "power_score": 0.0,
      "weather_score": 0.7,
      "eta_nn_target": 0.58,
      "source_model_version": "attendance-mlp-..."
    }
  ]
}
```

## Local Run

```bash
python3 /Users/khramchenko/Desktop/кпи/diplom/code/LockServer/services/mlp-service/app.py
```

Optional environment variables:

- `LOCKSERVER_MLP_BIND_HOST`
- `LOCKSERVER_MLP_PORT`
- `LOCKSERVER_MLP_ARTIFACTS_ROOT`
- `LOCKSERVER_MLP_LATEST_POINTER`
