# Simple Contract Checker — Technical Assessment

A lightweight FastAPI service that analyzes legal contracts for vague or ambiguous clauses using a two-agent LLM pipeline. Built as a base app to demonstrate multi-agent orchestration with AI-driven development workflows.

---

## Context

This project was built as part of a technical assessment focused on **multi-agent AI orchestration**.

The starting point was an intentionally simple contract analysis app with **no persistence layer** — results were returned directly to the caller and discarded. The goal: add a full PostgreSQL persistence layer (Docker Compose + SQLAlchemy + Alembic) through a structured, AI-driven development workflow, without writing the implementation manually.

---

## What the app does

`POST /analyze` accepts a `.pdf`, `.docx`, or `.txt` contract file and runs it through a sequential two-agent pipeline:

```
File upload → text extraction → Agent 1 → Agent 2 → JSON report
```

| Agent | Responsibility | Output |
|-------|---------------|--------|
| **Agent 1** | Detects document language and legal jurisdiction | `language`, `jurisdiction` |
| **Agent 2** | Finds vague/ambiguous sentences and rewrites them | `findings[]`, `summary` |

Each finding returned by Agent 2 has the following shape:

```json
{
  "sentence": "exact sentence from document",
  "issue": "why it is vague/ambiguous",
  "suggestion": "clear rewrite suggestion",
  "severity": "high|medium|low"
}
```

The full response also includes `language`, `jurisdiction`, `summary`, and the original `filename`.

When no `OPENAI_API_KEY` is set the app falls back to deterministic heuristics (keyword matching), so it runs entirely offline for testing.

---

## Project structure

```
app.py                          FastAPI entry point
controllers/analyze_controller  POST /analyze endpoint
services/
  parser_service.py             Text extraction (pdf, docx, txt)
  analyzer_service.py           Two-agent LLM pipeline + heuristic fallback
models/schemas.py               Pydantic models (Finding, AnalyzeReport, …)
core/config.py                  Settings via pydantic-settings / .env
crew-governance.md              AI workflow specification (see below)
initial_project.md              Original project brief
```

---

## Stack

- **FastAPI** + **Uvicorn** — HTTP layer
- **OpenAI SDK** (`gpt-4.1-mini`, `temperature=0`) — LLM agents
- **pdfplumber** / **python-docx** — document parsing
- **pydantic-settings** — typed config from `.env`
- **uv** — dependency management

---

## Running locally

```bash
uv sync
cp .env.example .env          # add OPENAI_API_KEY if desired
uv run uvicorn app:app --reload --port 8003
```

API docs available at:
- Swagger UI: `http://localhost:8003/docs`
- ReDoc: `http://localhost:8003/redoc`

Example request:

```bash
curl -X POST "http://localhost:8003/analyze" \
  -F "file=@contract.pdf"
```

---

## Gas Town workspace structure

The project lives inside a Gas Town workspace. The relevant directory hierarchy is:

```
<gt-root>/
  mayor/
    rigs.json                   Registry of all rigs in this workspace
  contract_checker/             Rig (project container)
    crew/
      gov/                      Crew member workspace
        state.json              Crew identity (rig + name, read by governance scripts)
        .claude/
          settings.json         SessionStart hook — auto-heals governance commands
          commands/
            crew-bugfix.md      /crew-bugfix  slash command
            crew-feature.md     /crew-feature slash command
            crew-risky.md       /crew-risky   slash command
```

The rig (`contract_checker`) is the project boundary. The crew member (`gov`) is the persistent orchestrator that lives inside it and manages all convoys. Polecats are ephemeral — they are spawned per bead, do their work, report back, and terminate.

---

## How the persistence feature was added — AI-driven orchestration

The persistence layer (PostgreSQL + SQLAlchemy + Alembic, two tables with UUIDv7 primary keys) was **not written manually**. It was delivered by an AI crew member following a structured multi-agent workflow defined in [`crew-governance.md`](./crew-governance.md).

### The workflow system

[`crew-governance.md`](./crew-governance.md) is the full specification — it documents the three convoy types, every gate, the two-tier escalation model, and the complete role description for each polecat specialist.

The file defines three slash commands that crew members (persistent AI orchestrators running in Claude Code) use to dispatch ephemeral worker agents (polecats) for any change:

| Command | When to use | Convoy type |
|---------|------------|-------------|
| `/crew-bugfix` | Confirmed bug, narrow scope | `convoy-hotfix` |
| `/crew-feature` | New functionality, localized scope | `convoy-feature` |
| `/crew-risky` | Structural/breaking/cross-system change | `convoy-governance` |

