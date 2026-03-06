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
        # Desktop notifications when long-running commands finish
        name = "done";
        src = done.src;
      }
      {
        # Colorizes man page output
        name = "colored-man-pages";
        src = colored-man-pages.src;
      }
      {
        # FZF key bindings (Ctrl-R history, Ctrl-T file finder, Alt-C cd)
        name = "fzf";
        src = fzf.src;
      }
      {
        # Auto-closes brackets, quotes, and other paired characters
        name = "autopair";
        src = autopair.src;
      }

    ];

    shellAbbrs = lib.mkMerge [
      {
        gitco = "git checkout";
        gitrb = "git rebase --autostash";
        gitcm = "git commit -m";
        gitca = "git commit --amend --no-edit";

        tp = "terraform plan";
        ta = "terraform apply";
        tay = "terraform apply --yes";
        lg = "lazygit";
        # Handy for nix shells with deep folder structures
        cdr = "cd $DEVENV_ROOT";
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
      zed = "zeditor";
      agy = "/Applications/Antigravity.app/Contents/MacOS/Electron";
      dev = "devenv shell -- $SHELL";
    };

    shellInit = ''
      ${if trace then "set -U fish_trace 2" else "set -e fish_trace"}
      set -U fish_greeting
      set __done_enabled
    '';

    functions.fish_reload = "source ~/.config/fish/config.fish";

    functions.cw = ''
      set -l session_name (basename $PWD)
      # Replace dots with underscores (tmux doesn't allow dots in session names)
      set session_name (string replace -a '.' '_' $session_name)

      if tmux has-session -t $session_name 2>/dev/null
        tmux attach -t $session_name
        return
      end

      tmux new-session -d -s $session_name -c $PWD
      tmux split-window -v -l 30% -t $session_name -c $PWD
      tmux select-pane -t $session_name:0.0
      tmux send-keys -t $session_name:0.0 "claude $argv" Enter
      tmux attach -t $session_name
    '';
  };
}
