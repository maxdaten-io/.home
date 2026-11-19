# shellcheck shell=bash
# rex-claude-restore — resume Claude sessions in their Rex panes after a
# restart. Rex brings windows and panes back under the same ids, but not what
# ran in them. The SessionStart hook (rex-session-start.sh) records one
# pane → session file per pane in $STATE; this picks from those records.
#
#   rex-claude-restore          fzf, newest first: space toggles, ctrl-a all,
#                               enter restores the marked rows (or the current one)
#   rex-claude-restore --list   print the records and what restore would do
#
# Per pick: a pane whose shell is at its prompt gets `cd … && claude --resume …`
# typed into it; a pane that is gone or runs something else gets a new tab
# with the same label; a pane where Claude already runs is skipped.
# Manual only: nothing runs this when Rex starts. The init.lua action
# claude_restore opens it in a floating layer, like `cs --rex`.

STATE=${XDG_STATE_HOME:-$HOME/.local/state}/rex-claude
self=${RCR_SELF:-$0}

# Every live pane in every Rex session: block, rex session, window label.
live_panes() {
	local s # rex would swallow the loop's stdin, hence </dev/null
	rex session ls --json | jq -r '.sessions[].session_id' | while read -r s; do
		rex window ls -s "$s" --json </dev/null |
			jq -r --arg s "$s" '.windows[] | .label as $l | .layers[].blocks[] | [.block_id, $s, $l] | @tsv'
	done
}

# What restore does with a live pane: here (shell at its prompt), running
# (Claude is up in it) or tab (something else holds the terminal).
# `process` reports the shell as foreground even under Claude, so Claude is
# told by its program_status record instead.
pane_action() {
	local rs=$1 b=$2 args
	args=$(jq -nc --arg b "$b" '{block_id: $b, method: "program_status"}')
	if rex api call -s "$rs" block.method "$args" 2>/dev/null |
		jq -e 'any(.records[]?; .app == "claude-code")' >/dev/null; then
		echo running && return
	fi
	args=$(jq -nc --arg b "$b" '{block_id: $b, method: "process"}')
	case $(rex api call -s "$rs" block.method "$args" 2>/dev/null | jq -r '.foreground.name // empty') in
	fish | fish_key_reader | bash | zsh | sh) echo here ;;
	*) echo tab ;;
	esac
}

# One TSV row per record whose transcript still exists, newest first:
# action, session id, rex session, block, dir, config dir, label, transcript, display.
records() {
	local now sid rs b cwd cfg tr t action label dir age color
	local -A pane_rs=() pane_label=()
	while IFS=$'\t' read -r b rs label; do
		pane_rs[$b]=$rs pane_label[$b]=$label
	done < <(live_panes)
	shopt -s nullglob
	local files=("$STATE"/*.json)
	shopt -u nullglob
	((${#files[@]})) || return 0
	now=$(date +%s)
	jq -rs 'sort_by(-.updated)[] | [.session_id, .rex_session, .block_id,
      .cwd, .config_dir, (.transcript // "-"), .updated] | @tsv' "${files[@]}" |
		while IFS=$'\t' read -r sid rs b cwd cfg tr t; do # tab is IFS whitespace: no empty fields
			[[ $tr == - || -f $tr ]] || continue
			if [[ -n ${pane_rs[$b]:-} ]]; then
				rs=${pane_rs[$b]} label=${pane_label[$b]}
				action=$(pane_action "$rs" "$b" </dev/null) # rex would swallow the loop's stdin
			else
				action=tab label=${cwd##*/}
			fi
			dir=$cwd
			if [[ ! -d $dir ]]; then # worktree gone: its repo, else ~
				dir=${cwd%%/.claude/worktrees/*} dir=${dir%%.worktrees/*}
				[[ -d $dir ]] || dir=$HOME
			fi
			age=$(((now - t) / 3600))h
			((now - t < 172800)) || age=$(((now - t) / 86400))d
			case $action in
			here) color=32 ;; running) color=2 ;; *) color=34 ;;
			esac
			printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t\e[2m%4s\e[0m  \e[%sm%-7s\e[0m  %-28s  \e[2m%s\e[0m\n' \
				"$action" "$sid" "$rs" "$b" "$dir" "$cfg" "$label" "$tr" \
				"$age" "$color" "$action" "${label:0:28}" "${cwd/#$HOME/\~}"
		done
}

preview() {
	local tr=$1
	[[ -f $tr ]] || { echo "transcript gone: $tr" && return; }
	printf '\e[2m%s  ·  %s\e[0m\n\n' "${tr##*/}" "$(date -r "$tr" '+%Y-%m-%d %H:%M')"
	tac "$tr" | grep -m 80 -E '"type":"(user|assistant)"' | tac | jq -r '
      select((.type == "user" or .type == "assistant") and (.isMeta | not))
      | (.message.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join(" ")) end) as $t
      | select(($t | length) > 0 and ($t | startswith("<") | not))
      | (if .type == "user" then "\u001b[36m▶ " else "  " end) + ($t | gsub("\\s+"; " ") | .[0:400]) + "\u001b[0m"' \
		2>/dev/null | tail -n 14 || true
}

