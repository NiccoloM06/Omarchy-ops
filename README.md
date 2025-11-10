# Omarchy-ops — Manuale tecnico completo (2025)

> Arch-based OPS & Security Environment — Hyprland • Alacritty • Limine • nftables

Omarchy-ops fornisce un ambiente operativo **secure-by-default** su Arch Linux: firewall moderno (**nftables**), sandboxing (**AppArmor**, **Firejail**), auditing e detection (**auditd**, **osquery**, **Falco**, **CrowdSec**), privacy networking (**Tor**, **DNSCrypt**, **Unbound**, **WireGuard/Proton**) e automazione ops.  
L’installazione è **modulare** in tre fasi (part0 → part1 → part2) per garantire stabilità e facilità di manutenzione.

---

## Struttura del progetto

```
Omarchy-ops/
├─ upgrade_part0.sh   # Bootstrap: pacchetti, repo Typecraft, tuning, ZSH (reboot)
├─ upgrade_part1.sh   # Sicurezza & rete: abilitazioni, nftables baseline, sysctl
├─ upgrade_part2.sh   # Servizi, Waybar, guardian, backup timer
├─ scripts/
│  ├─ gcli                    # Guardian CLI: profili rete (on/off/ops/show) via nftables
│  ├─ guardian_daemon.sh      # Watchdog di Falco/Osquery/CrowdSec
│  ├─ omarchy-ops-hooks.sh    # Hook post-aggiornamento: audit, AppArmor, reload
│  └─ system_tuning.sh        # Ottimizzazioni non invasive (sysctl, udev, zram)
└─ config/
   └─ dnscrypt-proxy.toml     # DNS sicuro, cache, DNSSEC, fallback
```

---

## Sequenza di installazione (passo-passo)

1. **Part 0 — Bootstrap**
   - Installa pacchetti base (ops, sicurezza, network tools, monitoring)
   - Clona **typecraft-dev/omarchy-supplement**
   - Applica **system_tuning.sh** (sysctl + udev + zram)
   - Imposta **ZSH + Starship** (se presenti nella repo supplement)
   - **Reboot**

2. **Part 1 — Sicurezza e rete**
   - Abilita e avvia servizi: `apparmor`, `nftables`, `auditd`, `falco`, `osqueryd`, `crowdsec`
   - Scrive ruleset **nftables** baseline in `/etc/nftables.conf`
   - Applica hardening kernel in `/etc/sysctl.d/99-omarchy-hardening.conf`
   - **Reboot**

3. **Part 2 — Servizi e automazione**
   - Installa moduli **Waybar** (Tor, Falco, CVE, Restic)
   - Attiva **restic-backup.timer**
   - Registra **guardian_daemon** (watchdog) e hook post-update

> Nota: i riavvii tra le fasi **non sono opzionali**: garantiscono enforcement corretto (AppArmor, nftables, zram, udev, BPF).

---

## Guardian CLI (`scripts/gcli`)

**gcli** gestisce profili di rete e kill-switch **con nftables**: crea in runtime tabella/chain `guardian` ed imposta policy coerenti con il profilo.

Comandi principali:
- `sudo gcli on` → **Paranoid (Tor)**: tutto il traffico TCP rediretto su 9040, DNS 127.0.0.1:5353, kill-switch attivo, MAC spoofing opzionale.
- `sudo gcli off` → **Standard (DNSCrypt)**: DNS locale sicuro (dnscrypt/unbound), nessuna restrizione, MAC ripristinato.
- `sudo gcli ops` → **Operations (Proxychains)**: consente solo traffico verso il proxy definito in `/etc/proxychains.conf` (kill-switch).
- `sudo gcli show` → stato corrente (profilo attivo, DNS, MAC, kill-switch).

Interno tecnico:
- usa **nftables** (nessuna dipendenza iptables),
- attende l’apertura della porta 9040 (Tor) con `ss -tln`,
- aggiorna `/etc/resolv.conf` a seconda del profilo (Tor DNS vs dnscrypt),
- mantiene lo **state file** in `/tmp/guardian_status`.

