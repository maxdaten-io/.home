{
  flake.modules.homeManager.fish =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      isDarwin = pkgs.stdenv.isDarwin;
      trace = false; # like set -x
    in
    {
      programs.fish.enable = true;
      programs.fish = {
        plugins = with pkgs.fishPlugins; [
          # https://mynixos.com/search?q=fishPlugins
          {
            # Desktop notifications when long-running commands finish
            name = "done";
            src = done.src;
          }
          {
            # Colorizes man page output
            name = "colored-man-pages";
            src = colored-man-pages.src;
          }
          {
            # FZF key bindings (Ctrl-R history, Ctrl-T file finder, Alt-C cd)
            name = "fzf";
            src = fzf.src;
          }
          {
            # Auto-closes brackets, quotes, and other paired characters
            name = "autopair";
            src = autopair.src;
          }

        ];

        shellAbbrs = lib.mkMerge [
          {
            gitco = "git checkout";
            gitrb = "git rebase --autostash";
            gitcm = "git commit -m";
            gitca = "git commit --amend --no-edit";

            tp = "terraform plan";
            ta = "terraform apply";
            tay = "terraform apply --yes";

            # kubens/kubectx open an fzf picker when run with no argument
            kn = "kubens";
            kx = "kubectx";

            lg = "lazygit";
            # Handy for nix shells with deep folder structures
            cdr = "cd $DEVENV_ROOT";
          }
          (lib.mkIf isDarwin {
            # Install nix-darwin (initially)
            # nix run nix-darwin -- switch --flake ${config.home.homeDirectory}/Workspace/.home/"
            nix-switch = "darwin-rebuild switch --flake ${config.home.homeDirectory}/Developer/.home/";
          })
        ];

        shellAliases = {
          k = "kubectl";
          br = "broot";
          ls = "${pkgs.lsd}/bin/lsd -l";
          zed = "zeditor";
          agy = "/Applications/Antigravity.app/Contents/MacOS/Electron";
          dev = "devenv shell -- $SHELL";
          claude-yolo = "claude --allow-dangerously-skip-permissions";
        };

        shellInit = ''
          ${if trace then "set -U fish_trace 2" else "set -e fish_trace"}
          set -U fish_greeting
          set __done_enabled
        '';

        interactiveShellInit = ''
          # devenv auto-activation: https://devenv.sh/auto-activation/
          if command -q devenv
              devenv hook fish | source
          end
        '';

        functions.fish_reload = "source ~/.config/fish/config.fish";

        functions.__gwt_preview = ''
          set -l p $argv[1]
          set -l home_rel (string replace -r "^$HOME" "~" $p)
          set -l branch (git -C $p rev-parse --abbrev-ref HEAD 2>/dev/null)
          set -l upstream (git -C $p rev-parse --abbrev-ref --symbolic-full-name "@{upstream}" 2>/dev/null)
          echo "path:   $home_rel"
          echo "local:  $branch"
          if test -n "$upstream"
              echo "remote: $upstream"
          else
              echo "remote: none"
          end
          echo ""
          git -C $p log --oneline -10 --decorate 2>/dev/null
        '';

        functions.gwt = ''
          set -l selected (git worktree list | awk '{
            path = $1
            n = split(path, parts, "/")
            name = parts[n]
            printf "%s\t%s %s\n", path, name, $3
          }' | fzf --reverse --border \
              --with-nth=2.. \
              --preview 'fish -c "__gwt_preview {1}"' \
              --preview-window=right:60%:wrap \
              | awk '{print $1}')

          if test -n "$selected"
              cd $selected
          end
        '';

        # fj — pick and run a just recipe (preview shows the recipe body)
        functions.fj = ''
          set -l recipe (just --summary 2>/dev/null | tr ' ' '\n' | fzf --reverse --border \
              --prompt 'just ❯ ' \
              --preview 'just --show {1}' \
              --preview-window 'right:60%:wrap')
          test -z "$recipe"; and return
          echo "just $recipe"
          just $recipe
        '';

        # frec — pick a Flux kustomization, then act on it
        #   enter: reconcile │ ctrl-s: suspend │ ctrl-r: resume
        functions.frec = ''
          set -l out ( \
            flux get kustomizations -A 2>/dev/null | fzf --reverse --border \
                --header-lines=1 \
                --header 'enter: reconcile │ ctrl-s: suspend │ ctrl-r: resume' \
                --expect=enter,ctrl-s,ctrl-r \
                --preview 'flux get kustomization {2} -n {1}' \
                --preview-window 'down:45%:wrap' \
          )
          test -z "$out"; and return
          set -l key $out[1]
          set -l ns (echo $out[2] | awk '{print $1}')
          set -l name (echo $out[2] | awk '{print $2}')
          test -z "$name"; and return
          switch $key
              case ctrl-s
                  flux suspend kustomization $name -n $ns
              case ctrl-r
                  flux resume kustomization $name -n $ns
              case '*'
                  flux reconcile kustomization $name -n $ns
          end
        '';

        # frg — interactive ripgrep; open the chosen match in $EDITOR at its line
        functions.frg = ''
          set -l rg 'rg --column --line-number --no-heading --color=always --smart-case'
          set -l picked ( \
            fzf --ansi --disabled --reverse --border \
                --prompt 'rg ❯ ' \
                --bind "start:reload:$rg {q} || true" \
                --bind "change:reload:$rg {q} || true" \
                --delimiter ':' \
                --preview 'bat --style=numbers --color=always --highlight-line {2} {1}' \
                --preview-window 'right:60%:+{2}+3/3' \
          )
          test -z "$picked"; and return
          set -l parts (string split ':' -- $picked)
          set -l file $parts[1]
          set -l line $parts[2]
          set -l col $parts[3]
          set -l ed (string split ' ' -- $EDITOR)
          switch (basename $ed[1])
              case vim nvim vi
                  command $ed[1] +$line "$file"
              case '*'
                  command $ed[1] "$file:$line:$col"
          end
        '';

      };
    };
}
