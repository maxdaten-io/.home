{
  flake.modules.homeManager.rex =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    lib.mkIf pkgs.stdenv.isDarwin {
      # Out-of-store on purpose: Rex's "Change Shortcut…" writes init.lua, and a
      # store symlink would be read-only. Apply edits with `rex config reload`.
      # The rex CLI wrapper itself lives in ./claude-code.nix.
      xdg.configFile."rex/init.lua".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Developer/.home/modules/home/rex/init.lua";
    };
}
