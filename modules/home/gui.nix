# GUI packages — only imported on hosts with a display (replaces the old
# `headless` specialArg).
{ inputs, ... }:
{
  flake.modules.homeManager.gui =
    { pkgs, ... }:
    let
      pkgsWithOverlay = import inputs.nixpkgs {
        inherit (pkgs.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      };
    in
    {
      home.packages = with pkgsWithOverlay; [
        # https://www.nerdfonts.com/
        # https://github.com/NixOS/nixpkgs/blob/master/pkgs/data/fonts/nerd-fonts/manifests/fonts.json
        nerd-fonts.hack
        nerd-fonts.jetbrains-mono
        nerd-fonts.zed-mono
        nerd-fonts.iosevka
        nerd-fonts.fira-mono
        nerd-fonts.fira-code
        nerd-fonts.sauce-code-pro

        # Applications
        lens
        obsidian
      ];
    };
}
