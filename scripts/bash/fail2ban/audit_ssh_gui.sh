#!/bin/bash
# ==============================================================================
# PVE-SENTINEL: Audit & Protection Script (ULTRA-OPTIMIZED VERSION)
# ==============================================================================

# Configurazione destinatari multipli (separati da spazio)
# Ciascuno riceverà l'email singolarmente con il proprio indirizzo nel campo To:
EMAILS="indirizzo1@example.com indirizzo2@example.com"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_HISTORY="$SCRIPT_DIR/attack_history.json"

CURRENT_DATE_STR=$(date +"%d%m%Y-%H%M")
REPORT_HTML="/tmp/pve_sentinel_${CURRENT_DATE_STR}.html"

# ------------------------------------------------------------------------------
# VERIFICA DIPENDENZE PACCHETTI (DEBIAN / PROXMOX VE)
# ------------------------------------------------------------------------------

REQUIRED_PACKAGES=("python3" "geoip-bin" "mutt" "fail2ban" "postfix")
MISSING_PACKAGES=()

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
    echo -e "\e[31m[-] Errore: Pacchetti mancanti rilevati sul sistema:\e[0m" >&2
    for pkg in "${MISSING_PACKAGES[@]}"; do
        echo -e "    - $pkg" >&2
    done
    echo -e "\e[33m[!] Esegui il seguente comando per installarli:\e[0m" >&2
    echo -e "    apt update && apt install -y ${MISSING_PACKAGES[*]}\n" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 1. ELABORAZIONE INCREMENTALE OTTIMIZZATA (CACHE GEOIP + JSON MEMORY)
