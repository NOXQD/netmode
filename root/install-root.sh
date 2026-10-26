#!/bin/bash
# Root half of the installation. Run by install.sh through sudo or pkexec:
#   install-root.sh <user> <repo-dir>
# Puts the helper where only root can change it, lets <user> run its four
# `apply <mode>` commands without a password, and re-applies the default mode
# at boot (kernel settings do not survive a reboot).
set -euo pipefail
PATH=/usr/sbin:/usr/bin:/sbin:/bin

user=${1:?user}
src=${2:?repo}
dest=/usr/local/lib/netmode

[[ $EUID -eq 0 ]] || { echo "needs root" >&2; exit 77; }
id -u "$user" >/dev/null

install -d -m 755 -o root -g root "$dest"
install -m 755 -o root -g root "$src/root/netmode-root" "$dest/netmode-root"
install -m 644 -o root -g root "$src/root/dev.noxqd.netmode.policy" /usr/share/polkit-1/actions/dev.noxqd.netmode.policy

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
{
  echo "# netmode: $user may switch network profiles without a password."
  echo "# The helper accepts only these mode names and nothing else."
  for mode in $("$dest/netmode-root" list | python3 -I -c 'import json,sys; print(*[m["id"] for m in json.load(sys.stdin)])'); do
    echo "$user ALL=(root) NOPASSWD: $dest/netmode-root apply $mode"
  done
} >"$tmp"
visudo -cf "$tmp" >/dev/null
install -m 440 -o root -g root "$tmp" /etc/sudoers.d/netmode

cat >/etc/systemd/system/netmode-boot.service <<UNIT
[Unit]
Description=netmode: apply the default network profile
After=NetworkManager.service

[Service]
Type=oneshot
ExecStart=$dest/netmode-root apply balanced

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable netmode-boot.service >/dev/null 2>&1
"$dest/netmode-root" apply balanced
echo "netmode: root part installed"
