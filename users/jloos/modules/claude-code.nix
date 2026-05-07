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
    version = "0.3.4";
    pyproject = true;

    src = pkgs.fetchPypi {
      pname = "notebooklm_py";
      inherit version;
      hash = "sha256-3HL4mx60wO+62GQaDsg9ouYxxakm4CmpOiWLADK1A8Q=";
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

    User runs **fish shell**. All terminal commands provided to the user must be fish-compatible (no bash-only syntax like `<<<`, `$()` subshells, `export FOO=bar`, etc.). Use fish equivalents: `set`, `string`, pipes with `psub`, etc.

    ## Devenv

    When asked to create a devenv environment for a project, use `devenv init` to initialize the environment.

    ## Engineering Process (Dave Farley)

    Apply Dave Farley's principles from *Modern Software Engineering* and *Continuous Delivery*:

    - **Work in small steps with fast feedback** — every change should be small, incremental, and independently deployable
    - **Optimize for learning** — treat development as an exercise in discovery; use empirical feedback (tests, plans, deploys) over speculation
    - **Continuous Delivery mindset** — the code on `main` must always be in a releasable state; never break the trunk
    - **Separate deployability from feature release** — deploy continuously, release features when ready
    - **Manage complexity through separation of concerns** — high cohesion, loose coupling, clear boundaries

    ## Communication Style

    Be direct and honest. Do not sugar-coat feedback or be overly agreeable. If something is wrong, say so plainly. Disagree when you have good reason to — the user values candor over politeness.

    Don't manage my feelings — I didn't come here for therapy. Be brutally honest, tell me if I'm wrong, avoid flattery and patronizing.

    Address me as "Captain" (as in a starship captain). Keep it natural — sprinkle it in, don't force it into every sentence.

    ## Tools and CLIs

    When a tool is missing in environment, try to use `nix` like `nix shell nixpkgs#nodejs_latest -c npx --help` first.

    Before editing config that references CLI tool options, always verify the correct syntax first by running `--help`, `man <tool>`, or reading docs. Never guess at flag values, separators, or option names.

    For GitHub interactions (issues, PRs, releases, repo metadata, API calls), prefer the `gh` CLI when available over raw `git`, web URLs, or scraping. Use `gh api` for anything not covered by a dedicated subcommand.

    ## Developer Profile

    Read `~/.claude/get-shit-done/USER-PROFILE.md` for behavioral preferences and directives on how to interact with this developer. Apply the directives based on their confidence level.
  '';

  home.file.".claude/statusline-command" = {
    source = "${claude-statusline}/bin/claude-statusline";
    executable = true;
  };

  home.packages = with pkgs; [
    notebooklm
    (
      let
        claudeCodeVersion = "2.1.132";

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
            hash = "sha512-imBlTl4dJ+IqGPMLTbLjSefBSd7c3iUjHGkz7/Q3RVDQJvcb2G83LFsaQGR3JwZ+fEwC7T6E6B8Mprwe9En08g==";
          };
          "x86_64-darwin" = {
            suffix = "darwin-x64";
            hash = "sha512-CnsFT78zXkcR2wcEVivP6aqOMcIKSnegPZZierlSQ/zaXWCVNoW+3OHloMnDm+7BX6BT41K2bz7GckCr0pHiyg==";
          };
          "aarch64-linux" = {
            suffix = "linux-arm64";
            hash = "sha512-VJgVycbS6u/lD05vGKmd+mMFypYt098jYt6yYGibqIvFPQcNkmMZJQfPIJBuVB/+XeySNlI4Pplo6jhwRM0HUA==";
          };
          "x86_64-linux" = {
            suffix = "linux-x64";
            hash = "sha512-ElubH7haoKIXy9SNn8dTGMym0n+zy6A70wWXhhcdAFo7P/M8bdLT6zRyp5TttrkhAZcA8xPVxEB/zNU3sPCMLg==";
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
          hash = "sha256-WjeDzfZFGrs9wbRrL27CGhzKu/lCs8I7dFyez1Vdzog=";
        };

        npmDepsHash = "sha256-TryA01iJPRSAzJc4/SUhecXGxSjkq26Z+Q49NAOuL0M=";

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
