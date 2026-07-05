{
  perSystem =
    { pkgs, ... }:
    {
      checks.statusline = import ./_statusline.nix {
        inherit pkgs;
        lib = pkgs.lib;
      };
    };
}
