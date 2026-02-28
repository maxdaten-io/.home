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

  # Strip ANSI escape codes for assertion matching
  stripAnsi = ''sed 's/\x1b\[[0-9;]*m//g' '';

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
in
pkgs.runCommand "statusline-test"
  {
    nativeBuildInputs = [
      statusline
      pkgs.git
    ];
  }
  ''
    set -euo pipefail

    export HOME=$(mktemp -d)

    pass() { echo "PASS: $1"; }
    fail() { echo "FAIL: $1"; exit 1; }

    assert_contains() {
      echo "$1" | grep -qF "$2" && pass "$3" || fail "$3: expected '$2' in output"
    }

    assert_not_contains() {
      if echo "$1" | grep -qF "$2"; then
        fail "$3: unexpected '$2' in output"
      else
        pass "$3"
      fi
    }

    # Clean slate
    rm -f ${cachePath}

    # ── Test 1: --fetch without credentials exits cleanly ──
    ${bin} --fetch
    if [ ! -f ${cachePath} ]; then
      pass "fetch-no-creds: exits 0, no cache created"
    else
      fail "fetch-no-creds: cache should not exist"
    fi

    # ── Test 2: --fetch with fresh cache skips fetch ──
    echo '{}' > ${cachePath}
    before=$(stat -c %Y ${cachePath} 2>/dev/null || stat -f %m ${cachePath})
    ${bin} --fetch
    after=$(stat -c %Y ${cachePath} 2>/dev/null || stat -f %m ${cachePath})
    if [ "$before" = "$after" ]; then
      pass "fetch-fresh-cache: cache untouched"
    else
      fail "fetch-fresh-cache: cache mtime changed"
    fi
    rm -f ${cachePath}

    # ── Test 3: Full rendering with usage cache ──
    echo '${usageCacheJson}' > ${cachePath}
    result=$(echo '${fullJson}' | ${bin} | ${stripAnsi})
    assert_contains "$result" "5h 23%" "render-full: 5h segment"
    assert_contains "$result" "7d 5%" "render-full: 7d segment"
    assert_contains "$result" "ctx 28%" "render-full: ctx used%"
    assert_contains "$result" "10K/200K" "render-full: token ratio"
    rm -f ${cachePath}

    # ── Test 4: Graceful degradation without cache ──
    result=$(echo '${fullJson}' | ${bin} | ${stripAnsi})
    assert_contains "$result" "ctx 28%" "render-no-cache: ctx present"
    assert_not_contains "$result" "5h" "render-no-cache: no 5h segment"
    assert_not_contains "$result" "7d" "render-no-cache: no 7d segment"

    # ── Test 5: Fallback ctx without context_window_size ──
    result=$(echo '${noCtxSizeJson}' | ${bin} | ${stripAnsi})
    assert_contains "$result" "72%" "render-fallback: remaining pct"
    assert_contains "$result" "10K" "render-fallback: token count"
    assert_not_contains "$result" "ctx" "render-fallback: no ctx label"

    # ── Test 6: Minimal JSON (empty) ──
    result=$(echo '{}' | ${bin} | ${stripAnsi})
    pass "render-empty: exits 0, no crash"

    echo "All statusline tests passed."
    touch $out
  ''
