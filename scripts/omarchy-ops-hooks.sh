#!/usr/bin/env bash
set -euo pipefail
[ "$EIUD" -ne 0 ] || { echo "Run as root"; exit 1; }
# =======================================================================================
#  OMARCHY-OPS BASH HOOKS | CHIMERA UPGRADE KIT (v52)
#  Provides functional aliases and wrappers for security utilities in the Bash shell.
#  This file is sourced by the user's ~/.bashrc.
# =======================================================================================

# --- Colors for Output Consistency ---
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[1;34m'
NC='\033[0m'

# --- Security Posture Control (gcli wrappers) ---

# Turn on Paranoid Mode (Tor Kill Switch)
gcli_on() {
    echo -e "🚀 Activating Security Level 3 ${RED}(Paranoid)${NC}..."
    sudo gcli on
}

# Turn off Paranoid Mode (Standard/DNSCrypt)
gcli_off() {
    echo -e "🚀 Deactivating Paranoid Mode. Returning to ${GREEN}(Standard/DNSCrypt)${NC}..."
    sudo gcli off
}

# Show Security Status (Calls gcli show)
gcli_status() {
    echo -e "📊 ${BLUE}Querying real-time security posture...${NC}"
    sudo gcli show
}

# --- AIDE Integrity Management ---

aide_check() {
    echo -e "🔎 ${BLUE}Starting AIDE filesystem integrity check...${NC}"
    sudo aide --check
}

aide_update() {
    echo -e "🔄 ${YELLOW}Updating AIDE integrity baseline...${NC}"
    # Execute the two-step update process required after system changes
    sudo aide --update && sudo mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
    echo -e "${GREEN}[OK]${NC} AIDE baseline updated successfully."
}

# --- Quick Aliases for Auditing & Scanning ---
# Note: Since we don't have zsh_functions, we use aliases or simple wrappers here.
alias gstatus="gcli_status"
alias gparanoid="gcli_on"
alias gstandard="gcli_off"
alias health="sudo chimera-healthcheck"
alias cleanlogs="sudo journalctl --vacuum-time=3d"
alias rootkit="sudo chkrootkit"
alias scan="sudo nmap -sS -v"

# --- POST-UPDATE SECURITY HOOKS ---
echo "[+] Running security checks..."
arch-audit -u
aa-enforce /etc/apparmor.d/*
systemctl reload falco osqueryd
# Ricarica regole/pack post-update
systemctl reload falco || systemctl restart falco
systemctl reload osqueryd || systemctl restart osqueryd


