# nix-rosetta-builder Setup Runbook

## Goal

Enable `aarch64-linux` and `x86_64-linux` builds from macOS using `nix-rosetta-builder` (Apple Virtualization.framework + Rosetta 2), compatible with Determinate Nix.

## Key Constraints

- Determinate Nix owns `/etc/nix/nix.conf` — nix-darwin's `nix.enable` must stay `false`
- `nix.linux-builder` and `nix.buildMachines` are inert with `nix.enable = false`
- The rosetta VM image is an `aarch64-linux` derivation requiring `kvm` feature — chicken-and-egg problem
- Bootstrap via `nix.enable = mkForce true` is blocked: nix-darwin has a hard check for Determinate, not just a priority conflict

## Bootstrap (one-time)

Use the standalone `nixpkgs#darwin.linux-builder` QEMU VM as a temporary builder to build the rosetta VM image.

### Prerequisites

1. Standalone linux-builder running in a separate terminal:
   ```fish
   nix run nixpkgs#darwin.linux-builder
   ```
1. SSH keys at `/etc/nix/builder_ed25519` (created by the standalone builder on first run)

### Steps

1. **Set up root SSH config** for the standalone builder:

   ```fish
   sudo mkdir -p /var/root/.ssh
   printf 'Host linux-builder\n  HostName localhost\n  Port 31022\n  User builder\n  IdentityFile /etc/nix/builder_ed25519\n  StrictHostKeyChecking no\n' | sudo tee /var/root/.ssh/config
   ```

1. **Write temporary `/etc/nix/machines`** (must include `kvm` feature!):

   ```fish
   echo 'ssh-ng://linux-builder aarch64-linux - 4 1 kvm,benchmark,big-parallel - -' | sudo tee /etc/nix/machines
   ```

1. **Restart nix daemon** to pick up machines file:

   ```fish
   sudo launchctl kickstart -k system/systems.determinate.nix-daemon
   ```

1. **Rebuild darwin config:**

   ```fish
   sudo darwin-rebuild switch --flake .
   ```

1. **After successful rebuild**, clean up:

   - Remove `linux-builder` entry from `/var/root/.ssh/config`
   - `/etc/nix/machines` is now managed by nix-darwin (rosetta-builder module writes it)
   - Stop the standalone linux-builder (Ctrl-C in its terminal)

## Nix Config Architecture

With `nix.enable = false`, nix-darwin cannot use `nix.buildMachines` or `nix.extraOptions`. Instead:

- `/etc/nix/machines` is written directly via `environment.etc."nix/machines"` — Determinate Nix's `nix.conf` already has `builders = @/etc/nix/machines`
- `/etc/nix/nix.custom.conf` holds custom settings (substituters, trusted keys, `builders-use-substitutes`) — included via Determinate Nix's `!include` mechanism
- The rosetta-builder module options (`cfg.sshProtocol`, `cfg.cores`, `cfg.speedFactor`) are referenced directly in the machines entry

`kvm` is intentionally omitted from the rosetta builder's features — Rosetta VMs lack `/dev/kvm`.

## Files

| File | Role |
|------|------|
| `flake.nix` | `nix-rosetta-builder` input with `inputs.nixpkgs.follows = "nixpkgs"` (fixes upstream stale lock) |
| `hosts/default.nix` | Wires `nix-rosetta-builder.darwinModules.default` into darwin config |
| `hosts/macos/configuration.nix` | `builders-use-substitutes = true` in `nix.custom.conf` |
| `nixos/modules/build-machines.nix` | `nix-rosetta-builder` config + manual `/etc/nix/machines` entry |

## Verification

```fish
cat /etc/nix/nix.conf                                      # Determinate Nix's original
cat /etc/nix/machines                                       # ssh-ng://rosetta-builder aarch64-linux,x86_64-linux ...
grep builders-use-substitutes /etc/nix/nix.custom.conf      # present
sudo ssh rosetta-builder                                    # VM reachable
nix build --rebuild nixpkgs#hello --system aarch64-linux    # builds via rosetta
nix build --rebuild nixpkgs#hello --system x86_64-linux     # builds via Rosetta translation
```

## Gotchas

- `--option builders 'ssh-ng://...'` fails under `sudo` because root has no SSH config for the host
- `nixos-disk-image` derivation requires the `kvm` feature — must be in machines entry during bootstrap
- Determinate Nix's nix.conf SHA256 (for `knownSha256Hashes` if ever needed): `a206701bfedc3fddc608a9a9211c8a54c9a144e853d151b79c87fc1cf96b7655`
