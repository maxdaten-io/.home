{ lib, ... }:
let
  palette = import ./palette.nix;
  # Powerline symbols as actual Unicode characters (via JSON decode)
  pl = builtins.fromJSON ''{"arrow":"\uE0B0","lcap":"\uE0B6","rcap":"\uE0B4","rarrow":"\uE0B2"}'';
in
{
  programs.starship =
    let
      # Function to create language configuration
      mkLanguageConfig =
        {
          symbol ? null,
        }:
        {
          disabled = false;
          format = "[[ $symbol( $version) ](fg:color_fg0 bg:color_blue_a11y)]($style)";
          inherit symbol;
          style = "bg:color_blue_a11y";
        };

      # Language configurations with their symbols
      languages = {
        package = mkLanguageConfig { symbol = ""; };
        nodejs = mkLanguageConfig { symbol = ""; };
        terraform = mkLanguageConfig { symbol = ""; };
        python = mkLanguageConfig { symbol = ""; };
        rust = mkLanguageConfig { symbol = ""; };
        golang = mkLanguageConfig { symbol = ""; };
        java = mkLanguageConfig { symbol = ""; };
        kotlin = mkLanguageConfig { symbol = ""; };
        swift = mkLanguageConfig { symbol = ""; };
        haskell = mkLanguageConfig { symbol = ""; };
        gradle = mkLanguageConfig { symbol = ""; };
        helm = mkLanguageConfig { symbol = ""; };
      };
    in
    {
      enable = true;
      enableFishIntegration = true;
      enableBashIntegration = true;
      enableZshIntegration = true;

      # https://starship.rs/config/
      settings = {
        # Inserts a blank line between shell prompts
        add_newline = false;
        line_break.disabled = false;

        palette = "atelier-cave";

        # Custom palette colors
        palettes.spaceship = {
          bright-purple = "#b16cfe";
          bright-cyan = "#00ffff";
          bright-blue = "#00aaff";
        };

        palettes.gruvbox_dark = {
          color_fg0 = "#fbf1c7";
          color_bg1 = "#3c3836";
          color_bg3 = "#665c54";
          color_blue = "#458588";
          color_aqua = "#689d6a";
          color_green = "#98971a";
          color_orange = "#d65d0e";
          color_purple = "#b16286";
          color_red = "#cc241d";
          color_yellow = "#d79921";
        };

        # Extend palette with WCAG AA-accessible prompt backgrounds.
        # Darkened variants of accent colors to achieve ≥4.5:1 contrast
        # with color_fg0 (#efecf4) as foreground text.
        palettes.atelier-cave = palette // {
          # Prompt bg variants (darkened for ≥4.5:1 with #efecf4)
          color_orange_a11y = "#9e5137"; # 4.88:1
          color_yellow_a11y = "#885e32"; # 4.87:1
          color_blue_a11y = "#4b5fbe"; # 4.88:1
          color_purple_a11y = "#7548b8"; # 5.33:1
          # System section text (Atelier Cave base05, 5.06:1 on bg1)
          color_text_dim = "#8b8792";
        };

        format = lib.replaceStrings [ "\n" ] [ "" ] ''
          [${pl.lcap}](color_orange_a11y)
          $os
          $username
          [${pl.arrow}](bg:color_yellow_a11y fg:color_orange_a11y)
          $directory
          $nix_shell
          [${pl.arrow}](fg:color_yellow_a11y bg:color_aqua)
          $git_branch
          $git_status
          [${pl.arrow}](fg:color_aqua bg:color_blue_a11y)
          [$all](fg:color_aqua bg:color_blue_a11y)
          [${pl.arrow}](fg:color_blue_a11y bg:color_bg3)
          $docker_context
          $kubernetes
          $aws
          $gcloud
          $azure
          [${pl.arrow}](fg:color_bg3 bg:color_bg1)
          $memory_usage
          $cmd_duration
          [${pl.rcap} ](fg:color_bg1)
          $line_break$jobs$shell$status$character '';

        os = {
          disabled = false;
          style = "bg:color_orange_a11y fg:color_fg0";
          symbols = {
            Windows = "󰍲";
            Ubuntu = "󰕈";
            SUSE = "";
            Raspbian = "󰐿";
            Mint = "󰣭";
            Macos = "󰀵";
            Manjaro = "";
            Linux = "󰌽";
            Gentoo = "󰣨";
            Fedora = "󰣛";
            Alpine = "";
            Amazon = "";
            Android = "";
            Arch = "󰣇";
            Artix = "󰣇";
            EndeavourOS = "";
            CentOS = "";
            Debian = "󰣚";
            Redhat = "󱄛";
            RedHatEnterprise = "󱄛";
            Pop = "";
          };
        };

        # Project View
        directory = {
          style = "fg:color_fg0 bg:color_yellow_a11y";
          format = "[ $path ]($style)[$read_only]($read_only_style)";
          truncation_length = 3;
          truncate_to_repo = true;
          truncation_symbol = "…/";
        };

        username = {
          disabled = false;
          style_user = "bg:color_orange_a11y fg:color_fg0";
          style_root = "bg:color_orange_a11y fg:color_fg0";
          format = "[ $user ]($style)";
          show_always = true;
        };

        nix_shell = {
          format = "[$symbol$state ]($style)";
          impure_msg = "";
          pure_msg = "λ";
          symbol = builtins.fromJSON ''"\uF313"'';
          style = "fg:color_fg0 bg:color_yellow_a11y";
        };

        git_branch = {
          style = "bg:color_aqua";
          format = "[[ $symbol$branch ](fg:color_bg1 bg:color_aqua)]($style)";
        };

        git_status = {
          style = "bg:color_aqua";
          format = "[[($all_status$ahead_behind )](fg:color_bg1 bg:color_aqua)]($style)";
        };

        # Cloud View

        kubernetes = {
          disabled = false;
          format = "[[ $symbol( $context(:$namespace)) ](fg:color_fg0 bg:color_bg3)]($style)";
          symbol = "";
          style = "bg:color_bg3";
          contexts = [
            {
              context_pattern = "gke_.*_(?P<cluster>[\\w-]+)";
              context_alias = "gke-$cluster";
            }
          ];
        };

        docker_context = {
          disabled = false;
          format = "[[ $symbol( $context) ](fg:color_fg0 bg:color_bg3)]($style)";
          symbol = "";
          style = "bg:color_bg3";
        };

        gcloud = {
          disabled = false;
          format = "[[ $symbol( $project:$account(@$domain)((:$region)) )](fg:color_fg0 bg:color_bg3)]($style)";
          symbol = "";
          style = "bg:color_bg3";
        };

        # System View

        time = {
          disabled = true;
          format = "[[  $time ](fg:color_fg0 bg:color_bg1)]($style)";
          style = "bg:color_bg1";
          time_format = "%R";
        };

        memory_usage = {
          disabled = false;
          threshold = 75;
          format = "[[ $symbol( $ram) ](fg:color_text_dim bg:color_bg1)]($style)";
          symbol = "";
          style = "bg:color_bg1";
        };

        cmd_duration = {
          format = "[[  $duration ](fg:color_text_dim bg:color_bg1)]($style)";
          style = "bg:color_bg1";
          min_time = 2000;
          show_milliseconds = false;
          show_notifications = true;
          min_time_to_notify = 45000;
        };

        jobs = {
          disabled = false;
          format = "[$symbol$number]($style) ";
          symbol = "✦ ";
          style = "bold blue";
          number_threshold = 1;
        };

        character = {
          success_symbol = "[❯](bold green)";
          error_symbol = "[❯](bold red)";
          format = "$symbol";
        };

        status = {
          style = "bold red";
          symbol = "✗ ";
          format = "[$symbol$common_meaning$signal_name$maybe_int]($style) ";
          map_symbol = true;
          disabled = false;
        };

        shell = {
          disabled = false;
          format = "[$indicator]($style) ";
          fish_indicator = "🐟";
          bash_indicator = "🐚";
          style = "cyan bold";
        };
        # ── Claude Code statusline profile ──────────────────────
        # Rendered by `starship prompt --profile claude`.
        # env_var modules are no-ops in the normal shell prompt
        # because the CLAUDE_* vars are never set there.

        fill.symbol = " ";

        profiles.claude = lib.replaceStrings [ "\n" ] [ "" ] ''
          [${pl.lcap}](color_orange_a11y)
          ''${env_var.CLAUDE_DIR}
          ([${pl.arrow}](fg:color_orange_a11y bg:color_aqua)$git_branch$git_status[${pl.arrow}](fg:color_aqua bg:color_blue_a11y))
          ''${env_var.CLAUDE_NO_GIT}
          ''${env_var.CLAUDE_MODEL}
          [${pl.rcap}](fg:color_blue_a11y)
          $fill
          ([${pl.lcap}](fg:color_purple_a11y)''${env_var.CLAUDE_USAGE})
          (''${env_var.CLAUDE_R_U2D})
          (''${env_var.CLAUDE_R_UEND})
          (''${env_var.CLAUDE_R_DOPEN})
          (''${env_var.CLAUDE_CTX}''${env_var.CLAUDE_STYLE}[${pl.rcap}](fg:color_bg3))
        '';

        # env_var sub-modules (nested so TOML generates [env_var.X] sections)
        env_var = {
          # Content modules
          CLAUDE_DIR.format = "[ $env_value ](fg:color_fg0 bg:color_orange_a11y)";
          CLAUDE_MODEL.format = "[ $env_value ](fg:color_fg0 bg:color_blue_a11y)";
          CLAUDE_USAGE.format = "[ $env_value ](fg:color_fg0 bg:color_purple_a11y)";
          CLAUDE_CTX.format = "[ $env_value ](fg:color_fg0 bg:color_bg3)";
          CLAUDE_STYLE.format = "[ $env_value ](fg:color_fg0 bg:color_bg3)";
          # Left sentinel
          CLAUDE_NO_GIT.format = "[${pl.arrow}](fg:color_orange_a11y bg:color_blue_a11y)";
          # Right side sentinels
          CLAUDE_R_U2D.format = "[${pl.rarrow}](fg:color_bg3 bg:color_purple_a11y)";
          CLAUDE_R_UEND.format = "[${pl.rcap}](fg:color_purple_a11y)";
          CLAUDE_R_DOPEN.format = "[${pl.lcap}](fg:color_bg3)";
        };
      }
      // languages;
    };
}
