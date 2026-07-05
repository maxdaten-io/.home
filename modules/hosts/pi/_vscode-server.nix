{
  pkgs,
  ...
}:
{
  services.vscode-server.enable = true;
  services.vscode-server.nodejsPackage = pkgs.nodejs_20;
}
