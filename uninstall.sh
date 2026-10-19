#!/usr/bin/env bash
# ==============================================================================
# INFERNAL — Theme Uninstaller Wrapper (uninstall.sh)
# ==============================================================================
# Delegates directly to install.sh --uninstall to avoid duplicated logic.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/install.sh" --uninstall "$@"

