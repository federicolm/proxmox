#!/bin/bash

echo "========================================================"
echo "      SSH SENTINEL - PERMANENT FORTRESS MODE"
echo "========================================================"

# Recupero parametri reali da Fail2Ban
MAX_RETRY=$(fail2ban-client get sshd maxretry)
FIND_TIME_SEC=$(fail2ban-client get sshd findtime)
BAN_TIME=$(fail2ban-client get sshd bantime)

# Se findtime è un giorno, lo formattiamo bene per il journal
FIND_TIME_JOURNAL="${FIND_TIME_SEC} seconds"

echo "[*] Configurazione Attiva:"
echo "    -> Maxretry:  $MAX_RETRY"
echo "    -> Findtime:  $FIND_TIME_JOURNAL"
echo "    -> Bantime:   $BAN_TIME (Permanente)"

get_country() {
    local ip=$1
    if [[ $ip == 192.168.* ]] || [[ $ip == 127.* ]]; then echo "LAN"
    else curl -s "http://ip-api.com/csv/$ip?fields=country"; fi
}

# --- SEZIONE 1: TOP ATTACCANTI STORICI ---
echo -e "\n[📊] TOP 10 NEMICI STORICI:"
journalctl _SYSTEMD_UNIT=ssh.service | grep "Failed password" | sed -n 's/.*from \([^ ]*\) port.*/\1/p' | sort | uniq -c | sort -nr | head -n 10 | while read count ip; do
    echo -e "$count\t$ip\t$(get_country $ip)"
done

# --- SEZIONE 2: ALLINEAMENTO BAN ---
echo -e "\n[🔥] APPLICAZIONE BAN (Finestra: $FIND_TIME_JOURNAL)..."
ips_to_ban=$(journalctl _SYSTEMD_UNIT=ssh.service --since "-$FIND_TIME_JOURNAL" | grep "Failed password" | sed -n 's/.*from \([^ ]*\) port.*/\1/p' | sort | uniq -c | awk -v limit="$MAX_RETRY" '$1 >= limit {print $2}')
currently_banned=$(fail2ban-client status sshd | sed -n '/Banned IP list:/ s/.*Banned IP list:[ \t]*//p')

for ip in $ips_to_ban; do
    if [[ $ip == 192.168.* ]] ; then continue; fi
    if [[ ! $currently_banned =~ $ip ]]; then
        echo "  [+] PERMA-BAN: $ip ($(get_country $ip))"
        fail2ban-client set sshd banip "$ip" > /dev/null
    fi
done

# --- SEZIONE 3: DETTAGLIO PRIGIONIERI ---
echo -e "\n[🛡️] ATTUALMENTE IN PRIGIONE (PERMANENTE):"
final_banned=$(fail2ban-client status sshd | sed -n '/Banned IP list:/ s/.*Banned IP list:[ \t]*//p')

if [ -z "$final_banned" ]; then
    echo "  Nessun IP in prigione."
else
    for ip in $final_banned; do
        ip=$(echo $ip | tr -d ',')
        [ -z "$ip" ] && continue
        total_fails=$(journalctl _SYSTEMD_UNIT=ssh.service | grep "$ip" | grep "Failed password" | wc -l)
        echo "  🚩 IP: $ip ($(get_country $ip)) | Totale tentativi: $total_fails"
    done
fi

echo -e "\n========================================================"
echo "STATO: $(fail2ban-client status sshd | grep "Currently banned" | awk '{print $4}') IP bloccati per sempre."
echo "========================================================"
