#!/usr/bin/env zsh
set -euo pipefail

# =======================================================================================
#  OMARCHY-OPS UPGRADE KIT (v54+) - FASE 2: FINALIZZAZIONE
#  Installa i moduli DKMS, attiva i servizi di sicurezza e integra Waybar.
#  DA ESEGUIRE DOPO IL RIAVVIO DEL KERNEL HARDENED.
# =======================================================================================

LOG_FILE="/tmp/omarchy_ops_upgrade2.log"
GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; BLUE='\033[1;34m'; NC='\033[0m'

# --- FUNZIONI DI LOGGING ---
log() {
  local level="$1"; shift
  local msg="$*"
  local ts; ts=$(date +"%Y-%m-%d %H:%M:%S")
  local color
  case "$level" in
    INFO) color="$BLUE" ;;
    SUCCESS) color="$GREEN" ;;
    WARN) color="$YELLOW" ;;
    ERROR) color="$RED" ;;
    *) color="$NC" ;;
  esac
  local log_message="[$ts] ${color}[$level]${NC} $msg"
  echo -e "$log_message" | tee -a "$LOG_FILE"
}
log_info()    { log "INFO" "$1"; }
log_warn()    { log "WARN" "$1"; }
log_success() { log "SUCCESS" "$1"; }
log_error()   { log "ERROR" "$1"; }

trap 'log_error "Installazione FASE 2 fallita. Controlla il log in $LOG_FILE."' ERR

# Pulisce il log precedente e redirige output
> "$LOG_FILE"
exec &> >(tee -a "$LOG_FILE")

if [ "$(id -u)" -ne 0 ]; then
  log_error "Questo script deve essere eseguito con 'sudo', non come root."
  exit 1
fi

if [[ ! -f /tmp/omarchy_ops_upgrade1.log ]]; then
  log_error "FASE 1 non completata. Esegui prima upgrade_part1.sh"
  exit 1
fi

export SUDO_USER=${SUDO_USER:-$USER}

# --- Carica configurazione AUR Helper ---
if [ -f "/etc/profile.d/chimera-ops.sh" ]; then
  source /etc/profile.d/chimera-ops.sh
else
  log_error "File di configurazione AUR non trovato. Interruzione."
  exit 1
fi

# --- Controllo Kernel hardened ---
local_kernel=$(uname -r)
if [[ $local_kernel != *"hardened"* ]]; then
  log_error "Kernel hardened non rilevato ($local_kernel)."
  log_error "Riavvia e seleziona 'linux-hardened' dal bootloader."
  exit 1
fi
log_success "Kernel hardened ($local_kernel) rilevato. Proseguimento."

# --- FASE 1: Installazione moduli DKMS (AUR) ---
log_info "Installazione di LKRG, Falco, OpenSnitch e BPF..."
log_warn "Attivazione modalità Operations (Proxy Kill Switch) per accesso AUR..."
sudo /usr/local/bin/gcli ops
log_success "Modalità Operations attiva."

log_info "Aggiornamento database AUR Helper tramite proxychains..."
sudo -u "$SUDO_USER" proxychains -q paru -Syyu --devel --timeupdate --noconfirm || log_warn "Aggiornamento cache AUR fallito, continuo."

log_info "Installazione pacchetti AUR..."
sudo -u "$SUDO_USER" proxychains -q paru -S --noconfirm lkrg-dkms falco-bin opensnitch bpf || log_warn "Installazione AUR con errori minori."
sudo systemctl enable --now lkrg
sudo systemctl enable --now falco-modern-bpf.service
sudo systemctl enable --now opensnitchd osqueryd crowdsec auditd
log_success "Moduli DKMS di sicurezza installati e abilitati."

# --- FASE 2: Avvio Guardian Daemon ---
log_info "Avvio del Guardian Daemon..."
sudo systemctl enable --now guardian-daemon.service
sudo systemctl start guardian-daemon.service
log_success "Guardian attivo."

# --- FASE 3: Imposta stato Paranoid ---
log_info "Impostazione postura di sicurezza predefinita (PARANOID)..."
sudo gcli on
log_success "Modalità Paranoid impostata come predefinita."

# --- FASE 4: Inizializzazione AIDE ---
log_warn "Inizializzazione di AIDE..."
sudo aide --init
sudo mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
log_success "Baseline AIDE creata."
log_warn "Copia /var/lib/aide/aide.db.gz su un supporto esterno sicuro!"

