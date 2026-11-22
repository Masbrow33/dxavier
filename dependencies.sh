#!/bin/bash
# ==========================================================
#  dependencies.sh — paket dasar untuk autoscript
#  Diperbaiki: syntax error (fi yatim), $NET tak terdefinisi,
#  dan paket usang yang tidak ada lagi di Debian/Ubuntu baru.
# ==========================================================
clear
red='\e[1;31m'
green='\e[1;32m'
yell='\e[1;33m'
NC='\e[0m'
green() { echo -e "\033[32;1m${*}\033[0m"; }
red()   { echo -e "\033[31;1m${*}\033[0m"; }
yellow(){ echo -e "\033[33;1m${*}\033[0m"; }

if [[ -e /etc/debian_version ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    OS=$ID   # debian atau ubuntu
elif [[ -e /etc/centos-release ]]; then
    source /etc/os-release
    OS=centos
else
    OS=unknown
fi

echo "Tools install...!"
echo "Progress..."
sleep 2

export DEBIAN_FRONTEND=noninteractive

apt update -y
# dist-upgrade bisa memasang kernel baru -> VPS butuh reboot di tengah
# instalasi -> sesi SSH putus. Pakai upgrade biasa dan tahan paket kernel.
apt upgrade -y
apt-mark hold linux-image-generic linux-headers-generic linux-virtual \
    linux-image-virtual 2>/dev/null || true
apt install -y sudo

# --- hapus paket yang konflik dengan autoscript ---
apt-get remove --purge -y ufw firewalld exim4 >/dev/null 2>&1 || true

# ----------------------------------------------------------
#  Install paket satu per satu supaya satu paket hilang
#  tidak menggagalkan seluruh instalasi.
# ----------------------------------------------------------
PKGS_CORE="screen curl jq bzip2 gzip coreutils rsyslog iftop htop zip unzip \
net-tools sed bc sudo build-essential git lsof openssl \
fail2ban tmux stunnel4 vnstat dropbear libsqlite3-dev \
socat cron bash-completion xz-utils gnupg dnsutils lsb-release chrony \
openvpn easy-rsa libpam0g-dev libcap-ng-dev libcap-ng-utils \
libcurl4-openssl-dev flex bison make libevent-dev \
netfilter-persistent iptables-persistent whois dos2unix"

PKGS_OPTIONAL="gnupg1 apt-transport-https dirmngr libxml-parser-perl \
neofetch screenfetch squid3 ntpdate xl2tpd pptpd \
libnss3-dev libnspr4-dev pkg-config libselinux1-dev \
libnss3-tools libcurl4-nss-dev"

installed=0; skipped=0
for p in $PKGS_CORE $PKGS_OPTIONAL; do
    if dpkg -s "$p" >/dev/null 2>&1; then
        installed=$((installed+1))
        continue
    fi
    if apt-get install -y -qq "$p" >/dev/null 2>&1; then
        installed=$((installed+1))
    else
        skipped=$((skipped+1))
    fi
done
green "Paket terpasang: $installed | dilewati (tidak tersedia): $skipped"

# --- Node.js ---
if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_20.x 2>/dev/null | bash - >/dev/null 2>&1
    apt-get install -y nodejs >/dev/null 2>&1 || true
fi

# ----------------------------------------------------------
#  vnstat: paket apt sudah cukup. Build dari source hanya
#  kalau binary-nya benar-benar tidak ada.
# ----------------------------------------------------------
NET=$(ip -o -4 route show default 2>/dev/null | awk '{print $5}' | head -n1)
if [ -z "$NET" ]; then
    NET=$(ip -o link show 2>/dev/null | awk -F': ' '$2 != "lo" {print $2; exit}')
fi
[ -z "$NET" ] && NET="eth0"
yellow "Interface terdeteksi: $NET"

if ! command -v vnstat >/dev/null 2>&1; then
    yellow "vnstat tidak ada, build dari source..."
    cd /root || cd /tmp || exit 1
    wget -q https://humdi.net/vnstat/vnstat-2.6.tar.gz
    if [ -s vnstat-2.6.tar.gz ]; then
        tar zxf vnstat-2.6.tar.gz
        cd vnstat-2.6 || exit 1
        ./configure --prefix=/usr --sysconfdir=/etc >/dev/null 2>&1 \
            && make >/dev/null 2>&1 \
            && make install >/dev/null 2>&1
        cd /
    fi
    rm -f /root/vnstat-2.6.tar.gz >/dev/null 2>&1
    rm -rf /root/vnstat-2.6 >/dev/null 2>&1
fi

if command -v vnstat >/dev/null 2>&1; then
    [ -f /etc/vnstat.conf ] && sed -i "s/^Interface .*/Interface \"$NET\"/" /etc/vnstat.conf 2>/dev/null
    vnstat -u -i "$NET" >/dev/null 2>&1 || true
    mkdir -p /var/lib/vnstat
    chown -R vnstat:vnstat /var/lib/vnstat 2>/dev/null || true
    systemctl enable vnstat >/dev/null 2>&1 || true
    systemctl restart vnstat >/dev/null 2>&1 || true
    green "vnstat siap pada interface $NET"
else
    red "vnstat gagal dipasang — monitoring bandwidth tidak akan berfungsi"
fi

yellow "Dependencies successfully installed..."
sleep 3
clear
