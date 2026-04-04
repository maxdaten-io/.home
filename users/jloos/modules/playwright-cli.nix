{ pkgs, ... }:
{
  home.packages = [
    (pkgs.buildNpmPackage rec {
      pname = "playwright-cli";
      version = "0.1.5";

      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@playwright/cli/-/cli-${version}.tgz";
        hash = "sha256-9MaOyu3+v1fmailoGDEEaEHNmrau5mjAGuf6bCPsbuo=";
      };

      npmDepsHash = "sha256-NHWEvnCFDx1d9D6VnmmpOhwvx350sPNpfoTJW5/sRPU=";

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
