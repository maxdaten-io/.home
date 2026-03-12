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
    set --universal FZF_LEGACY_KEYBINDINGS 0
    set --universal FZF_DISABLE_KEYBINDINGS 1
    set --universal --export FZF_CTRL_T_OPTS "--walker-skip .git,node_modules,target --preview 'bat --style=numbers,header,grid --color=always {}' --bind 'ctrl-/:change-preview-window(down|hidden|)'"
  '';
}
