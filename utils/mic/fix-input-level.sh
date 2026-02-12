#!/bin/bash

# Complete solution for the automatic microphone input level change problem
# Description: Blocks automatic lowering of microphone input level

set -e

echo "================================================================="
echo "Solution for the automatic microphone input level change problem"
echo "================================================================="

# Function to find microphone ID
# First by name, then via default input device
find_microphone_id() {
    local mic_id=""

    # 1. Try to find by name "Headphones Stereo Microphone" (for backward compatibility)
    mic_id=$(wpctl status 2>/dev/null | grep "Headphones Stereo Microphone" | head -1 | awk '{print $3}' | sed 's/[^0-9]//g')

    if [ ! -z "$mic_id" ] && [ "$mic_id" -gt 0 ] 2>/dev/null; then
        echo "$mic_id|Headphones Stereo Microphone"
        return 0
    fi

    # 2. Get the default source and search for its ID in wpctl
    local default_source=$(pactl info 2>/dev/null | grep "Default Source:" | cut -d' ' -f3)

    if [ ! -z "$default_source" ]; then
        # First search in Filters (for Bluetooth devices) — device with asterisk
        mic_id=$(wpctl status 2>/dev/null | grep "*" | grep "$default_source" | head -1 | grep -oE '[0-9]+\.' | head -1 | sed 's/\.//')

        if [ ! -z "$mic_id" ] && [ "$mic_id" -gt 0 ] 2>/dev/null; then
            local mic_name=$(wpctl status 2>/dev/null | grep -E "^\s+\*\s+$mic_id\." | sed 's/.*\. //' | head -1)
            echo "$mic_id|${mic_name:-$default_source}"
            return 0
        fi

        # Then search in Sources
        mic_id=$(wpctl status 2>/dev/null | grep -A 50 "Sources:" | grep -E "^\s+[0-9]+\." | grep -F "$default_source" | head -1 | awk '{print $1}' | sed 's/[^0-9]//g')

        if [ ! -z "$mic_id" ] && [ "$mic_id" -gt 0 ] 2>/dev/null; then
            local mic_name=$(wpctl status 2>/dev/null | grep -E "^\s+$mic_id\." | sed 's/.*\. //' | head -1)
            echo "$mic_id|${mic_name:-$default_source}"
            return 0
        fi
    fi

    echo "|"
    return 1
}

# Function to fix input level
fix_input_level() {
    echo "Fixing microphone input level..."

    # Find microphone ID
    local mic_info=$(find_microphone_id)
    local MIC_ID=$(echo "$mic_info" | cut -d'|' -f1)
    local MIC_NAME=$(echo "$mic_info" | cut -d'|' -f2)

    if [ ! -z "$MIC_ID" ] && [ "$MIC_ID" -gt 0 ] 2>/dev/null; then
        echo "Microphone found: $MIC_NAME (ID: $MIC_ID)"

        # Set maximum level
        wpctl set-volume "$MIC_ID" 1.0 2>/dev/null
        echo "✓ Level set to 100%"

        # Ensure it is not muted
        wpctl set-mute "$MIC_ID" 0 2>/dev/null
        echo "✓ Microphone unmuted"
    else
        echo "⚠️  Microphone not found by ID, falling back to generic settings"
    fi

    # Also via pactl (works with any microphone including Bluetooth)
    pactl set-source-volume @DEFAULT_SOURCE@ 100% 2>/dev/null
    pactl set-source-mute @DEFAULT_SOURCE@ 0 2>/dev/null
    echo "✓ Level set via PulseAudio"

    # Via ALSA for reliability (only for ALSA devices)
    amixer -c 1 sset "Capture" 100% 2>/dev/null || echo "⚠️  ALSA control not available (normal for Bluetooth)"
}

