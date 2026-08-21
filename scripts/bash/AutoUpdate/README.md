```markdown
# 🚀 Proxmox VE — Daily Automated Upgrade & Smart Kernel Manager

[![Bash Script](https://img.shields.io/badge/language-Bash-4EAA25.svg?style=flat-square)](https://www.gnu.org/software/bash/)
[![Proxmox VE](https://img.shields.io/badge/platform-Proxmox%20VE-E67E22.svg?style=flat-square)](https://www.proxmox.com)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg?style=flat-square)](https://www.gnu.org/licenses/gpl-3.0.html)

Un potente script Bash per l'automazione dei processi di manutenzione, pulizia e aggiornamento quotidiano dei nodi **Proxmox VE** (sia per installazioni fisiche che virtualizzate). 

Il core include una **logica avanzata e chirurgica per la gestione dei kernel**, meccanismi di **auto-healing** per sbloccare la coda APT in caso di pacchetti corrotti o interrotti, e routine ricorsive di **pulizia d'emergenza** se lo spazio su disco scende sotto la soglia di guardia.

---

## 📌 Indice
- [Funzionalità Principali](#-funzionalità-principali)
- [Algoritmo di Gestione e Pulizia dei Kernel](#-algoritmo-di-gestione-e-pulizia-dei-kernel)
- [Architettura di Pulizia ed Emergenza](#-architettura-di-pulizia-ed-emergenza)
- [Requisiti, Dipendenze e Configurazioni Mail](#-requisiti-dipendenze-e-configurazioni-mail)
- [Installazione e Schedulazione Systemd](#-installazione-e-schedulazione-systemd)
- [Test di Diagnostica Automatica](#-test-di-diagnostica-automatica)
- [Risoluzione Problemi e Debugging Mail](#-risoluzione-problemi-e-debugging-mail)
- [Logs e Monitoraggio](#-logs-e-monitoraggio)

---

## ✨ Funzionalità Principali

* **Gestione Chirurgica dei Kernel (Politica a 3 Livelli)**: Analizza ed esegue ad ogni avvio una pulizia mirata che conserva **esclusivamente**:
  1. Il kernel attualmente in esecuzione (`Running`).
  2. Il kernel immediatamente precedente a quello attuale (fallback di sicurezza).
  3. Tutte le versioni future/nuove appena installate in attesa di riavvio (`Reboot`).
* **Protezione dei Meta-Pacchetti**: Distingue accuratamente i pacchetti immagine del kernel (`-pve`) dai meta-pacchetti principali (es. `proxmox-kernel-7.0`), evitando che la pulizia interrompa i futuri aggiornamenti della serie.
* **Reportistica Email Integrale**: Invia via mail (tramite `mutt`) l'elenco completo di tutti i pacchetti da aggiornare o aggiornati, insieme a un resoconto dettagliato dei kernel rilevati, conservati e rimossi.
* **Auto-Heal della Coda APT/DPKG**: Intercetta automaticamente meta-pacchetti kernel rimasti in stato di inconsistenza (`iU`, `iF`, `iR`, `iH`), applicando un `dpkg --purge --force-all` mirato per ripristinare il database senza alcun intervento manuale.
* **Allineamento Bootloader Agnostico**: Rileva dinamicamente se il nodo utilizza **GRUB** o **systemd-boot** (`proxmox-boot-tool`) applicando il corretto refresh dell'ambiente di avvio al termine delle operazioni.

---

## 🧠 Algoritmo di Gestione e Pulizia dei Kernel

La funzione `cleanup_old_kernels` analizza la gerarchia delle versioni tramite un ordinamento numerico naturale (`sort -V`). 

```text
       [ Kernel Obsoleti ]           [ Safety Fallback ]         [ Active Running ]         [ Nuovi / Futuri ]
 (Rimossi completamente)        ---> (Versione Precedente) ---> (Kernel uname -r) ---> (Installati no Reboot)
           [ELIMINATI]                   [CONSERVATO]               [CONSERVATO]               [CONSERVATI]

