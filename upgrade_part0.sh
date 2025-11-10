#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
log() { echo -e "${GREEN}[part0]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[part0]${NC} $1"; }
log_err() { echo -e "${RED}[part0]${NC} $1"; }

# ==========================================================
# PART 0 — BOOTSTRAP ENVIRONMENT (Typecraft + ZSH + Tuning)
# ==========================================================

log "Aggiornamento sistema..."

sudo chmod +x ~/Omarchy-ops/install.sh
sudo ./install.sh
# --- Clone Typecraft omarchy-supplement ---
SUPP_DIR="/opt/omarchy-supplement"
if [ ! -d "$SUPP_DIR/.git" ]; then
  log "Clonazione repo Typecraft-dev/omarchy-supplement..."
  sudo git clone --depth=1 https://github.com/typecraft-dev/omarchy-supplement.git "$SUPP_DIR"
else
  log "Aggiornamento repo omarchy-supplement..."
  sudo git -C "$SUPP_DIR" pull --ff-only
fi

# --- System tuning ---
if [ -f "./scripts/system_tuning.sh" ]; then
  log "Eseguo ottimizzazioni di sistema..."
  bash ./scripts/system_tuning.sh
else
  log_warn "system_tuning.sh non trovato, salto ottimizzazioni."
fi

# --- ZSH Setup (usando file della repo Typecraft) ---
if [ -d "$SUPP_DIR/configs/zsh" ]; then
  log "Configurazione ZSH da omarchy-supplement..."
  mkdir -p "$HOME/.config/zsh"
  cp -r "$SUPP_DIR/configs/zsh/." "$HOME/.config/zsh/"
  [ -f "$SUPP_DIR/configs/zsh/.zshrc" ] && cp "$SUPP_DIR/configs/zsh/.zshrc" "$HOME/.zshrc"
  [ -f "$SUPP_DIR/configs/starship.toml" ] && cp "$SUPP_DIR/configs/starship.toml" "$HOME/.config/starship.toml"
fi

if [ "$SHELL" != "/bin/zsh" ]; then
  chsh -s /bin/zsh "$(whoami)"
  log "Shell predefinita impostata su ZSH."
fi

# Pacchetti base (repo ufficiali Arch)
sudo pacman -Sy --noconfirm --needed curl wget zsh starship fzf bat exa lsd zoxide

# Clona o aggiorna la repo Typecraft
SUPP_DIR="/opt/omarchy-supplement"
if [ ! -d "$SUPP_DIR/.git" ]; then
  sudo git clone --depth=1 https://github.com/typecraft-dev/omarchy-supplement.git "$SUPP_DIR"
else
  sudo git -C "$SUPP_DIR" pull --ff-only
fi

# Individua e lancia il system_tuning.sh del tuo progetto
# (presunto in Omarchy-ops/scripts/system_tuning.sh)
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
TUNER_PATHS=(
  "$PROJECT_DIR/scripts/system_tuning.sh"
  "./scripts/system_tuning.sh"
  "/opt/Omarchy-ops/scripts/system_tuning.sh"
)

FOUND=""
for p in "${TUNER_PATHS[@]}"; do
  if [ -f "$p" ]; then FOUND="$p"; break; fi
done

if [ -n "$FOUND" ]; then
  chmod +x "$FOUND" || true
  bash "$FOUND"
else
  echo "[!] system_tuning.sh non trovato. Percorsi provati:"
  printf ' - %s\n' "${TUNER_PATHS[@]}"
fi

sudo chmod +x ./Omarchy-ops/upgrade_part1
sudo chmod +x ./Omarchy-ops/upgrade_part2

log "${GREEN}Setup completato. Riavvia il sistema per continuare con part1.${NC}"
read -p "Riavviare ora? (Y/n): " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  sudo reboot
fi

