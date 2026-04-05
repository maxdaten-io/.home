{ pkgs, lib, ... }:
let
  apfel = pkgs.stdenv.mkDerivation rec {
    pname = "apfel";
    version = "0.8.5";

    src = pkgs.fetchurl {
      url = "https://github.com/Arthur-Ficial/apfel/releases/download/v${version}/${pname}-${version}-arm64-macos.tar.gz";
      hash = "sha256-UVC/OJ8kf5xBS846+tYoxDOV9xyjprhPNZlO+WswWvY=";
    };

    sourceRoot = ".";
    dontBuild = true;
    dontConfigure = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 apfel $out/bin/apfel
      runHook postInstall
    '';

    meta = with lib; {
      description = "CLI for Apple's on-device FoundationModels framework";
      homepage = "https://github.com/Arthur-Ficial/apfel";
      license = licenses.mit;
      platforms = [ "aarch64-darwin" ];
      mainProgram = "apfel";
    };
  };
in
{
  home.packages = lib.optionals pkgs.stdenv.isDarwin [ apfel ];
}
