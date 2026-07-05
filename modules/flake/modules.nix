# Enables the `flake.modules.<class>.<name>` option every dendritic module
# writes into. https://flake.parts/options/flake-parts-modules
{ inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.modules ];
}
