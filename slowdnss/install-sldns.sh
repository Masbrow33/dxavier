#!/bin/bash
# ==========================================================
#  SlowDNS Installer
#  Self-contained: semua binary & key diambil dari repo sendiri
#  (Masbrow33/dxavier/slowdnss) — tidak bergantung repo pihak lain.
#
#  Dipanggil oleh: setup.sh (baris ~337)
#  Hasil: service server-sldns + client-sldns aktif
# ==========================================================
set -uo pipefail

REPO="https://raw.githubusercontent.com/Masbrow33/dxavier/main/slowdnss"
red='\e[1;31m'; green='\e[1;32m'; yell='\e[1;33m'; NC='\e[0m'
ok()   { echo -e "${green}[ OK ]${NC} $*"; }
warn() { echo -e "${yell}[WARN]${NC} $*"; }
err()  { echo -e "${red}[FAIL]${NC} $*"; }

# --- port & path ---
SLDNS_DIR="/etc/slowdns"
SRV_UDP_PORT="5300"     # port DNS tunnel (UDP)
SSH_PORT="2269"         # port SSH lokal tujuan tunnel
CLIENT_SSH_PORT="3369"  # port SSH tambahan untuk client
DNS_UPSTREAM="8.8.8.8:53"

echo "=============================================="
echo "          SLOWDNS INSTALLER"
echo "=============================================="

# ---------------------------------------------------------- 1. root check
if [ "${EUID}" -ne 0 ]; then
    err "Harus dijalankan sebagai root."
    exit 1
fi

# ---------------------------------------------------------- 2. nameserver
NS=""
for f in /etc/xray/domain /root/domain /root/scdomain; do
    if [ -s "$f" ]; then NS=$(head -n1 "$f" | tr -d '\r\n '); break; fi
done
if [ -z "$NS" ]; then
    warn "Domain tidak ditemukan di /etc/xray/domain."
    read -rp "Input nameserver domain (contoh: ns.domainkamu.com) : " NS
fi
if [ -z "$NS" ]; then
    err "Nameserver kosong — SlowDNS tidak bisa dipasang."
    exit 1
fi
ok "Nameserver: $NS"

# ---------------------------------------------------------- 3. dependency
echo "[1/6] Memasang paket pendukung..."
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq python3 python3-dnslib net-tools dnsutils \
    cron iptables screen curl wget >/dev/null 2>&1
ok "Paket dasar terpasang"

# ---------------------------------------------------------- 4. binary & key
echo "[2/6] Mengunduh binary & key dari repo sendiri..."
rm -rf "$SLDNS_DIR"
mkdir -p "$SLDNS_DIR"
chmod 755 "$SLDNS_DIR"

fetch() {  # $1=file, $2=dest
    local url="$REPO/$1" dest="$2"
    for attempt in 1 2 3; do
        if wget -q --no-check-certificate --timeout=30 --tries=2 -O "$dest" "$url"; then
            if [ -s "$dest" ]; then return 0; fi
        fi
        sleep 2
    done
    return 1
}

fail=0
for f in sldns-server sldns-client server.key server.pub; do
    if fetch "$f" "$SLDNS_DIR/$f"; then
        ok "  $f ($(stat -c %s "$SLDNS_DIR/$f") byte)"
    else
        err "  $f GAGAL diunduh"
        fail=1
    fi
done
if [ "$fail" -ne 0 ]; then
    err "Ada file yang gagal diunduh. SlowDNS dibatalkan."
    exit 1
fi

chmod +x "$SLDNS_DIR/sldns-server" "$SLDNS_DIR/sldns-client"
chmod 600 "$SLDNS_DIR/server.key"
chmod 644 "$SLDNS_DIR/server.pub"

