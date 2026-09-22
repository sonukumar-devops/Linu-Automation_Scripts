#!/bin/bash

while true; do
echo "----------Mode Selection-------------"
echo "1) Check Compliance"
echo "2) Apply SCD"
echo "3) Exit"
echo "-------------------------------------"

read -rp "Enter your choice: " choice

case $choice in
1) mode="check"; break ;;
2) mode="apply"; break ;;
3) echo "Exiting..."; exit 0 ;;
*) echo "Invalid choice. Please select 1, 2 or 3 " ;;
esac
done

REPORT_FILE="/tmp/scd_compliance_report.txt"

# Print table header only if file doesn't exist
echo -e "+---------------\e[1m\e[32mSCD Compliance Report $(hostname -I | awk '{print $1}') ($(hostname))\e[0m--------------+\n" > "$REPORT_FILE"
echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
echo -e "|SCD Control|                               Check Name                         | Compliance       |" >> "$REPORT_FILE"
echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"



check_scd_2_1_1_and_2_15_1() {
echo -e "\n\e[35m[SCD 2.1.1] Disable unused filesystems and [SCD 2.15.1] Uncommon Network Protocols to be disabled\e[0m"

CONFIG_DIR="/etc/modprobe.d"
CONFIG_FILE="$CONFIG_DIR/CIS.conf"
MODULES=("dccp" "sctp" "rds" "tipc" "cramfs" "vfat" "squashfs" "udf" "usb-storage")

COMPLIANT="yes"

#check mode
if [[ "$mode" == "check" ]]; then

if [[ ! -f "$CONFIG_FILE" ]]; then
echo -e "\n\e[31m$CONFIG_FILE not found\e[0m".
COMPLIANT="no"
return
fi

echo -e "\n\e[33mScanning for Disabled Modules...\e[0m"

for modules in "${MODULES[@]}"; do

if ! grep -Eq -- "^install[[:space:]]+$modules[[:space:]]+/bin/true$" "$CONFIG_FILE" ; then
echo -e "\e[31mMissing or incorrect entry: $modules\e[0m"
COMPLIANT="no"
else

if grep -Eq -- "^install[[:space:]]{2,}$modules[[:space:]]+/bin/true$" "$CONFIG_FILE" || \
               grep -Eq -- "^install[[:space:]]+$modules[[:space:]]{2,}/bin/true$" "$CONFIG_FILE"; then
echo -e "\n\e[31mincorrect Spacing: $modules\e[0m"
            COMPLIANT="no"
        else
            echo -e "\e[32m$modules already Disabled.\e[0m"
        fi
        fi
        done
        fi
		
#apply mode		
if [[ "$mode" == "apply" ]]; then
# If the file doesn't exist, create it empty
[ ! -f "$CONFIG_FILE" ] && touch "$CONFIG_FILE"
echo -e "\e[31m$CONFIG_FILE was  missing ..\e[33m Created....\e[0m"

# First, normalize all lines that match the install pattern to have single spaces
sed -i -E 's|^install[[:space:]]+([^[:space:]]+)[[:space:]]+/bin/true$|install \1 /bin/true|' "$CONFIG_FILE"

# List of required modules to ensure they are present
required_modules=("dccp" "sctp" "rds" "tipc" "cramfs" "vfat" "squashfs" "udf" "usb-storage")

# Loop through required modules, add them if missing
for module in "${required_modules[@]}"; do
    if ! grep -Eq "^install[[:space:]]+$module[[:space:]]+/bin/true$" "$CONFIG_FILE"; then
		echo -e "\e[31m$module entry missing..\e[33m Adding..\e[0m"
        echo "install $module /bin/true" >> "$CONFIG_FILE"
        echo -e "\e[33mAdded missing entry for $module\e[0m"
		else
		echo -e "\e[32m$module entry Already Present..\e[0m"
    fi
done

echo -e "\e[33mCompleted spacing normalization and ensured all required modules are present.\e[0m"
fi

# Append result
  if [[ "$COMPLIANT" == "yes" ]]; then
    printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.1.1" "Disable unused filesystems" "Compliant" >> "$REPORT_FILE"
echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
    printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.1.1" "Uncommon Network Protocols to be disabled" "Compliant" >> "$REPORT_FILE"
else
    printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.15.1" "Disable unused filesystems" "Non-Compliant" >> "$REPORT_FILE"
echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
        printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.15.1" "Uncommon Network Protocols to be disabled" "Non-Compliant" >> "$REPORT_FILE"
fi

echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"

}
#=====================================================================================================
check_scd_2_1_3() { 
echo -e "\n\e[35m[SCD 2.1.3] Disable Automounting and USB Storage\e[0m"
COMPLIANT="yes"

if [[ "$mode" == "check" ]]; then
if systemctl is-enabled autofs &>/dev/null; then 
echo -e "\e[32mautofs service is Enabled.\e[0m" 
COMPLIANT="no"
else 
echo -e "\n\e[32mautofs service already disabled or Not found.\e[0m" 
fi
fi


if [[ "$mode" == "apply" ]]; then
if systemctl is-enabled autofs &>/dev/null; then 
echo -e "\e[32mautofs service is Enabled.\e[33m Disabling...\e[0m" 
systemctl --now disable autofs 
echo -e "\e[33mDisabled autofs service.\e[0m" 
else 
echo -e "\n\e[32mautofs service already disabled or Not found.\e[0m" 
fi
fi

# Append result
    if [[ "$COMPLIANT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.1.3" "Disable Automounting and USB Storage" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.1.3" "Disable Automounting and USB Storage" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}
#==========================================================================================================

check_scd_2_1_4() {
echo -e "\n\e[35m[SCD 2.1.4] Ensure sudo Log File Exists\e[0m"
COMPLIANT="yes"
SUDO_LOG_LINE='Defaults logfile="/var/log/sudo.log"'
SUDOERS_D_FILE="/etc/sudoers.d/logging"

#check mode
if [[ "$mode" == "check" ]]; then

if [[ ! -f "$SUDOERS_D_FILE" ]]; then
echo -e "\n\e[31mFile: $SUDOERS_D_FILE not found.\e[0m"
COMPLIANT="no"
return
fi
if grep -qF "$SUDO_LOG_LINE" "$SUDOERS_D_FILE" 2>/dev/null; then
echo -e "\e[32mSudo logging already configured in $SUDOERS_D_FILE\e[0m"
else
echo -e "\n\e[31mSudo logging line not present in $SUDOERS_D_FILE\e[0m"
COMPLIANT="no"
fi
fi
#apply mode
if [[ "$mode" == "apply" ]]; then
if [ ! -f "$SUDOERS_D_FILE" ]; then
echo -e "\n\e[31mFile: $SUDOERS_D_FILE not found.\e[33m Creating.../e[0m"
 touch "$SUDOERS_D_FILE"
echo "$SUDO_LOG_LINE" > "$SUDOERS_D_FILE"
chmod 440 "$SUDOERS_D_FILE"
echo -e "\e[33mAdded sudo logging line to $SUDOERS_D_FILE: $SUDO_LOG_LINE\e[0m"
else
if ! grep -qF "$SUDO_LOG_LINE" "$SUDOERS_D_FILE"; then
echo "$SUDO_LOG_LINE" >> "$SUDOERS_D_FILE"
echo -e "\e[33mAdded sudo logging line to $SUDOERS_D_FILE: $SUDO_LOG_LINE\e[0m"
else
echo -e "\e[32msudo logging line already present in $SUDOERS_D_FILE\e[0m"
fi
fi
fi

# Append result
    if [[ "$COMPLIANT" == "yes" ]]; then
        printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.1.4" "Ensure sudo Log File Exists" "Compliant" >> "$REPORT_FILE"
    else
        printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.1.4" "Ensure sudo Log File Exists" "Non-Compliant" >> "$REPORT_FILE"
    fi
        echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#=============================================================================================================

check_scd_2_2_2() {
echo -e "\n\e[35m[SCD 2.2.2] Ensure GPG Keys Are Configured\e[0m"
file="/etc/yum.conf"
COMPLAINT="yes"

#check mode
if [ "$mode" = "check" ]; then

if [[ ! -f "$file" ]]; then
echo -e "\n\e[31mFile: $file not found.\e[0m"
COMPLIANT="no"
return
fi
    count=$(grep -cE "^gpgcheck" "$file")

    # Case 1: More than 1 gpgcheck entry
    if (( count > 1 )); then
	echo -e "\n\e[31mMore than one entries are present\e[0m"
	COMPLAINT="no"
	
    # Case 2: Extra spaces before/after '='
    elif grep -Eq "^gpgcheck[[:space:]]+=[[:space:]]*[0-9]$" "$file" || \
         grep -Eq "^gpgcheck[[:space:]]*=[[:space:]]+[0-9]$" "$file"; then
		echo -e "\n\e[31mWrong Format present. Correction Required...\e[0m"
COMPLAINT="no"
    # Case 3: Correct format but incorrect value
    elif grep -Eq "^gpgcheck=0$" "$file"; then
	echo -e "\n\e[31mWrong Parameter present. Modification Required...\e[0m"
     COMPLAINT="no"
    # Case 4: No entry at all → insert it
    elif (( count == 0 )); then
	echo -e "\n\e[32mNo gpgcheck Entry Found..\e[0m"
COMPLAINT="no"
    else
        echo -e "\e[32mgpgcheck entry already correct.\e[0m"
    fi
fi

#apply mode

if [ "$mode" = "apply" ]; then

if [[ ! -f "$file" ]]; then
echo -e "\e[31mFile: $file not found.Manual Action needed.\e[0m"
return
fi
    count=$(grep -cE "^gpgcheck" "$file")

    # Case 1: More than 1 gpgcheck entry
    if (( count > 1 )); then
	echo -e "\e[31m more than one entries are present\e[0m"
	echo -e"\e[33mRemoving Multiple entries and keeping only one..\e[0m"
        sed -i -E '/^gpgcheck[[:space:]]*=/d' "$file"
        echo "gpgcheck=1" >> "$file"

    # Case 2: Extra spaces before/after '='
    elif grep -Eq "^gpgcheck[[:space:]]+=[[:space:]]*[0-9]$" "$file" || \
         grep -Eq "^gpgcheck[[:space:]]*=[[:space:]]+[0-9]$" "$file"; then
        sed -i -E 's/^gpgcheck[[:space:]]+=[[:space:]]*/gpgcheck=/; s/^gpgcheck=0$/gpgcheck=1/' "$file"
		echo -e "\e[31mWrong Format was present.\e[33m Correction done...\e[0m"

    # Case 3: Correct format but incorrect value
    elif grep -Eq "^gpgcheck=0$" "$file"; then
	sed -i -E 's/^gpgcheck=0$/gpgcheck=1/' "$file"
	echo -e "\e[31mWrong Value was set.\e[33m Modification done...\e[0m"
        

    # Case 4: No entry at all → insert it
    elif (( count == 0 )); then
	echo -e "\e[31mNo gpgcheck Entry Found.. Fixing...\e[0m"
        echo "gpgcheck=1" >> "$file"

    else
        echo -e "\e[32mgpgcheck entry already correct in $file\e[0m"
    fi
fi

# Append result
  if [[ "$COMPLAINT" == "yes" ]]; then
    printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.2.2" "Ensure GPG Keys Are Configured" "Compliant" >> "$REPORT_FILE"
else
    printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.2.2" "Ensure GPG Keys Are Configured" "Non-Compliant" >> "$REPORT_FILE"
fi

echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"

}

#=============================================================================================================

check_scd_2_30_3() {
    echo -e "\n\e[35m[SCD 2.30.3] Ensure gpgcheck Is Globally Enabled\e[0m"
COMPLAINT="yes"

#check mode
if [ "$mode" = "check" ]; then
    for file in /etc/yum.repos.d/*.repo; do
        echo -e "\nProcessing: $file"
        count=$(grep -cE "^gpgcheck" "$file")

        # Case 1: More than 1 gpgcheck entry
        if (( count > 2 )); then
            echo -e "\n\e[31mMultiple entries Present in $file\e[0m"
		COMPLAINT="no"
		
        # Case 2: Spaces before or after '='
        elif grep -Eq "^gpgcheck[[:space:]]*=[[:space:]]*[0-9]$" "$file" && \
             ! grep -Eq "^gpgcheck=[0-9]$" "$file"; then
            echo -e "\n\e[31mWrong Format of entries Present $file\e[0m"
		COMPLAINT="no"
		
        # Case 3: Correct format but incorrect value
        elif grep -Eq "^gpgcheck=0$" "$file"; then
           echo -e "\n\e[31mWrong Parameter value set in $file\e[0m"
		COMPLAINT="no"
		
        # Case 4: No entry at all → insert it
        elif (( count == 0 )); then
           echo -e "\n\e[31mMissing Entry in $file\e[0m"
           COMPLAINT="no"
        else
            echo -e "\e[32mgpgcheck already set correctly in $file\e[0m"
        fi
    done
fi

#apply mode

if [ "$mode" = "apply" ]; then
    for file in /etc/yum.repos.d/*.repo; do
        echo -e "\nProcessing: $file"
        count=$(grep -cE "^gpgcheck" "$file")

        # Case 1: More than 2 gpgcheck entry
        if (( count > 2 )); then
		echo -e "\e[31mMultiple entries Present.. Fixing\e[0m"
            sed -i -E '/^gpgcheck[[:space:]]*=/d' "$file"
			sed -i '/^[[:space:]]*enabled[[:space:]]*=[[:space:]]*1[[:space:]]*$/a gpgcheck=1' "$file"
		
           
        # Case 2: Spaces before or after '='
        elif grep -Eq "^gpgcheck[[:space:]]*=[[:space:]]*[0-9]$" "$file" && \
             ! grep -Eq "^gpgcheck=[0-9]$" "$file"; then
            sed -i -E 's/^gpgcheck[[:space:]]*=[[:space:]]*/gpgcheck=/; s/^gpgcheck=0$/gpgcheck=1/' "$file"
            echo -e "\e[32mFixed spacing and value\e[0m"

        # Case 3: Correct format but incorrect value
        elif grep -Eq "^gpgcheck=0$" "$file"; then
		 echo -e "\n\e[31mWrong value set in $file\e[33m Correcting..\e[0m"
            sed -i -E 's/^gpgcheck=0$/gpgcheck=1/' "$file"
          
			echo -e "\e[32mCorrected value to 1\e[0m"

        # Case 4: No entry at all ? insert it
        elif (( count == 0 )); then
            
			sed -i '/^[[:space:]]*#\?[[:space:]]*enabled[[:space:]]*=[[:space:]]*1[[:space:]]*$/a gpgcheck=1' "$file"
			sed -i '/repolist/a gpgcheck=1' "$file"  ## special case for redhat.repo file.
			
			echo -e "\e[33mAdded missing entry\e[0m"

        else
            echo -e "\e[32mCorrect entry Already Present\e[0m"
        fi
    done
fi

#=============================================================================================================

# Append result
  if [[ "$COMPLAINT" == "yes" ]]; then
    printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.30.3" "Ensure gpgcheck Is Globally Enabled" "Compliant" >> "$REPORT_FILE"
else
    printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.30.3" "Ensure gpgcheck Is Globally Enabled" "Non-Compliant" >> "$REPORT_FILE"
fi

echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"

}

#=============================================================================================================

check_scd_2_3_1() { 
echo -e "\n\e[35m[SCD 2.3.1] Ensure AIDE is Installed \e[0m"
COMPLAINT="yes"

if [ "$mode" = "check" ]; then
if ! rpm -q aide &>/dev/null; then 
echo -e "\n\e[31mAIDE is not installed!\e[0m" 
COMPLAINT="no"
else
echo -e "\e[32mAIDE is already installed...No action Required..\e[0m" 
fi
fi

if [ "$mode" = "apply" ]; then
if ! rpm -q aide &>/dev/null; then 
echo -e "\e[31mAIDE is not installed.\e[0m" 
echo -e "\e[33mAttempting Install.....\e[0m" 

yum install -y aide 

if ! rpm -q aide &>/dev/null; then 
echo -e "\e[31mInstallation Failed.(Repo not found or some other error occured.)\e[0m"
else
echo -e "\e[33mAIDE installed Successfully.\e[0m" 
fi

else 
echo -e "\e[32mAIDE is already installed...No action Required..\e[0m" 
fi
fi

# Append result
       if [[ "$COMPLAINT" == "yes" ]]; then
    printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.3.1" "Ensure AIDE is Installed" "Compliant" >> "$REPORT_FILE"
else
  printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.3.1" "Ensure AIDE is Installed" "Non-Compliant" >> "$REPORT_FILE"
	
fi
echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#=============================================================================================================

check_scd_2_30_5() { 
echo -e "\n\e[35m[SCD 2.30.5] Ensure Filesystem Integrity is Regularly Checked.\e[0m"
COMPLAINT="yes"
CRON_ENTRY="/usr/sbin/aide --check" 

if [ "$mode" = "check" ]; then
if crontab -l -u root 2>/dev/null | grep -q "$CRON_ENTRY"; then 
echo -e "\e[32mAIDE cron job already present...\e[0m" 
else 
echo -e "\n\e[31mAIDE cron job entry not present...\e[0m"
COMPLAINT="no"
fi
fi

if [ "$mode" = "apply" ]; then
if crontab -l -u root 2>/dev/null | grep -q "$CRON_ENTRY"; then 
echo -e "\e[32mAIDE cron job already present.\e[0m" 
else 
echo -e "\e[31mAIDE cron job entry not present.\e[33m Adding...\e[0m"
(crontab -l -u root 2>/dev/null; 
echo "0 5 * * * $CRON_ENTRY") | crontab -u root - 
echo -e "\e[33mAIDE cron job added: 0 5 * * * $CRON_ENTRY \e[0m"
fi
fi

# Append result
       if [[ "$COMPLAINT" == "yes" ]]; then
    printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.30.5" "Ensure Filesystem Integrity is Regularly Checked" "Compliant" >> "$REPORT_FILE"
else
  printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.30.5" "Ensure Filesystem Integrity is Regularly Checked" "Non-Compliant" >> "$REPORT_FILE"
	
fi
echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"

}

#=============================================================================================================

check_scd_2_4_1() {
  echo -e "\n\e[35m[SCD 2.4.1] Ensure Permissions on Bootloader Configs Are Configured\e[0m"
  COMPLAINT="yes"
  
 if [ "$mode" = "check" ]; then
for file in /boot/grub2/grubenv /boot/grub2/grub.cfg /boot/grub2/user.cfg; do
    if [ -f "$file" ]; then
      owner=$(stat -c "%U:%G" "$file")
      perms=$(stat -c "%a" "$file")
     
      if [[ "$owner" = "root:root" && "$perms" = "600" ]]; then
        echo -e "\e[32m$file already has correct ownership and permissions (root:root, 600)\e[0m"
      else
        echo -e "\n\e[31m$file does not have correct ownership and permissions (root:root, 600)\e[0m"
		COMPLAINT="no"
      fi
    else
      echo -e "\n\e[31m[WARN] $file not found.\e[0m"
	  COMPLAINT="no"
    fi
  done
  fi
  
  
   if [ "$mode" = "apply" ]; then
for file in /boot/grub2/grubenv /boot/grub2/grub.cfg /boot/grub2/user.cfg; do
    if [ -f "$file" ]; then
      owner=$(stat -c "%U:%G" "$file")
      perms=$(stat -c "%a" "$file")
     
      if [[ "$owner" = "root:root" && "$perms" = "600" ]]; then
        echo -e "\e[32m$file already has correct ownership and permissions (root:root, 600)\e[0m"
      else
        echo -e "\e[33mUpdating permissions and ownership for $file\e[0m"
        chown root:root "$file"
        chmod 600 "$file"
        echo -e "\e[33mPermissions has been set: $file owner=root:root, mode=600\e[0m"
      fi
    else
      echo -e "\n\e[31m[WARN] $file not found.\e[0m"
	  echo -e "\e[33m Creating $file and giving appropriate permission\e[0m"
	  touch "$file"
	  chown root:root "$file"
      chmod 600 "$file"
	  echo -e "\e[33m Created $file and permission set\e[0m"
    fi
  done
  fi
  
  # Append result
    if [[ "$COMPLAINT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.4.1" "Ensure Permissions on Bootloader Are Configured" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.4.1" "Ensure Permissions on Bootloader Are Configured" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#===================================================================================================================================

check_scd_2_5_1() {
  echo -e "\n\e[35m[SCD 2.5.1] Apply Process Hardening\e[0m"
  COMPLAINT="yes"
  
 
file="/etc/security/limits.conf"
correct="* hard core 0"

declare -A proc_params=(

  ["fs.suid_dumpable"]="0"
  ["kernel.randomize_va_space"]="2"
)

if [ "$mode" = "check" ]; then
# Case 1: Wrong format exists
if grep -Eq '^\*[[:space:]]*hard[[:space:]]+core[[:space:]]+0$' "$file" | grep -Eq '^\*[[:space:]]+hard[[:space:]]+core[[:space:]]*0$' "$file" && \
   ! grep -Eq '^\* hard core 0$' "$file"; then
    echo -e "\n\e[31mWrong format entry found.\e[0m"
	COMPLAINT="no"
	
# Case 2: Entry missing entirely
elif ! grep -Eq '^\* hard core 0$' "$file"; then
    echo -e "\n\e[31mCorrect entry: '* hard core 0' not found.\e[0m"
COMPLAINT="no"

else
    echo -e "\e[32mEntry: '* hard core 0' already correct.\e[0m"
fi

####
#check mode for /etc/sysctl.conf

for key in "${!proc_params[@]}"; do
    value="${proc_params[$key]}"
    
    # Check if the exact line already exists
    if  grep -qE "^${key}([[:space:]]{0}|[[:space:]]{2,})=[[:space:]]*${value}$" /etc/sysctl.conf; then
   
        echo -e "\n\e[31m[$key] not correctly configured as $value.\e[0m"
		COMPLAINT="no"
		
		elif grep -qE "^${key}[[:space:]]*=([[:space:]]{0}|[[:space:]]{2,})${value}$" /etc/sysctl.conf; then
		echo -e "\n\e[31m[$key] not correctly configured as $value.\e[0m"
		COMPLAINT="no"
		
		elif ! grep -Eq "^${key}[[:space:]]*=[[:space:]]*${value}$" /etc/sysctl.conf; then
		echo -e "\n\e[31mNo entry found as [$key] = $value. or wrong value set\e[0m"
		COMPLAINT="no"
    else
	echo -e "\e[32m[$key] Already configured correctly as $value.\e[0m"
	
	  fi
	  
done

#prelink

if rpm -q prelink &>/dev/null; then 
echo -e "\e[32mprelink is already installed.  \e[0m"
COMPLAINT="no"
else
echo -e "\e[32mprelink not installed as Expected.  \e[0m"
fi
fi


if [ "$mode" = "apply" ]; then

cp "$file" "$file.bak_$(date +%F_%T)"
echo -e "\e[33mBackup of $file taken as $file.bak_$(date +%F_%T)\e[0m"
# Case 1: Correcting Wrong format if exists
if grep -Eq '^\*[[:space:]]*hard[[:space:]]+core[[:space:]]+0$' "$file" | grep -Eq '^\*[[:space:]]+hard[[:space:]]+core[[:space:]]*0$' "$file" && \
   ! grep -Eq '^\* hard core 0$' "$file"; then
    echo -e "\e[31mWrong format entry found.\e[33mCorrecting...\e[0m"
    # Remove all wrong * hard core lines
    sed -i -E '/^\*[[:space:]]*hard[[:space:]]+core[[:space:]]+0$/d' "$file"
	sed -i -E '/^\*[[:space:]]+hard[[:space:]]+core[[:space:]]*0$/d' "$file"
    echo "$correct" >> "$file"
	echo -e "\e[33mCorrection Done...\e[0m"
	
	# Case 2: Entry missing entirely, Putting new one
	elif ! grep -Eq '^\* hard core 0$' "$file"; then
    echo -e "\e[31mCorrect entry: '* hard core 0' not found. \e[33mAdding it.\e[0m"
    echo "$correct" >> "$file"
	else
    echo -e "\e[32mEntry: '* hard core 0' already correct.\e[0m"
fi

###
echo -e "\e[33mChecking Parameters in sysctl.conf \e[0m"

# Backup
	 cp /etc/sysctl.conf /etc/sysctl.conf.bak_$(date +%F_%T)
     echo -e "\e[33mBackup of /etc/sysctl.conf created as /etc/sysctl.conf.bak_$(date +%F_%T)\e[0m"

for key in "${!proc_params[@]}"; do
    value="${proc_params[$key]}"
	
# Check if the exact line already exists in /etc/sysctl.conf
    if  grep -qE "^${key}[[:space:]]{2,}=[[:space:]]*${value}$" /etc/sysctl.conf; then
	 	echo -e "\e[31mWrong format entry found.\e[33mCorrecting...\e[0m" 
	 #remove wrong line
	  sed -i "/^[[:space:]]*${key}[[:space:]]*=/d" /etc/sysctl.conf
	  # Append correct entry
	  echo "$key = $value" >> /etc/sysctl.conf
	  echo -e "\e[33m[$key] entry added/updated to $value.\e[0m"
	  
	  sysctl -p > /dev/null 2>&1
	elif grep -qE "^${key}[[:space:]]*=[[:space:]]{2,}${value}$" /etc/sysctl.conf; then
	  echo -e "\e[31mWrong format entry found.\e[33mCorrecting...\e[0m"
	  #remove wrong line
	sed -i "/^[[:space:]]*${key}[[:space:]]*=/d" /etc/sysctl.conf
	
	# Append correct entry
        echo "$key = $value" >> /etc/sysctl.conf
	echo -e "\e[33m[$key] entry added/updated to $value.\e[0m"
	
	sysctl -p > /dev/null 2>&1
	elif ! grep -Eq "^${key}[[:space:]]*=[[:space:]]*${value}$" /etc/sysctl.conf; then
        # Append missing entry
		
		 echo -e "\e[31m No entry found as [$key] = $value or wrong value set.\e[0m"
		 sed -i "/^[[:space:]]*${key}[[:space:]]*=/d" /etc/sysctl.conf
        echo "$key = $value" >> /etc/sysctl.conf
		sysctl -p > /dev/null 2>&1
    echo -e "\e[33mEntry Added...\e[0m"
	else 
	 echo -e "\e[32m[$key] already correctly configured as $value.\e[0m"
    fi
done

#prelink

if rpm -q prelink &>/dev/null; then 
echo -e "\e[33mprelink is installed. Restoring and removing... \e[0m" 
prelink -ua 
yum remove -y prelink 
echo -e "\e[33mprelink removed. \e[0m" 
else 
echo -e "\e[32mprelink is not installed as expected.\e[0m" 
fi 
fi


  # Append result
    if [[ "$COMPLAINT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.5.1" "Apply Process Hardening" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.5.1" "Apply Process Hardening" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#===================================================================================================================================

check_scd_2_6_1() {
    echo -e "\n\e[35m[SCD 2.6.1] Configure AppArmor / Audit MAC Policy Monitoring\e[0m"
COMPLAINT="yes"
CHANGED=false
    AUDIT_RULES_FILE="/etc/audit/rules.d/audit.rules"
    REQUIRED_RULES=(
        "-w /etc/selinux/ -p wa -k MAC-policy"
        "-w /usr/share/selinux/ -p wa -k MAC-policy"
    )

if [ "$mode" = "check" ]; then
    for rule in "${REQUIRED_RULES[@]}"; do
        # Sanitize and normalize the rule
        clean_rule=$(echo "$rule" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/–/-/g')
        
        # Escape for grep: remove leading dashes confusion
        if grep -Fq -- "$clean_rule" "$AUDIT_RULES_FILE"; then
            echo -e "\e[32mRule already exists \e[0m: $clean_rule"
        else
		echo -e "\n\e[31mRule doesn't exist.. \e[0m: $clean_rule"
		COMPLAINT="no"
		fi
		
		done
		fi

	if [ "$mode" = "apply" ]; then
		 cp /etc/audit/rules.d/audit.rules /etc/audit/rules.d/audit.rules.bak_$(date +%F_%T)
      echo -e "\e[33mBackup of /etc/audit/rules.d/audit.rules created as /etc/audit/rules.d/audit.rules.bak_$(date +%F_%T)\e[0m"
		 for rule in "${REQUIRED_RULES[@]}"; do
        # Sanitize and normalize the rule
        clean_rule=$(echo "$rule" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/–/-/g')
        
        # Escape for grep: remove leading dashes confusion
        if grep -Fq -- "$clean_rule" "$AUDIT_RULES_FILE"; then
            echo -e "\e[32mRule already exists \e[0m: $clean_rule"
        else
		echo -e "\e[31mRule doesn't exist.. \e[0m: $clean_rule \e[33mAdding...."
		
            echo "$clean_rule" >> "$AUDIT_RULES_FILE"
            echo -e "\e[33mRule added\e[0m: $clean_rule"
            CHANGED=true
        fi
    done
	fi

    if [ "$CHANGED" = true ]; then
        echo -e "\e[33mRestarting auditd to apply changes...\e[0m"
        if systemctl is-enabled auditd &>/dev/null; then
            systemctl restart auditd 2>/dev/null || service auditd restart 2>/dev/null
        else
            echo -e "\e[31mAuditd is not enabled on this system. Kindly Check Manually\e[0m"
        fi
    fi


	# Append result
    if [[ "$COMPLAINT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.6.1" "Configure AppArmor" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.6.1" "Configure AppArmor" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
	}

	#===================================================================================================================================

	check_scd_2_7_1() {
    echo -e "\n\e[35m[SCD 2.7.1] Set GNOME Warning Banner\e[0m"
	COMPLAINT="yes"
    GDM_DIR="/etc/dconf/db/gdm.d"
    BANNER_FILE="$GDM_DIR/01-banner-message"
    SECTION="[org/gnome/login-screen]"
    ENABLE_LINE="banner-message-enable=true"
    TEXT_LINE="banner-message-text='Authorized uses only. All activity may be monitored and reported.'"
    CHANGED=false
    

# Check mode
if [ "$mode" = "check" ]; then

 # Ensure the Directory exists
 if [ ! -d "$GDM_DIR" ]; then
 echo -e "\n\e[31mDirectory: $GDM_DIR not found.\e[0m"
COMPLAINT="no"

 elif [ -d "$BANNER_FILE" ]; then
        echo -e "\n\e[31mFile: $BANNER_FILE is a directory. It should be a file. Removal required\e[0m"
		COMPLAINT="no"

# Ensure the file exists
    elif [ ! -f "$BANNER_FILE" ]; then
        echo -e "\n\e[31mFile: $BANNER_FILE not found.\e[0m"
		COMPLAINT="no"

elif ! grep -Fxq "$SECTION" "$BANNER_FILE"; then
echo -e "\n\e[31mlogin-screen section Missing \e[0m"
COMPLAINT="no"

elif ! grep -Fxq "$ENABLE_LINE" "$BANNER_FILE"; then
echo -e "\n\e[31m$ENABLE_LINE Missing.. \e[0m"
COMPLAINT="no"

elif ! grep -Fxq "$TEXT_LINE" "$BANNER_FILE"; then
echo -e "\n\e[31m$TEXT_LINE Missing.. \e[0m"
COMPLAINT="no"

else
        echo -e "\e[32m $SECTION already present \e[0m"
		echo -e "\e[32m $ENABLE_LINE already present \e[0m"
		echo -e "\e[32m $TEXT_LINE already present \e[0m"
fi
fi

#Apply Mode
if [ "$mode" = "apply" ]; then

if [ ! -d "$GDM_DIR" ]; then
        echo -e "\e[31mDirectory $GDM_DIR not found.\e[33mCreating...\e[0m"
		
        mkdir -p "$GDM_DIR"
		echo -e "\e[33mDirectory $GDM_DIR Created...\e[0m"
		echo -e "\e[31mFile $BANNER_FILE not found.\e[33mCreating...\e[0m"
		
        touch "$BANNER_FILE"
		echo -e "\e[33mFile $BANNER_FILE Created...\e[0m"
		echo "$SECTION" >> "$BANNER_FILE"
        echo -e "\e[33mAdded section\e[0m: $SECTION"
		echo "$ENABLE_LINE" >> "$BANNER_FILE"
        echo -e "\e[33mAdded line\e[0m: $ENABLE_LINE"
		echo "$TEXT_LINE" >> "$BANNER_FILE"
        echo -e "\e[33mAdded line\e[0m: $TEXT_LINE"
		CHANGED=true
		
# Ensure file exists not as directory	
	
 elif [ -d "$BANNER_FILE" ]; then
        echo -e "\n\e[31mFile: $BANNER_FILE is a directory.\e[33mRemoving...\e[0m"
		rm -rf "$BANNER_FILE"
		echo -e "\n\e[33mDirectory: $BANNER_FILE Removed.\e[0m"
		
    # Ensure file exists
    elif [ ! -f "$BANNER_FILE" ]; then
        echo -e "\e[31mFile $BANNER_FILE not found.\e[33mCreating...\e[0m"
		
        touch "$BANNER_FILE"
		echo -e "\e[33mFile $BANNER_FILE Created...\e[0m"
		echo "$SECTION" >> "$BANNER_FILE"
        echo -e "\e[33mAdded section\e[0m: $SECTION"
		echo "$ENABLE_LINE" >> "$BANNER_FILE"
        echo -e "\e[33mAdded line\e[0m: $ENABLE_LINE"
		echo "$TEXT_LINE" >> "$BANNER_FILE"
        echo -e "\e[33mAdded line\e[0m: $TEXT_LINE"
		CHANGED=true

    # Ensure section exists
    elif ! grep -Fxq "$SECTION" "$BANNER_FILE"; then
		echo -e "\e[31mSection: $SECTION not found.\e[33mAdding...\e[0m"
		echo "$SECTION" >> "$BANNER_FILE"
        echo -e "\e[33mAdded section\e[0m: $SECTION"
		echo "$ENABLE_LINE" >> "$BANNER_FILE"
        echo -e "\e[33mAdded line\e[0m: $ENABLE_LINE"
		echo "$TEXT_LINE" >> "$BANNER_FILE"
        echo -e "\e[33mAdded line\e[0m: $TEXT_LINE"
		CHANGED=true
        
    # Ensure enable line exists
    elif ! grep -Fxq "$ENABLE_LINE" "$BANNER_FILE"; then
	echo -e "\e[31mline: $ENABLE_LINE not found.\e[33mAdding...\e[0m"
        echo "$ENABLE_LINE" >> "$BANNER_FILE"
        echo -e "\e[33mAdded line\e[0m: $ENABLE_LINE"
		 echo "$TEXT_LINE" >> "$BANNER_FILE"
        echo -e "\e[33mAdded line\e[0m: $TEXT_LINE"
		CHANGED=true
        
    # Ensure text line exists
    elif ! grep -Fxq "$TEXT_LINE" "$BANNER_FILE"; then
	echo -e "\e[31mLine: $TEXT_LINE not found.\e[33mAdding...\e[0m"
        echo "$TEXT_LINE" >> "$BANNER_FILE"
        echo -e "\e[33mAdded line\e[0m: $TEXT_LINE"
		
        CHANGED=true
    else
        echo -e "\e[32mEverything already present as required. \e[0m"
    fi

   # Apply changes
    if [ "$CHANGED" = true ]; then
        echo -e "\e[33mRunning 'dconf update' to apply changes...\e[0m"
        dconf update
    else
        echo -e "\e[32mGNOME warning banner already configured correctly.\e[0m"
    fi
	fi
	
	# Append result
   if [[ "$COMPLAINT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.7.1" "Set GNOME Warning Banner" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.7.1" "Set GNOME Warning Banner" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#=======================================================================================================================================

check_scd_2_8_1() {
    echo -e "\n\e[35m[SCD 2.8.1] Ensure xinetd is Not Installed\e[0m"
COMPLAINT="yes"
    # Check mode
if [ "$mode" = "check" ]; then
 if rpm -q xinetd &>/dev/null; then
        echo -e "\e[31mxinetd is installed. \e[0m"
		COMPLAINT="no"

else
        echo -e "\e[32mxinetd is not installed as expected.\e[0m"
fi
fi

#Apply Mode
if [ "$mode" = "apply" ]; then
if rpm -q xinetd &>/dev/null; then
        echo -e "\e[31mxinetd is installed. \e[33mRemoving...\e[0m"
        yum remove -y xinetd && echo -e "\e[33mxinetd removed successfully.\e[0m" || echo -e "\e[31mFailed to remove xinetd. Please Remove it Manually. \e[0m"

else
        echo -e "\e[32mxinetd is not installed as expected.\e[0m"
    fi

fi

	# Append result
   if [[ "$COMPLAINT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.8.1" "Ensure xinetd is Not Installed" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.8.1" "Ensure xinetd is Not Installed" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}
#=======================================================================================================================================


check_scd_2_9_1_and_2_30_2() {
    echo -e "\n\e[35m[SCD 2.9.1 and 2.30.2] Disable Non-Essential Services and Disable the rhnsd Daemon\e[0m"
COMPLAINT="yes"

# Check mode
if [ "$mode" = "check" ]; then

 # Step 1: Check for X Windows packages (xserver-xorg*)
    echo -e "Checking for xserver-xorg* packages...\n"
    if rpm -qa | grep -q '^xorg-x11-server-*'; then
        echo -e "\e[31mxserver-xorg packages found.\e[0m"
		COMPLAINT="no"
		 else
        echo -e "\e[32mxserver-xorg* packages not installed.\e[0m"
    fi

 # Step 2: Disable all listed non-essential services
    SERVICES=(
        avahi-daemon
        cups
        isc-dhcp-server
        isc-dhcp-server6
        slapd
        nfs-kernel-server
        rpcbind
        bind9
        vsftpd
        apache2
        dovecot
        smbd
        squid
        snmpd
        rsync
        nis
		rhnsd
    )

       for service in "${SERVICES[@]}"; do
    if systemctl list-unit-files --type=service | grep -q "^$service.service"; then
        echo -e "\e[31mService found: $service\e[0m"
        
        # Check if active
        if systemctl is-active --quiet "$service"; then
            echo -e "Status $service: \e[31mActive (running)\e[0m"
			COMPLAINT="no"
        else
            echo -e "Status $service: \e[32mInactive (not running)\e[0m"
        fi

        # Check if enabled
        if systemctl is-enabled --quiet "$service"; then
            echo -e "Startup: \e[31mEnabled (will start at boot)\e[0m"
			COMPLAINT="no"
        else
            echo -e "Startup: \e[32mDisabled (will not start at boot)\e[0m"
        fi

    else
        echo -e "\e[32mService not found (not installed): $service\e[0m"
    fi
done
	
fi


#Apply Mode
if [ "$mode" = "apply" ]; then
# Step 1: Remove X Windows packages if found.(xserver-xorg*)
    echo -e "Checking for xserver-xorg* packages...\n"
    if rpm -qa | grep -q '^xorg-x11-server-*'; then
        echo -e "\e[33mxserver-xorg packages found. \e[33mRemoving...\e[0m"
        yum remove -y xorg-x11-server-* && echo -e "\e[33mxserver-xorg* packages removed.\e[0m" || echo -e "\e[31mFailed to remove xserver-xorg* packages. Kindly remove it Manually\e[0m"
    else
        echo -e "\e[32mxserver-xorg* packages not installed.\e[0m"
    fi

	# Step 2: Disable all listed non-essential services
    SERVICES=(
        avahi-daemon
        cups
        isc-dhcp-server
        isc-dhcp-server6
        slapd
        nfs-kernel-server
        rpcbind
        bind9
        vsftpd
        apache2
        dovecot
        smbd
        squid
        snmpd
        rsync
        nis
		rhnsd
    )

   for service in "${SERVICES[@]}"; do
    if systemctl list-unit-files --type=service | grep -q "^$service.service"; then
        echo -e "\e[31mService found: $service\e[0m"
        
        # Check if active
        if systemctl is-active --quiet "$service"; then
            echo -e "Status $service: \e[31mActive (running)..\e[33mStop process initiated\e[0m"
			systemctl stop "$service" &>/dev/null
			 echo -e "\e[33mStopped : $service\e[0m"
			
        else
            echo -e "Status $service: \e[32mInactive (not running)\e[0m"
        fi

        # Check if enabled
        if systemctl is-enabled --quiet "$service"; then
            echo -e "Startup $service: \e[31mEnabled (will start at boot)\e[33mDisable process initiated\e[0m"
			systemctl disable "$service" &>/dev/null
			echo -e "\e[33mDisabled : $service\e[0m"
        else
            echo -e "Startup $service: \e[32mAlready Disabled (will not start at boot)\e[0m"
        fi

    else
        echo -e "\e[32mService not found (not installed): $service\e[0m"
    fi
done
	
	
fi
	
	# Append result
   if [[ "$COMPLAINT" == "yes" ]]; then
    printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.9.1" "Disable Non-Essential Services" "Compliant" >> "$REPORT_FILE"
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
    printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.30.2" "Disable the rhnsd Daemon" "Compliant" >> "$REPORT_FILE"
else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.9.1" "Disable Non-Essential Services" "Non-Compliant" >> "$REPORT_FILE"
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
    printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.30.2" "Disable the rhnsd Daemon" "Non-Compliant" >> "$REPORT_FILE"
fi

echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}


#=======================================================================================================================================

check_scd_2_9_2() {
    echo -e "\n\e[35m[SCD 2.9.2] NTP/Chrony Configuration\e[0m"
	COMPLAINT="yes"
	
	
	# Check mode
if [ "$mode" = "check" ]; then

if rpm -q chrony &>/dev/null; then
        echo -e "\e[32mChrony is installed.\e[0m"

        # Check if chronyd is running as 'chrony' user
        if pgrep -u chrony chronyd &>/dev/null; then
            echo -e "\e[32mchronyd is running as 'chrony' user.\e[0m"
        else
            echo -e "\e[31mchronyd is not running as 'chrony' user or not running.\e[0m"
			COMPLAINT="no"
        fi

        # Start chronyd if not running
        if ! systemctl is-active --quiet chronyd; then
            echo -e "\e[31mchronyd service is not active.\e[0m"
			COMPLAINT="no"
        else
            echo -e "\e[32mchronyd service is already active and Running.\e[0m"
        fi

    elif rpm -q ntp &>/dev/null; then
        echo -e "\e[32mNTP is installed.\e[0m"

        # Check if ntpd is running as 'ntp' user
        if pgrep -u ntp ntpd &>/dev/null; then
            echo -e "\e[32mntpd is running as 'ntp' user.\e[0m"
        else
            echo -e "\e[31mntpd is not running as 'ntp' user or not running.\e[0m"
			COMPLAINT="no"
        fi

        # Start ntpd if not running
        if ! systemctl is-active --quiet ntpd; then
            echo -e "\e[31mntpd service is not active.\e[0m"
            
			COMPLAINT="no"
        else
            echo -e "\e[32mntpd service is already active and Running.\e[0m"
        fi

    else
        echo -e "\e[31mNeither chrony nor ntp is installed.\e[0m"
		COMPLAINT="no"
    fi

fi


#Apply Mode
if [ "$mode" = "apply" ]; then
	
    if rpm -q chrony &>/dev/null; then
        echo -e "\e[32mChrony is installed.\e[0m"

        # Check if chronyd is running as 'chrony' user
        if pgrep -u chrony chronyd &>/dev/null; then
            echo -e "\e[32mchronyd is running as 'chrony' user.\e[0m"
        else
            echo -e "\e[31mchronyd is not running as 'chrony' user or not running.\e[0m"
        fi

        # Start chronyd if not running
        if ! systemctl is-active --quiet chronyd; then
            echo -e "\e[31mchronyd service is not active. \e[33mStarting...\e[0m"
            systemctl start chronyd && echo -e "\e[33mchronyd started.\e[0m" || echo -e "\e[31mFailed to start chronyd. Kindly start it Manually\e[0m"
        else
            echo -e "\e[32mchronyd service is already active and Running.\e[0m"
        fi

    elif rpm -q ntp &>/dev/null; then
        echo -e "\e[32mNTP is installed.\e[0m"

        # Check if ntpd is running as 'ntp' user
        if pgrep -u ntp ntpd &>/dev/null; then
            echo -e "\e[32mntpd is running as 'ntp' user.\e[0m"
        else
            echo -e "\e[31mntpd is not running as 'ntp' user or not running.\e[0m"
        fi

        # Start ntpd if not running
        if ! systemctl is-active --quiet ntpd; then
            echo -e "\e[31mntpd service is not active. \e[33mStarting...\e[0m"
            systemctl start ntpd && echo -e "\e[32mntpd started.\e[0m" || echo -e "\e[31mFailed to start ntpd.\e[0m"
        else
            echo -e "\e[32mntpd service is already active and Running.\e[0m"
        fi

    else
        echo -e "\e[31mNeither chrony nor ntp is installed. Manual Action Needed\e[0m"
    fi
	fi
	
	# Append result
     if [[ "$COMPLAINT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.9.2" "NTP/Chrony Configuration" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.9.2" "NTP/Chrony Configuration" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#=======================================================================================================================================

check_scd_2_10_1_and_2_12_1() {
    echo -e "\n\e[35m[SCD 2.10.1] Service Clients and [SCD 2.12.1] Network Parameters\e[0m"
	COMPLAINT="yes"
	
#Check Mode
	if [ "$mode" = "check" ]; then
    for pkg in ypbind talk telnet openldap-clients nis rsh-client ldap-utils; do
        if rpm -q "$pkg" &>/dev/null; then
            echo -e "\e[31mPackage '$pkg' is installed.\e[0m"
			COMPLAINT="no"
        else
            echo -e "\e[32m Package '$pkg' is not installed. Skipping...\e[0m"
        fi
    done
	fi
	
#Apply Mode
if [ "$mode" = "apply" ]; then
    for pkg in ypbind talk telnet openldap-clients nis rsh-client ldap-utils; do
        if rpm -q "$pkg" &>/dev/null; then
            echo -e "\e[31mPackage '$pkg' is installed. \e[33mRemoving...\e[0m"
            yum remove -y "$pkg" && echo -e "\e[33mSuccessfully removed '$pkg' \e[0m" || echo -e "\e[31mFailed to remove '$pkg' .Kindly Remove Manually\e[0m"
        else
            echo -e "\e[32m Package '$pkg' is not installed. Skipping...\e[0m"
        fi
    done

fi


	# Append result
     if [[ "$COMPLAINT" == "yes" ]]; then
    printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.10.1" "Service Clients" "Compliant" >> "$REPORT_FILE"
echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
    printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.12.1" "Network Parameters" "Compliant" >> "$REPORT_FILE"
else
   printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.10.1" "Service Clients" "Non-Compliant" >> "$REPORT_FILE"
echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
    printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.12.1" "Network Parameters" "Non-Compliant" >> "$REPORT_FILE"
fi

echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}


#=======================================================================================================================================

check_scd_2_11_1() {
    echo -e "\n\e[35m[SCD 2.11.1] Remove Legacy Services\e[0m"
	COMPLAINT="yes"
	
	
# Legacy services list
    services=(
        "squid"      # HTTP proxy server
        "smb"        # Samba
        "dovecot"    # IMAP/POP3
        "pop3"       # POP3
        "httpd"      # HTTP server
        "vsftpd"     # FTP server
        "bind"       # DNS server
        "named"      # DNS server
        "nfs-server" # NFS
        "rpcbind"    # RPC
        "slapd"      # LDAP server
        "nslcd"      # LDAP client
    )
	
	#Check Mode
	if [ "$mode" = "check" ]; then

    for svc in "${services[@]}"; do
        # Check if the service is installed
        if systemctl list-unit-files | grep -q "^$svc"; then
            # Check if it's enabled
            if systemctl is-enabled "$svc" &>/dev/null; then
                echo -e "\n\e[31mService $svc is enable.\e[0m"
				COMPLAINT="no"
            else
                echo -e "\n\e[32mService $svc already disabled.\e[0m"
            fi
        else
            echo -e "\n\e[32mService $svc not installed.\e[0m"
        fi
    done

    # Legacy protocols to disable
    protocols=("dccp" "sctp" "rds" "tipc")
	echo -e "\e[33mChecking for Legacy Protocols...\e[0m"
    for proto in "${protocols[@]}"; do
        if lsmod | grep -q "^$proto"; then
            echo -e "\n\e[31mLegacy  protocol $proto present (not blocked)\e[0m"
			COMPLAINT="no"
           else
		   echo -e "\n\e[32mLegacy  protocol $proto Not present/loaded(SAFE)\e[0m"
        fi

    done
	
	fi
	
	#Apply Mode
if [ "$mode" = "apply" ]; then

for svc in "${services[@]}"; do
        # Check if the service is installed
        if systemctl list-unit-files | grep -q "^$svc"; then
            # Check if it's enabled
            if systemctl is-enabled "$svc" &>/dev/null; then
			echo -e "\e[31mService $svc is enable.\e[0m"
                echo -e "\e[33mDisabling legacy service\e[0m: $svc"
                systemctl disable "$svc" &>/dev/null
                echo -e "\e[32mService $svc disabled.\e[0m"
            else
                echo -e "\e[32mService $svc already disabled.\e[0m"
            fi
        else
            echo -e "\e[32mService $svc not installed.\e[0m"
        fi
    done

    # Legacy protocols to disable
    protocols=("dccp" "sctp" "rds" "tipc")
echo -e "\n\e[33mChecking for Legacy Protocols...\e[0m"
    for proto in "${protocols[@]}"; do
        if lsmod | grep -q "^$proto"; then
		echo -e "\n\e[31mLegacy  protocol $proto present (not blocked)\e[0m"
            echo -e "\e[33mUnloading and disabling protocol\e[0m: $proto"
            modprobe -r "$proto"
			echo -e "\e[33mProtocol: $proto Unloaded and disabled\e[0m: "
			else
		   echo -e "\n\e[32mLegacy  protocol $proto Not present/loaded(SAFE)\e[0m"
        fi

        # Block loading permanently
        if ! grep -q "install $proto /bin/true" /etc/modprobe.d/CIS.conf 2>/dev/null; then
           
			cp /etc/modprobe.d/CIS.conf /etc/modprobe.d/CIS.conf.bak_$(date +%F_%T)
			echo -e "\e[33mBackup of /etc/modprobe.d/CIS.conf created as /etc/modprobe.d/CIS.conf.bak_$(date +%F_%T)\e[0m"
			echo -e "\n\e[33mBlocking $proto module permanently.\e[0m"
			echo "install $proto /bin/true" >> /etc/modprobe.d/CIS.conf
			echo -e "\e[33m$proto module blocked permanently.\e[0m"
        else
            echo -e "\n\e[32mProtocol $proto already blocked.\e[0m"
        fi
    done

fi

	
	# Append result
   if [[ "$COMPLAINT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.11.1" "Remove Legacy Services" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.11.1" "Remove Legacy Services" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#=======================================================================================================================================

check_scd_2_13_1_and_2_27_2() {
    echo -e "\n\e[35m[SCD 2.13.1 and 2.27.2] Network Configuration (IPv6)\e[0m"
    COMPLAINT="yes"
    declare -A ipv6_params=(
        ["net.ipv6.conf.all.accept_ra"]="0"
        ["net.ipv6.conf.all.accept_redirects"]="0"
        ["net.ipv6.conf.default.accept_ra"]="0"
        ["net.ipv6.conf.default.accept_redirects"]="0"
        ["net.ipv6.conf.all.disable_ipv6"]="1"
    )

    
#Check Mode
	if [ "$mode" = "check" ]; then
	
	for param in "${!ipv6_params[@]}"; do
        value="${ipv6_params[$param]}"

        # Check current setting in sysctl.conf (strip spaces around =)
        current=$(grep -E "^\s*${param}\s*=" /etc/sysctl.conf | tail -n 1 | awk -F= '{gsub(/ /,"",$2); print $2}')
        
        if [[ "$current" == "$value" ]]; then
            echo -e "\e[32mAlready set:\e[0m $param = $value"
        else
            # Remove any existing lines for this param
            echo -e "\e[31Value missing or set incorrectly:\e[0m $param = $value"
	COMPLAINT="no"
        fi
    done
	fi
	
#Apply Mode
if [ "$mode" = "apply" ]; then
cp /etc/sysctl.conf /etc/sysctl.conf.bak_$(date +%F_%T)
echo -e "\e[33mBackup of /etc/sysctl.conf created as /etc/sysctl.conf/sysctl.conf.bak_$(date +%F_%T)\e[0m"
local changed=0
 for param in "${!ipv6_params[@]}"; do
        value="${ipv6_params[$param]}"

        # Check current setting in sysctl.conf (strip spaces around =)
        current=$(grep -E "^\s*${param}\s*=" /etc/sysctl.conf | tail -n 1 | awk -F= '{gsub(/ /,"",$2); print $2}')
        
        if [[ "$current" == "$value" ]]; then
            echo -e "\e[32mAlready set:\e[0m $param = $value"
        else
            # Remove any existing lines for this param
			echo -e "\e[31Value missing or set incorrectly: $param = $value\e[0m"
			
			echo -e "\e[33m Taking Appropriate action..\e[0m"
			
            sed -i "/^\s*${param}\s*=.*/d" /etc/sysctl.conf
            echo "$param = $value" >> /etc/sysctl.conf
            echo -e "\e[33mUpdated:\e[0m $param = $value"
			echo -e "\e[33mRunning  sysctl -p to apply changes\e[0m"
			sysctl -p >/dev/null
            
        fi
    done
fi 
    
	# Append result
  if [[ "$COMPLAINT" == "yes" ]]; then
    printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.13.1" "Network Configuration (ipv6)" "Compliant" >> "$REPORT_FILE"
echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
    printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.27.2" "Ensure Ipv6 Advertisements Are Not Accepted" "Compliant" >> "$REPORT_FILE"
else
     printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.13.1" "Network Configuration (ipv6)" "Compliant" >> "$REPORT_FILE"
echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
    printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.27.2" "Ensure Ipv6 Advertisements Are Not Accepted" "Compliant" >> "$REPORT_FILE"
fi

echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#=======================================================================================================================================

check_scd_2_17_1_and_2_17_2() {
COMPLAINT="yes"
    echo -e "\n\e[35m[SCD 2.17.1] Ensure auditd is Installed\e[0m"
    echo -e "\n\e[35m[SCD 2.17.2] Ensure Events That Modify The System's Mandatory Access Controls Are Collected \e[0m"
CHANGE=0

AUDIT_RULE_FILE="/etc/audit/rules.d/audit.rules"

#Required rules to check/add (check clean formatting)

required_lines=(
'-w /etc/apparmor/ -p wa -k MAC-policy'
'-w /etc/apparmor.d/ -p wa -k MAC-policy'
'-a always,exit -F arch=b64 -S sethostname -S setdomainname -k system-locale'
'-a always,exit -F arch=b32 -S sethostname -S setdomainname -k system-locale'
'-w /etc/issue -p wa -k system-locale'
'-w /etc/issue.net -p wa -k system-locale'
'-w /etc/hosts -p wa -k system-locale'
'-w /etc/sysconfig/network -p wa -k system-locale'
'-w /etc/sysconfig/network-scripts/ -p wa -k system-locale'
'-w /var/run/utmp -p wa -k session'
'-w /var/log/wtmp -p wa -k logins'
'-w /var/log/btmp -p wa -k logins'
'-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access'
'-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access'
'-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access'
'-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access'
)

#Check Mode
	if [ "$mode" = "check" ]; then
	# Step 1: Install auditd and audit-libs if not installed
if ! rpm -q audit &>/dev/null || ! rpm -q audit-libs &>/dev/null; then
    echo -e "\n\e[31maudit and audit-libs not installed.\e[0m"
	COMPLAINT="no"
else
    echo -e "\e[32maudit and audit-libs already installed.\e[0m"
fi
# Step 2: Enable and start auditd
if systemctl is-enabled auditd &>/dev/null; then
    echo -e "\e[32mauditd service already enabled.\e[0m"
else
    echo -e "\e[31mAuditd service not enabled.\e[0m"
	COMPLAINT="no"
fi	

# Step 3: Ensure audit rule file exists

if [[ ! -f "$AUDIT_RULE_FILE" ]]; then
echo -e "\n\e[31mFile: $AUDIT_RULE_FILE not found./e[0m"
COMPLAINT="no"
elif [[ ! -d "/etc/audit/rules.d" ]]; then
echo -e "\n\e[31mFile: $AUDIT_RULE_FILE not found./e[0m"
COMPLAINT="no"
else
echo -e "\e[32mFile: $AUDIT_RULE_FILE found.\e[33mChecking for Entries...../e[0m"
fi

# Step 5: Add lines if not present (safely)
for rule in "${required_lines[@]}"; do
    # Use grep with fixed string (-F) and no regex (-x) for exact match
    if ! grep -Fx -- "$rule" "$AUDIT_RULE_FILE" &>/dev/null; then 
        echo -e "\n\e[31mRule Missing\e[0m: $rule"
		COMPLAINT="no"
    else
        echo -e "\e[32mAlready exists\e[0m: $rule"
    fi
done
	
fi


#Apply Mode
if [ "$mode" = "apply" ]; then

# Step 1: Install auditd and audit-libs if not installed
if ! rpm -q audit &>/dev/null || ! rpm -q audit-libs &>/dev/null; then
    yum install -y audit audit-libs && echo -e "\e[33maudit and audit-libs installed.\e[0m"
else
    echo -e "\e[32maudit and audit-libs already installed.\e[0m"
fi

# Step 2: Enable and start auditd
if systemctl enable --now auditd &>/dev/null; then
    echo -e "\e[32mauditd service enabled and started.\e[0m"
else
    echo -e "\e[31mFailed to enable/start auditd service. Check Manually\e[0m"
fi

# Step 3: Ensure audit rule file exists

if [[ ! -d "/etc/audit/rules.d" ]]; then
echo -e "\e[31mDirectory: /etc/audit/rules.d not found.\e[33mCreating../e[0m"
mkdir -p /etc/audit/rules.d
touch "$AUDIT_RULE_FILE"
elif [[ ! -f "$AUDIT_RULE_FILE" ]]; then
echo -e "\e[31mFile: $AUDIT_RULE_FILE not found.\e[33mCreating.../e[0m"
touch "$AUDIT_RULE_FILE"
else
echo -e "\e[32mFile: $AUDIT_RULE_FILE found.\e[33mChecking for Entries...../e[0m"
fi

# Step 4: Add lines if not present (safely)

#Take Backup
	
cp $AUDIT_RULE_FILE $AUDIT_RULE_FILE.bak_$(date +%F_%T)
echo -e "\e[33mBackup of $AUDIT_RULE_FILE created as $AUDIT_RULE_FILE.bak_$(date +%F_%T)\e[0m"

for rule in "${required_lines[@]}"; do
    # Use grep with fixed string (-F) and no regex (-x) for exact match
    if ! grep -Fx -- "$rule" "$AUDIT_RULE_FILE" &>/dev/null; then
	echo -e "\e[33mRule Missing: $rule  \e[33mAdding...\e[0m"
        echo "$rule" >> "$AUDIT_RULE_FILE"
        echo -e "\e[33mAdded\e[0m: $rule"
		CHANGE=1
    else
        echo -e "\e[32mAlready exists\e[0m: $rule"
    fi
done


# Step 6: Restart auditd service
if [[ $CHANGE -eq 1 ]]; then
if systemctl restart auditd &>/dev/null; then
    echo -e "\e[33mChanges made and auditd service restarted successfully.\e[0m"
else
    echo -e "\e[31mFailed to restart auditd using systemctl, trying service command...\e[0m"
    if service auditd restart &>/dev/null; then
        echo -e "\e[33mChanges made and auditd restarted successfully using 'service' command.\e[0m"
		
    else
        echo -e "\e[31mauditd restart failed with both systemctl and service. Check Manually...\e[0m"
    fi
fi
else
echo -e "\e[32mNo Changes done in /etc/audit/rules.d/audit.rules .\e[0m"
echo -e "\e[32mAuditd Restart not needed. Already compliant.\e[0m"
fi
fi



# Append result
   if [[ "$COMPLAINT" == "yes" ]]; then
    printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.17.1" "Ensure auditd is Installed" "Compliant" >> "$REPORT_FILE"
echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
    printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.17.2" "Ensure Events That Modify The System's Mandatory Access Controls Are Collected" "Compliant" >> "$REPORT_FILE"
else
   printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.17.1" "Ensure auditd is Installed" "Non-Compliant" >> "$REPORT_FILE"
echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
    printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.17.2" "Ensure Events That Modify The System's Mandatory Access Controls Are Collected" "Non-Compliant" >> "$REPORT_FILE"
fi

echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
 
}

#=======================================================================================================================================

check_scd_2_18_1(){

echo -e "\n\e[35mSCD 2.18.1: Configure rsyslog\e[0m"
	COMPLIANT="yes"
	# File path
    rsyslog_conf="/etc/rsyslog.conf"
	
	# 5. Expected entries
    declare -a rsyslog_entries=(
        '*.emerg                                :omusrmsg:*'
        'auth,authpriv.*                        /var/log/secure'
        'mail.*                                 -/var/log/mail'
        'mail.info                              -/var/log/mail.info'
        'mail.warning                           -/var/log/mail.warn'
        'mail.err                               /var/log/mail.err'
        'news.crit                              -/var/log/news/news.crit'
        'news.err                               -/var/log/news/news.err'
        'news.notice                            -/var/log/news/news.notice'
        '*.=warning;*.=err                      -/var/log/warn'
        '*.crit                                 /var/log/warn'
        '*.*;mail.none;news.none                -/var/log/messages'
        'local0,local1.*                        -/var/log/localmessages'
        'local2,local3.*                        -/var/log/localmessages'
        'local4,local5.*                        -/var/log/localmessages'
        'local6,local7.*                        -/var/log/localmessages'
    )
	
	line_exists() {
        local needle="$(echo "$1" | tr -s '[:space:]')"
        while IFS= read -r line; do
            local normalized="$(echo "$line" | tr -s '[:space:]')"
            if [[ "$normalized" == "$needle" ]]; then
                return 0
            fi
        done < "$rsyslog_conf"
        return 1
    }

    added_count=0
	
#Check Mode
	if [ "$mode" = "check" ]; then
	if ! rpm -q rsyslog &>/dev/null; then
        echo -e "\n\e[31m Rsyslog Package is missing.\e[0m"
		COMPLIANT="no"
		else
		echo -e "\n\e[32mRsyslog Package Already Installed.\e[0m"
    fi
	
#Separate check for FileCreateMode

value="0640"
if grep -qi "^\$FileCreateMode" "$rsyslog_conf"; then

if grep -q "^\$FileCreateMode[[:space:]]\+$value" "$rsyslog_conf"; then
echo -e "\e[32m\$FileCreateMode already correctly set to 0640\e[0m "
else
echo -e "\e[31m\$FileCreateMode incorrectly set.\e[0m"
COMPLIANT="no"
fi
		
else
echo -e "\e[31mMissing Entry for \$FileCreateMode \e[0m "
COMPLIANT="no"
fi


	 #  Chech file if not exists
    if [ ! -f "$rsyslog_conf" ]; then
       echo -e "\n\e[31m $rsyslog_conf file is missing.\e[0m"
	   else
	   for entry in "${rsyslog_entries[@]}"; do
        if ! line_exists "$entry"; then
            echo -e "\n\e[31m Line : $entry missing\e[0m"
            COMPLIANT="no"
			else
			echo -e "\n\e[32m Line : $entry Already Present.\e[0m"
        fi
    done
    fi
	
	fi
	

	#Apply Mode
if [ "$mode" = "apply" ]; then
 # 1. Install rsyslog if not installed
    if ! rpm -q rsyslog &>/dev/null; then
	echo -e "\n\e[31m Rsyslog Package is missing.\e[33mInstalling...\e[0m"
        yum install -y rsyslog
		# 2. Enable rsyslog service
    systemctl enable --now rsyslog
	echo -e "\n\e[33mRsyslog Installed and Enabled\e[0m"
		else
		echo -e "\n\e[32mRsyslog Package Already Installed.\e[0m"
    fi
	
#Separate check for FileCreateMode
	
value="0640"

cp -pr $rsyslog_conf $rsyslog_conf.bak_$(date +%F_%T)
echo -e "\e[33mBackup of $rsyslog_conf created as $rsyslog_conf.bak_$(date +%F_%T)\e[0m"
if grep -qi '^\$FileCreateMode' "$rsyslog_conf"; then

if grep -q "^\$FileCreateMode[[:space:]]\+$value" "$rsyslog_conf"; then
echo -e "\e[32m\$FileCreateMode already correctly set to 0640\e[0m "
else
echo -e "\e[31m\$FileCreateMode incorrectly set\e[33m Modifying...\e[0m"
sed -i "0,/^[[:space:]]*\$FileCreateMode.*/s//\$FileCreateMode ${value}/" "$rsyslog_conf"
((added_count++))
 fi
		
else
echo -e "\e[31mMissing Entry for \$FileCreateMode \e[33m Adding...\e[0m "
echo "\$FileCreateMode $value" >> "$rsyslog_conf"
((added_count++))
fi
	
	
	 #  Chech file if not exists
    if [ ! -f "$rsyslog_conf" ]; then
       echo -e "\n\e[31m $rsyslog_conf file is missing.\e[33mCreating $rsyslog_conf...\e[0m"
	   touch "$rsyslog_conf"
	   else
	   
	   for entry in "${rsyslog_entries[@]}"; do
        if ! line_exists "$entry"; then
            echo -e "\n\e[31m Line : $entry missing\e[0m Adding..."
			
            echo "$entry" >> "$rsyslog_conf"
			 echo -e "\n\e[33m Parameter: $entry added.\e[0m"
            ((added_count++))
			else
			echo -e "\n\e[32m Line : $entry Already Present.\e[0m"
        fi
    done
    fi
	
	if [ "$added_count" -gt 0 ]; then
        echo -e "\e[33m$added_count rsyslog entries were added.\e[0m"
	systemctl restart rsyslog
	 echo -e "\e[33m rsyslog Restarted.\e[0m"
    else
        echo -e "\e[32mAll required rsyslog entries already exist. No changes made.\e[0m"
    fi

fi

	
	# Append result
    if [[ "$COMPLIANT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.18.1" "Configure Rsyslog" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.18.1" "Configure Rsyslog" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#=======================================================================================================================================

check_scd_2_19() {
    echo -e "\n\e[35mSCD 2.19: Cron Configuration\e[0m"
COMPLIANT="yes"


 # List of cron-related paths and their expected permission modes
    declare -A cron_paths=(
        ["/etc/crontab"]="600"
        ["/etc/cron.hourly"]="700"
        ["/etc/cron.daily"]="700"
        ["/etc/cron.weekly"]="700"
        ["/etc/cron.monthly"]="700"
        ["/etc/cron.d"]="700"
    )

   # Detect cron service
    cron_service=""
    if systemctl list-unit-files | grep -qE '^cron\.service'; then
        cron_service="cron"
    elif systemctl list-unit-files | grep -qE '^crond\.service'; then
        cron_service="crond"
    fi
	

#Check Mode
	if [ "$mode" = "check" ]; then
	# Check Chrony package First
	if ! rpm -q chrony &>/dev/null; then
	echo -e "\n\e[31mChrony package not installed. Exiting\e[0m"
	COMPLIANT="no"
	# Append result
    if [[ "$COMPLIANT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.19" "Cron Configuration" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.19" "Cron Configuration" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
	return 1
	else
	echo -e "\n\e[32mChrony package Already installed. Proceeding\e[0m"
	fi
	
	#check for chrony services
	
	if [ -n "$cron_service" ] && systemctl list-unit-files | grep -qw "$cron_service"; then
        if systemctl is-active --quiet "$cron_service"; then
        echo -e "\e[32mCron service '$cron_service' found and is active.\e[0m"
		else
		echo -e "\e[31mCron service '$cron_service' is found but not active.\e[0m"
		COMPLIANT="no"
		fi
    else
        echo -e "\e[31mCron service not found.\e[0m"
		COMPLIANT="no"
    fi
	
	#check for ownerships/Permissions
	
	for path in "${!cron_paths[@]}"; do
        if [ -e "$path" ]; then
            expected_mode="${cron_paths[$path]}"
            current_owner=$(stat -c %U:%G "$path")
            current_mode=$(stat -c %a "$path")

            changes_needed=false

            if [ "$current_owner" != "root:root" ]; then
               echo -e "\n\e[31mOwnership not correct for: \e[0m$path" 
			   COMPLIANT="no"
                else 
				echo -e "\e[32mOwnership Already correct for: \e[0m$path" 
            fi

            if [ "$current_mode" != "$expected_mode" ]; then
                echo -e "\n\e[31mPermissions Incorrect for \e[0m : $path"
				COMPLIANT="no"
				else
				echo -e "\e[32mPermissions Already correct for\e[0m : $path"
            fi

        else
            echo -e "\n\e[31mNot found\e[0m : $path, skipping."
			COMPLIANT="no"
        fi
    done
	# Handle /etc/cron.deny
    if [ -f /etc/cron.deny ]; then
        echo -e "\n\e[31m/etc/cron.deny Found. Removal Required\e[0m"
		COMPLIANT="no"
    else
        echo -e "\e[32m/etc/cron.deny not present as expected.\e[0m"
    fi

	
    # Handle /etc/cron.allow
    if [ ! -f /etc/cron.allow ]; then
        echo -e "\n\e[31m/etc/cron.allow not Found.\e[0m"
		COMPLIANT="no"
		else
		 echo -e "\e[32m/etc/cron.allow Found as requirement\e[0m"
		 
		 ca_owner=$(stat -c %U:%G /etc/cron.allow)
    ca_mode=$(stat -c %a /etc/cron.allow)
    allow_changes=false
    if [ "$ca_owner" != "root:root" ]; then
        echo -e "\n\e[31mOwnership Incorrect for: /etc/cron.allow \e[0m"
		COMPLIANT="no"
  else
  echo -e "\e[32mOwnership Already correct for: /etc/cron.allow \e[0m"
    fi

    if [ "$ca_mode" != "600" ]; then
	echo -e "\n\e[31mPermission Incorrect for: /etc/cron.allow \e[0m"
	COMPLIANT="no"
    else
	echo -e "\e[32mPermission already correct for: /etc/cron.allow \e[0m"
    fi
	
    fi
	
	fi
	

	
	#apply Mode
	if [ "$mode" = "apply" ]; then
	
	if ! rpm -q chrony &>/dev/null; then
	echo -e "\n\e[31mChrony package not installed. \e[33mInstalling\e[0m"
	yum install -y chrony
	else
	echo -e "\n\e[32mChrony package already installed. Proceeding\e[0m"
	fi
	
	#check for chrony services
	
	if [ -n "$cron_service" ] && systemctl list-unit-files | grep -qw "$cron_service"; then
        if systemctl is-active --quiet "$cron_service"; then
        echo -e "\e[32mCron service '$cron_service' found and is active.\e[0m"
		else
		echo -e "\e[31mCron service '$cron_service' is found but not active.\e[33mStarting...\e[0m"
		systemctl start "$cron_service" >/dev/null 2>&1
		echo -e "\e[31mCron service '$cron_service' Started...\e[0m"
		fi
    else
        echo -e "\e[31mCron service not found.\e[0m"
		
    fi
	
	#check for ownerships/Permissions
	
	  for path in "${!cron_paths[@]}"; do
        if [ -e "$path" ]; then
            expected_mode="${cron_paths[$path]}"
            current_owner=$(stat -c %U:%G "$path")
            current_mode=$(stat -c %a "$path")

            changes_needed=false

            if [ "$current_owner" != "root:root" ]; then
			echo -e "\e[31mOwnership not correct for: \e[0m$path Correcting...." 
                chown root:root "$path"
                changes_needed=true
                else 
				echo -e "\e[32mOwnership Already correct for: \e[0m$path"
            fi

            if [ "$current_mode" != "$expected_mode" ]; then
			echo -e "\e[31mPermissions not correct for: \e[0m$path Correcting...."
                chmod "$expected_mode" "$path"
                changes_needed=true
				else 
				echo -e "\e[32mPermissions Already correct for: \e[0m$path"
            fi
			else
            echo -e "\e[31mNot found\e[0m : $path, skipping."
        fi
			done
			 
			
			# Handle /etc/cron.deny
    if [ -f /etc/cron.deny ]; then
		echo -e "\e[33m/etc/cron.deny Found.\e[33mRemoving...\e[0m"
		rm -f /etc/cron.deny
        echo -e "\e[33m/etc/cron.deny removed.\e[0m"
    else
        echo -e "\e[32m/etc/cron.deny not present as expected.\e[0m"
    fi

    # Handle /etc/cron.allow
    if [ ! -f /etc/cron.allow ]; then
	echo -e "\e[33m/etc/cron.allow not Found.\e[33mCreating...\e[0m"
        touch /etc/cron.allow
        echo -e "\e[33m/etc/cron.allow created according to requirement.\e[0m"
    fi

    ca_owner=$(stat -c %U:%G /etc/cron.allow)
    ca_mode=$(stat -c %a /etc/cron.allow)

    if [ "$ca_owner" != "root:root" ]; then
	echo -e "\e[31mOwnership Incorrect for: /etc/cron.allow \e[0mModifying..."
        chown root:root /etc/cron.allow
		echo -e "\e[33mOwnership modified for: /etc/cron.allow \e[0m"
        
		else
		echo -e "\e[32mOwnership Already set correctly for: /etc/cron.allow \e[0m"
    fi

    if [ "$ca_mode" != "600" ]; then
	echo -e "\e[31mPermissions Incorrect for: /etc/cron.allow \e[0mModifying..."
        chmod 600 /etc/cron.allow
		echo -e "\e[33mPermissions modified for: /etc/cron.allow \e[0m"
        else
		echo -e "\e[32mPermission Already set correctly for: /etc/cron.allow \e[0m"
    fi
			
     fi  
	
	
	# Append result
    if [[ "$COMPLIANT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.19" "Cron Configuration" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.19" "Cron Configuration" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"

}

#=======================================================================================================================================

check_scd_2_20() {
	COMPLIANT="yes"
 echo -e "\n\e[35mExecuting SCD 2.20: SSH Server Configuration\e[0m"


CONFIG_FILE="/etc/ssh/sshd_config"
#TEMP_FILE="/tmp/sshd_config.tmp"
CHANGED=0

declare -A SETTINGS=(
  ["Protocol"]="2"
  ["SyslogFacility"]="AUTHPRIV"
  ["LogLevel"]="INFO"
  ["X11Forwarding"]="no"
  ["MaxAuthTries"]="4"
  ["IgnoreRhosts"]="yes"
  ["HostbasedAuthentication"]="no"
  ["AuthorizedKeysFile"]=".ssh/authorized_keys"
  ["PermitRootLogin"]="yes"
  ["PermitEmptyPasswords"]="no"
  ["PermitUserEnvironment"]="no"
  ["ChallengeResponseAuthentication"]="no"
  ["GSSAPIAuthentication"]="yes"
  ["GSSAPICleanupCredentials"]="no"
  ["UsePAM"]="yes"
  ["ClientAliveInterval"]="900"
  ["ClientAliveCountMax"]="0"
  ["LoginGraceTime"]="60"
  ["MACs"]="hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256"
  ["KexAlgorithms"]="ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256"
  ["Banner"]="/etc/issue.net"
)

#Check Mode
	if [ "$mode" = "check" ]; then
	for key in "${!SETTINGS[@]}"; do
    value="${SETTINGS[$key]}"
    if grep -iq "^$key" "$CONFIG_FILE"; then
        current=$(grep -i "^$key" "$CONFIG_FILE" | head -1 | awk '{$1=""; print $0}' | xargs)
        if [[ "$current" != "$value" ]]; then
            echo -e "\n\e[31mValue incorrectly set for\e[0m : $key"
			COMPLIANT="no"
            else
			echo -e "\e[32mValue already correctly set for\e[0m : $key => $value"
        fi
    else
        echo -e "\n\e[31mMissing Entry for \e[0m : $key $value"
       COMPLIANT="no"
    fi
done
	
	# Permissions and ownership on sshd_config
if [[ $(stat -c %U:%G "$CONFIG_FILE") != "root:root" || $(stat -c %a "$CONFIG_FILE") != "600" ]]; then
   
    echo -e "\e[31m/Permissions/Ownership not set correctly on \e[0m $CONFIG_FILE Correcting.."
	COMPLIANT="no"
	else
	echo -e "\e[32mPermissions/Ownership already set correctly on \e[0m $CONFIG_FILE"
fi

		#Host key permissions
PRIVATE_KEYS=$(find /etc/ssh -type f -name 'ssh_host_*_key')

for key in $PRIVATE_KEYS; do
if [[ $(stat -c %U:%G "$key") != "root:root" || $(stat -c %a "$key") != "600" ]]; then
	echo -e "\n\e[31mOwnership/Permission Incorrect for $key\e[0m "
	COMPLIANT="no"
	else
	echo -e "\n\e[32mOwnership/Permission Already correct for $key\e[0m"
	fi
done

	PUBLIC_KEYS=$(find /etc/ssh -type f -name 'ssh_host_*_key.pub')
for key in $PUBLIC_KEYS; do
if [[ $(stat -c %U:%G "$key") != "root:root" || $(stat -c %a "$key") != "644" ]]; then
echo -e "\n\e[31mOwnership/Permission Incorrect for $key\e[0m "
   COMPLIANT="no"
	else
	echo -e "\n\e[32mOwnership/Permission Already correct for $key\e[0m"
	fi
done
	
	fi

#apply Mode
	if [ "$mode" = "apply" ]; then
	cp "$CONFIG_FILE" "/tmp/sshd_config.tmp"
	sed -i '/DenyUsers/d;/DenyGroups/d' /etc/ssh/sshd_config  # special case to remove DenyUsers and DenyGroups line
	
		for key in "${!SETTINGS[@]}"; do
    value="${SETTINGS[$key]}"
    if grep -iq "^$key" "$CONFIG_FILE"; then
        current=$(grep -i "^$key" "$CONFIG_FILE" | head -1 | awk '{$1=""; print $0}' | xargs)
        if [[ "$current" != "$value" ]]; then
            echo -e "\e[31mValue incorrectly set for\e[0m : $key Modifying..."
            sed -i "s|^$key.*|$key $value|I" "$CONFIG_FILE"
            echo -e "\e[33mModified\e[0m : $key => $value"
			 CHANGED=1
            else
			echo -e "\e[32mValue already correctly set for\e[0m : $key => $value"
        fi
    else
        echo -e "\e[33mMissing Entry for \e[0m : $key $value"
       echo "$key $value" >> "$CONFIG_FILE"
        echo -e "\e[33mAdded\e[0m : $key $value"
        CHANGED=1
    fi
done

# Step 2: Take backup only if changes were made
if [[ $CHANGED -eq 1 ]]; then

    cp "/tmp/sshd_config.tmp" "/etc/ssh/sshd_config.bak_$(date +%Y%m%d_%H%M%S)"
    echo -e "\e[33mBackup created \e[0m: $BACKUP_FILE"
else
    echo -e "\e[32mNo sshd_config changes needed. Already compliant.\e[0m"
fi

	# Step 3: Restart sshd if config changed
if [[ $CHANGED -eq 1 ]]; then
    echo -e "\e[33mRestarting sshd service..."
    systemctl restart sshd && echo -e "\e[33msshd service restarted successfully.\e[0m" || echo -e "\e[31mFailed to restart sshd. Restart it Manually\e[0m"
	 echo -e "\e[33mSSH Configuration has been checked/modified according to the document. Further changes (if any) may require manual action.\e[0m"
else
    echo -e "\e[32mNo sshd Service restart needed. sshd_config unchanged.\e[0m"	
fi


	# Permissions and ownership on sshd_config
if [[ $(stat -c %U:%G "$CONFIG_FILE") != "root:root" || $(stat -c %a "$CONFIG_FILE") != "600" ]]; then
   
    echo -e "\e[31m/Permissions/Ownership not set correctly on \e[0m $CONFIG_FILE Correcting.."
	chown root:root "$CONFIG_FILE"
	chmod 600 "$CONFIG_FILE"
	else
	echo -e "\e[32mPermissions/Ownership already set correctly on \e[0m $CONFIG_FILE"
fi
	
		
	#Host key permissions
PRIVATE_KEYS=$(find /etc/ssh -type f -name 'ssh_host_*_key')

for key in $PRIVATE_KEYS; do
if [[ $(stat -c %U:%G "$key") != "root:root" || $(stat -c %a "$key") != "600" ]]; then
	echo -e "\n\e[31mOwnership/Permission Incorrect for $key\e[0m Correcting..."
	chown root:root "$key"
    chmod 600 "$key"
	else
	echo -e "\n\e[32mOwnership/Permission Already correct for $key\e[0m"
	fi
done
	
	PUBLIC_KEYS=$(find /etc/ssh -type f -name 'ssh_host_*_key.pub')
for key in $PUBLIC_KEYS; do
if [[ $(stat -c %U:%G "$key") != "root:root" || $(stat -c %a "$key") != "644" ]]; then
echo -e "\n\e[31mOwnership/Permission Incorrect for $key\e[0m Correcting..."
    chown root:root "$key"
    chmod 644 "$key"
	else
	echo -e "\n\e[32mOwnership/Permission Already correct for $key\e[0m"
	fi
done
	
	fi

# Append result
   if [[ "$COMPLIANT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.20" "SSH Server Configuration" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.20" "SSH Server Configuration" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#=======================================================================================================================================

check_scd_2_21_1() {
echo -e "\n\e[35m=== 2.21.1 PAM Configuration =====\e[0m"
COMPLIANT="yes"
CHANGE=0
# ---------------------
# pwquality.conf section
# ---------------------
PWQ_FILE="/etc/security/pwquality.conf"
#TEMP_FILE_PWQ="/tmp/pwquality1.tmp"
declare -A pwq_params=(
    ["minlen"]="14"
    ["minclass"]="4"
    ["dcredit"]="-1"
    ["ucredit"]="-1"
    ["ocredit"]="-1"
    ["lcredit"]="-1"
)

# PAM files: password-auth and system-auth
PAM_FILES=("/etc/pam.d/password-auth" "/etc/pam.d/system-auth")
CONFIG_FILE_password_auth="/etc/pam.d/password-auth"


CONFIG_FILE_system_auth="/etc/pam.d/system-auth"

# Required lines
declare -a pam_lines=(
'password    requisite     pam_pwquality.so try_first_pass local_users_only retry=3 authtok_type='
'password    sufficient    pam_unix.so remember=5 sha512 shadow nullok try_first_pass use_authtok'
'password    required      pam_pwhistory.so remember=5'
'password    [success=1 default=ignore] pam_unix.so sha512'
'auth        [success=1 default=bad] pam_unix.so'
'auth        [default=die] pam_faillock.so authfail audit deny=5 unlock_time=900'
'auth        sufficient    pam_faillock.so authsucc audit deny=5 unlock_time=900'
'auth required pam_faillock.so preauth audit silent deny=5 unlock_time=900'	
)



#Check Mode
	if [ "$mode" = "check" ]; then
	echo -e "\nChecking $PWQ_FILE"
	for key in "${!pwq_params[@]}"; do
    value="${pwq_params[$key]}"
    if grep -q "^$key" "$PWQ_FILE"; then
        current_val=$(grep "^$key" "$PWQ_FILE" | awk -F= '{gsub(/ /,""); print $2}')
        if [[ "$current_val" != "$value" ]]; then
            echo -e "\e[31mValue not Correct\e[0m : $key "
			COMPLIANT="no"
        else
            echo -e "\e[32mAlready set correctly\e[0m : $key = $value"
        fi
    else
        echo -e "\e[31mParameter Not Found\e[0m : $key = $value"
		COMPLIANT="no"
    fi
done
	
	
# -------------------------------
# PAM files: password-auth and system-auth
# -------------------------------

for file in "${PAM_FILES[@]}"; do
    echo "Checking $file ..."
    for line in "${pam_lines[@]}"; do
        if grep -Fq -- "$line" "$file"; then
            echo -e "\e[32mAlready present: $line\e[0m"
        else
            echo -e "\e[31mMissing: $line\e[0m"
			COMPLIANT="no"
        fi
    done
    echo
done
	
	fi


#apply Mode
	if [ "$mode" = "apply" ]; then
	
cp "$CONFIG_FILE_password_auth" "/tmp/password-auth.tmp"
cp "$CONFIG_FILE_system_auth" "/tmp/system-auth.tmp"
cp "$PWQ_FILE" "/tmp/pwquality1.tmp"
	
	for key in "${!pwq_params[@]}"; do
    value="${pwq_params[$key]}"
    if grep -q "^$key" "$PWQ_FILE"; then
        current_val=$(grep "^$key" "$PWQ_FILE" | awk -F= '{gsub(/ /,""); print $2}')
        if [[ "$current_val" != "$value" ]]; then
            echo -e "\n\e[31mValue not Correct\e[0m : $key "
			echo -e "\e[33mUpdating...\e[0m"
			 sed -i "s/^$key.*/$key = $value/" "$PWQ_FILE"
			  echo -e "\n\e[33mUpdated\e[0m : $key = $value"
			  CHANGE=1
        else
            echo -e "\n\e[32mAlready set correctly\e[0m : $key = $value"
        fi
    else
        echo -e "\e[31mParameter Not Found\e[0m : $key = $value"
		echo -e "\e[33mAdding...\e[0m"
		echo "$key = $value" >> "$PWQ_FILE"
		CHANGE=1
        echo -e "\e[33mAdded\e[0m : $key = $value"
    fi
done
	
#-------------------------------
# PAM files: password-auth and system-auth
# -------------------------------


for file in "${PAM_FILES[@]}"; do
    echo -e "\e[33mChecking $file ...\e[0m"
    for line in "${pam_lines[@]}"; do
        if grep -Fq -- "$line" "$file"; then
            echo -e "\e[32mAlready present: $line\e[0m"
        else
            echo -e "\e[31mMissing: $line\e[0m"
			echo "$line" >> "$file"
            echo -e "\e[33mAdded: $line\e[0m"
        fi
    done
    echo
done


	
# Step 2: Take backup only if changes were made
if [[ $CHANGED -eq 1 ]]; then
    
    cp "/tmp/password-auth.tmp" "/etc/pam.d/password-auth.bak_$(date +%Y%m%d_%H%M%S)"
	cp "/tmp/system-auth.tmp" "/etc/pam.d/system-auth.bak_$(date +%Y%m%d_%H%M%S)"
	cp "/tmp/pwquality1.tmp" "/etc/security/pwquality1.conf.bak_$(date +%Y%m%d_%H%M%S)"
	
    echo -e "\n\e[33mBackup created \e[0m: /etc/pam.d/password-auth.bak_$(date +%Y%m%d_%H%M%S)"
	echo -e "\e[33mBackup created \e[0m: /etc/pam.d/system-auth.bak_$(date +%Y%m%d_%H%M%S)"
	echo -e "\e[33mBackup created \e[0m: /etc/security/pwquality1.conf.bak_$(date +%Y%m%d_%H%M%S)"
else
    echo -e "\e[32mNo changes needed. Already compliant.\e[0m"
fi

echo -e "\e[32m\nEntries have been checked/modified according to the document. Further changes require manual action if necessary.\e[0m"
	
	fi


# Append result
    if [[ "$COMPLIANT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.21.1" "PAM Configuration" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.21.1" "PAM Configuration" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#=======================================================================================================================================

check_scd_2_22_1() {

echo -e "\n\e[35m2.22.1 Shadow Password Suite Parameters Hardening ---\e[0m"
COMPLIANT="yes"
# Backup login.defs
LOGIN_DEFS="/etc/login.defs"
BACKUP_DIR="/etc"

TARGET=30
MAXDAYS=90
MINDAYS=7
WARNDAYS=14


# Define parameters and desired values
declare -A PARAMS
PARAMS["PASS_MAX_DAYS"]=90
PARAMS["PASS_MIN_DAYS"]=7
PARAMS["PASS_WARN_AGE"]=14


#Check Mode
	if [ "$mode" = "check" ]; then
	
	# Check /etc/login.defs parameters
for param in "${!PARAMS[@]}"; do
    value="${PARAMS[$param]}"
    if grep -q "^$param" "$LOGIN_DEFS"; then
        current_val=$(grep "^$param" "$LOGIN_DEFS" | awk '{print $2}')
        if [[ "$current_val" -eq "$value" ]]; then
            echo -e "\e[32m$param is already set to \e[0m $value"
        else
		echo -e "\e[31m$param is not set to \e[0m $value"
			COMPLIANT="no"
        fi
    else
        echo -e "\e[31mLine: $param Missing.. \e[0m"
		COMPLIANT="no"
    fi
done
	
# Check default password inactivity = 30 days
#Desired inactive days = 30

# -----------------------------
# 1. Check for NEW user default (useradd)
# -----------------------------
DEFAULTS_FILE="/etc/default/useradd"

current_default=$(grep -E "^INACTIVE=" "$DEFAULTS_FILE" 2>/dev/null | cut -d= -f2)

if [ "$current_default" != "$TARGET" ]; then
    
    if grep -q "^INACTIVE=" "$DEFAULTS_FILE"; then
        # Modify existing line
        echo -e "\e[31mDefault INACTIVE is '$current_default' (should be $TARGET).\e[0m"
		COMPLIANT="no"
    else
        echo -e "\e[31mEntry: INACTIVE is missing.\e[0m"
		COMPLIANT="no"
    fi
else
    echo -e "\e[32mDefault INACTIVE already set to $TARGET in $DEFAULTS_FILE"
fi

# -----------------------------
# 2. Check for EXISTING users
# -----------------------------
# Loop through only real login users


# Loop through real login users
for user in $(awk -F: '{ if ($7!="/sbin/nologin" && $7!="/bin/false") print $1 }' /etc/passwd); do
    inactive=$(grep "^$user:" /etc/shadow | cut -d: -f7)

    # empty field means not set
    if [ -z "$inactive" ]; then
        echo -e "\e[31mUser $user has Inactive = not set\e[0m"
        COMPLIANT="no"
    elif [ "$inactive" -ne "$TARGET" ]; then
        echo -e "\e[31mUser $user has Inactive = $inactive\e[0m"
        COMPLIANT="no"
    else
        echo -e "\e[32mUser $user already has Inactive = $TARGET\e[0m"
    fi
done
	
	
# TMOUT Setting check
echo -e "\e[33m--- Configuration check TMOUT in /etc/bashrc, /etc/profile, and /etc/profile.d/tmout.sh ----- \e[0m"

# TMOUT block
TMOUT_VALUE=900

# Files to check
FILES=(
  "/etc/bashrc"
  "/etc/profile"
  "/etc/profile.d/tmout.sh"
)
for FILE in "${FILES[@]}"; do
   echo -e "\e[33mProcessing $FILE...\e[0m"

    # Check for TMOUT=900
    if grep -Eq "^[[:space:]]*TMOUT=[[:space:]]*$TMOUT_VALUE" "$FILE"; then
        echo -e "\e[32mTMOUT already set correctly in $FILE\e[0m"
    else
        echo -e "\e[31mTMOUT not set correctly in $FILE\e[0m"
        COMPLIANT="no"
    fi

# Check for export TMOUT
    if grep -Eq "^[[:space:]]*export[[:space:]]+TMOUT" "$FILE"; then
        echo -e "\e[32mexport TMOUT already present in $FILE\e[0m"
    else
        echo -e "\e[31mexport TMOUT not found in $FILE\e[0m"
       COMPLIANT="no"
    fi
	echo -e "\e[32m TMOUT check and configuration complete.\e[0m"
done
	fi

#apply Mode

	if [ "$mode" = "apply" ]; then
	cp "$LOGIN_DEFS" "$BACKUP_DIR/login.defs.bak_$(date +%F_%T)"
		echo -e "\e[33mBackup file : $BACKUP_DIR/login.defs.bak_$(date +%F_%T) \e[0m $value"
	# Update /etc/login.defs parameters
for param in "${!PARAMS[@]}"; do
    value="${PARAMS[$param]}"
    if grep -q "^$param" "$LOGIN_DEFS"; then
        current_val=$(grep "^$param" "$LOGIN_DEFS" | awk '{print $2}')
        if [[ "$current_val" -eq "$value" ]]; then
            echo -e "\e[32m$param is already set to \e[0m $value"
        else
		echo -e "\e[31m$param is not set to $value \e[33m Setting it ....\e[0m"
		
            sed -i "s/^$param.*/$param $value/" "$LOGIN_DEFS"
            echo -e "\e[33m$param updated from $current_val to \e[0m $value"
        fi
    else
	echo -e "\e[31mEntry: $param not found.\e[0m"
        echo "$param $value" >> "$LOGIN_DEFS"
        echo -e "\e[33m$param added with value \e[0m $value"
    fi
done
	
	# Set default password inactivity period to 30 days
#Desired inactive days


# -----------------------------
# 1. Check / Fix NEW user default (useradd)
# -----------------------------
DEFAULTS_FILE="/etc/default/useradd"
cp "$DEFAULTS_FILE" "$DEFAULTS_FILE.bak_$(date +%F_%T)"
		echo -e "\e[33mBackup file : $DEFAULTS_FILE.bak_$(date +%F_%T) \e[0m $value"
current_default=$(grep -E "^INACTIVE=" "$DEFAULTS_FILE" 2>/dev/null | cut -d= -f2)

if [ "$current_default" != "$TARGET" ]; then
    
    if grep -q "^INACTIVE=" "$DEFAULTS_FILE"; then
        # Modify existing line
		echo -e "\e[31mDefault INACTIVE is '$current_default' (should be $TARGET). \e[0mFixing..."
        sed -i "s/^INACTIVE=.*/INACTIVE=$TARGET/" "$DEFAULTS_FILE"
    else
        # Add new line
		 echo -e "\e[31mEntry: INACTIVE is missing.\e[33mAdding...\e[0m"
        echo "INACTIVE=$TARGET" >> "$DEFAULTS_FILE"
		echo -e "\e[33mAdded ; INACTIVE=$TARGET\e[0m"
    fi
else
    echo -e "\e[32mDefault INACTIVE already set to $TARGET in $DEFAULTS_FILE\e[0m"
fi

# -----------------------------
# 2. Check / Fix EXISTING users
# -----------------------------


# Loop through real login users
for user in $(awk -F: '{ if ($7!="/sbin/nologin" && $7!="/bin/false") print $1 }' /etc/passwd); do
    inactive=$(grep "^$user:" /etc/shadow | cut -d: -f7)

    # empty field means not set
    if [ -z "$inactive" ]; then
        echo -e "\e[31mUser $user has Inactive = not set, fixing...\e[0m"
        chage -M $MAXDAYS -I $TARGET "$user"
    elif [ "$inactive" -ne "$TARGET" ]; then
        echo -e "\e[31mUser $user has Inactive = $inactive, fixing...\e[0m"
        chage -M $MAXDAYS -m $MINDAYS -I $TARGET -W $WARNDAYS "$user"
    else
        echo -e "\e[32mUser $user already has Inactive = $TARGET\e[0m"
    fi
done
	
	# TMOUT Setting check
echo -e "\e[33m--- Configuration check TMOUT in /etc/bashrc, /etc/profile, and /etc/profile.d/tmout.sh ----- \e[0m"

# Values to set
TMOUT_VALUE="900"

# Files to check
FILES=(
  "/etc/bashrc"
  "/etc/profile"
  "/etc/profile.d/tmout.sh"
)

# Check and create /etc/profile.d/tmout.sh if not present
for file in "${FILES[@]}"; do
if [ ! -f "$file" ]; then
    echo -e "\e[31mFile: $file not found.\e[33mCreating ...\e[0m"
    touch "$file"
    chmod 644 "$file"
	else
	echo -e "\e[32mFile: $file found:\e[0m Proceeding to check entry..."
fi
done


# Check and update /etc/bashrc, /etc/profile and /etc/profile.d/tmout.sh
for FILE in "${FILES[@]}"; do
    echo -e "\e[33mProcessing $FILE...\e[0m"


    # Check for TMOUT=900
    if grep -Eq "^[[:space:]]*TMOUT=[[:space:]]*$TMOUT_VALUE" "$FILE"; then
        echo -e "\e[32mTMOUT already set correctly in $FILE\e[0m"
    else
        echo -e "\e[31mTMOUT not set correctly in $FILE, \e[33madding...\e[0m"
		cp "$FILE" "$FILE.bak_$(date +%F_%T)"
        echo "TMOUT=$TMOUT_VALUE" >> "$FILE"
    fi

    # Check for export TMOUT
    if grep -Eq "^[[:space:]]*export[[:space:]]+TMOUT" "$FILE"; then
        echo -e "\e[32mexport TMOUT already present in $FILE\e[0m"
    else
        echo -e "\e[31mexport TMOUT not found in $FILE, \e[33madding...\e[0m"
		cp "$FILE" "$FILE.bak_$(date +%F_%T)"
        echo "export TMOUT" >> "$FILE"
    fi
done
		
	fi
	
# Append result
if [[ "$COMPLIANT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.22.1" "Shadow Password Suite Parameters Hardening " "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.22.1" "Shadow Password Suite Parameters Hardening " "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#=======================================================================================================================================

check_scd_2_22_2() {
echo -e "\n\e[35m2.22.2 Logging and Auditing (Restrict 'su' command with sugroup) -----\e[0m"
COMPLIANT="yes"
GROUP_NAME="sugroup"
PAM_SU_FILE="/etc/pam.d/su"
PAM_LINE="auth required pam_wheel.so use_uid"
group_file="/etc/group"
pattern="^wheel:x:10:root,$"



#Check Mode
	if [ "$mode" = "check" ]; then
	# Check if the group exists
if getent group "$GROUP_NAME" > /dev/null 2>&1; then
    echo -e "\e[32mGroup '$GROUP_NAME' already exists.\e[0m"
else
    echo -e "\e[31mGroup '$GROUP_NAME' doesn't exist.\e[0m"
	COMPLIANT="no"
fi

# Check if the PAM line exists
if grep -qF "$PAM_LINE" "$PAM_SU_FILE"; then
    echo -e "\e[32mPAM entry already exists in \e[0m $PAM_SU_FILE."
else
    echo -e "\e[31m$PAM_LINE entry not found in:\e[0m $PAM_SU_FILE."
	COMPLIANT="no"
fi

# Check if the wheel:x:10:root, exists in /etc/group

if grep -qE "$pattern" "$group_file"; then
    echo -e "\e[32mEntry 'wheel:x:10:root,' already present in\e[0m $group_file"
	else
	echo -e "\e[31mEntry 'wheel:x:10:root,' not found in \e[0m $group_file"
	COMPLIANT="no"
		fi
	
	fi
	
#apply mode
if [ "$mode" = "apply" ]; then

# Check if the group exists
if getent group "$GROUP_NAME" > /dev/null 2>&1; then
    echo -e "\e[32mGroup '$GROUP_NAME' already exists.\e[0m"
else
echo -e "\e[31mGroup '$GROUP_NAME' doesn't exist.\e[0m Creating..."
    groupadd "$GROUP_NAME"
    echo -e "\e[33mGroup '$GROUP_NAME' created successfully.\e[0m"

fi

cp "$PAM_SU_FILE" "$PAM_SU_FILE.bak$(date +%F_%T)"
echo -e "\e[33mBacup taken as $PAM_SU_FILE.bak$(date +%F_%T) \e[0m"
# Check if the PAM line exists
if grep -qF "$PAM_LINE" "$PAM_SU_FILE"; then
    echo -e "\e[32mPAM entry already exists in \e[0m $PAM_SU_FILE."
else
echo -e "\e[31m$PAM_LINE entry not found in:\e[0m $PAM_SU_FILE."
    echo "$PAM_LINE" >> "$PAM_SU_FILE"
    echo -e "\e[33mPAM entry added to \e[0m $PAM_SU_FILE."
fi

# Check if the wheel:x:10:root, exists in /etc/group

if grep -qE "$pattern" "$group_file"; then
    echo -e "\e[32mEntry 'wheel:x:10:root,' already present\e[0m"
	else
	echo -e "\e[31mEntry 'wheel:x:10:root,' not found in $group_file\e[0m"
	echo -e "\e[33mAdding 'wheel:x:10:root,' to $group_file...\e[0m"
	#taking backup before entry
	cp "$group_file" "$group_file.bak$(date +%F_%T)"
	echo -e "\e[33mBacup taken as $group_file.bak$(date +%F_%T) \e[0m"
		echo "wheel:x:10:root," >> "$group_file"
		echo -e "\e[33mEntry added successful.\e[0m"
		fi

fi

# Append result
if [[ "$COMPLIANT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.22.2" "Logging and Auditing " "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.22.2" "Logging and Auditing " "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#=======================================================================================================================================

check_scd_2_23_1(){
echo -e "\n\e[35mSCD 2.23.1 System File Permissions Check -----\e[0m"
COMPLIANT="yes"
declare -A FILES=(
  ["/etc/passwd"]="root:root|644"
  ["/etc/passwd-"]="root:root|600"
  ["/etc/group"]="root:root|644"
  ["/etc/group-"]="root:root|640"
  ["/etc/shadow"]="root:root|000"
  ["/etc/shadow-"]="root:root|000"
  ["/etc/gshadow"]="root:root|000"
  ["/etc/gshadow-"]="root:root|000"
)


#Check Mode
	if [ "$mode" = "check" ]; then
	
	for FILE in "${!FILES[@]}"; do
    if [ -e "$FILE" ]; then
        DESIRED_OWNER=$(echo "${FILES[$FILE]}" | cut -d'|' -f1)
        DESIRED_PERMS=$(echo "${FILES[$FILE]}" | cut -d'|' -f2)

        CURRENT_OWNER=$(stat -c "%U:%G" "$FILE")
        CURRENT_PERMS=$(stat -c "%a" "$FILE" | awk '{printf "%03d\n",$1}')

        if [ "$CURRENT_OWNER" != "$DESIRED_OWNER" ]; then
            
            echo -e "\e[31mOwnership of $FILE not as $DESIRED_OWNER\e[0m"
			COMPLIANT="no"
        else
            echo -e "\e[32mOwnership of \e[0m $FILE already set to $DESIRED_OWNER"
        fi

        if [ "$CURRENT_PERMS" != "$DESIRED_PERMS" ]; then
            
            echo -e "\e[31mpermissions of $FILE not as $DESIRED_PERMS\e[0m"
			COMPLIANT="no"
        else
            echo -e "\e[32mPermissions of \e[0m $FILE already set to $DESIRED_PERMS"
        fi
    else
        echo -e "\e[31mFile $FILE not found. Check Manually.\e[0m"
		COMPLIANT="no"
    fi
done
		
	fi


#apply mode
if [ "$mode" = "apply" ]; then

for FILE in "${!FILES[@]}"; do
    if [ -e "$FILE" ]; then
        DESIRED_OWNER=$(echo "${FILES[$FILE]}" | cut -d'|' -f1)
        DESIRED_PERMS=$(echo "${FILES[$FILE]}" | cut -d'|' -f2)

        CURRENT_OWNER=$(stat -c "%U:%G" "$FILE")
        #CURRENT_PERMS=$(stat -c "%a" "$FILE")
		CURRENT_PERMS=$(stat -c "%a" "$FILE" | awk '{printf "%03d\n",$1}')

        if [ "$CURRENT_OWNER" != "$DESIRED_OWNER" ]; then
		   echo -e "\e[31mOwnership of $FILE not as $DESIRED_OWNER\e[0m Changing Ownership..."
            chown "$DESIRED_OWNER" "$FILE"
            echo -e "\e[33mChanged ownership of \e[0m $FILE to $DESIRED_OWNER"
        else
            echo -e "\e[32mOwnership of \e[0m $FILE already set to $DESIRED_OWNER"
        fi

        if [ "$CURRENT_PERMS" != "$DESIRED_PERMS" ]; then
		echo -e "\e[31mpermissions of $FILE not as $DESIRED_PERMS\e[0m Changing Permission..."
            chmod "$DESIRED_PERMS" "$FILE"
            echo -e "\e[33mChanged permissions of \e[0m $FILE to $DESIRED_PERMS"
			
        else
            echo -e "\e[32mPermissions of \e[0m $FILE already set to $DESIRED_PERMS"
        fi
    else
        echo -e "\e[31mFile $FILE not found. Check Manually.\e[0m"
		
    fi
done


fi



# Append result
    if [[ "$COMPLIANT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.23.1" "System File Permissions Check" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.23.1" "System File Permissions Check" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#=======================================================================================================================================

check_scd_2_24_1_and_2_26_1(){
echo -e "\n\e[35mSCD 2.24.1 and 2.26.1: User and Group Settings\e[0m"
COMPLIANT="yes"
echo -e "\nChecking for users with no password and nologin/false shell...\e[0m"

# Get list of users with non-login shells
nologin_users=$(awk -F: '($7 ~ /\/sbin\/nologin|\/bin\/false/) {print $1}' /etc/passwd)

#Check Mode
	if [ "$mode" = "check" ]; then

	# Loop through each user
for user in $nologin_users; do
    passwd_status=$(grep "^$user:" /etc/shadow | cut -d: -f2)

    if [[ "$passwd_status" == "!"* || "$passwd_status" == "*" || -z "$passwd_status" ]]; then
        # User has no valid password set
        # Now check if already locked
        if passwd -S "$user" 2>/dev/null | grep -q "LK"; then
            echo -e "\e[32mUser $user already locked. Skipping.\e[0m"
        else
            echo -e "\e[31m $user (No valid password + non-login shell) not locked \e[0m"
			COMPLIANT="no"
        fi
    fi
done

# Append result
   if [[ "$COMPLIANT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.24.1" "User and Group Settings" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.24.1" "User and Group Settings" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"

COMPLIANT="yes"	
echo
echo -e "\e[33mChecking and removing any legacy '+' entries in passwd, shadow, group...\e[0m"

for file in /etc/passwd /etc/shadow /etc/group; do
    if grep -q '^+' "$file"; then
        echo -e "\e[31mLegacy '+' entry found in $file. \e[0m"
		COMPLIANT="no"
    else
        echo -e "\e[32mNo legacy '+' entry found in $file. \e[0m"
    fi
done

echo

# Append result
    if [[ "$COMPLIANT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.26.1" "Disable System Accounts" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.26.1" "Disable System Accounts" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
	
fi

#apply mode
if [ "$mode" = "apply" ]; then

# Loop through each user
for user in $nologin_users; do
    passwd_status=$(grep "^$user:" /etc/shadow | cut -d: -f2)

    if [[ "$passwd_status" == "!"* || "$passwd_status" == "*" || -z "$passwd_status" ]]; then
        # User has no valid password set
        # Now check if already locked
        if passwd -S "$user" 2>/dev/null | grep -q "LK"; then
            echo -e "\e[32mUser $user already locked. Skipping.\e[0m"
        else
		 echo -e "\e[31m $user (No valid password + non-login shell) not locked \e[0m"
            echo -e "\e[33mLocking user: $user (No valid password + non-login shell) \e[0m"
            passwd -l "$user"
        fi
    fi
done


echo
echo -e "\e[33mChecking and removing any legacy '+' entries in passwd, shadow, group...\e[0m"

for file in /etc/passwd /etc/shadow /etc/group; do
    if grep -q '^+' "$file"; then
        echo -e "\e[31mLegacy '+' entry found in $file.\e[33mRemoving...\e[0m"
        sed -i '/^+/d' "$file"
		echo -e "\e[33mLegacy '+' entry removed from  $file.\e[33m\e[0m"
    else
        echo -e "\e[32mNo legacy '+' entry found in $file. \e[0m"
    fi
done

fi

}

#=======================================================================================================================================

check_scd_2_25_1() {
  echo -e "\e[35mSCD 2.25.1 : Restrict SSH Ciphers\e[0m"
COMPLIANT="yes"
# Expected ciphers config
required_ciphers="Ciphers aes128-ctr,aes192-ctr,aes256-ctr"

# Get the current Ciphers line (ignoring comments, case-insensitive)
existing_ciphers=$(grep -i "^Ciphers[[:space:]]" /etc/ssh/sshd_config | grep -v '^#' | tail -1)

# Normalize both by removing all whitespace
clean_required=$(echo "$required_ciphers" | tr -d '[:space:]')
clean_existing=$(echo "$existing_ciphers" | tr -d '[:space:]')


#Check Mode
	if [ "$mode" = "check" ]; then
	
	# Compare normalized values
if [ "$clean_existing" = "$clean_required" ]; then
    echo -e "\e[32mCiphers already correctly configured. No changes made.\e[0m"
else
    echo -e "\e[31mCiphers configuration not found or incorrect.\e[0m"
	COMPLIANT="no"
fi
	
	fi


#apply mode
if [ "$mode" = "apply" ]; then

# Compare normalized values and take action accordingly
if [ "$clean_existing" = "$clean_required" ]; then
    echo -e "\e[32mCiphers already correctly configured. No changes made.\e[0m"
else
    echo -e "\e[31mCiphers configuration not found or incorrect. Updating...\e[0m"
	
    # Backup
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak_$(date +%F_%T)
    echo -e "\e[33mBackup of sshd config taken as /etc/ssh/sshd_config_cipher.bak_$(date +%F_%T)\e[0m"

    # Remove existing Ciphers line(s)
    sed -i '/^[[:space:]]*Ciphers[[:space:]]/Id' /etc/ssh/sshd_config
	
    # Add correct Ciphers line at the end
    echo "$required_ciphers" >> /etc/ssh/sshd_config
	systemctl restart sshd
    echo -e "\e[33mCiphers updated in /etc/ssh/sshd_config\e[0m Restarted sshd service"
	
	
fi

fi


# Append result
   if [[ "$COMPLIANT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.25.1" " Restrict SSH Ciphers" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.25.1" " Restrict SSH Ciphers" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#=======================================================================================================================================

check_scd_2_26_2_and_2_26_3(){
COMPLIANT="yes"
echo
echo -e "\e[35mSCD 2.26.2: Ensuring default group for root is GID 0...\e[0m"

# Get root's current GID
current_gid=$(id -g root)


#Check Mode
        if [ "$mode" = "check" ]; then
if [[ "$current_gid" -eq 0 ]]; then
    echo -e "\e[32mRoot already has GID 0 (root group).\e[0m"
else
    echo -e "\e[31mRoot does not have GID 0. \e[0m"
        COMPLIANT="no"
fi

# Append result
      if [[ "$COMPLIANT" == "yes" ]]; then
        printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.26.2" "Ensuring default group for root is GID 0" "Compliant" >> "$REPORT_FILE"
    else
        printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.26.2" "Ensuring default group for root is GID 0" "Non-Compliant" >> "$REPORT_FILE"
    fi
        echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"


        COMPLIANT="yes"
echo
echo -e "\e[35mSCD 2.26.3: Ensuring default umask is set to 027 in /etc/bashrc and /etc/profile...\e[0m"

files=("/etc/bashrc" "/etc/profile")

for file in "${files[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo -e "\e[31mFile $file not found. Skipping...\e[0m"
		COMPLIANT="no"
        continue
    fi
	
	#find last umaskline number
	last_umask_line=$(grep -n '^[[:space:]]*umask[[:space:]]\+[0-9]\+' "$file" | tail -n1 | cut -d: -f1)
	if [[ -n "$last_umask_line" ]]; then
	#extract the value of last umask
	last_value=$(sed -n "${last_umask_line}s/^[[:space:]]*umask[[:space:]]\+\([0-9]\+\)/\1/p" "$file")
	
	if [[ "$last_value" == "027" ]]; then
	
	echo -e "\e[32mCorrect umask 027 already set in $file\e[0m"
	
	else
	echo -e "\e[31mIncorrect umask ($last_value) found in $file.\e[0m"
	COMPLIANT="no"
		fi
		else
		echo -e "\e[31mumask entry not found in $file. \e[0m"
		COMPLIANT="no"
	fi
	done



# Append result
   if [[ "$COMPLIANT" == "yes" ]]; then
        printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.26.3" "Ensuring default umask is set to 027" "Compliant" >> "$REPORT_FILE"
    else
        printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.26.3" "Ensuring default umask is set to 027" "Non-Compliant" >> "$REPORT_FILE"
    fi
        echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"


        fi

#apply mode
if [ "$mode" = "apply" ]; then
files=("/etc/bashrc" "/etc/profile")
#backup
        cp "$file" "${file}.bak_$(date +%F_%H%M%S)"
		echo -e "\e[33Backup taken as ${file}.bak_$(date +%F_%H%M%S)\e[0m"
if [[ "$current_gid" -eq 0 ]]; then
    echo -e "\e[32mRoot already has GID 0 (root group).\e[0m"
else
    echo -e "\e[31mRoot does not have GID 0. \e[33mChanging to GID 0...\e[0m"
    usermod -g 0 root && echo -e "\e[33mRoot's GID successfully changed to 0.\e[0m"


fi
echo
echo -e "\e[35mSCD 2.26.3: Ensuring default umask is set to 027 in /etc/bashrc and /etc/profile...\e[0m"



for file in "${files[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo -e "\e[31mFile $file not found. Skipping...\e[0m"
        continue
    fi
	
	#find last umaskline number
	last_umask_line=$(grep -n '^[[:space:]]*umask[[:space:]]\+[0-9]\+' "$file" | tail -n1 | cut -d: -f1)
	if [[ -n "$last_umask_line" ]]; then
	#extract the value of last umask
	last_value=$(sed -n "${last_umask_line}s/^[[:space:]]*umask[[:space:]]\+\([0-9]\+\)/\1/p" "$file")
	
	if [[ "$last_value" == "027" ]]; then
	
	echo -e "\e[32mCorrect umask 027 already set in $file\e[0m"
	
	else
	echo -e "\e[31mIncorrect umask ($last_value) found in $file. \e[33mUpdating...\e[0m"
		sed -i "${last_umask_line}s/^[[:space:]]*umask[[:space:]]\{1,\}[0-9]\+/umask 027/" "$file"
		
		echo -e "\e[31m \e[33mUpdated umask 027 in $file...\e[0m"
		fi
		else
		echo -e "\e[31mumask entry not found in $file. \e[33mAppending new entry..\e[0m"
        echo "umask 027" >> "$file"
        echo -e "\e[33mumask 027 appended to $file\e[0m"
	fi
	done


fi
}

#=======================================================================================================================================

check_scd_2_27_1(){ 
echo -e "\n\e[35mSCD 2.27.1. Modify Network Parameters\e[0m"
COMPLIANT="yes"
# Define the config file
SYSCTL_FILE="/etc/sysctl.conf"

# Define required settings as key=value pairs
declare -A settings=(
  ["net.ipv4.ip_forward"]="0"
  ["net.ipv4.conf.all.send_redirects"]="0"
  ["net.ipv4.conf.default.send_redirects"]="0"
  ["net.ipv4.conf.all.accept_source_route"]="0"
  ["net.ipv4.conf.default.accept_source_route"]="0"
  ["net.ipv4.conf.all.accept_redirects"]="0"
  ["net.ipv4.conf.default.accept_redirects"]="0"
  ["net.ipv4.conf.all.secure_redirects"]="0"
  ["net.ipv4.conf.default.secure_redirects"]="0"
  ["net.ipv4.conf.all.log_martians"]="1"
  ["net.ipv4.conf.default.log_martians"]="1"
  ["net.ipv4.icmp_echo_ignore_broadcasts"]="1"
  ["net.ipv4.icmp_ignore_bogus_error_responses"]="1"
  ["net.ipv4.conf.all.rp_filter"]="1"
  ["net.ipv4.conf.default.rp_filter"]="1"
  ["net.ipv4.tcp_syncookies"]="1"
)

#Check Mode
    if [ "$mode" = "check" ]; then
# Loop through each setting and apply if not present or incorrect
for key in "${!settings[@]}"; do
  value="${settings[$key]}"
  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*${value}[[:space:]]*(#.*)?$" "$SYSCTL_FILE"; then
    echo -e "\e[32m$key=$value already set correctly.\e[0m"
  else
  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$SYSCTL_FILE"; then
  echo -e "\e[31mEntry : $key exists but not set correctly in $SYSCTL_FILE\e[0m"
COMPLIANT="no"
	else 
    # Append correct setting if entry 
	echo -e "\e[31mEntry : $key missing in $SYSCTL_FILE\e[0m"
	COMPLIANT="no"
  fi
  fi
done
		
	fi


#apply mode
	if [ "$mode" = "apply" ]; then
	
  # Backup the original file
cp "$SYSCTL_FILE" "${SYSCTL_FILE}.bak_$(date +%F_%T)"
echo -e "\e[33Backup taken as ${SYSCTL_FILE}.bak_$(date +%F_%T)\e[0m"

# Loop through each setting and apply if not present or incorrect
for key in "${!settings[@]}"; do
  value="${settings[$key]}"
  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*${value}[[:space:]]*(#.*)?$" "$SYSCTL_FILE"; then
    echo -e "\e[32m$key=$value already set correctly.\e[0m"
  else
  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$SYSCTL_FILE"; then
  echo -e "\e[31mEntry : $key exists but not set correctly in $SYSCTL_FILE \e[33mFixing...\e[0m"
  
    # Remove any existing entry for the key and Append correct setting
    sed -i "s|^[[:space:]]*${key}[[:space:]]*=.*|$key = $value|" "$SYSCTL_FILE"
	else 
    # Append correct setting if entry 
	
	echo -e "\e[31mEntry : $key missing in $SYSCTL_FILE\e[0m"
    echo "$key = $value" >> "$SYSCTL_FILE"
    echo -e "\e[33mSet $key=$value in $SYSCTL_FILE\e[0m"
	fi
  fi
done

# Reload sysctl settings
sysctl -p 
echo 
echo -e "\e[32mSysctl reloaded successfully.\e[0m"
	fi

# Append result
    if [[ "$COMPLIANT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.27.1" "Modify Network Parameters" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.27.1" "Modify Network Parameters" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#=======================================================================================================================================

check_scd_2_28_1(){
COMPLIANT="yes"
echo -e "\n\e[35mSCD 2.28.1. Ensure audit logs are not automatically deleted../etc/audit/auditd.conf \e[0m"
COMPLIANT="yes"
AUDIT_FILE="/etc/audit/auditd.conf"

 # Define required settings as key=value pairs
declare -A settings=(
  ["max_log_file_action"]="keep_logs"
  ["action_mail_acct"]="root"
  ["admin_space_left_action"]="halt"
)

#Check Mode
    if [ "$mode" = "check" ]; then
	
for key in "${!settings[@]}"; do
value="${settings[$key]}"

 if grep -Eq "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*${value}[[:space:]]*(#.*)?$" "$AUDIT_FILE"; then
    echo -e "\e[32mvalue already set correctly.\e[0m ${key}=${value}"
  else
  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$AUDIT_FILE"; then
  echo -e "\e[31mEntry : ${key} exists but not set correctly in $AUDIT_FILE \e[0m"
  COMPLIANT="no"

	else 
    # Append correct setting if entry missing
	 echo -e "\e[31mEntry : ${key}  missing in $AUDIT_FILE\e[0m"
    COMPLIANT="no"
  fi
  fi

  done
	fi
	
	#apply mode
	if [ "$mode" = "apply" ]; then
	# Backup the original file
cp "$AUDIT_FILE" "$AUDIT_FILE.bak_$(date +%F_%T)"
echo -e "\e[33Backup taken as ${AUDIT_FILE}.bak_$(date +%F_%T)\e[0m"
	
for key in "${!settings[@]}"; do
value="${settings[$key]}"

 if grep -Eq "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*${value}[[:space:]]*(#.*)?$" "$AUDIT_FILE"; then
    echo -e "\e[32mvalue already set correctly.\e[0m ${key}=${value}"
  else
  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$AUDIT_FILE"; then
  echo -e "\e[31mEntry : ${key} exists but not set correctly in $AUDIT_FILE \e[33mFixing...\e[0m"
  
    # Remove any existing entry for the key and Append correct setting
    sed -i "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$AUDIT_FILE"
	else 
    # Append correct setting if entry missing
	 echo -e "\e[31mEntry : ${key}  missing in $AUDIT_FILE\e[33m Putting New Entry\e[0m"
    echo "${key} = ${value}" >> "$AUDIT_FILE"
    echo -e "\e[33mEntry: ${key} = ${value} did in  $AUDIT_FILE\e[0m"
  fi
  fi

  done

# Restart Auditd service
if systemctl is-enabled auditd &>/dev/null; then
            systemctl restart auditd 2>/dev/null || service auditd restart 2>/dev/null
			echo -e "\e[33mAuditd Restarted !.\e[0m"
        else
            echo -e "\e[31mAuditd is not enabled on this system.\e[0m"
        fi
	
	fi
	
# Append result
   if [[ "$COMPLIANT" == "yes" ]]; then
	printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.28.1" "Modify Network Parameters" "Compliant" >> "$REPORT_FILE"
    else
	printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.28.1" "Modify Network Parameters" "Non-Compliant" >> "$REPORT_FILE"
    fi
	echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#=======================================================================================================================================

check_scd_2_1_2() { 
echo -e "\n\e[35m[SCD 2.1.2] Ensure Sticky Bit Is Set on All World-Writable Directories\e[0m"
COMPLIANT="yes"
world_writable_dirs=$(df -P --local | awk 'NR!=1 {print $6}' | xargs -I '{}' find '{}' -xdev -type d  \( -perm -0002 -a ! -perm -1000 \) 2>/dev/null)


#Check Mode
    if [ "$mode" = "check" ]; then
	
if [ -z "$world_writable_dirs" ]; then 
echo -e "\e[32mAll world-writable directories already have the sticky bit set.\e[0m" 
else 
echo -e "\e[33mSticky bit is not set on the following directories: \e[0m" 
COMPLIANT="no"
echo "$world_writable_dirs" 
fi 
	
	fi

#apply mode
	if [ "$mode" = "apply" ]; then
	
	if [ -z "$world_writable_dirs" ]; then 
echo -e "\e[32mAll world-writable directories already have the sticky bit set.\e[0m" 
else 
echo -e "\e[31mSticky bit is not set many directories. \e[33mFixing... \e[0m" 
echo "$world_writable_dirs" | xargs -I '{}' chmod a+t '{}' 
echo -e "\n\e[33mSticky bit set on the following directories: \e[0m" 
echo "$world_writable_dirs" 
fi 
	
	fi

# Append result
  if [[ "$COMPLIANT" == "yes" ]]; then
        printf "| %-9s | %-64s | \e[32m%-16s\e[0m |\n" "2.1.2" "Ensure Sticky Bit Is Set on All World-Writable Directories" "Compliant" >> "$REPORT_FILE"
    else
        printf "| %-9s | %-64s | \e[31m%-16s\e[0m |\n" "2.1.2" "Ensure Sticky Bit Is Set on All World-Writable Directories" "Non-Compliant" >> "$REPORT_FILE"
    fi
        echo -e "+--------------------------------------------------------------------------------------------------+" >> "$REPORT_FILE"
}

#===================================================================================================================================
	
main() {
echo -e "\n\e[36mStarting SCD Compliance Hardening Script...(RHEL 8)\e[0m"
echo -e "\n\e[32m***************************Created By \e[1mSonu Kumar (CKYC)*********************************\e[0m"
sleep 3
check_scd_2_1_1_and_2_15_1
check_scd_2_1_3
check_scd_2_1_4
check_scd_2_3_1
check_scd_2_30_5
check_scd_2_4_1
check_scd_2_5_1
check_scd_2_6_1
check_scd_2_7_1
check_scd_2_8_1
check_scd_2_9_1_and_2_30_2
check_scd_2_9_2
check_scd_2_10_1_and_2_12_1
check_scd_2_11_1
check_scd_2_13_1_and_2_27_2
check_scd_2_17_1_and_2_17_2
check_scd_2_18_1
check_scd_2_19
check_scd_2_20
check_scd_2_21_1
check_scd_2_22_1
check_scd_2_22_2
check_scd_2_23_1
check_scd_2_24_1_and_2_26_1
check_scd_2_25_1
check_scd_2_26_2_and_2_26_3
check_scd_2_27_1
check_scd_2_28_1
check_scd_2_2_2
check_scd_2_30_3
check_scd_2_1_2
}
main

