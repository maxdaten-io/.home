# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal NixOS/Darwin configuration repository managed with Nix Flakes. It contains configuration for:

- macOS system configuration via nix-darwin
- Home Manager configuration for user environments
- Raspberry Pi NixOS configuration
- Secret management via sops-nix
- Development environment setup

## Key Commands

### Building and Switching Configurations

**macOS (Darwin) system rebuild:**

```bash
just switch
# or manually:
sudo darwin-rebuild switch --flake . --verbose
```

**Home Manager configuration for macOS** is applied via `just switch` (integrated into the darwin rebuild).

**NixOS (Pi) rebuild locally:**

```bash
sudo nixos-rebuild switch --flake .
```

**NixOS (Pi) rebuild remotely:**

```bash
nix run .#nixos-switch-pi4-nixos
```

### Flake Management

**Update all flake inputs:**

```bash
just update
# or manually:
nix flake update --commit-lock-file
```

**Build specific packages:**

```bash
nix build .#packages.aarch64-linux.default --system 'aarch64-linux' --max-jobs 0
```

### Development Environment

**Enter development shell:**

```bash
nix develop
```

**Build with remote builders:**

```bash
nix build .#packages.aarch64-linux.default --system 'aarch64-linux' --max-jobs 0
```

### Secret Management

**List all secrets:**

```bash
just sops-list-secrets
```

**Generate age keys for sops:**

```bash
./generate-sops-keys.sh
```

## Architecture

### Directory Structure

- `flake.nix` - Main flake configuration with all inputs and outputs
- `hosts/` - Host-specific configurations
  - `macos/` - macOS/Darwin configuration
  - `pi/` - Raspberry Pi NixOS configuration
- `users/jloos/` - User-specific Home Manager configuration
- `nixos/modules/` - Reusable NixOS modules
- `darwin/modules/` - Reusable Darwin modules

### Key Configuration Files

- `hosts/macos/configuration.nix` - Main macOS system configuration
- `users/jloos/home.nix` - Home Manager user environment
- `hosts/pi/configuration.nix` - Raspberry Pi system configuration
- `justfile` - Common commands and tasks

### Flake Inputs

The configuration uses multiple flake inputs including:

- `nixpkgs` - Main package repository
- `home-manager` - User environment management
- `darwin` - macOS system configuration
- `sops-nix` - Secret management
- `raspberry-pi-nix` - Raspberry Pi specific modules

### Remote Building

The system is configured for remote building from macOS to Raspberry Pi for ARM packages. Remote builders are configured in `/etc/nix/machines`.

### Secret Management

Uses sops-nix for encrypted secret management. Age keys are generated from SSH keys, and secrets are stored in YAML files with path-based encryption rules defined in `.sops.yaml`.

## Common Workflows

1. **Making system changes on macOS**: Edit configuration files, then run `just switch`
1. **Updating packages**: Run `just update` to update all flake inputs
1. **Adding new packages**: Add to appropriate nix file, then rebuild
1. **Managing secrets**: Use sops to edit encrypted files, ensure proper age keys are configured
1. **Building ARM packages**: Use remote building to Pi or local VM with `--system 'aarch64-linux'`

## Important Notes

- The repository uses flakes exclusively - no legacy nix-channels
- All user configuration is managed through Home Manager
- macOS system uses nix-darwin for system-level configuration
- Raspberry Pi runs full NixOS with custom image building
- Remote building requires SSH keys and proper nix configuration
