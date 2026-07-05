{
  flake.modules.nixos."hosts/pi" =
    {
      pkgs,
      ...
    }:
    {
      nixpkgs.config.allowUnfree = true;

      system.stateVersion = "24.11";

      environment.shells = with pkgs; [
        bashInteractive
        fish
        zsh
      ];

      boot.growPartition = true;
      boot.loader.timeout = 3;
      # boot.kernelModules = [ "kvm-amd" "kvm-intel" ];

      environment.systemPackages = with pkgs; [
        # system tools
        libraspberrypi
        raspberrypi-eeprom

        # minimal tools
        vim
        gitMinimal
        bash
        fish
        ncurses
        stress
        fastfetch
      ];

      # Select internationalisation properties.
      time.timeZone = "Europe/Berlin";
      i18n.defaultLocale = "en_US.UTF-8";

      # NTP time sync.
      services.timesyncd.enable = true;

      services.openssh.enable = true;
      services.openssh.settings.PermitRootLogin = "yes";

      # User & Additional
      users.users = {
        root = {
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIElfsEDFF7jnwSFGXsxbhvsHpBOMsjOAcQseFAtdbB0Z jloos@macos"
            # Generated via: ssh-keygen -t ed25519-sk -O resident -O application=ssh:macbook-pro -O verify-required
            # https://developers.yubico.com/SSH/Securing_SSH_with_FIDO2.html
            "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAII/TQ6VaYALM58rbQCHOwFt52Kzrt1CzmQJF0566/VALAAAAD3NzaDptYWNib29rLXBybw== jloos@macos"
          ];
        };
      };

      security.sudo.wheelNeedsPassword = false;

      # Virtualisation, enable emulation of other systems
      virtualisation.libvirtd.enable = true;
      security.polkit.enable = true;

      hardware.bluetooth = {
        enable = false;
        powerOnBoot = false;
      };
    };
}
