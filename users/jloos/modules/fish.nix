{
  pkgs,
  isDarwin,
  config,
  lib,
  ...
}:
let
  trace = false; # like set -x
in
{
  programs.fish.enable = true;
  programs.fish = {
    plugins = with pkgs.fishPlugins; [
      # https://mynixos.com/search?q=fishPlugins
      {
        name = "done";
        src = done.src;
      }
      # {
      #   name = "foreign-env";
      #   src = foreign-env.src;
      # }
      {
        name = "colored-man-pages";
        src = colored-man-pages.src;
      }
      {
        name = "fzf";
        src = fzf.src;
      }
      {
        name = "autopair";
        src = autopair.src;
      }
      {
        # https://github.com/lilyball/nix-env.fish
        # Setup nix environment in fish shell + completions of packages
        name = "nix-env";
        src = pkgs.fetchFromGitHub {
          owner = "lilyball";
          repo = "nix-env.fish";
          rev = "7b65bd228429e852c8fdfa07601159130a818cfa";
          hash = "sha256-RG/0rfhgq6aEKNZ0XwIqOaZ6K5S4+/Y5EEMnIdtfPhk=";
        };
      }
      {
        name = "pj";
        src = pkgs.fetchFromGitHub {
          owner = "oh-my-fish";
          repo = "plugin-pj";
          rev = "43c94f24fd53a55cb6b01400b9b39eb3b6ed7e4e";
          hash = "sha256-/4c/52HLvycTPjuiMKC949XYLPNJUhedd3xEV/ioxfw=";
        };
      }
    ];

    shellAbbrs = lib.mkMerge [
      {
        gitco = "git checkout";
        gitrb = "git rebase --autostash";
        gitcm = "git commit -m";
        gitca = "git commit --amend --no-edit";
        pjo = "pj open";
        tp = "terraform plan";
        ta = "terraform apply";
        tay = "terraform apply --yes";
        lg = "lazygit";
        # Handy for nix shells with deep folder structures
        cdr = "cd $PRJ_ROOT";
      }
      (lib.mkIf isDarwin {
        # Install nix-darwin (initially)
        # nix run nix-darwin -- switch --flake ${config.home.homeDirectory}/Workspace/.home/"
        nix-switch = "darwin-rebuild switch --flake ${config.home.homeDirectory}/Developer/.home/";
      })
    ];

    shellAliases = {
      k = "kubectl";
      br = "broot";
      ls = "${pkgs.lsd}/bin/lsd -l";
      h = "heygpt";
      x = "xgpt4";
      zed = "zeditor";
      agy = "/Applications/Antigravity.app/Contents/MacOS/Electron";
    };

    shellInit = ''
      ${if trace then "set -U fish_trace 2" else "set -e fish_trace"}
      set -U fish_greeting
      set -U PROJECT_PATHS ~/Developer/maxdaten-io/buzzar ~/Developer/maxdaten-io/gitops ~/Developer/.home ~/Developer
      set __done_enabled


    '';

    functions.fish_reload = "source ~/.config/fish/config.fish";
  };
}
