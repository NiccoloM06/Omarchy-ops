#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[1;32m'; NC='\033[0m'
log() { echo -e "${GREEN}[tuning]${NC} $1"; }

log "Applico ottimizzazioni leggere per Omarchy..."

# SYSCTL
cat <<'EOF' | sudo tee /usr/lib/sysctl.d/99-omarchy-tuning.conf >/dev/null
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_background_ratio = 5
vm.dirty_ratio = 15
kernel.sched_latency_ns = 6000000
kernel.sched_min_granularity_ns = 750000
kernel.sched_wakeup_granularity_ns = 1000000
net.core.netdev_max_backlog = 4096
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
kernel.nmi_watchdog = 0
kernel.printk = 3 3 3 3
EOF

sudo sysctl --system

# UDEV
sudo mkdir -p /etc/udev/rules.d
cat <<'EOF' | sudo tee /etc/udev/rules.d/60-omarchy-ioscheduler.rules >/dev/null
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", SUBSYSTEM=="block", ATTR{queue/rotational}="0"
EOF

sudo udevadm control --reload-rules && sudo udevadm trigger

# ZRAM
if ! grep -q "zram" /proc/modules; then
  log "Abilito zram (swap compresso)..."
  sudo modprobe zram
  echo lz4 | sudo tee /sys/block/zram0/comp_algorithm >/dev/null || true
  echo $(( $(grep MemTotal /proc/meminfo | awk '{print $2}') * 1024 / 2 )) | sudo tee /sys/block/zram0/disksize >/dev/null
  sudo mkswap /dev/zram0 && sudo swapon /dev/zram0
fi

log "Ottimizzazioni applicate con successo!"
