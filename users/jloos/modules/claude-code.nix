{ pkgs, ... }:
let
  claude-statusline = pkgs.writers.writeHaskellBin "claude-statusline" {
    libraries = [ pkgs.haskellPackages.aeson ];
    ghcArgs = [
      "-O2"
      "-with-rtsopts=-G1 -A128k -H4m -I0"
    ];
    threadedRuntime = false;
  } (builtins.readFile ./claude-code/statusline.hs);
in
{
  home.file.".claude/CLAUDE.md".text = ''
    # User Instructions

    > This file is managed by Home Manager. Edit `~/Developer/.home/users/jloos/modules/claude-code.nix` and run `home-manager switch --flake '.#jloos-macos'` to apply changes.

    ## Shell

    User runs **fish shell**. All terminal commands provided to the user must be fish-compatible (no bash-only syntax like `<<<`, `$()` subshells, `export FOO=bar`, etc.). Use fish equivalents: `set`, `string`, pipes with `psub`, etc.

    ## Devenv

    When asked to create a devenv environment for a project, use `devenv init` to initialize the environment.

    ## Tools and CLIs

    When a tool is missing in environment, try to use `nix` like `nix shell nixpkgs#nodejs_latest -c npx --help` first.
  '';

  home.file.".claude/statusline-command" = {
    source = "${claude-statusline}/bin/claude-statusline";
    executable = true;
  };

  home.packages = with pkgs; [
    (pkgs.buildNpmPackage rec {
      pname = "claude-code";
      version = "2.1.63";

      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
        hash = "sha256-eHztBWax0Rp5AMuSJvd9Kv5dAiueu6hef9XNB758unc=";
      };

      npmDepsHash = "sha256-/01NyPSKOXp8QtVBiBy0g8AME5XudrzKEQMpIPFbFxc=";

      # Get with `npm install @anthropic-ai/claude-code --package-lock-only`
      postPatch = ''
        cp ${./claude-code/package-lock.json} package-lock.json
      '';

      dontNpmBuild = true;

      env.AUTHORIZED = "1";

      postInstall = ''
        wrapProgram $out/bin/claude \
          --set DISABLE_AUTOUPDATER 1 \
          --set ENABLE_CLAUDEAI_MCP_SERVERS false \
          --unset DEV
      '';

      nativeBuildInputs = [ pkgs.makeWrapper ];

      meta = with pkgs.lib; {
        description = "Claude Code - AI-powered coding assistant";
        homepage = "https://www.npmjs.com/package/@anthropic-ai/claude-code";
        license = licenses.unfree;
        mainProgram = "claude";
      };
    })
  ];
}
