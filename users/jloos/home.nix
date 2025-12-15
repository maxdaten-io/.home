{
  config,
  lib,
  pkgs,
  inputs,
  headless ? true,
  ...
}:
let
  pkgsWithOverlay = import inputs.nixpkgs {
    inherit (pkgs) system;
    config.allowUnfree = true;
  };

  darwinPackages = with pkgs; [
    terminal-notifier
    # wireshark # broken on darwin https://github.com/NixOS/nixpkgs/issues/362416
  ];

  isDarwin = pkgs.stdenv.isDarwin;

  guiPackages = with pkgsWithOverlay; [
    # https://www.nerdfonts.com/
    # https://github.com/NixOS/nixpkgs/blob/master/pkgs/data/fonts/nerd-fonts/manifests/fonts.json
    nerd-fonts.hack
    nerd-fonts.jetbrains-mono
    nerd-fonts.zed-mono
    nerd-fonts.iosevka
    nerd-fonts.fira-mono
    nerd-fonts.fira-code
    nerd-fonts.sauce-code-pro

    # Applications
    lens
  ];

in
{
  home.stateVersion = "25.11";
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "jloos";
  home.homeDirectory = if isDarwin then lib.mkForce "/Users/jloos" else "/home/jloos";

  imports = [
    inputs.nix-index-database.homeModules.nix-index
    inputs.sops-nix.homeManagerModule
    (import ./modules/fish.nix {
      inherit
        pkgs
        config
        isDarwin
        lib
        ;
    })
    ./modules/starship.nix
    ./modules/git.nix
    ./modules/gh.nix
    ./modules/vim.nix
    ./modules/ssh.nix
    ./modules/tmux.nix
    ./modules/programs.nix
    ./modules/fzf.nix
    ./modules/sops.nix
    ./modules/ghostty.nix
    ./modules/zed.nix
    ./modules/zoxide.nix
    # ./modules/claude-code.nix
  ];

  programs.nix-index-database.comma.enable = true;

  home.packages =
    with pkgs;
    [
      direnv

      gnupg
      htop
      duf
      xz

      peco
      git-ignore
      lazygit

      # shell tools
      ripgrep
      watch
      tree
      wget
      pwgen
      neofetch
      lsd
      fd
      rename
      tldr
      gemini-cli
      claude-code
      mgrep
      #> ERROR: Could not find a version that satisfies the requirement keyring<24.0,>=23.4 (from yubikey-manager) (from versions: none)
      #> ERROR: No matching distribution found for keyring<24.0,>=23.4
      # yubikey-manager

      # Haskell
      haskell-language-server
      ghc

      # Data Structures
      jq
      yq
      jless
      dasel # Query data structures
      gron # transforms to grepable jsons

      # linting
      shellcheck

      # Infrastructure
      # awscli2 # currently broken
      google-cloud-sdk
      kubectl
      kustomize
      kubectx
      dive # Analyze docker layer
      lazydocker # k9s for docker
      skopeo # inspect docker images without docker daemon

      # gimick
      cmatrix

      # Other tools
      stress
      speedtest-cli

      # MCP
      terraform-mcp-server
    ]
    ++ lib.optionals (pkgs.stdenv.isDarwin) darwinPackages
    ++ lib.optionals (!headless) guiPackages;

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Configurations
  programs.man.generateCaches = true; # Allow man completions

  programs.btop.enable = true;
  # https://github.com/aristocratos/btop#configurability
  programs.btop.settings = {
    # truecolor = !isDarwin;
  };

  services.ollama.enable = false;

  home.sessionVariables = {
    EDITOR = if pkgs.stdenv.isDarwin then "zeditor --new --wait" else "vim";
  };
}
