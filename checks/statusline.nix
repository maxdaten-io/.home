{ pkgs, lib }:
let
  palette = import ../users/jloos/modules/palette.nix;
  pl = builtins.fromJSON ''{"arrow":"\uE0B0","lcap":"\uE0B6","rcap":"\uE0B4","rarrow":"\uE0B2"}'';

  statusline = pkgs.writers.writeHaskellBin "claude-statusline" {
    libraries = [
      pkgs.haskellPackages.aeson
      pkgs.haskellPackages.terminal-size
    ];
    ghcArgs = [
      "-O2"
      "-with-rtsopts=-G1 -A128k -H4m -I0"
    ];
    threadedRuntime = false;
  } (builtins.readFile ../users/jloos/modules/claude-code/statusline.hs);

  bin = "${statusline}/bin/claude-statusline";

  # Test-only starship config with the claude profile + env_var modules.
  # Mirrors the definitions in starship.nix so tests run in the sandbox
  # without access to ~/.config/starship.toml.
  testStarshipConfig = (pkgs.formats.toml { }).generate "starship-test.toml" {
    palette = "atelier-cave";
    palettes.atelier-cave = palette;

    fill.symbol = " ";

    profiles.claude = lib.replaceStrings [ "\n" ] [ "" ] ''
      [${pl.lcap}](color_orange)
      ''${env_var.CLAUDE_DIR}
      ([${pl.arrow}](fg:color_orange bg:color_aqua)$git_branch$git_status[${pl.arrow}](fg:color_aqua bg:color_blue))
      ''${env_var.CLAUDE_NO_GIT}
      ''${env_var.CLAUDE_MODEL}
      [${pl.rcap}](fg:color_blue)
      $fill
      ([${pl.lcap}](fg:color_purple)''${env_var.CLAUDE_USAGE})
      (''${env_var.CLAUDE_R_U2D})
      (''${env_var.CLAUDE_R_UEND})
      (''${env_var.CLAUDE_R_DOPEN})
      (''${env_var.CLAUDE_CTX}''${env_var.CLAUDE_STYLE}[${pl.rcap}](fg:color_bg3))
    '';

    # env_var sub-modules (nested so TOML generates [env_var.X] sections)
    env_var = {
      CLAUDE_DIR.format = "[ $env_value ](fg:color_fg0 bg:color_orange)";
      CLAUDE_MODEL.format = "[ $env_value ](fg:color_fg0 bg:color_blue)";
      CLAUDE_USAGE.format = "[ $env_value ](fg:color_fg0 bg:color_purple)";
      CLAUDE_CTX.format = "[ $env_value ](fg:color_fg0 bg:color_bg3)";
      CLAUDE_STYLE.format = "[ $env_value ](fg:color_fg0 bg:color_bg3)";
      CLAUDE_NO_GIT.format = "[${pl.arrow}](fg:color_orange bg:color_blue)";
      CLAUDE_R_U2D.format = "[${pl.rarrow}](fg:color_bg3 bg:color_purple)";
      CLAUDE_R_UEND.format = "[${pl.rcap}](fg:color_purple)";
      CLAUDE_R_DOPEN.format = "[${pl.lcap}](fg:color_bg3)";
    };

    # Need git modules defined (even if not used in most tests)
    git_branch = {
      style = "bg:color_aqua";
      format = "[[ $symbol$branch ](fg:color_fg0 bg:color_aqua)]($style)";
    };
    git_status = {
      style = "bg:color_aqua";
      format = "[[($all_status$ahead_behind )](fg:color_fg0 bg:color_aqua)]($style)";
    };
  };

  starshipBin = "${pkgs.starship}/bin/starship";

  # Helper: pipe JSON through statusline and strip ANSI escapes
  render = pkgs.writeShellScript "render-statusline" ''
    echo "$1" | STARSHIP_BIN="${starshipBin}" \
      STARSHIP_CONFIG="${testStarshipConfig}" \
      COLUMNS=120 \
      ${bin} | sed 's/\x1b\[[0-9;]*m//g'
  '';

  fullJson = builtins.toJSON {
    model.display_name = "Opus 4.6";
    workspace.current_dir = "/tmp";
    context_window = {
      remaining_percentage = 72.5;
      total_input_tokens = 8000;
      total_output_tokens = 2000;
      context_window_size = 200000;
    };
    rate_limits = {
      five_hour = {
        used_percentage = 22.7;
        resets_at = 4070952000; # 2099-01-01T12:00:00Z (Unix epoch seconds)
      };
      seven_day = {
        used_percentage = 5.1;
        resets_at = 4071427200; # 2099-01-07T00:00:00Z (Unix epoch seconds)
      };
    };
    output_style.name = "default";
  };

  noRateLimitsJson = builtins.toJSON {
    model.display_name = "Opus 4.6";
    workspace.current_dir = "/tmp";
    context_window = {
      remaining_percentage = 72.5;
      total_input_tokens = 8000;
      total_output_tokens = 2000;
      context_window_size = 200000;
    };
    output_style.name = "default";
  };

  noCtxSizeJson = builtins.toJSON {
    model.display_name = "Opus 4.6";
    workspace.current_dir = "/tmp";
    context_window = {
      remaining_percentage = 72.5;
      total_input_tokens = 8000;
      total_output_tokens = 2000;
    };
    output_style.name = "default";
  };

  testFile = pkgs.writeText "statusline.bats" ''
    setup() {
      bats_load_library bats-support
      bats_load_library bats-assert
      export HOME=$(mktemp -d)
      export STARSHIP_CONFIG="${testStarshipConfig}"
      export STARSHIP_BIN="${starshipBin}"
    }

    @test "render: full with rate_limits shows usage and ctx" {
      run ${render} '${fullJson}'
      assert_success
      # Both rate limit windows rendered (pct from input + countdown)
      assert_output --regexp "23% [0-9]+d"
      assert_output --regexp "5% [0-9]+d"
      # Context window
      assert_output --partial "ctx 28%"
      assert_output --partial "10K/200K"
    }

    @test "render: no rate_limits degrades gracefully" {
      run ${render} '${noRateLimitsJson}'
      assert_success
      assert_output --partial "ctx 28%"
      refute_output --partial "5h"
      refute_output --partial "7d"
    }

    @test "render: fallback without context_window_size" {
      run ${render} '${noCtxSizeJson}'
      assert_success
      assert_output --partial "72%"
      assert_output --partial "10K"
      refute_output --partial "ctx"
    }

    @test "render: empty JSON does not crash" {
      run ${render} '{}'
      assert_success
    }
  '';
in
pkgs.runCommand "statusline-test"
  {
    nativeBuildInputs = [
      pkgs.bats
      pkgs.bats.libraries.bats-support
      pkgs.bats.libraries.bats-assert
      statusline
      pkgs.git
      pkgs.starship
    ];
  }
  ''
    export HOME=$(mktemp -d)
    export STARSHIP_CONFIG="${testStarshipConfig}"
    export STARSHIP_BIN="${starshipBin}"
    export BATS_LIB_PATH="${pkgs.bats.libraries.bats-support}/share/bats:${pkgs.bats.libraries.bats-assert}/share/bats"
    bats --print-output-on-failure ${testFile}
    touch $out
  ''
