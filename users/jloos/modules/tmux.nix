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
    terminal = "tmux-256color";
    extraConfig = ''
      set -ag terminal-overrides ",*:RGB"
      set -g focus-events on
      # Allow OSC 8 hyperlinks to pass through to Ghostty
      set -ag terminal-features ",*:hyperlinks"
      set -g status-position bottom
      # Gap between panes and status bar
      set -g pane-border-status bottom
      set -g pane-border-format ""
      set -g base-index 1
      setw -g pane-base-index 1
      set -g renumber-windows on
      set -g window-style "bg=#1c1c1e"
      set -g window-active-style "bg=terminal"

      # Match Ghostty scroll speed (1 line per tick)
      bind -T copy-mode WheelUpPane send-keys -X -N 1 scroll-up
      bind -T copy-mode WheelDownPane send-keys -X -N 1 scroll-down

      # Status bar (must be after catppuccin plugin loads)
      set -g status-left-length 100
      set -g status-right-length 100
      set -g status-left "#{E:@catppuccin_status_session}"
      set -g status-right "#{E:@catppuccin_status_application}"
      set -agF status-right "#{E:@catppuccin_status_cpu}"
      set -ag status-right "#{E:@catppuccin_status_date_time}"

      # tmux-cpu must load AFTER status-right is set
      run ${pkgs.tmuxPlugins.cpu}/share/tmux-plugins/cpu/cpu.tmux
    '';
    plugins = with pkgs; [
      tmuxPlugins.tmux-fzf
      {
        plugin = tmuxPlugins.catppuccin;
        extraConfig = ''
          set -g @catppuccin_flavor "mocha"
          set -g @catppuccin_window_status_style "rounded"
          set -g @catppuccin_date_time_text " %H:%M"
        '';
      }
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
