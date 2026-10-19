# cmux sidebar and `cw`

## Reload

- `sidebars/worktrees.js` is symlinked out of the store, so saving hot-reloads it.
  No `just switch` needed.
- `cw.sh` is packaged by `../cmux.nix` and only changes after `just switch`.

## The live sidebar

- Make sure `worktrees` is the active sidebar before you judge a change:
  `defaults read com.cmuxterm.app cmuxExtensionSidebarProviderId` should print
  `cmux.sidebar.custom.worktrees`. If it doesn't, run `cmux sidebar select worktrees`.
- `cmux sidebar validate worktrees` validates the file and `cmux sidebar reload worktrees` reloads it.
- Docs: `cmux docs sidebars` (it gives the curl for the authoring guide) and
  `cmux docs api` for the `cmux()` actions.

## Screenshots

`cmux shot` crops and scales on its own; there's no need for imagemagick.

- The sidebar is about 300 window points wide. Use
  `cmux shot --region 0,0,310,700 --out "$CLAUDE_JOB_DIR/tmp/sb.png"`
  (620×1400px, about 120KB).
- Add `--scale 0.5` for layout checks.
- Keep full scale when checking a glyph or a clipped edge; a half-scale crop
  once hid a cut-off icon.

## Tests

`_tests/run.sh` runs `node --check` and the stubbed-runtime tests offline. Pre-commit
runs it for any change under `sidebars/` or `_tests/`. The tests cut
`worktrees.js` at its comment markers, so a renamed marker fails the tests;
update the slice in the test.

- `node _tests/harness.mjs sidebars/worktrees.js` prints `entries()` as a tree for
  a fixed set of workspaces. Extend its `W` array to reproduce a layout bug.
- `_tests/glyphs.py <font.ttf> <glyph-name>...` looks up Nerd Font codepoints.
  The fonts are in `~/Library/Fonts/HomeManager`. Run it with
  `nix shell nixpkgs#python3Packages.fonttools -c python3 _tests/glyphs.py ...`.
