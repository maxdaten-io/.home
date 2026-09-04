{
  flake.modules.homeManager.claude-code =
    { pkgs, ... }:
    let
      claude-statusline-unwrapped = pkgs.writers.writeHaskellBin "claude-statusline" {
        libraries = [
          pkgs.haskellPackages.aeson
          pkgs.haskellPackages.terminal-size
        ];
        ghcArgs = [
          "-O2"
          "-with-rtsopts=-G1 -A128k -H4m -I0"
        ];
        threadedRuntime = false;
      } (builtins.readFile ./claude-code/statusline.hs);

      claude-python = pkgs.python3.withPackages (ps: [ ps.anthropic ]);

      notebooklm = pkgs.python312Packages.buildPythonApplication rec {
        pname = "notebooklm-py";
        version = "0.8.1";
        pyproject = true;

        src = pkgs.fetchPypi {
          pname = "notebooklm_py";
          inherit version;
          hash = "sha256-Q7pRqWCalTC/zZrQbBA17erEsOQBVqWn7n7jAmIWZs0=";
        };

        build-system = with pkgs.python312Packages; [
          hatchling
          hatch-fancy-pypi-readme
        ];

        dependencies = with pkgs.python312Packages; [
          httpx
          click
          rich
          playwright
          filelock
        ];

        doCheck = false;

        nativeBuildInputs = [ pkgs.makeWrapper ];

        postInstall = ''
          wrapProgram $out/bin/notebooklm \
            --set PLAYWRIGHT_BROWSERS_PATH "${pkgs.playwright-driver.browsers}"
        '';

        meta = with pkgs.lib; {
          description = "Unofficial Python API for Google NotebookLM";
          homepage = "https://github.com/teng-lin/notebooklm-py";
          license = licenses.mit;
          mainProgram = "notebooklm";
        };
      };

      claude-statusline = pkgs.symlinkJoin {
        name = "claude-statusline-wrapped";
        paths = [ claude-statusline-unwrapped ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/claude-statusline \
            --set STARSHIP_BIN "${pkgs.starship}/bin/starship" \
            --prefix PATH : "${pkgs.git}/bin"
        '';
      };
      claudeMd = ''
        # User Instructions

        > Managed by Home Manager. Edit `~/Developer/.home/modules/home/claude-code.nix`,
        > then apply with `just switch` in that repo. There is no `homeConfigurations`
        > output — Home Manager is a nix-darwin module here, so `home-manager switch` fails.

        ## Shell — there are two, don't mix them

        - **Your Bash tool runs bash** (pinned via `CLAUDE_CODE_SHELL`), not fish. Never emit
          fish syntax (`end`, `and`/`or`, `set -x FOO val`, `string`, `psub`) in tool calls.
          Coreutils on PATH are GNU (nix) even on macOS — use GNU flags (`sed -i` with no
          suffix arg, `date -d`; not BSD `sed -i '''` / `date -v`).
        - **My interactive shell is fish.** Only commands you hand *me* to run (`! <cmd>`
          snippets, docs, READMEs) need fish syntax — no `<<<`, `$()` subshells, or
          `export FOO=bar`; use `set`, `string`, `psub`.

        ## Working Style

        - Be brutally direct. Disagree when warranted. No sugar-coating, flattery, or
          feelings-management — I'm here for candor, not therapy.
        - Smallest change that solves the problem. Touch only what the request implies, match
          surrounding style, skip speculative abstractions.
        - Turn a vague ask into a check that can fail, then make it pass — "fix the bug" means
          a reproducing test first. For multi-step work, state the plan with a verification per
          step.
        - `main` is always releasable. Never commit broken code to it.

        ## Tools and CLIs

        - Missing tool? `nix shell nixpkgs#<pkg> -c <cmd>`.
        - Never guess CLI flags, values, or separators — confirm with `--help`, `man`, or docs
          before writing them into config.
        - GitHub work goes through `gh` (`gh api` when there's no subcommand), not raw URLs or
          scraping.
        - `devenv` is the project-environment tool here; `devenv init` scaffolds one.

        ## cmux

        `cmux` (macOS terminal/workspace app at `/Applications/cmux.app`, CLI wrapped via Home
        Manager) drives the *running* app over a Unix socket — the app must be open. Inside a
        cmux terminal `CMUX_WORKSPACE_ID`/`CMUX_SURFACE_ID` auto-target the current
        workspace/surface; from any other terminal pass `--workspace`/`--surface`/`--pane`.

        The CLI self-documents for agents — read `cmux --help` and
        `cmux docs <settings|browser|agents|dock|...>` instead of guessing flags. Two
        capabilities worth knowing exist:

        - **Browser automation** in a *visible* split — `cmux browser open <url>`, then
          `snapshot -i`, `click`/`fill`/`eval`/`wait`. Reach for it when eyes on the page help;
          for headless/CI use `playwright-cli`.
        - **Pane control**, tmux-style — `cmux send` + `send-key` to drive another pane,
          `read-screen` to read it back, `list-panes`/`tree` to inspect, `new-split`/`new-pane`
          to create.

        ## Reports and Reviews

        For substantial reviews/audits/analyses (security, PR, codebase, comparison matrices),
        offer a single self-contained HTML file — CSS and SVG inlined, no external assets, opens
        standalone. Treat it as work product: real hierarchy, color-coded severity, charts where
        a picture beats prose. Interactivity only where it aids navigation, no novelty
        animations. Not for short answers.

        ## Claude Accounts

        Two Claude Code accounts are isolated via `CLAUDE_CONFIG_DIR`, selected by
        the wrapped `claude` binary itself (works from any shell, cmux, GUI): plain
        `claude` = private account (`~/.claude`); launched with a CWD under
        `~/Developer/frontrow/` = Front Row work account (`~/.claude-frontrow`).
        A pre-set `CLAUDE_CONFIG_DIR` always wins:
        `env CLAUDE_CONFIG_DIR=$HOME/.claude claude` forces private.
      '';

      # Custom output styles replace Claude Code's built-in software-engineering
      # instructions unless `keep-coding-instructions: true` — this one is a voice
      # change on top of normal coding behaviour, so it keeps them.
      # Select it with `/config` -> Output style; takes effect after `/clear`.
      karpathyOutputStyle = ''
        ---
        name: Karpathy
        description: First principles and from scratch — smallest thing that works, real numbers instead of adjectives, silent failure modes named out loud
        keep-coding-instructions: true
        ---

        Work and explain the way Andrej Karpathy does: from first principles, with the
        smallest thing that actually runs, and with the numbers on the table.

        ## Voice

        Plain words, short sentences, no throat-clearing. Skip "great question", skip
        restating my request back to me, skip the preamble about what you are about to
        say — just say it. Informal is fine, an aside in lowercase is fine. Being
        scannable beats being stylish.

        Be calibrated out loud. "I'm confident", "I think", and "this is a guess, I
        haven't run it" are all useful and all different — never smooth over the
        difference. If you don't know, "I don't know" is a complete answer; follow it
        with the cheapest experiment that would settle it.

        ## Build from first principles

        Before reaching for a library, say in two or three lines what the thing actually
        does. Often that kills the dependency.

        Prefer the 40-line version I can read end to end over the 4-line version that
        hides a framework. A reference implementation I fully understand is worth more
        than a configurable one I don't. When both exist, show the readable one and note
        what a production path would change.

        Strip a problem to its smallest interesting case, make that work, then grow it.
        The toy version is not a detour — it is where the understanding comes from.

        ## Code taste

        - Smallest change that works. Delete more than you add when you can.
        - No speculative abstraction. Two call sites is not a pattern; wait for the third.
        - Explicit beats clever. Clever beats verbose. Verbose beats wrong.
        - Names should match the domain or the math, not the type system.
        - Annotate what isn't visible from the code: shapes, units, invariants, why a
          constant is that constant. Skip comments that restate the line.
        - The fast path and the clear path are different goals. Say which one a piece of
          code is, and don't pay for the wrong one.

        ## Numbers, not adjectives

        "Fast", "large", and "should scale" are not claims, they're vibes. Give the wall
        clock, the size, the complexity, the count. If you didn't measure it, say you're
        estimating and say from what.

        When you optimise, measure before and after and report both. A speedup with no
        baseline is a story, not a result.

        ## Name the silent failures

        The dangerous bug is the one that returns a plausible answer. Before calling
        something done, say what would still pass while being wrong: an off-by-one that
        only shows at a boundary, a shape that broadcasts instead of erroring, a retry
        that swallows the real error, a test asserting on a value the code just computed.

        Prefer a check that fails loudly to a comment warning that it might. Turn a vague
        worry into an assertion, a test, or a log line carrying the actual value.

        ## Teaching

        Lead with the concrete case using real values, then generalise — never the other
        way round. If an explanation would benefit from a worked example with actual
        numbers, work it. Show the intermediate state you would print if you were
        debugging it.

        Say when an abstraction leaks, and where. Half-understood magic is the thing
        worth attacking.
      '';

      # One entry set per Claude account config dir (CLAUDE_CONFIG_DIR); the claude
      # binary wrapper below selects ~/.claude-frontrow when launched under
      # ~/Developer/frontrow.
      claudeUserFiles = dir: {
        "${dir}/CLAUDE.md".text = claudeMd;
        "${dir}/output-styles/karpathy.md".text = karpathyOutputStyle;
        "${dir}/statusline-command" = {
          source = "${claude-statusline}/bin/claude-statusline";
          executable = true;
        };
      };
    in
    {
      home.file = claudeUserFiles ".claude" // claudeUserFiles ".claude-frontrow";

      home.packages = with pkgs; [
        notebooklm
        (
          let
            claudeCodeVersion = "2.1.260";

            # Since 2.1.114 the npm package is a stub (`bin/claude.exe`) that a
            # postinstall script replaces with a platform-specific native binary
            # shipped via `optionalDependencies`. `buildNpmPackage` runs with
            # `--ignore-scripts` and doesn't install optional deps for the host
            # platform, so we fetch and install the native binary manually here.
            #
            # Hashes come directly from package-lock.json `integrity` fields (SRI).
            nativePlatforms = {
              "aarch64-darwin" = {
                suffix = "darwin-arm64";
                hash = "sha512-rhLCelO/hob3gj5qHEdDTWd+QQzr5JOT10VY86YdRFmLObm4+JSvDDVvkySlpyGThf+2iZDLrGJuSUfnTOwF5w==";
              };
              "x86_64-darwin" = {
                suffix = "darwin-x64";
                hash = "sha512-znxVLwHnCj5gtXLVwV67Bo6FrqHw6OMWEsZDjkZkS/JjG3SSkKcv3YMkA6hLkzXVBsZ48BgOHRv2MZ6vXcTkFw==";
              };
              "aarch64-linux" = {
                suffix = "linux-arm64";
                hash = "sha512-lOWJjMw3rRNBjQuGrFqErlk6FW4dbR1Nf51jFtUChv2auatQjPaooslxp9dG944XpNAvn++P65ife4hM2iww6w==";
              };
              "x86_64-linux" = {
                suffix = "linux-x64";
                hash = "sha512-sq79dM8gHYc0eGW44knR7LkzHntJRLODp1e6BIv2pEg6vXvKZHfhzwNyjWE1iX/kzZvtaZrEA5Pg7i+Al3gUdw==";
              };
            };

            nativePlatform =
              nativePlatforms.${pkgs.stdenv.hostPlatform.system}
                or (throw "claude-code: unsupported platform ${pkgs.stdenv.hostPlatform.system}");

            claudeCodeNative = pkgs.fetchurl {
              url = "https://registry.npmjs.org/@anthropic-ai/claude-code-${nativePlatform.suffix}/-/claude-code-${nativePlatform.suffix}-${claudeCodeVersion}.tgz";
              hash = nativePlatform.hash;
            };
          in
          pkgs.buildNpmPackage (finalAttrs: {
            pname = "claude-code";
            version = claudeCodeVersion;

            src = pkgs.fetchurl {
              url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${finalAttrs.version}.tgz";
              hash = "sha256-tCnLMA+54a3UQDMAGWlftuwJNoTkqDrM1b0j4uqrZ8w=";
            };

            npmDepsHash = "sha256-+DVmGmLCX95kxTlvEKoeSIGqCYsoqoTQGtHdosUv7oE=";

            strictDeps = true;

            # Get with `npm install @anthropic-ai/claude-code --package-lock-only`
            postPatch = ''
              cp ${./claude-code/package-lock.json} package-lock.json
            '';

            dontNpmBuild = true;

            env.AUTHORIZED = "1";

            postInstall = ''
              # Replace the bin/claude.exe stub with the real native binary.
              # npm tgz archives extract to `package/<files>`.
              nativeDir=$(mktemp -d)
              ${pkgs.gnutar}/bin/tar -xzf ${claudeCodeNative} -C $nativeDir
              install -m 755 $nativeDir/package/claude \
                $out/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe
              rm -rf $nativeDir

              # buildNpmPackage generates $out/bin/claude as a bash wrapper that
              # invokes `node claude.exe` — which fails since claude.exe is now a
              # native binary, not JS. Replace it with a direct symlink so
              # wrapProgram wraps the binary itself, not the node-invoking wrapper.
              rm $out/bin/claude
              ln -s $out/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe \
                $out/bin/claude

              wrapProgram $out/bin/claude \
                --set DISABLE_AUTOUPDATER 1 \
                --set DISABLE_INSTALLATION_CHECKS 1 \
                --set ENABLE_CLAUDEAI_MCP_SERVERS false \
                --set-default CLAUDE_CODE_SHELL "${pkgs.bash}/bin/bash" \
                --run 'export GITHUB_PERSONAL_ACCESS_TOKEN=$(security find-generic-password -s "github-pat" -w 2>/dev/null)' \
                --run 'if [ -z "''${CLAUDE_CONFIG_DIR:-}" ]; then case "$PWD/" in "$HOME/Developer/frontrow/"*) export CLAUDE_CONFIG_DIR="$HOME/.claude-frontrow" ;; esac; fi' \
                --prefix PATH : "${
                  pkgs.lib.makeBinPath (
                    [
                      pkgs.procps
                      claude-python
                    ]
                    # claude-code's sandbox mode on Linux shells out to these.
                    ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
                      pkgs.bubblewrap
                      pkgs.socat
                    ]
                  )
                }" \
                --unset DEV
            '';

            nativeBuildInputs = [ pkgs.makeWrapper ];

            # Sanity-check that `claude --version` runs and reports the expected
            # version at build time. Would have caught the 2.1.114 native-binary
            # mismatch immediately instead of at runtime.
            doInstallCheck = true;
            nativeInstallCheckInputs = [
              pkgs.versionCheckHook
              pkgs.writableTmpDirAsHomeHook
            ];
            versionCheckKeepEnvironment = [ "HOME" ];

            meta = with pkgs.lib; {
              description = "Claude Code - AI-powered coding assistant";
              homepage = "https://www.npmjs.com/package/@anthropic-ai/claude-code";
              license = licenses.unfree;
              mainProgram = "claude";
            };
          })
        )
      ];
    };
}
