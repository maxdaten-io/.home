_: {
  imports = [
    ./configuration.nix
    ./modules/linux-builder.nix
    ./modules/homebrew.nix
    ./modules/sops.nix
    ../../nixos/modules/build-machines.nix
  ];
}
