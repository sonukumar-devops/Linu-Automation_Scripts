
#!/bin/bash

check_rscd_status() {

systemctl status rscd > /dev/null 2>&1
return $?
}

check_rscd_status
if [ $? -eq 0 ]; then
echo -e "\e[32mRSCD  Already Active.\e[0m"
else

echo -e "\e[31mRSCD service is not active.\e[0m"

echo -e "\e[33mStarting RSCD service..\e[0m"

systemctl start rscd > /dev/null 2>&1

check_rscd_status
if [ $? -eq 0 ]; then

echo -e "\e[32mRSCD started Successfully.\e[0m"

else
echo -e "\e[31mFailed to start RSCD!! Check manually!\e[0m"

fi
fi

# Commvault
check_commvault_status() {

systemctl status commvault > /dev/null 2>&1
return $?
}

check_commvault_status
if [ $? -eq 0 ]; then
echo -e "\e[32mCommvault Active Already.\e[0m"
else

echo -e "\e[31mCommvault service is not active. \e[0m"

echo -e "\e[33mStarting Commvault service..\e[0m"

systemctl start commvault > /dev/null 2>&1

check_commvault_status
if [ $? -eq 0 ]; then

echo -e "\e[32mCommvault started Successfully.\e[0m"

else
echo -e "\e[31mFailed to start Commvault!! Check Manually..\e[0m"

fi
fi


# Chrony

check_Chrony_status() {

systemctl status chronyd > /dev/null 2>&1
return $?
}

check_Chrony_status
if [ $? -eq 0 ]; then
echo -e "\e[32mChrony Active Already.\e[0m"
else

echo -e "\e[31mChrony service is not active. \e[0m"

echo -e "\e[33mStarting Chrony service...\e[0m"

systemctl start chronyd > /dev/null 2>&1

check_Chrony_status
if [ $? -eq 0 ]; then

echo -e "\e[32mChrony started Successfully.\e[0m"

else
echo -e "\e[31mFailed to start Chrony!! Check manually..\e[0m".

fi
fi

# Audit

check_Audit_status() {

systemctl status auditd > /dev/null 2>&1
return $?
}

check_Audit_status
if [ $? -eq 0 ]; then
echo -e "\e[32mAudit Active Already.\e[0m"
else

echo -e "\e[31mAudit service is not active.\e[0m"

echo -e "\e[33mStarting Audit service...\e[0m"

systemctl start auditd > /dev/null 2>&1

check_Audit_status
if [ $? -eq 0 ]; then

echo -e "\e[32mAudit started Successfully.\e[0m"

else
echo -e "\e[31mFailed to start Audit!! Check manually..\e[0m"

fi
fi


## Rsyslog
check_rsyslog_status() {

systemctl status rsyslog > /dev/null 2>&1
return $?
}

check_rsyslog_status
if [ $? -eq 0 ]; then
echo -e "\e[32mRsyslog Active Already.\e[0m"
else

echo -e "\e[31mRsyslog service is not active. \e[0m"

echo -e "\e[33mStarting Rsyslog service...\e[0m"

systemctl start rsyslog > /dev/null 2>&1

check_rsyslog_status
if [ $? -eq 0 ]; then

echo -e "\e[32mRsyslog started Successfully.\e[0m"

else
echo -e "\e[31mFailed to start Rsyslog!! Check Manually..\e[0m"

fi
fi

