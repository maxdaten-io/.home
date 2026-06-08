{ ... }:
{
  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
    # Disable zsh integration: only consumed by Claude Code's zsh snapshot shell,
    # where the missing chpwd hook triggers zoxide's doctor warning on every `cd`.
    enableZshIntegration = false;
    options = [
      "--cmd"
      "cd"
    ];
  };

  programs.fish.functions = {
    gz = ''
      if test (count $argv) -eq 0
        open -a Ghostty $PWD
      else
        set -l dir (zoxide query $argv)
        and open -a Ghostty $dir
      end
    '';
  };
}
