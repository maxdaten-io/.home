#!/usr/bin/env bash
# Cases for guard-commit.sh, taken from real session transcripts.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
fail=0
t() {
  want=$1
  shift
  jq -n --arg c "$*" '{tool_input:{command:$c}}' | ./guard-commit.sh 2>/dev/null
  got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL want=$want got=$got: $*"
    fail=1
  fi
}
t 2 'git commit -qam "fix: x" && git push'
t 2 'git commit -a -m "x"'
t 2 'git commit --all -m x'
t 2 'git -C /Users/jloos/Developer/.home commit -am x'
t 2 'git add -A && git commit -m x'
t 2 'git add . && git commit -m x'
t 2 'git add -u'
t 0 'git add modules/home/cmux.nix && git commit -m "feat: add a thing"'
t 0 'git commit --amend --no-edit'
t 0 'git commit -m "x" -- justfile'
t 0 'git log --all --oneline'
t 0 'git add ./justfile'
t 0 'git commit -qm "fix(cmux): x"'
t 0 'echo add -A; ls -a'
exit $fail
