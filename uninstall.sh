#!/bin/bash
# Remove netmode. The kernel settings go back to the system defaults on reboot.
set -uo pipefail
plugin_id=noxqd.netmode

systemctl --user disable --now netmode-watch.service netmode-proxy.service 2>/dev/null
rm -f "$HOME/.config/systemd/user/netmode-watch.service" "$HOME/.config/systemd/user/netmode-proxy.service"
ext_dir=$HOME/.local/share/netmode/extension
flags=$HOME/.config/chromium-flags.conf
[[ -f $flags ]] && sed -i -e "s|,$ext_dir||" -e "\|^--load-extension=$ext_dir\$|d" "$flags"
rm -rf "$HOME/.local/share/netmode"
systemctl --user daemon-reload
omarchy plugin disable "$plugin_id" 2>/dev/null
rm -rf "$HOME/.config/omarchy/plugins/$plugin_id" "$HOME/.local/bin/netmode"
[[ ${1:-} == --purge ]] && rm -rf "$HOME/.config/netmode" "$HOME/.local/state/netmode"

if [[ -e /usr/local/lib/netmode ]]; then
  cmd='systemctl disable --now netmode-boot.service; rm -f /etc/systemd/system/netmode-boot.service /etc/sudoers.d/netmode /usr/share/polkit-1/actions/dev.noxqd.netmode.policy; rm -rf /usr/local/lib/netmode /run/netmode; systemctl daemon-reload'
  if [[ $EUID -eq 0 ]]; then bash -c "$cmd"
  elif [[ -t 0 ]]; then sudo bash -c "$cmd"
  else pkexec bash -c "$cmd"; fi
fi
omarchy restart shell 2>/dev/null
echo "netmode removed"
