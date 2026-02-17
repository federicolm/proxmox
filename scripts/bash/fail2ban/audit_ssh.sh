#!/bin/bash

# ========================================================
# CONFIGURAZIONE UTENTE
# ========================================================
EMAIL="" 
REPORT_HTML="/root/sentinel_report.html"

# ========================================================
# 1. CONTROLLI E AUTO-INSTALLAZIONE
# ========================================================

install_if_missing() {
    local cmd=$1; local pkg=$2
    if ! command -v "$cmd" &> /dev/null; then
        apt-get update -qq && apt-get install -y -qq "$pkg" < /dev/null
    fi
}

install_if_missing "mutt" "mutt"
install_if_missing "curl" "curl"
install_if_missing "sqlite3" "sqlite3"

# ========================================================
# 2. RACCOLTA DATI E GENERAZIONE HTML
# ========================================================

SSH_RAW=$(journalctl _SYSTEMD_UNIT=ssh.service | grep "Failed password")
SSH_OK=$(journalctl _SYSTEMD_UNIT=ssh.service | grep -c "Accepted password")
SSH_IPS=$(echo "$SSH_RAW" | sed -n 's/.*from \([^ ]*\) port.*/\1/p')

GUI_RAW=$(journalctl -u pvedaemon -u pveproxy | grep "authentication failure")
GUI_OK=$(journalctl -u pvedaemon -u pveproxy | grep -c "successful auth")
GUI_IPS=$(echo "$GUI_RAW" | sed -n 's/.*rhost=::ffff:\([^ ]*\) .*/\1/p')

ALL_IPS_TOTAL=$(echo -e "$SSH_IPS\n$GUI_IPS" | grep -v '^$' | sort)
TOTAL_ATTACKS=$(echo "$ALL_IPS_TOTAL" | wc -l)

{
echo "<html><head><meta charset='UTF-8'><style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #121212; color: #e0e0e0; line-height: 1.6; padding: 30px; }
    .container { max-width: 900px; margin: auto; background: #1e1e1e; padding: 20px; border-radius: 10px; box-shadow: 0 4px 15px rgba(0,0,0,0.5); }
    h1 { color: #00e5ff; border-bottom: 2px solid #00e5ff; padding-bottom: 10px; }
    h2 { color: #ffab40; margin-top: 30px; border-left: 4px solid #ffab40; padding-left: 10px; }
    .stat-grid { display: flex; flex-wrap: wrap; gap: 20px; margin: 20px 0; }
    .stat-card { background: #252525; padding: 15px; border-radius: 8px; flex: 1; min-width: 200px; text-align: center; border: 1px solid #333; }
    .stat-val { font-size: 24px; font-weight: bold; display: block; }
    .red { color: #ff5252; } .green { color: #69f0ae; } .orange { color: #ffd740; }
    table { width: 100%; border-collapse: collapse; margin-top: 15px; background: #252525; }
    th, td { text-align: left; padding: 12px; border-bottom: 1px solid #333; font-family: 'Courier New', monospace; }
    th { background-color: #333; color: #00e5ff; }
    .banned-label { background: #1b5e20; color: #fff; padding: 2px 8px; border-radius: 4px; font-size: 12px; }
    .autoband-label { background: #e65100; color: #fff; padding: 2px 8px; border-radius: 4px; font-size: 12px; }
</style></head><body>"

echo "<div class='container'><h1>🛡️ PVE Sentinel Security Audit</h1>"
echo "<p>Report generato il: <b>$(date)</b> su <b>$(hostname)</b></p>"

echo "<div class='stat-grid'>"
echo "<div class='stat-card'><span class='stat-val red'>$TOTAL_ATTACKS</span>Attacchi Respinti</div>"
echo "<div class='stat-card'><span class='stat-val green'>$SSH_OK</span>SSH Login OK</div>"
echo "<div class='stat-card'><span class='stat-val green'>$GUI_OK</span>GUI Login OK</div>"
echo "</div>"

echo "<h2>🌍 Analisi Geografica (Top 5)</h2><ul>"
echo "$ALL_IPS_TOTAL" | uniq -c | sort -nr | head -n 20 | awk '{print $2}' | while read ip; do
    curl -s --max-time 1.2 "http://ip-api.com/csv/$ip?fields=country"
done | sort | uniq -c | sort -nr | head -n 5 | while read c_count country; do
    echo "<li><b>$country</b>: $c_count IP unici coinvolti</li>"
done
echo "</ul>"

echo "<h2>📊 Top 10 Attaccanti e Azioni</h2>"
echo "<table><tr><th>Prove</th><th>IP Address</th><th>Nazione</th><th>Target</th><th>Azione</th></tr>"

ALL_BANNED=""
for jail in sshd proxmox; do ALL_BANNED+="$(fail2ban-client status $jail 2>/dev/null) "; done

echo "$ALL_IPS_TOTAL" | uniq -c | sort -nr | head -n 10 | while read count ip; do
    target="SSH"; echo "$GUI_IPS" | grep -q "$ip" && { echo "$SSH_IPS" | grep -q "$ip" && target="BOTH" || target="GUI"; }
    if [[ "$ALL_BANNED" =~ "$ip" ]]; then
        status="<span class='banned-label'>BANNED</span>"
    else
        jail_to_use="sshd"; [ "$target" != "SSH" ] && jail_to_use="proxmox"
        fail2ban-client set $jail_to_use banip $ip >/dev/null 2>&1
        status="<span class='autoband-label'>AUTO-BANNED</span>"
    fi
    country=$(curl -s --max-time 1.2 "http://ip-api.com/csv/$ip?fields=country")
    echo "<tr><td><b>$count</b></td><td>$ip</td><td>$country</td><td>$target</td><td>$status</td></tr>"
done
echo "</table>"

echo "<h2>🎯 Target Intelligence</h2>"
echo "<p><b>Utenze SSH più colpite:</b> <span class='orange'>$(echo "$SSH_RAW" | sed -n 's/.*for \(invalid user \)\?\([^ ]*\) from.*/\2/p' | sort | uniq -c | sort -nr | head -n 5 | xargs)</span></p>"
echo "<p><b>Utenze GUI più colpite:</b> <span class='orange'>$(echo "$GUI_RAW" | sed -n 's/.*user=\([^ ]*\).*/\1/p' | cut -d' ' -f1 | sort | uniq -c | sort -nr | head -n 5 | xargs)</span></p>"

echo "<h2>🛡️ Stato Difese Attive</h2><ul>"
for jail in sshd proxmox; do
    count_jail=$(fail2ban-client status $jail | sed -n '/Banned IP list:/ s/.*Banned IP list:[ \t]*//p' | wc -w)
    echo "<li>Jail <b>$jail</b>: <span class='green'>$count_jail</span> IP in blacklist</li>"
done
echo "</ul></div></body></html>"
} > "$REPORT_HTML"

# ========================================================
# 3. INVIO REPORT
# ========================================================

if [ -f "$REPORT_HTML" ]; then
    # Inviamo il file HTML come allegato. Mutt capirà il tipo di file.
    echo "In allegato il Security Audit a colori per Proxmox." | mutt -e "set content_type=text/html" -s "Sentinel Security Audit - $(hostname)" -a "$REPORT_HTML" -- "$EMAIL"
    echo -e "\e[32m[+] Report a colori inviato correttamente a $EMAIL\e[0m"
    # Opzionale: lascia il file HTML per consultazione locale o cancellalo
    # rm "$REPORT_HTML"
else
    echo -e "\e[31m[-] Errore nella generazione del report.\e[0m"
fi
