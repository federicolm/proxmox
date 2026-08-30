#!/bin/bash

# =========================================================
# Script 02: Creazione Template - VERSIONE 7
# Modifica: Aggiunta validazione spazio disco pre-import
# =========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_FILE="$SCRIPT_DIR/files/sources.json"
START_VMID=9000

# --- 0. REPORT PRE-OPERATIVO ---
echo "========================================================================"
echo "      REPORT PRE-OPERATIVO DATACENTER: $(hostname)"
echo "========================================================================"
echo "[1] SITUAZIONE STORAGE"
pvesm status
echo ""
echo "[2] TEMPLATE ESISTENTI (ID >= $START_VMID)"
qm list | awk -v s="$START_VMID" '$1 >= s {print $0}'
echo ""
echo "[3] SCANSIONE IMMAGINI"
find /var/lib/vz/template/cloudinit /mnt/pve/*/template/cloudinit -type f \( -name "*.qcow2" -o -name "*.img" \) 2>/dev/null | while read -r line; do
    echo "$line ($(du -h "$line" | awk '{print $1}'))"
done
echo "========================================================================"

# --- 1. SELEZIONE STORAGE ---
find_best_storage() {
    local all_storage=$(pvesm status | awk 'NR>1 && $3=="active" {print $2, $1, $4}')
    local best=""
    best=$(echo "$all_storage" | awk '$1 ~ /^(rbd)$/ {print $3, $2}' | sort -rn | head -n1 | awk '{print $2}')
    [[ -z "$best" ]] && best=$(echo "$all_storage" | awk '$1 ~ /^(lvmthin|zfspool)$/ {print $3, $2}' | sort -rn | head -n1 | awk '{print $2}')
    [[ -z "$best" ]] && best=$(echo "$all_storage" | awk '$1 ~ /^(dir|cephfs|nfs)$/ {print $3, $2}' | sort -rn | head -n1 | awk '{print $2}')
    echo "$best"
}

TARGET_STORAGE=$(find_best_storage)
[[ -z "$TARGET_STORAGE" ]] && { echo "[CRITICAL] No storage!"; exit 1; }

# --- 1b. VALIDAZIONE SPAZIO DISCO (NUOVA FUNZIONE) ---
check_disk_space() {
    local source_file="$1"
    local target_storage="$2"
    
    # Dimensione sorgente in KB
    local source_size_kb=$(du -k "$source_file" | awk '{print $1}')
    # Spazio disponibile sul target in KB (colonna 4 di pvesm status)
    local available_kb=$(pvesm status -storage "$target_storage" | awk 'NR>1 {print $4}')
    
    # Margine di sicurezza del 10% per la conversione qcow2 -> raw/lvm
    local required_kb=$(( source_size_kb + (source_size_kb / 10) ))

    if [ "$available_kb" -lt "$required_kb" ]; then
        return 1 # Spazio insufficiente
    fi
    return 0 # Spazio OK
}

# --- 2. LOGICA VMID ---
NEXT_ID=$START_VMID
get_next_free_id() {
    while qm status "$NEXT_ID" >/dev/null 2>&1 || [ -f "/etc/pve/qemu-server/${NEXT_ID}.conf" ]; do
        ((NEXT_ID++))
    done
    echo "$NEXT_ID"
}

# --- 3. TROVA FILE ---
get_source_path() {
    local search_name="$1"
    find /var/lib/vz/template/cloudinit /mnt/pve/*/template/cloudinit -type f -iname "$search_name" 2>/dev/null | head -n 1
}

# --- 4. LOOP ESECUZIONE ---
while read -r row; do
    os=$(echo "$row" | jq -r '.os')
    ver=$(echo "$row" | jq -r '.version')
    format=$(echo "$row" | jq -r '.format')
    
    clean_name=$(echo "${os}-${ver}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr '.' '-' | sed 's/[^a-z0-9-]//g' | sed 's/--/-/g')
    template_name="tmpl-${clean_name}"
    
    name_v1="${os// /_}-${ver}-cloudinit.${format}"
    name_v2="${os}-${ver}-cloudinit.${format}"
    name_v3="${os} ${ver}-cloudinit.${format}"

    echo "[PROCESS] Analisi: $os $ver"

    source_file=$(get_source_path "$name_v1")
    [[ -z "$source_file" ]] && source_file=$(get_source_path "$name_v2")
    [[ -z "$source_file" ]] && source_file=$(get_source_path "$name_v3")

    if [[ -z "$source_file" ]]; then
        echo "  [SKIP] Immagine non trovata."
        continue
    fi

    if qm list | grep -qE "[[:space:]]${template_name}([[:space:]]|$)" ; then
        echo "  [OK] Già presente ($template_name)."
        continue
    fi

    # CONTROLLO SPAZIO PRIMA DI PROCEDERE
    if ! check_disk_space "$source_file" "$TARGET_STORAGE"; then
        echo "  [SKIP] Spazio insufficiente su $TARGET_STORAGE per importare $os $ver."
        continue
    fi

    VMID_FINAL=$(get_next_free_id)
    echo "  [EXEC] Deploy VMID $VMID_FINAL ($template_name) su $TARGET_STORAGE"

    if qm create "$VMID_FINAL" --name "$template_name" --memory 1024 --cores 1 --net0 virtio,bridge=vmbr0 >/tmp/qm_err 2>&1; then
        
        echo "    -> Importazione disco..."
        if qm importdisk "$VMID_FINAL" "$source_file" "$TARGET_STORAGE" >>/tmp/qm_err 2>&1; then
            
            DISK_NAME=$(qm config "$VMID_FINAL" | grep -o "unused[0-9]:[^,]*" | head -n1 | cut -d':' -f2)
            [[ -z "$DISK_NAME" ]] && DISK_NAME="$TARGET_STORAGE:vm-$VMID_FINAL-disk-0"

            qm set "$VMID_FINAL" --scsihw virtio-scsi-pci --scsi0 "$DISK_NAME" >/dev/null 2>&1
            qm set "$VMID_FINAL" --ide2 "$TARGET_STORAGE:cloudinit" >/dev/null 2>&1
            qm set "$VMID_FINAL" --boot c --bootdisk scsi0 >/dev/null 2>&1
            qm set "$VMID_FINAL" --serial0 socket --vga serial0 >/dev/null 2>&1
            qm set "$VMID_FINAL" --agent enabled=1 >/dev/null 2>&1
            qm template "$VMID_FINAL" >/dev/null 2>&1
            echo "  [SUCCESS] Creato template $template_name."
            ((NEXT_ID++))
        else
            echo "  [ERROR] Importdisk fallito."
            qm destroy "$VMID_FINAL" --purge >/dev/null 2>&1
        fi
    else
        echo "  [ERROR] Creazione fallita: $(head -n 1 /tmp/qm_err)"
        rm -f "/etc/pve/qemu-server/${VMID_FINAL}.conf"
    fi

done < <(jq -c '.images[]' "$JSON_FILE")

echo "[LOG] Fine."

