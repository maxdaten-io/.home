{ inputs, ... }:
{
  flake.modules.nixos."hosts/pi" = {
    imports = [ inputs.sops-nix.nixosModules.sops ];

    sops.defaultSopsFile = ./secrets.yaml;
    sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    sops.age.keyFile = "/var/lib/sops-nix/key.txt";
    sops.age.generateKey = true;
  };
}
