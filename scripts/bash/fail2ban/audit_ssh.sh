#!/bin/bash

# ========================================================
# CONFIGURAZIONE UTENTE
# ========================================================
# INSERISCI IL TUO INDIRIZZO EMAIL QUI SOTTO:
EMAIL="" 

# Percorsi file
REPORT_TXT="/tmp/sentinel_report.txt"
REPORT_PS="/tmp/sentinel_report.ps"
REPORT_PDF="/root/sentinel_report.pdf"

# ========================================================
# 1. CONTROLLI PRELIMINARI E AUTO-INSTALLAZIONE
# ========================================================

if [ -z "$EMAIL" ]; then
    echo -e "\e[31mERRORE: La variabile EMAIL è vuota.\e[0m"
    echo "Modifica lo script (vim $0) e inserisci il tuo indirizzo."
    exit 1
fi

install_if_missing() {
    local cmd=$1
    local pkg=$2
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "\e[33m[*] Strumento '$cmd' non trovato. Installazione di '$pkg'...\e[0m"
        apt-get update -qq && apt-get install -y -qq "$pkg" < /dev/null
        if [ $? -ne 0 ]; then
            echo -e "\e[31m[-] Errore critico: Impossibile installare $pkg.\e[0m"
            exit 1
        fi
    fi
}

# Dipendenze aggiornate per Proxmox 9
install_if_missing "enscript" "enscript"
install_if_missing "ps2pdf" "ghostscript"
install_if_missing "sqlite3" "sqlite3"
install_if_missing "curl" "curl"
install_if_missing "mail" "mailutils"
install_if_missing "mutt" "mutt"

# ========================================================
# 2. ESECUZIONE AUDIT (Logica Consolidata)
# ========================================================

{
echo "========================================================"
echo "      PVE & SSH SENTINEL - PROXMOX 9 AUDIT"
echo "      Generato il: $(date)"
echo "      Hostname: $(hostname)"
echo "========================================================"

SSH_RAW=$(journalctl _SYSTEMD_UNIT=ssh.service | grep "Failed password")
SSH_OK=$(journalctl _SYSTEMD_UNIT=ssh.service | grep -c "Accepted password")
SSH_IPS=$(echo "$SSH_RAW" | sed -n 's/.*from \([^ ]*\) port.*/\1/p')

GUI_RAW=$(journalctl -u pvedaemon -u pveproxy | grep "authentication failure")
GUI_OK=$(journalctl -u pvedaemon -u pveproxy | grep -c "successful auth")
GUI_IPS=$(echo "$GUI_RAW" | sed -n 's/.*rhost=::ffff:\([^ ]*\) .*/\1/p')

ALL_IPS_TOTAL=$(echo -e "$SSH_IPS\n$GUI_IPS" | grep -v '^$' | sort)
TOTAL_ATTACKS=$(echo "$ALL_IPS_TOTAL" | wc -l)

echo -e "\n[🌐] STATISTICHE GLOBALI:"
echo "  -> Tentativi Brute Force totali: $TOTAL_ATTACKS"
echo "  -> Login SSH Riusciti: $SSH_OK"
echo "  -> Login GUI Riusciti: $GUI_OK"

echo -e "\n[🌍] TOP 5 NAZIONI ATTACCANTI:"
echo "$ALL_IPS_TOTAL" | uniq -c | sort -nr | head -n 20 | awk '{print $2}' | while read ip; do
    curl -s --max-time 1.2 "http://ip-api.com/csv/$ip?fields=country"
done | sort | uniq -c | sort -nr | head -n 5 | awk '{printf "  - %-15s %s IP unici\n", $2, $1}'

echo -e "\n[📊] TOP 10 ATTACCANTI E AUTO-BAN:"
echo -e "Prove\tIP\t\tNazione\t\tTarget\t\tStato"
echo "------------------------------------------------------------------------"
ALL_BANNED=""
for jail in sshd proxmox; do ALL_BANNED+="$(fail2ban-client status $jail 2>/dev/null) "; done

echo "$ALL_IPS_TOTAL" | uniq -c | sort -nr | head -n 10 | while read count ip; do
    target="SSH"
    echo "$GUI_IPS" | grep -q "$ip" && { echo "$SSH_IPS" | grep -q "$ip" && target="BOTH" || target="GUI"; }
    
    if [[ "$ALL_BANNED" =~ "$ip" ]]; then
        status="[BANNED]"
    else
        jail_to_use="sshd"; [ "$target" != "SSH" ] && jail_to_use="proxmox"
        fail2ban-client set $jail_to_use banip $ip >/dev/null 2>&1
        status="[AUTO-BANNED]"
    fi
    COUNTRY=$(curl -s --max-time 1.2 "http://ip-api.com/csv/$ip?fields=country")
    printf "%-8s %-15s %-15s %-10s \t %s\n" "$count" "$ip" "$COUNTRY" "$target" "$status"
done

echo -e "\n[🎯] TOP UTENZE COLPITE:"
echo -ne "  SSH: "; echo "$SSH_RAW" | sed -n 's/.*for \(invalid user \)\?\([^ ]*\) from.*/\2/p' | sort | uniq -c | sort -nr | head -n 5 | xargs
echo -ne "  GUI: "; echo "$GUI_RAW" | sed -n 's/.*user=\([^ ]*\).*/\1/p' | cut -d' ' -f1 | sort | uniq -c | sort -nr | head -n 5 | xargs

echo -e "\n[🛡️] STATO JAILS:"
for jail in sshd proxmox; do
    count_jail=$(fail2ban-client status $jail | sed -n '/Banned IP list:/ s/.*Banned IP list:[ \t]*//p' | wc -w)
    echo "  -> Jail: $jail | Ban attivi: $count_jail"
done
} > "$REPORT_TXT"

# ========================================================
# 3. GENERAZIONE PDF E INVIO
# ========================================================

enscript -B -f "Courier@8" "$REPORT_TXT" -p "$REPORT_PS" &> /dev/null
ps2pdf "$REPORT_PS" "$REPORT_PDF"

if [ -f "$REPORT_PDF" ]; then
    echo -e "\e[32m[+] Report PDF creato in $REPORT_PDF\e[0m"

    # Nuovo comando di invio con MUTT
    echo "In allegato il report di sicurezza Sentinel per $(hostname)" | mutt -s "Proxmox Security Audit - $(date +'%d/%m/%Y')" -a "$REPORT_PDF" -- "$EMAIL"

    if [ $? -eq 0 ]; then
        echo -e "\e[32m[+] Email inviata correttamente tramite mutt.\e[0m"
    else
        echo -e "\e[31m[-] Errore nell'invio dell'email.\e[0m"
    fi

    rm -f "$REPORT_PS" "$REPORT_TXT"
else
    echo -e "\e[31m[-] Errore nella creazione del PDF.\e[0m"
fi
