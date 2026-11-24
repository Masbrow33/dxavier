#!/bin/bash
dateFromServer=$(curl -v --insecure --silent https://google.com/ 2>&1 | grep Date | sed -e 's/< Date: //')
biji=`date +"%Y-%m-%d" -d "$dateFromServer"`
#########################

echo -e "
"
date
echo ""
domain=$(cat /root/domain 2>/dev/null | tr -d '\r\n ')
# Pengaman: domain kosong -> nginx gagal (server_name tanpa argumen)
if [ -z "$domain" ]; then
    domain=$(cat /etc/xray/domain 2>/dev/null | tr -d '\r\n ')
fi
if [ -z "$domain" ]; then
    domain=$(curl -s -m 10 https://ipinfo.io/ip/ 2>/dev/null | tr -d '\r\n')
fi
if [ -z "$domain" ]; then
    domain="127.0.0.1"
fi
echo "[ INFO ] Domain yang dipakai: $domain"
sleep 1
mkdir -p /etc/xray 
echo -e "[ ${green}INFO${NC} ] Checking... "
apt install iptables iptables-persistent -y
sleep 1

# ---------------------------------------------------------------
# Sinkronisasi waktu. Blok lama bermasalah dalam tiga hal:
#
# 1. "systemctl enable chronyd" dijalankan sebelum paket chrony
#    dipasang (baru di baris 48). Unitnya belum ada, jadi perintah itu
#    gagal dan mengotori keluaran instalasi.
# 2. "chronyd" bukan nama unit di Ubuntu/Debian — yang benar "chrony".
#    Keduanya dipanggil, satu pasti gagal.
# 3. "ntpdate pool.ntp.org" dijalankan sebelum ntpdate dipasang, dan
#    ntpdate sudah usang di Ubuntu 24.04. Bila jam VPS melenceng jauh,
#    sertifikat TLS bisa ditolak saat mengunduh paket.
#
# Urutan yang benar: pasang paket dulu, lalu aktifkan, lalu verifikasi.
# ---------------------------------------------------------------
echo -e "[ ${green}INFO$NC ] Menyiapkan sinkronisasi waktu"

# Pastikan paket waktu tersedia (idempoten: apt tidak memasang ulang)
if ! dpkg -s chrony >/dev/null 2>&1; then
    apt-get install -y -qq chrony >/dev/null 2>&1 || true
fi

# Nama unit: coba chrony dulu (Ubuntu/Debian), chronyd hanya bila ada
_waktu_unit=""
for u in chrony chronyd; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${u}\.service"; then
        _waktu_unit="$u"
        break
    fi
done

if [ -n "$_waktu_unit" ]; then
    systemctl enable "$_waktu_unit" >/dev/null 2>&1 || true
    systemctl restart "$_waktu_unit" >/dev/null 2>&1 || true
    echo -e "[ ${green}ok${NC} ] $_waktu_unit aktif"
else
    # Fallback: systemd-timesyncd, selalu ada di Ubuntu
    systemctl enable systemd-timesyncd >/dev/null 2>&1 || true
    systemctl restart systemd-timesyncd >/dev/null 2>&1 || true
    echo -e "[ ${yell}WARN${NC} ] chrony tidak tersedia, memakai systemd-timesyncd"
fi

# Zona waktu Indonesia
timedatectl set-timezone Asia/Jakarta 2>/dev/null || \
    ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime

sleep 1
echo -e "[ ${green}INFO$NC ] Status sinkronisasi waktu"
# chronyc hanya ada bila paket chrony terpasang
if command -v chronyc >/dev/null 2>&1; then
    chronyc tracking 2>/dev/null | head -4 || true
fi
timedatectl status 2>/dev/null | grep -iE 'Time zone|synchronized|NTP' || true

echo -e "[ ${green}INFO$NC ] Setting dll"
apt clean all >/dev/null 2>&1 || true
apt update -qq >/dev/null 2>&1 || true
apt install -y curl socat xz-utils wget apt-transport-https gnupg dnsutils lsb-release zip pwgen openssl netcat-openbsd cron 2>/dev/null || true


# install xray
sleep 1
echo -e "[ ${green}INFO$NC ] Downloading & Installing xray core"
domainSock_dir="/run/xray";! [ -d $domainSock_dir ] && mkdir  $domainSock_dir
chown www-data.www-data $domainSock_dir
# Make Folder XRay
mkdir -p /var/log/xray
mkdir -p /etc/xray
# Service xray berjalan sebagai root (lihat xray.service), jadi log harus
# dimiliki root. Sebelumnya di-chown ke www-data sehingga Xray gagal start
# dengan "permission denied" saat membuka /var/log/xray/access.log.
chown -R root:root /var/log/xray
chmod 755 /var/log/xray
touch /var/log/xray/access.log
touch /var/log/xray/error.log
touch /var/log/xray/access2.log
touch /var/log/xray/error2.log
chmod 644 /var/log/xray/*.log
# / / Ambil Xray Core Version Terbaru
# Xray: pakai versi terbaru (v1.5.6 sudah tidak bisa dipasang oleh
# install-release.sh terbaru). Fallback ke versi terbaru bila gagal.
if ! command -v xray >/dev/null 2>&1 && [ ! -x /usr/local/bin/xray ]; then
    # PENTING: jangan pakai "bash -c \"$(curl ...)\" @ install".
    # Substitusi perintah di dalam tanda kutip ganda membuat isi skrip
    # installer dieksekusi sebagai argumen, bukan sebagai skrip utuh,
    # sehingga muncul "@: unknown option -- -" dan Xray tidak terpasang.
    # Unduh ke file dulu, baru jalankan.
    # Juga jangan pakai "-u www-data": opsi itu sudah tidak ada di
    # install-release.sh versi sekarang (service jalan sebagai root).
    curl -sL -o /tmp/xray-install.sh https://github.com/XTLS/Xray-install/raw/main/install-release.sh
    if [ -s /tmp/xray-install.sh ]; then
        bash /tmp/xray-install.sh install 2>&1 | tail -5
        rm -f /tmp/xray-install.sh
    fi
fi
if ! command -v xray >/dev/null 2>&1 && [ ! -x /usr/local/bin/xray ]; then
    echo -e "[ ${red}ERROR${NC} ] Xray gagal dipasang otomatis."
    echo -e "[ ${yellow}INFO${NC} ] Pasang manual: bash -c \"\$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)\" @ install"
fi

# PENTING: install-release.sh resmi MEMBUAT ULANG /var/log/xray menjadi
# milik user "xray" dengan mode 700. Service kita berjalan sebagai root
# dengan CapabilityBoundingSet terbatas (tanpa CAP_DAC_OVERRIDE), sehingga
# root TIDAK bisa menembus direktori 700 milik user lain dan Xray gagal:
#   "open /var/log/xray/access.log: permission denied"
# Perbaikan harus dijalankan SETELAH installer resmi, bukan sebelumnya.
mkdir -p /var/log/xray
chown -R root:root /var/log/xray
chmod 755 /var/log/xray
touch /var/log/xray/access.log /var/log/xray/error.log \
      /var/log/xray/access2.log /var/log/xray/error2.log
chmod 644 /var/log/xray/*.log 2>/dev/null || true



## crt xray
systemctl stop nginx

# ---------------------------------------------------------------
# Sertifikat TLS. Blok lama menjalankan acme.sh tanpa memeriksa hasil:
#
#   acme.sh --issue -d $domain --standalone -k ec-256
#   acme.sh --installcert -d $domain --fullchainpath /etc/xray/xray.crt
#
# Bila penerbitan gagal — domain belum propagate, port 80 diblokir,
# kena rate limit Let's Encrypt, atau $domain berupa IP address (LE
# TIDAK menerbitkan sertifikat untuk IP) — acme.sh tetap mencetak
# "Installing full chain to: /etc/xray/xray.crt" tetapi berkasnya
# berukuran 0 byte. nginx.conf lalu merujuk berkas kosong itu, nginx
# gagal start, dan SEMUA path WebSocket ikut mati. Pengguna hanya
# melihat "nginx failed" tanpa tahu sebabnya.
#
# Sekarang: sertifikat diverifikasi dulu, dan bila tidak sah dibuat
# self-signed agar layanan tetap hidup.
# ---------------------------------------------------------------

_buat_selfsigned() {
    mkdir -p /etc/xray
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout /etc/xray/xray.key -out /etc/xray/xray.crt -days 3650 \
        -subj "/C=ID/ST=Jakarta/L=Jakarta/O=EkoBellick/CN=${domain}" \
        >/dev/null 2>&1
    chmod 600 /etc/xray/xray.key 2>/dev/null
    chmod 644 /etc/xray/xray.crt 2>/dev/null
}

_cert_sah() {
    [ -s /etc/xray/xray.crt ] || return 1
    openssl x509 -noout -in /etc/xray/xray.crt >/dev/null 2>&1
}

# Apakah $domain berupa alamat IP? Let's Encrypt tidak menerbitkannya.
_is_ip() {
    case "$1" in
        *[a-zA-Z]) return 1 ;;   # ada huruf -> domain
    esac
    printf '%s' "$1" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'
}

if _is_ip "$domain"; then
    echo -e "[ ${yell}WARN${NC} ] Domain '$domain' berupa alamat IP."
    echo -e "[ ${yell}WARN${NC} ] Let's Encrypt tidak menerbitkan sertifikat untuk IP."
    echo -e "[ ${INFO} ] Memakai sertifikat self-signed agar nginx tetap hidup."
    _buat_selfsigned
else
    mkdir -p /root/.acme.sh
    curl -fsSL https://acme-install.netlify.app/acme.sh -o /root/.acme.sh/acme.sh 2>/dev/null
    chmod +x /root/.acme.sh/acme.sh 2>/dev/null

    if [ -x /root/.acme.sh/acme.sh ]; then
        /root/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1 || true
        /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
        /root/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256 2>&1 | tail -5
        /root/.acme.sh/acme.sh --installcert -d "$domain" \
            --fullchainpath /etc/xray/xray.crt \
            --keypath /etc/xray/xray.key 2>&1 | tail -3
    fi

    # Verifikasi: berkas harus ada, tidak kosong, dan benar-benar X.509
    if ! _cert_sah; then
        echo -e "[ ${yell}WARN${NC} ] Sertifikat Let's Encrypt gagal dibuat untuk '$domain'."
        echo -e "[ ${yell}WARN${NC} ] Penyebab umum: domain belum mengarah ke IP ini,"
        echo -e "[ ${yell}WARN${NC} ] port 80 tertutup, atau kena batas Let's Encrypt."
        echo -e "[ ${INFO} ] Memakai sertifikat self-signed agar layanan tetap hidup."
        _buat_selfsigned
    else
        echo -e "[ ${green}ok${NC} ] Sertifikat Let's Encrypt terpasang untuk $domain"
    fi
fi

# Jaring pengaman terakhir: kalau masih tidak sah, jangan biarkan nginx
# memakai berkas rusak.
if ! _cert_sah; then
    _buat_selfsigned
fi
echo -e "[ ${INFO} ] Sertifikat: $(openssl x509 -noout -subject -in /etc/xray/xray.crt 2>/dev/null | sed 's/subject=//' | cut -c1-60)"

# nginx renew ssl
echo -n '#!/bin/bash
/etc/init.d/nginx stop
"/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" &> /root/renew_ssl.log
/etc/init.d/nginx start
' > /usr/local/bin/ssl_renew.sh
chmod +x /usr/local/bin/ssl_renew.sh
if ! grep -q 'ssl_renew.sh' /var/spool/cron/crontabs/root;then (crontab -l;echo "15 03 */3 * * /usr/local/bin/ssl_renew.sh") | crontab;fi

mkdir -p /home/vps/public_html

# set uuid
uuid=$(cat /proc/sys/kernel/random/uuid)
# xray config
cat > /etc/xray/config.json << END
{
  "log" : {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
      {
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api"
    },
   {
     "listen": "127.0.0.1",
     "port": "14016",
     "protocol": "vless",
      "settings": {
          "decryption":"none",
            "clients": [
               {
                 "id": "${uuid}"                 
#vless
             }
          ]
       },
       "streamSettings":{
         "network": "ws",
            "wsSettings": {
                "path": "/vless"
          }
        }
     },
     {
     "listen": "127.0.0.1",
     "port": "14017",
     "protocol": "vmess",
      "settings": {
            "clients": [
               {
                 "id": "${uuid}",
                 "alterId": 0
#vmess
             }
          ]
       },
       "streamSettings":{
         "network": "ws",
            "wsSettings": {
                "path": "/vmess"
          }
        }
     },
    {
      "listen": "127.0.0.1",
      "port": "14018",
      "protocol": "trojan",
      "settings": {
          "decryption":"none",		
           "clients": [
              {
                 "password": "${uuid}"
#trojanws
              }
          ],
         "udp": true
       },
       "streamSettings":{
           "network": "ws",
           "wsSettings": {
               "path": "/trojan-ws"
            }
         }
     },
    {
         "listen": "127.0.0.1",
        "port": "30300",
        "protocol": "shadowsocks",
        "settings": {
           "clients": [
           {
           "method": "aes-128-gcm",
          "password": "${uuid}"
#ssws
           }
          ],
          "network": "tcp,udp"
       },
       "streamSettings":{
          "network": "ws",
             "wsSettings": {
               "path": "/ss-ws"
           }
        }
     },	
      {
        "listen": "127.0.0.1",
        "port": "14019",
        "protocol": "vless",
        "settings": {
         "decryption":"none",
           "clients": [
             {
               "id": "${uuid}"
#vlessgrpc
             }
          ]
       },
          "streamSettings":{
             "network": "grpc",
             "grpcSettings": {
                "serviceName": "vless-grpc"
           }
        }
     },
     {
      "listen": "127.0.0.1",
      "port": "14020",
     "protocol": "vmess",
      "settings": {
            "clients": [
               {
                 "id": "${uuid}",
                 "alterId": 0
#vmessgrpc
             }
          ]
       },
       "streamSettings":{
         "network": "grpc",
            "grpcSettings": {
                "serviceName": "vmess-grpc"
          }
        }
     },
     {
        "listen": "127.0.0.1",
        "port": "14021",
        "protocol": "trojan",
        "settings": {
          "decryption":"none",
             "clients": [
               {
                 "password": "${uuid}"
#trojangrpc
               }
           ]
        },
         "streamSettings":{
         "network": "grpc",
           "grpcSettings": {
               "serviceName": "trojan-grpc"
         }
      }
   },
   {
    "listen": "127.0.0.1",
    "port": "30310",
    "protocol": "shadowsocks",
    "settings": {
        "clients": [
          {
             "method": "aes-128-gcm",
             "password": "${uuid}"
#ssgrpc
           }
         ],
           "network": "tcp,udp"
      },
    "streamSettings":{
     "network": "grpc",
        "grpcSettings": {
           "serviceName": "ss-grpc"
          }
       }
    }	
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8",
          "10.0.0.0/8",
          "100.64.0.0/10",
          "169.254.0.0/16",
          "172.16.0.0/12",
          "192.0.0.0/24",
          "192.0.2.0/24",
          "192.168.0.0/16",
          "198.18.0.0/15",
          "198.51.100.0/24",
          "203.0.113.0/24",
          "::1/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outboundTag": "blocked"
      },
      {
        "inboundTag": [
          "api"
        ],
        "outboundTag": "api",
        "type": "field"
      },
      {
        "type": "field",
        "outboundTag": "blocked",
        "protocol": [
          "bittorrent"
        ]
      }
    ]
  },
  "stats": {},
  "api": {
    "services": [
      "StatsService"
    ],
    "tag": "api"
  },
  "policy": {
    "levels": {
      "0": {
        "statsUserDownlink": true,
        "statsUserUplink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink" : true,
      "statsOutboundDownlink" : true
    }
  }
}
END
rm -rf /etc/systemd/system/xray.service.d
cat <<EOF> /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
# CAP_DAC_OVERRIDE wajib: tanpa itu root tidak bisa menulis ke
# /var/log/xray bila direktori itu dimiliki user lain (installer resmi
# XTLS membuatnya milik user "xray" mode 700). Tanpa cap ini Xray gagal
# start dengan "open /var/log/xray/access.log: permission denied".
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_DAC_OVERRIDE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_DAC_OVERRIDE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target

EOF
cat > /etc/systemd/system/runn.service <<EOF
[Unit]
Description=Xray runtime directory setup
Before=xray.service
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/mkdir -p /var/run/xray
ExecStart=/usr/bin/chown root:root /var/run/xray

[Install]
WantedBy=multi-user.target
EOF

#nginx config
cat >/etc/nginx/conf.d/xray.conf <<EOF
    server {
             listen 80;
             listen [::]:80;
             listen 443 ssl http2 reuseport;
             listen [::]:443 http2 reuseport;	
             server_name $domain;
             ssl_certificate /etc/xray/xray.crt;
             ssl_certificate_key /etc/xray/xray.key;
             ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDSA+AES256:EECDH+aRSA+AES256:RSA+AES256:EECDH+ECDSA+3DES:EECDH+aRSA+3DES:RSA+3DES:!MD5;
             ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
             root /home/vps/public_html;
        }
EOF
sed -i '$ ilocation = /vless' /etc/nginx/conf.d/xray.conf
sed -i '$ i{' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_redirect off;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_pass http://127.0.0.1:14016;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_http_version 1.1;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header X-Real-IP \$remote_addr;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header Upgrade \$http_upgrade;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header Connection "upgrade";' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header Host \$http_host;' /etc/nginx/conf.d/xray.conf
sed -i '$ i}' /etc/nginx/conf.d/xray.conf

sed -i '$ ilocation = /vmess' /etc/nginx/conf.d/xray.conf
sed -i '$ i{' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_redirect off;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_pass http://127.0.0.1:14017;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_http_version 1.1;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header X-Real-IP \$remote_addr;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header Upgrade \$http_upgrade;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header Connection "upgrade";' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header Host \$http_host;' /etc/nginx/conf.d/xray.conf
sed -i '$ i}' /etc/nginx/conf.d/xray.conf

sed -i '$ ilocation = /trojan-ws' /etc/nginx/conf.d/xray.conf
sed -i '$ i{' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_redirect off;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_pass http://127.0.0.1:14018;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_http_version 1.1;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header X-Real-IP \$remote_addr;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header Upgrade \$http_upgrade;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header Connection "upgrade";' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header Host \$http_host;' /etc/nginx/conf.d/xray.conf
sed -i '$ i}' /etc/nginx/conf.d/xray.conf

sed -i '$ ilocation = /ss-ws' /etc/nginx/conf.d/xray.conf
sed -i '$ i{' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_redirect off;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_pass http://127.0.0.1:30300;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_http_version 1.1;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header X-Real-IP \$remote_addr;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header Upgrade \$http_upgrade;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header Connection "upgrade";' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header Host \$http_host;' /etc/nginx/conf.d/xray.conf
sed -i '$ i}' /etc/nginx/conf.d/xray.conf

# SSH over WebSocket. ws-stunnel mendengarkan di 127.0.0.1:700 dan
# meneruskan ke dropbear. Tanpa location ini, port 700 hanya bisa
# diakses dari dalam server sehingga akun SSH-WS tidak pernah tersambung
# walau service-nya "active".
sed -i '$ ilocation = /ssh-ws' /etc/nginx/conf.d/xray.conf
sed -i '$ i{' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_redirect off;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_pass http://127.0.0.1:700;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_http_version 1.1;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header X-Real-IP \$remote_addr;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header Upgrade \$http_upgrade;' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header Connection "upgrade";' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_set_header Host \$http_host;' /etc/nginx/conf.d/xray.conf
sed -i '$ i}' /etc/nginx/conf.d/xray.conf

# Berkas .txt akun berisi karakter UTF-8 (•, —). Tanpa charset, browser
# menebak Latin-1 dan menampilkan mojibake seperti "â€¢".
sed -i '$ ilocation ^~ /akun/' /etc/nginx/conf.d/xray.conf
sed -i '$ i{' /etc/nginx/conf.d/xray.conf
sed -i '$ icharset utf-8;' /etc/nginx/conf.d/xray.conf
sed -i '$ i}' /etc/nginx/conf.d/xray.conf

sed -i '$ ilocation /' /etc/nginx/conf.d/xray.conf
sed -i '$ i{' /etc/nginx/conf.d/xray.conf
sed -i '$ iroot /home/vps/public_html;' /etc/nginx/conf.d/xray.conf
sed -i '$ iindex index.html;' /etc/nginx/conf.d/xray.conf
sed -i '$ itry_files \$uri \$uri/ =404;' /etc/nginx/conf.d/xray.conf
sed -i '$ i}' /etc/nginx/conf.d/xray.conf

sed -i '$ ilocation ^~ /vless-grpc' /etc/nginx/conf.d/xray.conf
sed -i '$ i{' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_redirect off;' /etc/nginx/conf.d/xray.conf
sed -i '$ igrpc_set_header X-Real-IP \$remote_addr;' /etc/nginx/conf.d/xray.conf
sed -i '$ igrpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;' /etc/nginx/conf.d/xray.conf
sed -i '$ igrpc_set_header Host \$http_host;' /etc/nginx/conf.d/xray.conf
sed -i '$ igrpc_pass grpc://127.0.0.1:14019;' /etc/nginx/conf.d/xray.conf
sed -i '$ i}' /etc/nginx/conf.d/xray.conf

sed -i '$ ilocation ^~ /vmess-grpc' /etc/nginx/conf.d/xray.conf
sed -i '$ i{' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_redirect off;' /etc/nginx/conf.d/xray.conf
sed -i '$ igrpc_set_header X-Real-IP \$remote_addr;' /etc/nginx/conf.d/xray.conf
sed -i '$ igrpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;' /etc/nginx/conf.d/xray.conf
sed -i '$ igrpc_set_header Host \$http_host;' /etc/nginx/conf.d/xray.conf
sed -i '$ igrpc_pass grpc://127.0.0.1:14020;' /etc/nginx/conf.d/xray.conf
sed -i '$ i}' /etc/nginx/conf.d/xray.conf

sed -i '$ ilocation ^~ /trojan-grpc' /etc/nginx/conf.d/xray.conf
sed -i '$ i{' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_redirect off;' /etc/nginx/conf.d/xray.conf
sed -i '$ igrpc_set_header X-Real-IP \$remote_addr;' /etc/nginx/conf.d/xray.conf
sed -i '$ igrpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;' /etc/nginx/conf.d/xray.conf
sed -i '$ igrpc_set_header Host \$http_host;' /etc/nginx/conf.d/xray.conf
sed -i '$ igrpc_pass grpc://127.0.0.1:14021;' /etc/nginx/conf.d/xray.conf
sed -i '$ i}' /etc/nginx/conf.d/xray.conf

sed -i '$ ilocation ^~ /ss-grpc' /etc/nginx/conf.d/xray.conf
sed -i '$ i{' /etc/nginx/conf.d/xray.conf
sed -i '$ iproxy_redirect off;' /etc/nginx/conf.d/xray.conf
sed -i '$ igrpc_set_header X-Real-IP \$remote_addr;' /etc/nginx/conf.d/xray.conf
sed -i '$ igrpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;' /etc/nginx/conf.d/xray.conf
sed -i '$ igrpc_set_header Host \$http_host;' /etc/nginx/conf.d/xray.conf
sed -i '$ igrpc_pass grpc://127.0.0.1:30310;' /etc/nginx/conf.d/xray.conf
sed -i '$ i}' /etc/nginx/conf.d/xray.conf


sleep 1
echo -e "[ ${green}INFO$NC ] Installing bbr.."
wget -q -O /usr/bin/bbr "https://raw.githubusercontent.com/Masbrow33/dxavier/main/ssh/bbr.sh"
chmod +x /usr/bin/bbr
bbr >/dev/null 2>&1
rm /usr/bin/bbr >/dev/null 2>&1
echo -e "$yell[SERVICE]$NC Restart All service"
systemctl daemon-reload
sleep 1
echo -e "[ ${green}ok${NC} ] Enable & restart xray "
systemctl enable xray
systemctl restart xray
# nginx wajib di-enable: tanpa ini nginx mati setelah reboot dan semua
# path WebSocket (/vless, /vmess, /trojan-ws, /ss-ws) serta halaman
# /akun/ ikut mati, padahal xray tetap hidup.
systemctl enable nginx
systemctl restart nginx
# runn tidak selalu ada di semua image; jangan sampai mencetak error
if systemctl list-unit-files 2>/dev/null | grep -q '^runn\.service'; then
    systemctl enable runn
    systemctl restart runn
fi

sleep 1
wget -q -O /usr/bin/auto-set "https://raw.githubusercontent.com/Masbrow33/dxavier/main/xray/auto-set.sh" && chmod +x /usr/bin/auto-set 
wget -q -O /usr/bin/crtxray "https://raw.githubusercontent.com/Masbrow33/dxavier/main/xray/crt.sh" && chmod +x /usr/bin/crtxray 
sleep 1
yellow() { echo -e "\\033[33;1m${*}\\033[0m"; }
yellow "xray/Vmess"
yellow "xray/Vless"



mv /root/domain /etc/xray/ 
if [ -f /root/scdomain ];then
rm /root/scdomain > /dev/null 2>&1
fi
clear
rm -f ins-xray.sh  