# ---------------------------------------------------------- 5. port SSH
echo "[3/6] Menyiapkan port SSH tambahan..."
for p in "$SSH_PORT" "$CLIENT_SSH_PORT"; do
    if ! grep -qE "^Port[[:space:]]+${p}$" /etc/ssh/sshd_config 2>/dev/null; then
        echo "Port $p" >> /etc/ssh/sshd_config
        ok "  Port $p ditambahkan ke sshd_config"
    else
        ok "  Port $p sudah ada"
    fi
done
sed -i 's/^#*AllowTcpForwarding.*/AllowTcpForwarding yes/' /etc/ssh/sshd_config 2>/dev/null
# validasi konfigurasi sebelum restart
if sshd -t 2>/dev/null; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
    ok "sshd direload"
else
    warn "sshd_config gagal validasi — reload dilewati"
fi

# ---------------------------------------------------------- 6. systemd unit
echo "[4/6] Membuat systemd service..."

cat > /etc/systemd/system/server-sldns.service <<EOF
[Unit]
Description=SlowDNS Server (DNS tunnel -> SSH :${SSH_PORT})
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${SLDNS_DIR}/sldns-server -udp :${SRV_UDP_PORT} -privkey-file ${SLDNS_DIR}/server.key ${NS} 127.0.0.1:${SSH_PORT}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/client-sldns.service <<EOF
[Unit]
Description=SlowDNS Client (outbound DNS tunnel)
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${SLDNS_DIR}/sldns-client -udp ${DNS_UPSTREAM} --pubkey-file ${SLDNS_DIR}/server.pub ${NS} 127.0.0.1:${CLIENT_SSH_PORT}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/server-sldns.service
chmod 644 /etc/systemd/system/client-sldns.service
systemctl daemon-reload
ok "Unit dibuat"

# ---------------------------------------------------------- 7. firewall
echo "[5/6] Membuka port di iptables..."
iptables -I INPUT -p udp --dport "$SRV_UDP_PORT" -j ACCEPT 2>/dev/null && ok "  UDP $SRV_UDP_PORT dibuka" || warn "  gagal buka UDP $SRV_UDP_PORT"
iptables -I INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT 2>/dev/null && ok "  TCP $SSH_PORT dibuka" || true
iptables -I INPUT -p tcp --dport "$CLIENT_SSH_PORT" -j ACCEPT 2>/dev/null && ok "  TCP $CLIENT_SSH_PORT dibuka" || true
# simpan aturan bila netfilter-persistent tersedia
if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 && ok "  aturan iptables disimpan"
elif [ -d /etc/iptables ]; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null && ok "  aturan disimpan ke rules.v4"
fi

# ---------------------------------------------------------- 8. jalankan
echo "[6/6] Mengaktifkan service..."
pkill -f sldns-server 2>/dev/null || true
pkill -f sldns-client 2>/dev/null || true
sleep 1

systemctl enable server-sldns >/dev/null 2>&1
systemctl enable client-sldns >/dev/null 2>&1
systemctl restart server-sldns
sleep 2
systemctl restart client-sldns
sleep 2

echo ""
echo "----------------------------------------------"
SRV=$(systemctl is-active server-sldns 2>/dev/null)
CLI=$(systemctl is-active client-sldns 2>/dev/null)
echo "  server-sldns : $SRV"
echo "  client-sldns : $CLI"
echo "  nameserver   : $NS"
echo "  UDP port     : $SRV_UDP_PORT"
echo "  SSH target   : 127.0.0.1:$SSH_PORT"
echo "----------------------------------------------"

if [ "$SRV" = "active" ] && [ "$CLI" = "active" ]; then
    ok "SLOWDNS BERHASIL DIPASANG"
else
    warn "Service belum aktif. Cek log:"
    echo "  journalctl -u server-sldns -n 20 --no-pager"
    echo "  journalctl -u client-sldns -n 20 --no-pager"
    # jangan exit 1: setup.sh harus lanjut ke komponen berikutnya
fi

# bersihkan file installer
cd /root 2>/dev/null && rm -f install-sldns.sh 2>/dev/null
exit 0
