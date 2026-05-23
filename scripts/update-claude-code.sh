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
# OLD_VERSION / NEW_VERSION are exported by the sourced lib at call time.
# shellcheck disable=SC2153
post_update_hook() {
  local changelog
  info "Changelog (${OLD_VERSION} → ${NEW_VERSION}):"
  echo ""

  changelog=$(curl -fsSL "${GITHUB_REPO}/raw/refs/heads/main/CHANGELOG.md" 2>/dev/null) || {
    warn "Could not fetch changelog"
    return 0
  }

  # Print per-version sections oldest-first so the newest lands near the prompt.
  local sections
  sections=$(echo "$changelog" | awk -v target="$NEW_VERSION" -v current="$OLD_VERSION" '
    /^## / {
      v = $2
      gsub(/^v/, "", v)
      if (v == target)       { printing = 1; idx++; versions[idx] = v }
      else if (v == current) { printing = 0 }
      else if (printing)     { idx++; versions[idx] = v }
      next
    }
    printing { sections[idx] = sections[idx] $0 "\n" }
    END {
      for (i = idx; i >= 1; i--) {
        printf "## %s\n\n%s", versions[i], sections[i]
      }
    }
  ')

  printf "%s" "$sections"

  # Ask claude itself to pick out the most impactful changes. Best-effort —
  # if claude is unavailable (fresh install, offline, rate-limited) we skip
  # the highlights and the per-version detail above is still useful.
  if [ -z "$sections" ] || ! command -v claude >/dev/null 2>&1; then
    return 0
  fi

  # Only summarize the newest version — the user has already glanced past
  # the older sections by the time they read the highlights at the prompt.
  local newest_section
  newest_section=$(echo "$changelog" | awk -v target="$NEW_VERSION" '
    /^## / {
      v = $2
      gsub(/^v/, "", v)
      if (v == target) { printing = 1; print; next }
      else if (printing) { exit }
    }
    printing { print }
  ')

  if [ -z "$newest_section" ]; then
    return 0
  fi

  printf "\n## Highlights (%s)\n\n" "$NEW_VERSION"
  local prompt="Summarize the most interesting and impactful changes from this claude-code release as 5-8 short bullets. Focus on new features, behavior changes, and renamed/breaking items — skip routine bug fixes unless they fix something widely impactful. Output only the bullets, no preamble or trailing commentary."
  printf "%s" "$newest_section" | claude -p "$prompt" 2>/dev/null || {
    warn "claude -p failed — skipping highlights"
  }
}

# ---------------------------------------------------------------------------
# Claude-code-specific hash/version patching
#
# The generic nix_set_field helpers in update-npm-package.sh do not work
# for this nix file because:
#
#   1. The version is stored as `claudeCodeVersion = "x.y.z"` — the capital
#      V means nix_set_field "version" (which looks for `version = "`) never
#      matches, so the version string is never updated.
#
#   2. The file contains multiple `hash = "..."` fields: four sha512 hashes
#      inside nativePlatforms (one per platform) and one sha256 inside the
#      `src = pkgs.fetchurl` block.  nix_set_field "hash" hits the first one
#      it finds after the anchor — which is the aarch64-darwin native hash —
#      and corrupts it with a sha256 value.
#
#   3. The native platform hashes are never updated at all; the library has
#      no concept of them.
#
# We call update_npm_package for the things it does correctly (lockfile and
# npmDepsHash), then run three targeted fixups below.
# ---------------------------------------------------------------------------

# Fix 1 – version
# Patch `claudeCodeVersion = "..."` directly with sed.
_fix_version() {
  local new_version="$1"
  sed -i "s|claudeCodeVersion = \"[^\"]*\"|claudeCodeVersion = \"${new_version}\"|" "$NIX_FILE"
  ok "claudeCodeVersion = \"${new_version}\""
}

# Fix 2 – src hash
# Fetch the main npm tarball and compute a sha256 SRI hash, then write it
# only into the `src = pkgs.fetchurl` block.
_fix_src_hash() {
  local version="$1"
  local url="https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz"
  info "Fetching src hash for ${version}…"
  local raw sri
  raw=$(nix-prefetch-url "$url" 2>/dev/null) || die "nix-prefetch-url failed for ${url}"
  sri=$(nix hash convert --to sri --hash-algo sha256 "$raw")
  awk -v val="$sri" '
    /src = pkgs\.fetchurl/ { in_src=1 }
    in_src && /hash = "/ {
      sub(/hash = "[^"]*"/, "hash = \"" val "\"")
      in_src=0
    }
    { print }
  ' "$NIX_FILE" >"${NIX_FILE}.tmp" && mv "${NIX_FILE}.tmp" "$NIX_FILE"
  ok "src hash = \"${sri}\""
}

# Fix 3 – native platform hashes
# The per-platform binary tarballs are published as separate npm packages
# (@anthropic-ai/claude-code-darwin-arm64, etc.) whose dist.integrity fields
# are sha512 SRI strings — exactly what goes in the nix file.
_fix_native_hashes() {
  local version="$1"
  info "Updating native platform hashes…"

  # Format: "nix-system:npm-suffix"
  local platforms=(
    "aarch64-darwin:darwin-arm64"
    "x86_64-darwin:darwin-x64"
    "aarch64-linux:linux-arm64"
    "x86_64-linux:linux-x64"
  )

  for entry in "${platforms[@]}"; do
    local nix_system="${entry%%:*}"
    local suffix="${entry##*:}"
    local pkg="@anthropic-ai/claude-code-${suffix}"
    local integrity
    integrity=$(npm view "${pkg}@${version}" dist.integrity 2>/dev/null) || {
      warn "Could not fetch integrity for ${pkg}@${version} — skipping"
      continue
    }
    # Patch the hash on the line immediately following `"nix_system" = {`
    awk -v target="\"${nix_system}\"" -v val="$integrity" '
      index($0, target) && index($0, "= {") { in_block=1; print; next }
      in_block && /hash = "/ {
        sub(/hash = "[^"]*"/, "hash = \"" val "\"")
        in_block=0
      }
      { print }
    ' "$NIX_FILE" >"${NIX_FILE}.tmp" && mv "${NIX_FILE}.tmp" "$NIX_FILE"
    ok "${nix_system}: ${integrity:0:40}…"
  done
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
# shellcheck disable=SC1091 source=lib/update-npm-package.sh
source "$SCRIPT_DIR/lib/update-npm-package.sh"

# The library correctly handles: lockfile generation, npmDepsHash.
# It does NOT correctly handle version or any of the hash fields — see above.
update_npm_package "${1:-}"

# Apply the three targeted fixups now that OLD_VERSION / NEW_VERSION are set.
info "Applying claude-code-specific patches…"
_fix_version "$NEW_VERSION"
_fix_src_hash "$NEW_VERSION"
_fix_native_hashes "$NEW_VERSION"
