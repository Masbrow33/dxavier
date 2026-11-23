#!/bin/bash
MYIP=$(wget -qO- ipinfo.io/ip);

colornow=$(head -1 /etc/yokkovpn/theme/color.conf 2>/dev/null | tr -d ' \r\n')
[ -z "$colornow" ] && colornow=green
[ -f "/etc/yokkovpn/theme/$colornow" ] || colornow=green
NC="\e[0m"
COLOR1="$(grep -w "TEXT" "/etc/yokkovpn/theme/$colornow" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' \r\n')"
[ -z "$COLOR1" ] && COLOR1='\033[0;32m'
COLBG1="$(grep -w "BG" "/etc/yokkovpn/theme/$colornow" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' \r\n')"
[ -z "$COLBG1" ] && COLBG1='\E[40;1;42m'

APIGIT=$(cat /etc/yokkovpn/github/api)
EMAILGIT=$(cat /etc/yokkovpn/github/email)
USERGIT=$(cat /etc/yokkovpn/github/username)

export RED='\033[0;31m';
export GREEN='\033[0;32m';
export ERROR="[${RED}ERROR${NC}]";
export INFO="[${GREEN}INFO${NC}]";


function setdns(){
clear
echo -e "$COLOR1┌─────────────────────────────────────────────────┐${NC}"
echo -e "$COLOR1│${NC} ${COLBG1}                 • USERS LOGS •                ${NC} $COLOR1│$NC"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}"
echo -e "$COLOR1┌─────────────────────────────────────────────────┐${NC}"
read -p "│  DNS : " setdnss

if [ -z $setdnss ]; then
echo -e "$COLOR1│${NC}"
echo -e "$COLOR1│${NC}  ${ERROR} DNS Cannot Be Empty";
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}" 
echo -e "$COLOR1┌────────────────────── BY ───────────────────────┐${NC}"
echo -e "$COLOR1│${NC}             • ARTA MAULANA PREMI •              $COLOR1│$NC"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}" 
echo -e ""
read -n 1 -s -r -p "   Press any key to back on menu"
menu-dns 
else
echo "$setdnss" > /root/dns
echo -e "$COLOR1│${NC}  ${INFO} Copy DNS To Resolv.conf";
echo "nameserver $setdnss" > /etc/resolv.conf
sleep 2
echo -e "$COLOR1│${NC}  ${INFO} Copy DNS To Resolv.conf.d/head";
echo "nameserver $setdnss" > /etc/resolvconf/resolv.conf.d/head
sleep 2
echo -e "$COLOR1│${NC}  ${INFO} DNS Update Successfully";
fi
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}" 
echo -e "$COLOR1┌────────────────────── BY ───────────────────────┐${NC}"
echo -e "$COLOR1│${NC}             • ARTA MAULANA PREMI •              $COLOR1│$NC"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}" 
echo -e ""
read -n 1 -s -r -p "   Press any key to back on menu"
menu-dns 
}

function resdns(){
    clear
echo -e "$COLOR1┌─────────────────────────────────────────────────┐${NC}"
echo -e "$COLOR1│${NC} ${COLBG1}                 • USERS LOGS •                ${NC} $COLOR1│$NC"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}"
echo -e "$COLOR1┌─────────────────────────────────────────────────┐${NC}"
read -p "│   Reset Default DNS [Y/N]: " -e answer
if [[ "$answer" = 'y' ]]; then
dnsfile="/root/dns"
if test -f "$dnsfile"; then
rm /root/dns
fi
echo -e "$COLOR1│${NC}"
echo -e "$COLOR1│${NC}  ${INFO} Delete Resolv.conf DNS";
echo "nameserver 8.8.8.8" > /etc/resolv.conf
sleep 2
echo -e "$COLOR1│${NC}  ${INFO} Delete Resolv.conf.d/head DNS";
echo "nameserver 8.8.8.8" > /etc/resolvconf/resolv.conf.d/head
sleep 2
else
echo -e "$COLOR1│${NC}"
echo -e "$COLOR1│${NC}   $INFO Operation Cancelled By User"
fi
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}" 
echo -e "$COLOR1┌────────────────────── BY ───────────────────────┐${NC}"
echo -e "$COLOR1│${NC}             • ARTA MAULANA PREMI •              $COLOR1│$NC"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}" 
echo -e ""
read -n 1 -s -r -p "   Press any key to back on menu"
menu-dns 
}

clear
echo -e "$COLOR1┌─────────────────────────────────────────────────┐${NC}"
echo -e "$COLOR1│${NC} ${COLBG1}                 • USERS LOGS •                ${NC} $COLOR1│$NC"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}"
echo -e "$COLOR1┌─────────────────────────────────────────────────┐${NC}"

dnsfile="/root/dns"
if test -f "$dnsfile"; then
udns=$(cat /root/dns)
echo -e "$COLOR1│${NC}"
echo -e "$COLOR1│${NC}   Active DNS : $udns"
echo -e "$COLOR1│${NC}"
fi
echo -e "$COLOR1│${NC}  $COLOR1 [01]$NC • CHANGE DNS       $COLOR1 [03]$NC • CONTENT CEK" 
echo -e "$COLOR1│${NC}  $COLOR1 [02]$NC • RESET DNS        $COLOR1 [04]$NC • REBOOT"
echo -e "$COLOR1│${NC}"
echo -e "$COLOR1│${NC}  $COLOR1 [00]$NC • GO BACK"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}" 
echo -e "$COLOR1┌────────────────────── BY ───────────────────────┐${NC}"
echo -e "$COLOR1│${NC}             • ARTA MAULANA PREMI •              $COLOR1│$NC"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}" 
echo -e ""
read -p " Select menu :  "  opt
echo -e   ""
case $opt in
01 | 1) clear ; setdns ;;
02 | 2) clear ; resdns ;;
03 | 3) clear ; delipvps ;;
04 | 4) clear ; renewipvps ;;
05 | 5) clear ; useripvps ;;
06 | 6) clear ; $ressee ;;
00 | 0) clear ; menu ;;
*) clear ; menu-dns ;;
esac
