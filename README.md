# dxavier — dependency files for `btr` autoscript

Repo ini berisi **semua file dependensi** yang dibutuhkan oleh
[`Masbrow33/btr`](https://github.com/Masbrow33/btr).

## Kenapa repo ini ada

Script `btr/setup.sh` sebelumnya mengambil 5 file dari
`artanodrop/dxavier`, dan `ssh/ssh-vpn.sh` mengambil 11 file dari repo yang sama.
**Repo `artanodrop/dxavier` sudah dihapus (HTTP 404)**, sehingga instalasi
gagal di tengah jalan:

- `dependencies.sh` gagal → paket dasar tidak terpasang
- `ins-xray.sh` gagal → Xray tidak ada
- `insshws.sh` gagal → WebSocket tidak ada
- `set-br.sh` gagal → backup tidak ada
- 11 file `ssh/*` gagal → SSH/OpenVPN/stunnel tidak lengkap

Repo ini adalah **mirror mandiri** supaya instalasi tidak lagi bergantung pada
repo pihak lain yang bisa hilang kapan saja.

## Isi

| Folder | Isi |
|---|---|
| `ssh/` | `ssh-vpn.sh`, `multiport`, `newudpgw`, `nginx.conf`, `password`, `speedtest_cli.py`, `vps.conf`, `xp.sh`, `proxy3.js`, `sshws-true.sh`, `bbr.sh`, `.htaccess` |
| `xray/` | `ins-xray.sh`, `auto-set.sh`, `crt.sh` |
| `websocket/` | `insshws.sh`, `dropbear-ws.py`, `openssh-socket.py`, service unit |
| `slowdnss/` | `install-sldns.sh` + binary `sldns-server` / `sldns-client` (amd64) + key |
| `backup/` | `set-br.sh`, `backup.sh`, `restore.sh`, `logcleaner.sh` |
| `bot_panel/` | `BotAPI.sh` — bot Telegram panel |
| `corn/` | `rebootvps.sh` |
| `dependencies.sh`, `jam.sh`, `issue.net` | file dasar |

## File yang sebelumnya hilang (dibuat ulang di sini)

1. **`ssh/.htaccess`** — konfigurasi Apache untuk `public_html` websocket.
   Dirujuk `ssh/ssh-vpn.sh` baris 146.
2. **`slowdnss/install-sldns.sh`** — installer SlowDNS, self-contained
   (binary & key diambil dari folder ini, bukan repo luar).
3. **`bot_panel/BotAPI.sh`** — bot Telegram panel.

> **Catatan penting:** `BotAPI.sh` adalah **reimplementasi**, bukan source asli
> vendor. Perintah yang tersedia: `/status`, `/services`, `/users`, `/disk`,
> `/ping`, `/id`, `/help`. Tidak memakai dependensi eksternal (stdlib Python 3).
>
> Binary SlowDNS di `slowdnss/` adalah **arsitektur amd64 (x86-64)** — cocok
> untuk VPS x86_64. Kalau VPS-mu ARM, binary ini tidak akan jalan.

## Cara pakai

Tidak perlu clone. `btr/setup.sh` mengunduh langsung dari repo ini:

```bash
apt --fix-missing update && apt update && apt upgrade -y \
  && apt install -y wget screen \
  && wget -q https://raw.githubusercontent.com/Masbrow33/btr/main/setup.sh \
  && chmod +x setup.sh && screen -S setup ./setup.sh
```

## Verifikasi semua URL hidup

```bash
for f in dependencies.sh jam.sh issue.net ssh/.htaccess ssh/multiport \
         ssh/newudpgw ssh/nginx.conf ssh/password ssh/speedtest_cli.py \
         ssh/vps.conf ssh/xp.sh ssh/proxy3.js ssh/sshws-true.sh \
         ssh/ssh-vpn.sh xray/ins-xray.sh xray/auto-set.sh xray/crt.sh \
         backup/set-br.sh websocket/insshws.sh corn/rebootvps.sh \
         slowdnss/install-sldns.sh bot_panel/BotAPI.sh; do
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://raw.githubusercontent.com/Masbrow33/dxavier/main/$f")
  printf "%-32s %s\n" "$f" "$code"
done
```
