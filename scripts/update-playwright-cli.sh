#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Package configuration
# ---------------------------------------------------------------------------
export NPM_PACKAGE="@playwright/cli"
export NIX_FILE="$REPO_ROOT/users/jloos/modules/playwright-cli.nix"
export LOCK_FILE="$REPO_ROOT/users/jloos/modules/playwright-cli/package-lock.json"
export PACKAGE_DISPLAY_NAME="playwright-cli"

# ---------------------------------------------------------------------------
# Run (uses default resolve_latest_version via npm view)
# ---------------------------------------------------------------------------
# shellcheck disable=SC1091 source=lib/update-npm-package.sh
source "$SCRIPT_DIR/lib/update-npm-package.sh"

update_npm_package "${1:-}"
