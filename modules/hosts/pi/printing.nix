{
  flake.modules.nixos."hosts/pi" =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      port = 631;
    in
    {
      # Printing
      services.printing = {
        enable = true;
        browsing = true;
        listenAddresses = [ "*:${toString port}" ];
        allowFrom = [ "all" ];
        defaultShared = true;
        extraConf = ''
          DefaultEncryption Never
        '';
        drivers = [
          pkgs.brlaser
        ];
      };

      networking.nftables.firewall = {
        rules.printing = {
          from = [ "local" ];
          to = [ "fw" ];
          allowedTCPPorts = [ port ];
          allowedUDPPorts = [ port ];
        };
      };

      # nginx reverse proxy from /printing to localhost:631
      services.nginx.virtualHosts."${config.networking.fqdnOrHostName}" =
        lib.mkIf config.services.nginx.enable
          {
            locations."/printing/" = {
              proxyPass = "http://127.0.0.1:${toString port}/";
              recommendedProxySettings = true;
              extraConfig = ''
                sub_filter 'href="/' 'href="/printing/';
                sub_filter 'src="/' 'src="/printing/';
                sub_filter_once off;
              '';
            };
          };
    };
}
