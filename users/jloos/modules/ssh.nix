{ pkgs, ... }:
{
  programs.ssh.enable = true;
  programs.ssh.package = pkgs.openssh;
  programs.ssh.enableDefaultConfig = false;
  programs.ssh.settings = {
    "enalytics" = {
      HostName = "142.132.133.78";
      User = "jpl";
    };
  };
}
