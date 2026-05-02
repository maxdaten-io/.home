{ ... }:
{
  programs.broot.enable = true;
  programs.bat.enable = true;
  programs.bash.enable = true;
  programs.bash.enableCompletion = true;
  programs.bash.initExtra = ''
    # devenv auto-activation: https://devenv.sh/auto-activation/
    if command -v devenv >/dev/null 2>&1; then
      eval "$(devenv hook bash)"
    fi
  '';
  programs.zsh.enable = true;
  programs.zsh.enableCompletion = true;
  programs.zsh.initContent = ''
    # devenv auto-activation: https://devenv.sh/auto-activation/
    if command -v devenv >/dev/null 2>&1; then
      eval "$(devenv hook zsh)"
    fi
  '';
}
