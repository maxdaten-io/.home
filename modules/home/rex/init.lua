-- Rex config. Linked out-of-store from ~/.config/rex/init.lua (see ../rex.nix),
-- so edits here and Rex's own "Change Shortcut…" both land in this file;
-- apply with `rex config reload`.

-- cmd+k clears the terminal, as in Terminal.app, iTerm2 and Ghostty.
rex.bind("cmd+k", "com.superlogical.terminal.clear")
rex.bind("shift+cmd+k", "session.switch")

-- Claude session picker: `cs -a --rex` (../cmux/cs.sh) in a floating layer over
-- the active window. Enter opens the pick in a new tab; the layer closes itself
-- when cs exits. Runs through the login shell so cs, claude and rex are on PATH.
rex.action({
  name = "claude_sessions",
  title = "Claude Sessions…",
  run = function(ctx)
    return rex.call("session.new_layer", {
      session_id = ctx.session_id,
      bounds = { 0.05, 0.05, 0.9, 0.9 },
      focus = true,
      layout = { block = { flavor = "com.superlogical.terminal.shell", options = { command = { "cs", "-a", "--rex" } } } },
    })
  end,
})
rex.bind("cmd+j", "claude_sessions")
