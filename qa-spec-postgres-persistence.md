# QA Spec: PostgreSQL Persistence for Contract Analysis Results

**Feature:** postgres-persistence
**Spec Author:** QA Spec (obsidian polecat)
**Date:** 2026-03-01
**Status:** READY FOR REVIEW

---

## Scope

Add PostgreSQL persistence so that each `/analyze` call stores:
- `document_analyses` table: id (UUIDv7, PK), document_text, summary, language, jurisdiction, created_at
- `findings` table: id (UUIDv7, PK), analysis_id (FK), sentence, issue, suggestion, severity

New deliverables: SQLAlchemy models, Alembic migrations, repository layer, docker-compose postgres service, minor integration in `ContractAnalyzer`.

---

## Definition of Ready (DoR)

Implementation MUST NOT start until ALL of the following are true:

1. **Database connectivity spec confirmed**: The env var name for the DB connection string is agreed upon (e.g., `DATABASE_URL`), and its format (DSN) is documented.
2. **Async driver decision made**: The async postgres driver (asyncpg vs psycopg2 in async mode vs psycopg3) is chosen and confirmed compatible with the FastAPI async runtime.
3. **UUIDv7 library selected**: A Python uuid7 library is identified and confirmed installable (e.g., `uuid7`, `uuid-utils`, or stdlib if available). Version pinned.
4. **Migration environment agreed**: Alembic will target the same database as the app (not a separate migration-only DB). The migration command is documented.
5. **Docker Compose port agreed**: The postgres service port mapping is specified to avoid conflict with existing local postgres (default 5432 may conflict).
6. **Persistence failure behavior decided**: One of the following is explicitly chosen (not both):
   - (A) Persistence failure returns HTTP 503 — analysis is not returned.
   - (B) Persistence failure is fire-and-forget — analysis is returned, failure is logged.
7. **ON DELETE behavior for findings FK decided**: Either `CASCADE` (delete findings when document_analyses row is deleted) or `RESTRICT` (prevent deletion of document_analyses if findings exist).
8. **Existing tests pass on main**: No pre-existing test failures on `main` that would mask regressions.

---

## Definition of Done (DoD)

The feature is CLOSED only when ALL of the following are true:

### Schema
- [ ] `document_analyses` table exists with columns: `id` (UUIDv7, PK, indexed), `document_text` (text, NOT NULL), `summary` (text), `language` (varchar), `jurisdiction` (varchar), `created_at` (timestamptz, default NOW()).
- [ ] `findings` table exists with columns: `id` (UUIDv7, PK, indexed), `analysis_id` (FK → `document_analyses.id`, indexed, NOT NULL), `sentence` (text), `issue` (text), `suggestion` (text), `severity` (varchar constrained to `high|medium|low`).
- [ ] `analysis_id` index exists in `findings` (separate from FK constraint).

### Migrations
- [ ] Alembic migration scripts exist and run cleanly on a fresh empty database (`alembic upgrade head` succeeds with no errors).
- [ ] `alembic downgrade -1` from the initial migration leaves the database in a clean state (rollback is safe).

### Docker Compose
- [ ] `docker-compose.yml` (or `docker-compose.override.yml`) includes a `postgres` service with healthcheck.
- [ ] The app service declares a dependency on postgres (waits for healthy).
- [ ] A `.env.example` (or equivalent) documents the `DATABASE_URL` variable.

### Integration
- [ ] After every successful `/analyze` call, one row is written to `document_analyses` and N rows to `findings` (N = number of findings returned in the response, after `max_findings` cap).
- [ ] The API response schema is unchanged — `AnalyzeResponse` is identical to pre-feature behavior.
- [ ] `document_text` stored equals the full extracted text (before any truncation applied to the LLM, i.e., the value passed into `analyze(text)`).
- [ ] Persistence behavior on failure matches the DoR decision (A or B).

### Code Quality
- [ ] Repository layer is separate from `analyzer_service.py` (single-responsibility).
- [ ] No raw SQL in the repository layer — SQLAlchemy ORM or Core query builders used.
- [ ] DB session lifecycle is managed correctly (no leaked connections).
- [ ] Dependencies (`sqlalchemy`, `alembic`, chosen async driver, `uuid7`) are added to `pyproject.toml`.

