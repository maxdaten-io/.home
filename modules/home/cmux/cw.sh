# shellcheck shell=bash
# cw — one cmux workspace per git worktree, one claude session per workspace.
#
#   cw new <name>   from anywhere inside a repo: find-or-create the repo's cmux
#                   group, open a workspace in it running `claude -w <name>`,
#                   then a right pane (shell + lazygit tab) inside the worktree.
#   cw done         from the worktree's shell: refuse if anything would be lost,
#                   remove the worktree (through the repo's WorktreeRemove hooks
#                   if it declares any), close this workspace.
#
# Worktree creation is left to `claude -w` so per-repo WorktreeCreate hooks run
# (front-row-ai puts worktrees in ../<repo>.worktrees and builds a dev stack).
# Consequence: cw can't know the path up front, it diffs `git worktree list`.

usage() {
  cat >&2 <<'EOF'
usage: cw new <name>   new worktree workspace (claude -w <name>) in this repo's cmux group
       cw done         remove this worktree (refuses on unsaved work) and close its workspace
EOF
  exit 2
}

die() {
  echo "cw: $*" >&2
  exit 1
}

# Main checkout of the repo containing $1 — also correct from inside a worktree.
repo_root() {
  local common
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
    die "not inside a git repository: $1"
  dirname "$common"
}

worktree_paths() {
  git -C "$1" worktree list --porcelain | sed -n 's/^worktree //p'
}

# `--command` text is typed into the user's login shell (fish); single quotes
# are literal in both fish and bash as long as the path has none itself.
shell_quote() {
  [[ $1 != *"'"* ]] || die "path contains a single quote: $1"
  printf "'%s'" "$1"
}

ref_of() { sed -n 's/^OK \([a-z_]*:[0-9]*\).*/\1/p' | head -1; }

# Process signature of <surface>: its pids, one per line — or "busy" while any
# leaf process isn't fish (e.g. the devenv TUI, whose `.devenv-wrapped` only
# gets a fish child once the dev shell is up).
surface_sig() {
  cmux top --workspace "$1" --processes --format tsv |
    awk -F'\t' -v s="$2" '
      $4 == "process" { name[$5] = $7; parent[$5] = $6 }
      END {
        for (p in name) {
          for (q = p; ; q = parent[q]) {
            if (parent[q] == s) { mine[p] = 1; break }
            if (!(parent[q] in name)) break
          }
        }
        for (p in mine) if (parent[p] in mine) haskid[parent[p]] = 1
        for (p in mine) { if (!(p in haskid) && name[p] != "fish") { print "busy"; exit } print p }
      }' | sort | tr '\n' ' '
}

# Text typed into a fresh terminal is lost while devenv's auto-activation
# (fish_prompt event -> blocking `devenv shell` TUI) owns the tty. Wait until
# only shells are left and the process set has held still for 1.5s.
send_when_ready() {
  local ws=$1 surface=$2 text=$3 sig prev="" stable=0 deadline=$((SECONDS + 90))
  while ((stable < 3)); do
    ((SECONDS < deadline)) || die "shell in $surface not idle after 90s (last: '${sig}')"
    sleep 0.5
    sig=$(surface_sig "$ws" "$surface")
    if [[ -n $sig && $sig != *busy* && $sig == "$prev" ]]; then
      stable=$((stable + 1))
    else
      stable=0
    fi
    prev=$sig
  done
  cmux send --workspace "$ws" --surface "$surface" "$text" >/dev/null
  cmux send-key --workspace "$ws" --surface "$surface" enter >/dev/null
}

cmd_new() {
  local name=${1:-}
  [[ $name =~ ^[A-Za-z0-9._-]+$ ]] || die "name must match [A-Za-z0-9._-]+, got '${name}'"

  local root before group ws claude_surface
  root=$(repo_root "$PWD")
  before=$(worktree_paths "$root")

  group=$(cmux workspace-group create --name "$(basename "$root")" --cwd "$root" \
    --idempotency-key "cw:$root" --json | jq -er '.group.ref') ||
    die "could not find or create cmux group for $root"

  ws=$(cmux workspace create --name "$name" --cwd "$root" --group "$group" --focus true | ref_of)
  [[ -n $ws ]] || die "cmux workspace create returned no workspace ref"
  claude_surface=$(cmux list-panes --workspace "$ws" --json | jq -er '.panes[0].selected_surface_ref')
  send_when_ready "$ws" "$claude_surface" "claude -w $name"

  # Wait for claude (and any WorktreeCreate hook) to register the worktree.
  local wt="" deadline=$((SECONDS + 90))
  while [[ -z $wt ]]; do
    ((SECONDS < deadline)) || {
      echo "cw: no new worktree after 90s; claude pane says:" >&2
      cmux read-screen --workspace "$ws" --surface "$claude_surface" --lines 8 >&2 || true
      die "giving up (untrusted dir? run plain 'claude' there once and accept the trust dialog)"
    }
    sleep 1
    wt=$(comm -13 <(sort <<<"$before") <(worktree_paths "$root" | sort) | head -1)
  done

  shell_quote "$wt" >/dev/null # dies here, not inside a later $(...)
  # The stamp is how `cw done` finds this workspace again, and how the sidebar
  # learns the worktree path (the claude pane's cwd is the repo root, not $wt).
  cmux workspace-action --action set-description --workspace "$ws" --description "cw:$wt" >/dev/null

  # lazygit first, shell second: the newest tab ends up selected, and there is
  # no CLI verb to select a tab. lazygit gets explicit -w/-g instead of a `cd`:
  # inside a devenv shell, cd-ing out of the project exits that shell (devenv's
  # PWD hook) and drops the rest of the command line.
  local gitdir lazygit_surface shell_surface pane
  gitdir=$(git -C "$wt" rev-parse --absolute-git-dir)
  lazygit_surface=$(cmux new-split right --workspace "$ws" --surface "$claude_surface" | ref_of)
  [[ -n $lazygit_surface ]] || die "split failed; worktree is at $wt"
  pane=$(cmux list-panes --workspace "$ws" --json |
    jq -er --arg s "$lazygit_surface" '.panes[] | select(.surface_refs | index($s)) | .ref')
  shell_surface=$(cmux new-surface --pane "$pane" --workspace "$ws" --focus false | ref_of)
  [[ -n $shell_surface ]] || die "new tab failed; worktree is at $wt"
  send_when_ready "$ws" "$lazygit_surface" "lazygit -w $(shell_quote "$wt") -g $(shell_quote "$gitdir")"
  # A bare `cd` is fine: if it leaves a devenv shell, the parent follows to $wt.
  send_when_ready "$ws" "$shell_surface" "cd $(shell_quote "$wt")"
  cmux focus-pane --pane "$(cmux list-panes --workspace "$ws" --json | jq -er '.panes[0].ref')" \
    --workspace "$ws" >/dev/null

  echo "$ws  $wt"
}

