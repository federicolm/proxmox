```markdown
# Script di Aggiornamento Automatico Proxmox VE (PVE Daily Upgrade)

Questo script in Bash è progettato per automatizzare il processo quotidiano di aggiornamento del sistema su nodi Proxmox VE (sia macchine virtuali che nodi fisici), includendo avanzate routine di gestione dello spazio su disco, riparazione autonoma dei pacchetti bloccati e notifiche email differenziate.

## 🚀 Funzionalità Principali

1. **Controllo e Riparazione Preventiva di APT/DPKG**: Prima di qualsiasi operazione, lo script controlla se la coda dei pacchetti è bloccata a causa di meta-pacchetti kernel rimansti "appesi" (stati di errore `iU`, `iF`, `iR`, `iH`). In caso positivo, ne forza la rimozione (`dpkg --purge --force-all`) per sbloccare il sistema in totale autonomia.
2. **Monitoraggio dello Spazio su Disco**: Verifica lo spazio libero sulla partizione Root (`/`). Se lo spazio scende sotto la soglia minima impostata (`3000 MB`), avvia manovre di emergenza incrementali:
   - Svuotamento della cache di `apt`.
   - Rotazione forzata dei log di sistema (`journalctl` a 2 giorni e rimozione vecchi log compressi).
   - Rimozione delle configurazioni residue dei vecchi kernel (`stato rc`).
   - *Extrema Ratio*: Forza lo spostamento in stato automatico e la rimozione di tutti i kernel obsoleti non in uso, preservando rigorosamente solo il kernel attivo (`uname -r`).
3. **Aggiornamento Sicuro**: Esegue un aggiornamento completo del sistema attraverso la sequenza `apt-get upgrade && apt-get dist-upgrade` in modalità non interattiva.
4. **Allineamento Agnostico del Bootloader**: Al termine dell'installazione di un nuovo kernel, lo script rileva automaticamente se il sistema utilizza **GRUB** o **systemd-boot** (`proxmox-boot-tool`) ed esegue il refresh corretto del bootloader.
5. **Notifiche Email Differenziate**: Invia report dettagliati tramite `mutt` differenziando i destinatari in base all'esito (Scenario A: nessun aggiornamento, Scenario B: aggiornamento riuscito/fallito o Errore Critico di spazio).

---

## 📂 Posizionamento dello Script

Per convenzione e sicurezza sui sistemi Linux/Proxmox, lo script deve essere posizionato in:

* **Percorso consigliato**: `/usr/local/bin/pve_upgrade_notify.sh`
* **Permessi richiesti**: Dev'essere eseguibile ed eseguito come utente `root`.

### Installazione rapida:
```bash
# Sostituisci il contenuto del file con lo script finale
nano /usr/local/bin/pve_upgrade_notify.sh

# Assegna i permessi di esecuzione
chmod +x /usr/local/bin/pve_upgrade_notify.sh

## Prerequisiti applicativi
Lo script si aspetta che i seguenti applicativi e configurazioni siano già presenti e funzionanti sul nodo Proxmox:

Mutt (mutt): Utilizzato per la composizione e l'invio delle email. Lo script si aspetta che mutt sia installato.

MTA di Sistema (Postfix / Sendmail): mutt si appoggia all'agente di trasporto della posta locale. Postfix deve essere configurato correttamente sul nodo Proxmox (es. in modalità Satellitare/Relay SMTP con autenticazione) per poter recapitare i messaggi verso gli indirizzi esterni configurati reali e funzionanti (es gmail, hotmail, etc.etc.etc.).

Repository APT Corretti: Lo script esegue comandi apt update ed è presupposto che i repository di Proxmox (No-Subscription o Enterprise) e di Debian siano configurati senza richiedere interazioni o prompt di conferma manuali.
