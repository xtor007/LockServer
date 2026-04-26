# LockServer Endpoints

## Base URL

- Gateway: `http://127.0.0.1:8080`

## Routing Rule

- all documented endpoints in this file must be called through the gateway on `http://127.0.0.1:8080`
- direct microservice ports are not the canonical API surface for manual checks
- direct service ports may still exist for health checks, service-to-service traffic, and low-level debugging

## Test Users

- Admin:
  - email: `admin@lock.local`
  - password: `admin1234`
- User:
  - email: `user@lock.local`
  - password: `user1234`

## Local Run

Build and start the full microservices stack:

```bash
cd /Users/khramchenko/Desktop/кпи/diplom/code/LockServer
env HOME=/tmp/codex-home CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift build
./infrastructure/local/start-stack.sh
```

Keep that terminal open. From a second terminal, verify all public routes through the gateway:

```bash
./infrastructure/local/verify-endpoints.sh
```

The verification script checks attendance-analysis bootstrap endpoints through the gateway on `127.0.0.1:8080`.

Stop the stack:

```bash
./infrastructure/local/stop-stack.sh
```

Local development uses mock device mode by default, so `/open/open` works without a real Arduino.

## Auth Types

- No auth:
  - `/`
  - `/validate`
  - `/verifier/*`
  - `/auth/changePasswordEmail`
- Basic Auth:
  - `/auth/getToken`
  - `/auth/changePassword`
- Bearer refresh token:
  - `/auth/refresh`
- Bearer auth token:
  - `/info/*`
  - `/open/open`
  - `/command/*`

## Public Endpoints

### `GET /`

- Auth: none
- Response:

```text
ok
```

### `GET /validate`

- Auth: none
- Response:

```json
{"isValid":true}
```

### `GET /verifier/verifyCard?code=<CARD_CODE>`

- Auth: none
- Example:

```http
GET /verifier/verifyCard?code=E28E892A
```

- Response:
  - `"1"` when access is valid
  - `"0"` when access is invalid

### `GET /verifier/verifyFinger?code=<FINGER_CODE>`

- Auth: none
- Example:

```http
GET /verifier/verifyFinger?code=1
```

- Response:
  - `"1"` when access is valid
  - `"0"` when access is invalid

## Auth Endpoints

### `GET /auth/getToken`

- Auth: Basic Auth
- Username: user email
- Password: user password
- Example credentials:
  - `admin@lock.local` / `admin1234`
  - `user@lock.local` / `user1234`
- Response:

```json
{
  "auth": "jwt",
  "refresh": "jwt",
  "expDate": "2026-04-25T18:00:00Z"
}
```

### `GET /auth/refresh`

- Auth: Bearer refresh token
- Header:

```http
Authorization: Bearer <refresh_token>
```

- Response:

```json
{
  "auth": "jwt",
  "refresh": "jwt",
  "expDate": "2026-04-25T18:00:00Z"
}
```

### `POST /auth/changePasswordEmail`

- Auth: none
- Headers:
  - `Content-Type: application/json`
- Body:

```json
{
  "email": "user@lock.local"
}
```

- Response:

```json
{
  "code": "abcdefgh"
}
```

### `POST /auth/changePassword`

- Auth: Basic Auth
- Username: email
- Password: code returned by `/auth/changePasswordEmail`
- Headers:
  - `Content-Type: application/json`
- Body:

```json
{
  "password": "newPassword123"
}
```

- Response:

```json
{
  "isValid": true
}
```

## User Endpoints

### `GET /info/`

- Auth: Bearer auth token
- Response:

```json
{
  "id": "uuid",
  "isAdmin": false,
  "name": "Test",
  "surname": "Employee",
  "department": "QA",
  "email": "user@lock.local",
  "workNormMinutes": 480,
  "hasCard": true,
  "hasFinger": true
}
```

### `POST /info/logs`

- Auth: Bearer auth token
- Headers:
  - `Content-Type: application/json`
- Body:

```json
{
  "valid": true,
  "id": null,
  "afterDate": null
}
```

