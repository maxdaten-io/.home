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
        version = "0.7.3";
        pyproject = true;

        src = pkgs.fetchPypi {
          pname = "notebooklm_py";
          inherit version;
          hash = "sha256-kYvNZ+rod+wzVl15iFAaWP1YL9Y/GcZIAiOvlfBlpeM=";
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

      # One entry set per Claude account config dir (CLAUDE_CONFIG_DIR); the claude
      # binary wrapper below selects ~/.claude-frontrow when launched under
      # ~/Developer/frontrow.
      claudeUserFiles = dir: {
        "${dir}/CLAUDE.md".text = claudeMd;
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
            claudeCodeVersion = "2.1.219";

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
                hash = "sha512-/t/JlmaHh6vtXbZ0R8iRnSBzhc1OSQLybS8HB5RA/BtbueODKQKvtCiCBVwdXXjmdn3aBFrmWRbGzpYZRVcZtw==";
              };
              "x86_64-darwin" = {
                suffix = "darwin-x64";
                hash = "sha512-+xuRyR76Q4ZtorDuZVaTvfFEKunCsthZxR+c8/cHtvViaYt4cZ11Aof2GYH0qQhyY5DaoQphO21Lnr/VfzpGqQ==";
              };
              "aarch64-linux" = {
                suffix = "linux-arm64";
                hash = "sha512-G5yLidk2u6djL5PPuBYXVwVhTsZY5zLoZwh1Jnrd/IRyYb0P0x4gKTzVvGlsGepkBrOp0H2k/KuicyNPrXt57Q==";
              };
              "x86_64-linux" = {
                suffix = "linux-x64";
                hash = "sha512-Eq8aJpMrfy5rwQZQys/MdDD5Ph96ugZMgmwZmo4mXveEvp7JTZX8vUvqN/sHBn/yVmhzJNWcvepzQuBkcrLXZw==";
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
              hash = "sha256-MzRkVGNkudIVt810dGRIrt/fu1/tWvMpC9S/F6rfnzA=";
            };

            npmDepsHash = "sha256-Wv5fERv/7Xd+rhgNSl1WWmnMML1kyWBXKxt4mILMjQ8=";

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
