# Crew Governance

A standardized workflow system for Gas Town crew members. Provides three slash
commands that guide crew members through the right convoy type for any change —
bug fixes, new features, or structural/breaking work.

---

## What problem does this solve?

Crew members are persistent orchestrators. When work needs to be done, they
create a **convoy** and dispatch **polecats** (ephemeral workers) to execute
the steps. Without governance, it's easy to skip gates, blur scope boundaries,
or start implementing before design is approved.

These commands encode the right workflow for each change type so it happens
consistently, every time.

**Two-tier escalation model**: polecats notify the crew member first. The crew
member is the first responder — they handle what they can (route design-critique
back to arch, assess validation failures, contain surprises). They escalate to
Mayor only when something is unresolvable or crosses rig boundaries.

---

## The three slash commands

| Command         | When to use                                        | Convoy type         |
|-----------------|----------------------------------------------------|---------------------|
| `/crew-bugfix`  | Confirmed bug, narrow scope, no redesign required  | `convoy-hotfix`     |
| `/crew-feature` | New functionality, localized to one subsystem      | `convoy-feature`    |
| `/crew-risky`   | Structural/breaking change, cross-rig impact       | `convoy-governance` |

**Rule of thumb**: when in doubt, escalate up the table. A bug that grows scope
becomes a feature. A feature that crosses rig boundaries becomes risky.

---

## How each workflow works

### `/crew-bugfix` → convoy-hotfix

The lightest workflow. Use when the bug is confirmed and the fix is narrow.

```
implement → validate → continuity
```

Steps:
1. Scope-check: is this truly narrow? If not, stop and use `/crew-feature`
2. Create convoy: `bd mol pour --formula convoy-hotfix`
3. Track progress through implement → validate → continuity
4. If scope grows or validation fails: you assess first, then escalate to Mayor only if the change crosses rig boundaries

**Parallel implementation:** you may dispatch multiple Implementers at once,
one per independent sub-task. Test Runner does not start until you confirm
all Implementers are done.

**Escalation rule**: scope grew within this rig → switch to `/crew-feature`. Scope crossed rig boundaries → notify Mayor.

---

### `/crew-feature` → convoy-feature

Standard workflow with a mandatory design gate before any code is written.

```
qa-spec ─┐
          ├──→ design-critique → implement → validate → continuity
arch    ──┘
```

Steps:
1. Create convoy: `bd mol pour --formula convoy-feature`
2. `qa-spec` and `arch` run in parallel (polecats execute)
3. **Design-critique gate**: you review Critic's verdict before allowing implementation
   - CLEAR → proceed
   - BLOCKED → route back to arch with Critic's findings
4. Implementation, validation, continuity follow

**Parallel implementation:** you may dispatch multiple Implementers at once,
one per independent sub-task. Test Runner does not start until you confirm
all Implementers are done.

**Hard rule**: no code before design-critique is CLEAR.

---

### `/crew-risky` → convoy-governance

Full governance for anything structural, cross-rig, or with broad impact.

```
qa-spec ─┐
          ├──→ design-critique → implement → validate ─┐
arch    ──┘                                             ├──→ continuity
                                       devops-stability ┘
```

Steps:
1. Document every affected system before starting
2. Create convoy: `bd mol pour --formula convoy-governance`
3. **Mayor approval is mandatory** before polecats start any step
4. After design-critique CLEAR: implementation begins
5. Validation and devops-stability run in parallel after implementation
6. Continuity only opens when **both** validation and devops pass
7. Any unexpected system discovered during work → **stop immediately**, assess scope, then notify Mayor if it crosses rig boundaries

**Parallel implementation:** you may dispatch multiple Implementers at once,
one per independent sub-task. Test Runner does not start until you confirm
all Implementers are done.

**Hard rules**: Mayor approves before start. Design gate before code. Any surprise stops the convoy — you assess, then escalate if you cannot contain it.

> If the change involves LLM prompts or agent behavior, use `--formula convoy-governance-ai` when creating the convoy in step 2.

---

## Installation

### Install in all existing crews

From anywhere inside your Gas Town workspace:

```bash
./mayor/rig/install-crew-governance.sh
```

### Install in a specific rig or crew

```bash
# All crews under one rig
./mayor/rig/install-crew-governance.sh --rig contract_checker

# One specific crew
./mayor/rig/install-crew-governance.sh --rig contract_checker --crew gov
```

### Preview without writing anything

```bash
./mayor/rig/install-crew-governance.sh --dry-run
```

### Overwrite existing command files

```bash
./mayor/rig/install-crew-governance.sh --force
```

---

## Creating new crews with governance pre-installed

Use `crew-add.sh` instead of `gt crew add` directly:

```bash
./mayor/rig/crew-add.sh <rig> <name>

# Example
./mayor/rig/crew-add.sh contract_checker researcher
```

This runs `gt crew add` and immediately installs the governance commands. The
new crew workspace is ready to use `/crew-bugfix`, `/crew-feature`, and
`/crew-risky` from the first session.

Any extra flags are passed through to `gt crew add`:

```bash
./mayor/rig/crew-add.sh contract_checker researcher --branch main
```

---

## Auto-heal on session start

The `crew/.claude/settings.json` includes a `SessionStart` hook that checks
whether governance commands exist in the current workspace. If they are missing,
it runs the install script automatically — silently, in the background.

This means any crew workspace created by any means (including `gt crew add`
directly) will self-heal on its first Claude Code session.

---

## Sharing with others

`install-crew-governance.sh` is fully self-contained:
- No hardcoded paths — discovers GT root by walking up dirs until `mayor/rigs.json` is found
- Only prerequisite: be inside a Gas Town workspace
- Requires `jq` or `python3` (for JSON parsing)

To share:

```bash
# Copy the file to a friend's Gas Town workspace, then:
./install-crew-governance.sh
```

---

## File locations

```
mayor/rig/
  install-crew-governance.sh   Main installer (shareable)
  crew-add.sh                  Wrapper: gt crew add + governance install
  crew-governance.md           This file

<rig>/crew/<name>/.claude/commands/
  crew-bugfix.md               /crew-bugfix  → convoy-hotfix
  crew-feature.md              /crew-feature → convoy-feature
  crew-risky.md                /crew-risky   → convoy-governance

<rig>/crew/.claude/settings.json
  SessionStart hook            Auto-heal if commands are missing
```

---

## Quick reference

```
Change type          Command           Convoy formula
─────────────────────────────────────────────────────
Bug fix              /crew-bugfix      convoy-hotfix
New feature          /crew-feature     convoy-feature
Structural/breaking  /crew-risky       convoy-governance
Structural + LLM     /crew-risky *     convoy-governance-ai
```

\* Use `/crew-risky` then choose `convoy-governance-ai` formula when creating the convoy.
