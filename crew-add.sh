#!/usr/bin/env bash
# =============================================================================
# crew-add.sh
#
# Wrapper around `gt crew add` that automatically installs crew governance.
# Ensures every new crew member is born with the governance workflow commands.
#
# USAGE
#   ./crew-add.sh <rig> <name> [gt crew add options...]
#
# EXAMPLES
#   ./crew-add.sh contract_checker gov
#   ./crew-add.sh contract_checker researcher --branch main
# =============================================================================

set -euo pipefail

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

# ── Validate args ─────────────────────────────────────────────────────────────
if [[ $# -lt 2 ]]; then
  echo ""
  echo "  Usage: $0 <rig> <name> [gt crew add options...]"
  echo ""
  echo "    <rig>   Name of the rig (e.g., contract_checker)"
  echo "    <name>  Name for the new crew member (e.g., gov)"
  echo ""
  echo "  Additional options are passed through to \`gt crew add\`."
  echo ""
  exit 1
fi

RIG="$1"
NAME="$2"
shift 2
EXTRA_ARGS=("$@")

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Create the crew ───────────────────────────────────────────────────────────
echo ""
bold "═══════════════════════════════════════════════════"
bold "  Creating crew member: $NAME (rig: $RIG)"
bold "═══════════════════════════════════════════════════"
echo ""

if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
  info "Running: gt crew add \"$NAME\" --rig \"$RIG\" ${EXTRA_ARGS[*]}"
else
  info "Running: gt crew add \"$NAME\" --rig \"$RIG\""
fi
echo ""

if ! gt crew add "$NAME" --rig "$RIG" "${EXTRA_ARGS[@]}"; then
  fail "gt crew add failed. Crew member not created."
  exit 1
fi

echo ""
ok "Crew member created."

# ── Install governance ────────────────────────────────────────────────────────
echo ""
bold "Installing crew governance commands..."
echo ""

"$SCRIPT_DIR/install-crew-governance.sh" --rig "$RIG" --crew "$NAME" --force

echo ""
bold "═══════════════════════════════════════════════════"
bold "  $NAME is ready with governance."
bold "═══════════════════════════════════════════════════"
echo ""
echo "  Available slash commands in this crew workspace:"
echo ""
echo "    /crew-bugfix    Bug fix (convoy-hotfix)"
echo "    /crew-feature   New feature (convoy-feature)"
echo "    /crew-risky     Structural change (convoy-governance)"
echo ""
