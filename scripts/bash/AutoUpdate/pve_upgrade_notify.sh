#!/bin/bash

# --- CONFIGURAZIONE EMAIL ---
USERS_EMAILS="email1@example.com email2@example.com"
ADMIN_EMAILS="email1@example.com email2@example.com"

HOSTNAME=$(hostname)
LOG_FILE="/var/log/pve_upgrade_daily.log"
KERNEL_NEED_REBOOT=false

# Evita interazioni bloccanti durante gli aggiornamenti di apt
export DEBIAN_FRONTEND=noninteractive

# Soglia minima di spazio libero su / (in Megabyte) - Es: 3000 MB (circa 3GB)
MIN_FREE_SPACE_MB=3000

# Inizio log
echo "--- Inizio Aggiornamento: $(date) ---" > $LOG_FILE

# --- FUNZIONE INVIO EMAIL ---
send_individual_emails() {
    local list="$1"
    local subj="$2"
    local msg="$3"
    for email in $list; do
        echo -e "$msg" | mutt -s "$subj" -- "$email"
        echo "Email inviata a: $email" >> $LOG_FILE
    done
}

# --- 1. SBLOCCO CODA APT (Gestione Kernel Appesi / Dipendenze Rotte) ---
echo "[INFO] Controllo preventivo integrità pacchetti..." >> $LOG_FILE

# Se ci sono pacchetti meta-kernel corrotti o parzialmente installati che bloccano APT,
# li intercettiamo e li rimuoviamo forzatamente dal database di dpkg per sbloccare la coda.
BROKEN_META=$(dpkg -l | awk '/^i[UFRH]  (proxmox|pve)-kernel-[0-9]/ {print $2}')
if [ -n "$BROKEN_META" ]; then
    echo "[WARN] Rilevato meta-pacchetto kernel bloccato: $BROKEN_META. Forzo la rimozione..." >> $LOG_FILE
    dpkg --purge --force-all $BROKEN_META >> $LOG_FILE 2>&1
fi

# Tenta un primo ripristino standard delle dipendenze rimaste in sospeso
apt-get install -f -y >> $LOG_FILE 2>&1


# --- 2. CONTROLLO PREVENTIVO SPAZIO DISPONIBILE ---
FREE_SPACE_MB=$(df -m / | awk 'NR==2 {print $4}')

