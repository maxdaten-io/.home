# Project-scoped Google Cloud credentials.
#
# A directory containing `.gcloud/` owns its own gcloud config *and* credential
# store. Walking into it arms the shell; walking out disarms it. Nothing is
# active by default: a bare shell targets no project, and the starship
# gcloud/kubernetes segments gate on exactly the variables set here — so
# "segment visible" means "a command would hit that project", and an empty
# prompt means an empty blast radius.
#
# Three variables, because no single one reaches every client:
#
#   CLOUDSDK_CONFIG                 gcloud CLI, and python google-auth
#                                   (`_cloud_sdk.get_config_path()` reads it first)
#   GOOGLE_APPLICATION_CREDENTIALS  Go clients, i.e. terraform-provider-google.
#                                   golang.org/x/oauth2/google `wellKnownFile()`
#                                   hardcodes ~/.config/gcloud/… and ignores
#                                   CLOUDSDK_CONFIG entirely; GOOGLE_APPLICATION_-
#                                   CREDENTIALS is checked ahead of it.
#   KUBECONFIG                      kubectl, and where `gcloud container clusters
#                                   get-credentials` writes.
#
# All three are set unconditionally once a scope is found, even when the file
# does not exist yet. A loud "no such file" from terraform beats silently
# falling through to the global credentials of some unrelated project.
{
  flake.modules.homeManager.gcloud-scope = {
    programs.fish.functions = {
      __gcloud_scope = {
        description = "Arm gcloud/kubectl from the nearest project-local .gcloud scope";
        onVariable = "PWD";
        body = ''
          set -l dir $PWD
          while test "$dir" != "$HOME" -a "$dir" != /
              if test -d $dir/.gcloud
                  set -gx CLOUDSDK_CONFIG $dir/.gcloud
                  set -gx GOOGLE_APPLICATION_CREDENTIALS $dir/.gcloud/application_default_credentials.json
                  set -gx KUBECONFIG $dir/.gcloud/kube.config
                  return
              end
              set dir (path dirname $dir)
          end
          set -e CLOUDSDK_CONFIG
          set -e GOOGLE_APPLICATION_CREDENTIALS
          set -e KUBECONFIG
        '';
      };

      gcloud-scope-init = {
        description = "Create a project-local gcloud scope in the current directory";
        body = ''
          set -l scope $PWD/.gcloud
          if test -d $scope
              echo "scope already exists: $scope"
          else
              mkdir -p $scope
              echo "created $scope"
          end
          # The PWD handler cannot fire for a directory we are already in.
          __gcloud_scope
          echo ""
          echo "armed:"
          echo "  CLOUDSDK_CONFIG                $CLOUDSDK_CONFIG"
          echo "  GOOGLE_APPLICATION_CREDENTIALS $GOOGLE_APPLICATION_CREDENTIALS"
          echo "  KUBECONFIG                     $KUBECONFIG"
          echo ""
          echo "next:"
          echo "  gcloud auth login"
          echo "  gcloud auth application-default login"
          echo "  gcloud config set project <PROJECT_ID>"
          echo "  gcloud container clusters get-credentials <CLUSTER> --region <REGION>"
        '';
      };
    };

    # `--on-variable PWD` never fires for the directory the shell starts in, so
    # arm it once by hand. (Registering the handler is already covered: Home
    # Manager notices the event handler and sources the function file eagerly
    # from config.fish, since fish will not autoload one.)
    programs.fish.interactiveShellInit = ''
      __gcloud_scope
    '';
  };
}
