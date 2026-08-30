#!/bin/bash

# ========================================================
# Script 01: Download Cloud-Init - PVE 9.1.6 - FIX TABELLA
# ========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_FILE="$SCRIPT_DIR/files/sources.json"
ADMIN_EMAIL=""
HOSTNAME=$(hostname)

# Configurazione Percorso
TARGET_DIR="/var/lib/vz/template/cloudinit"
mkdir -p "$TARGET_DIR"

# --- FUNZIONE CONTROLLO SPAZIO (Soglia 6GB) ---
check_space() {
    local free_kb=$(df -k "$TARGET_DIR" | awk 'NR==2 {print $4}')
    [ "$free_kb" -lt 6291456 ] && return 1 || return 0
}

# --- INIZIO COSTRUZIONE REPORT ---
# Usiamo un file temporaneo per evitare problemi di concatenazione variabili
TMP_REPORT="/tmp/cloudinit_report.txt"
echo "Audit Cloud-Init - $HOSTNAME (PVE 9.1.6)" > "$TMP_REPORT"
echo "Data: $(date)" >> "$TMP_REPORT"
echo "--------------------------------------------------------------------------------------" >> "$TMP_REPORT"
printf "%-30s | %-12s | %-20s\n" "IMMAGINE" "ESITO" "NOTE" >> "$TMP_REPORT"
echo "--------------------------------------------------------------------------------------" >> "$TMP_REPORT"

# --- ESECUZIONE ---
while read -r image; do
    os=$(echo "$image" | jq -r '.os')
    ver=$(echo "$image" | jq -r '.version')
    url=$(echo "$image" | jq -r '.url')
    expected_hash=$(echo "$image" | jq -r '.checksum')
    format=$(echo "$image" | jq -r '.format')
    
    clean_os="${os// /_}"
    image_name="${clean_os,,}-${ver}-cloudinit.${format}"
    target_file="$TARGET_DIR/$image_name"

    # Logica di stato
    STATUS=""
    NOTE=""

    # 1. Controllo se presente
    if [[ -f "$target_file" ]]; then
        current_h=$(sha256sum "$target_file" | awk '{print $1}')
        if [[ "$current_h" == "$expected_hash" ]]; then
            STATUS="OK"
            NOTE="GIA PRESENTE"
        else
            rm -f "$target_file"
            STATUS="REPLACE"
            NOTE="HASH ERRATO"
        fi
    fi

    # 2. Download se non OK
    if [[ "$STATUS" != "OK" ]]; then
        if ! check_space; then
            STATUS="SKIP"
            NOTE="DISCO PIENO"
        else
            temp_file="$TARGET_DIR/$(basename "$url")"
            wget -q --no-check-certificate -O "$temp_file" "$url"
            if [[ $? -eq 0 ]]; then
                actual_h=$(sha256sum "$temp_file" | awk '{print $1}')
                if [[ "$actual_h" == "$expected_hash" ]]; then
                    [[ "$temp_file" == *.xz ]] && unxz -f "$temp_file" && temp_file="${temp_file%.xz}"
                    mv "$temp_file" "$target_file"
                    STATUS="DOWNLOAD"
                    NOTE="SUCCESSO"
                else
                    STATUS="ERROR"
                    NOTE="HASH MISMATCH"
                    rm -f "$temp_file"
                fi
            else
                STATUS="ERROR"
                NOTE="WGET FAIL"
            fi
        fi
    fi

    # SCRITTURA RIGA NEL FILE TEMPORANEO (Garantisce l'invio a capo)
    printf "%-30s | %-12s | %-20s\n" "$os $ver" "$STATUS" "$NOTE" >> "$TMP_REPORT"

done < <(jq -c '.images[]' "$JSON_FILE")

echo "--------------------------------------------------------------------------------------" >> "$TMP_REPORT"

# --- INVIO EMAIL E PULIZIA ---
cat "$TMP_REPORT" | mutt -s "Cloud-Init Audit: $HOSTNAME" -- "$ADMIN_EMAIL"
rm -f "$TMP_REPORT"

