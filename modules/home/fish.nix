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
              # cmux session restore / vault resume types `claude --resume …`
              # into a fresh shell; `devenv shell`'s PTY proxy would swallow
              # that queued line. Take it off the tty before the hook fires and
              # replay it in the hook-spawned devenv shell. The file is removed
              # on first read, so the line runs at most once.
              if test -n "$DEVENV_ROOT"; and set -q _DEVENV_REPLAY
                  if test -f $_DEVENV_REPLAY
                      set -g __devenv_replay_cmd (cat $_DEVENV_REPLAY | string collect)
                      rm -f $_DEVENV_REPLAY
                      function __devenv_replay --on-event fish_prompt
                          functions -e __devenv_replay
                          eval $__devenv_replay_cmd
                      end
                  end
                  set -e _DEVENV_REPLAY
              else if test -z "$DEVENV_ROOT"; and ${pkgs.bash}/bin/bash -c 'read -t 0 </dev/tty' 2>/dev/null; and test -n "$(devenv hook-should-activate 2>/dev/null)"
                  set -gx _DEVENV_REPLAY (mktemp)
                  ${pkgs.bash}/bin/bash -c 'IFS= read -r l </dev/tty; printf %s "$l"' >$_DEVENV_REPLAY
              end
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
