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
    version = "0.6.0";
    pyproject = true;

    src = pkgs.fetchPypi {
      pname = "notebooklm_py";
      inherit version;
      hash = "sha256-yTfRPOORxyAhmg8Nqb8Dnfce4A2ziaR1GnIL7iyuPew=";
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
in
{
  home.file.".claude/CLAUDE.md".text = ''
    # User Instructions

    > This file is managed by Home Manager. Edit `~/Developer/.home/users/jloos/modules/claude-code.nix` and run `home-manager switch --flake '.#jloos-macos'` to apply changes.

    ## Shell

    **IMPORTANT**: I run **fish shell**. All terminal commands must be fish-compatible — no bash-isms like `<<<`, `$()` subshells, or `export FOO=bar`. Use fish equivalents: `set`, `string`, pipes with `psub`.

    ## Devenv

    To scaffold a devenv environment, run `devenv init`.

    ## Trunk

    `main` is always releasable. Never commit broken code to it.

    ## Execution Discipline

    Bias toward caution; for trivial tasks, use judgment.

    - **Think before coding** — state assumptions, surface ambiguities, discuss tradeoffs.
    - **Simplicity first** — minimum code that solves the problem; no speculative features or abstractions. Check: *"Would a senior engineer call this overcomplicated?"*
    - **Surgical changes** — touch only what's needed; match existing style. Every changed line should trace to the request.
    - **Goal-driven execution** — turn vague tasks into verifiable checks, then loop until they hold:
      - *"Add validation"* → write tests for invalid inputs, make them pass.
      - *"Fix the bug"* → write a reproducing test, make it pass.
      - *"Refactor X"* → tests pass before and after.

      Multi-step work: state a brief plan with a verification per step.

      ```
      1. [Step] → verify: [check]
      2. [Step] → verify: [check]
      ```

    ## Communication Style

    Be brutally direct. Disagree when warranted. No sugar-coating, flattery, or feelings-management — I'm here for candor, not therapy.

    ## Tools and CLIs

    - Missing tool? Try `nix shell nixpkgs#<pkg> -c <cmd>` first.
    - Before editing config that references CLI flags, verify syntax with `--help`, `man`, or docs. Never guess flag names, values, or separators.
    - For GitHub (issues, PRs, releases, API), prefer `gh` over raw `git`, URLs, or scraping. Use `gh api` for anything without a dedicated subcommand.

    ## Reports and Reviews

    For complex reviews/audits/analyses (security, PR, codebase, deep-dives, comparison matrices), offer a single self-contained HTML file.

    - Inline everything: CSS, SVG, no external assets. Opens standalone in a browser.
    - Treat it as work product: real typography, hierarchy, coherent color, color-coded severity.
    - Use interactivity (collapsible sections, filterable tables, tabs, hover details) only when it aids navigation. No novelty animations.
    - Add charts/diagrams when a picture genuinely beats prose.
    - Not a default for short answers — choose HTML when richer presentation earns its weight.

    ## Developer Profile

    Read `~/.claude/get-shit-done/USER-PROFILE.md` for behavioral preferences. Apply directives based on their confidence level.
  '';

  home.file.".claude/statusline-command" = {
    source = "${claude-statusline}/bin/claude-statusline";
    executable = true;
  };

  home.packages = with pkgs; [
    notebooklm
    (
      let
        claudeCodeVersion = "2.1.163";

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
            hash = "sha512-SZPoYNIjj8Osgde5m2UtJcUlKPqnqajc1uwzBk87qU+cqpMKg2KNBMN5rGUoHCX81fNs6jdWJuKuJgCB6Eqazw==";
          };
          "x86_64-darwin" = {
            suffix = "darwin-x64";
            hash = "sha512-MTy4TO8LUqnRxGXoIE3Jk5bYgiRqvJlXSIZxAO2m69Is9HK+mLevzU9Rr1ZKy+49ExJCNp8392G6+LEUP5+hdQ==";
          };
          "aarch64-linux" = {
            suffix = "linux-arm64";
            hash = "sha512-DLKiXFVTIuUfTnmeGoOEvOTwv5z0xi0yY1wSigubX3Q0jP12RgL3IBYOAtb4ytM3voAi4n/NhixvTwOWly2EEw==";
          };
          "x86_64-linux" = {
            suffix = "linux-x64";
            hash = "sha512-K0CAuLxVqLhenPzi56Ysx157GHDXvcSyegyEFlr3jKdmjIClBynQZlRdZdePeQWBdmz5KrnzJ/lT5zzSH5GKUQ==";
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
          hash = "sha256-KslNYNNOCwPnlciqVfHeJHXXpXWKx73QY6iwEbvoGUE=";
        };

        npmDepsHash = "sha256-2Yk6FQxC3q8LEjTtZlk8GWKYP7BnJdrmKqcljdWniRs=";

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
            --run 'export GITHUB_PERSONAL_ACCESS_TOKEN=$(security find-generic-password -s "github-pat" -w 2>/dev/null)' \
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
}