# Single-quoted for the pane's shell (fish or bash); ' itself is escaped.
sq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

restore() {
	local action=$1 sid=$2 rs=$3 b=$4 dir=$5 cfg=$6 label=$7
	rex session ls --json | jq -e --arg s "$rs" 'any(.sessions[]; .session_id == $s)' >/dev/null ||
		rs=${REX_SESSION:?not inside Rex and the recorded Rex session is gone}
	case $action in
	running) echo "skip  $label — Claude already runs in that pane" ;;
	here)
		rex send -s "$rs" -b "$b" "cd $(sq "$dir") && env CLAUDE_CONFIG_DIR=$(sq "$cfg") claude --resume $sid"$'\r' >/dev/null &&
			echo "pane  $label"
		;;
	*)
		rex window new -s "$rs" "$label" -c "$dir" --focus=false -- \
			env CLAUDE_CONFIG_DIR="$cfg" claude --resume "$sid" >/dev/null &&
			echo "tab   $label"
		;;
	esac
}

case ${1:-} in
--preview) preview "${2:-}" && exit ;;
--rows) records && exit ;;
--list)
	records | cut -f9
	exit
	;;
-h | --help)
	echo "usage: rex-claude-restore [--list]   pick recorded Claude sessions (space toggles) and resume them in their Rex panes" >&2
	exit 2
	;;
"") ;;
*) echo "rex-claude-restore: unknown argument $1" >&2 && exit 2 ;;
esac

rows=$(records)
if [[ -z $rows ]]; then
	echo "rex-claude-restore: nothing recorded in $STATE yet" >&2
	exit 0
fi

picks=$(fzf --multi --ansi --delimiter $'\t' --with-nth 9 --no-sort --layout=reverse \
	--info=inline-right --prompt 'restore › ' \
	--header $'space toggle · ctrl-a all · enter restore marked\n\e[32mhere\e[0m type into its pane · \e[34mtab\e[0m new tab · \e[2mrunning\e[0m skipped' \
	--bind 'space:toggle+down' --bind 'ctrl-a:toggle-all' \
	--preview "$self --preview {8}" --preview-window 'down,45%,wrap,border-top' \
	<<<"$rows") || exit 0

# fd 3: rex reads stdin and would swallow the remaining picks.
while IFS=$'\t' read -r -u 3 action sid rs b dir cfg label _; do
	restore "$action" "$sid" "$rs" "$b" "$dir" "$cfg" "$label" </dev/null || echo "fail  $label" >&2
done 3<<<"$picks"
# The floating layer closes when this exits; keep the summary readable.
[[ -z ${RCR_PAUSE:-} ]] || read -r -t 5 -p 'done — closing in 5s (enter closes now)' _ || true
