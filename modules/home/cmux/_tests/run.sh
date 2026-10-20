#!/usr/bin/env bash
# Offline checks for sidebars/worktrees.js: syntax, then each test stubs the
# cmux runtime and runs a slice of the file. Slices are cut at comment markers
# ("// --- model", "// Collapsed sections", ...), so renaming one fails here.
# harness.mjs has no assertions; it must run without throwing and prints the
# entries() tree for eyeballing. Live check (needs the app): `cmux sidebar
# validate worktrees`.
set -euo pipefail
cd "$(dirname "$0")"
js=../sidebars/worktrees.js

node --check "$js"
for t in cap-test.mjs fold-test.mjs name-test.mjs stamp-test.mjs; do
  node "$t" "$js" >/dev/null || {
    node "$t" "$js"
    exit 1
  }
done
node harness.mjs "$js" >/dev/null
echo "worktrees.js: syntax + 4 tests + harness ok"
