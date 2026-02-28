{ pkgs }:
let
  statusline = pkgs.writers.writeHaskellBin "claude-statusline" {
    libraries = [ pkgs.haskellPackages.aeson ];
    ghcArgs = [
      "-O2"
      "-with-rtsopts=-G1 -A128k -H4m -I0"
    ];
    threadedRuntime = false;
  } (builtins.readFile ../users/jloos/modules/claude-code/statusline.hs);

  bin = "${statusline}/bin/claude-statusline";

  # Helper: pipe JSON through statusline and strip ANSI escapes
  render = pkgs.writeShellScript "render-statusline" ''
    echo "$1" | ${bin} | sed 's/\x1b\[[0-9;]*m//g'
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

  # Hardcoded in statusline.hs — must match
  cachePath = "/tmp/.claude_usage_cache";

  testFile = pkgs.writeText "statusline.bats" ''
    setup() {
      bats_load_library bats-support
      bats_load_library bats-assert
      export HOME=$(mktemp -d)
      rm -f ${cachePath}
    }

    teardown() {
      rm -f ${cachePath}
    }

    @test "fetch: no credentials exits cleanly, no cache created" {
      run ${bin} --fetch
      assert_success
      [ ! -f ${cachePath} ]
    }

    @test "fetch: fresh cache skips fetch (TTL)" {
      echo '{}' > ${cachePath}
      local before
      before=$(stat -c %Y ${cachePath} 2>/dev/null || stat -f %m ${cachePath})
      run ${bin} --fetch
      assert_success
      local after
      after=$(stat -c %Y ${cachePath} 2>/dev/null || stat -f %m ${cachePath})
      [ "$before" = "$after" ]
    }

    @test "render: full with usage cache shows 5h/7d/ctx" {
      echo '${usageCacheJson}' > ${cachePath}
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
    ];
  }
  ''
    export HOME=$(mktemp -d)
    export BATS_LIB_PATH="${pkgs.bats.libraries.bats-support}/share/bats:${pkgs.bats.libraries.bats-assert}/share/bats"
    bats --print-output-on-failure ${testFile}
    touch $out
  ''
