{ pkgs, ... }:
{
  home.packages = [
    (pkgs.buildNpmPackage rec {
      pname = "playwright-cli";
      version = "0.1.8";

      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@playwright/cli/-/cli-${version}.tgz";
        hash = "sha256-7UJSZ3Kwzn93e4b2wAcB/j9a5VupgOUR4f0us31PfaQ=";
      };

      npmDepsHash = "sha256-LYhvEogLEXHHjvvQ3HQOe80DfSTf042fNKs4oKs4Bvg=";

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
