# shellcheck shell=bash
# cs — fzf over claude sessions, resume the pick right here.
#
#   cs [dir]   dir defaults to $PWD. Inside git, "the repo" is the main checkout
#              plus its worktrees (<root>/… and <root>.worktrees/…), so a
#              session started in any worktree shows up from anywhere in it.
#              Outside git: sessions whose cwd is dir or below it.
#   cs -a      start on every session of both accounts; profile, repo and
#              worktree are columns, so typing "frontrow katchup" filters by them.
#   --rex      enter opens the session in a new Rex tab instead of exec'ing it
#              here (the init.lua popup runs `cs --rex` in the pane's directory).
#
# ctrl-a toggles between dir's repo and all sessions. ctrl-/ toggles content
# search: the query's words must all appear in the transcript (rg,
# case-insensitive, raw JSONL so tool output counts too).
#
# Index and preview come from sessions-lib.sh (shared with `cw sessions`, same
# cache). Unlike cw, no cmux: enter cds into the session's directory (the root
# if that worktree is gone) and execs claude under the account that owns the
# transcript.

# Main checkout for $1, or $1 itself outside git. A worktree's common dir is
# <root>/.git; anything else (submodule) keeps its own toplevel.
repo_root() {
  local out common
  if out=$(git -C "$1" rev-parse --path-format=absolute --show-toplevel --git-common-dir 2>/dev/null); then
    common=${out#*$'\n'}
    [[ $common == */.git ]] && echo "${common%/.git}" || echo "${out%%$'\n'*}"
  else
    (cd "$1" && pwd -P)
  fi
}

# Records: file, cwd, account dir, tab label, display — newest first.
# root "" lists every session; the repo is then guessed from the path alone
# (no git per row: ~700 transcripts) by stripping the two worktree layouts.
list_repo_sessions() {
  local root=$1 now mtime f cwd branch title rel repo prof disp AGE
  [[ -f $CACHE ]] || return 0
  now=$(date +%s)
  sort -t $'\t' -k1,1nr "$CACHE" | while IFS=$'\t' read -r mtime f cwd branch title; do
    [[ -n $cwd ]] || continue
    if [[ -n $root ]]; then
      repo=$root
      case $cwd in "$root" | "$root"/* | "$root".worktrees/*) ;; *) continue ;; esac
    else
      repo=${cwd%%/.claude/worktrees/*}
      [[ $repo != "$cwd" || $cwd != *.worktrees/* ]] || repo=${cwd%%.worktrees/*}
    fi
    rel=${cwd#"$repo"} rel=${rel#/} rel=${rel#.claude/worktrees/} rel=${rel#.worktrees/}
    [[ -d $cwd ]] || rel+="${rel:+ }(gone)"
    fmt_age $((now - mtime))
    title=${title#"${title%%[! ]*}"} title=${title%"${title##*[! ]}"}
    disp=$'\e[2m'$AGE$'\e[0m  '
    if [[ -z $root ]]; then
      prof=${f%%/projects/*} prof=${prof##*/.claude} prof=${prof#-}
      disp+=$'\e[35m'${prof:-private}$'\e[0m \e[34m'${repo##*/}$'\e[0m  '
    fi
    disp+=$title
    [[ -z $rel ]] || disp+=$'  \e[33m▸ '$rel$'\e[0m'
    [[ -z $branch || $branch == main || $branch == master || $rel == *"${branch#worktree-}"* ]] ||
      disp+=$'  \e[2m('$branch$')\e[0m'
    printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$cwd" "${f%%/projects/*}" "${title:0:40}" "$disp"
  done
}

# list_repo_sessions narrowed to transcripts containing every word of $2.
# Each rg pass only reads the survivors of the last; ~70ms over 1 GB warm.
content_sessions() {
  local root=$1 terms t f files=()
  read -ra terms <<<"$2"
  shopt -s nullglob
  for t in "${SESSION_DIRS[@]}"; do files+=("$t"/*/*.jsonl); done
  shopt -u nullglob
  for t in "${terms[@]}"; do
    ((${#files[@]})) || break
    mapfile -t files < <(rg -l -F -i -- "$t" "${files[@]}" || true)
  done
  local -A hit=()
  for f in "${files[@]}"; do hit[$f]=1; done
  list_repo_sessions "$root" | while IFS= read -r line; do
    [[ -z ${hit[${line%%$'\t'*}]:-} ]] || printf '%s\n' "$line"
  done
}

# Scope (repo or all) lives in the file CS_SCOPE so fzf callbacks can read and
# flip it; the repo root in CS_REPO. Env, not argv: "" (all) would not survive
# fzf's transform quoting. The query comes from fzf's own FZF_QUERY.
scope_root() { [[ $(<"$CS_SCOPE") == all ]] || echo "$CS_REPO"; }
scope_label() { [[ $(<"$CS_SCOPE") == all ]] && echo claude || echo "${CS_REPO##*/}"; }
self=${CS_SELF:-$0}

case ${1:-} in
--list) list_repo_sessions "$(scope_root)" && exit ;;
--refresh) index_sessions && list_repo_sessions "$(scope_root)" && exit ;;
--content) content_sessions "$(scope_root)" "${FZF_QUERY-}" && exit ;;
--preview) shift && preview_session "$@" && exit ;;
# The two toggles print fzf actions for `transform:`. Content mode is "prompt
# starts with grep": fzf's own matching is off, each keystroke reloads from rg.
--toggle-scope)
  [[ $(<"$CS_SCOPE") == all ]] && echo repo >"$CS_SCOPE" || echo all >"$CS_SCOPE"
  if [[ ${FZF_PROMPT-} == grep* ]]; then
    echo "change-prompt(grep $(scope_label) › )+reload($self --content)"
  else
    echo "change-prompt($(scope_label) › )+reload($self --list)"
  fi
  exit
  ;;
