{ config, ... }:
{
  sops = {
    defaultSopsFile = ../secrets.yaml;
    age = {
      sshKeyPaths = [ "/Users/jloos/.ssh/id_ed25519" ];
      keyFile = "/Users/jloos/.config/sops/age/keys.txt";
      generateKey = true;
    };
    secrets = {
      GITHUB_TOKEN = {
        mode = "0400";
        owner = config.users.users.jloos.name;
      };
    };
  };

  # Create a template file with the GitHub token in the correct format
  sops.templates.github-access-token = {
    content = ''
      access-tokens = github.com=${config.sops.placeholder.GITHUB_TOKEN}
    '';
    mode = "0444";
  };
}
