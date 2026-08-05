# Common user environment for jloos on every host (CLI-only; GUI lives in gui.nix).
{ config, inputs, ... }:
let
  aspects = with config.flake.modules.homeManager; [
    fish
    starship
    gcloud-scope
    git
    gh
    vim
    ssh
    tmux
    programs
    fzf
    sops
    ghostty
    zed
    zoxide
    lazygit
    claude-code
    playwright-cli
    apfel
    cmux
    indie-consultant
  ];
in
{
  flake.modules.homeManager.base =
    { lib, pkgs, ... }:
    let
      darwinPackages = with pkgs; [
        terminal-notifier
        # wireshark # broken on darwin https://github.com/NixOS/nixpkgs/issues/362416
      ];

      isDarwin = pkgs.stdenv.isDarwin;
    in
    {
      home.stateVersion = "26.05";
      # Home Manager needs a bit of information about you and the
      # paths it should manage.
      home.username = "jloos";
      home.homeDirectory = if isDarwin then lib.mkForce "/Users/jloos" else "/home/jloos";

      imports = [
        inputs.nix-index-database.homeModules.nix-index
      ]
      ++ aspects;

      programs.nix-index-database.comma.enable = true;

      home.packages =
        with pkgs;
        [
          just
          nodejs
          python3

          gnupg
          htop
          duf
          xz

          peco
          git-ignore

          # shell tools
          ripgrep
          bats
          watch
          tree
          pstree
          wget
          pwgen
          fastfetch
          lsd
          fd
          rename
          tldr
          gemini-cli

          mgrep
          spec-kit
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
        ++ lib.optionals (pkgs.stdenv.isDarwin) darwinPackages;

      # Let Home Manager install and manage itself.
      programs.home-manager.enable = true;

      # Configurations
      programs.man = {
        enable = true;
        package = pkgs.man-db;
        generateCaches = true; # Allow man completions
      };

      programs.btop.enable = true;
      # https://github.com/aristocratos/btop#configurability
      programs.btop.settings = {
        # truecolor = !isDarwin;
      };

      services.ollama.enable = true;

      home.sessionVariables = {
        EDITOR = if pkgs.stdenv.isDarwin then "zeditor --new --wait" else "vim";
      };
    };
}
