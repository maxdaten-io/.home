_: {
  imports = [
    ./configuration.nix
    ./modules/homebrew.nix
    ./modules/sops.nix
    ../../nixos/modules/build-machines.nix
  ];
}
