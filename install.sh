#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/tmp/install.log"
GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;34m'; NC='\033[0m'
log() {
	local level="$1"; shift
	local msg="$*"
	local ts
	ts=$(date +"%Y-%m-%d %H:%M:%S")
	local color
	case "$level" in
		INFO) color="$BLUE" ;;
		SUCCESS) color="$GREEN" ;;
		WARN) color="$YELLOW" ;;
		ERROR) color="$NC" ;;
		*) color="$NC" ;;
	esac

local log_message 
log_message="[$ts] ${color}[$level]${NC} $msg"

echo -e "$log_message" >> "$LOG_FILE"
if [ "$level" == "ERROR" ]; then
	echo -e "$log_message" >&2
else
	echo -e "$log_messagge"
fi
}
log_info() { log "INFO" "$1"; }
log_warn() { log "WARN" "$1"; }
log_success() { log "SUCCESS"  "$1" }
log_error() { log "ERROR" "$1" }


trap 'log_error "Installazione FASE INSTALLAZIONE fallita. " >&2' ERR

>"$LOG_FILE"
exec &> >(tee -a "$LOG_FILE")
export SUDO_USER=${SUDO_USER:-$USER}

log "Avvio installazione pachetti"
sudo pacman -Syyu --noconfirm
sudo yay -Syyu --noconfirm

# Rilevazione paru e instllazione 
if command -v paru &> /dev/null; then
	log_success "rlevato paru"
else
	sudo pacman -S --noconfirm base-devel git
	sudo -u "$SUDO_USER" bash -c 'cd /tmp && git clone https://aut.archlinux.org/paru.git && cd paru && makepkg -si --noconfirm'
fi
sudo paru -Syyu
# Installazione

# --- Messaggio di Inizio ---
echo "--- INIZIO SCRIPT DI INSTALLAZIONE COMPLETO ---" | tee -a "$LOG_FILE"
echo "L'output completo sarà registrato in $LOG_FILE"
echo "Verrà chiesta la password di sudo..."

# --- 1. INSTALLAZIONE DAI REPOSITORY (Pacman) ---
# Include i tuoi tool di base, hardening, monitoring E i tool di security
echo "--- Fase 1: Installazione pacchetti da Pacman (Ufficiali + Black Arch)... ---" | tee -a "$LOG_FILE"

sudo pacman -S --noconfirm --needed \
\
# --- BASE E UTILITY ---
git curl wget zsh starship fzf bat exa lsd zoxide \
ansible chezmoi just \
\
# --- HARDENING E MONITORING ---
chkrootkit rkhunter lynis clamav audit apparmor apparmor-utils nftables crowdsec \
firejail firejail-profiles flatpak osquery restic rclone \
glances bpytop htop bpftrace tracee netdata prometheus prometheus-node-exporter grafana \
lnav logwatch \
yara maltrail zram-generator \
\
# --- PRIVACY E RETE ---
torsocks nyx onionshare proxychains-ng wireguard-tools unbound dnscrypt-proxy \
keepassxc gopass age gnupg macchanger secure-delete pass \
\
# --- CONTAINERIZATION E FORENSICS ---
bubblewrap podman systemd-nspawn \
testdisk foremost hashdeep \
\
# --- TOOL DI HACKING ---
nmap wireshark-qt tcpdump mitmproxy 


# Controllo dell'errore per Pacman
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_error "!!! ERRORE: L'installazione di Pacman è fallita. Controlla $LOG_FILE. !!!" 
    exit 1
fi

echo "--- Fase 2: Installazione pacchetti da AUR (Yay)... ---" 

# --- 2. INSTALLAZIONE DALL'AUR (Yay) ---
# Sostituisci 'yay' con 'paru' se lo preferisci
yay -S --noconfirm --needed \
gophish \
evilginx2 \
pacu \
scoutsuite \
aws-cli-v2 \
payloadsallthethings-git \
linpeas-git ffuf amass burpsuite sqlmap nikto hashcat john hydra aircrack-ng reaver bettercap metasploit exploitdb gnu-netcat autopsy ghidra set maltego spiderfoot sherlock jadx apktool frida-tools binwalk flashrom qemu-user-static

# Controllo dell'errore per Yay
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_error "!!! ERRORE: L'installazione di Yay è fallita. Controlla $LOG_FILE. !!!" 
    exit 1
fi
log "--- INSTALLAZIONE COMPLETATA ---"
log "--- Tutti i pacchetti sono stati installati. Controlla $LOG_FILE per i dettagli. ---"