# Runs every WorktreeRemove hook command declared in the repo's claude settings,
# with the same stdin/env contract claude uses. Returns 1 if none are declared.
run_remove_hooks() {
  local root=$1 wt=$2 cmds=() cmd f
  for f in "$root/.claude/settings.json" "$root/.claude/settings.local.json"; do
    [[ -f $f ]] || continue
    while IFS= read -r cmd; do cmds+=("$cmd"); done < <(
      jq -r '.hooks.WorktreeRemove[]?.hooks[]? | select(.type == "command") | .command' "$f"
    )
  done
  ((${#cmds[@]} > 0)) || return 1
  for cmd in "${cmds[@]}"; do
    (cd "$root" && jq -cn --arg p "$wt" '{path: $p}' | CLAUDE_PROJECT_DIR=$root bash -c "$cmd") ||
      echo "cw: hook exited non-zero: $cmd" >&2
  done
}

close_stamped() {
  local ws
  for ws in $(cmux workspace list --json |
    jq -r --arg d "cw:$1" '.workspaces[] | select(.description == $d) | .ref'); do
    # --force: the devenv shell counts as a running process; every data-loss
    # check has passed by the time we get here.
    cmux workspace close "$ws" --force >/dev/null
  done
}

cmd_done() {
  local wt root branch
  if ! wt=$(git rev-parse --show-toplevel 2>/dev/null); then
    # claude -w deletes a clean worktree itself on exit, leaving this shell in
    # a deleted directory; fall back to the workspace's stamp.
    local stamp
    stamp=$(cmux workspace list --json | jq -r --arg id "${CMUX_WORKSPACE_ID:-}" \
      '.workspaces[] | select(.id == $id or .ref == $id) | .description // empty')
    [[ $stamp == cw:* ]] || die "not inside a git worktree"
    wt=${stamp#cw:}
    [[ ! -e $wt ]] || die "$wt exists but is not a git worktree — inspect it by hand"
    echo "already removed by claude: $wt"
    close_stamped "$wt"
    return
  fi
  root=$(repo_root "$wt")
  [[ $wt != "$root" ]] || die "this is the main checkout ($root), not a worktree; run cw done from the worktree shell"
  branch=$(git -C "$wt" symbolic-ref --quiet --short HEAD || true)

  # 1. Nothing uncommitted (gitignored files don't count — same rule git uses).
  [[ -z $(git -C "$wt" status --porcelain) ]] ||
    die "uncommitted changes in $wt — commit, stash or discard first"

  # 2. No commit that exists only on this branch (not on any other branch or remote).
  local only
  if [[ -n $branch ]]; then
    only=$(git -C "$wt" rev-list --count HEAD --not --exclude="$branch" --branches --remotes)
  else
    only=$(git -C "$wt" rev-list --count HEAD --not --branches --remotes)
  fi
  ((only == 0)) || die "$only commit(s) on ${branch:-detached HEAD} exist nowhere else — push or merge first"

  # 3. claude -w locks its worktree ("claude session <name> (pid N ...)").
  local lock pid
  lock=$(git -C "$root" worktree list --porcelain |
    awk -v w="$wt" '$1=="worktree"{cur=substr($0,10)} cur==w && $1=="locked"{print substr($0,8)}')
  if [[ -n $lock ]]; then
    pid=$(sed -n 's/.*(pid \([0-9]*\).*/\1/p' <<<"$lock")
    if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
      die "claude (pid $pid) still holds $wt — exit it first"
    fi
    git -C "$root" worktree unlock "$wt"
  fi

  cd "$root" || die "cannot cd to $root"
  if ! run_remove_hooks "$root" "$wt"; then
    git -C "$root" worktree remove "$wt"
    [[ -z $branch ]] || git -C "$root" branch -d "$branch" >/dev/null 2>&1 ||
      echo "cw: kept branch $branch" >&2
  fi
  # Hooks fail silently by design (claude treats WorktreeRemove as non-blocking).
  # (captured first: `grep -q` + pipefail can turn an early exit into a false pass)
  local remaining
  remaining=$(worktree_paths "$root")
  ! grep -qxF "$wt" <<<"$remaining" || die "worktree still registered after removal: $wt"

  echo "removed $wt"
  # Close only workspaces stamped by `cw new` for this worktree — never "the
  # current one", which may be any terminal that happened to cd here.
  close_stamped "$wt"
}

case ${1:-} in
new) shift && cmd_new "$@" ;;
done) shift && cmd_done "$@" ;;
*) usage ;;
esac
