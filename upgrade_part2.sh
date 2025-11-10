#!/usr/bin/env zsh
set -euo pipefail

# =======================================================================================
#  OMARCHY-OPS UPGRADE KIT (v54) - FASE 2: FINALIZZAZIONE
#  Installa i moduli DKMS e finalizza il setup. DA ESEGUIRE DOPO IL RIAVVIO.
# =======================================================================================

# --- INCOLLA QUESTO NUOVO BLOCCO ALL'INIZIO ---
LOG_FILE="/tmp/omarchy_ops_upgrade2.log"

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

trap 'log_error "Installazione FASE 2 fallita. Controlla il log." >&2' ERR

# Pulisce il log precedente
> "$LOG_FILE"
# Redirige TUTTO l'output (stdout e stderr) dei comandi nel file di log
exec &> >(tee -a "$LOG_FILE")
# --- FINE NUOVO BLOCCO ---
if [ "$(id -u)" -ne 0 ]; then
    log_error "Questo script deve essere eseguito con 'sudo', non come root."
    exit 1
fi

if [[ ! -f /tmp/omarchy_ops_upgrade1.log ]]; then
	echo "part 1 not complete"
	exit 1
fi

export SUDO_USER=${SUDO_USER:-$USER}

# Carica la variabile $AUR_HELPER_CMD salvata dallo script di FASE 1
if [ -f "/etc/profile.d/chimera-ops.sh" ]; then
    source /etc/profile.d/chimera-ops.sh
else
    log_error "File di configurazione dell'AUR Helper non trovato. Impossibile continuare."
    exit 1
fi


# --- Controllo Kernel ---
local_kernel=$(uname -r)
if [[ $local_kernel != *"hardened"* ]]; then
    log_error "Kernel hardened non rilevato. Stai eseguendo $local_kernel."
    log_error "Assicurati di aver riavviato e selezionato 'linux-hardened' dal menu di avvio."
    exit 1
fi
log_success "Kernel hardened ($local_kernel) rilevato. Proseguimento."

# --- FASE 1: INSTALLAZIONE MODULI DKMS (AUR) ---
log "Installazione di LKRG, Falco, OpenSnitch (AUR) e bpf"
# Rimosso 'opensnitch-ebpf-module' perché è già incluso in 'opensnitch'
# --- MODIFICA CHIAVE QUI ---
log_warn "Attivazione Modalità 'Operations' (Proxy Kill Switch) per l'accesso AUR..."
log_warn "Assicurati che /etc/proxychains.conf sia configurato!"
sudo /usr/local/bin/gcli ops
log_success "Modalità Operations attivata."

log "INFO" "Forzatura aggiornamento database AUR Helper ($AUR_HELPER_CMD) tramite proxychains..."
# Nota: proxychains DEVE essere eseguito come l'utente, non come root
sudo -u "$SUDO_USER" proxychains -q paru -Syyu --devel --timeupdate --noconfirm || log_warn "Aggiornamento cache AUR fallito, si tenta di continuare."

log "INFO" "Installazione pacchetti AUR tramite proxychains..."
sudo -u "$SUDO_USER" proxychains -q paru lkrg-dkms falco-bin opensnitch bpf 
sudo systemctl enable --now lkrg
sudo systemctl enable --nowfalco-modern-bpf.service 
sudo systemctl enable --now opensnitchd
sudo systemctl enable --now osqueryd
sudo systemctl enable --now crowdsec
sudo systemctl enable --now auditd

log_success "Moduli DKMS di sicurezza installati e abilitati."

# --- FASE 2: ABILITAZIONE SERVIZI CHIMERA ---
log "Avvio del Guardian Daemon..."
# Il .service file è stato creato nella FASE 1
sudo systemctl enable --now guardian-daemon.service
sudo systemctl start guardian-daemon.service
log_success "Servizi Chimera attivati."

# --- FASE 3: IMPOSTAZIONE DELLO STATO DI DEFAULT (PARANOID) ---
log "Impostazione della postura di sicurezza predefinita su PARANOID..."
sudo gcli on 
log_success "Stato 'Paranoid' impostato come predefinito." 


# --- FASE 4: INIZIALIZZAZIONE AIDE ---
log_warn "AZIONE FINALE: Inizializzazione di AIDE..."
log "Questo processo creerà la baseline di integrità del sistema e richiederà tempo."
sudo aide --init
sudo mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
log_success "Baseline AIDE creata con successo."
log_warn "CRITICO: Copia ora /var/lib/aide/aide.db.gz su un supporto esterno sicuro!"

# Abilita Restic backup timer
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


# --- WAYBAR MODULES SETUP ---
mkdir -p ~/.local/bin
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


# --- FASE 5: PULIZIA ---
log "Rimozione dei file temporanei di installazione..."
sudo rm /etc/profile.d/chimera-ops.sh
log_success "Pulizia completata."

log_success "Upgrade a Omarchy-Ops completato!"
