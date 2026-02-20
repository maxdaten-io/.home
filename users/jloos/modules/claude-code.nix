{ pkgs, ... }:
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

  home.packages = with pkgs; [
    (pkgs.buildNpmPackage rec {
      pname = "claude-code";
      version = "2.1.49";

      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
        hash = "sha256-hIJ4s0PcuXMf8DlmSIzZLAGzEkJkLC+DjBDlO2PvnDk=";
      };

      npmDepsHash = "sha256-XMEvZ/SYJ6Ektkbj0cQjZq4gzzvpduXExi+FUmFaIS8=";

      # Get with `npm install @anthropic-ai/claude-code --package-lock-only`
      postPatch = ''
        cp ${./claude-code/package-lock.json} package-lock.json
      '';

      dontNpmBuild = true;

      env.AUTHORIZED = "1";

      postInstall = ''
        wrapProgram $out/bin/claude \
          --set DISABLE_AUTOUPDATER 1 \
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
