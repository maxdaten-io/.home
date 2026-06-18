{ pkgs, lib, ... }:
let
  # cmux is installed as a downloaded macOS app that auto-updates itself.
  # It ships a socket-client CLI inside the bundle, but only puts it on PATH
  # inside cmux's own terminals. Expose just that one binary (NOT the whole
  # bin/ dir — it also contains `open`/`ghostty`/`grok` which would shadow
  # system tools). Pointing at the bundle path means app updates need no bump.
  cmux = pkgs.writeShellScriptBin "cmux" ''
    exec /Applications/cmux.app/Contents/Resources/bin/cmux "$@"
  '';
in
{
  home.packages = lib.optionals pkgs.stdenv.isDarwin [ cmux ];
}