- Notes:
  - regular user can request own logs
  - admin can request another user by `id`
- Response:

```json
{
  "logs": [
    {
      "isOn": true,
      "time": "2026-04-25T10:00:00Z"
    }
  ]
}
```

### `GET /info/statistic`

- Auth: Bearer auth token
- Response:

```json
{
  "averageTime": 4
}
```

### `GET /open/open`

- Auth: Bearer auth token
- Response:

```json
{
  "isSuccess": true
}
```

## Admin Endpoints

### `GET /info/all`

- Auth: Bearer auth token of admin
- Response:

```json
{
  "employers": [
    {
      "employer": {
        "id": "uuid",
        "isAdmin": false,
        "name": "Test",
        "surname": "Employee",
        "department": "QA",
        "email": "user@lock.local",
        "workNormMinutes": 480,
        "hasCard": true,
        "hasFinger": true
      },
      "statistic": {
        "averageTime": 4
      }
    }
  ]
}
```

### `POST /command/add`

- Auth: Bearer auth token of admin
- Headers:
  - `Content-Type: application/json`
- Body:

```json
{
  "id": null,
  "isAdmin": false,
  "name": "New",
  "surname": "User",
  "department": "Ops",
  "email": "new.user@lock.local",
  "workNormMinutes": 480,
  "hasCard": null,
  "hasFinger": null
}
```

- Response:

```json
{
  "isValid": true
}
```

### `GET /command/delete?id=<USER_UUID>`

- Auth: Bearer auth token of admin
- Example:

```http
GET /command/delete?id=6b8007fd-a365-46b6-b0dd-69fe0ec8d3c7
```

- Response:

```json
{
  "isValid": true
}
```

## Internal Attendance Analysis Endpoints

These routes must be verified through the gateway. The underlying attendance-analysis service port is an internal implementation detail, not the canonical manual API surface.

### Day Format

- `day` must use `yyyy-MM-dd`
- interpretation is UTC

### Seeded Scenario Users

- baseline window is `3`
- `2026-04-06 ... 2026-04-08` are warmup days for seeded attendance users
- `GET /internal/attendance-analysis/users/:id/results` returns `10` precomputed `signals_ready` rows for `2026-04-09 ... 2026-04-22`
- `33333333-3333-3333-3333-333333333333` on `2026-04-22`: stable-history user, expected `signals_ready`, `historyDaysUsed = 3`, `F = 0`
- `44444444-4444-4444-4444-444444444444` on `2026-04-22`: variable-start-time user, expected `signals_ready`, `sessionsCount = 2`, non-zero `stddevStartMinutes`
- `55555555-5555-5555-5555-555555555555` on `2026-04-22`: repeated-deficit user, expected `signals_ready`, `historyDaysUsed = 3`, `F = 0.6667`
- `66666666-6666-6666-6666-666666666666` on `2026-04-22`: valid early-shift user, expected `signals_ready` with empty `anomalyReasons`
- `77777777-7777-7777-7777-777777777777` on `2026-04-22`: cross-midnight session, expected `workedMinutes = 225`, `historyDaysUsed = 3`, `F = 0`
- `22222222-2222-2222-2222-222222222222` on `2026-04-22`: seeded regular user, expected `workedMinutes = 485`, `historyDaysUsed = 3`

### Persistence Note

- `GET /internal/attendance-analysis/users/:id/observations*` reads already persisted observation rows
- local `./infrastructure/local/start-stack.sh` automatically materializes the seeded attendance fixture on startup
- rows also appear after one of the trigger endpoints has been executed for that user/day or for all users of that day
- `GET /internal/attendance-analysis/users/:id/results` reads only persisted `signals_ready` rows and returns stored baseline/core-signal fields

### Baseline Window

- default baseline window: `3`
- configurable by `LOCKSERVER_ATTENDANCE_ANALYSIS_BASELINE_WINDOW_DAYS`

### Result Statuses

