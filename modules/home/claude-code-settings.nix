# Nix-owned keys of each Claude Code account's mutable settings.json.
#
# Home Manager's upstream `programs.claude-code` links settings.json read-only
# into the store, which breaks as soon as Claude saves a permission. Instead each
# profile's patch is deep-merged into the file on activation (jq `*`): keys set
# here are owned by Nix (arrays such as permissions.deny are replaced wholesale),
# everything else Claude writes (permissions.allow, model, hooks) is left alone.
# Removing a key here does NOT remove it from the file; set it to false instead.
#
# Profiles are declared in ./claude-code.nix.
{
  flake.modules.homeManager.claude-code =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      json = pkgs.formats.json { };

      profile =
        { name, ... }:
        {
          options = {
            configDir = lib.mkOption {
              type = lib.types.str;
              default = ".${name}";
              description = "CLAUDE_CONFIG_DIR, relative to $HOME.";
            };
            settings = lib.mkOption {
              inherit (json) type;
              default = { };
              description = "settings.json keys owned by Nix.";
            };
            tools = lib.mkOption {
              type = lib.types.attrsOf lib.types.bool;
              default = { };
              description = "Built-in tool name -> enabled; false becomes a permissions.deny entry.";
            };
          };
        };

      patchFor =
        p:
        p.settings
        // {
          permissions.deny = lib.attrNames (lib.filterAttrs (_: enabled: !enabled) p.tools);
        };
    in
    {
      options.claude.profiles = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule profile);
        default = { };
        description = "Claude Code accounts, one per CLAUDE_CONFIG_DIR.";
      };

      config.home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.concatStrings (
          lib.mapAttrsToList (name: p: ''
            f="$HOME/${p.configDir}/settings.json"
            tmp=$(mktemp)
            { [ -s "$f" ] && cat "$f" || echo '{}'; } \
              | ${pkgs.jq}/bin/jq --slurpfile p ${json.generate "claude-settings-${name}.json" (patchFor p)} \
                  '. * $p[0]' > "$tmp"
            if cmp -s "$tmp" "$f"; then
              rm "$tmp"
            else
              run mkdir -p "$HOME/${p.configDir}"
              chmod 644 "$tmp"
              run mv "$tmp" "$f"
            fi
          '') config.claude.profiles
        )
      );
    };
}
