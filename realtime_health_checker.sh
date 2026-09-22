#!/bin/bash
###############################################################################
# System Diagnostic Script
# Description: Comprehensive health check for CPU, Memory, Disk, Processes, and Network.
# Requirements: sysstat (iostat, pidstat), procps (ps, top), net-tools/ss
###############################################################################

# --- Configuration ---
SYS_THRESHOLD=30  # System CPU % threshold for alert
LOG_LINES=400     # Approximate lines to scan for last 4 hours in /var/log/messages
TIME_WINDOW="4 hours"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# --- Helper Functions ---
print_header() {
    echo -e "\n${BOLD}${BLUE}=================================================================${NC}"
    echo -e "${BOLD}${BLUE} $1 ${NC}"
    echo -e "${BOLD}${BLUE}=================================================================${NC}\n"
}

print_status() {
    local status=$1
    local message=$2
    if [ "$status" -eq 0 ]; then
        echo -e "${GREEN}[OK]${NC} $message"
    else
        echo -e "${RED}[CRITICAL]${NC} $message"
    fi
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}[WARNING]${NC} Some metrics (like dmesg full access or process args) may be limited. Run as root for full details."
    fi
}

# --- 1. Kernel Errors (Last 4 Hours) ---
check_kernel_logs() {
    print_header "1. Kernel Errors & Failures (Last $TIME_WINDOW)"
    local found_errors=0
    echo "Generated: $(date)"

        echo " "
    # Check /var/log/messages (if exists)
    if [ -f /var/log/messages ]; then
        # Attempt to filter by time if journalctl isn't available, otherwise grep recent lines
        # Note: Exact time filtering in raw logs is complex without journalctl.
        # We grep for common error patterns in the tail of the file as a proxy for 'recent'.
        local errors=$(grep -iE "error|fail|critical|warn" /var/log/messages 2>/dev/null | tail -n $LOG_LINES)
        if [ -n "$errors" ]; then
            echo -e "${RED}Found potential errors in /var/log/messages:${NC}"
            echo "$errors" | head -20
            found_errors=1
        else
            print_status 0 "No obvious errors found in recent /var/log/messages entries."
        fi
    else
        echo -e "${YELLOW}[INFO]${NC} /var/log/messages not found. Skipping."
    fi

    # Check dmesg
    local dmesg_errors=$(dmesg --level=err,crit,alert,emerg 2>/dev/null | tail -n 50)
    if [ -z "$dmesg_errors" ]; then
        # Fallback for older dmesg versions without --level
        dmesg_errors=$(dmesg 2>/dev/null | grep -iE "error|fail|critical" | tail -n 50)
    fi

    if [ -n "$dmesg_errors" ]; then
        echo -e "${RED}Recent dmesg errors:${NC}"
        echo "$dmesg_errors" | head -20
        found_errors=1
    else
        print_status 0 "No recent kernel errors in dmesg."
    fi

    if [ $found_errors -ne 0 ]; then
        echo -e "\n${RED}ACTION REQUIRED: Review kernel logs above immediately.${NC}"
    fi
}

# --- 2. CPU, RAM, Load & Top 30 Processes ---
check_resources() {
    print_header "2. System Resources & Top 30 Processes"
    echo "Generated: $(date)"
        echo " "

    # CPU & Load
    local load=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    local cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | cut -d'%' -f1)

    # Handle top output variations (some show 'id', some '%id')
    if [ -z "$cpu_idle" ]; then
        cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $4}' | cut -d'%' -f1)
    fi

    local cpu_used=$(awk "BEGIN {printf \"%.2f\", 100 - $cpu_idle}")

    echo "Load Average: $load"
    echo "CPU Usage: ${cpu_used}% (Idle: ${cpu_idle}%)"

    # RAM
    free -h

    # Robustly extract System CPU (%sy)
local top_line=$(top -bn1 | grep "Cpu(s)")

# Method: Split by comma, find the segment containing 'sy', then extract the number
local sys_cpu=$(echo "$top_line" | awk -F',' '{
    for(i=1; i<=NF; i++) {
        if($i ~ /sy/) {
            gsub(/[^0-9.]/, "", $i); # Remove non-numeric chars
            print $i;
            exit;
        }
    }
}')