- `signals_ready`: observation exists, enough valid history exists, baseline and `Z_s`/`Z_t`/`F` were persisted
- `insufficient_history`: observation exists, but fewer than `N` previous valid days were materialized
- `technical_anomaly`: target day was materialized as broken data and excluded from signal calculation
- `not_ready`: no raw events were materialized for the requested day

### `POST /internal/attendance-analysis/observations/run`

- Base URL:
  - `http://127.0.0.1:8080`
- Auth: Bearer auth token of admin
- Headers:
  - `Content-Type: application/json`
- Body:

```json
{
  "userId": "33333333-3333-3333-3333-333333333333",
  "day": "2026-04-22"
}
```

- Response:

```json
{
  "status": "signals_ready",
  "observation": {
    "id": "uuid",
    "userId": "33333333-3333-3333-3333-333333333333",
    "day": "2026-04-22",
    "firstEntryTime": "2026-04-22T09:00:00Z",
    "workedMinutes": 510,
    "breakMinutes": 0,
    "sessionsCount": 1,
    "isTechnicalAnomaly": false,
    "anomalyReason": null,
    "createdAt": "2026-04-25T18:00:00Z",
    "updatedAt": "2026-04-25T18:00:00Z"
  },
  "result": {
    "id": "uuid",
    "userId": "33333333-3333-3333-3333-333333333333",
    "day": "2026-04-22",
    "status": "signals_ready",
    "observationId": "uuid",
    "historyDaysUsed": 3,
    "averageStartMinutes": 539.6667,
    "stddevStartMinutes": 1.2472,
    "stddevWorkedMinutes": 0,
    "workNormMinutes": 480,
    "zS": 8,
    "zT": 0.2672,
    "f": 0,
    "detailsJson": {
      "workNormMinutes": 480,
      "rawEventCount": 2,
      "rawEvents": [
        {
          "type": "enter",
          "time": "2026-04-22T09:00:00Z"
        },
        {
          "type": "exit",
          "time": "2026-04-22T17:30:00Z"
        }
      ],
      "sessionStartsCount": 1,
      "completedSessionsCount": 1,
      "sessionRanges": [
        {
          "start": "2026-04-22T09:00:00Z",
          "end": "2026-04-22T17:30:00Z",
          "workedMinutes": 510
        }
      ],
      "anomalyReasons": [],
      "baselineWindowDays": 3,
      "historyDaysUsed": 3,
      "baselineHistoryDays": [
        {
          "day": "2026-04-17",
          "firstEntryTime": "2026-04-17T08:58:00Z",
          "startMinutes": 538,
          "workedMinutes": 482,
          "isDeficit": false
        }
      ],
      "deficitHistoryDaysCount": 0,
      "averageStartMinutes": 539.6667,
      "stddevStartMinutes": 1.2472,
      "stddevWorkedMinutes": 0,
      "zS": 8,
      "zT": 0.2672,
      "f": 0,
      "calculationNotes": [
        "z_s_used_zero_variance_cap"
      ]
    },
    "createdAt": "2026-04-25T18:00:00Z",
    "updatedAt": "2026-04-25T18:00:00Z"
  },
  "wasRebuilt": false
}
```

- Notes:
  - builds an observation for one `userId + day`
  - does not overwrite an already persisted row for the same `userId + day`
  - if the row already exists, returns the stored observation/result with `"wasRebuilt": false`

### `POST /internal/attendance-analysis/observations/rebuild`

- Same request body as `/observations/run`
- Auth: Bearer auth token of admin
- Recomputes and overwrites the stored day result for the same `userId + day`

### `POST /internal/attendance-analysis/observations/run-all`

- Base URL:
  - `http://127.0.0.1:8080`
- Auth: Bearer auth token of admin
- Headers:
  - `Content-Type: application/json`
- Body:

```json
{
  "day": "2026-04-22"
}
```

- Notes:
  - builds observations for all directory users for the requested day
  - only `day` is supplied; user ids are discovered internally
  - does not overwrite already persisted rows for users that already have an observation/result for that day

### `POST /internal/attendance-analysis/observations/rebuild-all`

- Base URL:
  - `http://127.0.0.1:8080`
