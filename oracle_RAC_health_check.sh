#!/bin/bash

# ===== USER INPUT =====
USER="oracle"


SERVERS=(
10.191.213.214
10.191.213.215
10.191.213.216
10.191.212.202
)

RED="\e[31m"
GREEN="\e[32m"
RESET="\e[0m"

RED="\e[31m"
GREEN="\e[32m"
RESET="\e[0m"

echo "======================================================================================================================================"
echo -e "\e[32mServer Health Check Report | Generated on: $(date '+%Y-%m-%d %H:%M:%S')\e[0m"
echo "======================================================================================================================================"
echo

# ===== HEADER =====
printf "%-25s" "Parameter"
for srv in "${SERVERS[@]}"; do
    printf "%-30s" "$srv"
done
echo
echo "======================================================================================================================================"

# ===== FUNCTION TO RUN REMOTE COMMAND =====
run_cmd() {
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$USER@$1" "$2" 2>/dev/null
}



# =====  Current CPU USAGE =====
printf "%-25s" "Current CPU (%)"
for srv in "${SERVERS[@]}"; do
    cpu=$(top -b -n2 -d1 | grep "Cpu(s)" | tail -n1 | awk -F'id,' -v prefix="CPU Usage: " '{ split($1, vs, ","); printf("%d", 100 - vs[length(vs)]) }')
    if [[ "$cpu" -gt 85 ]]; then
         printf "%b%-30s%b" "$RED" "$cpu" "${RESET}"
    else
        printf "%b%-30s%b" "$GREEN" "$cpu" "${RESET}"
    fi
done
echo

# ===== Avg. CPU USAGE (30 Min) =====
printf "%-25s" "Avg CPU (30 min)"
for srv in "${SERVERS[@]}"; do
    cpu30=$(run_cmd "$srv" "sar -u -s \$(date -d '30 minutes ago' +%H:%M:%S) | awk '/Average:/ {printf \"%d\", 100-\$8}'")
    if [[ "$cpu30" -gt 85 ]]; then
         printf "%b%-30s%b" "$RED" "$cpu30" "${RESET}"
    else
        printf "%b%-30s%b" "$GREEN" "$cpu30" "${RESET}"
    fi
done
echo

# ===== Avg. CPU USAGE (2 hrs) =====
printf "%-25s" "Avg CPU (2 hrs)"
for srv in "${SERVERS[@]}"; do
    cpu2h=$(run_cmd "$srv" "sar -u -s \$(date -d '2 hours ago' +%H:%M:%S) | awk '/Average:/ {printf \"%d\", 100-\$8}'")
    if [[ "$cpu2h" -gt 85 ]]; then
         printf "%b%-30s%b" "$RED" "$cpu2h" "${RESET}"
    else
        printf "%b%-30s%b" "$GREEN" "$cpu2h" "${RESET}"
    fi
done
echo

# =====  CURRENT MEMORY  =====
printf "%-25s" "Current Memory  (%)"
for srv in "${SERVERS[@]}"; do
    mem=$(run_cmd "$srv" "free | awk '/Mem:/ {printf \"%d\", \$3/\$2*100}'")
    if [[ "$mem" -gt 85 ]]; then
         printf "%b%-30s%b" "$RED" "$mem" "${RESET}"
    else
        printf "%b%-30s%b" "$GREEN" "$mem" "${RESET}"
    fi
done
echo

# =====  Avg. MEMORY USAGE (30 Min)  =====
printf "%-25s" "Avg Avail Mem (30 min)"
for srv in "${SERVERS[@]}"; do
    avail30=$(run_cmd "$srv" "sar -r -s \$(date -d '30 minutes ago' +%H:%M:%S) | awk '/^Average:/ {printf \"%.2f%%\", (\$3 / (\$2 + \$4)) * 100}'")
	avail_30=${avail30%.*}
	used30=$(( 100 - avail_30 ))
    if [[ "$used30" -gt 85 ]]; then
         printf "%b%-30s%b" "$RED" "$used30" "${RESET}"
    else
        printf "%b%-30s%b" "$GREEN" "$used30" "${RESET}"
    fi
done
echo

# =====  Avg. MEMORY USAGE (2 hrs)  =====
printf "%-25s" "Avg Avail Mem (2 hrs)"
for srv in "${SERVERS[@]}"; do
    avail2h=$(run_cmd "$srv" "sar -r -s \$(date -d '2 hours ago' +%H:%M:%S) | awk '/^Average:/ {printf \"%.2f%%\", (\$3 / (\$2 + \$4)) * 100}'")
	avail_2h=${avail2h%.*}
	used2h=$(( 100 - avail_2h ))
    if [[ "$used2h" -gt 85 ]]; then
         printf "%b%-30s%b" "$RED" "$used2h" "${RESET}"
    else
        printf "%b%-30s%b" "$GREEN" "$used2h" "${RESET}"
    fi
