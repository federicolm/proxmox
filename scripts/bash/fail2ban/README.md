# 🛡️ PVE & SSH Sentinel: Active Defense System

[![Bash Script](https://img.shields.io/badge/language-Bash-4EAA25.svg?style=flat-square)](https://www.gnu.org/software/bash/)
[![Proxmox VE](https://img.shields.io/badge/platform-Proxmox%20VE-E67E22.svg?style=flat-square)](https://www.proxmox.com)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg?style=flat-square)](https://www.gnu.org/licenses/gpl-3.0.html)

**PVE Sentinel** è uno script bash avanzato per **Proxmox Virtual Environment** progettato per monitorare, analizzare e neutralizzare attacchi brute-force in tempo reale. Analizza i log di sistema (SSH e GUI Proxmox), identifica gli attaccanti più aggressivi e applica automaticamente il ban tramite Fail2Ban, generando infine un report grafico in HTML.



## ✨ Caratteristiche principali

* **Analisi Deep History**: Scansione completa di tutta la cronologia del Journal (non solo le ultime ore).
* **Auto-Ban Intelligente**: Rileva gli IP con migliaia di tentativi falliti e li aggiunge istantaneamente alle jail di Fail2Ban (`sshd` o `proxmox`).
* **Geolocalizzazione**: Identifica la nazione di provenienza dei Top 10 attaccanti.
* **Target Intelligence**: Distingue tra attacchi rivolti alla Web GUI e quelli al servizio SSH.
* **Report Grafico Email**: Genera un report HTML elegante con tema "Dark Dashboard" e lo invia via email tramite Mutt/Postfix.
* **Zero Dipendenze Manuali**: Lo script verifica e installa automaticamente tutti i pacchetti necessari (`curl`, `mutt`, `sqlite3`, ecc.).

## 📊 Anteprima del Report
Il report inviato via email include:
- **Global Stats**: Totale attacchi respinti vs login riusciti.
- **Top 5 Nations**: Classifica dei paesi più ostili.
- **Top 10 Offenders**: Lista dettagliata degli IP, numero di prove e stato del ban.
- **Targeted Users**: Elenco dei nomi utente più tentati dai bot.

## 🚀 Installazione Rapida

1. **Scarica lo script:**
   ```bash
   wget https://raw.githubusercontent.com/federicolm/proxmox/develop/scripts/bash/fail2ban/audit_ssh_gui.sh
   chmod 740 audit_ssh_gui.sh

2. **Configura la tua email:**
   ```bash
   EMAIL="tua@email.it"
   
3. **Configura il postfix sul proxmox:**
   ```bash
   nano /etc/postfix/main.cf
   ```
   vai in fondo ed aggiungi (esempio per utilizzare gmail)
   ```bash
   relayhost = [smtp.gmail.com]:587
   smtp_sasl_auth_enable = yes
   smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
   smtp_sasl_security_options = noanonymous
   smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt
   smtp_use_tls = yes
   ```
   attento alla duplicazione dell'istruzione di 
   ```bash
   relayhost = 
   ```
   
   riavvia posffix e riavvia la coda :
   ```bash
   systemctl restart postfix
   postqueue -f
   ```
5. **Installa fail2ban:**
   ```bash
   # apt install fail2ban

6. **Configura jail.local e proxmox.conf all'interno di /etc/fail2ban e /etc/fail2ban/filter.d/ :**
   ```bash
   mv jail.local /etc/fail2ban/
   mv proxmox.conf /etc/fail2ban/filter.d/

7. **Riavvia il servizio fail2ban e controllane lo status :**
   ```bash
   systemctl enable --now fail2ban
   
8. **Esegui:**
   ```bash
   ./audit_ssh_gui.sh

## 📅 Automazione (service per systemd)
Per ricevere il report di sicurezza ogni lunedì mattina alle 08:00, bisogna creare un service per systemd con la configurazione del relativo timer:

```Bash
cat << 'EOF' >> /etc/systemd/system/pve-sentinel.service
[Unit]
Description=Script di protezione e reportistica quotidiano Proxmox VE basato su fail2ban
After=network-online.target postfix.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/root/audit_ssh_gui.sh

[Install]
WantedBy=multi-user.target
EOF

cat << 'EOF' >> /etc/systemd/system/pve-sentinel.timer
[Unit]
Description=Avvia la protezione e la reportistica di PVE Sentinel ogni notte a mezzanotte

[Timer]
OnCalendar=*-*-* 00:00:00
Persistent=true
Unit=pve-sentinel.service

[Install]
WantedBy=timers.target
EOF
```

al termine eseguire : 

```Bash
systemctl enable --now pve-sentinel.service
systemctl enable --now pve-sentinel.timer
```

## 🛠️ Requisiti
* **Sistema Operativo**: Proxmox VE 7.x, 8.x o 9.x.
* **Servizi**: Fail2Ban installato e attivo con le jail `sshd` e `proxmox`.
* **Email**: Postfix configurato correttamente (consigliato l'uso di un Relay SMTP come Gmail).

## 🛡️ Sicurezza
Lo script richiede privilegi di root per poter leggere i log di sistema (journalctl) e interagire con fail2ban-client per eseguire i ban.

## ⭐ Se questo script ti è stato utile, lascia una stella su GitHub!