if [ "$FREE_SPACE_MB" -lt "$MIN_FREE_SPACE_MB" ]; then
    echo "[WARN] Spazio scarso ($FREE_SPACE_MB MB). Tento pulizia preventiva..." >> $LOG_FILE
    
    # Svuota cache pacchetti e log di sistema
    apt-get clean
    journalctl --vacuum-time=2d >> $LOG_FILE 2>&1
    rm -f /var/log/*.gz /var/log/*.1 /var/log/*/*.gz /var/log/*/*.1 >/dev/null 2>&1

    # Rimozione radicale delle configurazioni residue dei vecchi kernel (solo se esistono)
    RC_KERNELS=$(dpkg -l | awk '/^rc linux-image-|^rc proxmox-kernel-/ {print $2}')
    if [ -n "$RC_KERNELS" ]; then
        dpkg --purge $RC_KERNELS >> $LOG_FILE 2>&1
    fi
    
    # Primo tentativo di autoremove dei vecchi kernel e moduli
    apt-get autoremove --purge -y >> $LOG_FILE 2>&1
    
    # Ricontrolla lo spazio dopo la prima passata di pulizia
    FREE_SPACE_MB=$(df -m / | awk 'NR==2 {print $4}')
    
    if [ "$FREE_SPACE_MB" -lt "$MIN_FREE_SPACE_MB" ]; then
        echo "[WARN] Spazio ancora sotto la soglia ($FREE_SPACE_MB MB). Manovra extrema ratio sui kernel..." >> $LOG_FILE
        
        # FORZATURA UNIVERSALE KERNEL (Sintassi Corretta: apt-mark)
        OLD_KERNELS=$(dpkg -l | awk '/proxmox-kernel-.*-pve|pve-kernel-.*-pve/ {print $2}' | grep -v "$(uname -r)")
        if [ -n "$OLD_KERNELS" ]; then
            apt-mark auto $OLD_KERNELS >> $LOG_FILE 2>&1
            apt-get autoremove --purge -y >> $LOG_FILE 2>&1
        fi
        
        # Sincronizza i bootloader dopo lo spurgo forzato
        if command -v proxmox-boot-tool >/dev/null 2>&1 && [ -f /etc/kernel/proxmox-boot-uuids ]; then
            proxmox-boot-tool refresh >> $LOG_FILE 2>&1
        else
            update-grub >> $LOG_FILE 2>&1
        fi

        # Ultimo controllo definitivo dello spazio prima del blocco
        FREE_SPACE_MB=$(df -m / | awk 'NR==2 {print $4}')
        
        if [ "$FREE_SPACE_MB" -lt 1500 ]; then
            SUBJECT="[CRITICO] Aggiornamento PVE ANNULLATO per spazio insufficiente su $HOSTNAME"
            BODY="Il processo di aggiornamento automatico è stato INTERROTTO preventivamente.\n\n"
            BODY+="Spazio disponibile su / dopo pulizia kernel: $FREE_SPACE_MB MB (Soglia critica: 1500 MB).\n"
            BODY+="Liberare spazio manualmente sul nodo (es. ISO in /var/lib/vz/template) per consentire l'aggiornamento."
            
            send_individual_emails "$ADMIN_EMAILS" "$SUBJECT" "$BODY"
            echo "--- Fine Aggiornamento (ERRORE SPAZIO CRITICO): $(date) ---" >> $LOG_FILE
            exit 1
        fi
    fi
fi

# --- 3. AGGIORNAMENTO REPOSITORY ---
apt update >> $LOG_FILE 2>&1

# --- 4. VERIFICA REALE PACCHETTI AGGIORNABILI ---
UPGRADABLE_LIST=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | grep "/")
NUM_PACKAGES=$(echo "$UPGRADABLE_LIST" | grep -v '^$' | wc -l)

# Controllo preventivo per il Kernel
if echo "$UPGRADABLE_LIST" | grep -E -q "proxmox-kernel-|pve-kernel-"; then
    KERNEL_NEED_REBOOT=true
fi

# --- 5. LOGICA DI ESECUZIONE ---
if [ "$NUM_PACKAGES" -le 0 ]; then
    # --- SCENARIO A: NESSUN AGGIORNAMENTO ---
    SUBJECT="[INFO] PVE Update: Nessun aggiornamento per $HOSTNAME"
    BODY="Il processo di aggiornamento automatico è stato eseguito.\nNon ci sono pacchetti da installare, il sistema è già aggiornato."
    
    apt-get autoremove --purge -y >> $LOG_FILE 2>&1
    apt-get clean
    
    send_individual_emails "$USERS_EMAILS" "$SUBJECT" "$BODY"
    send_individual_emails "$ADMIN_EMAILS" "$SUBJECT" "$BODY"

else
    # --- SCENARIO B: CI SONO PACCHETTI DA AGGIORNARE ---
    if ! apt-get install -f -y >> $LOG_FILE 2>&1; then
        echo "[WARN] Rilevato pacchetto corrotto in coda. Tento il --fix-broken..." >> $LOG_FILE
        apt-get install --fix-broken -y >> $LOG_FILE 2>&1
    fi

    # Eseguiamo l'aggiornamento vero e proprio
    apt-get -y upgrade >> $LOG_FILE 2>&1 && apt-get -y dist-upgrade >> $LOG_FILE 2>&1
    UPGRADE_STATUS=$?

    if [ $UPGRADE_STATUS -eq 0 ]; then
        echo "[INFO] Rimozione vecchi kernel obsoleti..." >> $LOG_FILE
        apt-get autoremove --purge -y >> $LOG_FILE 2>&1
        apt-get clean
        
        if command -v proxmox-boot-tool >/dev/null 2>&1 && [ -f /etc/kernel/proxmox-boot-uuids ]; then
            proxmox-boot-tool refresh >> $LOG_FILE 2>&1
        else
            update-grub >> $LOG_FILE 2>&1
        fi
        
        SUBJECT="[OK] PVE Update Success: $HOSTNAME"
        BODY="L'aggiornamento automatico su $HOSTNAME è stato completato con successo e i vecchi kernel obsoleti sono stati rimossi.\n\n"
        BODY+="Elenco dei pacchetti aggiornati:\n$UPGRADABLE_LIST\n"
        
        if [ "$KERNEL_NEED_REBOOT" = true ]; then
            REBOOT_MSG="\n*** ATTENZIONE ***\nÈ stato installato un nuovo KERNEL.\nIl nodo deve essere riavviato."
            BODY="${BODY}${REBOOT_MSG}"
        fi

        send_individual_emails "$USERS_EMAILS" "$SUBJECT" "$BODY"
        send_individual_emails "$ADMIN_EMAILS" "$SUBJECT" "$BODY"
    else
        # FALLIMENTO
        SUBJECT="[ERRORE] PVE Update FAILED: $HOSTNAME"
        BODY="Errore durante l'installazione dei pacchetti su $HOSTNAME.\n\n"
        BODY+="Pacchetti che si è tentato di aggiornare:\n$UPGRADABLE_LIST\n\n"
        BODY+="Verificare i log in: $LOG_FILE"
        
        send_individual_emails "$ADMIN_EMAILS" "$SUBJECT" "$BODY"
    fi
fi

echo "--- Fine Aggiornamento: $(date) ---" >> $LOG_FILE
