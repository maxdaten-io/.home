{
  description = "Personal NixOS configuration";

  inputs = {
    # Nix Derivations
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";

    darwin = {
      url = "https://flakehub.com/f/nix-darwin/nix-darwin/0.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Install Homebrew
    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

    flake-parts.url = "github:hercules-ci/flake-parts";

    # Raspberry Pi
    raspberry-pi-nix = {
      url = "github:nix-community/raspberry-pi-nix/v0.4.0";
    };

    # System Tools
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nnf = {
      url = "github:maxdaten/nixos-nftables-firewall";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Developer environment (devenv 2.0)
    devenv.url = "github:cachix/devenv";

    # Code formatting
    treefmt-nix.url = "github:numtide/treefmt-nix";

    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";
  };

  nixConfig = {
    extra-trusted-public-keys = [
      "maxdaten-io.cachix.org-1:ZDDi/8gGLSeUEU9JST6uXDcQfNp2VZzccmjUljPHHS8="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
    ];
    extra-substituters = [
      "https://maxdaten-io.cachix.org"
      "https://nix-community.cachix.org"
      "https://devenv.cachix.org"
    ];
  };

  outputs =
    {
      nixpkgs,
      flake-parts,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { ... }:
      {
        imports = [
          ./hosts
        ];

        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
          "x86_64-darwin"
        ];

        perSystem =
          {
            system,
            ...
          }:
          {
            _module.args.pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
          };
      }
    );
}
