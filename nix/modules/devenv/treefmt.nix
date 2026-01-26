{
  inputs,
  pkgs,
  lib,
  ...
}:

let
  treefmtConfig = inputs.treefmt-nix.lib.evalModule pkgs {
    projectRootFile = "flake.nix";

    # Nix formatting
    programs.nixfmt.enable = true;
    programs.deadnix.enable = true;

    # JSON formatting
    programs.prettier = {
      enable = true;
      includes = [ "*.json" ];
      excludes = [
        ".vscode/*.json"
        "secrets/*.yaml"
        "**/secrets.yaml"
      ];
    };

    # Shell formatting
    programs.shellcheck.enable = true;
    programs.shfmt.enable = true;

    # YAML formatting
    programs.yamlfmt = {
      enable = true;
      includes = [ "*.yaml" ];
      excludes = [
        ".sops.yaml"
        "secrets/*.yaml"
        "**/secrets.yaml"
      ];
    };

    # Markdown formatting
    programs.mdformat.enable = true;
  };
in
{
  packages = [
    treefmtConfig.config.build.wrapper
  ]
  ++ (lib.attrValues treefmtConfig.config.build.programs);

  git-hooks.hooks.treefmt = {
    enable = true;
    package = treefmtConfig.config.build.wrapper;
  };
}
