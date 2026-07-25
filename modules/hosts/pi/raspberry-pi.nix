# Raspberry Pi hardware/board config — shared by the full `pi` host and the
# minimal `pi-minimal` bootstrap image.
{ inputs, ... }:
{
  flake.modules.nixos.raspberry-pi = {
    # `sd-image` carries the root filesystem and the `sdImage.*` options that
    # modules/hosts/pi/apps.nix builds on. raspberry-pi-nix bundled it into
    # `raspberry-pi` until it was split out after v0.4.0.
    imports = [
      inputs.raspberry-pi-nix.nixosModules.raspberry-pi
      inputs.raspberry-pi-nix.nixosModules.sd-image
    ];

    system.stateVersion = "24.11";
    nixpkgs.hostPlatform.system = "aarch64-linux";

    raspberry-pi-nix.board = "bcm2712";
    raspberry-pi-nix.libcamera-overlay.enable = false;

    # Build the kernel against our own nixpkgs instead of the one
    # raspberry-pi-nix vendors. Pinned, its kernels come from nixpkgs 24.11 and
    # their passthru lacks `buildDTBs` and `target`, which the NixOS modules in
    # current nixpkgs read to default `hardware.deviceTree.enable` and
    # `system.boot.loader.kernelFile`. Costs the upstream cachix kernel cache.
    raspberry-pi-nix.pin-inputs.enable = false;

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
  };
}
