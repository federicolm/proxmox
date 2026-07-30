#!/bin/bash

# --- CONFIGURAZIONE EMAIL ---
USERS_EMAILS=""
ADMIN_EMAILS=""

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

# --- FUNZIONE PULIZIA E GESTIONE KERNEL ---
cleanup_old_kernels() {
    local log_summary=""
    local running_ver=$(uname -r)
    
    # 1. Recupera la lista completa dei SOLI pacchetti immagine/moduli kernel reali installati (escludendo i meta-pacchetti principali)
    local all_installed_pkgs=$(dpkg -l | awk '/ii  (proxmox-kernel|pve-kernel)-[0-9].*-pve/ {print $2}' | sort -V)
    
    # Se non ci sono pacchetti kernel installati, esci
    if [ -z "$all_installed_pkgs" ]; then
        echo ""
        return
    fi

    # 2. Estrae la lista unica e ordinata delle sole versioni numeriche dei kernel (es: 6.17.13-21-pve, 7.0.14-6-pve)
    local all_versions=$(dpkg -l | awk '/ii  (proxmox-kernel|pve-kernel)-[0-9].*-pve/ {print $2}' | sed -E 's/(proxmox-kernel-|pve-kernel-|-signed)//g' | sort -V | uniq)

    # 3. Individua il kernel immediatamente precedente a quello in esecuzione
    local prev_running_ver=$(echo "$all_versions" | grep -B 1 "^${running_ver}$" | head -n 1)
    if [ "$prev_running_ver" = "$running_ver" ]; then
        prev_running_ver="" # Nessun kernel precedente trovato
    fi

    # 4. Individua tutti i kernel futuri/nuovi (uguali o superiori al running)
    local future_versions=$(echo "$all_versions" | grep -A 9999 "^${running_ver}$")

    log_summary+="\n=== SINTESI E STATO KERNEL ===\n"
    log_summary+="Kernel attualmente in esecuzione (Running): $running_ver\n"
    log_summary+="Kernel di sicurezza conservato (Precedente al Running): ${prev_running_ver:-Nessuno}\n"
    log_summary+="Kernel Nuovi/Futuri conservati:\n$future_versions\n\n"

    # 5. Determina i pacchetti da rimuovere:
    # Verranno conservati TUTTI i kernel >= running_ver E la versione prev_running_ver.
    # Tutto ciò che è più vecchio di prev_running_ver verrà purgato.
    local to_remove_pkgs=""
    for pkg in $all_installed_pkgs; do
        local keep=false
        
        # Controlla se appartiene ai kernel futuri/attuali
        for fver in $future_versions; do
            if [[ "$pkg" == *"$fver"* ]]; then
                keep=true
                break
            fi
        done
        
        # Controlla se appartiene al kernel immediatamente precedente
        if [ -n "$prev_running_ver" ] && [[ "$pkg" == *"$prev_running_ver"* ]]; then
            keep=true
        fi

        # Se non è da conservare, aggiungilo alla lista di rimozione
        if [ "$keep" = false ]; then
            to_remove_pkgs="$to_remove_pkgs $pkg"
        fi
    done

    # 6. Esecuzione purga pacchetti obsoleti
    if [ -n "$to_remove_pkgs" ]; then
        echo "[INFO] Rimozione dei seguenti vecchi kernel obsoleti:$to_remove_pkgs" >> $LOG_FILE
        log_summary+="Vecchi Kernel disinstallati e purgati dal sistema:\n$to_remove_pkgs\n\n"
        apt-get purge -y $to_remove_pkgs >> $LOG_FILE 2>&1
    else
        echo "[INFO] Nessun vecchio kernel da rimuovere. Il sistema è già pulito." >> $LOG_FILE
        log_summary+="Nessun vecchio kernel da rimuovere (sono presenti solo le versioni consentite).\n\n"
    fi

    echo -e "$log_summary"
}


# --- 1. SBLOCCO CODA APT (Gestione Kernel Appesi / Dipendenze Rotte) ---
echo "[INFO] Controllo preventivo integrità pacchetti..." >> $LOG_FILE

