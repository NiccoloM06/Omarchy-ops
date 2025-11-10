#!/usr/bin/env bash
set -euo pipefail

# =======================================================================================
#  GUARDIAN DAEMON v1.5 | OMARCHY-OPS (MONITORING SERVICE)
#  Monitors critical services and security state, writing JSON status for Waybar/TUI.
# =======================================================================================

# --- Variables ---
# NOTE: This script assumes its dependencies are resolved and the necessary
# logging functions are available through its calling environment (systemd).
STATE_FILE="/run/chimera/state.json"
GUARDIAN_CTL_STATUS_FILE="/tmp/guardian_status" # File written by gcli (contains profile name)
CHECK_INTERVAL=5 # Seconds between checks

# Fallback logger definition (if run outside of the main framework context)
log() { echo -e "[$1] [DAEMON] $*" >> /var/log/chimera_daemon.log; }
LOGFILE="/var/log/chimera_daemon.log"
# Define colors for JSON output consistency
GREEN='\033[1;32m'; RED='\033[1;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

# --- Ensure /run directory exists ---
mkdir -p "$(dirname "$STATE_FILE")"
log INFO "Guardian Daemon starting up..."

# --- Main Monitoring Loop ---
while true; do
    # --- Initialize Status Variables ---
    current_profile="STANDARD"
    overall_status="SECURE" # Assume secure by default
    lkrg_status="INACTIVE"
    opensnitch_status="INACTIVE"
    falco_status="INACTIVE"

    # --- Read Current Security Profile (Set by gcli) ---
    if [ -f "$GUARDIAN_CTL_STATUS_FILE" ]; then
        # Read only the first line, stripping ANSI color codes
        current_profile=$(head -n 1 "$GUARDIAN_CTL_STATUS_FILE" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g")
    fi

    # --- Check Critical Service Status ---
    # Check services and set overall_status to WARN if any are down
    if systemctl is-active --quiet lkrg &>/dev/null; then lkrg_status="ACTIVE"; else overall_status="WARN"; fi
    if systemctl is-active --quiet opensnitchd &>/dev/null; then opensnitch_status="ACTIVE"; else overall_status="WARN"; fi
    if systemctl is-active --quiet falco &>/dev/null; then falco_status="ACTIVE"; else overall_status="WARN"; fi
    
    # --- Determine Final Status ---
    if [ "$current_profile" == "PARANOID" ]; then
        # If in Paranoid mode, the status is determined by the active profile
        overall_status="PARANOID"
    fi

    # --- Write JSON State File ---
    # Use jq to create reliable JSON output
    jq -n \
      --arg status "$overall_status" \
      --arg profile "$current_profile" \
      --arg lkrg "$lkrg_status" \
      --arg opensnitch "$opensnitch_status" \
      --arg falco "$falco_status" \
      '{
          "timestamp": "'$(date -u --iso-8601=seconds)'",
          "overall_status": $status,
          "security_profile": $profile,
          "services": {
            "lkrg": $lkrg,
            "opensnitch": $opensnitch,
            "falco": $falco
          }
       }' > "$STATE_FILE"

    # Wait for the next check interval
    sleep "$CHECK_INTERVAL"
     echo "$(date): Running guardian checks..." >> "$LOGFILE"
    # Check Falco status
    if ! systemctl is-active --quiet falco; then
        echo "$(date): Falco not running! Restarting..." >> "$LOGFILE"
        systemctl restart falco
    fi
    # Check osquery
    if ! systemctl is-active --quiet osqueryd; then
        echo "$(date): Osquery down! Restarting..." >> "$LOGFILE"
        systemctl restart osqueryd
    fi
    # Check CrowdSec
    if ! systemctl is-active --quiet crowdsec; then
        echo "$(date): CrowdSec down! Restarting..." >> "$LOGFILE"
        systemctl restart crowdsec
    fi
    sleep 300
done