# Fallback if 'sy' label is missing (very old top versions)
if [ -z "$sys_cpu" ]; then
    sys_cpu=$(echo "$top_line" | awk '{print $6}' | cut -d'%' -f1)
fi

# Ensure it defaults to 0 if empty
sys_cpu=${sys_cpu:-0}   

    # Convert to integer for comparison
    local sys_int=${sys_cpu%.*}
    if [ "${sys_int:-0}" -gt "$SYS_THRESHOLD" ]; then
        echo -e "\n${RED}[ALERT] System CPU Utilization (${sys_cpu}%) is higher than threshold (${SYS_THRESHOLD}%)${NC}"
    else
        echo -e "\n${GREEN}[OK] System CPU Utilization (${sys_cpu}%) is within limits.${NC}"
    fi

    echo -e "\n${BOLD}\e[33mTop 30 Processes (by CPU) with Full Arguments:${NC}"
    # Using ps to get full args (ww) and sorting by CPU
    ps -eo pid,user,%cpu,%mem,stat,command --sort=-%cpu | head -31

        echo ""
        echo -e "\n${BOLD}\e[33mTop 30 Processes (by MEMORY) with Full Arguments:${NC}"
    # Using ps to get full args (ww) and sorting by CPU
    ps -eo pid,user,%cpu,%mem,stat,command --sort=-%mem | head -31


}

# --- 3. Disk Latency (iostat) - ROBUST VERSION ---
check_disk_latency() {
    print_header "3. Disk Latency (iostat)"

    if ! command -v iostat &> /dev/null; then
        echo -e "${YELLOW}[WARNING]${NC} iostat not found. Install sysstat package."
        return
    fi

    echo "Device | Await(ms) | %Util | Status"
    echo "-------|-----------|-------|-------"

    local issue_found=0
    local HDD_THRESH=20
    local SSD_THRESH=5

    # Use awk to dynamically find column indices from the header
    iostat -x 1 2 2>/dev/null | awk -v h_thresh="$HDD_THRESH" -v s_thresh="$SSD_THRESH" '
    BEGIN { red="\033[0;31m"; green="\033[0;32m"; yellow="\033[1;33m"; nc="\033[0m" }
    /^Device/ {
        # Map column names to their index numbers dynamically
        for (i=1; i<=NF; i++) {
            if ($i == "r_await") r_col = i
            else if ($i == "w_await") w_col = i
            else if ($i == "%util") u_col = i
            else if ($i == "await") await_col = i # Fallback for old versions
        }
        next
    }
    /^[a-z]/ { # Process device lines (sda, sdb, etc.)
        dev = $1
        # Calculate average await if split columns exist, otherwise use combined
        if (r_col && w_col) {
            await_val = ($r_col + $w_col) / 2
        } else if (await_col) {
            await_val = $await_col
        } else {
            await_val = 0
        }

        util_val = $u_col

        # Determine Status Color
        status = green "OK" nc
        if (await_val > h_thresh) {
            status = red "HIGH LATENCY" nc
            exit_code = 1 # Signal issue to shell
        } else if (await_val > s_thresh) {
            status = yellow "ELEVATED" nc
        }

        printf "%-7s| %-9.2f | %-5.1f | %s\n", dev, await_val, util_val, status
    }
    END { if (exit_code) exit 1 }
    '

    if [ $? -eq 1 ]; then
        echo -e "\n${RED}ACTION: High disk latency detected.${NC}"
    fi
}

