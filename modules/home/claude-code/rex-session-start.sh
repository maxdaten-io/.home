# shellcheck shell=bash
# Claude hook (SessionStart): Rex context, with naming split by scope.
# The Rex session is named after the Claude profile (private / frontrow), set
# here deterministically; the agent names only its own tab (window) by task.
# rex comes from PATH. stdout is injected into the agent's context.
command -v rex >/dev/null || exit 0

# Rex's own context, minus its session-naming instruction. Rex flags any
# non-default hook command as "out of date" and suggests `rex skill setup`,
# which would overwrite this Home Manager-managed hook, so drop that paragraph.
rex __internal session-start --agent claude --feature-session-naming=false 2>/dev/null |
  sed '/^The Rex setup for this agent is out of date/,/^to update it\.$/d' || true

[ -n "${REX_SESSION:-}" ] && [ -n "${REX_BLOCK:-}" ] || exit 0

# ~/.claude -> private, ~/.claude-frontrow -> frontrow (see claude.profiles).
profile=$(basename "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")
profile=${profile#.claude}
profile=${profile#-}
profile=${profile:-private}
rex session rename "$REX_SESSION" "$profile" >/dev/null 2>&1 || true

window=$(rex block inspect "$REX_BLOCK" --json 2>/dev/null | jq -r '.block.window_id // empty') || true
[ -n "$window" ] || exit 0
cat <<EOF

## Rex naming

The Rex session is named after the Claude profile (\`$profile\`) by this hook.
Don't rename the session.

Name your tab (window \`$window\`) as part of handling the first request that
identifies the work, without waiting for the user to ask:

\`\`\`sh
rex window rename "$window" <label>
\`\`\`

Use two to four lowercase words joined by hyphens, such as \`fix-login-redirect\`.
Name the task or project. Keep the existing label if it already describes the
same work.
EOF
