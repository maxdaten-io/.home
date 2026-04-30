{ ... }:
{
  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
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
