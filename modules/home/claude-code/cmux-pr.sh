# shellcheck shell=bash
# Claude hook (SessionStart, Notification): attach the agent's worktree PR to
# its cmux workspace. cmux finds PRs from the workspace shell's branch, which
# for `claude -w` is the root checkout, never the worktree the agent works in.
# Root sessions are left to cmux: a manual link would pin over its detection.
[ -n "${CMUX_WORKSPACE_ID:-}" ] || exit 0
cwd=$(jq -r '.cwd // empty')
[ -n "$cwd" ] && cd "$cwd" || exit 0
# A linked worktree has its own git dir, distinct from the shared common one.
[ "$(git rev-parse --git-dir 2>/dev/null)" != "$(git rev-parse --git-common-dir 2>/dev/null)" ] || exit 0
branch=$(git branch --show-current) && [ -n "$branch" ] || exit 0
(
  # The cwd's repo, not an inherited GH_REPO. A stale GITHUB_TOKEN shadows the
  # keyring login, so a failed call retries without it; `cmux pr` resolves the
  # PR through the same auth, so it runs in whichever env worked. `pr list`
  # exits 0 with no output when there is no PR; only that clears, never a
  # failed lookup.
  q() { env -u GH_REPO "$@" gh pr list --head "$branch" --state all -L 1 --json number -q '.[0].number // empty'; }
  unset=(-u GH_REPO)
  n=$(q) || { unset+=(-u GITHUB_TOKEN) && n=$(q -u GITHUB_TOKEN); } || exit 0
  if [ -n "$n" ]; then
    env "${unset[@]}" cmux pr "$n" --workspace "$CMUX_WORKSPACE_ID"
  else
    env "${unset[@]}" cmux pr clear --workspace "$CMUX_WORKSPACE_ID"
  fi
) >/dev/null 2>&1 &
