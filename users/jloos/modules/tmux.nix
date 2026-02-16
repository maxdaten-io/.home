{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    tmuxinator.enable = true;
    clock24 = true;
    mouse = true;
    extraConfig = ''
      set -g pane-active-border-style "fg=red,bold"
      set -g pane-border-style "fg=colour238"
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