# ------------------------------------------------------------------------------
PYTHON_PROCESSOR=$(python3 -c '
import json, os, subprocess, re
from datetime import datetime, timedelta

json_path = "'"$JSON_HISTORY"'"
data = {"last_timestamp": "", "daily": {}, "ips": {}, "ssh_ok": 0, "gui_ok": 0}

if os.path.exists(json_path):
    try:
        with open(json_path, "r") as f:
            data = json.load(f)
    except:
        pass

last_ts = data.get("last_timestamp", "")
now = datetime.now()
now_str = now.strftime("%Y-%m-%d %H:%M:%S")

since_arg = ["--since", last_ts] if last_ts else []

# Estrazione log incrementale SSH
ssh_cmd = ["journalctl", "_SYSTEMD_UNIT=ssh.service", "--no-pager", "--output=short-iso"] + since_arg
ssh_res = subprocess.run(ssh_cmd, capture_output=True, text=True)

# Estrazione log incrementale GUI
gui_cmd = ["journalctl", "-u", "pvedaemon", "-u", "pveproxy", "--no-pager", "--output=short-iso"] + since_arg
gui_res = subprocess.run(gui_cmd, capture_output=True, text=True)

ssh_ok_new = ssh_res.stdout.count("Accepted")
gui_ok_new = gui_res.stdout.count("successful auth")
data["ssh_ok"] = data.get("ssh_ok", 0) + ssh_ok_new
data["gui_ok"] = data.get("gui_ok", 0) + gui_ok_new

ssh_lines = ssh_res.stdout.split("\n")
for line in ssh_lines:
    if "Failed password" in line:
        date_part = line[:10]
        if not re.match(r"^\d{4}-\d{2}-\d{2}$", date_part):
            date_part = now.strftime("%Y-%m-%d")
        
        match = re.search(r"from\s+([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})", line)
        if match:
            ip = match.group(1)
            if date_part not in data["daily"]:
                data["daily"][date_part] = {"ssh": 0, "gui": 0}
            data["daily"][date_part]["ssh"] += 1
            
            if ip not in data["ips"]:
                data["ips"][ip] = {"count": 0, "ssh": 0, "gui": 0, "country": "Unknown"}
            data["ips"][ip]["count"] += 1
            data["ips"][ip]["ssh"] += 1

gui_lines = gui_res.stdout.split("\n")
for line in gui_lines:
    if "authentication failure" in line:
        date_part = line[:10]
        if not re.match(r"^\d{4}-\d{2}-\d{2}$", date_part):
            date_part = now.strftime("%Y-%m-%d")
            
        ip_match = re.search(r"([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})", line)
        if ip_match:
            ip = ip_match.group(1)
            if date_part not in data["daily"]:
                data["daily"][date_part] = {"ssh": 0, "gui": 0}
            data["daily"][date_part]["gui"] += 1
            
            if ip not in data["ips"]:
                data["ips"][ip] = {"count": 0, "ssh": 0, "gui": 0, "country": "Unknown"}
            data["ips"][ip]["count"] += 1
            data["ips"][ip]["gui"] += 1

# Ottimizzazione GeoIP: esegue la risoluzione solo per i top 10 attaccanti non ancora censiti nel JSON
sorted_ips_temp = sorted(data["ips"].items(), key=lambda x: x[1]["count"], reverse=True)
for ip, info in sorted_ips_temp[:20]:
    if info["country"] == "Unknown":
        geo = subprocess.run(["geoiplookup", ip], capture_output=True, text=True)
        if geo.returncode == 0 and geo.stdout:
            parts = geo.stdout.split(":")
            if len(parts) > 1 and "IP Address not found" not in parts[1]:
                country_name = parts[1].strip().split(", ")[-1]
                data["ips"][ip]["country"] = country_name

data["last_timestamp"] = now_str

with open(json_path, "w") as f:
    json.dump(data, f, indent=2)

total_fails = sum(info["count"] for info in data["ips"].values())
sorted_ips = sorted(data["ips"].items(), key=lambda x: x[1]["count"], reverse=True)
top_10 = sorted_ips[:10]

countries = {}
for ip, info in data["ips"].items():
    c = info["country"]
    countries[c] = countries.get(c, 0) + 1
sorted_countries = sorted(countries.items(), key=lambda x: x[1], reverse=True)[:5]

if data["daily"]:
    all_dates = sorted(data["daily"].keys())
    start_d = datetime.strptime(all_dates[0], "%Y-%m-%d").date()
    end_d = now.date()
    curr = start_d
    labels, d_ssh, d_gui = [], [], []
    while curr <= end_d:
        ds = curr.strftime("%Y-%m-%d")
        labels.append(curr.strftime("%d/%m"))
        d_ssh.append(data["daily"].get(ds, {}).get("ssh", 0))
        d_gui.append(data["daily"].get(ds, {}).get("gui", 0))
        curr += timedelta(days=1)
else:
    labels, d_ssh, d_gui = [], [], []

print(json.dumps({
    "total_fails": total_fails,
    "ssh_ok": data["ssh_ok"],
    "gui_ok": data["gui_ok"],
    "top_10": top_10,
    "top_countries": sorted_countries,
    "first_date": sorted(data["daily"].keys())[0] if data["daily"] else now.strftime("%Y-%m-%d"),
    "labels": labels,
    "data_ssh": d_ssh,
    "data_gui": d_gui
}))
')

TOTAL_FAILS=$(echo "$PYTHON_PROCESSOR" | python3 -c "import sys, json; print(json.load(sys.stdin)['total_fails'])")
SSH_OK=$(echo "$PYTHON_PROCESSOR" | python3 -c "import sys, json; print(json.load(sys.stdin)['ssh_ok'])")
GUI_OK=$(echo "$PYTHON_PROCESSOR" | python3 -c "import sys, json; print(json.load(sys.stdin)['gui_ok'])")
FIRST_DATE=$(echo "$PYTHON_PROCESSOR" | python3 -c "import sys, json; print(json.load(sys.stdin)['first_date'])")
LABELS=$(echo "$PYTHON_PROCESSOR" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin)['labels']))")
DATA_SSH=$(echo "$PYTHON_PROCESSOR" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin)['data_ssh']))")
DATA_GUI=$(echo "$PYTHON_PROCESSOR" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin)['data_gui']))")

