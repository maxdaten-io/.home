{
  pkgs,
  config,
  lib,
  ...
}:
{
  programs.fish.functions = lib.mkIf config.programs.fish.enable {
    tmux-project = ''
      if test -f .tmuxinator.yml
        tmuxinator start -p .tmuxinator.yml $argv
      else
        echo "No .tmuxinator.yml found in current directory"
        return 1
      end
    '';

    cw = ''
      set -l session_name (basename $PWD)
      # Replace dots with underscores (tmux doesn't allow dots in session names)
      set session_name (string replace -a '.' '_' $session_name)

      if tmux has-session -t $session_name 2>/dev/null
        tmux attach -t $session_name
        return
      end

      tmux new-session -d -s $session_name -c $PWD
      tmux split-window -v -l 20% -t $session_name -c $PWD
      tmux select-pane -t $session_name:0.0
      tmux send-keys -t $session_name:0.0 "claude $argv" Enter
      tmux attach -t $session_name
    '';
  };

  programs.tmux = {
    enable = true;
    tmuxinator.enable = true;
    clock24 = true;
    mouse = true;
    extraConfig = ''
      set -g pane-active-border-style "fg=red,bold"
      set -g pane-border-style "fg=colour238"
      set -g window-style "bg=colour235"
      set -g window-active-style "bg=terminal"
    '';
    plugins = with pkgs; [
      tmuxPlugins.cpu
      {
        plugin = tmuxPlugins.resurrect;
        extraConfig = "set -g @resurrect-strategy-nvim 'session'";
      }
      {
        plugin = tmuxPlugins.continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '60' # minutes
        '';
      }
    ];
  };
}
