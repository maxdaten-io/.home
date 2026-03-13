{ pkgs, ... }:
{
  programs.fzf =
    let
      fd = "${pkgs.fd}/bin/fd";
    in
    {
      enable = true;
      enableFishIntegration = true;
      # Alt-C
      changeDirWidgetCommand = "${fd} --type d --hidden --follow --exclude .git --no-ignore";
      changeDirWidgetOptions = [ "--preview 'tree -C {} | head -200'" ];
    };

  programs.fish.interactiveShellInit = ''
    set -gx FZF_LEGACY_KEYBINDINGS 0
    set -gx FZF_DISABLE_KEYBINDINGS 1
    set -gx FZF_CTRL_T_OPTS "--height=100% --walker-skip .git,node_modules,target --preview 'bat --style=numbers,header,grid --color=always {}' --bind 'ctrl-/:change-preview-window(down|hidden|)'"
  '';
}