# --- 4. D-State and Zombie Processes ---
check_process_states() {
    print_header "4. D-State (Uninterruptible) & Zombie Processes"
    echo "Generated: $(date)"
        echo " "
    # Zombies (State Z)
    local zombies=$(ps -eo pid,ppid,stat,user,%cpu,%mem,command | awk '$3 ~ /Z/')
    local z_count=$(echo "$zombies" | grep -c .)

    if [ "$z_count" -gt 0 ]; then
        echo -e "${RED}Found $z_count Zombie Process(es):${NC}"
        echo "PID    PPID   STAT USER   %CPU %MEM COMMAND"
        echo "$zombies"
    else
        print_status 0 "No Zombie processes found."
    fi

    echo ""

    # D-State (Uninterruptible Sleep - usually I/O wait)
    local d_state=$(ps -eo pid,ppid,stat,user,%cpu,%mem,command | awk '$3 ~ /D/')
    local d_count=$(echo "$d_state" | grep -c .)

    if [ "$d_count" -gt 0 ]; then
        echo -e "${RED}Found $d_count Process(es) in D-State (Uninterruptible Sleep):${NC}"
        echo "PID    PPID   STAT USER   %CPU %MEM COMMAND"
        echo "$d_state"
        echo -e "\n${YELLOW}NOTE: D-State processes usually indicate disk/NFS I/O issues. They cannot be killed.${NC}"
    else
        print_status 0 "No processes in D-State."
    fi
}

# --- 5. Network RECV-Q > 0 ---
check_network_queues() {
    print_header "5. Network Socket Queues (RECV-Q > 0)"
    echo "Generated: $(date)"
        echo " "
    if command -v ss &> /dev/null; then
        local cmd="ss -tnlp"
    elif command -v netstat &> /dev/null; then
        local cmd="netstat -tnlp"
    else
        echo -e "${YELLOW}[WARNING]${NC} Neither ss nor netstat found."
        return
    fi

    # Parse output: Look for Recv-Q (Col 2 in ss, Col 3 in netstat) > 0
    # SS Format: State Recv-Q Send-Q Local:Port Peer:Port Process
    # Netstat Format: Proto Recv-Q Send-Q Local Address Foreign Address State PID/Program

    local found_queue=0
    echo "Checking for non-zero Receive Queues..."

    if command -v ss &> /dev/null; then
        local issues=$(ss -tnlp 2>/dev/null | awk 'NR>1 && $2 > 0 {print}')
    else
        local issues=$(netstat -tnlp 2>/dev/null | awk '$1 ~ /^tcp/ && $3 > 0 {print}')
    fi

    if [ -n "$issues" ]; then
        echo -e "${RED}Found connections with data waiting in receive queue:${NC}"
        echo "$issues"
        echo -e "\n${YELLOW}CAUSE: The application is not reading data from the socket fast enough.${NC}"
    else
        print_status 0 "No Listening connections with RECV-Q > 0 found."
    fi
}


# --- 6. DNS Resolution Time Check ---
check_dns_latency() {
    print_header "6. DNS Resolution Time Check"
    echo "Generated: $(date)"
        echo " "
    # Configuration
    local DNS_THRESHOLD=15  # Threshold in milliseconds
    local DOMAINS=("ckycvmdbscan.sbi" "edmsvmdbscan.sbi")
    local issue_found=0

    if ! command -v dig &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} 'dig' command not found. Please install bind-utils or dnsutils."
        return
    fi

    echo -e "Threshold: ${DNS_THRESHOLD}ms | Checking specific internal scan names...\n"
    printf "%-30s | %-10s | %-10s | Status\n" "Hostname" "IP Address" "Time(ms)"
    echo "---------------------------------------------------------------"

    for domain in "${DOMAINS[@]}"; do
        # Run dig and capture output
        # +tries=1 prevents hanging on bad DNS, +timeout=2 sets a 2s limit
        local result=$(dig +tries=1 +timeout=2 "$domain" 2>/dev/null)

        # Extract Query Time (usually the number before 'msec')
        local time_ms=$(echo "$result" | grep "Query time:" | awk '{print $4}')

        # Extract Answer IP (first A record found)
        local ip_addr=$(echo "$result" | grep -A1 "ANSWER SECTION" | tail -1 | awk '{print $5}')

        if [ -z "$time_ms" ]; then
            time_ms="TIMEOUT"
            local status="${RED}FAILED${NC}"
            issue_found=1
        elif [ "$time_ms" -gt "$DNS_THRESHOLD" ] 2>/dev/null; then
            local status="${RED}SLOW${NC}"
            issue_found=1
        else
            local status="${GREEN}OK${NC}"
        fi

        if [ -z "$ip_addr" ]; then ip_addr="NO_IP"; fi

        printf "%-30s | %-10s | %-10s | %b\n" "$domain" "$ip_addr" "$time_ms" "$status"
    done

    if [ $issue_found -eq 1 ]; then
        echo -e "\n${RED}ACTION: DNS resolution failed or exceeded ${DNS_THRESHOLD}ms threshold.${NC}"
        echo "Check /etc/resolv.conf and internal DNS server health."
    else
        echo -e "\n${GREEN}[OK]${NC} All DNS resolutions within acceptable limits.${NC}"
    fi
}