---

## Guardian Daemon (`scripts/guardian_daemon.sh`)

Watchdog leggero che controlla ciclicamente **Falco**, **Osqueryd**, **CrowdSec**.  
Se un servizio cade, tenta il restart e logga l’evento. Consigliato registrarlo in systemd:

```
/etc/systemd/system/guardian-daemon.service
[Unit]
Description=Guardian Daemon (Falco/Osquery/CrowdSec watchdog)
After=network-online.target falco.service osqueryd.service crowdsec.service
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/guardian_daemon.sh
Restart=always
RestartSec=10s
User=root

[Install]
WantedBy=multi-user.target
```

Attivazione:
```bash
sudo cp scripts/guardian_daemon.sh /usr/local/bin/guardian_daemon.sh
sudo chmod +x /usr/local/bin/guardian_daemon.sh
sudo systemctl enable --now guardian-daemon.service
```

---

## Hooks post-aggiornamento (`scripts/omarchy-ops-hooks.sh`)

Esegue, dopo `pacman -Syu`:
- `arch-audit -u` (aggiorna database CVE)
- `aa-enforce /etc/apparmor.d/*` (enforcement)
- `systemctl reload falco || systemctl restart falco`
- `systemctl reload osqueryd || systemctl restart osqueryd`

Esecuzione come root assicurata (root-check).  
Suggerito collegamento come **pacman hook**:
```
/etc/pacman.d/hooks/99-omarchy-ops.hook -> /usr/local/bin/omarchy-ops-hooks.sh
```

---

## DNS sicuro (`config/dnscrypt-proxy.toml`)

Parametri chiave già inclusi:
```toml
listen_addresses = ['127.0.0.1:53']
require_dnssec = true
fallback_resolver = '9.9.9.9:53'
cache = true
```

Uso:
- **Standard mode** (gcli off): `/etc/resolv.conf` → 127.0.0.1 (dnscrypt/unbound)
- **Paranoid mode** (gcli on): Tor DNS (127.0.0.1:5353) tramite `torrc` configurato

---

## Ottimizzazioni di sistema (`scripts/system_tuning.sh`)

Obiettivo: **prestazioni senza invasività**.  
Applica:
- **sysctl** (`/usr/lib/sysctl.d/99-omarchy-tuning.conf`): bassa swappiness, granularità scheduler, buffer rete, printk minimo, blocco redirect ICMP.
- **udev** (`/etc/udev/rules.d/60-omarchy-ioscheduler.rules`): scheduler **bfq**, `rotational=0` per SSD.
- **zram**: swap compresso (LZ4), dimensione ≈ 50% RAM.

Rollback rapido:
```bash
sudo rm /usr/lib/sysctl.d/99-omarchy-tuning.conf
sudo rm /etc/udev/rules.d/60-omarchy-ioscheduler.rules
sudo sysctl --system
sudo swapoff /dev/zram0 2>/dev/null || true
```

---

## Servizi e riavvii

Abilitazione servizi (tipicamente in part1):
```bash
sudo systemctl enable --now apparmor nftables auditd falco osqueryd crowdsec unbound dnscrypt-proxy
```

Backup automatizzato:
```bash
sudo systemctl enable --now restic-backup.timer
```

**Reboot richiesti**: dopo part0 e dopo part1.

Verifica post-boot:
```bash
sudo systemctl --failed
sudo systemctl status apparmor nftables auditd falco osqueryd crowdsec
sudo nft list ruleset
```

---

## Tool e motivazione (cosa fanno *e perché*)

### Sicurezza, auditing e detection
- **AppArmor / apparmor-utils** — sandbox a livello kernel; isola applicazioni per ridurre l’impatto di exploit.
- **nftables** — firewall moderno unificato IPv4/IPv6; policy dichiarative; integra il kill-switch di gcli.
- **audit (auditd)** — registra eventi sensibili del kernel e utenti (compliance, forensic).
- **Falco** — rilevamento minacce runtime via syscall (BPF); segnala comportamenti anomali.
- **osquery** — inventario e stato del sistema interrogabile in SQL; policy, integrità, processi.
- **CrowdSec** — analisi comportamentale collettiva; difesa contro brute-force/scraping.
- **AIDE / Lynis** — integrità file (AIDE) e audit configurazioni (Lynis).

