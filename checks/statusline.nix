{ pkgs, lib }:
let
  palette = import ../users/jloos/modules/palette.nix;
  pl = builtins.fromJSON ''{"arrow":"\uE0B0","lcap":"\uE0B6","flame":"\uE0C4"}'';

  statusline = pkgs.writers.writeHaskellBin "claude-statusline" {
    libraries = [ pkgs.haskellPackages.aeson ];
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

    profiles.claude = lib.replaceStrings [ "\n" ] [ "" ] ''
      [${pl.lcap}](color_orange)
      ''${env_var.CLAUDE_DIR}
      ([${pl.arrow}](fg:color_orange bg:color_aqua)$git_branch$git_status[${pl.arrow}](fg:color_aqua bg:color_blue))
      ''${env_var.CLAUDE_NO_GIT}
      ''${env_var.CLAUDE_MODEL}
      ([${pl.arrow}](fg:color_blue bg:color_purple)''${env_var.CLAUDE_USAGE}[${pl.flame}](fg:color_purple bg:color_bg1))
      ''${env_var.CLAUDE_NO_USAGE}
      (''${env_var.CLAUDE_CTX})
      ([${pl.flame}](bg:color_bg1)''${env_var.CLAUDE_STYLE})
      ''${env_var.CLAUDE_CLOSE_DARK}
      ''${env_var.CLAUDE_CLOSE_BLUE}
    '';

    # env_var sub-modules (nested so TOML generates [env_var.X] sections)
    env_var = {
      CLAUDE_DIR.format = "[ $env_value ](fg:color_fg0 bg:color_orange)";
      CLAUDE_MODEL.format = "[ $env_value ](fg:color_fg0 bg:color_blue)";
      CLAUDE_USAGE.format = "[ $env_value ](fg:color_fg0 bg:color_purple)";
      CLAUDE_CTX.format = "[ $env_value ](fg:color_fg0 bg:color_bg1)";
      CLAUDE_STYLE.format = "[ $env_value ](fg:color_fg0 bg:color_bg1)";
      CLAUDE_NO_GIT.format = "[${pl.arrow}](fg:color_orange bg:color_blue)";
      CLAUDE_NO_USAGE.format = "[${pl.flame}](fg:color_blue bg:color_bg1)";
      CLAUDE_CLOSE_DARK.format = "[${pl.arrow}](fg:color_bg1)";
      CLAUDE_CLOSE_BLUE.format = "[${pl.arrow}](fg:color_blue)";
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
      ${bin} | sed 's/\x1b\[[0-9;]*m//g'
  '';

  # Use far-future reset times so countdown is always positive
  usageCacheJson = builtins.toJSON {
    five_hour = {
      utilization = 22.7;
      resets_at = "2099-01-01T12:00:00+00:00";
    };
    seven_day = {
      utilization = 5.1;
      resets_at = "2099-01-07T00:00:00+00:00";
    };
  };

  fullJson = builtins.toJSON {
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
      export CLAUDE_USAGE_CACHE="$HOME/.claude_usage_cache"
      export STARSHIP_CONFIG="${testStarshipConfig}"
      export STARSHIP_BIN="${starshipBin}"
      rm -f "$CLAUDE_USAGE_CACHE"
    }

    teardown() {
      rm -f "$CLAUDE_USAGE_CACHE"
    }

    @test "fetch: no credentials exits cleanly, no cache created" {
      run ${bin} --fetch
      assert_success
      [ ! -f "$CLAUDE_USAGE_CACHE" ]
    }

    @test "fetch: fresh cache skips fetch (TTL)" {
      echo '{}' > "$CLAUDE_USAGE_CACHE"
      local before
      before=$(stat -c %Y "$CLAUDE_USAGE_CACHE" 2>/dev/null || stat -f %m "$CLAUDE_USAGE_CACHE")
      run ${bin} --fetch
      assert_success
      local after
      after=$(stat -c %Y "$CLAUDE_USAGE_CACHE" 2>/dev/null || stat -f %m "$CLAUDE_USAGE_CACHE")
      [ "$before" = "$after" ]
    }

    @test "render: full with usage cache shows 5h/7d/ctx" {
      echo '${usageCacheJson}' > "$CLAUDE_USAGE_CACHE"
      run ${render} '${fullJson}'
      assert_success
      assert_output --partial "5h 23%"
      assert_output --partial "7d 5%"
      assert_output --partial "ctx 28%"
      assert_output --partial "10K/200K"
    }

    @test "render: no cache degrades gracefully" {
      run ${render} '${fullJson}'
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
