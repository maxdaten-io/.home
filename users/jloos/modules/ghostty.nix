{
  config,
  ...
}:
{

  xdg.configFile."ghostty/config".text = ''
    # Theme & Appearance
    theme = atelier-cave

    working-directory = ${config.home.homeDirectory}/Developer

    unfocused-split-opacity = 0.8
    cursor-click-to-move = true
    keybind = option+backspace=text:\x1b\x7f

    font-size = 15
  '';

  # theme
  xdg.configFile."ghostty/themes/atelier-cave".text = ''
    background = 19171c
    foreground = 8b8792

    cursor-color = 8b8792

    palette = 0=#19171c
    palette = 1=#be4678
    palette = 2=#2a9292
    palette = 3=#a06e3b
    palette = 4=#576ddb
    palette = 5=#955ae7
    palette = 6=#398bc6
    palette = 7=#8b8792

    palette = 8=#655f6d
    palette = 9=#aa573c
    palette = 10=#2a9292
    palette = 11=#a06e3b
    palette = 12=#576ddb
    palette = 13=#bf40bf
    palette = 14=#398bc6
    palette = 15=#efecf4

    cursor-style = block
    cursor-style-blink = false
    selection-invert-fg-bg = true
  '';
}
