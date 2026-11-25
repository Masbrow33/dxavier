#!/bin/bash
# ==========================================================
#  BadVPN Installer (UDP Gateway)
#  Hanya untuk x86_64 (ARM tidak support)
#  Dipanggil oleh: setup.sh
# ==========================================================
set -uo pipefail

red='\e[1;31m'; green='\e[1;32m'; yell='\e[1;33m'; NC='\e[0m'
ok()   { echo -e "${green}[ OK ]${NC} $*"; }
warn() { echo -e "${yell}[WARN]${NC} $*"; }
err()  { echo -e "${red}[FAIL]${NC} $*"; }

# Port UDP Gateway (7100-7900)
UDPGW_PORTS=(7100 7200 7300 7400 7500 7600 7700 7800 7900)
BADVPN_DIR="/usr/local/badvpn"

# ---------------------------------------------------------- 1. root check
if [ "${EUID}" -ne 0 ]; then
    err "Harus dijalankan sebagai root."
    exit 1
fi

# ---------------------------------------------------------- 2. dependency
ok "Memasang dependensi..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    -o DPkg::Lock::Timeout=300 -o Dpkg::Use-Pty=0 \
    build-essential cmake git \
    </dev/null >/dev/null 2>&1 || {
    err "Gagal instal dependensi"
    exit 1
}

# ---------------------------------------------------------- 3. clone & build BadVPN
ok "Mengunduh dan compile BadVPN..."
mkdir -p "$BADVPN_DIR"
cd "$BADVPN_DIR" || exit 1

if [ ! -d "badvpn" ]; then
    git clone https://github.com/ambrop72/badvpn.git 2>/dev/null || {
        err "Gagal clone repo BadVPN"
        exit 1
    }
fi

cd badvpn || exit 1
if [ ! -f "badvpn" ]; then
    cmake . 2>/dev/null >/dev/null
    make 2>/dev/null >/dev/null || {
        err "Gagal compile BadVPN"
        exit 1
    }
fi

# ---------------------------------------------------------- 4. setup UDP Gateway
ok "Mempersiapkan UDP Gateway..."
for port in "${UDPGW_PORTS[@]}"; do
    cat > /etc/systemd/system/badvpn-udpgw-${port}.service <<EOF
[Unit]
Description=BadVPN UDP Gateway Port $port
After=network.target

[Service]
Type=simple
ExecStart=${BADVPN_DIR}/badvpn/badvpn-udpgw -l 127.0.0.1:$port -t 127.0.0.1:7300 -m 1500
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 /etc/systemd/system/badvpn-udpgw-${port}.service
    systemctl enable badvpn-udpgw-${port}.service 2>/dev/null
    systemctl start badvpn-udpgw-${port}.service 2>/dev/null
    ok "  UDP Gateway port $port aktif"
done

# ---------------------------------------------------------- 5. verifikasi
ok "Verifikasi BadVPN..."
sleep 2
active_ports=0
for port in "${UDPGW_PORTS[@]}"; do
    if ss -lun 2>/dev/null | grep -q ":${port}"; then
        ((active_ports++))
    fi
done

if [ "$active_ports" -ge 9 ]; then
    ok "BadVPN BERHASIL DIPASANG (${active_ports}/9 port aktif)"
else
    warn "BadVPN terpasang tetapi hanya ${active_ports}/9 port aktif"
    warn "Cek log: journalctl -u badvpn-udpgw-* -n 20 --no-pager"
fi

# Bersihkan
cd /root 2>/dev/null
rm -f install-badvpn.sh 2>/dev/null
exit 0
