#!/usr/bin/env zsh
set -euo pipefail

# =======================================================================================
#  OMARCHY-OPS UPGRADE KIT (v54) - FASE 1: INSTALLAZIONE BASE
#  Installa il kernel hardened, l'arsenale e i servizi (SENZA moduli DKMS).
# =======================================================================================
# --- INCOLLA QUESTO NUOVO BLOCCO ALL'INIZIO ---
LOG_FILE="/tmp/omarchy_ops_upgrade1.log"
GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; BLUE='\033[1;34m'; NC='\033[0m'

# --- FUNZIONI DI LOGGING CORRETTE (SENZA 'tee' ERRATO) ---
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
    ERROR) color="$RED" ;;
    *) color="$NC" ;;
  esac

  local log_message
  log_message="[$ts] ${color}[$level]${NC} $msg"

  echo -e "$log_message" >> "$LOG_FILE"
  if [[ "$level" == "ERROR" ]]; then
      echo -e "$log_message" >&2
  else
      echo -e "$log_message"
  fi
}
log_info() { log "INFO" "$1"; }
log_warn() { log "WARN" "$1"; }
log_success() { log "SUCCESS" "$1"; }
log_error() { log "ERROR" "$1"; }
# -----------------------------------------------------------------

trap 'log_error "Installazione FASE 1 fallita. Controlla il log." >&2' ERR

# Pulisce il log precedente
> "$LOG_FILE"
# Redirige TUTTO l'output (stdout e stderr) dei comandi nel file di log
exec &> >(tee -a "$LOG_FILE")
# --- FINE NUOVO BLOCCO ---
log "Avvio di Omarchy-Ops Upgrade Kit (FASE 1)..."
log "Il log completo sarà disponibile in $LOG_FILE"

if [ "$(id -u)" -ne 0 ]; then
    log_error "Questo script deve essere eseguito con 'sudo', non come root."
    exit 1
fi
export SUDO_USER=${SUDO_USER:-$USER}

read -r -p "Continuare con l'installazione della FASE 1 (Componenti Base)? (y/N) " response
if [[ ! "$response" =~ ^([yY])$ ]]; then
    log "Upgrade annullato."
    exit 0
fi

AUR_HELPER_CMD="paru -S --noconfirm"

# Esporta la variabile per lo script di FASE 2
echo "export AUR_HELPER_CMD=\"$AUR_HELPER_CMD\"" | sudo tee /etc/profile.d/chimera-ops.sh > /dev/null

# --- FASE 1: HARDENING KERNEL & SISTEMA (IDEMPOTENTE) ---
log "Installazione di linux-hardened, AIDE, auditd..."
sudo pacman -Syyu --noconfirm

# =======================================================================================
#  OMARCHY-OPS | OPS-ORIENTED TOOLSET INSTALLER (Part 1)
# =======================================================================================


# Install Proton tools and extra utilities (AUR)
if command -v yay >/dev/null 2>&1; then
  yay -Syyu --noconfirm protonvpn-cli-ng protonmail-bridge mullvad-vpn bettercap
else
  echo "[!] AUR helper not found (yay). Install manually: protonvpn-cli-ng protonmail-bridge"
fi

# Enable core security services
sudo systemctl enable --now apparmor nftables auditd crowdsec unbound dnscrypt-proxy
sudo systemctl enable --now falco osqueryd netdata clamav-freshclam

# Configure nftables firewall baseline
sudo tee /etc/nftables.conf >/dev/null <<'EOF'
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority 0;
    ct state established,related accept
    iif lo accept
    tcp dport {22, 80, 443} accept
    icmp type echo-request accept
    drop
  }
  chain forward { type filter hook forward priority 0; drop }
  chain output {
    type filter hook output priority 0;
    accept
  }
}
EOF

sudo systemctl restart nftables

# Kernel and network hardening
sudo tee /etc/sysctl.d/99-omarchy-hardening.conf >/dev/null <<'EOF'
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.unprivileged_bpf_disabled=1
kernel.unprivileged_userns_clone=0
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv6.conf.all.accept_redirects=0
EOF
sudo sysctl --system

echo "[+] OPS-oriented stack successfully installed and configured."

# falco e lkrg rimossi da qui
#sudo pacman -S --needed --noconfirm linux-hardened linux-hardened-headers aide auditd chkrootkit rkhunter lynis clamav + tools
sudo pacman -S --needed --noconfirm linux-hardened linux-hardened-headers 

sudo -u "$SUDO_USER" paru -S --needed --noconfirm aide 
sudo systemctl enable --now auditd
sudo systemctl enable --now apparmor
sudo systemctl enable --now nftable
sudo systemctl enable --now crowdsec
sudo systemctl enable --now unbound
sudo systemctl enable --now osqueryd 
sudo systemctl enable --now netdata
log_success "Kernel Hardened e moduli di auditing base installati."

