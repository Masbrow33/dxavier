#!/bin/bash
# ==========================================================
#  dependencies.sh — paket dasar untuk autoscript
#
#  Kenapa versi ini mencetak progress:
#  Versi lama membuang SEMUA keluaran apt ke /dev/null. Setelah baris
#  "sudo is already the newest version", layar diam bermenit-menit
#  padahal script masih memasang ~60 paket satu per satu. Pengguna
#  mengira script berhenti lalu menjalankannya lagi. Dua-tiga instalasi
#  berjalan bersamaan, saling mengunci dpkg, dan VPS kehabisan memori
#  sampai tidak bisa di-SSH.
#
#  Sekarang: nomor urut per paket, log lengkap, dan apt diminta
#  menunggu lock (DPkg::Lock::Timeout) alih-alih menggantung diam.
# ==========================================================
[ -n "$TERM" ] && clear 2>/dev/null || true
red='\e[1;31m'
green='\e[1;32m'
yell='\e[1;33m'
NC='\e[0m'
green() { echo -e "\033[32;1m${*}\033[0m"; }
red()   { echo -e "\033[31;1m${*}\033[0m"; }
yellow(){ echo -e "\033[33;1m${*}\033[0m"; }

LOG=/var/log/yokkovpn-deps.log
: > "$LOG" 2>/dev/null || { LOG=/tmp/yokkovpn-deps.log; : > "$LOG"; }

# Opsi apt: tunggu lock maksimal 5 menit, jangan menggantung selamanya.
APT_OPTS="-o DPkg::Lock::Timeout=300 -o Dpkg::Use-Pty=0"

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

# --- tunggu apt lain selesai, dengan pemberitahuan ---
_apt_wait() {
    local i=0
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        [ "$i" -eq 0 ] && yellow "Menunggu proses apt lain selesai (maks 5 menit)..."
        i=$((i+1))
        [ "$i" -ge 300 ] && { red "Lock apt tidak lepas setelah 5 menit."; return 1; }
        sleep 1
    done
    return 0
}

yellow "[1/5] apt update"
_apt_wait && apt update -y >>"$LOG" 2>&1 || true
echo "      selesai"

# dist-upgrade bisa memasang kernel baru -> VPS butuh reboot di tengah
# instalasi -> sesi SSH putus. Pakai upgrade biasa dan tahan paket kernel.
yellow "[2/5] apt upgrade"
_apt_wait && apt upgrade -y $APT_OPTS >>"$LOG" 2>&1 || true
echo "      selesai"

yellow "[3/5] tahan paket kernel + sudo"
apt-mark hold linux-image-generic linux-headers-generic linux-virtual \
    linux-image-virtual >>"$LOG" 2>&1 || true
_apt_wait && apt install -y sudo $APT_OPTS >>"$LOG" 2>&1 || true
echo "      selesai"

# --- hapus paket yang konflik dengan autoscript ---
yellow "[4/5] hapus ufw / firewalld / exim4"
_apt_wait && apt-get remove --purge -y ufw firewalld exim4 $APT_OPTS >>"$LOG" 2>&1 || true
echo "      selesai"

# ----------------------------------------------------------
#  Install paket. Coba borongan dulu (cepat). Kalau ada satu nama
#  paket yang tidak tersedia di repo, ulangi satu per satu supaya
#  paket lain tetap terpasang.
# ----------------------------------------------------------
PKGS_CORE="screen curl jq bzip2 gzip coreutils rsyslog iftop htop zip unzip \
net-tools sed bc sudo build-essential git lsof openssl \
fail2ban tmux stunnel4 vnstat dropbear libsqlite3-dev \
socat cron bash-completion xz-utils gnupg dnsutils lsb-release chrony \
openvpn easy-rsa libpam0g-dev libcap-ng-dev libcap-ng-utils \
libcurl4-openssl-dev flex bison make libevent-dev \
netfilter-persistent iptables-persistent whois dos2unix"

PKGS_OPTIONAL="gnupg1 apt-transport-https dirmngr libxml-parser-perl \
neofetch screenfetch squid ntpdate xl2tpd pptpd \
libnss3-dev libnspr4-dev pkg-config libselinux1-dev \
libnss3-tools libcurl4-nss-dev"

yellow "[5/5] pasang paket"
_apt_wait

# debconf noninteraktif untuk paket yang biasanya bertanya
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections 2>/dev/null || true
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections 2>/dev/null || true

TOTAL=$(echo $PKGS_CORE $PKGS_OPTIONAL | wc -w)
printf "      %d paket, memasang sekaligus... " "$TOTAL"
if timeout 900 apt-get install -y -qq $APT_OPTS $PKGS_CORE $PKGS_OPTIONAL >>"$LOG" 2>&1; then
    echo "OK"
    installed=$TOTAL; skipped=0
else
    echo "ada yang tidak tersedia, ulangi satu per satu"
    installed=0; skipped=0; n=0
    for p in $PKGS_CORE $PKGS_OPTIONAL; do
        n=$((n+1))
        if dpkg -s "$p" >/dev/null 2>&1; then
            installed=$((installed+1))
            continue
        fi
        printf "      [%2d/%d] %-26s " "$n" "$TOTAL" "$p"
        if timeout 300 apt-get install -y -qq $APT_OPTS "$p" >>"$LOG" 2>&1; then
            printf "OK\n"; installed=$((installed+1))
        else
            printf "dilewati\n"; skipped=$((skipped+1))
        fi
    done
fi
green "Paket terpasang: $installed | dilewati (tidak tersedia): $skipped"

# --- Node.js ---
if ! command -v node >/dev/null 2>&1; then
    yellow "Node.js belum ada, memasang..."
    curl -fsSL https://deb.nodesource.com/setup_20.x 2>/dev/null | bash - >>"$LOG" 2>&1
    timeout 300 apt-get install -y nodejs $APT_OPTS >>"$LOG" 2>&1 || true
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
echo "Log lengkap: $LOG"
sleep 3
[ -n "$TERM" ] && clear 2>/dev/null || true
