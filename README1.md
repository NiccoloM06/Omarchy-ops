# 🚀 Kit di Potenziamento "Omarchy-Ops" (v52)

![Status](https://img.shields.io/badge/status-stable-brightgreen) ![Kernel](https://img.shields.io/badge/kernel-linux--hardened-red) ![Target](https://img.shields.io/badge/target-Omarchy-blue)

> **v52 (Idempotent Edition)**: Un kit di potenziamento chirurgico per Omarchy. Installa in modo sicuro solo i componenti di sicurezza mancanti, trasformando l'estetica di Omarchy in una vera fortezza operativa.

---

## 1.0 Obiettivo

Questo repository **non** è un installer. È un kit di potenziamento ("upgrade kit") intelligente e idempotente, progettato per essere applicato **sopra** un'installazione Omarchy (di DHH) esistente e crittografata (LUKS).

**Obiettivo:**  
Iniettare un'architettura di sicurezza di livello enterprise (hardening, monitoraggio, tooling) nell'ambiente Omarchy, imponendo una postura "secure-by-default".

---

## 2.0 Flusso di Installazione

**Prerequisito fondamentale:** Omarchy già installato su un disco crittografato con LUKS.

### Fase 1: Creazione dell'Utente Operativo (Raccomandato)

```bash
sudo useradd -m -G wheel -s /bin/bash ops-hack
sudo passwd ops-hack
```

> Nota: esegui il login come 'ops-hack' per tutti i passaggi successivi.

### Fase 2: Esecuzione del Kit di Potenziamento

```bash
sudo pacman -S --noconfirm git
git clone https://URL_DEL_TUO_REPO/omarchy-ops.git
cd omarchy-ops
chmod +x upgrade.sh
sudo ./upgrade.sh
```

> ⚠️ Attenzione: lo script modifica servizi critici. Eseguilo solo con backup aggiornati.

### Fase 3: Passaggi Manuali Critici (Post-Upgrade)

**Configurazione Bootloader (Limine)**

```bash
sudo nano /etc/kernel/cmdline
```

Aggiungi alla fine della riga esistente:

```
lsm=landlock,lockdown,yama,apparmor,bpf
```

Aggiorna l'hook del kernel:

```bash
sudo pacman -S linux-hardened
```

**Configurazione fstab (BTRFS)**

```bash
sudo nano /etc/fstab
```

Aggiungi `compress=zstd,noatime` alle opzioni della partizione root / (se non già presenti).

**Integrazione Waybar**

```bash
nano ~/.config/waybar/config
```

Aggiungi questo blocco JSON nell'array `"modules-right"`:

```json
"custom/guardian": {
    "format": "🛡️ {} <span color='{}'>{}</span>",
    "exec": "cat /run/chimera/state.json | jq -r 'if .profile == \"PARANOID\" then \"#ff5555\" else \"#50fa7b\" end as $color | .profile as $profile | \"\\($profile) \\($color) \\(.status)\"'",
    "exec-if": "test -f /run/chimera/state.json",
    "return-type": "json",
    "interval": 3,
    "tooltip": true,
    "on-click": "sudo gcli show"
}
```

Apri il file di stile:

```bash
nano ~/.config/waybar/style.css
```

Aggiungi:

```css
#custom-guardian {
    padding: 0 10px;
    border-radius: 10px;
    margin: 4px;
}
#custom-guardian.warn {
    background-color: #f1fa8c;
    color: #282a36;
}
#custom-guardian.alert {
    background-color: #ff5555;
    color: #f8f8f2;
}
```

Riavvia il sistema:

```bash
sudo reboot
```

### Fase 4: Inizializzazione AIDE (Post-Riavvio)

```bash
sudo aide --init
sudo mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
```

> 💡 Consiglio: copia `/var/lib/aide/aide.db.gz` su un supporto esterno sicuro.

---

## 3.0 Controllo Operativo (gcli)

| Comando        | Descrizione                                                                 |
|----------------|-----------------------------------------------------------------------------|
| `sudo gcli on`   | Modalità Paranoid (Default): Kill Switch attivo, traffico via Tor, MAC Spoofing attivo |
| `sudo gcli off`  | Modalità Standard: Connessione diretta, DNS cifrato, MAC Spoofing disattivo |
| `sudo gcli show` | Mostra lo stato di sicurezza attuale (profilo, DNS, MAC, firewall)         |

---

## 4.0 Funzionalità Aggiunte

- **Difesa a livello kernel:** `linux-hardened` + LKRG  
- **Integrità e auditing:** AIDE, Falco, auditd, chkrootkit, rkhunter, lynis, clamav  
- **Firewalling avanzato:** UFW (ingress), OpenSnitch (egress), Fail2ban  
- **Arsenale completo:** BlackArch tools (Metasploit, Burp, ZAP, SearchSploit, Aircrack, Nmap, SQLMap, Wireshark)  
- **Monitoraggio daemon:** `guardian_daemon.sh` per servizi critici

---

## 5.0 Disclaimer

> ⚠️ Attenzione: l'uso di questi strumenti è di tua esclusiva responsabilità. Agisci sempre eticamente e solo con autorizzazione.

---

## 6.0 Licenza

MIT
