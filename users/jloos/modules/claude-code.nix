{ pkgs, ... }:
{
  home.file.".claude/CLAUDE.md".text = ''
    # User Instructions

    ## Devenv

    When asked to create a devenv environment for a project, use `devenv init` to initialize the environment.
  '';

  home.packages = with pkgs; [
    (pkgs.buildNpmPackage rec {
      pname = "claude-code";
      version = "2.1.7";

      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
        hash = "sha256-iafHnlQkbYbnzJGI+/JVKnDzaVFE/RTe+r+A+Mge2HQ=";
      };

      npmDepsHash = "sha256-kDZx4Yy2W+JkXN0+5iPr+rC/TUiZpR37KeUgGwZBlNk=";

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
