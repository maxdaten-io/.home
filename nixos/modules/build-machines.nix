{ ... }:
{
  nix-rosetta-builder = {
    enable = false;
    onDemand = true;
  };

  # Write /etc/nix/machines directly — nix.buildMachines is inert with nix.enable = false.
  # Determinate Nix's nix.conf already has: builders = @/etc/nix/machines
  # environment.etc."nix/machines" = lib.mkIf cfg.enable {
  #   text = ''
  #     ${cfg.sshProtocol}://rosetta-builder aarch64-linux,x86_64-linux - ${toString cfg.cores} ${toString cfg.speedFactor} kvm,benchmark,big-parallel,nixos-test - -
  #   '';
  # };
}
