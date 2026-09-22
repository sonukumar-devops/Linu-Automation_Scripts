#!/bin/bash

###############################################################################
# monitor_system.sh
#
# Purpose:
#- Collect important system diagnostics (CPU, Memory, Disk, Network, IPC, PSI)
#- Work in two modes:
#manual-> always run diagnostics
#auto-> run only when CPU/MEM crosses threshold (for cron jobs)
#- Produce a readable summary of detected issues at the end
#
# Usage:
#./monitor_system.sh manual
#./monitor_system.sh auto
###############################################################################
#sh start.sh manual >/dev/null 2>&1
# ----------------------------
# CONFIGURATION
# ----------------------------
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

MODE=${1:-manual} # Default mode = manual
THRESHOLD=85 # CPU/MEM threshold for auto mode (in %)

LOG_DIR="/var/log/sys_monitor"
TOP_LOG_DIR="/var/log/top_monitor"
mkdir -p $LOG_DIR
mkdir -p $TOP_LOG_DIR

TIMESTAMP=$(date +%F_%T) # Timestamp for log file name
LOGFILE="$LOG_DIR/monitor_$TIMESTAMP.log" # Full log path
TOP_LOGFILE="$TOP_LOG_DIR/top_snapshot_$TIMESTAMP.log"


ISSUES="" # Summary text will be stored here

TRIGGER_CONDITION=0
TS_FILE="/tmp/last_run_ts"
COOLDOWN=300

#################SOS Report Section##############################

SOS_TS_FILE="/var/tmp/.last_sos_time"

CURRENT_TIME=$(date +%s)
RUN_SOS=0

if [[ -f "$SOS_TS_FILE" ]]; then
    LAST_RUN=$(cat "$SOS_TS_FILE")
    DIFF=$(( CURRENT_TIME - LAST_RUN ))

    if (( DIFF > 3600 )); then   # 3600 sec = 60 min
        RUN_SOS=1
    else
        RUN_SOS=0
    fi
else
    RUN_SOS=1   # first time run
fi

###################################################################

# ----------------------------
# HELPER FUNCTIONS
# ----------------------------

# Add a single issue to the summary
add_issue() {
ISSUES+=" - $1\n"
}

# Print section header cleanly (for log + screen)
print_section() {
echo -e "\n\e[33m==================== $1 ====================\n\e[0m" | tee -a "$LOGFILE"
}

#keep logs for just 7 days

LOG_DIR="/var/log/sys_monitor"
find "$LOG_DIR" -type f -name "*.log" -mtime +7 -exec rm -f {} \;
find "$TOP_LOG_DIR" -type f -name "*.log" -mtime +7 -exec rm -f {} \;
find /var/tmp -type f -name "sosreport-*" -mtime +7 -delete
###############################################################################
# AUTO MODE CHECK
###############################################################################

