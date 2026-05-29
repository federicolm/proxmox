# 🚀 Proxmox VE — Daily Automated Upgrade & Auto-Heal

[![Bash Script](https://img.shields.io/badge/language-Bash-4EAA25.svg?style=flat-square)](https://www.gnu.org/software/bash/)
[![Proxmox VE](https://img.shields.io/badge/platform-Proxmox%20VE-E67E22.svg?style=flat-square)](https://www.proxmox.com)
[![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](https://opensource.org/licenses/MIT)

Un potente script Bash per l'automazione dei processi di manutenzione, pulizia e aggiornamento quotidiano dei nodi **Proxmox VE** (sia per installazioni fisiche che all'interno di macchine virtuali). 

Il core include meccanismi avanzati di **auto-healing** per sbloccare la coda APT in caso di kernel corrotti o interrotti, e routine ricorsive di **pulizia d'emergenza** se lo spazio su disco scende sotto la soglia di guardia.

---

## 📌 Indice
- [Funzionalità Principali](#-funzionalità-principali)
- [Architettura di Pulizia ed Emergenza](#-architettura-di-pulizia-ed-emergenza)
- [Requisiti e Prerequisiti](#-requisiti-e-prerequisiti)
- [Installazione e Configurazione](#-installazione-e-configurazione)
- [Codice Sorgente Integrale](#-codice-sorgente-integrale)
- [Logs e Debugging](#-logs-e-debugging)

---

## ✨ Funzionalità Principali

* **Auto-Heal della Coda APT/DPKG**: Intercetta automaticamente meta-pacchetti kernel rimasti "appesi" o in stato di inconsistenza (`iU`, `iF`, `iR`, `iH`), applicando un `dpkg --purge --force-all` mirato per ripristinare il database dei pacchetti senza alcun intervento manuale.
* **Allineamento Bootloader Agnostico**: Rileva dinamicamente se il nodo utilizza **GRUB** o **systemd-boot** (`proxmox-boot-tool`) applicando il corretto refresh dell'ambiente di boot al termine della rimozione dei vecchi kernel.
* **Notifiche Email Scalabili**: Sfrutta `mutt` per inviare report differenziati ad amministratori e utenti in base allo scenario riscontrato (nessun aggiornamento, aggiornamento riuscito, fallimento o spazio insufficiente).

---

## 🛡️ Architettura di Pulizia ed Emergenza

Quando lo spazio sulla root (`/`) scende sotto la soglia definita nella variabile `MIN_FREE_SPACE_MB` (Default: **3000 MB**), lo script esegue azioni di pulizia incrementali:

| Fase | Target | Comando / Azione |
| :--- | :--- | :--- |
| **Fase 1** | Cache APT | `apt-get clean` |
| **Fase 2** | Log di Sistema | `journalctl --vacuum-time=2d` + Rimozione forzata dei `.gz` in `/var/log` |
| **Fase 3** | Configurazione Residue | Purge dei pacchetti in stato `rc` (vecchi file di configurazione kernel rimasti orfani) |
| **Fase 4** | Moduli Orfani | Primo tentativo di `apt-get autoremove --purge` |
| **Fase 5 (Extrema Ratio)** | Vecchi Kernel | `apt-mark auto` su tutti i kernel obsoleti (preservando rigorosamente il kernel attivo da `uname -r`) seguito da uno spurgo forzato dei moduli |

> ⚠️ **Soglia Critica**: Se lo spazio residuo rimane inferiore a **1500 MB** dopo tutte le fasi di pulizia, il processo viene **interrotto preventivamente** e viene inviato un alert email critico all'amministratore per evitare il crash del nodo.

---

## 🛠️ Requisiti e Prerequisiti

Prima di implementare lo script, assicurarsi che il sistema disponga dei seguenti applicativi già configurati:

1. **Mutt**: Utilizzato per la composizione delle mail tramite CLI.
2. **MTA di Sistema (Postfix / Sendmail)**: Postfix deve essere configurato (es. in modalità *Satellitare/Relay SMTP* con autenticazione) sul nodo per garantire il recapito dei messaggi verso domini esterni.
3. **APT Repositories**: I file `sources.list` e `pve-enterprise.list` (o pve-no-subscription) devono essere allineati e non richiedere prompt interattivi.

---

## 📂 Installazione e Configurazione

### 1. Posizionamento del file
Lo script deve essere memorizzato nella directory dedicata agli applicativi locali:
```bash
nano /usr/local/bin/pve_upgrade_notify.sh
```

### 2. Creazione service e timer
Per schedulare correttamente lo script è consigliabile aggiungere un service per systemd ed un relativo timer che scatti ogni notte a mezzanotte (ad esempio).

```bash
nano /etc/systemd/system/pve-upgrade.service
```

incollare il seguente codice per il service

```bash
[Unit]
Description=Proxmox VE Daily Automated Upgrade
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pve_upgrade_notify.sh
StandardOutput=journal
StandardError=journal
```

per il timer

```bash
nano /etc/systemd/system/pve-upgrade.timer
```

incollare la seguente configurazione oppure sceglierne una più appropriata per le varie esigenze

```bash
[Unit]
Description=Run Proxmox VE Daily Upgrade at Midnight

[Timer]
OnCalendar=*-*-* 00:00:00
Persistent=true
Unit=pve-upgrade.service

[Install]
WantedBy=timers.target
```
