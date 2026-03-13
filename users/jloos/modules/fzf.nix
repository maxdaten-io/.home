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
    bind \cg fzf_git_changed
  '';

  programs.fish.functions.fzf_git_changed =
    let
      listCmd = "{ git diff --name-only --relative 2>/dev/null; git diff --name-only --staged --relative 2>/dev/null; git ls-files --others --exclude-standard --relative 2>/dev/null; } | sort -u";
    in
    ''
      set -l files (git diff --name-only --relative 2>/dev/null; git diff --name-only --staged --relative 2>/dev/null; git ls-files --others --exclude-standard --relative 2>/dev/null)
      if test (count $files) -eq 0
        echo "No changed files"
        return
      end
      printf '%s\n' $files | sort -u | fzf --height=100% --multi \
        --preview 'git -c pager.diff=cat diff --color=always -- {} 2>/dev/null; git -c pager.diff=cat diff --staged --color=always -- {} 2>/dev/null; test -f {} && git ls-files --others --exclude-standard -- {} | grep -q . && bat --style=numbers,header,grid --color=always {}' \
        --preview-window=right:60% \
        --bind 'ctrl-/:change-preview-window(down|hidden|)' \
        --bind 'ctrl-r:reload(${listCmd})' \
        --header 'ctrl-r: refresh | ctrl-/: toggle preview' | while read -l f
        commandline --insert -- (string escape -- $f)" "
      end
      commandline -f repaint
    '';
}
