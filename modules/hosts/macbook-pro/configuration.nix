# scutil --get LocalHostName
{ config, inputs, ... }:
{
  flake.darwinConfigurations."Jan-Philips-MacBook-Pro" = inputs.darwin.lib.darwinSystem {
    modules = [
      config.flake.modules.darwin."hosts/macbook-pro"
      config.flake.modules.darwin.jloos
    ];
  };
}
