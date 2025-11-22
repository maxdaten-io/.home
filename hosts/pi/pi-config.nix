{ ... }:

{
  system.stateVersion = "24.11";
  nixpkgs.hostPlatform.system = "aarch64-linux";

  raspberry-pi-nix.board = "bcm2712";
  raspberry-pi-nix.libcamera-overlay.enable = false;

  hardware = {
    raspberry-pi.config = {
      all = {
        options = {
          camera_auto_detect.enable = false;

          arm_boost.enable = true;
          arm_boost.value = true;

          otg_mode.enable = true;
          otg_mode.value = true;
        };
        # https://github.com/raspberrypi/linux/blob/c8c99191e1419062ac8b668956d19e788865912a/arch/arm/boot/dts/overlays/README#L222-L224
        base-dt-params = {
          hdmi = {
            enable = true;
            value = "off";
          };
          pcie = {
            enable = true;
            value = "off";
          };
          act_led_trigger = {
            enable = true;
            value = "heartbeat";
          };
          # krnbt = {
          #   # enable autoprobing of bluetooth driver
          #   enable = true;
          #   value = "off";
          # };
        };
        dt-overlays = {
          disable-bt = {
            enable = true;
            params = { };
          };
        };
      };
    };
  };
}
