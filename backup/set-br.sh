#!/bin/bash
# Warna didefinisikan sendiri: script ini dijalankan sebagai proses
# terpisah, sedangkan variabel warna di setup.sh tidak di-export,
# sehingga tanpa ini semua pesan tampil tanpa warna.
green=$'\033[0;32m'
yell=$'\033[1;33m'
NC=$'\033[0m'

dateFromServer=$(curl -v --insecure --silent https://google.com/ 2>&1 | grep Date | sed -e 's/< Date: //')
biji=`date +"%Y-%m-%d" -d "$dateFromServer"`
#########################

date
echo ""
sleep 1
echo -e "[ ${green}INFO${NC} ] Checking... "
sleep 2
sleep 1
echo -e "[ ${green}INFO${NC} ] Download & Install rclone... "
curl -fsSL https://rclone.org/install.sh | bash > /dev/null 2>&1
printf "q\n" | rclone config > /dev/null 2>&1
sleep 1
echo -e "[ ${green}INFO${NC} ] Downloading rclone config ... "
# Unduh lewat berkas sementara: rclone.conf yang kosong membuat semua
# backup gagal tanpa pesan yang jelas.
_rclone_dir=/root/.config/rclone
mkdir -p "$_rclone_dir"
_rclone_tmp=$(mktemp /tmp/rclone.XXXXXX)
if wget -q --timeout=25 --tries=2 -O "$_rclone_tmp" \
     "https://raw.githubusercontent.com/Masbrow33/dxavier/main/backup/rclone.conf" \
   && [ -s "$_rclone_tmp" ]; then
    mv -f "$_rclone_tmp" "$_rclone_dir/rclone.conf"
    chmod 600 "$_rclone_dir/rclone.conf"
    echo -e "[ ${green}ok${NC} ] rclone.conf terpasang"
else
    rm -f "$_rclone_tmp"
    echo -e "[ ${yell}WARN${NC} ] rclone.conf gagal diunduh, backup cloud tidak siap"
fi

# wondershaper: hapus dulu sisa clone sebelumnya, kalau tidak
# "git clone" gagal ("already exists") dan "cd wondershaper" ikut gagal.
rm -rf /root/wondershaper
if git clone --depth 1 https://github.com/magnific0/wondershaper.git /root/wondershaper &> /dev/null; then
    cd /root/wondershaper || true
    sleep 1
    echo -e "[ ${green}INFO${NC} ] Installing wondershaper... "
    make install > /dev/null 2>&1
    cd || true
    rm -rf /root/wondershaper > /dev/null 2>&1
else
    echo -e "[ ${yell}WARN${NC} ] wondershaper gagal di-clone, pembatas bandwidth dilewati"
fi
echo > /home/limit

pkgs='msmtp-mta ca-certificates bsd-mailx'
if ! dpkg -s $pkgs > /dev/null 2>&1; then
sleep 1
echo -e "[ ${green}INFO${NC} ] Installing... "
# msmtp-mta memunculkan dialog whiptail ("Enable AppArmor support?").
# Tanpa noninteractive, instalasi menggantung menunggu jawaban yang tidak
# pernah datang karena output di-redirect. Paksa noninteractive + jawab
# pertanyaannya lebih dulu lewat debconf.
export DEBIAN_FRONTEND=noninteractive
echo "msmtp msmtp/apparmor boolean false" | debconf-set-selections 2>/dev/null || true
apt install -y -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" $pkgs < /dev/null > /dev/null 2>&1
else
sleep 1
echo -e "[ ${green}INFO${NC} ] Already Installed... "
fi
sleep 1
echo -e "[ ${green}INFO${NC} ] Creating service... "

cat> /etc/msmtprc << EOF
account default
host smtp.gmail.com
port 587
from 3bulanmm@gmail.com
tls on
tls_starttls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
auth on
user 3bulanmm
password aww123321aww
logfile ~/.msmtp.log
EOF

chown -R www-data:www-data /etc/msmtprc
sleep 1
echo -e "[ ${green}INFO${NC} ] Downloading files... "
# Unduh lewat berkas sementara. Pola lama "wget -O && chmod +x" membuat
# berkas kosong hasil unduhan yang gagal tetap menjadi executable —
# /usr/bin/cleaner lalu dijalankan cron setiap 6 jam dan gagal terus.
ambil_tool() {
    local src="$1" dst="$2" tmpf
    tmpf=$(mktemp /tmp/bt.XXXXXX)
    if wget -q --timeout=25 --tries=2 -O "$tmpf" \
         "https://raw.githubusercontent.com/Masbrow33/dxavier/main/backup/$src.sh" \
       && [ -s "$tmpf" ] && bash -n "$tmpf" 2>/dev/null; then
        mv -f "$tmpf" "/usr/bin/$dst"
        chmod +x "/usr/bin/$dst"
        echo -e "[ ${green}ok${NC} ] $dst"
        return 0
    fi
    rm -f "$tmpf"
    rm -f "/usr/bin/$dst"
    echo -e "[ ${yell}WARN${NC} ] $dst gagal dipasang"
    return 1
}

ambil_tool backup    backup
ambil_tool restore   restore
ambil_tool logcleaner cleaner

if [ ! -f "/etc/cron.d/cleaner" ]; then
cat> /etc/cron.d/cleaner << END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
* */6 * * * root /usr/bin/cleaner
END
fi

service cron restart > /dev/null 2>&1

rm -f /root/set-br.sh