```

### Regole di Selezione e Conservazione

1. **In Esecuzione (`uname -r`)**: La versione attiva sul sistema viene sempre protetta.
2. **Precedente (`grep -B 1`)**: La versione antecedente a quella in esecuzione viene preservata come ripristino d'emergenza in caso di problemi dopo un aggiornamento.
3. **Futuri (`grep -A 9999`)**: Tutti i kernel con versione pari o superiore a quella in esecuzione vengono conservati integralmente.
4. **Obsoleti**: Tutti i pacchetti di kernel più vecchi del fallback vengono disinstallati e rimossi dal sistema (`apt-get purge`), liberando centinaia di megabyte o gigabyte su disco.

---

## 🛡️ Architettura di Pulizia ed Emergenza

Quando lo spazio sulla root (`/`) scende sotto la soglia definita nella variabile `MIN_FREE_SPACE_MB` (Default: **3000 MB**), lo script esegue azioni di pulizia incrementali:

| Fase | Target | Comando / Azione |
| --- | --- | --- |
| **Fase 1** | Cache APT | `apt-get clean` |
| **Fase 2** | Log di Sistema | `journalctl --vacuum-time=2d` + Rimozione dei log ruotati (`.gz` / `.1`) |
| **Fase 3** | Configurazioni Residue | Purge dei pacchetti in stato `rc` (file di configurazione orfani) |
| **Fase 4** | Moduli Orfani | Tentativo di `apt-get autoremove --purge` |
| **Fase 5 (Extrema Ratio)** | Vecchi Kernel | `apt-mark auto` sui kernel non attivi seguito dallo spurgo dei moduli |

> ⚠️ **Soglia Critica**: Se lo spazio residuo rimane inferiore a **1500 MB** dopo la pulizia, il processo si **interrompe preventivamente** inviando un alert email critico per evitare l'arresto del nodo.

---

## 🛠️ Requisiti, Dipendenze e Configurazioni Mail

### 1. Installazione delle Dipendenze

Assicurarsi che sul nodo Proxmox siano installati tutti i pacchetti necessari:

```bash
apt-get update
apt-get install -y mutt postfix sasl2-bin ca-certificates bsd-mailx

```

---

### 2. Configurazione di Postfix (Relay SMTP Satellitare)

Per consentire a Proxmox di inviare email tramite provider esterni (es. Gmail, SendGrid, ecc.), Postfix deve essere configurato come nodo satellitare.

#### A. File `/etc/postfix/main.cf`

Modificare il file aggiungendo o verificando le seguenti direttive in fondo:

```ini
myhostname = pve-hp.local
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
mydestination = $myhostname, localhost.$mydomain, localhost
mynetworks = 127.0.0.0/8
inet_interfaces = loopback-only
inet_protocols = ipv4

# Configurazione Relay SMTP
relayhost = [smtp.gmail.com]:587
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_tls_security_level = encrypt
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt

```

#### B. File `/etc/postfix/sasl_passwd`

Creare il file per le credenziali SMTP:

```bash
nano /etc/postfix/sasl_passwd

```

Inserire la riga con le credenziali (nel caso di Gmail, utilizzare una **App Password** generata da Google, senza spazi):

```text
[smtp.gmail.com]:587 tuo_indirizzo_gmail@gmail.com:xxxx-xxxx-xxxx-xxxx

```

Applicare i permessi corretti, generare il database hash e riavviare Postfix:

```bash
chmod 600 /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd
systemctl restart postfix

```

---

### 3. Configurazione di Mutt

Per garantire che l'intestazione del mittente sia formattata correttamente e il nome del nodo venga letto in automatico, configurare il file dell'utente `root`:

```bash
nano ~/.muttrc

```

Aggiungere le seguenti righe. **Nota:** È fondamentale usare i **doppi apici** (`"`) nella variabile `realname` per permettere a Bash di espandere correttamente il comando `$(hostname)`.

```ini
set sendmail="/usr/sbin/sendmail -oem -i"
set realname="Proxmox VE - $(hostname)"
set from="tuo_indirizzo_gmail@gmail.com"
set use_from=yes

```

---

## 📂 Installazione e Schedulazione Systemd

### 1. Posizionamento Script e Permessi

Creare ed incollare lo script nel percorso dedicato agli applicativi locali:

```bash
nano /usr/local/bin/pve_upgrade_notify.sh
chmod +x /usr/local/bin/pve_upgrade_notify.sh

```

### 2. Creazione del Servizio Systemd

Creare il file di servizio:

```bash
nano /etc/systemd/system/pve-upgrade.service

```

Configurazione:

```ini
[Unit]
Description=Proxmox VE Daily Automated Upgrade & Kernel Cleanup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pve_upgrade_notify.sh
StandardOutput=journal
StandardError=journal

```

### 3. Creazione del Timer Systemd

Creare il timer per l'esecuzione automatica (es. ogni notte a mezzanotte):

```bash
nano /etc/systemd/system/pve-upgrade.timer

```

Configurazione:

```ini
[Unit]
Description=Run Proxmox VE Daily Upgrade and Kernel Cleanup at Midnight

[Timer]
OnCalendar=*-*-* 00:00:00
Persistent=true
Unit=pve-upgrade.service

[Install]
WantedBy=timers.target

```

### 4. Abilitazione ed Avvio del Timer

```bash
systemctl daemon-reload
systemctl enable --now pve-upgrade.timer

```

---

## 🧪 Test di Diagnostica Automatica

