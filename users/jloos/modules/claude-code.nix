{ pkgs, ... }:
{
  home.packages = with pkgs; [
    (pkgs.buildNpmPackage rec {
      pname = "claude-code";
      version = "2.0.75";

      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
        hash = "sha256-gQzf+LG/wdIdsWSIfNkSrk+NQYI9ITZKAs0UeNE7g2I=";
      };

      npmDepsHash = "sha256-qjFhnH73w2BZl1LrexT1bxBxj6IJdbCiHbklp4Dm+qY=";

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
