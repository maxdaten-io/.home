{
  flake.modules.homeManager.cmux =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # cmux is installed as a downloaded macOS app that auto-updates itself.
      # It ships a socket-client CLI inside the bundle, but only puts it on PATH
      # inside cmux's own terminals. Expose just that one binary (NOT the whole
      # bin/ dir — it also contains `open`/`ghostty`/`grok` which would shadow
      # system tools). Pointing at the bundle path means app updates need no bump.
      cmux = pkgs.writeShellScriptBin "cmux" ''
        exec /Applications/cmux.app/Contents/Resources/bin/cmux "$@"
      '';

      # One cmux workspace per git worktree; see cmux/cw.sh.
      cw = pkgs.writeShellApplication {
        name = "cw";
        runtimeInputs = [
          cmux
          pkgs.coreutils
          pkgs.gawk
          pkgs.git
          pkgs.gnused
          pkgs.jq
        ];
        text = builtins.readFile ./cmux/cw.sh;
      };
    in
    lib.mkIf pkgs.stdenv.isDarwin {
      home.packages = [
        cmux
        cw
      ];

      # Out-of-store on purpose: cmux hot-reloads sidebars on save, a store
      # symlink would turn every tweak into a `just switch`.
      xdg.configFile."cmux/sidebars/worktrees.js".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Developer/.home/modules/home/cmux/sidebars/worktrees.js";

      # Nix owns cmux.json (read-only); app settings changed in the UI land in
      # Application Support instead. Vault only reads ~/.claude on its own, so
      # the work account (~/.claude-frontrow, picked by the claude wrapper for
      # ~/Developer/frontrow) is registered as an extra JSONL-backed agent.
      # Group order is an app preference (sessionIndex.agentOrder), set by drag.
      xdg.configFile."cmux/cmux.json".text = builtins.toJSON {
        "$schema" = "https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json";
        schemaVersion = 1;
        vault.agents = [
          {
            id = "claude-work";
            name = "Claude (Front Row)";
            iconAssetName = "AgentIcons/Claude"; # only icons bundled in cmux's Assets.car
            sessionIdSource = {
              type = "argvOption";
              argvOption = "--resume";
            };
            resumeCommand = "env CLAUDE_CONFIG_DIR=${config.home.homeDirectory}/.claude-frontrow claude --resume {{sessionId}}";
            cwd = "preserve";
            sessionDirectory = "~/.claude-frontrow/projects";
          }
        ];
      };

      # cmux loads its shell integration only via the outer shell's
      # --init-command, whose fish_prompt reporter sits behind the blocking
      # devenv hook. Load it in the devenv shell too, so cmux sees a ready
      # prompt; the vault's "open session" waits for that before typing.
      programs.fish.interactiveShellInit = ''
        if set -q DEVENV_ROOT; and set -q CMUX_FISH_INTEGRATION_FILE; and not functions -q _cmux_prompt
            source $CMUX_FISH_INTEGRATION_FILE
        end
      '';
    };
}
