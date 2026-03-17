{
  ...
}:
{
  imports = [
    # ./grafana.nix # disabled: NixOS 26.05 requires explicit secret_key
    ./prometheus.nix
  ];
}