### Tests
- [ ] Unit tests exist for the repository layer (see test sketches below).
- [ ] All pre-existing tests (if any) still pass.
- [ ] Tests can run without a live postgres instance (mocked or in-memory SQLite where possible, or clearly documented postgres requirement for integration tests).

---

## Acceptance Criteria

### AC-1: Successful analysis persists document and findings

**Given** a running postgres instance and a valid contract file
**When** `POST /analyze` completes successfully
**Then**:
- Exactly one row exists in `document_analyses` matching the returned `language`, `jurisdiction`, and `summary`
- The stored `document_text` equals the full extracted text from the file
- Exactly N rows exist in `findings` where N = `len(response.report.findings)`
- Each finding row's `sentence`, `issue`, `suggestion`, `severity` match the corresponding response finding

### AC-2: Schema correctness via migration

**Given** an empty postgres database
**When** `alembic upgrade head` is run
**Then** both tables exist with the exact schema specified (verified via `\d document_analyses` and `\d findings`)

### AC-3: severity constraint enforced

**Given** a finding with severity not in `{high, medium, low}`
**When** it is persisted
**Then** either:
- The application normalizes it to `medium` (consistent with existing `normalize_finding` behavior) before insert, OR
- The DB rejects it with a constraint violation and the behavior matches the DoR failure-mode decision

The behavior must be one or the other — not silently storing an invalid value.

### AC-4: Persistence failure behavior is explicit and tested

**Given** the database is unreachable
**When** `POST /analyze` is called
**Then** the response matches the DoR decision (AC-4A or AC-4B):
- **AC-4A** (fail-fast): Returns HTTP 503 with a clear error message; analysis is NOT returned
- **AC-4B** (fire-and-forget): Returns HTTP 200 with the analysis; failure is logged at ERROR level

### AC-5: API response schema unchanged

**Given** the persistence feature is deployed
**When** `POST /analyze` is called
**Then** the JSON response structure is identical to the pre-feature `AnalyzeResponse` — no added or removed fields

### AC-6: Transactional atomicity

**Given** a successful analysis with N findings
**When** the persistence transaction commits
**Then** either all N+1 rows (1 document_analyses + N findings) are present, OR none are (no partial writes)

### AC-7: UUIDv7 monotonicity

**Given** two sequential analysis calls
**When** `document_analyses` rows are queried `ORDER BY id`
**Then** they appear in creation order (UUIDv7 encodes timestamp, enabling time-ordered sorting)

### AC-8: Docker Compose starts clean

**Given** a fresh checkout with no `.env` beyond the example
**When** `docker-compose up` is run
**Then** postgres starts healthy and the app connects successfully on first request

---

## Edge Cases and Boundary Conditions

| ID | Scenario | Expected Behavior |
|----|----------|-------------------|
| EC-1 | Analysis returns 0 findings | One `document_analyses` row is inserted; zero `findings` rows. No error. |
| EC-2 | Analysis returns exactly `max_findings` findings | All `max_findings` rows are inserted (cap is applied before persistence, not after). |
| EC-3 | `document_text` is at max length (150,000 chars) | Stored without truncation. Postgres `text` is unbounded — no silent data loss. |
| EC-4 | Two concurrent `/analyze` requests for the same document | Two independent `document_analyses` rows with distinct UUIDv7 ids. No race condition or duplicate key error. |
| EC-5 | Same document submitted twice sequentially | Two rows in `document_analyses` — identical content, distinct ids. No deduplication (not in scope). |
| EC-6 | Database not reachable at app startup | App fails to start with a clear error (or defers connection and fails on first use — behavior must be documented). |
| EC-7 | Database goes away mid-operation | Transaction fails; behavior matches AC-4A or AC-4B. Connection pool recovers on next request. |
| EC-8 | `severity` value arrives as uppercase (`"HIGH"`) | Normalized to lowercase before insert (consistent with existing `normalize_finding`). |
| EC-9 | `findings` FK with `ON DELETE CASCADE` | Deleting a `document_analyses` row also deletes its `findings` rows. |
| EC-9' | `findings` FK with `ON DELETE RESTRICT` | Deleting a `document_analyses` row is rejected if findings exist. |
| EC-10 | Migration run twice on same database | `alembic upgrade head` is idempotent — second run is a no-op, no errors. |
| EC-11 | `document_text` contains non-ASCII/Unicode characters | Stored correctly (postgres `text` is UTF-8; driver must use UTF-8 encoding). |

