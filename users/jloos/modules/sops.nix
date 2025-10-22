{ config, ... }:
{
  sops = {
    defaultSopsFile = ../secrets.yaml;
    age.sshKeyPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    age.generateKey = true;

    secrets.OPENAI_API_KEY = {
      path = "${config.home.homeDirectory}/.config/openai/OPENAI_API_KEY";
    };
  };

  home.sessionVariables = {
    SOPS_AGE_KEY_FILE = "/Users/jloos/.config/sops/age/keys.txt";
    SOPS_AGE_KEY_DIRECTORY = "/Users/jloos/.config/sops/age";
  };
}
