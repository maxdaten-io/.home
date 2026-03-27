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
          command = ''git diff --cached | claude --model haiku -p "Generate a concise git commit message for this diff. Output ONLY the commit message, nothing else. Use conventional commit format." | git commit -F -'';
        }
        {
          key = "P";
          description = "Push up to selected commit";
          context = "commits";
          loadingText = "Pushing commit...";
          output = "log";
          command = "git push {{.SelectedRemote.Name}} {{.SelectedLocalCommit.Sha}}:{{.SelectedLocalBranch.Name}}";
        }
      ];
    };
  };
}
