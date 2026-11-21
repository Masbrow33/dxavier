#!/bin/bash
# Websocket installer (ws-dropbear + ws-stunnel)
# Semua file diambil dari repo sendiri (Masbrow33/dxavier), bukan pihak ketiga.
BASE="https://raw.githubusercontent.com/Masbrow33/dxavier/main/websocket"

cd

# Pastikan python3 ada (Debian 12 tidak punya /usr/bin/python)
if ! command -v python3 >/dev/null 2>&1; then
    apt-get install -y -qq python3 >/dev/null 2>&1 || true
fi

wget -q -O /usr/local/bin/ws-dropbear "$BASE/dropbear-ws.py"
wget -q -O /usr/local/bin/ws-stunnel "$BASE/ws-stunnel"

chmod +x /usr/local/bin/ws-dropbear
chmod +x /usr/local/bin/ws-stunnel

wget -q -O /etc/systemd/system/ws-dropbear.service "$BASE/service-wsdropbear"
wget -q -O /etc/systemd/system/ws-stunnel.service "$BASE/ws-stunnel.service"
chmod 644 /etc/systemd/system/ws-dropbear.service
chmod 644 /etc/systemd/system/ws-stunnel.service

# Pengaman: kalau service masih menunjuk /usr/bin/python, ganti ke python3
sed -i 's|/usr/bin/python |/usr/bin/python3 |g; s|/usr/bin/python$|/usr/bin/python3|g'     /etc/systemd/system/ws-dropbear.service /etc/systemd/system/ws-stunnel.service 2>/dev/null

systemctl daemon-reload
systemctl enable ws-dropbear.service ws-stunnel.service >/dev/null 2>&1
systemctl restart ws-dropbear.service ws-stunnel.service

sleep 2
for s in ws-dropbear ws-stunnel; do
    st=$(systemctl is-active "$s" 2>&1)
    if [ "$st" = "active" ]; then
        echo "[ OK ] $s aktif"
    else
        echo "[WARN] $s $st — cek: journalctl -u $s -n 20"
    fi
done
