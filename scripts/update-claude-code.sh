#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Package configuration
# ---------------------------------------------------------------------------
export NPM_PACKAGE="@anthropic-ai/claude-code"
export NIX_FILE="$REPO_ROOT/users/jloos/modules/claude-code.nix"
export LOCK_FILE="$REPO_ROOT/users/jloos/modules/claude-code/package-lock.json"
export PACKAGE_DISPLAY_NAME="claude-code"
export PACKAGE_ANCHOR='pname = "claude-code"'

GITHUB_REPO="https://github.com/anthropics/claude-code"

# ---------------------------------------------------------------------------
# Overrides
# ---------------------------------------------------------------------------

# Resolve latest version from GitHub tags (more reliable for this package).
resolve_latest_version() {
  echo "Fetching latest version from GitHub tags…" >&2
  git ls-remote --tags --refs "$GITHUB_REPO" |
    sed 's|.*refs/tags/||' |
    sed 's/^v//' |
    sort -V |
    tail -1
}

# Show changelog highlights after a successful update.
post_update_hook() {
  local changelog
  info "Changelog highlights (${OLD_VERSION} → ${NEW_VERSION}):"
  echo ""

  changelog=$(curl -fsSL "${GITHUB_REPO}/raw/refs/heads/main/CHANGELOG.md" 2>/dev/null) || {
    warn "Could not fetch changelog"
    return 0
  }

  echo "$changelog" | awk -v target="$NEW_VERSION" -v current="$OLD_VERSION" '
    /^## / {
      v = $2
      gsub(/^v/, "", v)
      if (v == target) { printing = 1 }
      else if (v == current) { printing = 0 }
    }
    printing { print }
  '
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
# shellcheck disable=SC1091 source=lib/update-npm-package.sh
source "$SCRIPT_DIR/lib/update-npm-package.sh"

update_npm_package "${1:-}"
