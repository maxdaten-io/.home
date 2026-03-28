{ pkgs, config, ... }:

{
  imports = [ ./nix/modules/devenv/treefmt.nix ];

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
      # Local devenv MCP server (uses system-installed devenv 2.0)
      devenv = {
        type = "stdio";
        command = "devenv";
        args = [ "mcp" ];
        env = {
          DEVENV_ROOT = config.devenv.root;
        };
      };
    };
  };
}