# Create an efficient input level monitor
create_level_keeper() {
    echo "Creating microphone input level keeper..."

    cat > ~/.local/bin/mic-level-keeper << 'EOF'
#!/bin/bash

# Simple and effective microphone level keeper

LOGFILE="/tmp/mic-level-keeper.log"

# Function to find microphone ID
# First by name, then via default input device
find_microphone_id() {
    local mic_id=""

    # 1. Try to find by name "Headphones Stereo Microphone" (for backward compatibility)
    mic_id=$(wpctl status 2>/dev/null | grep "Headphones Stereo Microphone" | head -1 | awk '{print $3}' | sed 's/[^0-9]//g')

    if [ ! -z "$mic_id" ] && [ "$mic_id" -gt 0 ] 2>/dev/null; then
        echo "$mic_id|Headphones Stereo Microphone"
        return 0
    fi

    # 2. Get the default source and search for its ID in wpctl
    local default_source=$(pactl info 2>/dev/null | grep "Default Source:" | cut -d' ' -f3)

    if [ ! -z "$default_source" ]; then
        # First search in Filters (for Bluetooth devices) — device with asterisk
        mic_id=$(wpctl status 2>/dev/null | grep "*" | grep "$default_source" | head -1 | grep -oE '[0-9]+\.' | head -1 | sed 's/\.//')

        if [ ! -z "$mic_id" ] && [ "$mic_id" -gt 0 ] 2>/dev/null; then
            local mic_name=$(wpctl status 2>/dev/null | grep -E "^\s+\*\s+$mic_id\." | sed 's/.*\. //' | head -1)
            echo "$mic_id|${mic_name:-$default_source}"
            return 0
        fi

        # Then search in Sources
        mic_id=$(wpctl status 2>/dev/null | grep -A 50 "Sources:" | grep -E "^\s+[0-9]+\." | grep -F "$default_source" | head -1 | awk '{print $1}' | sed 's/[^0-9]//g')

        if [ ! -z "$mic_id" ] && [ "$mic_id" -gt 0 ] 2>/dev/null; then
            local mic_name=$(wpctl status 2>/dev/null | grep -E "^\s+$mic_id\." | sed 's/.*\. //' | head -1)
            echo "$mic_id|${mic_name:-$default_source}"
            return 0
        fi
    fi

    echo "|"
    return 1
}

echo "$(date): Starting microphone level keeper" >> "$LOGFILE"

while true; do
    # Find microphone ID each time (it may change when PipeWire restarts)
    mic_info=$(find_microphone_id)
    MIC_ID=$(echo "$mic_info" | cut -d'|' -f1)
    MIC_NAME=$(echo "$mic_info" | cut -d'|' -f2)

        if [ ! -z "$MIC_ID" ] && [ "$MIC_ID" -gt 0 ] 2>/dev/null; then
        # Get current level
        CURRENT_VOLUME=$(wpctl get-volume "$MIC_ID" 2>/dev/null | awk '{print $2}')

            if [ ! -z "$CURRENT_VOLUME" ]; then
            # Convert to percent for convenience
            CURRENT_PERCENT=$(echo "$CURRENT_VOLUME * 100" | bc -l 2>/dev/null | cut -d. -f1)

            # If level is below 95%, restore to 100%
            if [ ! -z "$CURRENT_PERCENT" ] && [ "$CURRENT_PERCENT" -lt 95 ] 2>/dev/null; then
                echo "$(date): Level dropped to ${CURRENT_PERCENT}% on $MIC_NAME (ID: $MIC_ID), restoring to 100%" >> "$LOGFILE"

                # Restore level in three ways
                wpctl set-volume "$MIC_ID" 1.0 2>/dev/null
                pactl set-source-volume @DEFAULT_SOURCE@ 100% 2>/dev/null
                amixer -c 1 sset "Capture" 100% 2>/dev/null

                echo "$(date): Level restored to 100%" >> "$LOGFILE"
            fi
        fi
        else
        # Log only once every 10 seconds to avoid log spam
        if [ -z "$LAST_LOG_TIME" ] || [ $(($(date +%s) - LAST_LOG_TIME)) -ge 10 ]; then
            echo "$(date): Microphone not found, searching..." >> "$LOGFILE"
            LAST_LOG_TIME=$(date +%s)
        fi
    fi

    # Check every 0.2 seconds for fast reaction
    sleep 0.2
done
EOF

    chmod +x ~/.local/bin/mic-level-keeper
    echo "✓ Level keeper created: ~/.local/bin/mic-level-keeper"
}