# ------------------------------------------------------------------------------
# 2. GENERAZIONE STRUTTURA HTML BASE
# ------------------------------------------------------------------------------
cat <<EOF > "$REPORT_HTML"
<!DOCTYPE html>
<html lang="it">
<head>
<meta charset="UTF-8">
<style>
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
    .chart-box { width: 100%; box-sizing: border-box; background: #252525; padding: 15px; border-radius: 8px; border: 1px solid #333; margin-top: 15px; }
</style>
</head>
<body>
EOF

HOSTNAME=$(hostname)
DATE_STR=$(date +"%a %b %d %r %Z %Y")

cat <<EOF >> "$REPORT_HTML"
<div class='container'>
  <h1>🛡️ PVE Sentinel Security Audit</h1>
  <p>Report generato il: <b>$DATE_STR</b> su <b>$HOSTNAME</b></p>
<div class='stat-grid'>
  <div class='stat-card'><span class='stat-val red'>$TOTAL_FAILS</span>Attacchi Respinti</div>
  <div class='stat-card'><span class='stat-val green'>$SSH_OK</span>SSH Login OK</div>
  <div class='stat-card'><span class='stat-val green'>$GUI_OK</span>GUI Login OK</div>
</div>
<h2>🌍 Analisi Geografica (Top 5)</h2>
<ul>
EOF

echo "$PYTHON_PROCESSOR" | python3 -c '
import sys, json
d = json.load(sys.stdin)
for country, count in d["top_countries"]:
    print(f"<li><b>{country}</b>: {count} IP unici coinvolti</li>")
' >> "$REPORT_HTML"

echo "</ul>" >> "$REPORT_HTML"

# ------------------------------------------------------------------------------
# 3. TOP 10 ATTACCANTI E STATO BANS
# ------------------------------------------------------------------------------
echo "<h2>📊 Top 10 Attaccanti e Azioni</h2>" >> "$REPORT_HTML"
echo "<table><tr><th>Prove</th><th>IP Address</th><th>Nazione</th><th>Target</th><th>Azione</th></tr>" >> "$REPORT_HTML"

ALL_BANNED=""
for jail in sshd proxmox; do ALL_BANNED+="$(fail2ban-client status $jail 2>/dev/null) "; done

echo "$PYTHON_PROCESSOR" | python3 -c '
import sys, json
d = json.load(sys.stdin)
for ip, info in d["top_10"]:
    count = info["count"]
    country = info["country"]
    target = "GUI" if info["gui"] > info["ssh"] else "SSH"
    print(f"{count}|{ip}|{country}|{target}")
' | while IFS='|' read -r count ip country target; do
    [ -z "$ip" ] && continue
    
    if [[ "$ALL_BANNED" =~ "$ip" ]]; then
        status="<span class='banned-label'>BANNED</span>"
    else
        jail_to_use="sshd"
        [ "$target" != "SSH" ] && jail_to_use="proxmox"
        fail2ban-client set $jail_to_use banip "$ip" >/dev/null 2>&1
        status="<span class='autoband-label'>AUTO-BANNED</span>"
    fi
    
    echo "<tr><td><b>$count</b></td><td>$ip</td><td>$country</td><td>$target</td><td>$status</td></tr>" >> "$REPORT_HTML"
done

echo "</table>" >> "$REPORT_HTML"

# ------------------------------------------------------------------------------
# 4. TARGET INTELLIGENCE
# ------------------------------------------------------------------------------
echo "<h2>🎯 Target Intelligence</h2>" >> "$REPORT_HTML"

SSH_RAW=$(journalctl _SYSTEMD_UNIT=ssh.service --no-pager 2>/dev/null)
GUI_RAW=$(journalctl -u pvedaemon -u pveproxy --no-pager 2>/dev/null)

top_ssh_users=$(grep "Failed password" <<< "$SSH_RAW" | sed -n 's/.*for \(invalid user \)\?\([^ ]*\) from.*/\2/p' | sort 2>/dev/null | uniq -c | sort -nr 2>/dev/null | head -n 5 | xargs)
top_gui_users=$(grep "authentication failure" <<< "$GUI_RAW" | sed -n 's/.*user=\([^ ]*\).*/\1/p' | cut -d' ' -f1 | sort 2>/dev/null | uniq -c | sort -nr 2>/dev/null | head -n 5 | xargs)

echo "<p><b>Utenze SSH più colpite:</b> <span class='orange'>${top_ssh_users:-Nessuna}</span></p>" >> "$REPORT_HTML"
echo "<p><b>Utenze GUI più colpite:</b> <span class='orange'>${top_gui_users:-Nessuna}</span></p>" >> "$REPORT_HTML"

echo "<h2>🛡️ Stato Difese Attive</h2><ul>" >> "$REPORT_HTML"
for jail in sshd proxmox; do
    count_jail=$(fail2ban-client status $jail 2>/dev/null | sed -n '/Banned IP list:/ s/.*Banned IP list:[ \t]*//p' | wc -w)
    echo "<li>Jail <b>$jail</b>: <span class='green'>$count_jail</span> IP in blacklist</li>" >> "$REPORT_HTML"
done
echo "</ul>" >> "$REPORT_HTML"

# ------------------------------------------------------------------------------
# 5. ESTRAZIONE GRAFICO CON DATI MEMORIZZATI
# ------------------------------------------------------------------------------
cat <<EOF >> "$REPORT_HTML"
<h2>📈 Distribuzione Temporale (Storico Completo: da $FIRST_DATE a oggi)</h2>
<div class="chart-box">
  <canvas id="attackTimelineChart" height="120"></canvas>
</div>

</div></body>
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<script>
document.addEventListener("DOMContentLoaded", function() {
    const ctx = document.getElementById('attackTimelineChart').getContext('2d');
    new Chart(ctx, {
        type: 'line',
        data: {
            labels: $LABELS,
            datasets: [
                {
                    label: 'Attacchi SSH',
                    data: $DATA_SSH,
                    borderColor: '#ff5252',
                    backgroundColor: 'rgba(255, 82, 82, 0.1)',
                    borderWidth: 2,
                    pointRadius: 2,
                    tension: 0.2,
                    fill: true
                },
                {
                    label: 'Attacchi Web GUI',
                    data: $DATA_GUI,
                    borderColor: '#ffd740',
                    backgroundColor: 'rgba(255, 215, 64, 0.1)',
                    borderWidth: 2,
                    pointRadius: 2,
                    tension: 0.2,
                    fill: true
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: true,
            plugins: {
                legend: { labels: { color: '#e0e0e0', font: { family: 'Segoe UI', size: 12 } } }
            },
            scales: {
                x: { ticks: { color: '#a6adc8', maxRotation: 45, maxTicksLimit: 12 }, grid: { color: '#333' } },
                y: { beginAtZero: true, ticks: { color: '#a6adc8', precision: 0 }, grid: { color: '#333' } }
            }
        }
    });
});
</script>
</html>
EOF

# ------------------------------------------------------------------------------
# 6. INVIO E-MAIL MULTIPLE (SINGOLE IN "TO:") CON ALLEGATO RINOMINATO
# ------------------------------------------------------------------------------
if [ -f "$REPORT_HTML" ]; then
    for DEST in $EMAILS; do
        echo "In allegato il Security Audit a colori per Proxmox." | mutt -e "set content_type=text/html" -s "Sentinel Security Audit - $(hostname)" -a "$REPORT_HTML" -- "$DEST"
    done
    echo -e "\e[32m[+] Report inviato correttamente a tutti i destinatari (Allegato: pve_sentinel_${CURRENT_DATE_STR}.html)\e[0m"
fi

