{ pkgs, ... }:
{
  home.file.".claude/CLAUDE.md".text = ''
    # User Instructions

    ## Devenv

    When asked to create a devenv environment for a project, use `devenv init` to initialize the environment.

    ## Tools and CLIs

    When a tool is missing in environment, try to use `nix` like `nix shell nixpkgs#nodejs_latest -c npx --help` first.
  '';

  home.packages = with pkgs; [
    (pkgs.buildNpmPackage rec {
      pname = "claude-code";
      version = "2.1.34";

      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
        hash = "sha256-9poksTheZl3zwxmGwTNwAmUmTooZCY5huFqe73RYh1A=";
      };

      npmDepsHash = "sha256-ELjyYK9VtlUWqh+gwz6OPAcZB9r5mELT8IGxOOt0iLA=";

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