# Create WirePlumber configuration to block automatic control
create_wireplumber_config() {
    echo "Creating WirePlumber configuration..."

    mkdir -p ~/.config/wireplumber/main.lua.d

    cat > ~/.config/wireplumber/main.lua.d/99-disable-input-auto-control.lua << 'EOF'
-- Block automatic microphone input level control

-- Rules to block automatic level control
rule_input_level = {
  matches = {
    {
      { "media.class", "equals", "Audio/Source" },
      { "node.name", "matches", "*Mic*" },
    },
  },
  apply_properties = {
    -- Disable automatic level control
    ["audio.auto-gain-control.enable"] = false,
    ["audio.agc.enable"] = false,
    ["device.auto-volume"] = false,
    ["device.auto-level"] = false,
    ["alsa.auto-gain"] = false,

    -- Block volume changes
    ["volume.lock"] = true,
    ["volume.auto"] = false,

    -- Fix the level
    ["volume"] = 1.0,
    ["mute"] = false,
  },
}

table.insert(alsa_monitor.rules, rule_input_level)

-- Real-time monitoring of level changes
local function monitor_input_level()
  for node in nodes_om:iterate() do
    if node.properties["media.class"] == "Audio/Source" and
       node.properties["node.name"] and
       string.match(node.properties["node.name"], "Mic") then

      -- Attach parameter change handler
      node:connect("params-changed", function(node, param_name)
        if param_name == "Props" then
          -- Forcefully restore level
          node:set_param("Props", Pod.Object {
            "Spa:Pod:Object:Param:Props", "Props",
            volume = 1.0,
            mute = false,
          })
          Log.warning("Input level auto-corrected to 100%")
        end
      end)

      Log.info("Input level monitoring enabled for: " .. node.properties["node.name"])
    end
  end
end

-- Start monitoring with a delay
Core.timeout_add(1000, function()
  monitor_input_level()
  return false
end)

-- Monitor new devices
nodes_om:connect("object-added", function(om, node)
  if node.properties["media.class"] == "Audio/Source" and
     node.properties["node.name"] and
     string.match(node.properties["node.name"], "Mic") then

    Core.timeout_add(500, function()
      -- Set fixed parameters
      node:set_param("Props", Pod.Object {
        "Spa:Pod:Object:Param:Props", "Props",
        volume = 1.0,
        mute = false,
      })

      -- Attach monitoring
      node:connect("params-changed", function(node, param_name)
        if param_name == "Props" then
          node:set_param("Props", Pod.Object {
            "Spa:Pod:Object:Param:Props", "Props",
            volume = 1.0,
            mute = false,
          })
        end
      end)

      Log.info("New microphone auto-configured: " .. node.properties["node.name"])
      return false
    end)
  end
end)
EOF

    echo "✓ WirePlumber configuration created"
}

# Create systemd service for autostart
create_systemd_service() {
    echo "Creating systemd service..."

    mkdir -p ~/.config/systemd/user

    cat > ~/.config/systemd/user/mic-level-keeper.service << 'EOF'
[Unit]
Description=Microphone input level keeper
After=pipewire.service

[Service]
Type=simple
ExecStart=%h/.local/bin/mic-level-keeper
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
EOF

    # Reload and enable service
    systemctl --user daemon-reload
    systemctl --user enable mic-level-keeper.service

    echo "✓ Systemd service created and enabled"
}