# --- FASE 5: Configura Restic Backup Timer ---
sudo tee /etc/systemd/system/restic-backup.service >/dev/null <<'EOF'
[Unit]
Description=Restic backup
[Service]
Type=oneshot
Environment=RESTIC_REPOSITORY=/var/backups/restic
Environment=RESTIC_PASSWORD_COMMAND=/usr/local/bin/restic-pass
ExecStart=/usr/bin/restic backup /home /etc --exclude-file=/etc/restic-excludes
EOF

sudo tee /etc/systemd/system/restic-backup.timer >/dev/null <<'EOF'
[Unit]
Description=Nightly Restic backup
[Timer]
OnCalendar=03:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
sudo systemctl enable --now restic-backup.timer

# --- FASE 6: WAYBAR MODULES SETUP ---
log_info "Configurazione moduli Waybar personalizzati per Omarchy-Ops..."

mkdir -p ~/.local/bin
mkdir -p "$HOME/.config/waybar"

# Script moduli
cat <<'EOF' > ~/.local/bin/waybar-tor
#!/usr/bin/env bash
systemctl --quiet is-active tor && echo '{"text":"ﯲ tor:up","class":"ok"}' || echo '{"text":"ﯲ tor:down","class":"bad"}'
EOF
chmod +x ~/.local/bin/waybar-tor

cat <<'EOF' > ~/.local/bin/arch-audit-bar
#!/usr/bin/env bash
out=$(arch-audit -u 2>/dev/null | wc -l)
cls="ok"; [ "$out" -gt 0 ] && cls="warn"
echo "{\"text\":\" cve:$out\",\"class\":\"$cls\"}"
EOF
chmod +x ~/.local/bin/arch-audit-bar

cat <<'EOF' > ~/.local/bin/falco-alerts
#!/usr/bin/env bash
LOG=/var/log/falco.log
cnt=$(sudo grep -c "Notice\\|Warning\\|Error" "$LOG" 2>/dev/null || echo 0)
cls="ok"; [ "$cnt" -gt 0 ] && cls="warn"
echo "{\"text\":\" falco:$cnt\",\"class\":\"$cls\"}"
EOF
chmod +x ~/.local/bin/falco-alerts

cat <<'EOF' > ~/.local/bin/restic-last
#!/usr/bin/env bash
st=$(journalctl -u restic-backup.service -n 1 --no-pager 2>/dev/null | grep -q "Finished" && echo ok || echo bad)
txt=" backup:$st"
cls=$([ "$st" = ok ] && echo ok || echo bad)
echo "{\"text\":\"$txt\",\"class\":\"$cls\"}"
EOF
chmod +x ~/.local/bin/restic-last

# File di configurazione JSONC dei moduli
WAYBAR_CFG="$HOME/.config/waybar/omarchy-modules.jsonc"
cat > "$WAYBAR_CFG" <<'EOF'
{
  // Moduli Omarchy-ops da integrare in Waybar
  "custom/tor": {
    "format": "{}",
    "exec": "~/.local/bin/waybar-tor",
    "interval": 10
  },
  "custom/falco": {
    "format": "{}",
    "exec": "~/.local/bin/falco-alerts",
    "interval": 30
  },
  "custom/cve": {
    "format": "{}",
    "exec": "~/.local/bin/arch-audit-bar",
    "interval": 3600
  },
  "custom/restic": {
    "format": "{}",
    "exec": "~/.local/bin/restic-last",
    "interval": 600
  }
}
EOF
log_success "Moduli Waybar creati in: $WAYBAR_CFG"

# CSS opzionale per colorazione
cat > "$HOME/.config/waybar/style-omarchy.css" <<'EOF'
#custom-tor.ok, #custom-falco.ok, #custom-restic.ok {
  color: #50fa7b;
}
#custom-tor.bad, #custom-falco.warn, #custom-cve.warn, #custom-restic.bad {
  color: #ffb86c;
}
EOF
log_success "File CSS opzionale creato: ~/.config/waybar/style-omarchy.css"

# Reload Waybar
if systemctl --user list-units | grep -q "^waybar.service"; then
  systemctl --user restart waybar && log_success "Waybar ricaricato (systemd user)."
else
  pkill -USR1 waybar 2>/dev/null && log_success "Waybar ricaricato via USR1." || log_warn "Waybar non attivo: riavvia manualmente."
fi

# Suggerimento finale
log_info "Aggiungi nel tuo ~/.config/waybar/config i moduli nella sezione 'modules-right':"
echo '  "modules-right": ["custom/tor", "custom/falco", "custom/cve", "custom/restic", "clock"]'

# --- FASE 7: PULIZIA ---
log_info "Pulizia file temporanei..."
sudo rm -f /etc/profile.d/chimera-ops.sh
log_success "Pulizia completata."

log_success "Upgrade Omarchy-Ops completato con successo!"

