#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NIX_FILE="$REPO_ROOT/users/jloos/modules/claude-code.nix"
LOCK_FILE="$REPO_ROOT/users/jloos/modules/claude-code/package-lock.json"

# Get version from argument or fetch latest
if [[ $# -ge 1 && $1 == "latest" ]]; then
  echo "Fetching latest version from GitHub tags..."
  VERSION=$(git ls-remote --tags --refs https://github.com/anthropics/claude-code |
    sed 's|.*refs/tags/||' |
    sed 's/^v//' |
    sort -V |
    tail -1)
elif [[ $# -ge 1 ]]; then
  VERSION="$1"
else
  echo "Usage: update-claude-code.sh <version|latest>"
  exit 1
fi

CURRENT_VERSION=$(grep 'version = "' "$NIX_FILE" | head -1 | sed 's/.*version = "\([^"]*\)".*/\1/')

echo "Current version: $CURRENT_VERSION"
echo "Target version:  $VERSION"

if [[ $CURRENT_VERSION == "$VERSION" ]]; then
  echo "Already at version $VERSION"
  exit 0
fi

echo ""
echo "==> Fetching source hash..."
SRC_HASH_RAW=$(nix-prefetch-url "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${VERSION}.tgz" 2>/dev/null)
SRC_HASH=$(nix hash convert --to sri --hash-algo sha256 "$SRC_HASH_RAW")
echo "Source hash: $SRC_HASH"

echo ""
echo "==> Generating package-lock.json..."
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
pushd "$TMPDIR" >/dev/null
npm install "@anthropic-ai/claude-code@${VERSION}" --package-lock-only 2>/dev/null
popd >/dev/null
cp "$TMPDIR/package-lock.json" "$LOCK_FILE"
echo "Updated: $LOCK_FILE"

echo ""
echo "==> Computing npmDepsHash..."
NPM_DEPS_HASH=$(nix run nixpkgs#prefetch-npm-deps -- "$LOCK_FILE" 2>/dev/null)
echo "npmDepsHash: $NPM_DEPS_HASH"

echo ""
echo "==> Updating $NIX_FILE..."

# Update version
sed -i "s/version = \"$CURRENT_VERSION\"/version = \"$VERSION\"/" "$NIX_FILE"

# Update source hash (match the specific line pattern)
sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"$SRC_HASH\"|" "$NIX_FILE"

# Update npmDepsHash
sed -i "s|npmDepsHash = \"sha256-[^\"]*\"|npmDepsHash = \"$NPM_DEPS_HASH\"|" "$NIX_FILE"

echo ""
echo "==> Done! Updated claude-code: $CURRENT_VERSION -> $VERSION"
echo ""
echo "Changes:"
git diff --stat "$NIX_FILE" "$LOCK_FILE" 2>/dev/null || true