# --- FASE 2: HARDENING DI RETE (IDEMPOTENTE) ---
log "Installazione e configurazione di UFW, Fail2ban, DNSCrypt, Tor..."
# opensnitch rimosso da qui
sudo pacman -S --needed --noconfirm ufw fail2ban dnscrypt-proxy tor macchanger jq proxychains-ng
sudo systemctl enable --now ufw
sudo systemctl enable --now fail2ban
sudo systemctl enable --now tor
sudo systemctl enable --now dnscrypt-proxy
# --- NUOVA SEZIONE: CONFIGURAZIONE TOR ---
log_info "Configurazione di Tor per Transparent Proxy..."
# Aggiunge le righe necessarie a /etc/tor/torrc se non sono già presenti
if ! grep -q "VirtualAddrNetwork" /etc/tor/torrc; then
    sudo bash -c 'cat <<EOF >> /etc/tor/torrc

# --- Configurazione Omarchy-Ops ---
User tor
VirtualAddrNetwork 10.192.0.0/10
TransPort 9040
DNSPort 5353
AutomapHostsOnResolve 1
EOF'
    log_success "Configurazione Tor per Transparent Proxy aggiunta a /etc/tor/torrc."
else
    log_info "Configurazione Tor già presente in /etc/tor/torrc."
fi
# --- FINE NUOVA SEZIONE ---
log "Applicazione delle regole firewall di base e configurazione Fail2ban..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw --force enable
cat <<EOF | sudo tee /etc/fail2ban/jail.local > /dev/null
[DEFAULT]
bantime = 1h
maxretry = 5
[sshd]
enabled = true
EOF
log "Configurazione di DNSCrypt (Quad9)..."
sudo cp "./config/dnscrypt-proxy.toml" /etc/dnscrypt-proxy/dnscrypt-proxy.toml
log_success "Firewall e servizi di rete configurati."

# --- FASE 3: INSTALLAZIONE ARSENALE (IDEMPOTENTE) ---
if ! grep -q "\[blackarch\]" /etc/pacman.conf; then
    log "Aggiunta del repository BlackArch..."
    cd /tmp && curl -sO https://blackarch.org/strap.sh
    chmod +x strap.sh && sudo ./strap.sh
    sudo pacman -Syu --noconfirm
else
    log_success "Repository BlackArch già presente."
fi
log "Installazione della suite di sicurezza professionale (solo pacchetti mancanti)..."
#errore dato da owasp-zap(tolto)
sudo pacman -S --needed --noconfirm  metasploit burpsuite aircrack-ng autopsy cutter hash-identifier steghide trivy exploit-db wireshark-qt nmap sqlmap ffuf gobuster whatweb dnsrecon impacket bettercap hydra john hashcat kerbrute seclists
sudo searchsploit -u || log_warn "searchsploit ha restituito un codice non zero ma non critico"
sudo pacman -Sc --noconfirm 
log_success "Arsenale di sicurezza installato."
# --- FASE 4: INSTALLAZIONE UTILITY CHIMERA ---
log "Installazione di Guardian CLI (gcli) e Daemon..."
sudo cp ./scripts/gcli /usr/local/bin/gcli
sudo cp ./scripts/guardian_daemon.sh /usr/local/sbin/guardian_daemon.sh
sudo chmod +x /usr/local/bin/gcli /usr/local/sbin/guardian_daemon.sh

# Crea il file .service, ma NON abilitarlo ancora
cat <<'EOF' | sudo tee /etc/systemd/system/guardian-daemon.service > /dev/null
[Unit]
Description=Chimera Guardian - Real-time Security Monitor
After=network-online.target falco.service lkrg.service opensnitchd.service
[Service]
Type=simple
ExecStart=/usr/local/sbin/guardian_daemon.sh
ProtectSystem=full
ProtectHome=yes
NoNewPrivileges=yes
PrivateTmp=yes
LockPersonality=yes
Restart=always
RestartSec=10
User=root
[Install]
WantedBy=multi-user.target
EOF
# --- FIREWALL CONFIGURATION (NFTABLES) ---
sudo tee /etc/nftables.conf >/dev/null <<'EOF'
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority 0;
    ct state established,related accept
    iif lo accept
    tcp dport {22, 443, 80} accept
    icmp type echo-request accept
    drop
  }
  chain forward { type filter hook forward priority 0; drop }
  chain output {
    type filter hook output priority 0;
    accept
  }
}
EOF
sudo systemctl restart nftables
echo "[+] NFTables firewall configured."

log_success "Utility Chimera copiate."
sudo nft list ruleset > /etc/nftables.conf
sudo systemctl enable --now nftables

log_success "FASE 1 di Upgrade a Omarchy-Ops completata!"
log "[✔] Configurazione base completata. Riavvio necessario prima di part2."
read -p "Vuoi riavviare ora? (Y/n): " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  sudo reboot
fi

