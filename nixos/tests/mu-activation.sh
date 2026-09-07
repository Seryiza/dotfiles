#!/usr/bin/env bash
set -euo pipefail

hook=$(nix eval --raw .#nixosConfigurations.yuri-alpha.config.home-manager.users.seryiza.home.activation.runMuInit.data)
# Force the running-server branch without touching the real mail server.
hook="if true; then${hook#*then}"
output=$(bash -euo pipefail -c "$hook"$'\nprintf "activation-continued\\n"')
if [[ "$output" != "activation-continued" ]]; then
  printf 'runMuInit exited before activation could continue\n' >&2
  exit 1
fi
