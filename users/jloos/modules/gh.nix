{ ... }:
{

  # GitHub
  programs.gh = {
    enable = true;

    settings = {
      git_protocol = "ssh";
      prompt = "enabled";
    };
  };

  programs.gh-dash.enable = true;

  programs.fish.shellAliases = {
    "e!" = "gh copilot explain";
    "!!" = "gh copilot suggest -t shell";
    "git!" = "gh copilot suggest -t git";
  };
}
