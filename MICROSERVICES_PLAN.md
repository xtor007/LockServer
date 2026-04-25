# Microservices Plan

## Goal

Split the current `LockServer` monolith into domain services without introducing a generic "database service". The structure must stay flexible for future attendance analytics services, but analytics itself is out of scope for the first split.

## Core Principles

- Keep the external contract stable for existing clients.
- Preserve current routes documented in [ENDPOINTS.md](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/ENDPOINTS.md).
- Do not build a shared CRUD-style `db-service`.
- Each service owns its own data and business rules.
- Isolate Arduino and hardware/network instability behind a dedicated device-facing service.
- Publish domain events so future analytics services can consume them without reading operational databases directly.

## Proposed Services

### 1. `api-gateway`

Responsibilities:

- Single external entry point for `LockApp`, Postman, and future web/admin clients.
- Preserve the current public API shape.
- Route requests to internal services.
- Compose responses when a client-facing endpoint needs data from more than one internal service.

Current monolith areas related to this responsibility:

- [Sources/App/routes.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/routes.swift)
- [Sources/App/configure.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/configure.swift)
- route enums under `Sources/App/Controllers/*/Routes`

External routes to preserve at gateway:

- `GET /`
- `GET /validate`
- `GET /auth/getToken`
- `GET /auth/refresh`
- `POST /auth/changePasswordEmail`
- `POST /auth/changePassword`
- `GET /info/`
- `POST /info/logs`
- `GET /info/statistic`
- `GET /info/all`
- `GET /open/open`
- `GET /command/delete`
- `POST /command/add`
- `GET /verifier/verifyCard`
- `GET /verifier/verifyFinger`

Notes:

- `api-gateway` should be the only service exposed to clients in normal operation.
- Gateway should not own business data.

### 2. `auth-service`

Responsibilities:

- Login via Basic Auth.
- Auth token and refresh token issuing.
- Password change flow.
- Password reset code workflow.
- Auth-related email dispatch, or integration with a notification adapter.

Current monolith files that map here:

- [Sources/App/Controllers/Auth/AuthController.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Controllers/Auth/AuthController.swift)
- [Sources/App/Controllers/Auth/Authenticator/AuthTokenAuthenticator.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Controllers/Auth/Authenticator/AuthTokenAuthenticator.swift)
- [Sources/App/Controllers/Auth/Authenticator/RefreshTokenAuthenticator.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Controllers/Auth/Authenticator/RefreshTokenAuthenticator.swift)
- [Sources/App/Controllers/Auth/Authenticator/EmployerBasicAuthenticator.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Controllers/Auth/Authenticator/EmployerBasicAuthenticator.swift)
- [Sources/App/Controllers/Auth/Authenticator/ChangePasswordAuthenticator.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Controllers/Auth/Authenticator/ChangePasswordAuthenticator.swift)
- [Sources/App/Controllers/Auth/Constants/AuthConstants.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Controllers/Auth/Constants/AuthConstants.swift)
- [Sources/App/Managers/ChangePassword/ChangePasswordManager.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/ChangePassword/ChangePasswordManager.swift)
- [Sources/App/Managers/Mail/MailManager.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/Mail/MailManager.swift)
- [Sources/App/Managers/Mail/SMTP/SMTPManager.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/Mail/SMTP/SMTPManager.swift)

Data ownership recommendation:

- Own auth settings and auth-related projections needed for login.
- Do not depend on direct reads from another service database.
- If employee credentials remain stored with employee records at first, move toward an auth-owned projection fed by events.

### 3. `directory-service`

Responsibilities:

- Employee directory.
- Employee lifecycle: create/delete.
- Card assignment state.
- Finger assignment state.
- Employee metadata such as name, surname, department, email, admin flag.

Current monolith files that map here:

- [Sources/App/Controllers/Command/CommantController.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Controllers/Command/CommantController.swift)
- [Sources/App/Controllers/Info/Model/Response/EmployerModel.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Controllers/Info/Model/Response/EmployerModel.swift)
- [Sources/App/Managers/DB/DBManager.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/DB/DBManager.swift)
- [Sources/App/Managers/DB/MySQL/Model/Employer.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/DB/MySQL/Model/Employer.swift)
- [Sources/App/Managers/DB/MySQL/Model/Card.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/DB/MySQL/Model/Card.swift)
- [Sources/App/Managers/DB/MySQL/Model/Finger.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/DB/MySQL/Model/Finger.swift)
- [Sources/App/Managers/DB/MySQL/Migrations/CreateEmployer.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/DB/MySQL/Migrations/CreateEmployer.swift)
- [Sources/App/Managers/DB/MySQL/Migrations/CreateCard.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/DB/MySQL/Migrations/CreateCard.swift)
- [Sources/App/Managers/DB/MySQL/Migrations/CreateFinger.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/DB/MySQL/Migrations/CreateFinger.swift)

