-- Rex config. Linked out-of-store from ~/.config/rex/init.lua (see ../rex.nix),
-- so edits here and Rex's own "Change Shortcut…" both land in this file;
-- apply with `rex config reload`.

-- cmd+k clears the terminal, as in Terminal.app, iTerm2 and Ghostty.
rex.bind("cmd+k", "com.superlogical.terminal.clear")
rex.bind("shift+cmd+k", "session.switch")

-- Directory the focused terminal last reported (OSC 7), or nil. pwd comes back
-- as a URL, file://<host>/Users/…, percent-encoded.
local function block_dir(ctx)
  if not ctx.block_id then return nil end
  local ok, r = pcall(rex.call, "block.method", { session_id = ctx.session_id, block_id = ctx.block_id, method = "pwd" })
  local url = ok and type(r) == "table" and r.pwd or nil
  if not url then return nil end
  return (url:gsub("^file://[^/]*", ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- Claude session picker: `cs --rex` (../cmux/cs.sh) in a floating layer over
-- the active window, started in the focused pane's directory so it opens on
-- that repo's sessions (ctrl-a widens to all). Enter opens the pick in a new
-- tab; the layer closes itself when cs exits. Runs through the login shell so
-- cs, claude and rex are on PATH. An empty cwd starts in ~.
rex.action({
  name = "claude_sessions",
  title = "Claude Sessions…",
  description = "Pick a Claude Code session of this repo (or all) and resume it in a new tab.",
  category = "Claude",
  keywords = "claude session resume picker transcript",
  run = function(ctx)
    return rex.call("session.new_layer", {
      session_id = ctx.session_id,
      bounds = { 0.05, 0.05, 0.9, 0.9 },
      focus = true,
      layout = {
        block = {
          flavor = "com.superlogical.terminal.shell",
          options = { command = { "cs", "--rex" }, cwd = block_dir(ctx) or "" },
        },
      },
    })
  end,
})
rex.bind("cmd+j", "claude_sessions")
