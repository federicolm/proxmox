#!/bin/bash

# Colori
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' 

echo -e "${YELLOW}========================================================${NC}"
echo -e "      PVE & SSH SENTINEL - OMNISCIENT ACTIVE AUDIT"
echo -e "      Data: $(date)"
echo -e "${YELLOW}========================================================${NC}"

# 1. Caricamento Dati
echo -ne "[*] Analisi totale Journal (Deep History)... "

# SSH Data
SSH_RAW=$(journalctl _SYSTEMD_UNIT=ssh.service | grep "Failed password")
SSH_OK=$(journalctl _SYSTEMD_UNIT=ssh.service | grep -c "Accepted password")
SSH_IPS=$(echo "$SSH_RAW" | sed -n 's/.*from \([^ ]*\) port.*/\1/p')

# GUI Data
GUI_RAW=$(journalctl -u pvedaemon -u pveproxy | grep "authentication failure")
GUI_OK=$(journalctl -u pvedaemon -u pveproxy | grep -c "successful auth")
GUI_IPS=$(echo "$GUI_RAW" | sed -n 's/.*rhost=::ffff:\([^ ]*\) .*/\1/p')

ALL_IPS_TOTAL=$(echo -e "$SSH_IPS\n$GUI_IPS" | grep -v '^$' | sort)
TOTAL_ATTACKS=$(echo "$ALL_IPS_TOTAL" | wc -l)
echo -e "${GREEN}Fatto.${NC}"

get_country() {
    local country=$(curl -s --max-time 1.2 "http://ip-api.com/csv/$1?fields=country")
    echo "${country:-Unknown}"
}

# --- SEZIONE 2: NUOVE STATISTICHE GLOBALI ---
echo -e "\n${CYAN}[🌐] STATISTICHE GLOBALI DI ACCESSO:${NC}"
echo -e "  -> Tentativi Brute Force totali: ${RED}$TOTAL_ATTACKS${NC}"
echo -e "  -> Login SSH Riusciti: ${GREEN}$SSH_OK${NC}"
echo -e "  -> Login GUI Riusciti: ${GREEN}$GUI_OK${NC}"
echo -ne "  -> Ultimo attacco rilevato: ${YELLOW}"
journalctl -u ssh -u pvedaemon -u pveproxy | grep -E "Failed password|authentication failure" | tail -n 1 | awk '{print $1,$2,$3}'
echo -ne "${NC}"

# --- SEZIONE 3: TOP 5 PAESI ATTACCANTI ---
echo -e "\n${CYAN}[🌍] TOP 5 NAZIONI ATTACCANTI:${NC}"
# Estraiamo i paesi degli IP più frequenti (campionamento per velocità)
echo "$ALL_IPS_TOTAL" | uniq -c | sort -nr | head -n 20 | awk '{print $2}' | while read ip; do
    get_country "$ip"
done | sort | uniq -c | sort -nr | head -n 5 | awk '{printf "  - %-15s %s tentativi\n", $2, $1}'

# --- SEZIONE 4: TOP 10 + AUTO-BAN (Inalterata) ---
echo -e "\n${YELLOW}[📊] TOP 10 ATTACCANTI E AZIONI CORRETTIVE:${NC}"
echo -e "Prove\tIP\t\tNazione\t\tTarget\t\tStato/Azione"
echo -e "------------------------------------------------------------------------"

ALL_BANNED=""
for jail in sshd proxmox; do ALL_BANNED+="$(fail2ban-client status $jail 2>/dev/null) "; done

echo "$ALL_IPS_TOTAL" | uniq -c | sort -nr | head -n 10 | while read count ip; do
    target="SSH"
    echo "$GUI_IPS" | grep -q "$ip" && { echo "$SSH_IPS" | grep -q "$ip" && target="BOTH" || target="GUI"; }
    
    if [[ "$ALL_BANNED" =~ "$ip" ]]; then
        status="${GREEN}[BANNED]${NC}"
    else
        jail_to_use="sshd"; [ "$target" != "SSH" ] && jail_to_use="proxmox"
        fail2ban-client set $jail_to_use banip $ip >/dev/null 2>&1
        status="${RED}[AUTO-BANNED]${NC}"
    fi

    printf "%-8s %-15s %-15s %b%-10s%b \t %b\n" "$count" "$ip" "$(get_country "$ip")" "$NC" "$target" "$NC" "$status"
done

# --- SEZIONE 5: UTENZE ---
echo -e "\n${YELLOW}[🎯] STATISTICHE UTENZE TOTALI:${NC}"
echo -ne "  SSH: "; echo "$SSH_RAW" | sed -n 's/.*for \(invalid user \)\?\([^ ]*\) from.*/\2/p' | sort | uniq -c | sort -nr | head -n 5 | xargs
echo -ne "  GUI: "; echo "$GUI_RAW" | sed -n 's/.*user=\([^ ]*\).*/\1/p' | cut -d' ' -f1 | sort | uniq -c | sort -nr | head -n 5 | xargs

# --- SEZIONE 6: RIEPILOGO JAILS ---
echo -e "\n${GREEN}[🛡️] STATO FINALE PROTEZIONE:${NC}"
for jail in sshd proxmox; do
    count_jail=$(fail2ban-client status $jail | sed -n '/Banned IP list:/ s/.*Banned IP list:[ \t]*//p' | wc -w)
    echo -e "  -> Jail: $jail | Ban attivi: ${YELLOW}$count_jail${NC}"
done

echo -e "\n${YELLOW}========================================================${NC}"
