{
  pkgs,
  config,
  ...
}:
{
  # https://daiderd.com/nix-darwin/manual/index.html
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;
  system.stateVersion = 5;
  ids.gids.nixbld = 350;
  system.primaryUser = "jloos";

  environment.systemPackages = with pkgs; [
    fish
    git
    cachix
    curl
    rsync
    mas

    nixfmt-rfc-style
    nixd
    devenv
    direnv
  ];

  nix.enable = false;

  environment.etc."nix/nix.custom.conf".text = pkgs.lib.mkForce ''
    # Written by hosts/macos/configuration.nix
    # The contents below are based on options specified at installation time.
    substituters = https://cache.nixos.org/ https://maxdaten-io.cachix.org
    trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= maxdaten-io.cachix.org-1:ZDDi/8gGLSeUEU9JST6uXDcQfNp2VZzccmjUljPHHS8=
    trusted-users = root @admin

    !include ${config.sops.templates.github-access-token.path}
  '';

  # init nix in zsh & fish
  programs.fish.enable = true;
  environment.shells = with pkgs; [
    bashInteractive
    fish
    zsh
  ];
  environment.loginShellInit = ''
    export PATH=$HOME/.local/bin:$PATH
  '';
  environment.variables.LANG = "en_US.UTF-8";

  security.pam.services.sudo_local.touchIdAuth = true;
}
