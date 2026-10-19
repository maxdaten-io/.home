{ pkgs, config, ... }:

let
  guard-commit = pkgs.writeShellApplication {
    name = "guard-commit";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ./scripts/guard-commit.sh;
  };
in
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

    hooks.guard-commit = {
      hookType = "PreToolUse";
      matcher = "^Bash$";
      command = "${guard-commit}/bin/guard-commit";
    };
  };

  # Pre-commit, not the Claude PostToolUse hook: most sidebar edits go through
  # sed/python in Bash, which that hook never sees.
  git-hooks.hooks.cmux-sidebar = {
    enable = true;
    name = "cmux sidebar tests";
    entry = "bash modules/home/cmux/_tests/run.sh";
    files = "^modules/home/cmux/(sidebars|_tests)/";
    pass_filenames = false;
  };
  git-hooks.hooks.guard-commit = {
    enable = true;
    name = "guard-commit tests";
    entry = "bash scripts/guard-commit-test.sh";
    files = "^scripts/guard-commit";
    pass_filenames = false;
  };
  # ~20 s, so pre-push and only when Nix inputs change. CI can't cover this:
  # `Check Flake` is red on the pi config and never builds darwin.
  git-hooks.hooks.darwin-eval = {
    enable = true;
    name = "darwin config evaluates";
    entry = ''nix eval .#darwinConfigurations."Jan-Philips-MacBook-Pro".config.system.build.toplevel.drvPath'';
    files = "(\\.nix|flake\\.lock)$";
    pass_filenames = false;
    stages = [ "pre-push" ];
  };
}