- Auth: Bearer auth token of admin
- Headers:
  - `Content-Type: application/json`
- Body:

```json
{
  "day": "2026-04-22"
}
```

- Notes:
  - rebuilds observations for all directory users for the requested day
  - for `2026-04-22`, this includes the seeded user `22222222-2222-2222-2222-222222222222`
  - overwrites already persisted rows for that day across all directory users

### `GET /internal/attendance-analysis/users/:id/observations`

- Base URL:
  - `http://127.0.0.1:8080`
- Auth: Bearer auth token
- Access rule:
  - admin can request any user
  - regular user can request only own user id
- Response:

```json
{
  "observations": [
    {
      "id": "uuid",
      "userId": "33333333-3333-3333-3333-333333333333",
      "day": "2026-04-22",
      "firstEntryTime": "2026-04-22T09:00:00Z",
      "workedMinutes": 510,
      "breakMinutes": 0,
      "sessionsCount": 1,
      "isTechnicalAnomaly": false,
      "anomalyReason": null,
      "createdAt": "2026-04-25T18:00:00Z",
      "updatedAt": "2026-04-25T18:00:00Z"
    }
  ]
}
```

### `GET /internal/attendance-analysis/users/:id/observations/:day`

- Base URL:
  - `http://127.0.0.1:8080`
- Auth: Bearer auth token
- Access rule:
  - admin can request any user
  - regular user can request only own user id
- Example:

```http
GET /internal/attendance-analysis/users/33333333-3333-3333-3333-333333333333/observations/2026-04-22
```

### `GET /internal/attendance-analysis/users/:id/results`

- Base URL:
  - `http://127.0.0.1:8080`
- Auth: Bearer auth token
- Access rule:
  - admin can request any user
  - regular user can request only own user id
- Response:

```json
{
  "results": [
    {
      "id": "uuid",
      "userId": "33333333-3333-3333-3333-333333333333",
      "day": "2026-04-22",
      "status": "signals_ready",
      "observationId": "uuid",
      "historyDaysUsed": 3,
      "averageStartMinutes": 539.6667,
      "stddevStartMinutes": 1.2472,
      "stddevWorkedMinutes": 0,
      "workNormMinutes": 480,
      "zS": 8,
      "zT": 0.2672,
      "f": 0,
      "detailsJson": {
        "baselineWindowDays": 3,
        "historyDaysUsed": 3,
        "deficitHistoryDaysCount": 0,
        "baselineHistoryDays": [
          {
            "day": "2026-04-17",
            "firstEntryTime": "2026-04-17T08:58:00Z",
            "startMinutes": 538,
            "workedMinutes": 482,
            "isDeficit": false
          }
        ],
        "calculationNotes": [
          "z_s_used_zero_variance_cap"
        ]
      },
      "createdAt": "2026-04-26T10:34:32Z",
      "updatedAt": "2026-04-26T10:34:32Z"
    }
  ]
}
```

### Auxiliary Internal Raw Logs Endpoint

`attendance-analysis-service` reads raw access events internally through:

```http
GET http://127.0.0.1:8083/internal/access/users/:id/logs
```

This raw-log route is service-to-service infrastructure. It is not part of the manual verification surface and should not be treated as a canonical user-facing endpoint.

## Quick Postman Order

1. `GET /validate`
2. `GET /auth/getToken` with Basic Auth
3. `GET /info/`
4. `GET /info/statistic`
5. `POST /info/logs`
6. `GET /open/open`
7. `GET /verifier/verifyCard?code=E28E892A`
8. `GET /verifier/verifyFinger?code=1`
9. `GET /info/all` as admin
10. `POST /command/add` as admin
11. `GET /command/delete?id=...` as admin
12. `POST http://127.0.0.1:8080/internal/attendance-analysis/observations/rebuild`
13. `POST http://127.0.0.1:8080/internal/attendance-analysis/observations/rebuild-all`
14. `GET http://127.0.0.1:8080/internal/attendance-analysis/users/:id/observations/:day`
15. `GET http://127.0.0.1:8080/internal/attendance-analysis/users/:id/results`
