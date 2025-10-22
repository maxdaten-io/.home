{ pkgs, ... }:
{

  home.packages = with pkgs; [ diffnav ];

  # Git
  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "Jan-Philip Loos";
        email = "maxdaten@gmail.com";
      };

      alias = {
        r = "rebase --autostash";
        # https://softwaredoug.com/blog/2022/11/09/idiot-proof-git-aliases.html
        mainbranch = "!git remote show origin | sed -n '/HEAD branch/s/.*: //p'";
        switch-default = "!git switch $(git mainbranch)";
        sd = "switch-default";
        sync = "!git pull origin $(git mainbranch) --rebase";
        update = "!git pull origin $(git rev-parse --abbrev-ref HEAD) --rebase";
        squash = "!git rebase -v -i $(git mainbranch)";
        publish = "push origin HEAD --force-with-lease";
        pub = "publish";
        amend = "commit --amend --no-edit";
        blog = "log --all --decorate --oneline --graph";
      };

      core = {
        autocrlf = "input";
        excludesfile = (pkgs.writeText ".gitignore" (builtins.readFile ./global.gitignore)).outPath;
      };

      column = {
        ui = "auto";
      };

      branch = {
        sort = "-committerdate";
      };

      tag = {
        sort = "version:refname";
      };

      pager = {
        diff = "diffnav";
      };

      diff = {
        algorithm = "histogram";
        colorMoved = "plain";
        mnemonicPrefix = true;
        renames = true;
      };

      pull = {
        rebase = false;
      };

      push = {
        autoSetupRemote = true;
      };

      init = {
        defaultBranch = "main";
      };

      fetch = {
        prune = true;
        pruneTags = true;
        all = true;
      };

      commit = {
        verbose = true;
      };
    };
  };
}
