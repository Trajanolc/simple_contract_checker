#!/usr/bin/env bash
# =============================================================================
# install-crew-governance.sh
#
# Installs crew governance slash commands into Gas Town crew workspaces.
# These commands define three engineering workflow profiles for crew members:
#
#   /crew-bugfix    Fast-track: bug fixes with narrow scope (convoy-hotfix)
#   /crew-feature   Standard:   new features (convoy-feature)
#   /crew-risky     Full:       structural/breaking changes (convoy-governance)
#
# Crew members are persistent orchestrators. They create convoys and coordinate
# polecats — they do not implement. These commands encode that workflow.
#
# USAGE
#   ./install-crew-governance.sh [OPTIONS]
#
# OPTIONS
#   --rig NAME    Only install in crews belonging to this rig
#   --crew NAME   Only install in the named crew
#   --force       Overwrite existing command files
#   --dry-run     Print what would be installed, but don't write anything
#   --help        Show this message
#
# REQUIREMENTS
#   - A Gas Town workspace with mayor/rigs.json
#   - jq or python3 (for JSON parsing)
#
# SHAREABLE
#   This script is self-contained. It auto-discovers the Gas Town root and all
#   registered crew members. To share with friends:
#     1. Copy this file to their Gas Town workspace
#     2. Run: ./install-crew-governance.sh
# =============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
FORCE=false
DRY_RUN=false
FILTER_RIG=""
FILTER_CREW=""

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}  ✓${RESET} $*"; }
info() { echo -e "${BLUE}  →${RESET} $*"; }
warn() { echo -e "${YELLOW}  ⚠${RESET} $*"; }
fail() { echo -e "${RED}  ✗${RESET} $*" >&2; }
bold() { echo -e "${BOLD}$*${RESET}"; }

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rig)
      FILTER_RIG="$2"
      shift 2
      ;;
    --crew)
      FILTER_CREW="$2"
      shift 2
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      sed -n '2,32p' "$0" | sed 's/^# //' | sed 's/^#//'
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ── Locate GT root ────────────────────────────────────────────────────────────
find_gt_root() {
  # Use $GT_TOWN_ROOT if set and valid
  if [[ -n "${GT_TOWN_ROOT:-}" && -f "$GT_TOWN_ROOT/mayor/rigs.json" ]]; then
    echo "$GT_TOWN_ROOT"
    return
  fi

  # Walk up from current directory looking for mayor/rigs.json
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/mayor/rigs.json" ]]; then
      echo "$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done

  echo ""
}

GT_ROOT="$(find_gt_root)"

if [[ -z "$GT_ROOT" ]]; then
  fail "Could not find a Gas Town root (mayor/rigs.json not found)."
  echo ""
  echo "  Run this script from within your Gas Town workspace, or set:"
  echo "    export GT_TOWN_ROOT=/path/to/your/workspace"
  exit 1
fi

RIGS_JSON="$GT_ROOT/mayor/rigs.json"

# ── JSON parser (jq or python3 fallback) ─────────────────────────────────────
parse_rig_names() {
  if command -v jq &>/dev/null; then
    jq -r '.rigs | keys[]' "$RIGS_JSON" 2>/dev/null
  elif command -v python3 &>/dev/null; then
    python3 - "$RIGS_JSON" << 'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for k in d.get("rigs", {}).keys():
    print(k)
PY
  else
    fail "jq or python3 is required to parse rigs.json"
    exit 1
  fi
}