Data ownership:

- `Employers`
- `Cards`
- `Fingers`

Notes:

- `directory-service` should answer questions like:
  - who is this employee
  - does this employee have card/finger assigned
  - create/remove employee
- It should not decide whether a door should open. That belongs to `access-service`.

### 4. `access-service`

Responsibilities:

- Access decision logic.
- Open command orchestration from app/API perspective.
- Card verification flow.
- Finger verification flow.
- Access event journal.
- Operational attendance/log view used by current product.
- Current basic statistics until analytics services exist later.

Current monolith files that map here:

- [Sources/App/Controllers/Open/OpenController.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Controllers/Open/OpenController.swift)
- [Sources/App/Controllers/KeyVerifier/KeyVerifierController.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Controllers/KeyVerifier/KeyVerifierController.swift)
- [Sources/App/Controllers/Info/InfoController.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Controllers/Info/InfoController.swift)
- [Sources/App/Controllers/Open/Model/OpeningResult.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Controllers/Open/Model/OpeningResult.swift)
- [Sources/App/Controllers/Info/Model/Request/GetLogsRequest.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Controllers/Info/Model/Request/GetLogsRequest.swift)
- [Sources/App/Controllers/Info/Model/Response/EnterModel.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Controllers/Info/Model/Response/EnterModel.swift)
- [Sources/App/Controllers/Info/Model/Response/Statistic.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Controllers/Info/Model/Response/Statistic.swift)
- [Sources/App/Controllers/Info/Model/Response/EmployerWithStatistic.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Controllers/Info/Model/Response/EmployerWithStatistic.swift)
- [Sources/App/Managers/Verifier/CardCodeVerifier.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/Verifier/CardCodeVerifier.swift)
- [Sources/App/Managers/Verifier/FingerVerifier.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/Verifier/FingerVerifier.swift)
- [Sources/App/Managers/Statistic/StatisticManager.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/Statistic/StatisticManager.swift)
- [Sources/App/Managers/DB/MySQL/Model/Enter.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/DB/MySQL/Model/Enter.swift)
- [Sources/App/Managers/DB/MySQL/Migrations/CreateEnter.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/DB/MySQL/Migrations/CreateEnter.swift)

Data ownership:

- `Enters`
- access decision log / audit stream

Notes:

- `access-service` should ask `directory-service` about credentials and employee state.
- `access-service` should ask `device-service` to execute the physical open request.
- Future attendance analytics services should consume `access` events rather than reading this database directly.

### 5. `device-service`

Responsibilities:

- Isolate Arduino-specific integration.
- Open command transport to hardware.
- Device availability checks, retries, timeouts, response normalization.
- Mock mode for local development without hardware.

Current monolith files that map here:

- [Sources/App/Managers/Arduino/ArduinoManager.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/Arduino/ArduinoManager.swift)
- [Sources/App/Managers/Arduino/Constants/ArduinoConstants.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/Arduino/Constants/ArduinoConstants.swift)
- [Sources/App/Managers/Arduino/Model/ArduinoResponse.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/Arduino/Model/ArduinoResponse.swift)
- [Sources/App/Managers/Network/NetworkManager.swift](/Users/khramchenko/Desktop/кпи/diplom/code/LockServer/Sources/App/Managers/Network/NetworkManager.swift)

Notes:

- Device service should hide the exact Arduino protocol from the rest of the system.
- Current `LOCKSERVER_MOCK_ARDUINO=1` behavior should evolve into an explicit local/dev mode for this service.

## Future Analytics Readiness

Analytics services are not part of the first split, but the architecture should support them. To prepare for that:

- `access-service` must publish versioned access events.
- `directory-service` should publish employee and credential events.
- Analytics must not read operational tables directly as their primary integration path.
- Keep all times in UTC in events and storage.

Suggested future event names:

- `employee.created`
- `employee.deleted`
- `credential.card.assigned`
- `credential.finger.assigned`
- `access.requested`
- `access.granted`
- `access.denied`
- `door.open.requested`
- `door.opened`
- `device.online`
- `device.offline`

## Data Ownership Rule

This is the most important architecture rule:

- no single shared `db-service`
- no direct cross-service table access
- each service owns its schema
- inter-service communication happens via API calls or domain events

## Migration Direction

Recommended migration order:

1. Extract `device-service`.
2. Extract `auth-service`.
3. Extract `directory-service`.
4. Extract `access-service`.
5. Put `api-gateway` in front and preserve the current external routes.

This order keeps the hardware boundary isolated early and makes the later split of business logic cleaner.