---

## Unit Test Sketches

These describe WHAT must be tested, not HOW to implement the tests.

### Test 1: `test_repository_save_analysis`
- **Arrange**: Mock DB session; `AnalyzeReport` with `language="English"`, `jurisdiction="US"`, `summary="..."`, 2 findings
- **Act**: Call `repository.save(document_text="some contract", report=report)`
- **Assert**:
  - DB session received exactly 1 `document_analyses` insert with correct field values
  - DB session received exactly 2 `findings` inserts, each with the correct `analysis_id` matching the inserted `document_analyses.id`
  - Transaction was committed

### Test 2: `test_repository_save_empty_findings`
- **Arrange**: Mock DB session; `AnalyzeReport` with 0 findings
- **Act**: `repository.save("text", report)`
- **Assert**: 1 `document_analyses` insert, 0 `findings` inserts, transaction committed

### Test 3: `test_severity_stored_lowercase`
- **Arrange**: Finding with `severity="HIGH"` (uppercase)
- **Act**: `repository.save(...)` with that finding
- **Assert**: The `severity` value passed to the DB insert is `"high"` (lowercase)

### Test 4: `test_transaction_atomicity_on_findings_failure`
- **Arrange**: Mock DB session that raises `SQLAlchemyError` on the second insert (first findings row)
- **Act**: `repository.save(...)` with 2 findings
- **Assert**: Transaction is rolled back; no `document_analyses` row persisted

### Test 5: `test_uuid7_ids_are_time_ordered`
- **Arrange**: Generate two UUIDv7 ids in sequence with a small delay
- **Assert**: `id1 < id2` when compared lexicographically (UUIDv7 monotonicity)

### Test 6: `test_persistence_failure_does_not_affect_response` (if AC-4B chosen)
- **Arrange**: Repository that raises on save; `ContractAnalyzer` integrated with it
- **Act**: Call `analyzer.analyze(text)`
- **Assert**: Returns valid `AnalyzeReport`; failure is logged at ERROR level; no exception propagated

### Test 7: `test_persistence_failure_returns_503` (if AC-4A chosen)
- **Arrange**: Repository that raises on save; full API test client
- **Act**: `POST /analyze` with valid file
- **Assert**: Response status is 503; body contains error detail

### Test 8: `test_api_response_schema_unchanged`
- **Arrange**: Working postgres; valid contract file
- **Act**: `POST /analyze`
- **Assert**: Response JSON has exactly the fields: `filename`, `report.language`, `report.jurisdiction`, `report.summary`, `report.findings[].sentence`, `report.findings[].issue`, `report.findings[].suggestion`, `report.findings[].severity` — no extra fields

### Test 9: `test_migration_idempotent`
- **Arrange**: Apply migration to test DB
- **Act**: Run `alembic upgrade head` a second time
- **Assert**: Exits 0, no errors, tables still have correct schema

---

## Open Questions (must be resolved before DoR is met)

1. **Failure mode**: AC-4A (503) or AC-4B (fire-and-forget)? Who decides — architect?
2. **FK on delete**: CASCADE or RESTRICT on `findings.analysis_id`?
3. **DB URL env var name**: `DATABASE_URL`? `POSTGRES_DSN`?
4. **Async driver**: `asyncpg` (recommended for async FastAPI) or `psycopg2` (sync, requires thread pool)?
5. **App startup behavior when DB is unavailable**: Fail fast or lazy connect?

---

*This spec defines acceptance conditions only. Implementation approach is left to the implementer.*
