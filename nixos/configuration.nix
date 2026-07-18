# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, nixpkgs-unstable, sysc-greet, ... }:
let
  unstable-pkgs = import nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config = pkgs.config;
  };

  swaySession = (pkgs.runCommand "00-sway-uwsm-session" {} ''
    mkdir -p $out/share/wayland-sessions
    cat > $out/share/wayland-sessions/00-sway-uwsm.desktop <<EOF
    [Desktop Entry]
    Name=Sway
    Comment=Sway compositor managed by UWSM
    Exec=${config.programs.uwsm.package}/bin/uwsm start -F -- /run/current-system/sw/bin/sway
    Type=Application
    EOF
  '').overrideAttrs {
    passthru.providedSessions = [ "00-sway-uwsm" ];
  };

  rocmEnv = pkgs.symlinkJoin {
    name = "rocm-combined";
    paths = with pkgs.rocmPackages; [
      clr
      clr.icd
      hipblas
      rocblas
      rocminfo
      rocm-smi
    ];
  };
in {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [ ];
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  boot.kernelPackages = unstable-pkgs.linuxPackagesFor unstable-pkgs.linux_latest;
  boot.kernelParams = [ ];
  boot.initrd.kernelModules = [ "amdgpu" ];
  boot.kernelModules = [ "amdxdna" ];
  boot.supportedFilesystems = [ "ntfs" ];
  boot.blacklistedKernelModules = [ "nouveau" "nvidiafb" ];
  boot.kernelPatches = [ ];

  # Bootloader
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot";
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "nodev";
  boot.loader.grub.configurationLimit = 5;
  boot.loader.grub.useOSProber = true;
  boot.loader.grub.efiSupport = true;

  zramSwap = {
    enable = true;
    memoryPercent = 200;
  };

  boot.kernel.sysctl = {
    "vm.swappiness" = 100;
    "vm.page-cluster" = 0;
  };

  hardware.amdgpu.initrd.enable = true;
  hardware.amdgpu.opencl.enable = true;

  hardware.cpu.amd.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;
  services.fwupd.enable = true;

  systemd.tmpfiles.rules =
    [ "L+    /opt/rocm   -    -    -     -    ${rocmEnv}" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [ libvdpau-va-gl libva-vdpau-driver ];
  };

  hardware.nvidia = {
    open = true;
    modesetting.enable = true;
    powerManagement.finegrained = true;
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true;
      amdgpuBusId = "PCI:101:0:0";
      nvidiaBusId = "PCI:100:0:0";
    };
  };

  hardware.nvidia-container-toolkit.enable = true;
  # When the NVIDIA driver changes, `switch` can activate new userspace
  # libraries while the old kernel module remains loaded until reboot.
  systemd.services.nvidia-container-toolkit-cdi-generator.restartIfChanged =
    false;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.blueman.enable = true;

  time.timeZone = "Asia/Bishkek";
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.supportedLocales = [ "all" ];

  networking.hostName = "yuri-alpha";

  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.backend = "iwd";

  networking.wireless.iwd.enable = true;
  networking.wireless.iwd.settings = {
    General = {
      RoamThreshold = -75;
      RoamThreshold5G = -80;
      RoamRetryInterval = 20;
    };
  };

  services.nscd.enableNsncd = true;

  networking.nftables.enable = true;

  networking.firewall = {
    enable = true;
    extraInputRules = ''
      iifname "docker0" accept
      iifname "br-*" accept
    '';

    allowedTCPPorts = [
      # SSH
      22

      # Samba
      139
      445

      # CUPS (printing)
      631

      # Syncthing (transfer)
      22000
    ];

    allowedUDPPorts = [
      # Samba
      137
      138

      # mDNS (printer discovery)
      5353

      # Syncthing (local discovery + QUIC)
      21027
      22000
    ];

    allowedTCPPortRanges = [
      # KDE Connect
      {
        from = 1714;
        to = 1764;
      }
    ];

    allowedUDPPortRanges = [
      # KDE Connect
      {
        from = 1714;
        to = 1764;
      }
    ];
  };

  security.rtkit.enable = true;
  security.polkit.enable = true;

  # sudo
  security.sudo.extraConfig = ''
    Defaults timestamp_timeout=-1
  '';

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };

  programs.dconf.enable = true;
  programs.autojump.enable = true;
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [ stdenv.cc.cc.lib ];

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  programs.ssh = { startAgent = true; };

  services.openssh.enable = true;

  environment.localBinInPath = true;

  environment.systemPackages = with pkgs; [
    swaySession
    glibcLocales
    busybox
    iputils
  ];

  environment.variables = { QT_QPA_PLATFORM = "wayland"; };

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  environment.sessionVariables.BROWSER = "firefox";

  virtualisation.docker.enable = true;
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
    daemon.settings = { host-gateway-ips = [ "10.0.2.2" ]; };
  };

  systemd.user.services.docker.environment = {
    DOCKERD_ROOTLESS_ROOTLESSKIT_DISABLE_HOST_LOOPBACK = "false";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  services.tailscale.enable = true;

  services.searx = {
    enable = true;
    configureUwsgi = true;
    environmentFile = "/var/lib/searxng/searx.env";
    uwsgiConfig = {
      http = "127.0.0.1:18888";
      disable-logging = true;
    };
    settings = {
      use_default_settings.engines.keep_only =
        [ "brave" "duckduckgo" "startpage" "bing" ];
      general.instance_name = "SearXNG";
      search = {
        autocomplete = "duckduckgo";
        formats = [ "html" "json" ];
        safe_search = 0;
      };
      server = {
        image_proxy = true;
        limiter = false;
        secret_key = "$SEARX_SECRET_KEY";
      };
      engines = [
        {
          name = "brave";
          disabled = false;
          timeout = 5.0;
        }
        {
          name = "duckduckgo";
          disabled = false;
          timeout = 5.0;
        }
        {
          name = "startpage";
          disabled = false;
          timeout = 5.0;
        }
        {
          name = "bing";
          disabled = false;
          timeout = 5.0;
        }
      ];
    };
  };

  # Samba
  services.samba = { enable = true; };

  services.clamav = {
    daemon.enable = true;
    updater.enable = true;
    updater.interval = "daily";
  };

  services.flatpak.enable = true;

  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "amdgpu" "nvidia" ];
  services.xserver.displayManager.lightdm.enable = false;
  services.xserver.displayManager.lightdm.greeters.gtk.enable = false;

  services.xserver = {
    dpi = 180;
    xkb = {
      variant = "";
      layout = "us";
    };
  };

  services.sysc-greet = {
    enable = true;
    compositorCommand = "${sysc-greet.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/sysc-greet";
  };

  programs.sway = {
    enable = true;
    package = null;
  };

  services.displayManager.sessionPackages = [ swaySession ];

  programs.uwsm = {
    enable = true;
    waylandCompositors = {};
  };

  services.dbus.enable = true;

  qt = {
    enable = true;
    style = "adwaita";
    platformTheme = null;
  };

  environment.pathsToLink =
    [ "/share/xdg-desktop-portal" "/share/applications" ];

  services.gvfs.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;

  services.seatd.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  xdg.portal = {
    enable = true;
    wlr = {
      enable = true;
      settings.screencast = {
        chooser_type = "dmenu";
        chooser_cmd = "${pkgs.wmenu}/bin/wmenu -i -b -l 10 -f 'Iosevka 14' -p 'Share: '";
      };
    };
    extraPortals = with pkgs; [ xdg-desktop-portal-gtk ];
  };

  hardware.uinput.enable = true;
  programs.ydotool.enable = true;
  services.udev = {
    # NOTE: Xremap requires the following:
    # https://github.com/xremap/xremap?tab=readme-ov-file#running-xremap-without-sudo
    extraRules = ''
      KERNEL=="uinput", GROUP="input", TAG+="uaccess"
      KERNEL=="accel*", GROUP="render", MODE="0660"
    '';
  };

  users.users.seryiza = {
    isNormalUser = true;
    description = "Sergey Zaborovsky";
    extraGroups = [
      "audio"
      "video"
      "render"
      "seat"
      "input"
      "uinput"
      "ydotool"
      "networkmanager"
      "wheel"
      "docker"
      "tty"
      "sway"
    ];
  };

  system.stateVersion = "23.11";
}
