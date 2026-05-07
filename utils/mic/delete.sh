systemctl --user stop mic-level-keeper.service 2>/dev/null || true
systemctl --user disable mic-level-keeper.service 2>/dev/null || true
pkill -f mic-level-keeper 2>/dev/null || true
rm -f ~/.local/share/mic-level-keeper.pid

systemctl --user daemon-reload

rm -f ~/.local/bin/mic-level-keeper
rm -f ~/.config/systemd/user/mic-level-keeper.service
rm -f ~/.config/wireplumber/main.lua.d/99-disable-input-auto-control.lua
rm -f /tmp/mic-level-keeper.log

systemctl --user restart wireplumber

systemctl --user is-active mic-level-keeper.service 2>/dev/null || true
pgrep -af mic-level-keeper 2>/dev/null || true
ls -la ~/.config/wireplumber/main.lua.d 2>/dev/null || true
