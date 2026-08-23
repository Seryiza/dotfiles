{ ... }:
{
  # Requires uinput + udev rules configured in nixos/configuration.nix.
  services.xremap = {
    enable = true;
    withWlroots = true;
    watch = true;
    debug = false;

    # Keep modifier ownership here so Caps-based chords pass through keymap
    # rules before xremap emits the synthetic Control event.
    config.modmap = [{
      name = "Global";
      remap = {
        "CapsLock" = "Control_L";
        "KEY_F23" = "Control_R";
      };
    }];

    config.keymap = [{
      name = "Escape on Ctrl+[";
      remap = { "C-KEY_LEFTBRACE" = "Esc"; };
    }];
  };
}
