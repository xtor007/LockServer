# Microservices Plan

## Goal

Keep the existing external API stable while running the backend as explicit domain services behind a gateway.

## Implemented Layout

- `contracts/`
- `shared/`
- `services/api-gateway/`
- `services/auth-service/`
- `services/directory-service/`
- `services/access-service/`
- `services/device-service/`
- `infrastructure/local/`

## Service Responsibilities

### `api-gateway`

- public entry point on port `8080`
- preserves all routes from `ENDPOINTS.md`
- proxies auth routes to `auth-service`
- proxies user/access routes to `access-service`
- coordinates `command/add` and `command/delete` across multiple services

### `auth-service`

- owns login and refresh token issuing
- owns password reset/change flow
- owns welcome/reset email dispatch adapters
- owns `auth_users`
- exposes internal token introspection for the gateway

### `directory-service`

- owns employee directory data
- owns card and finger assignments
- owns `directory_employers`, `directory_cards`, `directory_fingers`
- exposes internal lookup endpoints for access decisions

### `access-service`

- owns access logs and simple attendance/statistic behavior
- owns `access_enters`
- serves `info/*`, `open/open`, and verifier logic behind the gateway
- calls `directory-service` for employee/credential lookup
- calls `device-service` for actual open requests

### `device-service`

- isolates Arduino transport
- supports local mock mode without hardware
- exposes an internal open endpoint used by `access-service`

## Synchronous Calls

The implemented synchronous paths are:

- `api-gateway -> auth-service`
- `api-gateway -> directory-service`
- `api-gateway -> access-service`
- `access-service -> directory-service`
- `access-service -> device-service`

## Event Contracts

Versioned JSONL events are written to:

`$LOCKSERVER_EVENTS_DIR`

Current emitted names:

- `employee.created`
- `employee.deleted`
- `access.granted`
- `access.denied`
- `door.open.requested`
- `door.opened`
- `device.online`
- `device.offline`

These events are intentionally versioned from the start so future analytics consumers can subscribe without reading operational tables directly.

## Data Ownership Rule

- no shared CRUD-style `db-service`
- no direct cross-service table reads
- one MySQL instance is reused only as infrastructure
- table ownership is explicit per domain service

## Local Development

The reference local workflow is:

```bash
env HOME=/tmp/codex-home CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift build
./infrastructure/local/start-stack.sh
./infrastructure/local/verify-endpoints.sh
./infrastructure/local/stop-stack.sh
```

`start-stack.sh` is a long-running process and should stay open while the stack is in use.

Mock device mode is enabled by default in `infrastructure/local/.env.example`.
