#!/bin/bash

IPFILE="/home/tcsidm/SCRIPTS/ckyc_db_VIP.txt"     #--------->keep IPs in a file and keep that location here

PORTS_VIP=(1531 1532 1533 1534 1536 1538 1539) ##ports used to connect to VIP
PORTS_SCAN=(1535)                              ## Ports used to connect to Scan IP.
SCAN_HOST="ckycvmdbscan.sbi"

echo -e "\e[33m------------------------------\e[0m"
date
echo -e "\e[33m------------------------------\e[0m"

echo -e "\e[33m Checking Connection via Virtual IPs\e[0m"

while IFS= read -r ip
do
[[ -z "$ip" ]] && continue
[[ "$ip" =~ ^# ]] && continue

for port in "${PORTS_VIP[@]}"
do

#run nc with 1-second timeout
output=$(nc -vz -w 1 "$ip" "$port" 2>&1)
time_taken=$(nc -vz -w 1 "$ip" "$port" 2>&1 |  awk '/received/ {print $(NF-1)" "$NF}')
rc=$?


if [[ $rc -eq 0 && -n "$time_taken" ]]; then
echo -e "\e[32m Connected $ip:$port in $time_taken\e[0m"
else
echo -e "\e[31m Connecting to $ip:$port --> Connection Timeout/refused\e[0m"
fi
done
echo ""
done < "$IPFILE"

## Scan ports for ckycvmdbscan.sbi

echo -e "\e[33m Checking Connection via Scan Name\e[0m"

for port in "${PORTS_SCAN[@]}"
do
echo -n "Port $port: "
output=$(nc -vz -w 1 "$SCAN_HOST" "$port" 2>&1)
echo -e "$output"
done

