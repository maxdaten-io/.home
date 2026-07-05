# jloos nix/nixos configs

Inspired by \<DAlperin/dotfiles>.

## Structure

TBD

## Home-Manager

On your macos read the [flake section of home-manager](https://nix-community.github.io/home-manager/index.html#ch-nix-flakes).

To apply new configuration currently run:

```sh
home-manager switch --flake '.#jloos-macos'
```

Update dependencies:

```sh
nix flake update
```

## Raspberry Pi 4 NixOS

Flake based nixos configuration including building a customized install image via docker (mildly inspired by <https://github.com/zefhemel/nix-docker>).

### Build & Provision Image (arm only)

On macos you need a linux vm to build the image.

Start it with: `nix run .#builder` (you will logon automatically, you can stop it with `shutdown now` after you are done)

Add following line to `/etc/nix/machines`:

```conf
ssh-ng://builder@localhost aarch64-linux /etc/nix/builder_ed25519 4 - nixos-test,benchmark,big-parallel,kvm - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUpCV2N4Yi9CbGFxdDFhdU90RStGOFFVV3JVb3RpQzVxQkorVXVFV2RWQ2Igcm9vdEBuaXhvcwo=
```

Run:

```sh
nix build .#packages.aarch64-linux.default --system 'aarch64-linux' --max-jobs 0
```

to build the image inside the vm. It will be transferred to `./result`.

### Install NixOS

Once the pi started, connect via ssh `ssh jloos@pi4-nixos` or as root `ssh root@pi4-nixos`.

```bash
git clone git@github.com:MaxDaten/.home.git
sudo ln -sf /home/jloos/.home/flake.nix /etc/nixos/flake.nix
sudo nixos-install --root / --flake
reboot
```

### Apply new NixOS configuration

Either run on the pi:

```bash
sudo nixos-rebuild switch --flake github:MaxDaten/.home/<commit-sha>
# for example:
# sudo nixos-rebuild switch --flake github:MaxDaten/.home/12e09b66f64f46b97236ffb2eba97e41969b4c1f
```

or remotely:

```bash
nix run .#nixos-switch-pi4-nixos
```

### Use Visual Studio Code remotely

Does not work out of the box but <https://github.com/msteen/nixos-vscode-server> is already installed as a nixos module.
But it has to be [enabled manually on user basis](https://github.com/msteen/nixos-vscode-server#enable-the-service):

```bash
systemctl --user enable auto-fix-vscode-server.service
systemctl --user start auto-fix-vscode-server.service
```

### Secret Management

[sops](https://github.com/mozilla/sops) & [sops-nix](https://github.com/Mic92/sops-nix) is used to manage secrets consumed by nixos.

You have to follow these steps to allow yourself to edit secrets:

1. Get your age compatible key from ssh `./generate-sops-keys.sh`
1. Add your key to `./.sops.yaml`:

```yaml
keys:
  - &user age1m2xmznzaswlsyyrndx5q55tzcdzuxc0nmnawu0q8mnve8vjatyhsn2z6rc
creation_rules:
  - path_regex: secrets/[^/]+\.yaml$
    key_groups:
      - age:
          - *user
```

The machine to consume secrets has to be imported via it's host key:

```bash
# on host machine
cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age
```

For me details follow documentation of sops-nix.

## Setup Remote Building

Main documentation about remote building:

- <https://nixos.wiki/wiki/Distributed_build>
- <https://nixos.org/manual/nix/stable/advanced-topics/distributed-builds.html>

I had some hoops to jump to get it working, now here my way with a concrete example based on this flake setup.

Scenario:

You want to build the pi4 installer image from `jloos-macos` on `pi4-nixos` via:

```sh
# Will work after setup
nix build .#packages.aarch64-linux.default --system 'aarch64-linux' --max-jobs 0
```

The macos default nix installation runs via nix-daemon. The nix-daemon runs as root. The root of `jloos-macos` needs to be able to access `pi4-nixos` via ssh and nix has to be configured with `pi4-nixos` as a remote builder.

### 1. Configure pi4-nixos as a remote builder

```conf
# /etc/nix/nix.conf
builders = @/etc/nix/machines
# Allow macos user jloos to perform remote builds
trusted-users = root jloos
```

```conf
# /etc/nix/machines
# Last part is generated via: pi4-nixos$ base64 -w0 /etc/ssh/ssh_host_ed25519_key.pub
ssh://pi4-nixos aarch64-linux - 4 2 nixos-test,benchmark,big-parallel,kvm - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUwva0lMK1VGcG1Rb1YwemREQ1BvdmQ1alFZSkNvbEpXNlVrbmQzV0FKZFggcm9vdEBwaTQtbml4b3MK
```

### 2. Allow root@macos access to pi4-nixos

Generated a ssh key for root on macos

```bash
jloos@macos$ sudo ssh-keygen -t ed25519
jloos@macos$ sudo cat /var/root/.ssh/id_ed25519.pub
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIPxyE0ilAv126v5gVToRTiH8dha0wquEvI3ZMZpPNvK root@macos
```

Add public key to the pi roots authorizedKeys in [modules/hosts/pi/base.nix](modules/hosts/pi/base.nix).

```nix
users.extraUsers.root.openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIPxyE0ilAv126v5gVToRTiH8dha0wquEvI3ZMZpPNvK root@macos"
];
```

and allow root login at [machines/pi4-nixos/default.nix](machines/pi4-nixos/default.nix):

```nix
services.openssh.permitRootLogin = "yes";
```

Hopefully this command should be able to build the image on `pi4-nixos`:

```sh
# Will work after setup
nix build .#packages.aarch64-linux.default --system 'aarch64-linux' --max-jobs 0
```

## TODO

- [x] Integrate already present home-manager managed home configs for `users.jloos`
- [x] Secret management via [sops-nix](https://github.com/Mic92/sops-nix)
  - <https://xeiaso.net/blog/nixos-encrypted-secrets-2021-01-20>
- [x] Hardware Dashboard
  - [x] Grafana
  - [x] Prometheus
  - [x] Provision Dashboard via nix
- [x] Home-Bridge
  - <https://github.com/SquircleSpace/nixos-configuration/tree/master/homebridge>
  - [x] Pin package
  - [x] Service not starting
- [x] Remote building on pi4
- [ ] Add cachix
