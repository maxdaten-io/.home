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
    python3 # Required for mdformat in treefmt
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
