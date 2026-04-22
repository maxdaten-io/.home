{ pkgs, ... }:

# @playwright/cli — agent-facing CLI bundled with Playwright skills.
# Built from the upstream GitHub release tag so the lock file lives
# upstream and we don't vendor anything in this repo.
#
# Refresh recipe (when bumping `version`):
#   1. Update the `src` hash:
#        nix-prefetch-url --unpack --type sha256 \
#          https://github.com/microsoft/playwright-cli/archive/refs/tags/v<version>.tar.gz
#        nix hash convert --to sri sha256:<hash>
#   2. Set `npmDepsHash = lib.fakeHash;` and rebuild — Nix will print the
#      correct hash; copy it back here.
#
# Why not importNpmLock? It filters devDependencies out of its built
# npm cache and there's no opt-in to include them, which collides with
# upstream locks that mix runtime + dev deps in a single tree.

{
  home.packages = [
    (pkgs.buildNpmPackage rec {
      pname = "playwright-cli";
      version = "0.1.8";

      src = pkgs.fetchFromGitHub {
        owner = "microsoft";
        repo = "playwright-cli";
        rev = "v${version}";
        hash = "sha256-8f/wFO4hSytpy3kEPyScoMWXWyeTl/SKoc3vD7xYaKo=";
      };

      npmDepsHash = "sha256-DK+nTRdVKznerAMK7McCCgr2OK4GXymbmgyR9qU/aH4=";

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
