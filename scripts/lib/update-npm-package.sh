#!/usr/bin/env bash
# Shared library for updating buildNpmPackage-based Nix packages.
#
# Usage: source this file from a package-specific update script, then call
# `update_npm_package <version|latest>`.
#
# Required variables (set before calling update_npm_package):
#   NPM_PACKAGE         - npm package name, e.g. "@anthropic-ai/claude-code"
#   NIX_FILE             - absolute path to the .nix file to update
#   LOCK_FILE            - absolute path to the vendored package-lock.json
#   PACKAGE_DISPLAY_NAME - human-readable name for log output, e.g. "claude-code"
#
# Optional overrides:
#   resolve_latest_version  - function returning the latest version string
#                             (default: npm view $NPM_PACKAGE version)
#   post_update_hook        - function called after a successful update with
#                             OLD_VERSION and NEW_VERSION set
#
# Exports after update_npm_package completes:
#   OLD_VERSION / NEW_VERSION

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors (disabled when not on a terminal)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  _bold="\033[1m"
  _dim="\033[2m"
  _green="\033[32m"
  _yellow="\033[33m"
  _red="\033[31m"
  _cyan="\033[36m"
  _reset="\033[0m"
else
  _bold="" _dim="" _green="" _yellow="" _red="" _cyan="" _reset=""
fi

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
info() { printf "${_cyan}==>${_reset} ${_bold}%s${_reset}\n" "$*"; }
ok() { printf "${_green} ✓${_reset}  %s\n" "$*"; }
warn() { printf "${_yellow} ⚠${_reset}  %s\n" "$*" >&2; }
die() {
  printf "${_red} ✗${_reset}  %s\n" "$*" >&2
  exit 1
}
field() { printf "    ${_dim}%-14s${_reset} %s\n" "$1" "$2"; }

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found in PATH"
}

check_prerequisites() {
  require_cmd nix-prefetch-url
  require_cmd nix
  require_cmd npm
  require_cmd sed
  require_cmd git
}

# ---------------------------------------------------------------------------
# npm helpers
# ---------------------------------------------------------------------------

# Derive the registry tarball URL for a (possibly scoped) npm package.
#   @scope/name  -> https://registry.npmjs.org/@scope/name/-/name-VERSION.tgz
#   name         -> https://registry.npmjs.org/name/-/name-VERSION.tgz
npm_tarball_url() {
  local pkg="$1" version="$2"
  local unscoped="${pkg##*/}"
  echo "https://registry.npmjs.org/${pkg}/-/${unscoped}-${version}.tgz"
}

# Default latest-version resolver — can be overridden before calling update.
if ! declare -F resolve_latest_version >/dev/null 2>&1; then
  resolve_latest_version() {
    npm view "${NPM_PACKAGE}" version 2>/dev/null ||
      die "Could not fetch latest version of ${NPM_PACKAGE} from npm"
  }
fi

# ---------------------------------------------------------------------------
# Nix helpers
# ---------------------------------------------------------------------------

# Prefetch a URL and return its SRI hash (sha256).
nix_prefetch_sri() {
  local url="$1"
  local raw
  raw=$(nix-prefetch-url "$url" 2>/dev/null) ||
    die "nix-prefetch-url failed for ${url}"
  nix hash convert --to sri --hash-algo sha256 "$raw"
}

# Compute the npmDepsHash for a given package-lock.json.
nix_npm_deps_hash() {
  local lockfile="$1"
  nix run nixpkgs#prefetch-npm-deps -- "$lockfile" 2>/dev/null ||
    die "prefetch-npm-deps failed for ${lockfile}"
}

# ---------------------------------------------------------------------------
# Nix file patching
# ---------------------------------------------------------------------------

# Replace a quoted value in a Nix file:  key = "old" → key = "new"
# Only replaces the first occurrence after PACKAGE_ANCHOR (if set),
# otherwise replaces ALL matches.
# PACKAGE_ANCHOR should uniquely identify the package block,
# e.g. 'pname = "claude-code"'.
nix_set_field() {
  local file="$1" key="$2" value="$3"
  if [[ -n ${PACKAGE_ANCHOR:-} ]]; then
    awk -v anchor="$PACKAGE_ANCHOR" -v key="$key" -v val="$value" '
      !found && index($0, anchor) { in_block=1 }
      in_block && !found && $0 ~ key " = \"" {
        sub(key " = \"[^\"]*\"", key " = \"" val "\"")
        found=1
      }
      { print }
    ' "$file" >"${file}.tmp" && mv "${file}.tmp" "$file"
  else
    sed -i "s|${key} = \"[^\"]*\"|${key} = \"${value}\"|" "$file"
  fi
}

