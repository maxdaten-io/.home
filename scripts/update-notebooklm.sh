#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

NIX_FILE="$REPO_ROOT/users/jloos/modules/claude-code.nix"
PYPI_PACKAGE="notebooklm-py"
PACKAGE_DISPLAY_NAME="notebooklm"

# ---------------------------------------------------------------------------
# Colors (disabled when not on a terminal)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  _bold="\033[1m" _dim="\033[2m" _green="\033[32m"
  _yellow="\033[33m" _red="\033[31m" _cyan="\033[36m" _reset="\033[0m"
else
  _bold="" _dim="" _green="" _yellow="" _red="" _cyan="" _reset=""
fi

info() { printf "${_cyan}==>${_reset} ${_bold}%s${_reset}\n" "$*"; }
ok() { printf "${_green} ✓${_reset}  %s\n" "$*"; }
warn() { printf "${_yellow} ⚠${_reset}  %s\n" "$*" >&2; }
die() {
  printf "${_red} ✗${_reset}  %s\n" "$*" >&2
  exit 1
}
field() { printf "    ${_dim}%-14s${_reset} %s\n" "$1" "$2"; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

resolve_latest_version() {
  curl -fsSL "https://pypi.org/pypi/${PYPI_PACKAGE}/json" |
    python3 -c "import sys,json; print(json.load(sys.stdin)['info']['version'])" 2>/dev/null ||
    die "Could not fetch latest version from PyPI"
}

pypi_sdist_url() {
  local version="$1"
  curl -fsSL "https://pypi.org/pypi/${PYPI_PACKAGE}/${version}/json" |
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for url in data['urls']:
    if url['packagetype'] == 'sdist':
        print(url['url'])
        sys.exit(0)
sys.exit(1)
" 2>/dev/null || die "Could not resolve sdist URL for ${PYPI_PACKAGE}==${version}"
}

nix_prefetch_sri() {
  local url="$1" raw
  raw=$(nix-prefetch-url "$url" 2>/dev/null) ||
    die "nix-prefetch-url failed for ${url}"
  nix hash convert --to sri --hash-algo sha256 "$raw"
}

nix_set_field() {
  local file="$1" key="$2" value="$3"
  sed -i '' "s|${key} = \"[^\"]*\"|${key} = \"${value}\"|" "$file"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

update_notebooklm() {
  local requested_version="${1:-}"

  [[ -f $NIX_FILE ]] || die "Nix file not found: ${NIX_FILE}"
  command -v nix-prefetch-url >/dev/null 2>&1 || die "nix-prefetch-url not found"
  command -v curl >/dev/null 2>&1 || die "curl not found"

  # --- resolve version ---
  local version
  case "${requested_version}" in
  latest)
    info "Resolving latest version of ${PACKAGE_DISPLAY_NAME}…"
    version=$(resolve_latest_version)
    ;;
  "")
    echo "Usage: $(basename "$0") <version|latest>"
    exit 1
    ;;
  *)
    version="${requested_version}"
    ;;
  esac

  # --- read current version from nix file (match the notebooklm derivation) ---
  OLD_VERSION=$(awk '/pname = "notebooklm-py"/{found=1} found && /version = "/{gsub(/.*version = "/,""); gsub(/".*/,""); print; exit}' "$NIX_FILE")
  NEW_VERSION="$version"
  export OLD_VERSION NEW_VERSION

  info "Updating ${PACKAGE_DISPLAY_NAME}"
  field "current:" "$OLD_VERSION"
  field "target:" "$NEW_VERSION"

  if [[ $OLD_VERSION == "$NEW_VERSION" ]]; then
    ok "Already at version ${NEW_VERSION}"
    return 0
  fi

  # --- 1. resolve sdist URL and fetch hash ---
  info "Resolving sdist URL…"
  local src_url src_hash
  src_url=$(pypi_sdist_url "$NEW_VERSION")
  ok "$src_url"

  info "Fetching source hash…"
  src_hash=$(nix_prefetch_sri "$src_url")
  ok "hash = \"${src_hash}\""

  # --- 2. patch nix file ---
  # The nix file has two `version = "..."` lines (claude-code and notebooklm).
  # We patch the notebooklm block specifically using awk.
  info "Patching ${NIX_FILE##*/}…"

  awk -v new_ver="$NEW_VERSION" -v new_hash="$src_hash" '
    /pname = "notebooklm-py"/ { in_block = 1 }
    in_block && /version = "/ && !ver_done {
      sub(/version = "[^"]*"/, "version = \"" new_ver "\"")
      ver_done = 1
    }
    in_block && /hash = "sha256-/ && !hash_done {
      sub(/hash = "[^"]*"/, "hash = \"" new_hash "\"")
      hash_done = 1
      in_block = 0
    }
    { print }
  ' "$NIX_FILE" >"${NIX_FILE}.tmp" && mv "${NIX_FILE}.tmp" "$NIX_FILE"

  ok "Done"

  # --- 3. summary ---
  echo ""
  info "${PACKAGE_DISPLAY_NAME}: ${OLD_VERSION} → ${NEW_VERSION}"
  echo ""
  git diff --stat "$NIX_FILE" 2>/dev/null || true
}

update_notebooklm "${1:-}"
