{ pkgs, ... }:
{
  home.packages = [
    (pkgs.buildNpmPackage rec {
      pname = "playwright-cli";
      version = "0.1.6";

      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@playwright/cli/-/cli-${version}.tgz";
        hash = "sha256-QG0rxAODZgoi32jNpmBltt6BqTXAT6FdfrnzSh2v5sc=";
      };

      npmDepsHash = "sha256-SxPSa5MtbEPVwnjAp9I5un0ye4UXvJxO8so6RwsYI2w=";

      # Get with `npm install @playwright/cli --package-lock-only`
      postPatch = ''
        cp ${./playwright-cli/package-lock.json} package-lock.json
        ${pkgs.jq}/bin/jq 'del(.devDependencies)' package.json > package.json.tmp
        mv package.json.tmp package.json
      '';

      npmFlags = [ "--omit=dev" ];
      dontNpmBuild = true;

      nativeBuildInputs = [ pkgs.makeWrapper ];

      meta = with pkgs.lib; {
        description = "Playwright CLI with skills for coding agents";
        homepage = "https://github.com/microsoft/playwright-cli";
        license = licenses.asl20;
        mainProgram = "playwright-cli";
      };
    })
  ];
}