# ---------------------------------------------------------------------------
# Lock-file generation
# ---------------------------------------------------------------------------

generate_lockfile() {
  local pkg="$1" version="$2" dest="$3"
  local tmpdir
  tmpdir=$(mktemp -d)

  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" EXIT

  pushd "$tmpdir" >/dev/null
  npm install "${pkg}@${version}" --package-lock-only 2>/dev/null ||
    die "npm install --package-lock-only failed for ${pkg}@${version}"
  popd >/dev/null

  cp "$tmpdir/package-lock.json" "$dest"
}

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

update_npm_package() {
  local requested_version="${1:-}"

  # --- guard: required config ---
  [[ -n ${NPM_PACKAGE:-} ]] || die "NPM_PACKAGE is not set"
  [[ -n ${NIX_FILE:-} ]] || die "NIX_FILE is not set"
  [[ -n ${LOCK_FILE:-} ]] || die "LOCK_FILE is not set"
  [[ -n ${PACKAGE_DISPLAY_NAME:-} ]] || die "PACKAGE_DISPLAY_NAME is not set"
  [[ -f $NIX_FILE ]] || die "Nix file not found: ${NIX_FILE}"

  check_prerequisites

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

  # --- read current version from nix file ---
  if [[ -n ${PACKAGE_ANCHOR:-} ]]; then
    OLD_VERSION=$(awk -v anchor="$PACKAGE_ANCHOR" '
      index($0, anchor) { found=1 }
      found && /version = "/ { gsub(/.*version = "/, ""); gsub(/".*/, ""); print; exit }
    ' "$NIX_FILE")
  else
    OLD_VERSION=$(grep 'version = "' "$NIX_FILE" | head -1 |
      sed 's/.*version = "\([^"]*\)".*/\1/')
  fi
  NEW_VERSION="$version"
  export OLD_VERSION NEW_VERSION

  info "Updating ${PACKAGE_DISPLAY_NAME}"
  field "current:" "$OLD_VERSION"
  field "target:" "$NEW_VERSION"

  if [[ $OLD_VERSION == "$NEW_VERSION" ]]; then
    ok "Already at version ${NEW_VERSION}"
    return 0
  fi

  # --- 1. source hash ---
  local src_url src_hash
  src_url=$(npm_tarball_url "$NPM_PACKAGE" "$NEW_VERSION")
  info "Fetching source hash…"
  src_hash=$(nix_prefetch_sri "$src_url")
  ok "hash = \"${src_hash}\""

  # --- 2. package-lock.json ---
  info "Generating package-lock.json…"
  generate_lockfile "$NPM_PACKAGE" "$NEW_VERSION" "$LOCK_FILE"
  ok "Updated ${LOCK_FILE##*/}"

  # --- 3. npm deps hash ---
  info "Computing npmDepsHash…"
  local npm_deps_hash
  npm_deps_hash=$(nix_npm_deps_hash "$LOCK_FILE")
  ok "npmDepsHash = \"${npm_deps_hash}\""

  # --- 4. patch nix file ---
  info "Patching ${NIX_FILE##*/}…"
  nix_set_field "$NIX_FILE" "version" "$NEW_VERSION"
  nix_set_field "$NIX_FILE" "hash" "$src_hash"
  nix_set_field "$NIX_FILE" "npmDepsHash" "$npm_deps_hash"
  ok "Done"

  # --- 5. summary ---
  echo ""
  info "${PACKAGE_DISPLAY_NAME}: ${OLD_VERSION} → ${NEW_VERSION}"
  echo ""
  git diff --stat "$NIX_FILE" "$LOCK_FILE" 2>/dev/null || true

  # --- 6. optional post-update hook ---
  if declare -F post_update_hook >/dev/null 2>&1; then
    echo ""
    post_update_hook
  fi
}
