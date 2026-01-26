{ pkgs, ... }:
{
  # https://zed.dev/docs/configuring-zed
  programs.zed-editor = {
    enable = true;

    # Make LSP binaries and formatters available to Zed
    extraPackages = with pkgs; [
      nixd
      nixfmt
    ];

    extensions = [
      "just-ls"
      "just"
      "nix"
      "terraform"
      "dockerfile"
      "toml"
      "sql"
      "zed-log"
      "kotlin"
    ];

    userSettings = {
      # UI and theme settings
      theme = {
        mode = "system";
        light = "One Light";
        dark = "One Dark";
      };
      base_keymap = "JetBrains";

      # Font settings
      ui_font_size = 16;
      ui_font_features = {
        calt = true;
      };
      buffer_font_size = 12;
      buffer_font_fallbacks = [ "JetBrainsMono Nerd Font" ];
      terminal = {
        font_family = "JetBrainsMono Nerd Font";
        line_height = "standard";
        font_size = 14;
      };

      # Features
      features = {
        edit_prediction_provider = "zed";
      };

      # Agent (replaces assistant in new format)
      agent = {
        default_model = {
          provider = "anthropic";
          model = "claude-sonet-4.5-latest";
        };
      };

      # Language-specific settings
      languages = {
        Nix = {
          language_servers = [
            "nixd"
            "!nil"
          ];
        };
        JavaScript = {
          format_on_save = "off";
        };
      };

      # LSP configurations
      lsp = {
        nixd = {
          binary = {
            path_lookup = true;
          };
          settings = {
            formatting = {
              command = [ "nixfmt" ];
            };
          };
        };
        terraform = {
          binary = {
            path_lookup = true;
          };
        };
        tinymist = {
          initialization_options = {
            exportPdf = "onSave";
            outputPath = "$root/$name";
          };
        };
      };

      # Auto-install extensions
      auto_install_extensions = {
        dockerfile = true;
        just = true;
        just-ls = true;
        kotlin = true;
        nix = true;
        sql = true;
        terraform = true;
        toml = true;
        zed-log = true;
      };
    };
  };
}
