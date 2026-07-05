{ config, inputs, ... }:
let
  nixos = config.flake.modules.nixos;
in
{
  flake.nixosConfigurations = {
    # minimal pi for bootstrapping and quick testing
    pi-minimal = inputs.nixpkgs.lib.nixosSystem {
      modules = [ nixos.raspberry-pi ];
    };

    # full pi configuration
    pi = inputs.nixpkgs.lib.nixosSystem {
      modules = [
        nixos.raspberry-pi
        nixos."hosts/pi"
        nixos.jloos
      ];
    };
  };
}
