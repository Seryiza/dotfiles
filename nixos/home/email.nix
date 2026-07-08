{ config, lib, pkgs, ... }:
let
  inherit (lib) concatStringsSep filter flatten;

  maildir = "${config.home.homeDirectory}/Maildir";

  muAccounts = filter (a: a.enable && a.mu.enable)
    (lib.attrValues config.accounts.email.accounts);

  addresses = map (a: a.address) muAccounts
    ++ map (alias: alias.address or alias)
    (flatten (map (a: a.aliases or [ ]) muAccounts));

  addressesShell = concatStringsSep " " (map lib.escapeShellArg addresses);

  myAddresses =
    concatStringsSep " " (map (addr: "--my-address=" + addr) addresses);

  bins = {
    offlineimap = lib.getExe pkgs.offlineimap;
    mu = lib.getExe pkgs.mu;
    gawk = lib.getExe pkgs.gawk;
    grep = lib.getExe pkgs.gnugrep;
    pgrep = lib.getExe' pkgs.procps "pgrep";
  };
in {
  home.packages = with pkgs; [ offlineimap mu ];

  programs.offlineimap.enable = true;
  programs.mu.enable = true;

  home.activation.runMuInit = lib.mkForce
    (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if ${bins.pgrep} -f "mu server" >/dev/null 2>&1; then
        echo "runMuInit: mu server running; skipping init" >&2
        exit 0
      fi

      MUHOME="${config.programs.mu.home}"
      MU_ADDRS=$(( \
        ${bins.mu} info store 2>/dev/null | \
        ${bins.gawk} '/personal-address/{print $4}' | \
        paste -sd ' ' \
      ) || true)
      missing=0
      for addr in ${addressesShell}; do
        echo "$MU_ADDRS" | ${bins.grep} -Fqx "$addr" || missing=1
      done

      if [[ ! -d "$MUHOME" || "$missing" -eq 1 ]]; then
        run ${bins.mu} init --maildir=${maildir} --muhome "$MUHOME" \
          ${myAddresses} $VERBOSE_ARG
      fi
    '');

  accounts.email = {
    maildirBasePath = maildir;
    accounts = {
      fastmail = {
        address = "seryiza@fastmail.com";
        userName = "seryiza@fastmail.com";
        primary = true;
        flavor = "fastmail.com";
        realName = "Sergey Zaborovsky";
        aliases = [ "/@seryiza\\.xyz$/" ];
        passwordCommand = "${pkgs.pass}/bin/pass mail/seryiza@fastmail.com";
        mu = { enable = true; };
        offlineimap = {
          enable = true;
          extraConfig.account = { autorefresh = 0; };
        };
      };
    };
  };

  # Run OfflineIMAP every 5 minutes as a timer-only user service. Do not
  # install the service into default.target; user activation waits for default
  # target jobs to settle, so a stuck mail sync can block nixos-rebuild switch.
  systemd.user.services.offlineimap-sync = {
    Unit.Description = "OfflineIMAP sync";
    Service = {
      Type = "oneshot";
      ExecStart = bins.offlineimap;
      Environment =
        "PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.mu pkgs.offlineimap ]}";
      TimeoutStartSec = "5m";
      TimeoutStopSec = "1m";
      KillMode = "control-group";
      KillSignal = "SIGINT";
    };
  };

  systemd.user.timers.offlineimap-sync = {
    Unit.Description = "Run OfflineIMAP periodically";
    Timer = {
      OnBootSec = "1m";
      OnUnitActiveSec = "5m";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
