{ inputs, ... }:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.nnf.nixosModules.default
    ./configuration.nix
    ./pi-config.nix
    ./network.nix
    ./printing.nix
    ./nix-config.nix
    ./system-dashboard
    ../../nixos/modules/my-networks
  ];

  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.age.generateKey = true;
}
