#!/bin/bash
# Script to log top 20 CPU/Memory consuming processes if utilization > 75%

LOGFILE="/var/log/every_minute/high_usage_$(date '+%Y-%m-%d').log"
mkdir -p /var/log/every_minute
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')


# Get overall CPU and memory usage
CPU_USAGE=$(top -bn1 | awk '/Cpu\(s\)/ {print 100 - $8}')  #### to fetch current CPU usage
MEM_USAGE=$(free | awk '/Mem:/ {print $3/$2 * 100.0}')      #### to fetch current Memory usage
LOAD_1_MIN=$(awk '{print $1}' /proc/loadavg)
LOAD_1_MIN_INT=${LOAD_1_MIN%.*}
CPU_CORES=$(nproc)

CPU_INT=${CPU_USAGE%.*}  #### Conversion into Integer
MEM_INT=${MEM_USAGE%.*}

# If either CPU or memory > 70%
if [ $CPU_INT -ge 70 ] || [ $MEM_INT -ge 70 ] || [ $LOAD_1_MIN_INT -ge $CPU_CORES ]; then
    echo "==============================" >> "$LOGFILE"
    echo "High Resource Usage Detected at $TIMESTAMP" >> "$LOGFILE"
    echo "CPU Usage: ${CPU_USAGE}% | Memory Usage: ${MEM_USAGE}%  | Load_Average: ${LOAD_1_MIN_INT}" >> "$LOGFILE"
    echo "----------------------------------------------" >> "$LOGFILE"
    echo "Top 20 Processes by CPU:" >> "$LOGFILE"
    ps -eo user,pid,ppid,cmd,%mem,%cpu,args --sort=-%cpu | head -n 21 >> "$LOGFILE"
    echo "----------------------------------------------" >> "$LOGFILE"
    echo "Top 20 Processes by Memory:" >> "$LOGFILE"
    ps -eo user,pid,ppid,cmd,%mem,%cpu,args --sort=-%mem | head -n 21 >> "$LOGFILE"
    echo "==============================" >> "$LOGFILE"
    echo "" >> "$LOGFILE"
	
D_state=$(ps -eo state | grep -c D)
echo -e "\e[33m D-State process: $D_state\e[0m" >> "$LOGFILE"

if [ $D_state -ge 0 ]; then
echo -e "\e[33m ================D-State Processes===============\e[0m" >> "$LOGFILE"
echo "pid  state  user     cmd                          mem  cpu" >> "$LOGFILE"
ps -eo pid,state,user,cmd,%mem,%cpu | awk '$2=="D"' >> "$LOGFILE"
fi

ps -eo pid,state,user,cmd | awk '$2=="D"'
iowait=$(sar -u 1 4| grep -E "^Average" | awk '{print $6}')
echo " " >> "$LOGFILE"
echo -e "\e[33m Current IOwait: $iowait\e[0m" >> "$LOGFILE"
echo " " >> "$LOGFILE"
Run_Q=$(vmstat 1 3 | awk '{print $1}' | tail -1)
echo -e "\e[33m Current RUNQ: $Run_Q\e[0m" >> "$LOGFILE"

fi

