{
  self,
  inputs,
  withSystem,
  ...
}:
let
  inherit (inputs.nixpkgs) lib;
  piConfigurations = lib.filterAttrs (
    name: _:
    lib.lists.elem name [
      "pi"
      "pi-minimal"
    ]
  ) self.nixosConfigurations;
  forPiConfigurations = f: lib.concatMapAttrs f piConfigurations;
in
{
  perSystem =
    { pkgs, ... }:
    {
      apps = forPiConfigurations (
        name: _: {
          "nixos-switch-${name}" = {
            type = "app";
            program =
              let
                script = pkgs.writeShellApplication {
                  name = "nixos-switch-${name}";
                  # https://www.haskellforall.com/2023/01/announcing-nixos-rebuild-new-deployment.html
                  text = ''
                    ${lib.getExe pkgs.nixos-rebuild} switch \
                      --flake .#${name} \
                      --target-host pi \
                      --use-remote-sudo \
                      --build-host pi \
                      --fast \
                  '';
                };
              in
              lib.getExe script;
            meta.description = "Deploy NixOS configuration ${name} to Raspberry Pi";
          };
        }
      );
    };

  flake.packages.aarch64-linux = forPiConfigurations (
    name: nixos: {
      "sd-image-${name}" = nixos.config.system.build.sdImage;
    }
  );

  flake.apps.aarch64-darwin = forPiConfigurations (
    name: nixos: {
      "flash-sd-image-${name}" = {
        type = "app";
        program = withSystem "aarch64-darwin" (
          { pkgs, ... }:
          pkgs.writeShellApplication {
            name = "flash-sd-image-${name}";
            runtimeInputs = with pkgs; [
              zstd
              coreutils
            ];
            text = ''
              export img="${nixos.config.system.build.sdImage}/sd-image/${nixos.config.sdImage.imageName}.zst"
              echo "Flashing SD card: $img"
              read -p "Write image $img? (This may take a while) [yn]: " -r WRITE_IMAGE

              case $WRITE_IMAGE in
                [Yy]* )
                    echo "Write image to sd card"
                    diskutil list

                    read -p "Enter device: " -r TARGET_SD

                    echo "Unmounting disk to allow writing to disk"
                    sudo diskutil unmount "$TARGET_SD" || true
                    sudo diskutil unmountDisk "$TARGET_SD"

                    echo "Start writing to disk"
                    TARGET_SD="''${TARGET_SD//disk/rdisk}" # Unbuffered write
                    zstd -d $img -c | sudo dd of="$TARGET_SD" conv=fsync bs=4M iflag=fullblock status=progress

                    echo "✓ Done... ejecting sd"
                    sudo diskutil eject "$TARGET_SD"
                    ;;
                * ) exit;;
              esac
            '';
          }
        );
        meta.description = "Flash SD card with ${name} NixOS image for Raspberry Pi";
      };
    }
  );
}
