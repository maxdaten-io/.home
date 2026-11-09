# shellcheck shell=bash
# cs — fzf over the claude sessions of one repo, resume the pick right here.
#
#   cs [dir]   dir defaults to $PWD. Inside git, "the repo" is the main checkout
#              plus its worktrees (<root>/… and <root>.worktrees/…), so a
#              session started in any worktree shows up from anywhere in it.
#              Outside git: sessions whose cwd is dir or below it.
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

# Records: file, cwd, account dir, display — newest first.
list_repo_sessions() {
  local root=$1 now mtime f cwd branch title rel disp AGE
  [[ -f $CACHE ]] || return 0
  now=$(date +%s)
  sort -t $'\t' -k1,1nr "$CACHE" | while IFS=$'\t' read -r mtime f cwd branch title; do
    case $cwd in
    "$root") rel="" ;;
    "$root"/* | "$root".worktrees/*)
      rel=${cwd#"$root"} rel=${rel#/} rel=${rel#.claude/worktrees/} rel=${rel#.worktrees/}
      ;;
    *) continue ;;
    esac
    [[ -d $cwd ]] || rel+="${rel:+ }(gone)"
    fmt_age $((now - mtime))
    title=${title#"${title%%[! ]*}"}
    disp=$'\e[2m'$AGE$'\e[0m  '$title
    [[ -z $rel ]] || disp+=$'  \e[33m▸ '$rel$'\e[0m'
    [[ -z $branch || $branch == main || $branch == master || $rel == *"${branch#worktree-}"* ]] ||
      disp+=$'  \e[2m('$branch$')\e[0m'
    printf '%s\t%s\t%s\t%s\n' "$f" "$cwd" "${f%%/projects/*}" "$disp"
  done
}

case ${1:-} in
--list) list_repo_sessions "$2" && exit ;;
--refresh) index_sessions && list_repo_sessions "$2" && exit ;;
--preview) shift && preview_session "$@" && exit ;;
-h | --help)
  echo "usage: cs [dir]   pick a claude session of dir's repo (default \$PWD) and resume it" >&2
  exit 2
  ;;
esac

root=$(repo_root "${1:-$PWD}") || exit 1
self=${CS_SELF:-$0}
q=$(printf '%q' "$root")
if [[ ! -f $CACHE ]]; then
  echo "cs: first run, indexing all transcripts (can take ~1 min)…" >&2
  index_sessions
fi

# Opens at once on the cached list; the start binding re-indexes behind it.
# Process substitution, not a pipe: the reload abandons the initial stream, its
# writer dies of SIGPIPE, and under pipefail that failed the whole pick.
pick=$(fzf --ansi --delimiter $'\t' --with-nth 4 --with-shell 'bash -c' \
  --no-sort --layout=reverse --info=inline-right --prompt "${root##*/} › " \
  --header 'enter resume · ctrl-r refresh' \
  --preview "$self --preview {1} {2} $q" --preview-window 'down,45%,wrap,border-top' \
  --bind "start:reload($self --refresh $q)" \
  --bind "ctrl-r:reload($self --refresh $q)" < <(list_repo_sessions "$root")) || exit 0

IFS=$'\t' read -r f cwd account _ <<<"$pick"
dir=$cwd
[[ -d $dir ]] || dir=$root
cd "$dir" || exit 1
exec env CLAUDE_CONFIG_DIR="$account" claude --resume "$(basename "$f" .jsonl)"