check_auto_mode() {

CPU=$(LC_ALL=C top -bn1 | awk -F',' '/Cpu\(s\)/ {
    gsub(/[^0-9.]/,"",$4);
    printf "%d\n", 100 - $4
}')

CPU_INT=${CPU%.*}

MEM=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')

LOAD_1_MIN=$(awk '{print $1}' /proc/loadavg)
LOAD_1_MIN_INT=${LOAD_1_MIN%.*}
CPU_CORES=$(nproc)

#######################Check block for logs error in Journalctl and /var/log/messages########################

LOG_ERR_FLAG=0

# ---- journalctl check (last 2 minutes, real errors only) ----
JCTL_ERR=$(journalctl --since "2 minutes ago" -p err..alert --no-pager 2>/dev/null \
    | grep -Ev '^(--|$)')

if [[ -n "$JCTL_ERR" ]]; then
    LOG_ERR_FLAG=1
    
fi

# Check errors in /var/log/messages (last 2 minutes)
if [ -f /var/log/messages ]; then
    MSG_ERR=$(awk -v d="$(date --date='2 minutes ago' '+%b %e %H:%M')" '
        $0 >= d && tolower($0) ~ /(error|fail|failed|timeout|reset|i\/o error|blk_update_request|hung task|scsi)/
    ' /var/log/messages)

    if [[ -n "$MSG_ERR" ]]; then
        LOG_ERR_FLAG=1
    fi
fi

########################### Check block D-state Process #####################################

DSTATE_COUNT=$(ps -eo state --no-headers | awk '$1 ~ /^D/ {count++} END {print count+0}')
D_STATE_CULPRIT_PIDS=$(ps -eo pid,state --no-headers | awk '
    $2 ~ /D/ { print $1 }
' | sort -u)

##############################################################################

if [[ "$MODE" == "auto" ]]; then
if (( CPU_INT < THRESHOLD && MEM < THRESHOLD && LOAD_1_MIN_INT <= CPU_CORES  )); then

exit 0
fi

TRIGGER_CONDITION=1

if (( TRIGGER_CONDITION == 0 )); then
	exit 0
	fi

    NOW=$(date +%s)

    if [ -f "$TS_FILE" ]; then
        LASTRUN=$(cat "$TS_FILE")

        if (( NOW - LASTRUN < COOLDOWN )); then
            exit 0
        fi
    fi

    # Update timestamp ONLY when triggered
    echo "$NOW" > "$TS_FILE"


touch "$LOGFILE"
touch "$LOGFILE"
touch "$TOP_LOGFILE"

##########################SOS Trigger section###################################
if (( RUN_SOS == 1 )); then
    echo "[INFO] Triggering sosreport (cooldown passed)..." | tee -a "$LOGFILE"

    sos report --batch --tmp-dir /var/tmp > /dev/null 2>&1 < /dev/null & disown

    # Update timestamp
    echo "$CURRENT_TIME" > "$SOS_TS_FILE"
else
    echo "[INFO] Skipping sosreport (last run within 30 minutes)" | tee -a "$LOGFILE"
fi
#################################################################################

#########################Reason for Auto trigger#################################



echo "Trigger Reasons:" | tee -a "$LOGFILE"

# CPU
if (( CPU_INT >= THRESHOLD )); then
    echo "  • High CPU Usage  : ${CPU_INT}% (Threshold: ${THRESHOLD}%)" | tee -a "$LOGFILE"
fi

#MEM
if (( MEM >= THRESHOLD )); then
    echo "  • High Memory Usage : ${MEM}% (Threshold: ${THRESHOLD}%)" | tee -a "$LOGFILE"
fi

#LOAD
if (( LOAD_1_MIN_INT > CPU_CORES )); then
    echo "  • High Load Average : ${LOAD_1_MIN_INT} (CPU Cores: ${CPU_CORES})" | tee -a "$LOGFILE"
fi

# D-state
if (( DSTATE_COUNT > 0 )); then
	add_issue "D-state process was detected ($DSTATE_COUNT blocked tasks)"
    echo "  • Blocked (D-state) Tasks Detected : ${DSTATE_COUNT}" | tee -a "$LOGFILE"
	echo "" | tee -a "$LOGFILE"

print_section "......D-State Processes......."

printf "%-8s %-7s %-4s %-4s %-4s %s\n" \
"PID" "USER" "%CPU" "%MEM" "STAT" "COMMAND" | tee -a "$LOGFILE"

for pid in $D_STATE_CULPRIT_PIDS; do
    ps -p "$pid" -o pid,user,%cpu,%mem,stat,args --no-headers
done | tee -a "$LOGFILE"
	
fi

# Journal / log errors
if (( LOG_ERR_FLAG > 0 )); then
    echo "  • Kernel/System Errors Detected in Logs" | tee -a "$LOGFILE"
fi

echo "" | tee -a "$LOGFILE"
echo -e "\n\e[33mCollecting diagnostics\e[0m" | tee -a "$LOGFILE"
fi
}



###############################################################################
# DATA COLLECTION FUNCTIONS
###############################################################################

# ----------------------------
# 1) CPU ANALYSIS
# ----------------------------
Data_Collection() {


###########################################################
# TOP 50 CPU CONSUMING PROCESSES (FULL COMMAND)
###########################################################
echo "" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
#print_section "Top command snapshot"
        TOP_SNAP=$(top -c -b -n 1)
        echo "$TOP_SNAP" | tee -a "$TOP_LOGFILE"
echo -e "\e[33m Report Generated on : $(date '+%Y-%m-%d %H:%M:%S %Z' )\e[0m"| tee -a "$LOGFILE"

print_section "Top 50 CPU Consuming Processes (FULL ARGS)"
echo "" | tee -a "$LOGFILE"
TOP_CPU_PIDS=$(echo "$TOP_SNAP" | awk '$1 ~ /^[0-9]+$/ {print $1, $9}' \
 | sort -k2 -nr | head -50 | awk '{print $1}')

printf "%-8s %-7s %-6s %-6s %s\n" \
"PID" "USER" "%CPU" "%MEM" "COMMAND" | tee -a "$LOGFILE"

for pid in $TOP_CPU_PIDS; do
    ps -p "$pid" -o pid,user,%cpu,%mem,args --no-headers
done | tee -a "$LOGFILE"

    print_section "CPU STATISTICS (sar -u)"
    sar -u 1 1 >> "$LOGFILE" 2>/dev/null

        print_section "VMSTAT STATISTICS (vmstat 1 2)"
        vmstat 1 2 >> "$LOGFILE" 2>/dev/null

        echo "" | tee -a "$LOGFILE"

    ###########################################################
    # TOP 5 USERS BY CPU (WITH PROCESS + THREAD COUNT)
    ###########################################################

echo "" | tee -a "$LOGFILE"
print_section "Process Count Per User (from top snapshot)"

# Header
printf "%-20s %-15s %-15s %-15s\n" "USER" "PROCESS_COUNT" "CPU(%)" "MEM(%)" | tee -a "$LOGFILE"

# Data
awk '
/^ *PID / {
    for (i=1; i<=NF; i++) {
        if ($i=="USER") user_col=i
        if ($i ~ /%?CPU/) cpu_col=i
		if ($i ~ /%?MEM/) mem_col=i
    }
    next
}

user_col && cpu_col && NF {
    user = $user_col
    cpu  = $cpu_col
	mem  = $mem_col

    count[user]++
    cpu_sum[user] += cpu
	mem_sum[user] += mem
}

END {
    for (u in count) {
        printf "%-20s %-15d %-15.2f %-15.2f\n", u, count[u], cpu_sum[u], mem_sum[u]
    }
}
' "$TOP_LOGFILE" | sort -k3 -nr | tee -a "$LOGFILE"
	
	

    echo "" | tee -a "$LOGFILE"
    #print_section "---- Top 5 Users by CPU util ----"
    #printf "%-15s %-10s %-15s %-15s\n" "USER" "CPU(%)" "PROC_COUNT" "THREAD_COUNT" | tee -a "$LOGFILE"
    #printf "%-15s %-10s %-15s %-15s\n" "----" "------" "----------" "-------------" | tee -a "$LOGFILE"
	#
    #ps -eo user,pcpu --no-headers | \
    #awk '{ cpu[$1]+=$2 } END { for (u in cpu) print cpu[u], u }' | \
    #sort -nr | head -5 | \
    #while read cpu user; do
    #    proc_count=$(ps -u "$user" --no-headers | wc -l)
    #    thread_count=$(ps -u "$user" -o nlwp --no-headers | awk '{sum+=$1} END {print sum+0}')
    #    printf "%-15s %-10s %-15s %-15s\n" "$user" "$cpu" "$proc_count" "$thread_count"
    #done | tee -a "$LOGFILE"

        print_section "MEMORY INFO (free -g)"
        # Capture free -g output
        FREE_OUTPUT=$(free -g)
        echo "$FREE_OUTPUT" | tee -a "$LOGFILE"

        echo "" | tee -a "$LOGFILE"

        echo "" | tee -a "$LOGFILE"

TOP_MEM_PIDS=$(echo "$TOP_SNAP" | awk '$1 ~ /^[0-9]+$/ {print $1, $10}' \
 | sort -k2 -nr | head -50 | awk '{print $1}')
echo "" | tee -a "$LOGFILE"
echo -e "\e[33m Date and Time : $(date '+%Y-%m-%d %H:%M:%S %Z' )\e[0m"| tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
print_section "Top 50 MEMORY Consuming Processes (FULL ARGS)"
echo "" | tee -a "$LOGFILE"
printf "%-8s %-6s %-6s %-6s %s\n" \
"PID" "USER" "%CPU" "%MEM" "COMMAND" | tee -a "$LOGFILE"

for pid in $TOP_MEM_PIDS; do
    ps -p "$pid" -o pid,user,%cpu,%mem,args --no-headers
done | tee -a "$LOGFILE"

echo "" | tee -a "$LOGFILE"

###########################################################
# TOP 5 USERS BY MEMORY (WITH PROCESS COUNT)
###########################################################

        #echo "" | tee -a "$LOGFILE"
        #echo -e "\e[33m---- Top 5 Users by Memory Utilization ----\e[0m" | tee -a "$LOGFILE"
        #printf "%-15s %-10s %-15s\n" "USER" "MEM(%)" "PROCESS_COUNT" | tee -a "$LOGFILE"
        #printf "%-15s %-10s %-15s\n" "----" "------" "--------------" | tee -a "$LOGFILE"
		#
        #ps -eo user,pmem --no-headers | \
        #awk '{ mem[$1]+=$2 } END { for (u in mem) print mem[u], u }' | \
        #sort -nr | head -5 | \
        #while read mem user; do
        #proc_count=$(ps -u "$user" --no-headers | wc -l)
        #printf "%-15s %-10s %-15s\n" "$user" "$mem" "$proc_count"
        #done | tee -a "$LOGFILE"

        ###########################################################
        # SHARED MEMORY SEGMENT ANALYSIS
        ###########################################################

        echo "" | tee -a "$LOGFILE"
        echo -e "\e[33m---- Shared Memory Segments ----\e[0m" | tee -a "$LOGFILE"

        # Take snapshot only once
        SHM_SNAPSHOT=$(ipcs -m)

        # Print snapshot to logfile
        echo "$SHM_SNAPSHOT" | tee -a "$LOGFILE"

        ###########################################################
    # LOAD AVERAGE (FROM TOP SNAPSHOT)
    ###########################################################

    # Extract load averages from the single top snapshot
    LOAD1=$(echo "$TOP_SNAP" | grep "load average" | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    LOAD5=$(echo "$TOP_SNAP" | grep "load average" | awk -F'load average:' '{print $2}' | awk '{print $2}' | tr -d ',')
    LOAD15=$(echo "$TOP_SNAP" | grep "load average" | awk -F'load average:' '{print $2}' | awk '{print $3}' | tr -d ',')

#########################High I-NODE value trigger Block ##############################
HIGH_INODE_FLAG=0

if df -i | awk 'NR>1 { gsub("%","",$5); if ($5 > 90) found=1 } END { exit !found }'; then
    HIGH_INODE_FLAG=1
    add_issue "High inode usage detected (>90%)"
fi

if (( HIGH_INODE_FLAG > 0 )); then

    echo "" | tee -a "$LOGFILE"
print_section "DISK I-NODE utilization More than 90%"

df -i | awk '
NR==1 {
    printf "%-20s %-12s %-12s %-8s %s\n", $1, $2, $3, $5, $6
    next
}
{
    gsub("%","", $5)
    if ($5 > 90)
        printf "%-20s %-12s %-12s %-8s %s\n", $1, $2, $3, $5"%", $6
}
' | tee -a "$LOGFILE"
fi
        echo "" | tee -a "$LOGFILE"

        ###########################################################
    # DISK I/O ANALYSIS (iostat -xz 1 1)
    ###########################################################

        print_section "-----------DISK & IO STATS----------"
    echo "" | tee -a "$LOGFILE"
        echo -e "\e[33m Data Taken at : $(date '+%Y-%m-%d %H:%M:%S %Z' )\e[0m"| tee -a "$LOGFILE"

    # Capture a single I/O snapshot
    IOSTAT_SNAP=$(iostat -xz 1 1)

    # Print full iostat snapshot
    echo "$IOSTAT_SNAP" | tee -a "$LOGFILE"

    # Parse disk device metrics
    echo "" | tee -a "$LOGFILE"


###########################################################
# NETWORK ANALYSIS (PORTS and PACKET DROPS)
###########################################################

        # LISTENING PORT(ss -lnt)

        SS_SNAP=$(ss -lnt)

        # Log raw output
        #echo "$SS_SNAP" | tee -a "$LOGFILE"

        echo "" | tee -a "$LOGFILE"
        # NIC Packet Drops (ip -s link)

        print_section "----NIC Packet Drops (ip -s link)----"
        NET_SNAP=$(ip -s link)
        echo "" | tee -a "$LOGFILE"
        echo "$NET_SNAP" | tee -a "$LOGFILE"

}

##################################################################################################


Data_Summary() {

############################# Data Summary Section ########################################

############################# CPU Summary ########################################

print_section " ---------CPU BREAKDOWN-------- "

CPU_USER=$(cat "$LOGFILE" | grep "CPU STATISTICS" -A6| tail -1 | awk '{print $3}')
CPU_SYS=$(cat "$LOGFILE" | grep "CPU STATISTICS" -A6| tail -1 | awk '{print $5}')
CPU_IDLE=$(cat "$LOGFILE" | grep "CPU STATISTICS" -A6| tail -1 | awk '{print $8}')
CPU_IOWAIT=$(cat "$LOGFILE" | grep "CPU STATISTICS" -A6| tail -1 | awk '{print $6}')
CPU_STEAL=$(cat "$LOGFILE" | grep "CPU STATISTICS" -A6| tail -1 | awk '{print $7}')
CPU_USAGE=$(echo "100 - $CPU_IDLE" | bc)
#DSTATE_COUNT=$(echo "$TOP_SNAP" | awk '$8=="D" {count++} END {print count+0} ')
ZOMBIE_COUNT=$(echo "$TOP_SNAP" | awk '$8=="Z" {count++} END {print count+0}')
RUN_QUEUE=$(cat "$LOGFILE" | grep "VMSTAT STATISTICS" -A5| tail -1 | awk '{print $1}')
CONTEXT_SWITCH=$(cat "$LOGFILE" | grep "VMSTAT STATISTICS" -A5| tail -1 | awk '{print $12}')
CPU_INTERRUPTS=$(cat "$LOGFILE" | grep "VMSTAT STATISTICS" -A5| tail -1 | awk '{print $11}')
CPU_CORES=$(nproc --all)

echo "CPU User%: $CPU_USER"| tee -a "$LOGFILE"
echo "CPU System%: $CPU_SYS"| tee -a "$LOGFILE"
echo "CPU Idle%: $CPU_IDLE"| tee -a "$LOGFILE"
echo "CPU iowait%: $CPU_IOWAIT"| tee -a "$LOGFILE"
echo "CPU Usage%: $CPU_USAGE"| tee -a "$LOGFILE"
echo "CPU Steal%: $CPU_STEAL"| tee -a "$LOGFILE"
#echo "D-State Processes: $DSTATE_COUNT" | tee -a "$LOGFILE"
echo "Zombie Processes : $ZOMBIE_COUNT" | tee -a "$LOGFILE"
echo "Run Queue :$RUN_QUEUE" | tee -a "$LOGFILE"
echo "Context Switches :$CONTEXT_SWITCH" | tee -a "$LOGFILE"
echo "Interrupts :$CPU_INTERRUPTS" | tee -a "$LOGFILE"
echo "CPU Cores :$CPU_CORES" | tee -a "$LOGFILE"

echo "" | tee -a "$LOGFILE"

############################# Memory Summary #################################

print_section "----------MEMORY BREAKDOWN---------- "

# Parse memory values
MEMORY_TOTAL=$(echo "$FREE_OUTPUT" | awk '/^Mem:/ {print $2}')
MEMORY_USED=$(echo "$FREE_OUTPUT" | awk '/^Mem:/ {print $3}')
BUFF_CACHE=$(echo "$FREE_OUTPUT" | awk '/^Mem:/ {print $6}')
MEMORY_AVAILABLE=$(echo "$FREE_OUTPUT" | awk '/^Mem:/ {print $7}')

# Calculate real used memory
MEMORY_USED_REAL=$(( MEMORY_TOTAL - MEMORY_AVAILABLE ))

# Parse swap values
SWAP_TOTAL=$(echo "$FREE_OUTPUT" | awk '/^Swap:/ {print $2}')
SWAP_USED=$(echo "$FREE_OUTPUT" | awk '/^Swap:/ {print $3}')

SWAP_TOTAL_mb=$(( SWAP_TOTAL * 1024 ))
SWAP_USED_mb=$(( SWAP_USED * 1024 ))
MEMORY_USED_PERCENTAGE=$(echo "scale=2;$MEMORY_USED_REAL*100/$MEMORY_TOTAL" | bc )
SWAP_USED_PERCENTAGE=$(echo "scale=2;$SWAP_USED_mb*100/$SWAP_TOTAL_mb" | bc )
SWAP_IN=$(cat $LOGFILE | grep "VMSTAT STATISTICS" -A5|tail -1|awk '{print $7}')
SWAP_OUT=$(cat $LOGFILE | grep "VMSTAT STATISTICS" -A5|tail -1|awk '{print $8}')
MEM_AVAILABLE_MB=$(( MEMORY_AVAILABLE * 1024 ))



############### Important for DB servers ########################

HP_TOTAL=$(grep HugePages_Total /proc/meminfo | awk '{print $2}')
HP_FREE=$(grep HugePages_Free  /proc/meminfo | awk '{print $2}')
HP_RSVD=$(grep HugePages_Rsvd /proc/meminfo | awk '{print $2}')

echo "Memory Total: $MEMORY_TOTAL GB" | tee -a "$LOGFILE"
echo "Memory Used REAL: $MEMORY_USED_REAL GB" | tee -a "$LOGFILE"  # Real Used = Total - Available
echo "Memory Usage(%): $MEMORY_USED_PERCENTAGE%" | tee -a "$LOGFILE"
echo "Swap Total: $SWAP_TOTAL GB" | tee -a "$LOGFILE"
echo "Swap Used: $SWAP_USED GB" | tee -a "$LOGFILE"
echo "Buff/Cache: $BUFF_CACHE GB" | tee -a "$LOGFILE"
echo "Swap IN: $SWAP_IN" | tee -a "$LOGFILE"
echo "Swap Out: $SWAP_OUT" | tee -a "$LOGFILE"

echo "" | tee -a "$LOGFILE"
echo "---- HugePages Status ----" | tee -a "$LOGFILE"

echo "HugePages Total: $HP_TOTAL" | tee -a "$LOGFILE"
echo "HugePages Free: $HP_FREE" | tee -a "$LOGFILE"
echo "HugePages Reserved: $HP_TOTAL" | tee -a "$LOGFILE"

echo "" | tee -a "$LOGFILE"
 # Count orphan segments (nattach = 0)
    ORPHAN_SHM=$(echo "$SHM_SNAPSHOT" | awk 'NR>3 && $6==0 {count++} END {print count+0}')

    echo "Orphan SHM Segments: $ORPHAN_SHM" | tee -a "$LOGFILE"
        LARGE_SHM_BYTES=$((2028 * 1024 * 1024))
        LARGE_SHM_FLAG=0

        # Find large segments (>2 GB)
    LARGE_SHM=$(echo "$SHM_SNAPSHOT" | awk -v TH="$LARGE_SHM_BYTES" '
    NR > 1 && $5 ~ /^[0-9]+$/ && $5 > TH
')

if [[ -n "$LARGE_SHM" ]]; then
    LARGE_SHM_FLAG=1
    add_issue "Large shared memory segment(s) detected (>100MB)"
fi


        # Total SHM allocated (in MB)
    TOTAL_SHM_MB=$(echo "$SHM_SNAPSHOT" | awk '
    $1 ~ /^0x/ { sum += $5 }
    END { printf "%.0f", sum / 1024 / 1024 }
')

TOTAL_RAM_MB=$(free -m | awk '/Mem:/ {print $2}')
SHM_PERCENT=$(awk -v shm="$TOTAL_SHM_MB" -v ram="$TOTAL_RAM_MB" \
    'BEGIN { printf "%.0f", (shm/ram)*100 }')

    echo "Total SHM Allocated (MB) : $TOTAL_SHM_MB" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"

############################# Load Average #################################
print_section "-----Load Average BREAKDOWN--------- "

        echo "Load Average 1m : $LOAD1"  | tee -a "$LOGFILE"
    echo "Load Average 5m : $LOAD5"  | tee -a "$LOGFILE"
    echo "Load Average 15m : $LOAD15" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"

############################# Disk Breakdown #################################

DISK_ISSUE_FLAG=0
HIGH_AWAIT_FLAG=0
CRITICAL_AWAIT_FLAG=0
HIGH_UTIL_FLAG=0
CRITICAL_UTIL_FLAG=0
HIGH_QUEUE_FLAG=0
CRITICAL_QUEUE_FLAG=0



###########################################################
# PARSE IOSTAT METRICS (from IOSTAT_SNAP)
###########################################################

echo "" | tee -a "$LOGFILE"
echo "---- Parsed Disk I/O Metrics (iostat -xz) ----" | tee -a "$LOGFILE"

echo -e "\e[33m Data Taken at : $(date '+%Y-%m-%d %H:%M:%S %Z' )\e[0m"| tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
printf "%-10s %-8s %-8s %-8s %-10s %-8s %-8s\n" \
"DEVICE" "r/s" "w/s" "await" "%util" "avgqu" "svctm" | tee -a "$LOGFILE"
printf "%-10s %-8s %-8s %-8s %-10s %-8s %-8s\n" \
"------" "----" "----" "-----" "-----" "------" "------" | tee -a "$LOGFILE"

echo "$IOSTAT_SNAP" | awk '
    # Match device rows: sda, vda, dm-x, nvme0n1, etc
    $1 ~ /^(sd|vd|hd|dm-|nvme)/ {
        dev=$1
        rs=$2
        ws=$3
        r_await=$10
                w_await=$11
        svctm=$15     # may be "-" on newer systems
        util=$(NF)

        avgqu=$12   # avgqu-sz

        printf "%-10s %-8s %-8s %-8s %-8s %-10s %-8s %-8s\n", dev, rs, ws, r_await, w_await, util, avgqu, svctm

        # PASS METRICS TO BASH FOR ISSUE HANDLING
        print "CHK", dev, rs, ws, r_await, w_await, util, avgqu, svctm
    }
' | while read tag dev rs ws r_await w_await util avgqu svctm; do

    [[ "$tag" != "CHK" ]] && continue

        DEVICE_BAD=0

    ####################################################
    # CONDITION 1 — HIGH LATENCY (await)
    ####################################################
    if (( $(echo "$r_await > 20" | bc -l) )) || (( $(echo "$w_await > 20" | bc -l) )); then
        add_issue "Disk latency high: device=$dev r_await=${r_await}ms  $dev w_await=${w_await}ms"
                HIGH_AWAIT_FLAG=1
                DEVICE_BAD=1
    fi

    if (( $(echo "$w_await > 20" | bc -l) )); then
        add_issue "DISK LATENCY: $dev w_await=${w_await}ms"
                HIGH_AWAIT_FLAG=1
                DEVICE_BAD=1
    fi

    ####################################################
    # CONDITION 2 — HIGH UTILIZATION (%util)
    ####################################################
    if (( $(echo "$util > 80" | bc -l) )); then
        add_issue "Disk $dev near saturation: util=$util%"
                HIGH_UTIL_FLAG=1
                DEVICE_BAD=1
    fi

    if (( $(echo "$util >= 99" | bc -l) )); then
        add_issue "CRITICAL: Disk $dev at 100% utilization → severe bottleneck"
                CRITICAL_UTIL_FLAG=1
                DEVICE_BAD=1
    fi

    ####################################################
    # CONDITION 3 — QUEUE DEPTH (avgqu-sz)
    ####################################################
    if (( $(echo "$avgqu > 1" | bc -l) )); then
        add_issue "Queue buildup on $dev: avgqu=$avgqu"
                HIGH_QUEUE_FLAG=1
                DEVICE_BAD=1
    fi

    if (( $(echo "$avgqu > 5" | bc -l) )); then
        add_issue "CRITICAL queue depth on $dev: avgqu=$avgqu"
                CRITICAL_QUEUE_FLAG=1
                DEVICE_BAD=1
    fi

    ####################################################
    # CONDITION 4 — SVCTM (service time)
    ####################################################
    if [[ "$svctm" != "-" ]] && (( $(echo "$svctm > 20" | bc -l) )); then
        add_issue "High service time on $dev: svctm=${svctm}ms"
    fi


        ############### Adding to DISK_PROBLEM_DEVICES ARRAY #####################

        if (( DEVICE_BAD == 1 )); then
        DISK_PROBLEM_DEVICES+=("$dev $await $util $avgqu")
        DISK_ISSUE_FLAG=1
        fi

done


###########################################################
# DNS Latency Check
###########################################################

############################# EDMS SCAN Name ##############################

print_section "Checking DNS Resolution and query Time"

DNS_SERVER=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)

#attempt for edms scanname

for i in {1..3}; do
DNS_QUERY_TIME=$(dig @"$DNS_SERVER" edmsvmdbscan.sbi +stats +tries=1 +time=2 2>/dev/null \
    | awk '/Query time:/ {print $4}')
	done

# fallback if empty
if [[ -z "$DNS_QUERY_TIME" ]]; then
    DNS_QUERY_TIME=9999
fi

echo "" | tee -a "$LOGFILE"
echo "---- DNS Latency Check EDMS SCANANME----" | tee -a "$LOGFILE"
echo "DNS Server: $DNS_SERVER" | tee -a "$LOGFILE"
echo "Query Time: ${DNS_QUERY_TIME} ms" | tee -a "$LOGFILE"

if (( DNS_QUERY_TIME > 10 )); then
    HIGH_DNS_LATENCY_FLAG=1
    add_issue "WARNING: High DNS query latency (${DNS_QUERY_TIME} ms) from $DNS_SERVER for edmsvmdbscan.sbi"
fi

################################## CKYC SCAN NAME ####################################

#attempt for edms scanname

for i in {1..3}; do
DNS_QUERY_TIME=$(dig @"$DNS_SERVER" ckycvmdbscan.sbi +stats +tries=1 +time=2 2>/dev/null \
    | awk '/Query time:/ {print $4}')
	done

# fallback if empty
if [[ -z "$DNS_QUERY_TIME" ]]; then
    DNS_QUERY_TIME=9999
fi

echo "" | tee -a "$LOGFILE"
echo "---- DNS Latency Check CKYC SCANNAME----" | tee -a "$LOGFILE"
echo "DNS Server: $DNS_SERVER" | tee -a "$LOGFILE"
echo "Query Time: ${DNS_QUERY_TIME} ms" | tee -a "$LOGFILE"

if (( DNS_QUERY_TIME > 10 )); then
    HIGH_DNS_LATENCY_FLAG=1
    add_issue "WARNING: High DNS query latency (${DNS_QUERY_TIME} ms) from $DNS_SERVER for ckycvmdbscan.sbi"
fi

######################################################################


HIGH_RECV_Q_FLAG=0

###########################################################
# Ports With High Recv-Q (Backlog / Connection Pressure)
###########################################################

echo "" | tee -a "$LOGFILE"
echo -e "\e[33m---- Listening Ports With Recv-Q > 1 ----\e[0m" | tee -a "$LOGFILE"

# Print table and capture whether high recv-q exists
FOUND_RECV_Q=$(echo "$SS_SNAP" | awk '
BEGIN {
    found = 0
    printf "%-8s %-10s %-10s %-40s\n", "PORT", "RECV-Q", "SEND-Q", "ADDRESS"
}

/LISTEN/ {
    recv = $2
    send = $3
    port_field = $4

    split(port_field, arr, ":")
    port = arr[length(arr)]

    if (recv > 1) {
        found = 1
        printf "%-8s %-10s %-10s %-40s\n", port, recv, send, port_field
    }
}

END {
    if (found == 0) {
        print "No listening ports with Recv-Q > 1 found."
    }
    print found
}
' | tee -a "$LOGFILE" | tail -n 1)

# Trigger flag + issue in shell (not in awk)
if (( FOUND_RECV_Q == 1 )); then
    HIGH_RECV_Q_FLAG=1
    add_issue "WARNING: High Recv-Q found on one or more listening ports"
fi


###########################################################
# Connection Analysis Per Port
###########################################################

echo "" | tee -a "$LOGFILE"
echo -e "\e[33m---- Connection Analysis (ESTABLISHED / WAIT) ----\e[0m" | tee -a "$LOGFILE"

NETSTAT_SNAP=$(netstat -an)

for i in $(echo "$NETSTAT_SNAP" | awk '/LISTEN/ && /10\.191\.213\.2[0-9]/ {print $4}' \
    | grep -E ':(153[0-9]|154[0-7])$')
do
    ip=$(echo "$i" | cut -d: -f1)
    port=$(echo "$i" | cut -d: -f2)

    est=$(echo "$NETSTAT_SNAP" | grep -w "$i" | grep ESTABLISHED | grep -v 127.0.0.1 | wc -l)
    wait=$(echo "$NETSTAT_SNAP" | grep -w "$i" | grep WAIT | grep -v 127.0.0.1 | wc -l)

    echo "$i ==> ESTABLISHED: $est WAIT: $wait" | tee -a "$LOGFILE"

    # Top EST clients
    echo "$NETSTAT_SNAP" | grep -w "$i" | grep ESTABLISHED | awk '{print $5}' \
        | cut -d: -f1 | sort | uniq -c | sort -nr | head -5 \
        | awk '{print "ESTABLISHED:", $2, "==>", $1}' | tee -a "$LOGFILE"

    # Top WAIT clients
    echo "$NETSTAT_SNAP" | grep -w "$i" | grep WAIT | awk '{print $5}' \
        | cut -d: -f1 | sort | uniq -c | sort -nr | head -5 \
        | awk '{print "WAIT:", $2, "==>", $1}' | tee -a "$LOGFILE"

    echo "----------------------------------------" | tee -a "$LOGFILE"
done

# Total summary
echo "" | tee -a "$LOGFILE"
echo "TOTAL...." | tee -a "$LOGFILE"

TOTAL_EST=$(echo "$NETSTAT_SNAP" | grep ESTABLISHED | grep -v 127.0.0.1 | wc -l)
TOTAL_WAIT=$(echo "$NETSTAT_SNAP" | grep WAIT | grep -v 127.0.0.1 | wc -l)

echo -e "\e[33mESTABLISHED: $TOTAL_EST\e[0m" | tee -a "$LOGFILE"
echo -e "\e[33mWAIT: $TOTAL_WAIT\e[0m" | tee -a "$LOGFILE"




}




Issue_Condition() {

HIGH_SYS_FLAG=0
HIGH_RUNQ_FLAG=0
HIGH_SWAPUSED_FLAG=0
HIGH_SWAP_ACTIVITY_FLAG=0
HIGH_ORPHAN_SHM_FLAG=0
HIGH_TOTAL_SHM_FLAG=0
HIGH_LOAD_FLAG=0
#D_STATE_FLAG=0
ZOMBIE_PROCESS_FLAG=0
#HIGH_RECV_Q_FLAG=0
HIGH_CS_FLAG=0


# %sys usage Thresholds .

SYS_WARN=25
SYS_CRIT=40

if (( CPU_SYS > SYS_CRIT )); then
    add_issue "CRITICAL: System CPU (%sys) very high = ${CPU_SYS}%. Indicates kernel bottleneck (I/O, IRQ, softirq, locks)."
        HIGH_SYS_FLAG=1

elif (( CPU_SYS > SYS_WARN )); then
    add_issue "WARNING: System CPU (%sys) high = ${CPU_SYS}%. Suggest checking I/O, network, interrupts."
        HIGH_SYS_FLAG=1

fi

# CPU STEAL TIME issue DETECTION

STEAL_WARN=2
STEAL_CRIT=5
HIGH_STEAL_FLAG=0

if (( $(echo "$CPU_STEAL > $STEAL_WARN" | bc -l) )); then
    HIGH_STEAL_FLAG=1
    add_issue "High CPU Steal detected: %steal=${CPU_STEAL}% (VM host contention suspected)"
fi

if (( $(echo "$CPU_STEAL > $STEAL_CRIT" | bc -l) )); then
        HIGH_STEAL_FLAG=1
    add_issue "CRITICAL: CPU Steal extremely high (${CPU_STEAL}%) — severe hypervisor contention"
fi


# Run Queue thresholds
    if (( RUN_QUEUE > CPU_CORES )); then
        add_issue "High Run Queue: $RUN_QUEUE (CPU cores=$CPU_CORES)"
                HIGH_RUNQ_FLAG=1
    fi

    if (( RUN_QUEUE > CPU_CORES * 2 )); then
        add_issue "CRITICAL: Run Queue extremely high ($RUN_QUEUE > 2x CPU cores)"
                HIGH_RUNQ_FLAG=1
    fi


###################################################
# Context Switching Detection (Normalized per CPU)
###################################################

HIGH_CS_FLAG=0
CS_PER_SEC=$CONTEXT_SWITCH
CS_SEVERITY="NORMAL"

if (( CPU_CORES > 0 )); then
    CS_PER_CPU=$(awk -v cs="$CS_PER_SEC" -v cpu="$CPU_CORES" '
        BEGIN { printf "%.0f", cs / cpu }
    ')
else
    CS_PER_CPU=0
fi

if (( CS_PER_CPU > 20000 )); then
    HIGH_CS_FLAG=1
    add_issue "CRITICAL: Context switching extremely high (${CS_PER_CPU}/sec per CPU)"
elif (( CS_PER_CPU > 15000 )); then
    HIGH_CS_FLAG=1
    add_issue "WARNING: High context switching (${CS_PER_CPU}/sec per CPU)"
else
    CS_SEVERITY="INFO"
fi

    if (( ZOMBIE_COUNT > 0 )); then
        ZOMBIE_PROCESS_FLAG=1
    add_issue "$ZOMBIE_COUNT Zombie processes found (parent not reaping properly)"
    fi

        # Add issue if swap is > 50% of total Swap
   if (( SWAP_USED_PERCENTAGE > 50 )); then
       add_issue "High Swap Usage ! Possible Memory Pressure"
           HIGH_SWAPUSED_FLAG=1
    fi

        # si > 0 means memory pressure (pages pulled from disk)
    if (( SWAP_IN > 0 )); then
        add_issue "Swap-In detected: si=$SWAP_IN KB/s (Memory pressure)"
                HIGH_SWAP_ACTIVITY_FLAG=1
    fi

    # so > 0 means pages actively being swapped OUT (critical)
    if (( SWAP_OUT > 0 )); then
        add_issue "Swap-Out detected: so=$SWAP_OUT KB/s (Critical memory exhaustion)"
                HIGH_SWAP_ACTIVITY_FLAG=1
    fi

        if (( ORPHAN_SHM > 0 )); then
        add_issue "$ORPHAN_SHM orphan shared memory segments detected (possible memory leak)"
                HIGH_ORPHAN_SHM_FLAG=1
    fi
###################################################
# High Shared Memory Detection
###################################################

        if (( SHM_PERCENT > 80 )); then
    HIGH_TOTAL_SHM_FLAG=1
    add_issue "CRITICAL: SHM uses ${SHM_PERCENT}% of system RAM"
        elif (( SHM_PERCENT > 70 )); then
    HIGH_TOTAL_SHM_FLAG=1
    add_issue "WARNING: SHM uses ${SHM_PERCENT}% of system RAM"
        fi

###################################################
# High Load Average DETECTION
###################################################
        if (( $(echo "$LOAD1 > $CPU_CORES" | bc -l) )); then
        HIGH_LOAD_FLAG=1
        add_issue "High Load: LOAD1=$LOAD1 (CPU cores=$CPU_CORES)"
    fi

    if (( $(echo "$LOAD1 > $CPU_CORES*2" | bc -l) )); then
        HIGH_LOAD_FLAG=1
        add_issue "CRITICAL: LOAD1 extremely high ($LOAD1 > 2x CPU cores)"
    fi




###################################################
# Packet Drop Detection
###################################################
HIGH_PKT_DROP_FLAG=0
PKT_DROP_SEVERITY="NORMAL"

RX_DROPS_TOTAL=0
TX_DROPS_TOTAL=0

while read -r line; do
    if [[ $line =~ ^[0-9]+:\  ]]; then
        iface=$(echo "$line" | awk '{gsub(":", "", $2); print $2}')
    fi

    if [[ $line == "RX:"* ]]; then
        read -r rx_line
        rx_drop=$(echo "$rx_line" | awk '{print $4}')
        RX_DROPS_TOTAL=$((RX_DROPS_TOTAL + rx_drop))
    fi

    if [[ $line == "TX:"* ]]; then
        read -r tx_line
        tx_drop=$(echo "$tx_line" | awk '{print $4}')
        TX_DROPS_TOTAL=$((TX_DROPS_TOTAL + tx_drop))
    fi
done <<< "$NET_SNAP"


if (( RX_DROPS_TOTAL > 0 || TX_DROPS_TOTAL > 0 )); then
    HIGH_PKT_DROP_FLAG=1

    if (( RX_DROPS_TOTAL > 100 || TX_DROPS_TOTAL > 100 )); then
        PKT_DROP_SEVERITY="CRITICAL"
        add_issue "CRITICAL: Network packet drops detected (RX=$RX_DROPS_TOTAL TX=$TX_DROPS_TOTAL)"
    else
        PKT_DROP_SEVERITY="WARNING"
        add_issue "WARNING: Network packet drops detected (RX=$RX_DROPS_TOTAL TX=$TX_DROPS_TOTAL)"
    fi
fi


# --------------------------------------------------
# Detect High SHM Attach Count (SAFE)
# --------------------------------------------------
HIGH_NATTCH_FLAG=0
SHM_NATTCH_THRESHOLD=1500

if echo "$SHM_SNAPSHOT" | awk -v TH="$SHM_NATTCH_THRESHOLD" '
    $1 ~ /^0x/ && $6+0 > TH {
        found=1
        exit
    }
    END { exit !found }
'; then
    HIGH_NATTCH_FLAG=1
    add_issue "High SHM attachment count detected (nattch > $SHM_NATTCH_THRESHOLD)"
fi


###################################################
# Memory Pressure Detection
###################################################

MEM_PRESSURE_FLAG=0

# Condition 1: Active swapping
if (( SWAP_IN > 0 || SWAP_OUT > 0 )); then
    MEM_PRESSURE_FLAG=1
fi

# Condition 2: Very low available memory (<5% of RAM)
AVAIL_MEM_PCT=$(awk -v avail="$MEM_AVAILABLE_MB" -v total="$TOTAL_RAM_MB" \
    'BEGIN { printf "%.0f", (avail/total)*100 }')

if (( AVAIL_MEM_PCT < 5 )); then
    MEM_PRESSURE_FLAG=1
fi

#############################################################################################






###########################################################
# ROOT CAUSE ANALYSIS ENGINE (BIFURCATION)
###########################################################
Issue_Bifurcation() {

    echo "" | tee -a "$LOGFILE"
    echo "===================================================" | tee -a "$LOGFILE"
    echo "             ROOT CAUSE ANALYSIS (BIFURCATION)       " | tee -a "$LOGFILE"
    echo "===================================================" | tee -a "$LOGFILE"

#######################################################
# 1️ HIGH SYSTEM CPU USAGE
#######################################################
    if (( HIGH_SYS_FLAG == 1 )); then

        echo "" | tee -a "$LOGFILE"
        echo -e "\e[33mHIGH %SYS CPU USAGE FOUND... ANALYSING ROOT CAUSE ...\e[0m" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"

###################################################
# A. SoftIRQ (ksoftirqd) Diagnosis
###################################################
        echo -e "\e[33m---- Checking SoftIRQ (ksoftirqd) CPU Usage ----\e[30m" | tee -a "$LOGFILE"

        SOFTIRQ_THRESHOLD=10
        SOFTIRQ_FOUND=0

        echo "$TOP_SNAP" | awk -v th=$SOFTIRQ_THRESHOLD '
            $1 ~ /^[0-9]+$/ && $2 ~ /ksoftirqd/ {
                cpu=$9
                if(cpu > th) {
                    SOFTIRQ_FOUND=1
                    cmd=""
                    for(i=12;i<=NF;i++) cmd=cmd" "$i
                    printf "%-10s %-18s %-8s %s\n", $1, $2, cpu, cmd
                }
        }' | tee -a "$LOGFILE"

        if (( SOFTIRQ_FOUND == 1 )); then
            echo "" | tee -a "$LOGFILE"
            echo -e "\e[35mSUGGESTED ACTION:\e[0m" | tee -a "$LOGFILE"
            echo "  • Check NIC or storage interrupts" | tee -a "$LOGFILE"
            echo "  • Verify IRQ affinity (/proc/interrupts)" | tee -a "$LOGFILE"
            echo "  • Enable irqbalance" | tee -a "$LOGFILE"
        else
            echo "No SoftIRQ overload detected." | tee -a "$LOGFILE"
        fi


###################################################
# B. Disk I/O Latency Diagnosis
###################################################
        echo "" | tee -a "$LOGFILE"
        echo -e "\e[33m---- Checking for Disk I/O Latency  ----\e[0m" | tee -a "$LOGFILE"

        #IOSTAT_OUTPUT=$(iostat -xz 1 1 2>/dev/null)
        #echo "$IOSTAT_SNAP" | tee -a "$LOGFILE"

        DISK_ISSUE=0

        echo "$IOSTAT_SNAP" | awk '
            $1 ~ /^sd|^dm|^nvme/ {
                dev=$1; await=$10; util=$NF;
                if(await > 50 || util > 90) {
                    print dev, await, util
                }
        }' | while read dev await util; do
            DISK_ISSUE=1
            echo "High disk latency on $dev (await=${await}ms, util=${util}%)" | tee -a "$LOGFILE"
        done

        if (( DISK_ISSUE == 1 )); then
            echo "" | tee -a "$LOGFILE"
            echo -e "\e[35mSUGGESTED ACTION:\e[0m" | tee -a "$LOGFILE"
            echo "  • Check SAN path stability (multipath -ll)" | tee -a "$LOGFILE"
            echo "  • Check storage errors in dmesg" | tee -a "$LOGFILE"
            echo "  • Review I/O heavy processes" | tee -a "$LOGFILE"
        else
            echo "No disk bottleneck detected." | tee -a "$LOGFILE"
        fi


###################################################
# C. Interrupt Storm Detection
###################################################

echo "" | tee -a "$LOGFILE"
echo -e "\e[33m---- Interrupt Load Analysis ----" | tee -a "$LOGFILE"

IRQ_ISSUE=0
IRQ_THRESHOLD=20000   # Tune based on workload

# Generate interrupt summary (clean + readable)
IRQ_SUMMARY=$(awk '
/eth|ens|eno|enp|mlx|nvme|ahci|megaraid/ {
    irq=$1
    total=0
    for(i=2;i<=NF;i++) total += $i
    printf "%-25s total=%d\n", irq, total
}' /proc/interrupts)

echo "$IRQ_SUMMARY" | tee -a "$LOGFILE"

# Detect IRQ storm
echo "$IRQ_SUMMARY" | while read irq total; do
    val=$(echo "$total" | awk -F= '{print $2}')
    if (( val > IRQ_THRESHOLD )); then
        IRQ_ISSUE=1
        echo "High interrupt load detected: $irq → $val" | tee -a "$LOGFILE"
    fi
done

# Action Plan
if (( IRQ_ISSUE == 1 )); then
    echo "" | tee -a "$LOGFILE"
    echo -e "\e[35mSUGGESTED ACTION:\e[0m" | tee -a "$LOGFILE"
    echo "  • Redistribute interrupts using irqbalance" | tee -a "$LOGFILE"
    echo "  • Check NIC firmware & driver version" | tee -a "$LOGFILE"
    echo "  • Verify no interrupt imbalance: cat /proc/interrupts" | tee -a "$LOGFILE"
    echo "  • Tune RSS/RPS/XPS for network load distribution" | tee -a "$LOGFILE"
else
    echo "No interrupt storm detected." | tee -a "$LOGFILE"
fi


    fi  # end HIGH_SYS_FLAG block


#######################################################
# 2️ RUN QUEUE > CPU CORES (CPU Saturation)
#######################################################

if (( HIGH_RUNQ_FLAG == 1 )); then

    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33m High Run Queue Found (CPU Saturation).ANALYSING ROOT CAUSE...\e[0m" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"
    echo "RUNQ=$RUN_QUEUE  CPU_CORES=$CPU_CORES" | tee -a "$LOGFILE"
        echo "Possible Reasons for High RUNQ:" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
        echo "1. CPU Processes Contributing to High RUNQ" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
        echo "2. D-State (Blocked I/O) causing thread pile-up (Will be Printed if any)" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
        echo "3. Load Average" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
        echo "4. Context Switch Storm (Threads fighting for CPU)" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
        echo "Checking One by One......" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"

    ###################################################
        # 1. Identify top CPU-consuming processes (From TOP_SNAP)
        ###################################################
        echo -e "\e[33m---- Top CPU Processes Contributing to High RUNQ (from TOP snapshot) ----\e[0m" | tee -a "$LOGFILE"

        printf "%-8s %-7s %-6s %-6s %s\n" \
        "PID" "USER" "%CPU" "%MEM" "COMMAND" | tee -a "$LOGFILE"

        for pid in $TOP_CPU_PIDS; do
                ps -p "$pid" -o pid,user,%cpu,%mem,args --no-headers
        done | tee -a "$LOGFILE"

        echo "" | tee -a "$LOGFILE"
        echo -e "\e[35mSUGGESTED ACTION:\e[0m" | tee -a "$LOGFILE"
        echo "  • Investigate top CPU hogs above" | tee -a "$LOGFILE"
        echo "  • Consider tuning or restricting high-CPU applications" | tee -a "$LOGFILE"

    ###################################################
    # 3. Check Load Average impact
    ###################################################
    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33m---- Checking Load Average ----\e[0m" | tee -a "$LOGFILE"

    echo "Load Average: 1min=$LOAD1  5min=$LOAD5  15min=$LOAD15" | tee -a "$LOGFILE"

    echo "" | tee -a "$LOGFILE"
    echo -e "\e[35mSUGGESTED ACTION:\e[0m" | tee -a "$LOGFILE"
    echo "  • If LOAD1 >> LOAD15 means sudden spike. Identify High Cpu consuming, R-state and D-STATE processess (if any)" | tee -a "$LOGFILE"
    echo "  • If load stays above CPU cores → CPU saturation is chronic" | tee -a "$LOGFILE"


###################################################
# 4. Check Context Switch Storm (Threads fighting for CPU)
###################################################
    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33m---- Context Switch Rate ----\e[0m" | tee -a "$LOGFILE"

    echo "Context Switches/sec = $CONTEXT_SWITCH" | tee -a "$LOGFILE"

    if (( CONTEXT_SWITCH > 20000 )); then
        echo "" | tee -a "$LOGFILE"
        echo "High context switching detected → Possible thread contention" | tee -a "$LOGFILE"
                print_section "-------Top Thread-heavy Processes-------"
                ps -eo pid,ppid,user,%cpu,%mem,nlwp,args --sort=-nlwp | head -20 | tee -a "$LOGFILE"
                echo "" | tee -a "$LOGFILE"
        echo -e "\e[35mSUGGESTED ACTION:\e[0m" | tee -a "$LOGFILE"
        echo "  • Check thread-heavy applications (Java, Web servers) " | tee -a "$LOGFILE"
        echo "  • Consider Reducing thread pool sizes" | tee -a "$LOGFILE"


        else
        echo -e "\e[32m No high Context Switches Found\e[0m" | tee -a "$LOGFILE"

        fi


fi


###########################################################
# 3. ZOMBIE PROCESSES FROM TOP SNAPSHOT
###########################################################

if (( ZOMBIE_PROCESS_FLAG == 1 )) ; then

echo "" | tee -a "$LOGFILE"

echo -e "\e[33mANALYSING ROOT CAUSE...For ZOMBIE Process\e[0m" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

echo " Current ZOMBIE Processess: " | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"


Z_STATE_CULPRIT_PIDS=$(ps -eo pid,state --no-headers | awk '
    $2 ~ /Z/ { print $1 }
' | sort -u)


echo "" | tee -a "$LOGFILE"

printf "%-8s %-7s %-7s %-4s %-4s %-4s %s\n" \
"PID" "PPID" "USER" "%CPU" "%MEM" "STAT" "COMMAND" | tee -a "$LOGFILE"

for pid in $Z_STATE_CULPRIT_PIDS; do
    ps -p "$pid" -o pid,ppid,user,%cpu,%mem,stat,args --no-headers
done | tee -a "$LOGFILE"


echo "" | tee -a "$LOGFILE"
echo -e "\e[35mSUGGESTED ACTION:\e[0m" | tee -a "$LOGFILE"
echo "  • Fix application logic (missing wait()/waitpid())" | tee -a "$LOGFILE"
echo "  • Restart parent process if safe" | tee -a "$LOGFILE"
echo "  • Try Killing parent process" | tee -a "$LOGFILE"
echo "  • Long-term fix required in application code" | tee -a "$LOGFILE"
fi



#######################################################
# 4 HIGH SWAP USAGE (Memory Pressure / Swap Storm)
#######################################################
if (( HIGH_SWAPUSED_FLAG == 1 )); then

    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33mHIGH SWAP USAGE DETECTED...ANALYSING ROOT CAUSE...\e[0m" | tee -a "$LOGFILE"
    echo "SWAP_USED=$SWAP_USED  SWAP_TOTAL=$SWAP_TOTAL" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"

    ###################################################
    # A. Identify Top Swap-Using Processes
    ###################################################
    echo -e "\e[33m---- Top Swap-Consuming Processes ----\e[0m" | tee -a "$LOGFILE"

    printf "%-8s %-10s %-8s %-8s %s\n" "PID" "USER" "SWAP(MB)" "%MEM" "COMMAND" | tee -a "$LOGFILE"

    # /proc/<pid>/smaps_rollup gives swap usage per process (RHEL8+)
    for pid in /proc/[0-9]*; do
        p=${pid##*/}
        swap_kb=$(grep -s "Swap:" $pid/smaps_rollup 2>/dev/null | awk '{sum += $2} END{print sum}')
        if [[ -n "$swap_kb" && "$swap_kb" -gt 0 ]]; then
            swap_mb=$(( swap_kb / 1024 ))
            user=$(ps -o user= -p $p 2>/dev/null)
            mem=$(ps -o %mem= -p $p 2>/dev/null)
            cmd=$(ps -o comm= -p $p 2>/dev/null)

            echo "$p $user $swap_mb $mem $cmd"
        fi
    done | sort -k3 -nr | head -10 | awk '
        { printf "%-8s %-10s %-8s %-8s %s\n", $1, $2, $3, $4, $5 }
    ' | tee -a "$LOGFILE"


###################################################
# B. Detect Swap-In / Swap-Out Activity (Paging Pressure)
###################################################
    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33m---- Swap Activity (SI / SO) from Vmstat snapshot----\e[0m" | tee -a "$LOGFILE"

    echo "Swap-In (si): $SWAP_IN  KB/s" | tee -a "$LOGFILE"
    echo "Swap-Out (so): $SWAP_OUT  KB/s" | tee -a "$LOGFILE"

    if (( SWAP_IN > 50 || SWAP_OUT > 50 )); then
        echo "High swap activity detected → SYSTEM IS PAGING HEAVILY" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"
        echo "SUGGESTED ACTION:" | tee -a "$LOGFILE"
        echo "  • Reduce memory-heavy processes" | tee -a "$LOGFILE"
        echo "  • Check JVM heap sizes / DB SGA sizes" | tee -a "$LOGFILE"
        echo "  • Consider increasing RAM" | tee -a "$LOGFILE"
        echo "  • Tune vm.swappiness (set to 10)" | tee -a "$LOGFILE"
    fi


    #######################################################
    # C. HugePages Check (Common Memory Optimization Issue)
    #######################################################
    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33m---- HugePages Status ----\e[0m" | tee -a "$LOGFILE"

    echo "HugePages: Total=$HP_TOTAL  Free=$HP_FREE  Reserved=$HP_RSVD" | tee -a "$LOGFILE"

    if (( HP_TOTAL > 0 && HP_FREE == 0 )); then
        echo "" | tee -a "$LOGFILE"
        echo "HugePages completely consumed means possible memory Starvation." | tee -a "$LOGFILE"
        echo -e "\e[35mSUGGESTED ACTION:\e[0m" | tee -a "$LOGFILE"
        echo "  • Increase HugePages count" | tee -a "$LOGFILE"
        echo "  • Fix DB/JVM memory configuration" | tee -a "$LOGFILE"
    fi

fi  # END HIGH_SWAPUSED_FLAG



#######################################################
# 5 ACTIVE SWAP ACTIVITY (Swap-In / Swap-Out > 0)
#######################################################

if (( HIGH_SWAP_ACTIVITY_FLAG == 1 )); then

    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33mACTIVE SWAPING (si/so > 0) FOUND.. ANALYSING ROOT CAUSE\e[0m" | tee -a "$LOGFILE"
    echo "Swap-In (si): $SWAP_IN  KB/s" | tee -a "$LOGFILE"
    echo "Swap-Out (so): $SWAP_OUT  KB/s" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"

    ###################################################
    # A. Identify Processes Causing Heavy Paging
    ###################################################

PAGING_CULPRIT_PIDS=$(ps -eo pid,state,%cpu,%mem --no-headers | awk '
    $2 ~ /D/ || $3 > 50 || $4 > 5 { print $1 }
' | sort -u)

echo "" | tee -a "$LOGFILE"

if [[ -n "$PAGING_CULPRIT_PIDS" ]]; then
    echo "" | tee -a "$LOGFILE"
    echo -e "\e[32m---- Heavy Paging Suspected Processes ----\e[0m" | tee -a "$LOGFILE"

    printf "%-8s %-10s %-6s %-6s %-5s %s\n" \
        "PID" "USER" "%CPU" "%MEM" "STAT" "COMMAND" | tee -a "$LOGFILE"

    for pid in $PAGING_CULPRIT_PIDS; do
        ps -p "$pid" -o pid,user,%cpu,%mem,stat,args --no-headers
    done | tee -a "$LOGFILE"
else
    echo -e "\e[32mNo paging-suspected processes detected\e[0m" | tee -a "$LOGFILE"
fi

    ###################################################
    # B. Show Top Swap Consuming Processes
    ###################################################
    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33m---- Top Processes Using Swap (from smaps_rollup) ----\e[0m" | tee -a "$LOGFILE"

    printf "%-8s %-6s %-10s %s\n" "PID" "USER" "SWAP(MB)" "COMMAND" | tee -a "$LOGFILE"

    for p in /proc/[0-9]*; do
        pid=${p##*/}
        swap_kb=$(grep -s "Swap:" $p/smaps_rollup | awk '{sum+=$2} END{print sum}')
        if [[ -n "$swap_kb" && "$swap_kb" -gt 0 ]]; then
            swap_mb=$(( swap_kb / 1024 ))
            user=$(ps -o user= -p $pid)
            cmd=$(ps -o comm= -p $pid)
            echo "$pid $user $swap_mb $cmd"
        fi
    done | sort -k3 -nr | head -10 | tee -a "$LOGFILE"

    ###################################################
    # C. Swap Storm Interpretation
    ###################################################
    echo "" | tee -a "$LOGFILE"

    if (( SWAP_IN > 150 || SWAP_OUT > 150 )); then
        echo -e "\e[31mCRITICAL: System is under SWAP STORM (si/so > 150 KB/s)\e[0m" | tee -a "$LOGFILE"
        echo "System may freeze soon." | tee -a "$LOGFILE"
    elif (( SWAP_IN > 50 || SWAP_OUT > 50 )); then
        echo "WARNING: Moderate swap activity detected (si/so > 50 KB/s)" | tee -a "$LOGFILE"
    else
        echo "NOTE: Minimal swap activity but still abnormal (si/so > 0)" | tee -a "$LOGFILE"
    fi

###################################################
# D. Suggested Action Plan
###################################################
    echo "" | tee -a "$LOGFILE"
    echo -e "\e[35mSUGGESTED ACTION:\e[0m" | tee -a "$LOGFILE"
    echo "  • Reduce memory-heavy processes above" | tee -a "$LOGFILE"
    echo "  • Investigate JVM heap / DB SGA configuration" | tee -a "$LOGFILE"
    echo "  • Tune vm.swappiness = 10 (avoid early swapping)" | tee -a "$LOGFILE"
    echo "  • Add more RAM if memory consistently runs full" | tee -a "$LOGFILE"
    echo "  • Check for memory leak patterns (rapid RSS increase)" | tee -a "$LOGFILE"

fi # END HIGH_SWAPIN_SWAP_OUT_FLAG



#######################################################
# 6. SHARED MEMORY ISSUES (ORPHAN SHM / HIGH SHM USAGE)
#######################################################


if (( HIGH_ORPHAN_SHM_FLAG == 1 || HIGH_TOTAL_SHM_FLAG == 1 )); then

    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33mSHARED MEMORY (IPC SHM) ISSUES FOUND ...ANALYSING ROOT CAUSE\e[0m" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"

    ###################################################
    # A. ORPHANED SHARED MEMORY SEGMENTS
    ###################################################
    if (( ORPHAN_SHM > 0 )); then
        echo -e "\e[33m---- Orphaned Shared Memory Segments Detected ----\e[0m" | tee -a "$LOGFILE"
        echo "Count: $ORPHAN_SHM" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"

        # Print orphaned SHM full details from snapshot
        awk '$NF == "0" { printf "%-10s %-10s %-10s %-10s %-10s %-10s\n",
              $1,$2,$3,$4,$5,$6 }' <<< "$SHM_SNAPSHOT" | tee -a "$LOGFILE"

        echo "" | tee -a "$LOGFILE"
        echo "SUGGESTED ACTION:" | tee -a "$LOGFILE"
        echo "  • Orphan SHM means: creator died but SHM still exists" | tee -a "$LOGFILE"
        echo "  • Identify owner process and app using SHM" | tee -a "$LOGFILE"
        echo "  • Clean orphaned segments manually: ipcrm -m <shmid>" | tee -a "$LOGFILE"
        echo "  • Check application crash logs" | tee -a "$LOGFILE"
        echo "  • Tune SHMMNI / SHMMAX if apps frequently leak SHM" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"
    else
        echo "No orphan shared memory segments detected." | tee -a "$LOGFILE"
    fi


###################################################
# B. TOTAL SHARED MEMORY EXTREMELY HIGH
###################################################

    if (( HIGH_TOTAL_SHM_FLAG == 1 )) && \
   (( HIGH_SWAP_ACTIVITY_FLAG == 1 || MEM_PRESSURE_FLAG == 1 )); then
        echo "" | tee -a "$LOGFILE"
        echo -e "\e[33m---- Total Shared Memory Extremely High ----\e[0m" | tee -a "$LOGFILE"
        printf "%-35s : %s%%\n" "Total SHM usage of RAM" "$SHM_PERCENT" | tee -a "$LOGFILE"
                printf "%-35s : %s MB\n" "Total SHM" "$SHM_TOTAL_MB" | tee -a "$LOGFILE"
                printf "%-35s : %s MB\n" "Total System RAM" "$TOTAL_RAM_MB" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"

        echo "Top SHM Segments (sorted by size):" | tee -a "$LOGFILE"
                echo "SHMID        USER     PERMS      SIZE(bytes)    N-ATTACH" | tee -a "$LOGFILE"
        awk '
            NR>3 && $5 ~ /^[0-9]+$/ {
                printf "%-12s %-10s %-10s %-12s %-10s\n",
                       $2,$3,$4,$5,$NF
            }
        ' <<< "$SHM_SNAPSHOT" | sort -k4 -nr | head -10 | tee -a "$LOGFILE"

        echo "" | tee -a "$LOGFILE"
    echo -e "\e[33mROOT CAUSE :\e[0m"
    echo "  • Large shared memory allocation consuming significant RAM" | tee -a "$LOGFILE"
    echo "  • Typical for database buffer caches and IPC-heavy workloads" | tee -a "$LOGFILE"
    echo "  • Problem arises when memory pressure or swapping occurs" | tee -a "$LOGFILE"

    if (( HIGH_SWAP_ACTIVITY_FLAG == 1 )); then
        echo "  • Swap activity detected — SHM contributing to memory pressure" | tee -a "$LOGFILE"
    fi

    if (( MEM_PRESSURE_FLAG == 1 )); then
        echo "  • Low free memory observed — risk of paging" | tee -a "$LOGFILE"
    fi

        echo "" | tee -a "$LOGFILE"
    echo -e "\e[35mSUGGESTED ACTION:\e[0m" | tee -a "$LOGFILE"
    echo "  • Validate SGA / buffer cache sizing (DBA review)" | tee -a "$LOGFILE"
    echo "  • Ensure enough free RAM remains for OS" | tee -a "$LOGFILE"
    echo "  • Avoid shrinking SHM unless swapping or OOM occurs" | tee -a "$LOGFILE"
    echo "  • Review application SHM usage if non-DB segments exist" | tee -a "$LOGFILE"
    echo "  • Monitor trends rather than taking immediate action" | tee -a "$LOGFILE"
        echo "  • Increase kernel SHM limits if necessary (shmmax/shmall)" | tee -a "$LOGFILE"


        elif (( HIGH_TOTAL_SHM_FLAG == 1 )); then
###################################################
# Informational-only case
###################################################
    echo "" | tee -a "$LOGFILE"
    echo "INFO: High Total SHM usage observed (${SHM_PERCENT}% of RAM), but system is stable." | tee -a "$LOGFILE"
    echo "No swap activity or memory pressure detected." | tee -a "$LOGFILE"
    echo "This is normal for database/RAC workloads." | tee -a "$LOGFILE"

    fi


fi ## END SHARED MEMORY and ORPHAN_SHM Bifurcation



#######################################################
# 7. HIGH LOAD AVERAGE (LOAD1 > CPU_CORES)
#######################################################

if (( HIGH_LOAD_FLAG == 1 )) ; then

if (( $(echo "$LOAD1 > $CPU_CORES" | bc -l) )); then

    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33m HIGH LOAD AVERAGE OBSERVED...ANALYSING ROOT CAUSE\e[0m" | tee -a "$LOGFILE"
    echo "Load1 = $LOAD1    CPU Cores = $CPU_CORES" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"

###################################################
# A. Load Summary
###################################################
    echo -e "\e[33m---- Load Average Snapshot ----\e[0m" | tee -a "$LOGFILE"
    echo "1min = $LOAD1    5min = $LOAD5    15min = $LOAD15" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"

    if (( $(echo "$LOAD1 > $CPU_CORES*2" | bc -l) )); then
        echo -e "\e[31mCRITICAL: Load average more than double CPU cores → Severe contention.\e[0m" | tee -a "$LOGFILE"
    else
        echo "WARNING: Load average above CPU capacity → Possible CPU wait or I/O wait." | tee -a "$LOGFILE"
    fi


###################################################
# B. Identify Culprit Processes from TOP Snapshot
###################################################
    echo "" | tee -a "$LOGFILE"
    CULPRIT_PIDS=$(echo "$TOP_SNAP" | awk '
    $1 ~ /^[0-9]+$/ {
        pid=$1
        state=$8
        cpu=$9
        if (state=="R" || state=="D" || cpu > 50)
            print pid
    }
' | sort -u)


echo "" | tee -a "$LOGFILE"
echo "---- Processes Contributing to High Load ----" | tee -a "$LOGFILE"

printf "%-8s %-10s %-6s %-6s %-4s %s\n" \
"PID" "USER" "%CPU" "%MEM" "STAT" "COMMAND" | tee -a "$LOGFILE"

for pid in $CULPRIT_PIDS; do
    ps -p "$pid" -o pid,user,%cpu,%mem,stat,args --no-headers
done | tee -a "$LOGFILE"

    ###################################################
    # D. Suggested Action Plan
    ###################################################
    echo "" | tee -a "$LOGFILE"
    echo -e "\e[35mSUGGESTED ACTION:\e[0m" | tee -a "$LOGFILE"
    echo "  • Check top CPU Consuming processes " | tee -a "$LOGFILE"
    echo "  • Check   %sys usage, I/O wait, context switch, run queue (Already Printed if any)" | tee -a "$LOGFILE"
    echo "  • Check I/O bottleneck (Already Printed if any)" | tee -a "$LOGFILE"
    echo "  • Check D-state (uninterruptible) processes for disk stalls (Already Printed if any)" | tee -a "$LOGFILE"
    echo "  • Investigate thread-heavy or stuck application loops" | tee -a "$LOGFILE"
    echo "  • Consider Increasing CPUs." | tee -a "$LOGFILE"

fi

fi  # end of high load Bifurcation



#######################################################
# 8. DISK I/O BOTTLENECK (await / %util / avgqu / errors)
#######################################################
if (( DISK_ISSUE_FLAG == 1 )); then

    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33m DISK I/O BOTTLENECK OBSERVED..ANALYSING ROOT CAUSE...\e[0m" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"

    ###################################################
    # A. List problematic devices detected earlier
    ###################################################
    echo -e "\e[33m---- Problematic Disk Devices Detected ----\e[0m" | tee -a "$LOGFILE"
    printf "%-10s %-10s %-10s %-10s\n" "DEVICE" "await(ms)" "%util" "avgqu" | tee -a "$LOGFILE"

    for entry in "${DISK_PROBLEM_DEVICES[@]}"; do
        echo "$entry" | tee -a "$LOGFILE"
    done

    echo "" | tee -a "$LOGFILE"


    ###################################################
    # B. Disk Latency Analysis
    ###################################################
    echo -e "\e[33m---- Disk Latency & Saturation Summary ----\e[0m" | tee -a "$LOGFILE"

    if (( HIGH_AWAIT_FLAG == 1 )); then
        echo "High disk latency detected (await > 20 ms)." | tee -a "$LOGFILE"
        echo "Impact: Applications waiting for disk, slower response." | tee -a "$LOGFILE"
    fi

    if (( HIGH_UTIL_FLAG == 1 )); then
        echo "Disk utilization > 80% → Device nearing saturation." | tee -a "$LOGFILE"
    fi

    if (( CRITICAL_UTIL_FLAG == 1 )); then
        echo "CRITICAL: Disk stuck at 99-100% → Hard bottleneck." | tee -a "$LOGFILE"
    fi

    if (( HIGH_QUEUE_FLAG == 1 )); then
        echo "Queue depth increasing (avgqu > 1) → Requests waiting too long." | tee -a "$LOGFILE"
    fi

    echo "" | tee -a "$LOGFILE"


    ###################################################
    # C. Check Storage Path (multipath)
    ###################################################
    echo -e "\e[33m---- Storage Path Status (multipath -ll) ----\e[0m" | tee -a "$LOGFILE"

    MP_OUT=$(multipath -ll 2>/dev/null)
    #echo "$MP_OUT" | tee -a "$LOGFILE"

    if echo "$MP_OUT" | grep -qi "failed\|fault\|removed"; then
        echo "" | tee -a "$LOGFILE"
        echo "ALERT: Multipath shows failed or faulty paths." | tee -a "$LOGFILE"
        MP_ISSUE_FLAG=1
    else
        echo -e "\e[32mMultipath paths appear healthy.\e[0m" | tee -a "$LOGFILE"
    fi


    ###################################################
    # D. Check Kernel Logs For I/O Errors
    ###################################################
    echo "" | tee -a "$LOGFILE"
    echo "---- Disk Errors From Kernel Logs (dmesg) ----" | tee -a "$LOGFILE"

    DMESG_ERRORS=$(dmesg | grep -Ei "error|fail|scsi|block|I/O|timeout" | tail -20)

    if [[ -n "$DMESG_ERRORS" ]]; then
        echo "$DMESG_ERRORS" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"
        echo "ALERT: Kernel reported disk/storage errors." | tee -a "$LOGFILE"
        DMESG_ISSUE_FLAG=1
    else
        echo -e "\e[32mNo disk-related kernel errors found.\e[0m" | tee -a "$LOGFILE"
    fi


    ###################################################
    # E. Suggested Action Plan Based on Findings
    ###################################################
    echo "" | tee -a "$LOGFILE"
    echo -e "\e[35mSUGGESTED ACTION PLAN:\e[0m" | tee -a "$LOGFILE"

    if (( CRITICAL_AWAIT_FLAG == 1 || CRITICAL_UTIL_FLAG == 1 )); then
        echo -e "\e[33m  • CRITICAL: Engage storage/SAN team immediately\e[0m" | tee -a "$LOGFILE"
        echo "  • Run: 'iostat -xz 1', 'sar -d', check latency again" | tee -a "$LOGFILE"
    fi

    if (( MP_ISSUE_FLAG == 1 )); then
        echo "  • Fix multipath failures; check fibre/iSCSI paths" | tee -a "$LOGFILE"
    fi

    if (( DMESG_ISSUE_FLAG == 1 )); then
        echo "  • Kernel sees SCSI or disk timeouts → check SAN switches" | tee -a "$LOGFILE"
    fi

    echo "  • Identify I/O heavy processes → iotop / ps -eo io" | tee -a "$LOGFILE"
    echo "  • Check NFS mounts if latency involves network FS" | tee -a "$LOGFILE"
    echo "  • Consider moving high-load apps to SSD/NVMe" | tee -a "$LOGFILE"
    echo "  • Tune scheduler (deadline/noop for SAN, cfq for HDD)" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"

fi #END of DISK I/O BOTTLENECK BIFURCATION


#######################################################
# 9. High RECV-Q BIFURCATION
#######################################################

if (( HIGH_RECV_Q_FLAG == 1 )); then
        echo -e "\e[33mHigh RECV-Q Found..Output of ss-lnt Already Printed before.\[0m" | tee -a "$LOGFILE"
		echo "" | tee -a "$LOGFILE"
                echo -e "\e[35mSUGGESTED ACTION:\e[0m" | tee -a "$LOGFILE"
                echo "  • Check CPU Usage (App doesn't gets scheduled because of High CPU usage)" | tee -a "$LOGFILE"
                echo "  • Check for RUN-Q (threads waiting for CPU --> accept() delayed) " | tee -a "$LOGFILE"
                echo "  • Check application accept()/worker thread Behavior " | tee -a "$LOGFILE"
                echo "  • Check for Blocked (D-state) processes --> app may be stuck in I/O" | tee -a "$LOGFILE"
                echo "  • Check for Thread-Heavy Processes." | tee -a "$LOGFILE"
                echo "  • Tune kernel backlog (somaxconn, tcp_max_syn_backlog parameters ) in sysctl.conf" | tee -a "$LOGFILE"
                echo "" | tee -a "$LOGFILE"


    fi


#######################################################
# 10. High CPU STEAL TIME ROOT CAUSE ANALYSIS
#######################################################
if (( HIGH_STEAL_FLAG == 1 )); then

    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33mANALYSING ROOT CAUSE FOR HIGH CPU STEAL TIME...\e[0m" | tee -a "$LOGFILE"
    echo "CPU Steal Time = ${CPU_STEAL}%" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"


        # Check if VM
    if grep -q hypervisor /proc/cpuinfo; then
        echo "System is Likely a VM. (OS running on hypervisor)" | tee -a "$LOGFILE"
    else
        echo "WARNING: %steal on bare metal is unexpected. It shoud be always 0." | tee -a "$LOGFILE"
    fi

        # Correlate with run queue
    if (( RUNQ > CPU_CORES )); then
        echo "CPU contention inside VM + host scheduling delay" | tee -a "$LOGFILE"
                echo "Threads waiting for CPU inside VM" | tee -a "$LOGFILE"
    fi

        ###################################################
    # Explanation
    ###################################################
    echo -e "\e[33mROOT CAUSE :\e[0m"
        echo "  • VM is not receiving requested CPU Time" | tee -a "$LOGFILE"
    echo "  • CPU cycles are being taken by the hypervisor" | tee -a "$LOGFILE"
    echo "  • Indicates host-level CPU overcommitment" | tee -a "$LOGFILE"


        echo -e "\e[35mSUGGESTED ACTION (OUTSIDE VM)\e[0m:" | tee -a "$LOGFILE"
        echo "  • Check host CPU usage & overcommit ratio" | tee -a "$LOGFILE"
    echo "  • Migrate VM to less loaded host" | tee -a "$LOGFILE"
        echo "  • Review VM vCPU count vs actual usage" | tee -a "$LOGFILE"
    echo "  • Increase vCPU allocation if possible" | tee -a "$LOGFILE"

        echo "" | tee -a "$LOGFILE"
    echo "NOTE:" | tee -a "$LOGFILE"
    echo "  • Killing processes inside VM will NOT fix %steal" | tee -a "$LOGFILE"
    echo "  • This is a virtualization-level bottleneck" | tee -a "$LOGFILE"

fi #END High CPU STEAL TIME ROOT CAUSE ANALYSIS

#######################################################
# 11. SHARED MEMORY (SHM) ROOT CAUSE ANALYSIS
#######################################################
if (( LARGE_SHM_FLAG == 1 )); then

    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33m ROOT CAUSE FOR LARGE SHARED MEMORY SEGMENTS\e[0m" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"

    ###################################################
    # A. Identify large SHM segments
    ###################################################
    echo -e "\e[33m---- Large Shared Memory Segments (>2GB)----\e[0m" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"
    printf "%-10s %-10s %-10s %-10s %-10s %-10s\n" "key" "SHMID" "OWNER" "perms" "SIZE(bytes)" "NATTCH" | tee -a "$LOGFILE"
    echo "$LARGE_SHM" | tee -a "$LOGFILE"

    ###################################################
    # B. Check for orphaned SHM
    ###################################################

    if (( ORPHAN_SHM > 0 )); then
        echo "" | tee -a "$LOGFILE"
        echo "WARNING: Orphaned shared memory segments detected (nattch=0)" | tee -a "$LOGFILE"
    fi

    ###################################################
    # C. Correlate with memory pressure
    ###################################################
    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33m---- Memory Pressure Correlation ----\e[0m" | tee -a "$LOGFILE"
    echo "Swap Used (MB) : $Swap_Used_MB" | tee -a "$LOGFILE"
    echo "Swap In/Out    : si=$SWAP_IN  so=$SWAP_OUT" | tee -a "$LOGFILE"

    if (( Swap_Used_MB > 0 )); then
        echo -e "\e[31mLarge SHM + Swap usage detected → possible memory pressure\e[0m" | tee -a "$LOGFILE"
    fi

    ###################################################
    # D. HugePages check
    ###################################################
    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33m---- HugePages Status ----\e[0m" | tee -a "$LOGFILE"

    grep -E "HugePages_Total|HugePages_Free|Hugepagesize" /proc/meminfo | tee -a "$LOGFILE"

    ###################################################
    # ROOT CAUSE SUMMARY
    ###################################################
    echo "" | tee -a "$LOGFILE"

    if (( ORPHAN_SHM > 0 )); then
        echo -e " • \e[31m Orphaned SHM segments consuming memory\e[0m" | tee -a "$LOGFILE"
    fi

    if (( Swap_Used_MB > 0 )); then
        echo -e " • \e[31m Large SHM contributing to memory pressure and swap usage\e[0m" | tee -a "$LOGFILE"
    else
        echo -e "• \e[32m As Swapping isn't observed, Large SHM appears but not causing immediate pressure\e[0m" | tee -a "$LOGFILE"
    fi

    ###################################################
    # SUGGESTED ACTION
    ###################################################
    echo "" | tee -a "$LOGFILE"
    echo -e "\e[35mSUGGESTED ACTION:\e[0m" | tee -a "$LOGFILE"
    echo "  • Verify if SHM owner/application is expected (DB, middleware)" | tee -a "$LOGFILE"
    echo "  • Remove orphaned SHM (ipcrm) after validation" | tee -a "$LOGFILE"
    echo "  • Configure HugePages for large SHM workloads" | tee -a "$LOGFILE"
    echo "  • Ensure total SHM fits in physical RAM (avoid swap)" | tee -a "$LOGFILE"
    echo "  • Restart leaking application if SHM grows continuously" | tee -a "$LOGFILE"

fi  #END of SHARED MEMORY (SHM) ROOT CAUSE ANALYSIS


###################################################
# 12. SHM Bifurcation: High nattach Segments
###################################################

if (( HIGH_NATTCH_FLAG == 1 )); then
    echo "" | tee -a "$LOGFILE"
        echo -e "\e[33mANALYSING ROOT CAUSE FOR High N-Attach Count ----\e[0m" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"
    echo -e "\e[33m---- Shared Memory Segments with High Attach Count ----\e[0m" | tee -a "$LOGFILE"

    printf "%-12s %-10s %-12s %-12s %-10s\n" \
    "KEY" "SHMID" "OWNER" "SIZE(MB)" "NATTCH" | tee -a "$LOGFILE"

    echo "$SHM_SNAPSHOT" | awk -v TH="$SHM_NATTCH_THRESHOLD" '
        $1 ~ /^0x/ && $2 ~ /^[0-9]+$/ {
            key=$1
            shmid=$2
            owner=$3
            size_mb=$5/1024/1024
            nattch=$6

            if (nattch > TH) {
                printf "%-12s %-10s %-12s %-12.1f %-10s\n",
                       key, shmid, owner, size_mb, nattch
            }
        }
    ' | tee -a "$LOGFILE"

    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33mROOT CAUSE :\e[0m"
    echo "  • Many processes attached to same SHM segment" | tee -a "$LOGFILE"
    echo "  • Large thread pools or fork-heavy applications" | tee -a "$LOGFILE"
    echo "  • IPC-heavy apps (Oracle / SAP / Java / messaging)" | tee -a "$LOGFILE"

    echo "" | tee -a "$LOGFILE"
    echo -e "\e[35mSUGGESTED ACTION:\e[0m" | tee -a "$LOGFILE"
    echo "  • Identify owning application (owner column)" | tee -a "$LOGFILE"
        echo "  • Identify processes attached to SHM using : ipcs -m -i <shmid>" | tee -a "$LOGFILE"
        echo "  • Remove SHM only if nattach = 0" | tee -a "$LOGFILE"
    echo "  • Check application connection/thread pool limits" | tee -a "$LOGFILE"
    echo "  • Verify SHMMAX / SHMALL kernel limits" | tee -a "$LOGFILE"
    echo "  • Restart app only if safe and SHM leak suspected" | tee -a "$LOGFILE"

fi #END HIGG N-ATTACH SHM PROCESS ROOT CAUSE ANALYSIS



###################################################
# 13 Context Switching Bifurcation
###################################################
if (( HIGH_CS_FLAG == 1 )) && \
   (( HIGH_RUNQ_FLAG == 1 || HIGH_SYS_FLAG == 1 || HIGH_SWAP_ACTIVITY_FLAG == 1 || D_STATE_FLAG == 1 )); then

    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33m---- High Context Switching Detected ----\e[0m" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"
        echo -e "\e[33m---- ROOT CAUSE ANALYSIS FOR HIGH CONTEXT SWITCHING ----\e[0m" | tee -a "$LOGFILE"
    echo "Context Switches/sec : $CS_PER_SEC" | tee -a "$LOGFILE"

    echo "" | tee -a "$LOGFILE"
    echo "CONDITION TRIGGERS:" | tee -a "$LOGFILE"
    (( HIGH_RUNQ_FLAG == 1 ))        && echo "  • High Run Queue detected" | tee -a "$LOGFILE"
    (( HIGH_SYS_FLAG == 1 ))    && echo "  • High %sys CPU utilization" | tee -a "$LOGFILE"
    (( HIGH_SWAP_ACTIVITY_FLAG == 1 )) && echo "  • Active swap-in/out observed" | tee -a "$LOGFILE"
    (( D_STATE_FLAG == 1 ))      && echo "  • Processes stuck in D-state" | tee -a "$LOGFILE"

    echo "" | tee -a "$LOGFILE"
    echo -e "\e[33mROOT CAUSE :\e[0m" | tee -a "$LOGFILE"
    echo "  • Excessive runnable threads competing for CPU" | tee -a "$LOGFILE"
    echo "  • Lock contention or synchronization overhead" | tee -a "$LOGFILE"
    echo "  • Oversized thread pools or fork-heavy applications" | tee -a "$LOGFILE"

    ###################################################
    # Top Thread-Heavy Processes
    ###################################################
    echo "" | tee -a "$LOGFILE"
    echo "---- Top 15 Thread-Heavy Processes ----" | tee -a "$LOGFILE"

    printf "%-8s %-10s %-10s %-6s %s\n" \
    "PID" "USER" "THREADS" "%CPU" "COMMAND" | tee -a "$LOGFILE"

    ps -eLf \
        --sort=-nlwp \
        -o pid,user,nlwp,%cpu,cmd \
        --no-headers \
        | head -15 \
        | tee -a "$LOGFILE"

echo "" | tee -a "$LOGFILE"
echo -e "\e[35mSUGGESTED ACTION:\e[0m" | tee -a "$LOGFILE"
echo "  • Review thread pool configuration for top processes" | tee -a "$LOGFILE"
echo "  • Ensure thread count aligns with CPU cores" | tee -a "$LOGFILE"
echo "  • Investigate lock contention if %sys is elevated" | tee -a "$LOGFILE"
echo "  • Check application logs for excessive thread creation" | tee -a "$LOGFILE"
echo "  • Avoid killing processes unless confirmed runaway threads" | tee -a "$LOGFILE"

fi # END OF HIGH CONTEXT SWITCHING BIFURCATION



###################################################
# 14. Packet Drop Bifurcation
###################################################

if (( HIGH_PKT_DROP_FLAG == 1 )); then

        echo "" | tee -a "$LOGFILE"
    echo -e "\e[33m---- Packet Drops Detected ----\e[0m" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"
    echo -e "\e[33m---- Network Interfaces with Packet Drops ----\e[0m" | tee -a "$LOGFILE"

    printf "%-12s %-10s %-10s\n" "INTERFACE" "RX_DROP" "TX_DROP" | tee -a "$LOGFILE"
        RX_DROP_IFACES=0
        TX_DROP_IFACES=0
        BOTH_DROP_IFACES=0

    while read -r line; do
        if [[ $line =~ ^[0-9]+:\  ]]; then
            iface=$(echo "$line" | awk '{gsub(":", "", $2); print $2}')
        fi

        if [[ $line == "RX:"* ]]; then
            read -r rx_line
            rx_drop=$(echo "$rx_line" | awk '{print $4}')
        fi

        if [[ $line == "TX:"* ]]; then
            read -r tx_line
            tx_drop=$(echo "$tx_line" | awk '{print $4}')

                if (( rx_drop > 0 && tx_drop > 0 )); then
                        BOTH_DROP_IFACES=$((BOTH_DROP_IFACES + 1))
                elif (( rx_drop > 0 )); then
                        RX_DROP_IFACES=$((RX_DROP_IFACES + 1))
                elif (( tx_drop > 0 )); then
                        TX_DROP_IFACES=$((TX_DROP_IFACES + 1))
                fi

            if (( rx_drop > 0 || tx_drop > 0 )); then
                printf "%-12s %-10s %-10s\n" "$iface" "$rx_drop" "$tx_drop" | tee -a "$LOGFILE"
            fi
        fi
    done <<< "$NET_SNAP"


echo "" | tee -a "$LOGFILE"
echo -e "\e[33mROOT CAUSE ANALYSIS:\e[0m" | tee -a "$LOGFILE"

if (( RX_DROP_IFACES > 0 )); then
    echo "  • RX packet drops detected (receiver-side pressure)" | tee -a "$LOGFILE"
    echo "  • Possible NIC ring buffer overflow" | tee -a "$LOGFILE"
    echo "  • CPU softirq processing lag" | tee -a "$LOGFILE"
    echo "  • IRQ imbalance across CPU cores" | tee -a "$LOGFILE"
fi

if (( TX_DROP_IFACES > 0 )); then
    echo "  • TX packet drops detected (sender-side congestion)" | tee -a "$LOGFILE"
    echo "  • Application sending faster than NIC can transmit" | tee -a "$LOGFILE"
    echo "  • Queue discipline (qdisc) congestion" | tee -a "$LOGFILE"
fi

if (( BOTH_DROP_IFACES > 0 )); then
    echo "  • Bidirectional packet drops detected (severe network pressure)" | tee -a "$LOGFILE"
    echo "  • Potential NIC saturation or driver-level limitations" | tee -a "$LOGFILE"
fi



echo "" | tee -a "$LOGFILE"
echo -e "\e[35mSUGGESTED ACTION:\e[0m" | tee -a "$LOGFILE"

if (( RX_DROP_IFACES > 0 )); then
    echo "  • Check NIC ring buffer sizes (ethtool -g <iface>)" | tee -a "$LOGFILE"
    echo "  • Increase RX buffers if supported (ethtool -G <iface>)" | tee -a "$LOGFILE"
    echo "  • Check softirq load (top /mpstat -P ALL)" | tee -a "$LOGFILE"
    echo "  • Verify IRQ balance (irqbalance service)" | tee -a "$LOGFILE"
fi

if (( TX_DROP_IFACES > 0 )); then
    echo "  • Check application send rate / batching behavior" | tee -a "$LOGFILE"
    echo "  • Review traffic shaping or tc rules (tc qdisc show)" | tee -a "$LOGFILE"
    echo "  • Validate NIC transmit queue limits" | tee -a "$LOGFILE"
fi

if (( BOTH_DROP_IFACES > 0 )); then
    echo "  • Verify NIC bandwidth vs workload demand" | tee -a "$LOGFILE"
    echo "  • Check for NIC driver or firmware issues" | tee -a "$LOGFILE"
    echo "  • Consider NIC bonding or higher-capacity interface" | tee -a "$LOGFILE"
fi



fi # END OF Packet Drop Bifurcation


}


###########################################################
# KERNEL DISK ERROR CHECK (dmesg)
###########################################################

    echo "" | tee -a "$LOGFILE"
    print_section "---- Kernel Disk Error Messages ----"

    DMESG_ERR=$(dmesg | grep -iE "I/O error|blk_update_request|abort|disk error|buffer I/O|write error|read error|recovered error|fail" )

    if [[ -n "$DMESG_ERR" ]]; then
        echo "$DMESG_ERR" | tee -a "$LOGFILE"

        # Add each line as an issue
        echo "$DMESG_ERR" | while read line; do
            add_issue "KERNEL DISK ERROR: $line"
        done
    else
        echo -e "\e[32mNo disk-related errors in dmesg\e[0m" | tee -a "$LOGFILE"
    fi

####################Print Block For errors in Journalctl and /var/log/messages#########################
	
if (( LOG_ERR_FLAG == 1 )); then
    echo "" | tee -a "$LOGFILE"
	add_issue "Errors detected in /var/log/messages or Journalctl (last 2 minutes)"
    echo "---- Recent Error Logs (Last 2 Minutes) ----" | tee -a "$LOGFILE"

    echo -e "\e[33m[journalctl]\e[0m" | tee -a "$LOGFILE"
    journalctl --since "2 minutes ago" -p err..alert --no-pager 2>/dev/null | head -20 | tee -a "$LOGFILE"
	
    echo "" | tee -a "$LOGFILE"
	
    echo -e "\e[33m[/var/log/messages]\e[0m" | tee -a "$LOGFILE"
    if [[ -n "$MSG_ERR" ]]; then
	
        echo "$MSG_ERR" | tail -20 | tee -a "$LOGFILE"
    else
        echo "No recent errors found in /var/log/messages" | tee -a "$LOGFILE"
    fi
fi	
	
	
}



Issue_Summary() {

print_section "SUMMARY OF ISSUES"

if [[ -z "$ISSUES" ]]; then
echo -e "\e[32mNo issues detected.\e[0m" | tee -a "$LOGFILE"
else
echo -e "\e[31m $ISSUES\e[0m" | tee -a "$LOGFILE"
fi

echo -e "\nLog saved at: $LOGFILE"

}



###############################################################################
# MAIN FLOW OF SCRIPT
###############################################################################

check_auto_mode
Data_Collection
Data_Summary
Issue_Condition
Issue_Summary
Issue_Bifurcation

exit 0