# --- 6. High System CPU Processes (Top 50) ---
check_high_sys_processes() {
    # Check if global sys_cpu variable is set from check_resources, otherwise calculate briefly
    local current_sys=${sys_cpu:-0}
    local sys_int=${current_sys%.*}

    # Only run if System CPU > Threshold (Default 30%)
    if [ "${sys_int:-0}" -le "$SYS_THRESHOLD" ]; then
        return 0
    fi

    print_header "6. Top 50 Processes Causing High System CPU (> ${SYS_THRESHOLD}%)"
    echo -e "${RED}ALERT: System CPU is at ${current_sys}%. Identifying kernel-heavy processes...${NC}\n"

    if ! command -v pidstat &> /dev/null; then
        echo -e "${YELLOW}[WARNING]${NC} pidstat not found. Install sysstat."
        return
    fi

    # Run pidstat for 1 iteration (snapshot)
    # We use awk to dynamically find the %system column index from the header
    # Typical columns: Time UID PID %usr %system %guest %wait %CPU CPU Command
    # %system is usually column 5, but we detect it to be safe.

    pidstat -u 1 1 2>/dev/null | awk -v thresh="$SYS_THRESHOLD" '
    BEGIN {
        red="\033[0;31m"; green="\033[0;32m"; nc="\033[0m";
        sys_col=0; header_printed=0; count=0;
    }
    /^Linux/ { next } # Skip version line
    /^Average:/ { next } # Skip average line if present
    /^Time/ {
        # Find column index for %system
        for(i=1; i<=NF; i++) {
            if($i == "%system") sys_col=i;
            if($i == "Command") cmd_col=i;
        }
        # Print custom header
        printf "%-10s %-8s %-8s %-8s %-8s %-8s %-6s %-6s %s\n", "Time", "UID", "PID", "%usr", "%system", "%CPU", "CPU", "Core", "Command"
        print "-----------------------------------------------------------------------------------------"
        next
    }
    {
        if(sys_col > 0 && $sys_col+0 > 0) {
            # Store line and sort value
            lines[NR] = $0
            vals[NR] = $sys_col+0
            count++
        }
    }
    END {
        # Simple bubble sort for top 50 (sufficient for snapshot)
        for(i=1; i<=count; i++) {
            for(j=i+1; j<=count; j++) {
                if(vals[i] < vals[j]) {
                    # Swap values
                    tmp = vals[i]; vals[i] = vals[j]; vals[j] = tmp;
                    # Swap lines
                    tmp = lines[i]; lines[i] = lines[j]; lines[j] = tmp;
                }
            }
        }
        # Print top 50
        limit = (count < 50) ? count : 50;
        for(i=1; i<=limit; i++) {
            # Only print if > 0.01% to avoid noise
            if(vals[i] > 0.01) {
                print lines[i]
            }
        }
    }'

    echo -e "\n${YELLOW}TIP: High %system indicates excessive syscalls, lock contention, or driver issues.${NC}"
}

# --- Main Execution ---
main() {
    clear
    echo -e "${BOLD}System Diagnostic Report${NC}"
    echo "Generated: $(date)"
    echo "Hostname: $(hostname)"
    check_root

    check_kernel_logs
    check_resources
    check_disk_latency
    check_process_states
    check_network_queues
    check_dns_latency
    check_high_sys_processes
    print_header "Diagnostic Complete"
}

main "$@"

