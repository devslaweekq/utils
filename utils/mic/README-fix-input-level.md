# Fixing the automatic microphone input level change problem

## 🎤 Problem description

In Ubuntu with PipeWire the microphone can automatically lower the input level when you:

- Cough
- Speak loudly
- Produce sharp/impulsive sounds

Result: the "Input Volume" slider moves left and people stop hearing you.

## ✅ Solution

The `fix-input-level.sh` script completely solves this problem.

### 🛠️ What the script does:

1. **Monitoring** – checks the level every 0.2 seconds
2. **Instant restore** – if it drops below 95% it immediately restores to 100%
3. **Multiple protection** – uses `wpctl`, `pactl` and `amixer` together
4. **WirePlumber configuration** – blocks automatic control at the system level
5. **Autostart** – a systemd service starts automatically at login

## 🚀 Usage

### Full setup (run once)

```bash
./utils/mic/fix-input-level.sh
```

### Control

```bash
# Check status
./utils/mic/fix-input-level.sh --status

# Restart monitoring
./utils/mic/fix-input-level.sh --restart

# Stop monitoring
./utils/mic/fix-input-level.sh --stop

# Test level restoration
./utils/mic/fix-input-level.sh --test
```

### Control via systemd

```bash
# Service status
systemctl --user status mic-level-keeper

# Restart
systemctl --user restart mic-level-keeper

# Stop
systemctl --user stop mic-level-keeper

# Start
systemctl --user start mic-level-keeper
```

## 📊 Monitoring

### Logs

```bash
# Watch logs in real time
tail -f /tmp/mic-level-keeper.log

# Last entries
tail -10 /tmp/mic-level-keeper.log
```

### Checking that it works

```bash
# Check current microphone level
wpctl get-volume 55

# Force level down for testing
wpctl set-volume 55 0.3

# Wait 1–2 seconds and check that it was restored
wpctl get-volume 55
```

## 📁 Created files

### Main components

- `~/.local/bin/mic-level-keeper` – main monitoring script
- `~/.config/systemd/user/mic-level-keeper.service` – autostart service
- `~/.config/wireplumber/main.lua.d/99-disable-input-auto-control.lua` – WirePlumber blocking config

### Logs and state

- `/tmp/mic-level-keeper.log` – monitoring log
- `~/.local/share/mic-level-keeper.pid` – PID of the process

## 🔧 Diagnostics

### Problem: monitoring does not work

```bash
# Check status
./Linux/fix-input-level.sh --status

# Restart
./Linux/fix-input-level.sh --restart

# Check logs
tail -5 /tmp/mic-level-keeper.log
```

### Problem: level still goes down

```bash
# Test level restoration
./Linux/fix-input-level.sh --test

# If the test fails, reinstall
./Linux/fix-input-level.sh
```

### Problem: service does not start

```bash
# Reload systemd
systemctl --user daemon-reload

# Enable service
systemctl --user enable mic-level-keeper.service

# Start
systemctl --user start mic-level-keeper.service
```

## ⚡ Result

After setup:

- ✅ The "Input Volume" slider stays in place
- ✅ When it drops it is automatically restored within 0.2–0.4 seconds
- ✅ People hear you consistently
- ✅ Works after system reboot
- ✅ Does not break other features (echo cancellation, noise reduction)

## 🆘 Support

If you have issues:

1. Run: `./Linux/fix-input-level.sh --status`
2. Check logs: `tail -10 /tmp/mic-level-keeper.log`
3. Test: `./Linux/fix-input-level.sh --test`

---

## 📝 Difference from `micro.sh`

- **`micro.sh`** – basic microphone tweaks, does NOT solve the automatic level problem
- **`fix-input-level.sh`** – full solution for the automatic input level problem

**To fix the slider issue, use ONLY `fix-input-level.sh`!**

---

**Version:** 2.0 **Date:** 2025
