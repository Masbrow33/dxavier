#!/bin/bash
# Websocket installer (ws-dropbear + ws-stunnel + ws-openssh)
# Semua file diambil dari repo sendiri (Masbrow33/dxavier), bukan pihak ketiga.
#
# Kenapa unduhan lewat berkas sementara: wget -O mengosongkan berkas tujuan
# sebelum unduhan selesai. Bila jaringan gagal di tengah jalan, yang tersisa
# adalah berkas kosong. Untuk skrip Python yang kosong, systemd tetap
# menjalankannya, prosesnya langsung mati, dan service terlihat enabled
# tetapi tidak pernah aktif — tanpa pesan yang menunjukkan sebab sebenarnya.

BASE="https://raw.githubusercontent.com/Masbrow33/dxavier/main/websocket"

cd || exit 1

# Pastikan python3 ada (Debian 12 tidak punya /usr/bin/python)
if ! command -v python3 >/dev/null 2>&1; then
    apt-get install -y -qq python3 >/dev/null 2>&1 || true
fi

GAGAL=0

# $1 = nama berkas di repo, $2 = tujuan, $3 = py|sh|unit
ambil() {
    local nama="$1" tujuan="$2" jenis="${3:-sh}" tmpf
    tmpf=$(mktemp "/tmp/ws.XXXXXX") || { GAGAL=$((GAGAL + 1)); return 1; }

    if ! wget -q --timeout=25 --tries=2 -O "$tmpf" "$BASE/$nama"; then
        rm -f "$tmpf"
        echo "[WARN] gagal mengunduh $nama"
        GAGAL=$((GAGAL + 1)); return 1
    fi

    if [ ! -s "$tmpf" ]; then
        rm -f "$tmpf"
        echo "[WARN] $nama kosong"
        GAGAL=$((GAGAL + 1)); return 1
    fi

    # Berkas Python diperiksa bisa dikompilasi. Ini menangkap unduhan
    # terpotong sebelum service dipasang lalu gagal tanpa penjelasan.
    if [ "$jenis" = "py" ] && ! python3 -m py_compile "$tmpf" 2>/dev/null; then
        rm -f "$tmpf"
        echo "[WARN] $nama bukan Python yang sah"
        GAGAL=$((GAGAL + 1)); return 1
    fi

    if [ "$jenis" = "sh" ] && ! bash -n "$tmpf" 2>/dev/null; then
        rm -f "$tmpf"
        echo "[WARN] $nama bukan shell yang sah"
        GAGAL=$((GAGAL + 1)); return 1
    fi

    mkdir -p "$(dirname "$tujuan")"
    if mv -f "$tmpf" "$tujuan"; then
        if [ "$jenis" = "unit" ]; then
            chmod 644 "$tujuan"
        else
            chmod +x "$tujuan"
        fi
        echo "[ OK ] $nama -> $tujuan"
        return 0
    fi

    rm -f "$tmpf"
    echo "[WARN] tidak bisa menulis $tujuan"
    GAGAL=$((GAGAL + 1)); return 1
}

ambil "dropbear-ws.py"     "/usr/local/bin/ws-dropbear"              py
ambil "ws-stunnel"         "/usr/local/bin/ws-stunnel"               py
ambil "openssh-socket.py"  "/usr/local/bin/ws-openssh"               py

ambil "service-wsopenssh"  "/etc/systemd/system/ws-openssh.service"  unit
ambil "service-wsdropbear" "/etc/systemd/system/ws-dropbear.service" unit
ambil "ws-stunnel.service" "/etc/systemd/system/ws-stunnel.service"  unit

# Pengaman: kalau service masih menunjuk /usr/bin/python, ganti ke python3
sed -i 's|/usr/bin/python |/usr/bin/python3 |g; s|/usr/bin/python$|/usr/bin/python3|g' \
    /etc/systemd/system/ws-dropbear.service \
    /etc/systemd/system/ws-stunnel.service \
    /etc/systemd/system/ws-openssh.service 2>/dev/null

systemctl daemon-reload

# Jangan start service yang berkasnya gagal terpasang. Lebih jelas
# melaporkan satu service dilewati daripada membiarkan systemd mencoba
# lalu gagal berulang kali.
UNITS=""
for pair in "ws-dropbear:/usr/local/bin/ws-dropbear" \
            "ws-stunnel:/usr/local/bin/ws-stunnel" \
            "ws-openssh:/usr/local/bin/ws-openssh"; do
    u="${pair%%:*}"
    f="${pair##*:}"
    if [ -s "$f" ] && [ -f "/etc/systemd/system/$u.service" ]; then
        UNITS="$UNITS $u.service"
    else
        echo "[WARN] $u dilewati (berkas tidak lengkap)"
    fi
done

if [ -n "$UNITS" ]; then
    systemctl enable $UNITS >/dev/null 2>&1
    systemctl restart $UNITS
fi

sleep 2
for s in ws-dropbear ws-stunnel ws-openssh; do
    [ -f "/etc/systemd/system/$s.service" ] || continue
    st=$(systemctl is-active "$s" 2>&1)
    if [ "$st" = "active" ]; then
        echo "[ OK ] $s aktif"
    else
        echo "[WARN] $s $st — cek: journalctl -u $s -n 20"
    fi
done

if [ "$GAGAL" -gt 0 ]; then
    echo "[WARN] $GAGAL berkas gagal dipasang — jalankan ulang installer ini"
fi