### Privacy, rete e anonimato
- **Tor / nyx / torsocks / onionshare** — routing anonimo, monitor di circuito (nyx), condivisione via onion.
- **dnscrypt-proxy / unbound** — DNS cifrato, caching, DNSSEC; evita leakage e MITM DNS.
- **wireguard-tools** — VPN veloce nel kernel; alternativa a OpenVPN.
- **proxychains-ng** — forzatura di traffico app via proxy (usato in gcli ops).

### Backup, storage e cifratura
- **Restic** — backup cifrati e deduplicati; integrato con systemd timer.
- **Rclone** — sync verso cloud (S3/GDrive/WebDAV).
- **age / gnupg** — cifratura moderna (age) e PGP (gnupg).
- **KeepassXC / gopass / pass** — password manager locale o git-based.

### Monitoraggio e metrica
- **glances / bpytop / htop** — diagnostica risorse in tempo reale.
- **bpftrace / tracee** — tracing kernel eventi/sicurezza.
- **netdata / prometheus / prometheus-node-exporter / grafana** — metriche e dashboard.

### Rete e analisi
- **nmap / wireshark-qt / tcpdump / mitmproxy** — ricognizione, packet capture, debugging protocolli.

### Sandbox e container
- **Firejail / firejail-profiles** — sandbox utenti per app desktop e cli.
- **bubblewrap** — contenimento utenti (flatpak runtime).
- **podman / systemd-nspawn** — container rootless e ambienti chiusi.

### Forensics e log
- **lnav / logwatch** — lettura e reportistica log.
- **testdisk / foremost / hashdeep / chkrootkit / rkhunter / yara / maltrail** — recupero, hashing, anti-rootkit, IDS di rete.

### Utility e QoL
- **zram-generator** — swap compresso via systemd.
- **macchanger** — spoofing MAC (integrato nei profili gcli).
- **fzf / bat / exa / lsd / zoxide / starship** — shell UX moderna (ricerca fuzzy, cat con highlight, ls avanzato, cd intelligente, prompt informativo).

---

## Come modificare/estendere

- **gcli**: aggiungere un nuovo profilo → creare una nuova funzione `gcli_<nome>` e aggiornare lo switch-case; usare `nft add rule` sul chain `guardian`.
- **Waybar**: gli script stanno in part2; aggiungere un modulo nuovo copiando i pattern di `waybar-tor`/`falco-alerts`.
- **Falco**: aggiungere regole locali in `/etc/falco/falco_rules.local.yaml` e `systemctl reload falco`.
- **AppArmor**: profili in `/etc/apparmor.d/`; enforce via `aa-enforce` (hook già incluso).
- **DNS**: modificare `config/dnscrypt-proxy.toml`; ricordarsi di allineare `gcli` per lo switch profilo.

Suggerimento: mantenere le funzioni di log comuni (`log`, `log_warn`, `log_success`) per coerenza tra script.

---

## Troubleshooting rapido

- **AppArmor “inactive”** → assicurarsi di aver riavviato dopo part1; controllare `systemd-boot`/cmdline kernel (se richiesto dalla distro).  
- **Tor non parte** → verificare `ss -tln | grep :9040`; controllare `tor.service` e `torrc` (DNSPort 5353).  
- **DNS leakage** → `resolv.conf` deve puntare a 127.0.0.1; verificare stato dnscrypt/unbound.  
- **Falco silenzioso** → controllare BPF support nel kernel; provare `systemctl restart falco`.  
- **Waybar moduli** → eseguibili e con permessi +x; loggare l’output in `journalctl --user`.

---

## Licenza e contributi

Progetto pensato per ambienti Arch e derivati.  
Contributi via PR sono benvenuti (nuovi profili gcli, regole Falco, moduli Waybar, integrazioni Proton).

— DHH / Typecraft integrations
