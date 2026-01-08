{ pkgs, lib, ... }:
let
  skillsDir = ./claude-code/skills;
  pluginsSkillsDir = ./claude-code/plugins/skills;
  commandsDir = ./claude-code/commands;

  # Discover all skill directories (folders containing SKILL.md)
  localSkillDirs = lib.filterAttrs (
    name: type: type == "directory" && builtins.pathExists (skillsDir + "/${name}/SKILL.md")
  ) (builtins.readDir skillsDir);

  # Discover skills from plugins submodule (if it exists)
  pluginSkillDirs =
    if builtins.pathExists pluginsSkillsDir then
      lib.filterAttrs (
        name: type: type == "directory" && builtins.pathExists (pluginsSkillsDir + "/${name}/SKILL.md")
      ) (builtins.readDir pluginsSkillsDir)
    else
      { };

  # Discover all command files (*.md files in commands directory)
  commandFiles' = lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".md" name) (
    builtins.readDir commandsDir
  );

  # Generate home.file entries for local skills
  localSkillFiles = lib.mapAttrs' (
    name: _:
    lib.nameValuePair ".claude/skills/${name}/SKILL.md" { source = skillsDir + "/${name}/SKILL.md"; }
  ) localSkillDirs;

  # Generate home.file entries for plugin skills
  pluginSkillFiles = lib.mapAttrs' (
    name: _:
    lib.nameValuePair ".claude/skills/${name}/SKILL.md" {
      source = pluginsSkillsDir + "/${name}/SKILL.md";
    }
  ) pluginSkillDirs;

  # Merge all skill files (plugins can override local skills with same name)
  skillFiles = localSkillFiles // pluginSkillFiles;

  # Generate home.file entries for each command
  commandFiles = lib.mapAttrs' (
    name: _: lib.nameValuePair ".claude/commands/${name}" { source = commandsDir + "/${name}"; }
  ) commandFiles';
in
{
  # Deploy all Claude Code skills and commands via Home Manager
  home.file = skillFiles // commandFiles;

  home.packages = with pkgs; [
    (pkgs.buildNpmPackage rec {
      pname = "claude-code";
      version = "2.0.76";

      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
        hash = "sha256-/KOZNv+OkxDI5MaDPWRVNBuSrNkjF3hfD3c+50ORudk=";
      };

      npmDepsHash = "sha256-BF6dsCmTA8auNquXCt71fWNQ1gRktZlmPuziVY2/ttk=";

      # Get with `npm install @anthropic-ai/claude-code --package-lock-only`
      postPatch = ''
        cp ${./claude-code/package-lock.json} package-lock.json
      '';

      dontNpmBuild = true;

      env.AUTHORIZED = "1";

      postInstall = ''
        wrapProgram $out/bin/claude \
          --set DISABLE_AUTOUPDATER 1 \
          --unset DEV
      '';

      nativeBuildInputs = [ pkgs.makeWrapper ];

      meta = with pkgs.lib; {
        description = "Claude Code - AI-powered coding assistant";
        homepage = "https://www.npmjs.com/package/@anthropic-ai/claude-code";
        license = licenses.unfree;
        mainProgram = "claude";
      };
    })
  ];
}
