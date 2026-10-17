# shellcheck shell=bash
# cw — one cmux workspace per git worktree, one claude session per workspace.
#
#   cw new <name>   from anywhere inside a repo: find-or-create the repo's cmux
#                   group, open a workspace in it running `claude -w <name>`,
#                   then a right pane (shell + lazygit tab) inside the worktree.
#   cw done         from the worktree's shell: refuse if anything would be lost,
#                   remove the worktree (through the repo's WorktreeRemove hooks
#                   if it declares any), close this workspace.
#   cw sessions     fzf list of past claude sessions from both accounts, grouped
#                   by main checkout; enter resumes one in a new workspace.
#                   (cmux Vault covers the 30 most recent per account.)
#
# Worktree creation is left to `claude -w` so per-repo WorktreeCreate hooks run
# (front-row-ai puts worktrees in ../<repo>.worktrees and builds a dev stack).
# Consequence: cw can't know the path up front, it diffs `git worktree list`.

usage() {
  cat >&2 <<'EOF'
usage: cw new <name>   new worktree workspace (claude -w <name>) in this repo's cmux group
       cw done         remove this worktree (refuses on unsaved work) and close its workspace
       cw sessions     browse and resume past claude sessions (both accounts)
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
  local ids=refs
  [[ $2 == *:* ]] || ids=uuids # same id form as the caller holds
  cmux --id-format "$ids" top --workspace "$1" --processes --format tsv |
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

# --- sessions: Vault-like history across both claude accounts ------------------
# cmux's Vault (with the claude-work agent from cmux.nix) shows ~30 sessions per
# account, grouped by folder name; this reads every transcript of both
# accounts and groups them by main checkout via real git, so any
# worktree shows up however it was started.
#
# Cache: one TSV row per transcript, re-extracted only when its mtime changes:
#   mtime  file  cwd  branch  title
SESSION_DIRS=("$HOME/.claude/projects" "$HOME/.claude-frontrow/projects")
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/cw/sessions.tsv
WORK_PREFIX=$HOME/Developer/frontrow/

oneline() { tr '\t\n\r' '   ' | cut -c1-160; }

# Transcripts run to tens of MB: never parse one whole. The last top-level
# `cwd` wins (tac reads from the end); title is /rename > claude's ai-title >
# first real prompt. Title records repeat through the file, the last is current.
# `|| true`: grep -m1 / head close the pipe early, which pipefail reports.
extract_session() {
  local f=$1 meta title
  meta=$(tac "$f" | grep '"cwd":' | head -n 20 |
    jq -r 'select(.cwd) | [.cwd, (.gitBranch // "")] | @tsv' 2>/dev/null | head -1) || true
  if [[ -z $meta ]]; then
    printf '%s\t\t\t\n' "$f" # no message ever recorded a cwd: cache as empty
    return
  fi
  title=$(grep '"type":"custom-title"' "$f" | tail -1 | jq -r '.customTitle // empty' 2>/dev/null) || true
  [[ -n $title ]] ||
    title=$(grep '"type":"ai-title"' "$f" | tail -1 | jq -r '.aiTitle // empty' 2>/dev/null) || true
  [[ -n $title ]] || title=$(head -n 200 "$f" | jq -r '
      select(.type == "user" and (.isMeta | not)) | .message.content
      | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join(" ")) end
      | select(length > 0 and (startswith("<") | not))' 2>/dev/null | head -1) || true
  printf '%s\t%s\t%s\n' "$f" "$meta" "$(oneline <<<"${title:-(untitled)}")"
}

index_sessions() {
  mkdir -p "${CACHE%/*}"
  local -A cached=()
  local line rest f mtime d tmp
  if [[ -f $CACHE ]]; then
    while IFS= read -r line; do
      rest=${line#*$'\t'}
      cached[${rest%%$'\t'*}]=$line
    done <"$CACHE"
  fi
  local files=()
  shopt -s nullglob
  for d in "${SESSION_DIRS[@]}"; do files+=("$d"/*/*.jsonl); done
  shopt -u nullglob
  ((${#files[@]})) || return 0
  tmp=$(mktemp "${CACHE}.XXXXXX")
  while IFS=$'\t' read -r mtime f; do
    line=${cached[$f]:-}
    if [[ ${line%%$'\t'*} == "$mtime" ]]; then
      printf '%s\n' "$line"
    else
      printf '%s\t%s\n' "$mtime" "$(extract_session "$f")"
    fi
  done < <(stat -c $'%Y\t%n' "${files[@]}") >"$tmp"
  mv "$tmp" "$CACHE"
}

# Sets AGE (no subshell: list_sessions calls this for every row).
fmt_age() {
  local s=$1
  if ((s < 3600)); then
    AGE="$((s / 60))m"
  elif ((s < 86400)); then
    AGE="$((s / 3600))h"
  elif ((s < 604800)); then
    AGE="$((s / 86400))d"
  else AGE="$((s / 604800))w"; fi
}

# cwd -> ROOT, LABEL (globals, memoized: ~150 distinct dirs vs ~750 rows).
# Real git where the directory still exists; for deleted worktrees fall back
# to the two layouts we create them in. Root is the parent of the common dir
# only when that is a plain `.git`; submodules (Meet-Commit, mealieservice,
# maxdaten.io) keep theirs in the superproject's .git/modules/.
declare -A RESOLVED=()
resolve_cwd() {
  local cwd=$1 out top common label=""
  if [[ -n ${RESOLVED[$cwd]:-} ]]; then
    ROOT=${RESOLVED[$cwd]%%$'\t'*}
    LABEL=${RESOLVED[$cwd]#*$'\t'}
    return
  fi
  # A leftover worktree dir without .git would resolve to whatever repo encloses
  # it (~/Developer/frontrow is one), so a layout path must be its own toplevel.
  local wt=""
  [[ $cwd =~ ^(.*/\.claude/worktrees/[^/]+) || $cwd =~ ^(.*\.worktrees/[^/]+) ]] && wt=${BASH_REMATCH[1]}
  if out=$(git -C "$cwd" rev-parse --path-format=absolute --show-toplevel --git-common-dir 2>/dev/null) &&
    [[ -z $wt || ${out%%$'\n'*} == "$wt" ]]; then
    top=${out%%$'\n'*}
    common=${out#*$'\n'}
    if [[ $common == */.git ]]; then
      ROOT=${common%/.git}
    else
      # Submodule (or a worktree of one): its git dir records the checkout.
      ROOT=$(git --git-dir="$common" rev-parse --path-format=absolute --show-toplevel 2>/dev/null) || ROOT=$top
    fi
    [[ $top == "$ROOT" ]] || label=${top##*/}
    [[ $cwd == "$top" ]] || label+=${label:+/}${cwd#"$top"/}
  elif [[ $cwd =~ ^(.*)/\.claude/worktrees/([^/]+) || $cwd =~ ^(.*)\.worktrees/([^/]+) ]]; then
    ROOT=${BASH_REMATCH[1]}
    label="${BASH_REMATCH[2]} (gone)"
  else
    ROOT=$cwd
    [[ -d $cwd ]] || label="(gone)"
  fi
  LABEL=$label
  RESOLVED[$cwd]=$ROOT$'\t'$LABEL
}

# fzf records (NUL-separated): file, cwd, root, account dir, two-line display —
# WORK first, repos by their newest session, sessions newest first.
list_sessions() {
  [[ -f $CACHE ]] || return 0
  local now mtime f cwd branch title section disp ROOT LABEL AGE
  now=$(date +%s)
  while IFS=$'\t' read -r mtime f cwd branch title; do
    [[ -n $cwd ]] || continue
    resolve_cwd "$cwd"
    [[ $ROOT/ == "$WORK_PREFIX"* ]] && section=0 || section=1
    # Two lines like Vault: "age  title" / dim "repo ▸ worktree (branch)".
    # \x1f stands in for the line break until the final tr (see below).
    fmt_age $((now - mtime))
    title=${title#"${title%%[! ]*}"} # ai-titles can carry leading spaces
    disp=$'\e[2m'$AGE$'\e[0m  '$title$'\x1f    \e[2m'${ROOT##*/}
    [[ -z $LABEL ]] || disp+=$' \e[0;33m▸ '$LABEL$'\e[0;2m'
    [[ -z $branch || $branch == main || $branch == master || $branch == development ]] ||
      [[ $LABEL == *"$branch"* || $branch == "worktree-${LABEL%% *}" ]] || disp+=" ($branch)"
    disp+=$'\e[0m'
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$section" "$mtime" "$f" "$cwd" "$ROOT" "${f%%/projects/*}" "$disp"
  done <"$CACHE" |
    awk -F'\t' -v OFS='\t' '{ rows[NR] = $0; root[NR] = $5; if ($2 > top[$5]) top[$5] = $2 }
      END { for (i = 1; i <= NR; i++) print top[root[i]], rows[i] }' |
    sort -t $'\t' -k2,2n -k1,1nr -k6,6 -k3,3nr | cut -f4- |
    tr '\n\037' '\000\n' # NUL-separated records, real newline inside: fzf --read0
}

preview_session() {
  local f=$1 cwd=$2 root=$3
  printf '\e[1m%s\e[0m\n' "$(grep -F -- "$f" "$CACHE" | cut -f5 | head -1)"
  printf '\e[2m%s  ·  %s\e[0m\n' "${cwd/#$HOME/\~}" "$(date -r "$f" '+%Y-%m-%d %H:%M')"
  [[ -d $cwd ]] || printf '\e[33mworktree gone — resumes in %s\e[0m\n' "${root/#$HOME/\~}"
  echo
  tac "$f" | grep -m 60 -E '"type":"(user|assistant)"' | tac | jq -r '
      select((.type == "user" or .type == "assistant") and (.isMeta | not))
      | (.message.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join(" ")) end) as $t
      | select(($t | length) > 0 and ($t | startswith("<") | not))
      | (if .type == "user" then "\u001b[36m▶ " else "  " end) + ($t | gsub("\\s+"; " ") | .[0:400]) + "\u001b[0m"' \
    2>/dev/null | tail -n 12 || true
}

# New workspace at the session's directory (main checkout if the worktree is
# gone), resumed under the account that owns the transcript.
resume_session() {
  local f=$1 cwd=$2 root=$3 account=$4 dir id title out ws surface
  id=$(basename "$f" .jsonl)
  dir=$cwd
  [[ -d $dir ]] || dir=$root
  [[ -d $dir ]] || die "neither $cwd nor $root exists"
  title=$(grep -F -- "$f" "$CACHE" | cut -f5 | head -1 | cut -c1-40)
  # UUIDs, not workspace:N refs: from a Dock terminal, refs resolve against the
  # Dock's socket capability, where the new workspace isn't found.
  out=$(cmux --id-format uuids workspace create --name "↺ ${title:-$id}" --cwd "$dir" --focus true --json) ||
    die "cmux workspace create failed"
  ws=$(jq -er '.workspace_id' <<<"$out")
  surface=$(jq -er '.surface_id' <<<"$out")
  send_when_ready "$ws" "$surface" "env CLAUDE_CONFIG_DIR=$(shell_quote "$account") claude --resume $id"
}

cmd_sessions() {
  case ${1:-} in
  --list) list_sessions && return ;;
  --refresh) index_sessions && list_sessions && return ;;
  --preview) shift && preview_session "$@" && return ;;
  --resume)
    shift
    resume_session "$@" >>"${CACHE%/*}/resume.log" 2>&1
    return
    ;;
  esac
  # CW_SELF lets an unbuilt checkout be tested (`CW_SELF="bash cw.sh"`).
  local self=${CW_SELF:-$0} out
  mkdir -p "${CACHE%/*}"
  while :; do
    # Opens at once on the cached list; the start binding re-indexes behind it.
    out=$(list_sessions | fzf --read0 --ansi --delimiter $'\t' --with-nth 5 --with-shell 'bash -c' \
      --no-sort --highlight-line --layout=reverse --info=inline-right --prompt 'session › ' \
      --header 'enter resume · ctrl-r refresh · esc reset · ctrl-q quit' \
      --preview "$self sessions --preview {1} {2} {3}" --preview-window 'down,45%,wrap,border-top' \
      --bind "start:reload($self sessions --refresh)" \
      --bind "ctrl-r:reload($self sessions --refresh)" \
      --bind "enter:execute-silent(nohup $self sessions --resume {1} {2} {3} {4} >/dev/null 2>&1 &)" \
      --expect ctrl-q) || true
    [[ ${out%%$'\n'*} != ctrl-q ]] || break
  done
}

case ${1:-} in
new) shift && cmd_new "$@" ;;
done) shift && cmd_done "$@" ;;
sessions) shift && cmd_sessions "$@" ;;
*) usage ;;
esac
