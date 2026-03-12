{
  pkgs,
  config,
  lib,
  ...
}:
let
  palette = import ./palette.nix;

  # Atelier Cave theme for catppuccin/tmux
  # Maps the base16 Atelier Cave palette to catppuccin's @thm_* variables.
  # Base tones interpolated from base00(#19171c)–base07(#efecf4).
  # Accent variants derived from the 8 Atelier Cave accent colors.
  atelierCaveTheme = pkgs.writeText "catppuccin_atelier-cave_tmux.conf" ''
    # Atelier Cave — custom catppuccin theme
    # Base colors
    set -ogq @thm_bg "#26232a"
    set -ogq @thm_fg "${palette.color_fg0}"

    # Accent colors
    set -ogq @thm_rosewater "#e2dfe7"
    set -ogq @thm_flamingo "#d06a94"
    set -ogq @thm_pink "#bf40bf"
    set -ogq @thm_mauve "${palette.color_purple}"
    set -ogq @thm_red "${palette.color_red}"
    set -ogq @thm_maroon "#c0625a"
    set -ogq @thm_peach "${palette.color_orange}"
    set -ogq @thm_yellow "${palette.color_yellow}"
    set -ogq @thm_green "${palette.color_green}"
    set -ogq @thm_teal "#359e9e"
    set -ogq @thm_sky "#5ba0d0"
    set -ogq @thm_sapphire "${palette.color_aqua}"
    set -ogq @thm_blue "${palette.color_blue}"
    set -ogq @thm_lavender "#a87ceb"

    # Surface & overlay scale (dark → light)
    set -ogq @thm_subtext_1 "#a8a4ae"
    set -ogq @thm_subtext_0 "#c5c2cb"
    set -ogq @thm_overlay_2 "#8b8792"
    set -ogq @thm_overlay_1 "#7e7887"
    set -ogq @thm_overlay_0 "${palette.color_bg3}"
    set -ogq @thm_surface_2 "#585260"
    set -ogq @thm_surface_1 "#47424e"
    set -ogq @thm_surface_0 "#37333c"
    set -ogq @thm_mantle "${palette.color_bg1}"
    set -ogq @thm_crust "#110f15"
  '';

  # Patch catppuccin plugin to include the custom theme
  # Side-effect script: scans all panes for Claude Code, sets per-window
  # user options (@claude_w, @claude_a, @claude_i, @claude_any) so the
  # catppuccin window_text format can read them.  Produces no stdout.
  claudePaneMonitor = pkgs.writeShellScript "claude-pane-monitor" ''
    session="$(tmux display-message -p '#{session_name}')"
    declare -A working asking idle

    while IFS=$'\t' read -r win title; do
      case "$title" in
        *"Claude Code"*)
          case "$title" in
            "✳ "*)  asking[$win]=$(( ''${asking[$win]:-0} + 1 )) ;;
            "Claude Code") idle[$win]=$(( ''${idle[$win]:-0} + 1 )) ;;
            *)      working[$win]=$(( ''${working[$win]:-0} + 1 )) ;;
          esac ;;
      esac
    done < <(tmux list-panes -s -t "$session" -F '#{window_index}	#{pane_title}')

    while read -r win; do
      w=''${working[$win]:-0}; a=''${asking[$win]:-0}; i=''${idle[$win]:-0}
      total=$((w + a + i))
      tmux set-option -wqt "''${session}:''${win}" @claude_w "$w"
      tmux set-option -wqt "''${session}:''${win}" @claude_a "$a"
      tmux set-option -wqt "''${session}:''${win}" @claude_i "$i"
      tmux set-option -wqt "''${session}:''${win}" @claude_any "$([ $total -gt 0 ] && echo 1 || echo 0)"
    done < <(tmux list-windows -t "$session" -F '#{window_index}')
  '';

  # Build the window text format with per-window Claude state icons.
  # Each state shows a colored icon + count (if >1).  Falls back to #W when
  # no Claude panes are present (@claude_any != 1).
  #
  # tmux conditional: #{?#{m:1,#{@claude_any}}, <claude-icons> claude, #W}
  # Per-state icon:   #{?#{m:0,#{@claude_X}},, <icon><count>}
  #   — m:0 matches when count IS zero → empty; false branch shows the icon.
  #   — count shown only when >1 via nested #{?#{m:1,#{@claude_X}},,#{@claude_X}}
  claudeWindowText =
    let
      # icon + optional count for a single state
      stateIcon =
        optName: icon: color:
        let
          countIfMany = "#{?#{m:1,#{@${optName}}},,#{@${optName}}}";
        in
        "#{?#{m:0,#{@${optName}}},,#[fg=${color}]${icon}#[fg=${palette.color_fg0}]${countIfMany} }";
      workingIcon = stateIcon "claude_w" "󱜚" palette.color_purple;
      askingIcon = stateIcon "claude_a" "󰭻" palette.color_green;
      idleIcon = stateIcon "claude_i" "󰏤" palette.color_bg3;
    in
    " #{?#{m:1,#{@claude_any}},${workingIcon}${askingIcon}${idleIcon}claude,#W} #{b:pane_current_path}";

  catppuccinWithCave = pkgs.tmuxPlugins.catppuccin.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      cp ${atelierCaveTheme} $out/share/tmux-plugins/catppuccin/themes/catppuccin_atelier-cave_tmux.conf
    '';
  });
in
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
      set -g allow-passthrough on
      set -g status-position bottom
      # Gap between panes and status bar
      set -g pane-border-status bottom
      set -g pane-border-format " #P: #{?pane_title,#T,#{pane_current_command}} "
      set -g base-index 1
      setw -g pane-base-index 1
      set -g renumber-windows on
      set -g window-style "bg=#26232a"
      set -g window-active-style "bg=terminal"

      # Match Ghostty scroll speed (1 line per tick)
      bind -T copy-mode WheelUpPane send-keys -X -N 1 scroll-up
      bind -T copy-mode WheelDownPane send-keys -X -N 1 scroll-down

      # Faster status updates for Claude Code indicator responsiveness
      set -g status-interval 5

      # Status bar (must be after catppuccin plugin loads)
      set -g status-left-length 100
      set -g status-right-length 100
      set -g status-left "#{E:@catppuccin_status_session}"
      set -g status-right "#(${claudePaneMonitor})#{E:@catppuccin_status_application}"
      set -agF status-right "#{E:@catppuccin_status_cpu}"
      set -ag status-right "#{E:@catppuccin_status_date_time}"

      # tmux-cpu must load AFTER status-right is set
      run ${pkgs.tmuxPlugins.cpu}/share/tmux-plugins/cpu/cpu.tmux
    '';
    plugins = with pkgs; [
      tmuxPlugins.tmux-fzf
      {
        plugin = tmuxPlugins.fzf-tmux-url;
        extraConfig = ''
          set -g @fzf-url-fzf-options '-w 100% -h 50% --multi -0 --no-preview --scroll-off=0'
          set -g @fzf-url-open "${pkgs.writeShellScript "copy-url" ''printf '%s' "$1" | pbcopy''}"
        '';
      }
      {
        plugin = catppuccinWithCave;
        extraConfig = ''
          set -g @catppuccin_flavor "atelier-cave"
          # Window pill reads per-window @claude_* options set by claudePaneMonitor
          # Shows aggregated state icons (working/asking/idle) across ALL panes
          set -g @catppuccin_window_text "${claudeWindowText}"
          set -g @catppuccin_window_status_style "rounded"
          set -g @catppuccin_date_time_text " %d.%m. %H:%M"

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
