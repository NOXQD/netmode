#!/bin/bash
# netmode installer for Omarchy. Re-run it to update.
#   ./install.sh                full install (asks for the root password once)
#   ./install.sh --no-root      only the user part (no profile switching)
#   ./install.sh --no-restart   do not restart the shell
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin_id=noxqd.netmode
plugin_dir=$HOME/.config/omarchy/plugins/$plugin_id
exe=$HOME/.local/bin/netmode
do_root=1
do_restart=1
for arg in "$@"; do
  case $arg in
    --no-root) do_root=0 ;;
    --no-restart) do_restart=0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if (( do_root )); then
  if [[ $EUID -eq 0 ]]; then
    bash "$here/root/install-root.sh" "${SUDO_USER:-root}" "$here"
  elif [[ -t 0 ]] && command -v sudo >/dev/null; then
    sudo bash "$here/root/install-root.sh" "$USER" "$here"
  else
    pkexec bash "$here/root/install-root.sh" "$USER" "$here"
  fi
fi

install -d "$HOME/.local/bin"
install -m 755 "$here/bin/netmode" "$exe"

install -d "$plugin_dir"
for f in manifest.json BarWidget.qml Popup.qml PopupContent.qml Fmt.js; do
  install -m 644 "$here/plugin/$f" "$plugin_dir/$f"
done
sed "s|@EXE@|$exe|" "$here/plugin/Env.js.in" >"$plugin_dir/Env.js"
chmod 644 "$plugin_dir/Env.js"

ext_dir=$HOME/.local/share/netmode/extension
install -d "$ext_dir"
install -m 644 "$here"/extension/manifest.json "$here"/extension/background.js "$ext_dir/"
port=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("proxy_port", 18765))' "$HOME/.config/netmode/config.json" 2>/dev/null || echo 18765)
printf 'const PORT = %s\nconst TOKEN = "%s"\n' "$port" "$("$exe" token)" >"$ext_dir/token.js"
chmod 600 "$ext_dir/token.js"

# Chromium reads its flags once at start; the extension is picked up on the next launch.
flags=$HOME/.config/chromium-flags.conf
if [[ -f $flags ]] && ! grep -qF "$ext_dir" "$flags"; then
  [[ -e $flags.netmode-bak ]] || cp "$flags" "$flags.netmode-bak"
  if grep -q '^--load-extension=' "$flags"; then
    sed -i "s|^--load-extension=\(.*\)\$|--load-extension=\1,$ext_dir|" "$flags"
  else
    echo "--load-extension=$ext_dir" >>"$flags"
  fi
fi

install -d "$HOME/.config/systemd/user"
cat >"$HOME/.config/systemd/user/netmode-proxy.service" <<UNIT
[Unit]
Description=netmode: local accelerator for the AnimeLib video servers

[Service]
ExecStart=$exe proxy
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
UNIT
cat >"$HOME/.config/systemd/user/netmode-watch.service" <<UNIT
[Unit]
Description=netmode: video profile while AnimeLib is open
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart=$exe watch
Restart=on-failure
RestartSec=3
Nice=10

[Install]
WantedBy=graphical-session.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now netmode-watch.service netmode-proxy.service >/dev/null 2>&1 || true
systemctl --user restart netmode-watch.service netmode-proxy.service || true

if ! grep -q "\"$plugin_id\"" "$HOME/.config/omarchy/shell.json" 2>/dev/null; then
  omarchy plugin enable "$plugin_id" || echo "enable it with: omarchy plugin enable $plugin_id"
fi
if (( do_restart )); then
  omarchy restart shell || true
fi
echo "netmode installed. Restart Chromium once to load the video accelerator."
echo "Try: netmode, netmode set video, netmode bench"