done
echo

# =====  LOAD AVERAGE =====
printf "%-25s" "Load Avg (1m, 5m, 15m)"

for srv in "${SERVERS[@]}"; do

    load=$(run_cmd "$srv" "awk '{print \$1, \$2, \$3}' /proc/loadavg")
    cores=$(run_cmd "$srv" "nproc")

    if [[ -z "$load" || -z "$cores" ]]; then
        printf "%-30s" "NA"
        continue
    fi

    l1=$(echo "$load" | awk '{print $1}')
    l5=$(echo "$load" | awk '{print $2}')
    l15=$(echo "$load" | awk '{print $3}')

    # Compare 5m or 15m load with CPU cores
    overload=$(awk -v l5="$l5" -v l15="$l15" -v c="$cores" \
        'BEGIN { if (l5>c || l15>c) print 1; else print 0 }')

    if [[ "$overload" -eq 1 ]]; then
        printf "%b%-30s%b" "$RED" "$l1, $l5, $l15" "$RESET"
    else
        printf "%b%-30s%b" "$GREEN" "$l1, $l5, $l15" "$RESET"
    fi
done
echo

# FILESYSTEM > 85%

printf "%-25s" "FS >85% Usage"

for srv in "${SERVERS[@]}"; do

    fs=$(run_cmd "$srv" "
        df -P | awk '
        NR>1 {
            for (i=1; i<=NF; i++) {
                if (\$i ~ /^[0-9]+%$/) {
                    pct=\$i
                    gsub(/%/, \"\", pct)
                    mnt=\$(i+1)
                    if (pct+0 > 85)
                        print mnt \" (\" pct \"%)\"
                }
            }
        }'
    " | tr '\n' ',' | sed 's/,$//')

    if [[ -n "$fs" ]]; then
        printf "%b%-30s%b" "$RED" "$fs" "$RESET"
    else
        printf "%b%-30s%b" "$GREEN" "None" "$RESET"
    fi

done

echo

# NTP STATUS

printf "%-25s" "NTP Sync"
for srv in "${SERVERS[@]}"; do

    ntp=$(run_cmd "$srv" "timedatectl show -p NTPSynchronized --value")

    if [[ "$ntp" == "yes" ]]; then
        printf "%b%-30s%b" "$GREEN" "Yes" "$RESET"
    elif [[ "$ntp" == "no" ]]; then
        printf "%b%-30s%b" "$RED" "No" "$RESET"
    else
        printf "%-30s" "NA"
    fi
done
echo

# ===== CRITICAL SERVICES =====
printf "%-25s" "Critical Services"

for srv in "${SERVERS[@]}"; do
    svc=$(run_cmd "$srv" "
        for s in auditd rsyslog chronyd crond sshd commvault; do
            systemctl is-active \$s &>/dev/null || echo \$s
        done
    ")

    if [[ -z "$svc" ]]; then
        printf "%b%-30s%b" "$GREEN" "All Running" "${RESET}"
    else
        printf "%b%-30s%b" "$RED" "Not Running" "${RESET}"
    fi
done

echo

# =====  OS Watcher =====
printf "%-25s" "OS Watcher"
for srv in "${SERVERS[@]}"; do
    osw=$(run_cmd "$srv" "pgrep -fa 'oswbb|OSWatcher' | wc -l")
    if [[ "$osw" -gt 0 ]]; then
         printf "%b%-30s%b" "$GREEN" "Running" "${RESET}"
    else
        printf "%b%-30s%b" "$RED" "Not Running" "${RESET}"
    fi
done
echo

# =====  UPTIME =====
printf "%-25s" "Uptime"
for srv in "${SERVERS[@]}"; do
    up=$(run_cmd "$srv" "uptime -p | sed 's/, [0-9]* minute.*//'")
    printf "%-30s" "${up:-NA}"
done
echo

# ===== JOURNAL ERROR COUNT =====
printf "%-25s" "Journal Errors (2h)"
for srv in "${SERVERS[@]}"; do
    err=$(run_cmd "$srv" "sudo journalctl --since '2 hours ago' -p err --no-pager | grep -v '^--' | wc -l")
	if [[ "$err" -gt 0 ]]; then
         printf "%b%-30s%b" "$RED" "$err" "${RESET}"
    else
        printf "%b%-30s%b" "$GREEN" "$err" "${RESET}"
    fi
    #printf "%-30s" "${err:-0}"
done
echo

echo "================================================================================================================="
echo -e "\e[33mKindly  check the Errors Manually using "journalctl --since "'2 hours ago'" -p err --no-pager" (if found) \e[0m"
echo "================================================================================================================="
echo
