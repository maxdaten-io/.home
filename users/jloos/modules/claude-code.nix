{ pkgs, lib, ... }:
let
  commandsDir = ./claude-code/commands;

  # Discover all command files (*.md files in commands directory)
  commandFiles' = lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".md" name) (
    builtins.readDir commandsDir
  );

  # Generate home.file entries for each command
  commandFiles = lib.mapAttrs' (
    name: _: lib.nameValuePair ".claude/commands/${name}" { source = commandsDir + "/${name}"; }
  ) commandFiles';
in
{
  # Deploy Claude Code commands via Home Manager
  home.file = commandFiles;

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