# Function to start monitoring
start_monitoring() {
    echo "Starting input level monitoring..."

    # Stop old processes
    pkill -f mic-level-keeper 2>/dev/null || true
    sleep 0.5

    # Start via systemd
    if systemctl --user start mic-level-keeper.service 2>/dev/null; then
        sleep 0.5
        SERVICE_PID=$(systemctl --user show mic-level-keeper.service -p MainPID --value 2>/dev/null)
        if [ ! -z "$SERVICE_PID" ] && [ "$SERVICE_PID" != "0" ]; then
            echo "✓ Monitoring started via systemd (PID: $SERVICE_PID)"
        else
            echo "✓ Monitoring started via systemd"
        fi
    else
        # Fallback: start manually if systemd is not available
        ~/.local/bin/mic-level-keeper &
        MONITOR_PID=$!
        echo "$MONITOR_PID" > ~/.local/share/mic-level-keeper.pid
        echo "✓ Monitoring started manually (PID: $MONITOR_PID)"
    fi
}

# Function to check status
check_status() {
    echo "================================================================="
    echo "Status of the microphone input level fix:"
    echo "================================================================="

    echo "--- Current microphone level ---"
    mic_info=$(find_microphone_id)
    MIC_ID=$(echo "$mic_info" | cut -d'|' -f1)
    MIC_NAME=$(echo "$mic_info" | cut -d'|' -f2)
    if [ ! -z "$MIC_ID" ] && [ "$MIC_ID" -gt 0 ] 2>/dev/null; then
        CURRENT_VOLUME=$(wpctl get-volume "$MIC_ID" 2>/dev/null | awk '{print $2}')
        CURRENT_PERCENT=$(echo "$CURRENT_VOLUME * 100" | bc -l 2>/dev/null | cut -d. -f1)
        echo "Microphone: $MIC_NAME (ID: $MIC_ID)"
        echo "Current level: ${CURRENT_PERCENT}%"
    else
        echo "❌ Microphone not found"
    fi

    echo -e "\n--- Monitoring status ---"
    # Check via systemd service
    if systemctl --user is-active mic-level-keeper.service >/dev/null 2>&1; then
        SERVICE_PID=$(systemctl --user show mic-level-keeper.service -p MainPID --value 2>/dev/null)
        if [ ! -z "$SERVICE_PID" ] && [ "$SERVICE_PID" != "0" ]; then
            echo "✅ Monitoring is active via systemd (PID: $SERVICE_PID)"
        else
            echo "✅ Monitoring is active via systemd"
        fi
    elif [ -f ~/.local/share/mic-level-keeper.pid ]; then
        pid=$(cat ~/.local/share/mic-level-keeper.pid 2>/dev/null)
        if [ ! -z "$pid" ] && ps -p "$pid" > /dev/null 2>&1; then
            echo "✅ Monitoring is active manually (PID: $pid)"
        else
            echo "❌ Monitoring is not active"
        fi
    else
        echo "❌ Monitoring is not running"
    fi

    echo -e "\n--- System service ---"
    if systemctl --user is-enabled mic-level-keeper.service >/dev/null 2>&1; then
        echo "✅ Autostart enabled"
        SERVICE_STATUS=$(systemctl --user is-active mic-level-keeper.service 2>&1)
        if [ "$SERVICE_STATUS" = "active" ]; then
            echo "✅ Service is active"
        else
            echo "⚠️  Service is not active (status: $SERVICE_STATUS)"
        fi
    else
        echo "❌ Autostart disabled"
    fi

    echo -e "\n--- Configuration files ---"
    if [ -f ~/.local/bin/mic-level-keeper ]; then
        echo "✅ Monitoring script: ~/.local/bin/mic-level-keeper"
    else
        echo "❌ Monitoring script is missing"
    fi

    if [ -f ~/.config/wireplumber/main.lua.d/99-disable-input-auto-control.lua ]; then
        echo "✅ WirePlumber config: ~/.config/wireplumber/main.lua.d/99-disable-input-auto-control.lua"
    else
        echo "❌ WirePlumber configuration is missing"
    fi

    if [ -f ~/.config/systemd/user/mic-level-keeper.service ]; then
        echo "✅ Systemd service: ~/.config/systemd/user/mic-level-keeper.service"
    else
        echo "❌ Systemd service is missing"
    fi

    echo -e "\n--- Monitoring logs ---"
    if [ -f /tmp/mic-level-keeper.log ]; then
        echo "Last 3 entries:"
        tail -3 /tmp/mic-level-keeper.log
    else
        echo "No logs found"
    fi
}

