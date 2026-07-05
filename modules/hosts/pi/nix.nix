{
  flake.modules.nixos."hosts/pi" =
    { ... }:
    {

      # Nix System
      nix = {
        settings = {
          auto-optimise-store = true;
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          max-jobs = 4;
          cores = 4;
          system-features = [
            # "kvm"
            "nixos-test"
            "benchmark"
            "big-parallel"
          ];
          # extra-platforms = [ "x86_64-linux" ];
          trusted-users = [
            "root"
            "jloos"
            "@wheel"
          ];
        };
        gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 30d";
        };
        # Free up to 1GiB whenever there is less than 100MiB left.
        extraOptions = ''
          min-free = ${toString (100 * 1024 * 1024)}
          max-free = ${toString (1024 * 1024 * 1024)}
          keep-outputs = true
          keep-derivations = true
        '';
      };
    };
}