È possibile eseguire un controllo completo dello stato dell'ambiente lanciando questo script di diagnostica direttamente sul nodo:

```bash
bash -c '
echo "=== 1. VERIFICA DIPENDENZE E PACCHETTI ==="
for cmd in mutt dpkg awk sed grep df journalctl; do
    if command -v $cmd >/dev/null 2>&1; then
        echo -e "[\e[32mOK\e[0m] $cmd installato: $(which$cmd)"
    else
        echo -e "[\e[31mERRORE\e[0m] $cmd MANCANTE!"
    fi
done

echo -e "\n=== 2. VERIFICA ESISTENZA E PERMESSI SCRIPT ==="
SCRIPT_PATH="/usr/local/bin/pve_upgrade_notify.sh"
if [ -f "$SCRIPT_PATH" ]; then
    echo -e "[\e[32mOK\e[0m] File trovato in $SCRIPT_PATH"
    if [ -x "$SCRIPT_PATH" ]; then
        echo -e "[\e[32mOK\e[0m] Permessi di esecuzione OK"
    else
        echo -e "[\e[31mERRORE\e[0m] Mancano i permessi di esecuzione! (Esegui: chmod +x $SCRIPT_PATH)"
    fi
else
    echo -e "[\e[31mERRORE\e[0m] Script NON trovato in $SCRIPT_PATH!"
fi

echo -e "\n=== 3. VERIFICA CONFIGURAZIONE VARIABILI EMAIL ==="
if [ -f "$SCRIPT_PATH" ]; then
    grep -E "USERS_EMAILS|ADMIN_EMAILS" "$SCRIPT_PATH"
fi

echo -e "\n=== 4. TEST DI ESECUZIONE DIRETTA DELLO SCRIPT ==="
if [ -x "$SCRIPT_PATH" ]; then
    echo "Lancio dello script in corso..."
    $SCRIPT_PATH
    echo "Stato uscita script (Exit Code): $?"
else
    echo "Impossibile eseguire lo script."
fi

echo -e "\n=== 5. ULTIMI LOG DALLO SCRIPT DEDICATO ==="
if [ -f "/var/log/pve_upgrade_daily.log" ]; then
    tail -n 20 /var/log/pve_upgrade_daily.log
else
    echo "File di log /var/log/pve_upgrade_daily.log non ancora creato."
fi
'

```

---

## 🔧 Risoluzione Problemi e Debugging Mail

### 1. Mail Troncata in Gmail ("[Messaggio troncato] Visualizza intero messaggio")

Se ricevi l'email ma Gmail ne tronca la visualizzazione, il problema **non è un errore**, ma un limite di Google: Gmail nasconde automaticamente i contenuti quando la dimensione dell'email supera i **102 KB**. Questo avviene spesso a causa dell'output prolisso generato dall'aggiornamento del bootloader (`grub-mkconfig`).

**Soluzione:**
Puoi ridurre drasticamente la lunghezza del report indirizzando in `> /dev/null 2>&1` l'output dei comandi di bootloader all'interno dello script bash `pve_upgrade_notify.sh`:

```bash
# Sostituisci la chiamata a update-grub con:
update-grub > /dev/null 2>&1

# Oppure, se usi proxmox-boot-tool:
proxmox-boot-tool refresh > /dev/null 2>&1

```

### 2. Le email non arrivano

Fai un test manuale rapido:

```bash
echo "Test invio da Proxmox $(hostname)" | mutt -s "Test Email Proxmox" -- destinatario@dominio.com

```

Quindi analizza gli errori del servizio postfix:

```bash
journalctl -u postfix -n 50 --no-pager

```

* **Errore SASL `535-5.7.8 Username and Password not accepted**`:
Password o App Password errata nel file `/etc/postfix/sasl_passwd`. Rigenerare la password per le app da Google e rieseguire `postmap /etc/postfix/sasl_passwd && systemctl restart postfix`.
* **Errore `status=deferred` o `Connection timed out` sulla porta 25**:
Il provider di rete blocca la porta 25. Assicurarsi di utilizzare la porta `587` nel file `main.cf`.

### 3. Gestione della Coda di Posta bloccata

```bash
# Visualizza le mail attualmente bloccate
mailq

# Forza il tentativo di invio immediato della coda
postfix flush

# Cancella tutti i messaggi irrecuperabili bloccati in coda
postsuper -d ALL

```

---

## 🔍 Logs e Monitoraggio

Per verificare i log specifici creati dallo script:

```bash
cat /var/log/pve_upgrade_daily.log

```

Per seguire l'esecuzione del timer/servizio tramite il journal di systemd:

```bash
journalctl -u pve-upgrade.service -f

```

Per verificare lo stato del timer programmato:

```bash
systemctl status pve-upgrade.timer

```
