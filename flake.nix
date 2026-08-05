{
  description = "Personal NixOS configuration";

  inputs = {
    # Nix Derivations
    #
    # TEMPORARY PIN: nixpkgs-unstable evals ≥ 2026-07-08 ship a cctools ld that
    # crashes (Trace/BPT trap: 5) on every aarch64-darwin link — terminal-notifier,
    # starship, and anything else not in cache fails to build. Reproduced on Hydra:
    # https://hydra.nixos.org/build/337061993. Pinned to the last-good rev (2026-07-02,
    # the pre-update lock state). Restore the rolling URL once fixed upstream:
    # nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
    nixpkgs.url = "github:NixOS/nixpkgs/65179426c83bb3f6bc14898b42ea1c6f01d374b0";

    darwin = {
      # TEMPORARY PIN (see nixpkgs above): newer nix-darwin needs a newer
      # nixos-render-docs (--sidebar-depth) than the pinned nixpkgs provides.
      # Restore together with nixpkgs:
      # url = "https://flakehub.com/f/nix-darwin/nix-darwin/0.1";
      url = "github:nix-darwin/nix-darwin/a1fa429e945becaf60468600daf649be4ba0350c";
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

    # Every file under ./modules is a flake-parts module (dendritic pattern,
    # https://github.com/mightyiam/dendritic)
    import-tree.url = "github:vic/import-tree";

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

    # Provides the devenv CLI installed in modules/hosts/macbook-pro/system.nix.
    # Pinned to a release tag rather than `main` so the installed version is a
    # real release, not whatever mid-cycle commit the last `just update` caught.
    # Bump deliberately: https://github.com/cachix/devenv/releases
    devenv.url = "github:cachix/devenv/v2.2.1";

    # Code formatting
    treefmt-nix.url = "github:numtide/treefmt-nix";

    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";

    # Pinned nixpkgs for rosetta builder VM image stability — update deliberately,
    # not on every `just update`. Needs a nixpkgs with services.logind.settings
    # (missing in upstream's pinned d89fc19).
    nixpkgs-rosetta-builder.url = "github:NixOS/nixpkgs/c06b4ae3d6599a672a6210b7021d699c351eebda";

    nix-rosetta-builder = {
      url = "github:cpick/nix-rosetta-builder";
      inputs.nixpkgs.follows = "nixpkgs-rosetta-builder";
    };
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

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
