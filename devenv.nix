{ pkgs, config, ... }:

{
  imports = [ ./nix/modules/devenv/treefmt.nix ];

  # Workaround: pre-commit pulls in dotnet-sdk which depends on swift,
  # and swift is broken on Darwin in current nixpkgs-unstable.
  overlays = [
    (_: prev: {
      pre-commit = prev.pre-commit.override { dotnet-sdk = prev.emptyDirectory; };
    })
  ];

  name = ".home shell";

  packages = with pkgs; [
    sops
    age
    ssh-to-age

    just
    nodejs_latest
  ];

  # Claude Code MCP server configuration
  claude.code = {
    enable = true;

    mcpServers = {
      # Local devenv MCP server
      devenv = {
        type = "stdio";
        command = "${pkgs.devenv}/bin/devenv";
        args = [ "mcp" ];
        env = {
          DEVENV_ROOT = config.devenv.root;
        };
      };
    };
  };
}
