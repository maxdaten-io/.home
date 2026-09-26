# Nix-owned keys of each Claude Code account's mutable settings.json.
#
# Home Manager's upstream `programs.claude-code` links settings.json read-only
# into the store, which breaks as soon as Claude saves a permission. Instead each
# profile's patch is deep-merged into the file on activation (jq `*`): keys set
# here are owned by Nix (arrays such as permissions.deny are replaced wholesale),
# everything else Claude writes (permissions.allow, model, hooks) is left alone.
# Removing a key here does NOT remove it from the file; set it to false instead.
#
# The baseline trims the system prompt sent on every request — recipe:
# https://aihero.dev/s/D9UXCK (Matt Pocock). Measure with `/context` before and
# after a change.
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

      # Every prompt-affecting settings key as of claude-code 2.1.283 (read from
      # the binary's settings schema), written out so a profile only flips values.
      baseSettings = {
        enableArtifact = false; # replaces the deprecated disableArtifact
        disableWorkflows = false; # Workflow tool; used for multi-agent runs
        # true: bundled skills/workflows removed; built-in slash commands stay
        # typable but hidden from the model.
        disableBundledSkills = false;
        disableClaudeAiConnectors = true; # claude.ai cloud MCP connectors
        disableRemoteControl = false; # claude.ai/code, `claude remote-control`
        disableAgentView = false; # `claude agents`, --bg, /background
        includeGitInstructions = true; # built-in commit/PR workflow prompt
        # Per skill: "on" | "name-only" (no description) | "user-invocable-only"
        # (hidden from model, /name still works) | "off".
        skillOverrides = { };
      };

      # Built-in tools; false = bare-name permissions.deny entry, which drops the
      # schema from the payload (a scoped rule like "Bash(rm *)" only blocks calls).
      # Deferred tools (loaded via ToolSearch) cost ~a name each until loaded, so
      # denying them saves little; the always-loaded ones are marked (L).
      # Glob/Grep are absent: the native binary folds them into Bash.
      baseTools = {
        Agent = true; # (L)
        Artifact = true; # (L) gated by enableArtifact above
        ArtifactComments = true;
        ArtifactData = true;
        AskUserQuestion = true; # (L)
        Bash = true; # (L)
        CronCreate = true; # /loop <interval>
        CronDelete = true;
        CronList = true;
        DesignSync = false;
        Edit = true; # (L)
        EndConversation = true;
        EnterPlanMode = true;
        EnterWorktree = true; # (L)
        ExitPlanMode = true;
        ExitWorktree = true;
        LSP = true;
        ListAgents = true; # (L)
        ListMcpResourcesTool = true;
        Monitor = true;
        NotebookEdit = false;
        PushNotification = true;
        Read = true; # (L)
        ReadMcpResourceDirTool = true;
        ReadMcpResourceTool = true;
        RemoteTrigger = false; # /schedule cloud routines
        ReportFindings = true; # (L) /code-review
        ScheduleWakeup = true; # (L) dynamic /loop
        SendFeedback = false; # (L)
        SendMessage = true;
        Skill = true; # (L)
        TaskCreate = true; # Task*: bg jobs, progress tracking
        TaskGet = true;
        TaskList = true;
        TaskStop = true;
        TaskUpdate = true;
        ToolSearch = true; # (L) never deny: loads every deferred tool
        WebFetch = true;
        WebSearch = true;
        Workflow = true; # (L)
        Write = true; # (L)
      };

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
              description = "settings.json keys owned by Nix; baseline keys are mkDefault.";
            };
            tools = lib.mkOption {
              type = lib.types.attrsOf lib.types.bool;
              default = { };
              description = "Built-in tool name -> enabled; false becomes a permissions.deny entry.";
            };
          };
          config = {
            settings = lib.mapAttrs (_: lib.mkDefault) baseSettings;
            tools = lib.mapAttrs (_: lib.mkDefault) baseTools;
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
