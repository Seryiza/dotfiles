{ ... }:
{
  # Requires uinput + udev rules configured in nixos/configuration.nix.
  services.xremap = {
    enable = true;
    withWlroots = true;
    watch = true;
    debug = false;

    config.modmap = [{
      name = "Global";
      remap = {
        "KEY_F23" = "Control_R";
      };
    }];

    config.keymap = [{
      name = "Escape on Ctrl+[";
      remap = { "C-KEY_LEFTBRACE" = "Esc"; };
    }];
  };
}
