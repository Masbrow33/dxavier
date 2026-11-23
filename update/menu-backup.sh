#!/bin/bash
dateFromServer=$(curl -v --insecure --silent https://google.com/ 2>&1 | grep Date | sed -e 's/< Date: //')
biji=`date +"%Y-%m-%d" -d "$dateFromServer"`
###########- COLOR CODE -##############
colornow=$(head -1 /etc/yokkovpn/theme/color.conf 2>/dev/null | tr -d ' \r\n')
[ -z "$colornow" ] && colornow=green
[ -f "/etc/yokkovpn/theme/$colornow" ] || colornow=green
NC="\e[0m"
RED="\033[0;31m" 
COLOR1="$(grep -w "TEXT" "/etc/yokkovpn/theme/$colornow" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' \r\n')"
[ -z "$COLOR1" ] && COLOR1='\033[0;32m'
COLBG1="$(grep -w "BG" "/etc/yokkovpn/theme/$colornow" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' \r\n')"
[ -z "$COLBG1" ] && COLBG1='\E[40;1;42m'
###########- END COLOR CODE -##########


clear
echo -e "$COLOR1┌─────────────────────────────────────────────────┐${NC}"
echo -e "$COLOR1│${NC} ${COLBG1}             • BACKUP PANEL MENU •             ${NC} $COLOR1│$NC"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}"
echo -e " $COLOR1┌───────────────────────────────────────────────┐${NC}"
echo -e " $COLOR1│$NC   ${COLOR1}[01]${NC} • BACKUP VPS      ${COLOR1}[03]${NC} • BACKUP API    $COLOR1│$NC"
echo -e " $COLOR1│$NC   ${COLOR1}[02]${NC} • RESTORE VPS     ${COLOR1}[04]${NC} • RESET API     $COLOR1│$NC"
echo -e " $COLOR1│$NC                                               $COLOR1│$NC"
echo -e " $COLOR1│$NC   ${COLOR1}[00]${NC} • GO BACK${NC}                              $COLOR1│$NC"
echo -e " $COLOR1└───────────────────────────────────────────────┘${NC}"
echo -e "$COLOR1┌────────────────────── BY ───────────────────────┐${NC}"
echo -e "$COLOR1│${NC}             • ARTA MAULANA PREMI •              $COLOR1│$NC"
echo -e "$COLOR1└─────────────────────────────────────────────────┘${NC}"
echo -e ""
read -p " Select menu :  "  opt
echo -e ""
case $opt in
01 | 1) clear ; backup ;;
02 | 2) clear ; restore ;;
03 | 3) clear ; menu3 ;;
04 | 4) clear ; menu4 ;;
00 | 0) clear ; menu ;;
*) clear ; menu-backup ;;
esac

       
