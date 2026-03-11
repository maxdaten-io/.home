{ ... }:
{
  programs.lazygit = {
    enable = true;
    settings = {
      customCommands = [
        {
          key = "<c-g>";
          description = "Generate commit message with Claude";
          context = "files";
          loadingText = "Generating commit message...";
          output = "terminal";
          command = ''git diff --cached | claude -p "Generate a concise git commit message for this diff. Output ONLY the commit message, nothing else. Use conventional commit format." | git commit -F -'';
        }
      ];
    };
  };
}