--toggle-grep)
  if [[ ${FZF_PROMPT-} == grep* ]]; then
    echo "change-prompt($(scope_label) › )+enable-search+reload($self --list)"
  else
    echo "change-prompt(grep $(scope_label) › )+disable-search+reload($self --content)"
  fi
  exit
  ;;
-h | --help)
  echo "usage: cs [-a] [--rex] [dir]   pick a claude session of dir's repo (default \$PWD), or of all repos (-a), and resume it" >&2
  exit 2
  ;;
esac

all=0 rex=0
while [[ ${1:-} == -* ]]; do
  case $1 in
  -a | --all) all=1 ;;
  --rex) rex=1 ;;
  *) echo "cs: unknown flag $1" >&2 && exit 2 ;;
  esac
  shift
done

CS_REPO=$(repo_root "${1:-$PWD}") || exit 1
CS_SCOPE=$(mktemp "${TMPDIR:-/tmp}/cs-scope.XXXXXX")
export CS_REPO CS_SCOPE
trap 'rm -f "$CS_SCOPE"' EXIT
((all)) && echo all >"$CS_SCOPE" || echo repo >"$CS_SCOPE"
q=$(printf '%q' "$CS_REPO")
if [[ ! -f $CACHE ]]; then
  echo "cs: first run, indexing all transcripts (can take ~1 min)…" >&2
  index_sessions
fi

# Opens at once on the cached list; the start binding re-indexes behind it.
# Process substitution, not a pipe: the reload abandons the initial stream, its
# writer dies of SIGPIPE, and under pipefail that failed the whole pick.
pick=$(fzf --ansi --delimiter $'\t' --with-nth 5 --with-shell 'bash -c' \
  --no-sort --layout=reverse --info=inline-right --prompt "$(scope_label) › " \
  --header 'enter resume · ctrl-a repo/all · ctrl-/ search content · ctrl-r refresh' \
  --preview "$self --preview {1} {2} $q" --preview-window 'down,45%,wrap,border-top' \
  --bind "start:reload($self --refresh)" \
  --bind "ctrl-r:reload($self --refresh)" \
  --bind "ctrl-a:transform:$self --toggle-scope" \
  --bind "ctrl-/:transform:$self --toggle-grep" \
  --bind "change:transform:[[ \$FZF_PROMPT != grep* ]] || echo 'reload($self --content)'" \
  < <(list_repo_sessions "$(scope_root)")) || exit 0
rm -f "$CS_SCOPE" # exec below skips the EXIT trap

IFS=$'\t' read -r f cwd account label _ <<<"$pick"
dir=$cwd
if [[ ! -d $dir ]]; then # worktree gone: its repo (same guess as the list), else ~
  dir=${cwd%%/.claude/worktrees/*} dir=${dir%%.worktrees/*}
  [[ -d $dir ]] || dir=$HOME
fi
id=$(basename "$f" .jsonl)
if ((rex)); then
  exec rex window new -s "$REX_SESSION" "$label" -c "$dir" -- env CLAUDE_CONFIG_DIR="$account" claude --resume "$id"
fi
cd "$dir" || exit 1
exec env CLAUDE_CONFIG_DIR="$account" claude --resume "$id"
