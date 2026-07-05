{
  flake.modules.homeManager.vim =
    { pkgs, ... }:
    {
      programs.neovim = {
        enable = true;
        vimAlias = true;
        extraConfig = ''
          colorscheme gruvbox
        '';

        plugins = with pkgs.vimPlugins; [
          gruvbox

          # Languages
          vim-nix

          vim-fish

          vim-go

          vim-pandoc
          vim-pandoc-syntax

          vim-yaml
          vim-json
          vim-markdown
        ];
      };
    };
}
