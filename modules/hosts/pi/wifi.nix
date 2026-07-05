{
  flake.modules.nixos."hosts/pi" =
    {
      config,
      ...
    }:
    {
      sops.secrets."wireless.env" = {
        restartUnits = [ "wpa_supplicant-wlan0.service" ];
        group = "wheel";
        mode = "0440";
      };

      # Wireless networking (1). You might want to enable this if your Pi is not attached via Ethernet.
      networking.wireless = {
        enable = true;
        interfaces = [ "wlan0" ];
        secretsFile = config.sops.secrets."wireless.env".path;
        networks = {
          "Player Five" = {
            pskRaw = "ext:PLAYER_FIVE";
            priority = 100;
          };
          "Player Two" = {
            pskRaw = "ext:PLAYER_TWO";
            priority = 50;
          };
        };
      };
    };
}
