{ pkgs, ... }:
{
  programs.k9s = {
    enable = true;

    # Use generators!
    # https://gist.github.com/jmatsushita/5c50ef14b4b96cb24ae5268dab613050#file-home-nix-L52
    plugins = {
      # https://github.com/derailed/k9s/issues/364
      pinologs = {
        shortCut = "Shift-L";
        confirm = false;
        description = "Logs (pino)";
        scopes = [ "po" ];
        command = "${pkgs.sh}/bin/sh";
        background = false;
        args = [
          "-c"
          "kubectl logs $NAME -n $NAMESPACE --context $CONTEXT | pino-pretty -c | less -R"
        ];
      };
    };
  };
}
