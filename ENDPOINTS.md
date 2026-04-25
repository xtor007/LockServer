# LockServer Endpoints

## Base URL

- Gateway: `http://127.0.0.1:8080`

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
