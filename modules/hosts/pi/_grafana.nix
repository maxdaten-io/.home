{
  config,
  pkgs,
  ...
}:
let
  grafanaUriPath = "/dashboard/";
  raspberryDashboardSrc = pkgs.fetchFromGitHub {
    # https://github.com/rfmoz/grafana-dashboards
    owner = "rfmoz";
    repo = "grafana-dashboards";
    rev = "cad8539cc4c4ed043935e69b9c1ec23e551806f4";
    sparseCheckout = [
      "prometheus/node-exporter-full.json"
    ];
    sha256 = "sha256-9BYujV2xXRRDvNI4sjimZEB4Z2TY/0WhwJRh5P122rs=";
  };
in
{
  sops.secrets.grafana_admin_password = {
    owner = "grafana";
  };

  # grafana configuration
  services.grafana = {
    enable = true;
    settings = {
      server.http_port = 2342;
      server.http_addr = "127.0.0.1";
      server.root_url = "%(protocol)s://%(domain)s:%(http_port)s${grafanaUriPath}";

      security = {
        admin_user = "jloos";
        admin_password = "$__file{/run/secrets/grafana_admin_password}";
      };
    };
  };

  services.grafana.provision.enable = true;
  services.grafana.provision.datasources.settings = {
    apiVersion = 1;

    datasources = [
      {
        # https://grafana.com/docs/grafana/latest/datasources/prometheus/
        name = "Prometheus";
        type = "prometheus";
        url = "http://127.0.0.1:${toString config.services.prometheus.port}";
      }
    ];
  };

  services.grafana.provision.dashboards.settings = {
    apiVersion = 1;

    providers = [
      {
        # https://grafana.com/docs/grafana/latest/datasources/prometheus/
        name = "Raspberry PI Dashboard";
        type = "file";
        options.path = "${raspberryDashboardSrc}/prometheus";
      }
    ];
  };

  services.avahi.extraServiceFiles.grafana = ''
    <?xml version="1.0" standalone='no'?><!--*-nxml-*-->
    <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
    <service-group>
      <name replace-wildcards="yes">Grafana on %h</name>
      <service>
        <type>_http._tcp</type>
        <port>${toString config.services.grafana.settings.server.http_port}</port>
      </service>
    </service-group>
  '';

  # nginx reverse proxy
  services.nginx.virtualHosts."${config.networking.fqdnOrHostName}" = {
    locations."${grafanaUriPath}" = {
      proxyPass = "http://127.0.0.1:${toString config.services.grafana.settings.server.http_port}/";
      proxyWebsockets = true;
    };
  };

  users.users.prometheus.extraGroups = [ config.users.groups.video.name ];
}