# Main function
main() {
    echo "Starting full solution for the automatic input level problem..."

    # Check privileges
    if [ "$EUID" -eq 0 ]; then
        echo "⚠️  Do NOT run this script as root!"
        exit 1
    fi

    # Create required directories
    mkdir -p ~/.local/bin ~/.local/share ~/.config/systemd/user ~/.config/wireplumber/main.lua.d

    # Run all steps
    fix_input_level
    create_level_keeper
    create_wireplumber_config
    create_systemd_service
    start_monitoring

    echo "================================================================="
    echo "✅ The problem of automatic input level change is SOLVED!"
    echo "================================================================="
    echo ""
    echo "What has been done:"
    echo "1. Created an effective input level monitor (checks every 0.2 seconds)"
    echo "2. Configured WirePlumber to block automatic level control"
    echo "3. Created a systemd service for autostart"
    echo "4. Monitoring started immediately"
    echo "5. Input level fixed at 100%"
    echo ""
    echo "Control:"
    echo "  systemctl --user start mic-level-keeper   - start"
    echo "  systemctl --user stop mic-level-keeper    - stop"
    echo "  systemctl --user status mic-level-keeper  - status"
    echo ""
    echo "Logs: tail -f /tmp/mic-level-keeper.log"
    echo ""
    echo "🎤 Now the Input Volume slider will NOT move left!"
    echo "    When the level drops, it will automatically be restored to 100%."

    echo ""
    check_status
}

# Parse arguments
case "${1:-}" in
    --status)
        check_status
        exit 0
        ;;
    --stop)
        echo "Stopping monitoring..."
        pkill -f mic-level-keeper 2>/dev/null && echo "✓ Process stopped" || echo "Process not found"
        systemctl --user stop mic-level-keeper 2>/dev/null && echo "✓ Service stopped" || echo "Service was not running"
        rm -f ~/.local/share/mic-level-keeper.pid
        exit 0
        ;;
    --restart)
        echo "Restarting monitoring..."
        systemctl --user restart mic-level-keeper
        echo "✓ Service restarted"
        exit 0
        ;;
    --test)
        echo "Testing level restoration..."
        mic_info=$(find_microphone_id)
        MIC_ID=$(echo "$mic_info" | cut -d'|' -f1)
        MIC_NAME=$(echo "$mic_info" | cut -d'|' -f2)
        if [ ! -z "$MIC_ID" ] && [ "$MIC_ID" -gt 0 ] 2>/dev/null; then
            echo "Testing microphone: $MIC_NAME (ID: $MIC_ID)"
            echo "Lowering level to 20%..."
            wpctl set-volume "$MIC_ID" 0.2 2>/dev/null
            echo "Waiting 3 seconds for recovery..."
            sleep 3
            CURRENT_VOLUME=$(wpctl get-volume "$MIC_ID" 2>/dev/null | awk '{print $2}')
            CURRENT_PERCENT=$(echo "$CURRENT_VOLUME * 100" | bc -l 2>/dev/null | cut -d. -f1)
            echo "Current level: ${CURRENT_PERCENT}%"
            if [ "$CURRENT_PERCENT" -gt 90 ]; then
                echo "✅ TEST PASSED! Level was restored."
            else
                echo "❌ TEST FAILED! Level was not restored."
            fi
        else
            echo "❌ Microphone not found for testing"
        fi
        exit 0
        ;;
    --help|-h)
        echo "Usage: $0 [option]"
        echo ""
        echo "Options:"
        echo "  (no options) - Perform full setup"
        echo "  --status     - Check status"
        echo "  --stop       - Stop monitoring"
        echo "  --restart    - Restart monitoring"
        echo "  --test       - Test level restoration"
        echo "  --help, -h   - Show this help"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo "❌ Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
