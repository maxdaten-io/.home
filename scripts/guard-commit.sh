#!/usr/bin/env bash
# Claude Code PreToolUse hook (Bash): reject commands that stage the whole
# tree. Parallel sessions share this checkout (worktree.bgIsolation = "none"),
# so `git commit -a` / `git add -A` sweeps another session's WIP into your
# commit — it happened in 5aa45c1. Exit 2 blocks the call and shows stderr
# to the agent.
set -euo pipefail

cmd=$(jq -r '.tool_input.command // empty')

git='git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+'
commit_all="${git}commit[^;&|]*[[:space:]](-[[:alnum:]]*a[[:alnum:]]*|--all)([[:space:]]|$)"
add_all="${git}add[^;&|]*[[:space:]](-A|--all|-u|--update|\.)([[:space:]]|$)"

if grep -qE -e "$commit_all" -e "$add_all" <<<"$cmd"; then
  cat >&2 <<'EOF'
Blocked: this stages the whole tree, and parallel sessions share this checkout.
Stage the paths you changed by name, then commit:
  git add path/one path/two && git commit -m "..."
Check `git status` first; leave changes you didn't make unstaged.
EOF
  exit 2
fi
