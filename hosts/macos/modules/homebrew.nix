{ config, inputs, ... }:
{
  nix-homebrew = {
    enable = true;
    enableRosetta = true;

    user = "jloos";
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
    };

    mutableTaps = false;
  };

  homebrew = {
    enable = true;

    taps = builtins.attrNames config.nix-homebrew.taps;

    global = {
      brewfile = true;
    };

    onActivation = {
      autoUpdate = true;
      # "none" so undeclared casks / Mac App Store apps are never auto-removed.
      # "zap" previously uninstalled+wiped every MAS app not listed in masApps.
      cleanup = "none";
      upgrade = true;
    };

    casks = [
      "keyclu"
      "ghostty"
    ];

    masApps = {
      "Discovery" = 1381004916;
      "WhatsApp" = 310633997;
      "WireGuard" = 1451685025;
      "Strongbox - Password Manager" = 897283731;
      "AusweisApp" = 948660805;
    };
  };
}
