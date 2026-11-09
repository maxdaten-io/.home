# Raspberry Pi 5 (bcm2712) hardware/board config — shared by the full `pi` host
# and the minimal `pi-minimal` bootstrap image. Board support comes from
# nvmd/nixos-raspberrypi (replaced the archived raspberry-pi-nix).
{ inputs, ... }:
let
  rpi = inputs.nixos-raspberrypi;
in
{
  flake.modules.nixos.raspberry-pi =
    { lib, pkgs, ... }:
    {
      imports = [
        rpi.lib.inject-overlays # vendor kernel, firmware, bootloader packages
        rpi.nixosModules.trusted-nix-caches # nixos-raspberrypi.cachix.org on the Pi
        rpi.nixosModules.raspberry-pi-5.base
        # system.build.sdImage for the flash apps; also defines fileSystems with
        # the same labels raspberry-pi-nix used (NIXOS_SD, FIRMWARE), so the
        # existing card keeps mounting.
        rpi.nixosModules.sd-image
      ];
      # The board modules read the flake from this argument; set here instead of
      # specialArgs (dendritic: inputs reach modules by lexical capture).
      _module.args.nixos-raspberrypi = rpi;

      system.stateVersion = "24.11";
      nixpkgs.hostPlatform.system = "aarch64-linux";

      # One kernel in /boot/firmware, as raspberry-pi-nix did (uboot off). The
      # sd-image module forces the generational "kernel" bootloader, which keeps
      # every generation's kernel+initrd there — the existing card's FIRMWARE
      # partition is 128 MiB, a few generations would fill it.
      boot.loader.raspberry-pi.bootloader = lib.mkForce "kernelboot";

      # The SD-image module pulls in profiles/base.nix, which enables zfs: an
      # out-of-tree module build against the vendor kernel, never used here.
      boot.supportedFilesystems.zfs = lib.mkForce false;
      # Same import pulls in the generic all-hardware initrd module list (ahci,
      # 3w-9xxx, …) that the vendor kernel may not build; nixos-raspberrypi's
      # disabledModules for it misses (path joined without "/"). The board
      # module brings the ones the Pi needs (mmc_block, pcie_brcmstb, …).
      hardware.enableAllHardware = lib.mkForce false;

      # The system evaluates on our nixpkgs (unstable); the vendor kernel comes
      # prebuilt from nixos-raspberrypi's pin (26.05), whose kernel derivation
      # predates two attributes unstable's modules read: `buildDTBs`
      # (device-tree.nix — the old "attribute 'buildDTBs' missing" CI failure)
      # and `target` (the rpi bootloader on release >= 26.11). Add them as
      # passthru: not part of the derivation, so the drvPath is unchanged and
      # the kernel stays a cache hit; and unlike `//` they survive the
      # `kernel.override` that boot.kernelPackages applies. Values are copied
      # from our stock kernel for the same platform (aarch64: "Image", true).
      # A further missing attribute fails evaluation loudly; that is the cue
      # to recheck.
      boot.kernelPackages = rpi.packages.${pkgs.stdenv.hostPlatform.system}.linuxPackages_rpi5.extend (
        _: super: {
          kernel = super.kernel.overrideAttrs (old: {
            passthru = (old.passthru or { }) // {
              inherit (pkgs.linux) target buildDTBs;
            };
          });
        }
      );

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
