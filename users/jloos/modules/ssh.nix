{ pkgs, ... }:
{
  programs.ssh.enable = true;
  programs.ssh.package = pkgs.openssh;
  programs.ssh.enableDefaultConfig = false;
  programs.ssh.matchBlocks = {
    "enalytics" = {
      hostname = "142.132.133.78";
      user = "jpl";
    };
  };
}
