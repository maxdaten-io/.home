{
  flake.modules.nixos."hosts/pi" =
    {
      config,
      ...
    }:
    let
      prometheusUriPath = "/prometheus/";
    in
    {
      services.prometheus.enable = true;
      services.prometheus = {
        globalConfig.scrape_interval = "15s";

        exporters = {
          node = {
            enable = true;
            enabledCollectors = [
              "systemd"
              "wifi"
              "ksmd"
              "processes"
              "meminfo_numa"
            ];
            port = 9000;
          };
        };

        scrapeConfigs = [
          {
            job_name = "node-exporter";
            static_configs = [
              {
                targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ];
              }
            ];
          }
        ];
      };

      services.avahi.extraServiceFiles.prometheus = ''
        <?xml version="1.0" standalone='no'?><!--*-nxml-*-->
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">Prometheus on %h</name>
          <service>
            <type>_http._tcp</type>
            <port>${toString config.services.prometheus.port}</port>
          </service>
        </service-group>
      '';

      # nginx reverse proxy
      services.nginx.virtualHosts."${config.networking.fqdnOrHostName}" = {
        locations."${prometheusUriPath}" = {
          proxyPass = "http://127.0.0.1:${toString config.services.prometheus.port}/";
          proxyWebsockets = true;
        };
      };
    };
}