Each convoy type enforces a specific gate sequence. For a new feature (`/crew-feature`), the flow is:

```
qa-spec ─┐
          ├──→ design-critique → implement → validate → continuity
arch    ──┘
```

No code is written until the design-critique gate is **CLEAR**. See [`crew-governance.md → Polecat role reference`](./crew-governance.md#polecat-role-reference) for the full responsibility, output, and constraint spec for each specialist role (QA Spec, Architect, Critic, Implementer, Test Runner, DevOps, Librarian).

### Workflow design

**Task decomposition:**

The feature was broken into six sequential steps, with parallelism where dependencies allowed:

```
qa-spec ─┐
          ├──→ design-critique → [docker · models · migrations · repo · wiring] → test → continuity
arch    ──┘
                                └────────────── parallel implementers ──────────┘
```

| Step | Polecat | Runs after |
|------|---------|-----------|
| qa-specification | QA Spec | convoy creation |
| architecture-framing | Architect | convoy creation (parallel with QA) |
| design-critique | Critic | both QA + arch complete |
| implementation × 5 | Implementers | design-critique CLEAR |
| validation | Test Runner | all implementers done |
| continuity | Librarian | validation passes |

**Reasoning behind this decomposition:**

The split between QA Spec and Architect running in parallel (rather than sequentially) was deliberate: both are research/planning tasks with no shared output — they can proceed independently and converge at the design-critique gate. This cuts one full round-trip from the critical path.

The five Implementer sub-tasks (docker-compose setup, ORM models, Alembic migration, repository layer, controller wiring) were made independent by defining clear file-level boundaries in the architecture step: each implementer owned a distinct set of files and could not touch files outside its scope without notifying the crew member first. This meant all five ran in parallel without coordination overhead between them.

The design-critique gate before any implementation is the key discipline mechanism: it prevents polecats from building on a flawed architecture and then having to undo committed code. The gate is cheap (one polecat, no code written) and the cost of skipping it is high (rework after commits).

### Coordination strategy

**Agent assignment approach:**

The crew member (`gov`) never implements — it dispatches and gates. Each bead gets exactly one polecat whose role is defined by the step name (`qa-specification`, `architecture-framing`, etc.). The crew member reads the polecat's output from the bead and either advances the convoy or routes it back (e.g., BLOCKED design-critique goes back to arch, not to Mayor).

**Sequencing and dependencies:**

- QA Spec and Architect have no dependency on each other → dispatched in parallel
- design-critique depends on both → hard gate, crew member manually reviews before unblocking
- Implementers have no dependency on each other (file-boundary isolation enforced by arch) → dispatched in parallel
- Test Runner depends on all Implementers → crew member waits for all completion confirmations before unblocking
- Librarian depends on Test Runner PASS → only opens after crew member reviews validation evidence

### The prompt sent to the crew member

Adding the persistence layer was triggered with a single natural-language prompt:

> *"hi steve, in this project in line `services/analyzer_service.py:79` the LLM responds with those fields — `findings[]` and `summary`. I need to persist them in a PostgreSQL database. Use `/crew-feature` to create a convoy creating the docker-compose database, SQLAlchemy and Alembic for connection. There must be one table for the document (`summary`, `language`, `jurisdiction`, `sent_date`) and another relational table for the findings. Use UUIDv7 with index in both."*

The crew member then:

1. Invoked `/crew-feature` to open a `convoy-feature`
2. Dispatched **qa-spec** and **arch** polecats in parallel to produce a QA spec and architecture proposal
3. Ran **design-critique** and waited for CLEAR before any code was written
4. Dispatched parallel **Implementer** polecats — one per independent sub-task (docker-compose, models, migrations, repository layer, controller wiring)
5. Ran the **Test Runner** only after all Implementers confirmed completion
6. Closed with **continuity** (docs, migration notes)

### Key design decisions made by the crew

- Two tables: `documents` (one row per upload) and `findings` (one row per finding, FK to document)
- Both use **UUIDv7** as primary key with a B-tree index — time-ordered, globally unique, index-friendly
- **SQLAlchemy** async ORM for the repository layer; **Alembic** for versioned migrations
- **Docker Compose** brings up a `postgres:16` container; the app connects via `DATABASE_URL` in `.env`
- Alembic migration runs automatically on startup so the schema is always in sync

---

## Replicability — installing governance on any machine

The governance workflow is fully self-contained and portable. Two shell scripts ship with this repo:

| Script | Purpose |
|--------|---------|
| `install-crew-governance.sh` | Installs the three slash commands into every crew workspace in the Gas Town structure. Self-discovers the GT root by walking up the directory tree until `mayor/rigs.json` is found — no hardcoded paths. Requires `jq` or `python3`. |
| `crew-add.sh` | Wrapper around `gt crew add` that immediately installs governance on the new crew. Any crew created with this script is born with `/crew-bugfix`, `/crew-feature`, and `/crew-risky` ready to use. |

To bootstrap governance on a new machine:

```bash
# Install into all existing crews
./install-crew-governance.sh

# Install into one specific rig/crew
./install-crew-governance.sh --rig contract_checker --crew gov

# Preview without writing anything
./install-crew-governance.sh --dry-run

# Create a new crew with governance pre-installed
./crew-add.sh contract_checker researcher
```

Additionally, a `SessionStart` hook is written into each crew's `.claude/settings.json`. On every new Claude Code session it checks whether the governance command files exist and, if they are missing, re-runs the installer silently in the background. This means even a crew created by other means (`gt crew add` directly, cloning, etc.) will self-heal on its first session — governance cannot accidentally be left out.

---

## Observing the work — tmux and the Gas Town dashboard

Every polecat and crew member runs in its own Claude Code session. Gas Town surfaces these through two observation channels:

**tmux panes** — each agent session is a live terminal pane. You can attach to any pane and read the agent's reasoning, tool calls, and intermediate output in real time. During the persistence feature delivery the tmux layout showed the crew member pane alongside the parallel Implementer panes so you could watch all sub-tasks progressing simultaneously.

**Gas Town dashboard** — `gt dashboard` (or the web UI, depending on your GT version) shows the convoy graph: which beads are pending, in-progress, or complete; which polecat is assigned to each; and the mail thread between polecats and the crew member. This gives a bird's-eye view of the entire convoy without attaching to individual panes.

Together these two channels mean the work is never a black box — at any point during the feature delivery you could see exactly what every agent was doing, what decision gates had been passed, and what evidence had been produced.

---

## Fault recovery

### Potential failure points

| Failure point | What can go wrong |
|---|---|
| **LLM timeout / empty response** | A polecat calls the LLM and gets no response or a malformed JSON back. The polecat reports BLOCKED to the crew member with the raw output attached. |
| **Polecat session crash mid-implementation** | A Claude Code session dies after partial commits. The branch has partial work; the bead is still in-progress. |
| **Design-critique loops (repeated BLOCKED)** | Architect and Critic disagree and the loop doesn't converge. After two rounds with no resolution, the crew member escalates to Mayor. |
| **Implementer scope creep** | An implementer discovers a dependency outside its assigned files. If it acts without notifying, it produces conflicts with a peer implementer working in parallel. |
| **Test Runner FAIL after all implementation** | One or more tests fail. The crew member must decide: is it an implementation bug (retry one implementer) or a systemic design issue (restart from arch)? |
| **DB migration failure on startup** | Alembic migration fails at boot (e.g., DB not reachable, schema conflict). The app cannot start; error surfaces in the startup log. |
| **Crew member session restart mid-convoy** | The crew member's Claude Code session closes unexpectedly while a bead is in flight. Polecats have already sent mail; the bead state is in the durable store. |
| **Missing governance commands after clone** | A new machine clones the repo and runs `gt crew add` directly, missing the slash commands. Crew member cannot invoke `/crew-feature`. |

### Recovery approach

**Convoy state is durable** — the convoy (and all its beads) lives in Gas Town's durable store, not in any agent's memory. If a polecat crashes mid-implementation, the crew member reads the last known bead state and re-dispatches a fresh polecat to resume from that point. The work already committed to the branch is preserved.

**Mail is the interface** — polecats communicate with the crew member exclusively through `gt mail send`. Mail is persisted. If the crew member session ends unexpectedly, the next session can open its inbox and reconstruct exactly what every polecat reported and what decisions were pending.

**Crew member is the first responder** — the two-tier escalation model means that most failures (validation failures, scope questions, design-critique blocks) are handled by the crew member without stopping the convoy. Only genuinely unresolvable or cross-rig issues reach the Mayor, keeping the blast radius of any individual failure small.

**Auto-heal on session start** — the `SessionStart` hook that re-installs governance also serves as a general recovery entry point: when a crew member's session restarts after a crash it immediately re-reads its state, checks in-flight convoys, and picks up where it left off.

**Missing governance commands** — even if a crew workspace was created outside `crew-add.sh`, the `SessionStart` hook detects missing command files and silently re-runs the installer. The crew member is never permanently broken by a missing install step.

The net effect: the persistence feature could have survived a crashed polecat, a timed-out crew member, or even a machine reboot mid-convoy — the convoy graph, branch commits, and mail thread would have preserved everything needed to continue.

---

## Two-tier escalation model

The governance system uses a two-tier escalation model. Polecats report to the crew member first — the crew member handles what they can (re-route a failing design back to arch, assess a test failure, contain a scope creep). They escalate to the **Mayor** (top-level orchestrator) only when something crosses rig boundaries or is unresolvable.

This kept the entire persistence feature delivery contained within a single crew member session with no Mayor interruptions.

---

## Production improvements

Things that would be added before running this workflow in a production engineering team:

**Convoy formula library** — the current governance uses ad-hoc `bd mol pour --formula convoy-feature` calls with inline variable definitions. A production setup would have a versioned library of named formulas (e.g., `convoy-db-migration`, `convoy-api-endpoint`) with pre-defined bead templates, required variable schemas, and default polecat assignments. This removes ambiguity when a new crew member picks the wrong formula.

**Automated gate enforcement** — the design-critique gate is currently enforced by the crew member's prompt instructions ("do not allow implementation before CLEAR"). In production this would be a hard system-level gate: the convoy runner refuses to open the implementation bead unless the critique bead is in state `CLEAR`, making it physically impossible to bypass.

**Polecat output schemas** — today polecats report back in natural language via mail. In production, each polecat role would produce a structured JSON artifact (QA Spec → `qa-spec.json`, Architect → `arch.json`, Test Runner → `test-report.json`) stored as bead attachments. The crew member and downstream polecats read structured data, not prose — reducing misinterpretation and enabling automated validation.

**Retry policies per bead** — currently a failed polecat requires manual crew member intervention. Production convoys would have configurable retry limits per bead type (e.g., Implementer: 1 retry before crew member review; Test Runner: 0 retries, always escalate). This prevents infinite retry loops while still automating the common case.

**Observability integration** — beyond tmux and the GT dashboard, production convoys would emit structured events (bead state transitions, gate decisions, escalations) to an external system (e.g., Datadog, OpenTelemetry) for cross-convoy analytics: how often does design-critique block? Which sub-tasks fail most in validation? Which convoy types take longest?

**Cross-rig convoy support** — the current workflow is contained to a single rig (`contract_checker`). A production multi-service system would need convoy orchestration that can span rigs, with explicit inter-rig contracts and Mayor-mediated handoffs for shared infrastructure changes (e.g., shared DB schema, shared auth service).

**Prompt versioning for LLM agents** — the app's Agent 1 and Agent 2 prompts are inline strings in `analyzer_service.py`. In production these would be versioned artifacts managed by the Prompt Designer polecat role (already present in `convoy-governance-ai`) and stored in a prompt registry, so prompt changes go through the same governance workflow as code changes.

**Extended polecat roster for `/crew-risky` convoys** — for structural or cross-rig changes that touch LLM behavior, three additional specialist polecats would join the `convoy-governance-ai` pipeline:

- **Cost & Performance Engineer** — runs after architecture-framing and before implementation, estimating token usage, latency impact, and cost delta for any prompt or model change. Produces a cost/latency report that the Critic reviews alongside the architecture. Changes that exceed a defined cost threshold require explicit Mayor sign-off.

- **Cybersec** — runs in parallel with the Test Runner during validation, scanning for prompt injection surfaces, data leakage risks, insecure output handling, and dependency vulnerabilities introduced by the change. Reports PASS/FAIL with findings; convoys do not reach continuity unless this polecat clears.

- **Evaluation Engineer** — runs in parallel with Cybersec and the Test Runner, executing a regression suite on an LLM evaluation platform (LangSmith, LangFuse, or equivalent) to verify that the change did not degrade any tracked LLM metric (accuracy, faithfulness, refusal rate, latency percentiles). Produces a before/after comparison report stored as a bead artifact. This is the guard against silent regressions in LLM behavior that unit tests alone cannot catch.

These three roles would only activate in `convoy-governance-ai` convoys (the variant used for changes that involve LLM prompts or agent behavior), keeping the lighter `convoy-feature` and `convoy-hotfix` workflows fast for non-LLM changes.

---

## Submission

**Walkthrough video:** [https://youtu.be/EbkOX-gTpyE](https://youtu.be/EbkOX-gTpyE)

**Gas Town workspace:** [https://github.com/Trajanolc/gastown_workspace](https://github.com/Trajanolc/gastown_workspace)

**Time spent:** ~4 hours total — ~2 hours designing and writing the governance workflow specification (`crew-governance.md` + installer scripts), ~1 hour on the base app and persistence feature delivery via the crew member, ~1 hour on documentation.
