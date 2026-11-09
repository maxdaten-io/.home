# shellcheck shell=bash
# Claude session index shared by `cw sessions` and `cs`: both packages prepend
# this file (see ../cmux.nix), so it defines functions and globals only.

# Reads every transcript of both claude accounts.
#
# Cache: one TSV row per transcript, re-extracted only when its mtime changes:
#   mtime  file  cwd  branch  title
SESSION_DIRS=("$HOME/.claude/projects" "$HOME/.claude-frontrow/projects")
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/cw/sessions.tsv

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
  # stat first, not in a process substitution: there its failure (e.g. BSD
  # stat without -c) is invisible and the mv below replaced the cache with "".
  local stats
  stats=$(stat -c $'%Y\t%n' "${files[@]}") || return 1
  tmp=$(mktemp "${CACHE}.XXXXXX")
  while IFS=$'\t' read -r mtime f; do
    line=${cached[$f]:-}
    if [[ ${line%%$'\t'*} == "$mtime" ]]; then
      printf '%s\n' "$line"
    else
      printf '%s\t%s\n' "$mtime" "$(extract_session "$f")"
    fi
  done <<<"$stats" >"$tmp"
  mv "$tmp" "$CACHE"
}

# Sets AGE (no subshell: list callers run this for every row). Read by the
# including script, which per-file shellcheck cannot see.
# shellcheck disable=SC2034
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
