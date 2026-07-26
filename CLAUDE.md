# CLAUDE.md

Personal Nix flake: nix-darwin (MacBook Pro), NixOS (Raspberry Pi), Home
Manager, sops-nix.

## Git Workflow

**No pull requests for your own changes.** Single-maintainer repo — commit
directly to `main` and push. Don't create branches or ask whether to open a PR.
(`.github/workflows/update-flake.yml` opens automated dependency PRs; that bot
is not a pattern to imitate.)

**No worktrees or branches in agent mode.** Background sessions (`/bg`,
`claude --bg`, agent view) otherwise move themselves into a
`.claude/worktrees/<name>` worktree on a `worktree-*` branch before their first
edit. Turned off here with `worktree.bgIsolation = "none"`, which sits in
`.claude/settings.local.json` because devenv's `claude.code` module owns
`.claude/settings.json` (a nix-store symlink) and exposes no passthrough for
arbitrary settings keys. `.claude/` is gitignored, so a fresh clone needs it
re-added:

```json
{ "worktree": { "bgIsolation": "none" } }
```

Work in the checkout you are given and commit to `main`. Reach for
`EnterWorktree` only when I ask for a worktree.

`main` must stay releasable. Evaluate a Darwin change before pushing it:

```bash
nix eval .#darwinConfigurations."Jan-Philips-MacBook-Pro".config.system.build.toplevel.drvPath
```

**Known pre-existing CI red:** `Check Flake` fails with `attribute 'buildDTBs' missing` — raspberry-pi-nix v0.4.0 against current nixpkgs. This predates
current work, so judge a change by whether it adds *new* failures.
`Check Formatting` must stay green.

## Architecture

The repo follows the [dendritic pattern](https://github.com/mightyiam/dendritic):
every `.nix` file under `modules/` is a flake-parts module, auto-imported via
[import-tree](https://github.com/vic/import-tree) — **paths containing a `_`
component are skipped**. Files contribute config to named buckets under
`flake.modules.<class>.<name>` (classes: `nixos`, `darwin`, `homeManager`), and
host wiring files assemble those buckets into `darwinConfigurations` /
`nixosConfigurations`. Flake inputs reach inner modules by **lexical capture
from the outer flake-parts module — there is no `specialArgs`**.

`flake.nix` holds inputs only; outputs are
`mkFlake { inherit inputs; } (import-tree ./modules)`.

- `modules/flake/` — flake-level plumbing (systems, perSystem pkgs, checks)
- `modules/home/` — Home Manager aspects; `base.nix` is the roll-up every host
  imports, `gui.nix` only hosts with a display
- `modules/users/jloos.nix` — user account + home-manager wiring, both classes
- `modules/hosts/macbook-pro/` — Darwin host `"Jan-Philips-MacBook-Pro"`
- `modules/hosts/pi/` — `nixosConfigurations.pi` and `.pi-minimal`, plus
  sd-image and flash apps

Several inputs carry `TEMPORARY PIN` comments in `flake.nix` recording why they
are rev-pinned and what restores them. Read those before touching a pin.

## Commands

`just` recipes are the interface — read `justfile` for the full set. The ones
that surprise:

- `just switch` — darwin-rebuild, then *interactively offers to auto-commit*
  by shelling out to `claude -p`
- `just update` — **much more than `nix flake update`**: also `devenv update`
  plus npm (claude-code) and PyPI (notebooklm) bumps, each committed atomically
- `just sops-list-secrets` — derives the file list from `path_regex` entries in
  `.sops.yaml`; `./generate-sops-keys.sh` derives age keys from SSH keys

The dev shell is **devenv, not `nix develop`** — this flake defines no
`devShells`. Use `devenv shell` (CI runs `devenv shell treefmt --fail-on-change`).

Pi deploys build on the Pi itself: `nix run .#nixos-switch-pi` (or
`.#nixos-switch-pi-minimal`).

Local `aarch64-linux` building is **currently off** —
`modules/hosts/macbook-pro/rosetta-builder.nix` sets
`nix-rosetta-builder.enable = false`. If re-enabling it: `nix.buildMachines` is
inert here because `nix.enable = false` (Determinate Nix owns `nix.conf`, which
already reads `builders = @/etc/nix/machines`), so the builder entry has to be
written to `/etc/nix/machines` directly. The file keeps that as commented code.
