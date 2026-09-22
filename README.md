# Linu-Automation_Scripts
Shell Scripts in Linux
Script 1: app_to_db_connectivity.sh 
Task: It checks the connectivity from APP servers Public Ip to Oracle RAC DATABSE Servers Scan and Virtual Ips.

Script 2: oracle_RAC_health_check.sh
Task: Connects to all the node one by one via passwordless ssh via oracle user and collects data like CPU, Memory, 
Load Average, Uptime, Errors and services like auditd, rsyslog, crond, chronyd.

Script 3: process_capture.sh
Task: Captures Top 30 culprit processes whenever CPU or Memory Utilization breaches the Threshold of 70% along with 
D-state processes.

Script 4: realtime_health_checker.sh
Task: It was made to check the overall issue check at realtime. It checks CPU, Memory, Load Average, Disk latency,
RUN-Q, D-state and Zombie Processes in a affected server.

Script 5: services_check.sh
Task: MAde to check the important services in the service and start it in case of not running after OS Patching.