BROKEN_META=$(dpkg -l | awk '/^i[UFRH]  (proxmox|pve)-kernel-[0-9]/ {print $2}')
if [ -n "$BROKEN_META" ]; then
    echo "[WARN] Rilevato meta-pacchetto kernel bloccato: $BROKEN_META. Forzo la rimozione..." >> $LOG_FILE
    dpkg --purge --force-all $BROKEN_META >> $LOG_FILE 2>&1
fi

apt-get install -f -y >> $LOG_FILE 2>&1


# --- 2. CONTROLLO PREVENTIVO SPAZIO DISPONIBILE ---
FREE_SPACE_MB=$(df -m / | awk 'NR==2 {print $4}')

if [ "$FREE_SPACE_MB" -lt "$MIN_FREE_SPACE_MB" ]; then
    echo "[WARN] Spazio scarso ($FREE_SPACE_MB MB). Tento pulizia preventiva..." >> $LOG_FILE
    
    apt-get clean
    journalctl --vacuum-time=2d >> $LOG_FILE 2>&1
    rm -f /var/log/*.gz /var/log/*.1 /var/log/*/*.gz /var/log/*/*.1 >/dev/null 2>&1

    RC_KERNELS=$(dpkg -l | awk '/^rc linux-image-|^rc proxmox-kernel-/ {print $2}')
    if [ -n "$RC_KERNELS" ]; then
        dpkg --purge $RC_KERNELS >> $LOG_FILE 2>&1
    fi
    
    apt-get autoremove --purge -y >> $LOG_FILE 2>&1
    FREE_SPACE_MB=$(df -m / | awk 'NR==2 {print $4}')
    
    if [ "$FREE_SPACE_MB" -lt "$MIN_FREE_SPACE_MB" ]; then
        echo "[WARN] Spazio ancora sotto la soglia ($FREE_SPACE_MB MB). Manovra extrema ratio sui kernel..." >> $LOG_FILE
        
        OLD_KERNELS=$(dpkg -l | awk '/(proxmox-kernel|pve-kernel)-[0-9].*-pve/ {print $2}' | grep -v "$(uname -r)")
        if [ -n "$OLD_KERNELS" ]; then
            apt-mark auto $OLD_KERNELS >> $LOG_FILE 2>&1
            apt-get autoremove --purge -y >> $LOG_FILE 2>&1
        fi
        
        if command -v proxmox-boot-tool >/dev/null 2>&1 && [ -f /etc/kernel/proxmox-boot-uuids ]; then
            proxmox-boot-tool refresh >> $LOG_FILE 2>&1
        else
            update-grub >> $LOG_FILE 2>&1
        fi

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

if echo "$UPGRADABLE_LIST" | grep -E -q "proxmox-kernel-|pve-kernel-"; then
    KERNEL_NEED_REBOOT=true
fi

# --- 5. LOGICA DI ESECUZIONE ---
if [ "$NUM_PACKAGES" -le 0 ]; then
    # --- SCENARIO A: NESSUN AGGIORNAMENTO PACCHETTI ---
    echo "[INFO] Nessun aggiornamento pacchetti da applicare. Esecuzione check-up e pulizia kernel..." >> $LOG_FILE
    
    KERNEL_LOG_SUMMARY=$(cleanup_old_kernels)
    
    apt-get autoremove --purge -y >> $LOG_FILE 2>&1
    apt-get clean
    
    if command -v proxmox-boot-tool >/dev/null 2>&1 && [ -f /etc/kernel/proxmox-boot-uuids ]; then
        proxmox-boot-tool refresh >> $LOG_FILE 2>&1
    else
        update-grub >> $LOG_FILE 2>&1
    fi

    SUBJECT="[INFO] PVE Update: Nessun aggiornamento per $HOSTNAME"
    BODY="Il processo di controllo automatico è stato eseguito.\nNon ci sono pacchetti software da aggiornare.\n"
    BODY+="$KERNEL_LOG_SUMMARY"
    
    RUNNING_VER=$(uname -r)
    NEWEST_VER=$(dpkg -l | awk '/ii  (proxmox-kernel|pve-kernel)-[0-9].*-pve/ {print $2}' | sed -E 's/(proxmox-kernel-|pve-kernel-|-signed)//g' | sort -V | tail -n 1)
    
    if [ "$RUNNING_VER" != "$NEWEST_VER" ] && [ -n "$NEWEST_VER" ]; then
        BODY+="\n*** ATTENZIONE ***\nIl nodo sta ancora eseguendo la versione $RUNNING_VER ma è già presente la nuova versione $NEWEST_VER.\nÈ consigliato un riavvio del nodo."
    fi

    send_individual_emails "$USERS_EMAILS" "$SUBJECT" "$BODY"
    send_individual_emails "$ADMIN_EMAILS" "$SUBJECT" "$BODY"

else
    # --- SCENARIO B: CI SONO PACCHETTI DA AGGIORNARE ---
    if ! apt-get install -f -y >> $LOG_FILE 2>&1; then
        echo "[WARN] Rilevato pacchetto corrotto in coda. Tento il --fix-broken..." >> $LOG_FILE
        apt-get install --fix-broken -y >> $LOG_FILE 2>&1
    fi

    apt-get -y upgrade >> $LOG_FILE 2>&1 && apt-get -y dist-upgrade >> $LOG_FILE 2>&1
    UPGRADE_STATUS=$?

    if [ $UPGRADE_STATUS -eq 0 ]; then
        KERNEL_LOG_SUMMARY=$(cleanup_old_kernels)

        apt-get autoremove --purge -y >> $LOG_FILE 2>&1
        apt-get clean
        
        if command -v proxmox-boot-tool >/dev/null 2>&1 && [ -f /etc/kernel/proxmox-boot-uuids ]; then
            proxmox-boot-tool refresh >> $LOG_FILE 2>&1
        else
            update-grub >> $LOG_FILE 2>&1
        fi
        
        SUBJECT="[OK] PVE Update Success: $HOSTNAME"
        BODY="L'aggiornamento automatico su $HOSTNAME è stato completato con successo.\n\n"
        BODY+="=== ELENCO COMPLETO DEI PACCHETTI AGGIORNATI ===\n"
        BODY+="$UPGRADABLE_LIST\n"
        BODY+="$KERNEL_LOG_SUMMARY"

        NEWEST_VER=$(dpkg -l | awk '/ii  (proxmox-kernel|pve-kernel)-[0-9].*-pve/ {print $2}' | sed -E 's/(proxmox-kernel-|pve-kernel-|-signed)//g' | sort -V | tail -n 1)
        if [ "$KERNEL_NEED_REBOOT" = true ] || [ "$(uname -r)" != "$NEWEST_VER" ]; then
            REBOOT_MSG="*** ATTENZIONE ***\nÈ presente un nuovo KERNEL non ancora caricato ($NEWEST_VER).\nIl nodo deve essere riavviato."
            BODY="${BODY}\n${REBOOT_MSG}"
        fi

        send_individual_emails "$USERS_EMAILS" "$SUBJECT" "$BODY"
        send_individual_emails "$ADMIN_EMAILS" "$SUBJECT" "$BODY"
    else
        # FALLIMENTO
        SUBJECT="[ERRORE] PVE Update FAILED: $HOSTNAME"
        BODY="Errore durante l'installazione dei pacchetti su $HOSTNAME.\n\n"
        BODY+="=== ELENCO PACCHETTI CHE SI È TENTATO DI AGGIORNARE ===\n$UPGRADABLE_LIST\n\n"
        BODY+="Verificare i log in: $LOG_FILE"
        
        send_individual_emails "$ADMIN_EMAILS" "$SUBJECT" "$BODY"
    fi
fi

echo "--- Fine Aggiornamento: $(date) ---" >> $LOG_FILE