# ── Discover crew directories ─────────────────────────────────────────────────
# Outputs lines of the form "rig_name:crew_name:crew_dir"
discover_crews() {
  local rig_names
  rig_names="$(parse_rig_names)"

  if [[ -z "$rig_names" ]]; then
    return
  fi

  while IFS= read -r rig; do
    [[ -z "$rig" ]] && continue

    if [[ -n "$FILTER_RIG" && "$rig" != "$FILTER_RIG" ]]; then
      continue
    fi

    local crew_base="$GT_ROOT/$rig/crew"
    [[ -d "$crew_base" ]] || continue

    for state_file in "$crew_base"/*/state.json; do
      [[ -f "$state_file" ]] || continue
      local crew_dir
      crew_dir="$(dirname "$state_file")"
      local crew_name
      crew_name="$(basename "$crew_dir")"

      if [[ -n "$FILTER_CREW" && "$crew_name" != "$FILTER_CREW" ]]; then
        continue
      fi

      echo "$rig:$crew_name:$crew_dir"
    done
  done <<< "$rig_names"
}

# ── Write a single command file ───────────────────────────────────────────────
# Usage: write_command <crew_dir> <name> << 'MD' ... MD
write_command() {
  local crew_dir="$1"
  local name="$2"
  local dest="$crew_dir/.claude/commands/${name}.md"

  if [[ -f "$dest" && "$FORCE" == "false" ]]; then
    warn "Skipping ${name}.md (already exists — use --force to overwrite)"
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    info "Would write: $dest"
    return
  fi

  mkdir -p "$(dirname "$dest")"
  cat > "$dest"
  ok "Installed: ${name}.md"
}

# ── Install all three governance commands into one crew dir ───────────────────
install_crew() {
  local rig="$1"
  local crew="$2"
  local crew_dir="$3"

  echo ""
  bold "  [$rig / $crew]"
  info "  $crew_dir/.claude/commands/"

  # ── crew-bugfix.md ──────────────────────────────────────────────────────────
  write_command "$crew_dir" "crew-bugfix" << 'MD'
---
description: Crew governance for bug fixes — creates a convoy-hotfix
allowed-tools: Bash(bd mol pour*), Bash(gt mail send*)
---

You are the crew member orchestrating a **bug fix**. You coordinate — polecats implement.

## Step 1 — Scope check

Confirm this is a true bug fix with narrow scope:
- Bug is confirmed and reproducible
- Scope is limited (ideally < 1 file or 1 subsystem)
- No architectural redesign required

**If scope is broader** → stop here and use `/crew-feature` instead.

## Step 2 — Create the convoy

```bash
# Read your crew address from state.json:
CREW_ADDR=$(python3 -c "import json; d=json.load(open('state.json')); print(d['rig']+'/crew/'+d['name'])")

bd mol pour --formula convoy-hotfix \
  --var crew_member="$CREW_ADDR" \
  --var objective='<what bug needs to be fixed>' \
  --var scope='<affected file(s) or subsystem>'
```

Note the convoy ID returned (e.g., `mol-abc123`). Track it through all steps.

## Step 3 — Track convoy progress

**Parallel implementation:** you may dispatch multiple Implementers at once,
one per independent sub-task. Test Runner does not start until you confirm
all Implementers are done.

| Step           | Polecat role        | Your action                                                                  |
|----------------|---------------------|------------------------------------------------------------------------------|
| implementation | Implementers (1..N) | Dispatch in parallel per sub-task; wait for ALL before unblocking validation |
| validation     | Test Runner         | Unblock only when ALL Implementers have reported done                        |
| continuity     | Librarian           | Confirm institutional memory was saved                                       |

## Step 4 — Follow convoy steps

Allow polecats to execute each step in order:
- **Do NOT implement** — you coordinate, polecats execute
- **Review validation evidence** before continuity begins
- **Watch for escalation mails** — scope growth must be handled immediately

## Step 5 — Two-tier escalation

You are the first responder. Handle what you can — only escalate to Mayor when you cannot decide alone.

**Resolve yourself** (do not involve Mayor):
- Validation failure → review Test Runner evidence, decide whether to retry or escalate the convoy profile
- Scope grew slightly but stays within this rig → reassess profile, switch to `/crew-feature` if needed

**Escalate to Mayor** (you cannot decide alone):
- Scope grew beyond this rig's boundaries
- Any change that affects other rigs or shared contracts

```bash
gt mail send mayor/ -s "ESCALATION: <summary>" -m "<what, why, what you already tried>"
```

## Done

Convoy complete when:
- Validation passes (Test Runner evidence reviewed)
- Continuity step has saved institutional memory
- Branch submitted for review

---

## Polecat Role Descriptions

Use these blocks when dispatching polecats. Copy the relevant section into the issue bead.

---

### Implementer  ·  step: `implementation`

You are the **Implementer** for this convoy. Fix the assigned bug within the defined scope.

**You must produce:**
- Code fix committed to the branch
- Brief explanation: root cause and what changed

**Constraints:**
- Do NOT redesign architecture
- Do NOT expand scope beyond your assigned sub-task
- Do NOT touch files outside your assigned sub-task without notifying the crew member first
- You may have peer Implementers working on other sub-tasks in parallel — stay within your assigned scope only

**On scope growth:** mail the crew member at the address given in your issue bead before touching any out-of-scope file:
  `gt mail send <crew_member_address> -s "[IMPLEMENTER] SCOPE GROWTH: <convoy>" -m "<what, why>"`

**Done:** fix committed, explanation written — mail the crew member to confirm your sub-task is complete.

---

### Test Runner  ·  step: `validation`

You are the **Test Runner** for this convoy. Run the test suite and report results.

**You must produce:**
- PASS/FAIL report
- Logs and traces (attach or summarize)
- Reproduction steps on failure

**Constraints:**
- Do NOT interpret results or draw conclusions about root cause
- Do NOT attempt to fix any failures
- Do NOT self-close — you report, the crew member decides
- You start only when the crew member tells you all Implementers are done

**On failure:** mail the crew member with full evidence immediately; do not proceed:
  `gt mail send <crew_member_address> -s "[TEST RUNNER] BLOCKED: <convoy>" -m "<what, why>"`

**Done:** report delivered to crew member.

---

### Librarian  ·  step: `continuity`

You are the **Librarian** for this convoy. Preserve institutional memory of what happened.

**You must produce:**
- Root cause summary
- What changed: file paths and commit reference
- How to verify the fix
- Known edge cases or follow-up items

**Constraints:**
- Do NOT alter code or tests
- Record what happened, not what should happen next

**On any issue:** mail the crew member at the address given in your issue bead:
  `gt mail send <crew_member_address> -s "[LIBRARIAN] BLOCKED: <convoy>" -m "<what, why>"`

**Done:** memory artifact written and accessible.
MD

  # ── crew-feature.md ─────────────────────────────────────────────────────────
  write_command "$crew_dir" "crew-feature" << 'MD'
---
description: Crew governance for new features — creates a convoy-feature
allowed-tools: Bash(bd mol pour*), Bash(gt mail send*)
---

You are the crew member orchestrating a **new feature**. You coordinate — polecats implement.

## Step 1 — Create the convoy

```bash
# Read your crew address from state.json:
CREW_ADDR=$(python3 -c "import json; d=json.load(open('state.json')); print(d['rig']+'/crew/'+d['name'])")

bd mol pour --formula convoy-feature \
  --var crew_member="$CREW_ADDR" \
  --var objective='<high-level objective of the feature>' \
  --var scope='<scope or subsystem affected>' \
  --var feature_name='<short name for release notes>'
```

Note the convoy ID returned (e.g., `mol-abc123`). Track it through all steps.

## Step 2 — Convoy DAG

```
qa-spec ─┐
          ├──→ design-critique → implementation → validation → continuity
arch    ──┘
```

**Parallel implementation:** you may dispatch multiple Implementers at once,
one per independent sub-task. Test Runner does not start until you confirm
all Implementers are done.

| Step                 | Polecat role        | Your action                                                                  |
|----------------------|---------------------|------------------------------------------------------------------------------|
| qa-specification     | QA Spec             | Wait — runs in parallel with arch                                            |
| architecture-framing | Architect           | Wait — runs in parallel with qa-spec                                         |
| design-critique      | Critic              | **GATE**: review findings, approve or block                                  |
| implementation       | Implementers (1..N) | Dispatch in parallel per sub-task; wait for ALL before unblocking validation |
| validation           | Test Runner         | Unblock only when ALL Implementers have reported done                        |
| continuity           | Librarian           | Confirm release notes and memory saved                                       |

## Step 3 — Design-critique gate (HARD GATE)

**Do NOT allow implementation before design-critique is approved.**

When the Critic reports findings:
- **CLEAR** → convoy proceeds to implementation
- **BLOCKED** → route back to architecture-framing yourself with Critic's findings attached

If still BLOCKED after two rounds with no resolution → escalate to Mayor:
```bash
gt mail send mayor/ -s "ESCALATION: design-critique unresolved on <feature_name>" -m "<findings, rounds attempted>"
```

## Step 4 — Follow convoy steps

- **Do NOT implement** — you coordinate, polecats execute
- **Enforce the design gate** — no implementation without CLEAR verdict
- **Watch for escalation mails** — scope growth requires your assessment first

## Step 5 — Two-tier escalation

You are the first responder. Handle what you can — only escalate to Mayor when you cannot decide alone.

**Resolve yourself** (do not involve Mayor):
- design-critique BLOCKED → route back to architecture-framing yourself
- Validation failure → review evidence, decide whether to retry or escalate convoy profile

**Escalate to Mayor** (you cannot decide alone):
- Scope grew beyond this rig's boundaries
- design-critique BLOCKED after two rounds with no resolution
- Any change that affects other rigs or shared contracts

```bash
gt mail send mayor/ -s "ESCALATION: <summary>" -m "<what, why, what you already tried>"
```

## Done

Convoy complete when:
- Design-critique: CLEAR verdict received
- Validation passes (Test Runner evidence reviewed)
- Continuity step has saved release notes and institutional memory

---

## Polecat Role Descriptions

Use these blocks when dispatching polecats. Copy the relevant section into the issue bead.

---

### QA Spec  ·  step: `qa-specification`

You are the **QA Spec** for this convoy. Define what done looks like before implementation begins.

**You must produce:**
- DoR (Definition of Ready): what must be true before implementation can start
- DoD (Definition of Done): what must be true to close the feature
- Acceptance criteria
- Edge cases
- Test sketches

**Constraints:**
- Do NOT write implementation code
- Do NOT bias criteria toward any specific implementation approach
- Implementation MUST NOT start until DoR is satisfied

**On any issue:** mail the crew member at the address given in your issue bead:
  `gt mail send <crew_member_address> -s "[QA SPEC] BLOCKED: <convoy>" -m "<what, why>"`

**Done:** notify the crew member that qa-specification is complete.

---

### Architect  ·  step: `architecture-framing`

You are the **Architect** for this convoy. Define the system boundaries and decompose the work.

**You must produce:**
- System boundaries and guardrails (what polecats must not cross)
- Bead decomposition proposal
- ADR updates if required

**Constraints:**
- Do NOT write implementation code
- Guardrails must be explicit and checkable

**On any issue:** mail the crew member at the address given in your issue bead:
  `gt mail send <crew_member_address> -s "[ARCHITECT] BLOCKED: <convoy>" -m "<what, why>"`

**Done:** notify the crew member — they will trigger design-critique.

---

### Critic  ·  step: `design-critique`

You are the **Critic** for this convoy. Review the architecture and qa-spec for issues before implementation begins.

**You must produce:**
- Findings report with verdict: CLEAR or BLOCKED
- Specific issues with severity

**Constraints:**
- Do NOT modify any documents or code
- Do NOT approve if critical findings remain unresolved
- Verdict: CLEAR = convoy proceeds to implementation; BLOCKED = crew member routes back to architecture-framing

**On any issue:** mail the crew member at the address given in your issue bead:
  `gt mail send <crew_member_address> -s "[CRITIC] BLOCKED: <convoy>" -m "<what, why>"`

**Done:** mail the crew member with your findings and verdict.

---

### Implementer  ·  step: `implementation`

You are the **Implementer** for this convoy. Build the assigned sub-task per architect guardrails and QA DoR.

**You must produce:**
- Feature implemented per architect guardrails and QA DoR
- All changes committed

**Constraints:**
- Do NOT cross architect system boundaries
- Do NOT begin before DoR is satisfied
- Do NOT expand scope or touch files outside your sub-task without notifying the crew member first
- You may have peer Implementers working on other sub-tasks in parallel — stay within your assigned scope only

**On scope growth:** mail the crew member at the address given in your issue bead before touching any out-of-scope file:
  `gt mail send <crew_member_address> -s "[IMPLEMENTER] SCOPE GROWTH: <convoy>" -m "<what, why>"`

**Done:** your sub-task committed — mail the crew member to confirm completion.

---

### Test Runner  ·  step: `validation`

You are the **Test Runner** for this convoy. Run the test suite and report results.

**You must produce:**
- PASS/FAIL report
- Logs and traces (attach or summarize)
- Reproduction steps on failure

**Constraints:**
- Do NOT interpret results or draw conclusions about root cause
- Do NOT attempt to fix any failures
- Do NOT self-close — you report, the crew member decides
- You start only when the crew member tells you all Implementers are done

**On failure:** mail the crew member with full evidence immediately; do not proceed:
  `gt mail send <crew_member_address> -s "[TEST RUNNER] BLOCKED: <convoy>" -m "<what, why>"`

**Done:** report delivered to crew member.

---

### Librarian  ·  step: `continuity`

You are the **Librarian** for this convoy. Preserve institutional memory and produce release notes.

**You must produce:**
- Release notes for the feature
- Bead/commit summary
- Change intent and impact
- Verification instructions
- Known limitations

**Constraints:**
- Do NOT alter code or tests
- Record what happened, not what should happen next

**On any issue:** mail the crew member at the address given in your issue bead:
  `gt mail send <crew_member_address> -s "[LIBRARIAN] BLOCKED: <convoy>" -m "<what, why>"`

**Done:** memory artifact written and accessible.
MD

  # ── crew-risky.md ───────────────────────────────────────────────────────────
  write_command "$crew_dir" "crew-risky" << 'MD'
---
description: Crew governance for breaking/structural changes — creates a convoy-governance
allowed-tools: Bash(bd mol pour*), Bash(gt mail send*)
---

You are the crew member orchestrating a **structural or breaking change**. This is
the highest-governance convoy. You gate and coordinate — polecats implement.

## Step 1 — Document all affected systems

Before creating the convoy, list every system that will be touched:
- Which rigs, subsystems, or APIs are affected?
- Are there public contracts or shared interfaces changing?
- Does this involve LLM or agent prompts? → use `--formula convoy-governance-ai` instead

## Step 2 — Create the convoy

```bash
# Read your crew address from state.json:
CREW_ADDR=$(python3 -c "import json; d=json.load(open('state.json')); print(d['rig']+'/crew/'+d['name'])")

bd mol pour --formula convoy-governance \
  --var crew_member="$CREW_ADDR" \
  --var objective='<high-level objective>' \
  --var scope='<primary scope or subsystem>' \
  --var impact_areas='<comma-separated list of affected systems>'
```

Note the convoy ID returned (e.g., `mol-abc123`). Track it through all steps.

## Step 3 — Mayor approval (MANDATORY BEFORE ANY CODE)

**Before polecats start any step**, notify Mayor:

```bash
gt mail send mayor/ \
  -s "RISKY CONVOY: <objective>" \
  -m "Convoy ID: <id>
Impact areas: <impact_areas>
Rationale: <why this change is needed>
Requesting approval to proceed."
```

**Do NOT allow qa-spec or arch to start until Mayor approves.**

## Step 4 — Convoy DAG

```
qa-spec ─┐
          ├──→ design-critique → implementation → validation ─┐
arch    ──┘                                                    ├──→ continuity
                                              devops-stability ┘
```

**Parallel implementation:** you may dispatch multiple Implementers at once,
one per independent sub-task. Test Runner does not start until you confirm
all Implementers are done.

| Step                 | Polecat role        | Your action                                                                  |
|----------------------|---------------------|------------------------------------------------------------------------------|
| qa-specification     | QA Spec             | Wait — runs in parallel with arch                                            |
| architecture-framing | Architect           | Wait — must include risk assessment per impact area                          |
| design-critique      | Critic              | **GATE**: review findings, approve or block                                  |
| implementation       | Implementers (1..N) | Dispatch in parallel per sub-task; wait for ALL before unblocking validation |
| validation           | Test Runner         | Unblock only when ALL Implementers have reported done; runs in parallel with devops-stability |
| devops-stability     | DevOps              | Runs in parallel with validation                                             |
| continuity           | Librarian           | Opens only when BOTH validation AND devops pass                              |

## Step 5 — Design-critique gate (HARD GATE)

**Do NOT allow implementation before design-critique is approved.**

When the Critic reports:
- **CLEAR** → convoy proceeds to implementation
- **BLOCKED** → route back to architecture-framing yourself with findings attached

If still BLOCKED after two rounds with no resolution → escalate to Mayor:
```bash
gt mail send mayor/ -s "ESCALATION: design-critique unresolved on <objective>" -m "<findings, rounds attempted>"
```

## Step 6 — Any surprise → stop and assess

If any unexpected system is found to be affected during implementation:

1. Stop the convoy immediately
2. Document what was discovered
3. Assess: is this something you can contain within this rig, or does it cross boundaries?
4. If it crosses rig boundaries or shared contracts → notify Mayor:
   ```bash
   gt mail send mayor/ -s "CONVOY SURPRISE: <objective>" -m "<what was found, which systems>"
   ```
5. Wait for Mayor guidance before continuing

## Step 7 — Dual validation gate

Both validation AND devops-stability must pass before continuity.

**Resolve yourself** (do not involve Mayor):
- Validation failure → review Test Runner evidence, decide whether infrastructure issue or scope issue
- DevOps failure → review reproducibility report, decide whether environment issue or scope issue

**Escalate to Mayor** (you cannot decide alone):
- Either failure after assessment reveals scope beyond this rig
- Structural surprise confirmed during investigation

```bash
gt mail send mayor/ -s "ESCALATION: <summary>" -m "<what, why, what you already tried>"
```

## Done

Convoy complete when:
- Mayor approved the convoy at creation
- Design-critique: CLEAR verdict received
- Validation passes (Test Runner evidence)
- DevOps stability passes (reproducibility confirmed)
- Continuity step documents all affected systems and environment requirements

---

## Polecat Role Descriptions

Use these blocks when dispatching polecats. Copy the relevant section into the issue bead.

---

### QA Spec  ·  step: `qa-specification`

You are the **QA Spec** for this convoy. Define what done looks like before implementation begins.

**You must produce:**
- DoR (Definition of Ready): what must be true before implementation can start
- DoD (Definition of Done): what must be true to close the change
- Acceptance criteria
- Edge cases
- Test sketches
- Behavioral test cases for AI components (if applicable)

**Constraints:**
- Do NOT write implementation code
- Do NOT bias criteria toward any specific implementation approach
- Implementation MUST NOT start until DoR is satisfied

**On any issue:** mail the crew member at the address given in your issue bead:
  `gt mail send <crew_member_address> -s "[QA SPEC] BLOCKED: <convoy>" -m "<what, why>"`

**Done:** notify the crew member that qa-specification is complete.

---

### Architect  ·  step: `architecture-framing`

You are the **Architect** for this convoy. Define system boundaries, decompose the work, and assess risk.

**You must produce:**
- System boundaries and guardrails (what polecats must not cross)
- ADR updates (mandatory for cross-rig changes)
- Bead decomposition proposal
- Risk assessment per impact area (every impact area listed in the convoy must have a risk entry)

**Constraints:**
- Do NOT write implementation code
- Every impact area listed in the convoy must have a risk entry
- Guardrails must be explicit and checkable

**On any issue:** mail the crew member at the address given in your issue bead:
  `gt mail send <crew_member_address> -s "[ARCHITECT] BLOCKED: <convoy>" -m "<what, why>"`

**Done:** notify the crew member — prompt-design (if convoy-governance-ai) auto-starts; otherwise the crew member triggers design-critique.

---

### Prompt Designer  ·  step: `prompt-design` *(convoy-governance-ai only)*

You are the **Prompt Designer** for this convoy. Produce production-ready prompt specifications.

**You must produce:**
- Production-ready prompt specifications (not drafts)
- Versioned prompt definitions with rationale
- Behavioral contracts
- Structured output schemas
- Guardrails and refusals

**Constraints:**
- Do NOT write implementation code
- All prompts must be versioned
- Polecats are FORBIDDEN from improvising — if a prompt is missing they must stop and mail the crew member

**On any issue:** mail the crew member at the address given in your issue bead:
  `gt mail send <crew_member_address> -s "[PROMPT DESIGNER] BLOCKED: <convoy>" -m "<what, why>"`

**Done:** notify the crew member that qa+prompts are ready for design-critique.

---

### Critic  ·  step: `design-critique`

You are the **Critic** for this convoy. Review the architecture, qa-spec, and (if applicable) prompt specifications.

**You must produce:**
- Findings report with verdict: CLEAR or BLOCKED
- Specific issues with severity
- Evaluation of prompt specification completeness and safety (if applicable)

**Constraints:**
- Do NOT modify any documents or code
- Do NOT approve if critical findings remain unresolved
- Verdict: CLEAR = convoy proceeds to implementation; BLOCKED = crew member routes back to architecture-framing
- Do NOT route yourself — mail the crew member with findings and verdict

**On BLOCKED:** mail the crew member immediately:
  `gt mail send <crew_member_address> -s "[CRITIC] BLOCKED: <convoy>" -m "<findings>"`

**Done:** mail the crew member with your findings and verdict.

---

### Implementer  ·  step: `implementation`

You are the **Implementer** for this convoy. Build the assigned sub-task per architect guardrails and QA DoR.

**You must produce:**
- Feature/change implemented per architect guardrails and QA DoR
- All changes committed
- If prompts were specified by the Prompt Designer: follow specs EXACTLY

**Constraints:**
- Do NOT cross architect system boundaries
- Do NOT begin before DoR is satisfied
- Do NOT expand scope or touch files outside your sub-task without notifying the crew member first
- Do NOT improvise or invent prompts under any circumstance — if a prompt spec is missing, STOP and mail the crew member immediately before writing any prompt
- You may have peer Implementers working on other sub-tasks in parallel — stay within your assigned scope only

**On scope growth or missing prompt spec:** mail the crew member at the address given in your issue bead immediately:
  `gt mail send <crew_member_address> -s "[IMPLEMENTER] BLOCKED: <convoy>" -m "<what, why>"`

**Done:** your sub-task committed — mail the crew member to confirm completion.

---

### Test Runner  ·  step: `validation`

You are the **Test Runner** for this convoy. Run the test suite and report results.

**You must produce:**
- PASS/FAIL report
- Logs and traces (attach or summarize)
- Reproduction steps on failure
- Behavioral test results for AI components: input/output pairs vs expected (if applicable)

**Constraints:**
- Do NOT interpret results or draw conclusions about root cause
- Do NOT attempt to fix any failures
- Do NOT self-close — you report, the crew member decides
- You start only when the crew member tells you all Implementers are done

**On failure:** mail the crew member with full evidence immediately; do not proceed:
  `gt mail send <crew_member_address> -s "[TEST RUNNER] BLOCKED: <convoy>" -m "<what, why>"`

**Done:** report delivered to crew member.

---

### DevOps  ·  step: `devops-stability`

You are the **DevOps** for this convoy. Verify reproducibility and environment stability.

**You must produce:**
- Reproducibility report (PASS/FAIL)
- Environment snapshot: versions, configs, dependencies
- List of issues found

**Constraints:**
- Do NOT fix failures
- Do NOT interpret root cause — report only

**On failure:** mail the crew member with full report immediately; do not proceed:
  `gt mail send <crew_member_address> -s "[DEVOPS] BLOCKED: <convoy>" -m "<what, why>"`

**Done:** report delivered to crew member.

---

### Librarian  ·  step: `continuity`

You are the **Librarian** for this convoy. Preserve institutional memory across all affected systems.

**You must produce:**
- Release notes
- Bead/commit summary
- Change intent and impact across all impact areas
- Prompt specs in effect (versioned references, if applicable)
- Behavioral contracts summary (if applicable)
- Verification instructions
- Environment requirements confirmed by DevOps

**Constraints:**
- Do NOT alter code or tests
- Record what happened, not what should happen next

**On any issue:** mail the crew member at the address given in your issue bead:
  `gt mail send <crew_member_address> -s "[LIBRARIAN] BLOCKED: <convoy>" -m "<what, why>"`

**Done:** memory artifact written and accessible.
MD
}

# ── Verify installation ───────────────────────────────────────────────────────
VERIFY_ALL_OK=true

verify_install() {
  local crew_dir="$1"
  local commands=("crew-bugfix" "crew-feature" "crew-risky")

  for name in "${commands[@]}"; do
    local dest="$crew_dir/.claude/commands/${name}.md"
    if [[ "$DRY_RUN" == "true" ]]; then
      info "Would verify: $dest"
    elif [[ -f "$dest" ]]; then
      ok "$name.md"
    else
      fail "$name.md — not found at $dest"
      VERIFY_ALL_OK=false
    fi
  done
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo ""
bold "═══════════════════════════════════════════════════"
bold "  Crew Governance Command Installer"
bold "═══════════════════════════════════════════════════"
echo ""
info "GT root: $GT_ROOT"
[[ -n "$FILTER_RIG"  ]] && info "Filter rig:  $FILTER_RIG"
[[ -n "$FILTER_CREW" ]] && info "Filter crew: $FILTER_CREW"
[[ "$DRY_RUN" == "true" ]] && warn "DRY RUN — no files will be written"
[[ "$FORCE"   == "true" ]] && warn "FORCE mode — existing files will be overwritten"
echo ""

# Discover crews
CREWS="$(discover_crews)"

if [[ -z "$CREWS" ]]; then
  warn "No crew directories found matching the given filters."
  echo ""
  echo "  Make sure crews exist under <rig>/crew/<name>/state.json"
  exit 0
fi

# Install
INSTALL_COUNT=0
CREWS_LIST=()

while IFS=: read -r rig crew crew_dir; do
  [[ -z "$rig" || -z "$crew" || -z "$crew_dir" ]] && continue
  install_crew "$rig" "$crew" "$crew_dir"
  CREWS_LIST+=("$crew_dir")
  INSTALL_COUNT=$(( INSTALL_COUNT + 1 ))
done <<< "$CREWS"

# Verify
echo ""
bold "Verifying installation..."
echo ""

for crew_dir in "${CREWS_LIST[@]}"; do
  verify_install "$crew_dir"
done

echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  warn "Dry run complete. Run without --dry-run to install."
  exit 0
fi

if [[ "$VERIFY_ALL_OK" == "false" ]]; then
  fail "Some commands failed to install. Check permissions."
  exit 1
fi

bold "═══════════════════════════════════════════════════"
bold "  Installation complete. ($INSTALL_COUNT crew(s) updated)"
bold "═══════════════════════════════════════════════════"
echo ""
echo "  Installed slash commands:"
echo ""
echo "    /crew-bugfix    Bug fix, narrow scope     → convoy-hotfix"
echo "    /crew-feature   New feature, local impact → convoy-feature"
echo "    /crew-risky     Structural/breaking change → convoy-governance"
echo ""
echo "  Open a crew workspace and run one of the above to start."
echo ""
