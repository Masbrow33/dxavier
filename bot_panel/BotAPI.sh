#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BotAPI.sh — Telegram Bot Panel (reimplementasi)

Dipakai oleh: update/menu-bot.sh
  - disalin ke /usr/bin/bbt lalu dijalankan via:
        screen -dmS sam_bot bbt

Konfigurasi yang dibaca:
  /root/ResBotAuth        -> "Toket: <token>"  dan  "Admin_ID: <id1,id2>"
  /root/multi/bot.conf    -> "Botname: <nama>"  dan  "Limit: <n>"

Perintah: /start /help /status /services /users /disk /id /ping
Hanya Admin_ID yang boleh memakai perintah (kecuali /id dan /start).

Tanpa dependensi eksternal — hanya stdlib Python 3.
"""
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

AUTH_FILE = "/root/ResBotAuth"
CONF_FILE = "/root/multi/bot.conf"
LOCK_FILE = "/tmp/.bbt.lock"
LOG_FILE = "/var/log/bbt.log"

BOT_NAME = "Bot Panel"
LIMIT = "1"
TOKEN = ""
ADMINS = set()


# ---------------------------------------------------------------- logging
def log(msg):
    line = "[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass
    print(line, flush=True)


# ---------------------------------------------------------------- config
def load_config():
    global TOKEN, ADMINS, BOT_NAME, LIMIT

    if os.path.exists(AUTH_FILE):
        try:
            with open(AUTH_FILE) as f:
                for raw in f:
                    line = raw.strip()
                    low = line.lower()
                    if low.startswith("toket:"):
                        TOKEN = line.split(":", 1)[1].strip()
                    elif low.startswith("admin_id:"):
                        ids = line.split(":", 1)[1].strip()
                        for part in re.split(r"[,\s]+", ids):
                            if part.strip().lstrip("-").isdigit():
                                ADMINS.add(int(part.strip()))
        except OSError as exc:
            log("gagal baca %s: %s" % (AUTH_FILE, exc))

    if os.path.exists(CONF_FILE):
        try:
            with open(CONF_FILE) as f:
                for raw in f:
                    line = raw.strip()
                    low = line.lower()
                    if low.startswith("botname:"):
                        BOT_NAME = line.split(":", 1)[1].strip() or BOT_NAME
                    elif low.startswith("limit:"):
                        LIMIT = line.split(":", 1)[1].strip() or LIMIT
        except OSError:
            pass


# ---------------------------------------------------------------- helpers
def run(cmd, timeout=10):
    """Jalankan perintah shell, kembalikan stdout (string)."""
    try:
        out = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        )
        return (out.stdout or out.stderr or "").strip()
    except Exception as exc:  # noqa: BLE001
        return "error: %s" % exc


def human_kb(kb):
    kb = float(kb)
    for unit in ("KB", "MB", "GB", "TB"):
        if kb < 1024:
            return "%.1f %s" % (kb, unit)
        kb /= 1024.0
    return "%.1f PB" % kb


def server_status():
    host = socket.gethostname()
    up = run("uptime -p") or run("uptime")
    load = run("cat /proc/loadavg").split()[:3]
    mem = run("free -k | awk '/Mem:/{print $2\" \"$3\" \"$7}'").split()
    disk = run("df -k / | awk 'NR==2{print $2\" \"$3\" \"$4\" \"$5}'").split()
    ip = run("hostname -I | awk '{print $1}'")

    lines = [
        "\U0001F5A5\ufe0f <b>%s</b>" % host,
        "",
        "\u23f1 Uptime : %s" % (up or "-"),
        "\u2699\ufe0f Load   : %s" % (" / ".join(load) if load else "-"),
        "\U0001F4CD IP     : %s" % (ip or "-"),
    ]
    if len(mem) >= 3:
        lines.append(
            "\U0001F9E0 RAM    : %s / %s (tersedia %s)"
            % (human_kb(mem[1]), human_kb(mem[0]), human_kb(mem[2]))
        )
    if len(disk) >= 4:
        lines.append(
            "\U0001F4BE Disk   : %s / %s (%s terpakai)"
            % (human_kb(disk[1]), human_kb(disk[0]), disk[3])
        )
    return "\n".join(lines)


SERVICES = [
    ("ssh", "SSH"),
    ("dropbear", "Dropbear"),
    ("nginx", "Nginx"),
    ("xray", "Xray"),
    ("stunnel4", "Stunnel4"),
    ("server-sldns", "SlowDNS"),
    ("fail2ban", "Fail2ban"),
]


def services_status():
    lines = ["\U0001F527 <b>Status Layanan</b>", ""]
    for unit, label in SERVICES:
        state = run("systemctl is-active %s 2>/dev/null" % unit) or "unknown"
        if state == "active":
            mark = "\u2705"
        elif state in ("inactive", "failed"):
            mark = "\u274c"
        else:
            mark = "\u26aa"
        lines.append("%s %-10s <code>%s</code>" % (mark, label, state))
    return "\n".join(lines)


def users_info():
    out = run("awk -F: '$3>=1000 && $3<65534 && $6 ~ /^\\/home/ {print $1}' /etc/passwd")
    users = [u for u in out.splitlines() if u.strip()]
    exp = run("cat /etc/expired 2>/dev/null")
    expired = [e for e in exp.splitlines() if e.strip()]
    lines = ["\U0001F465 <b>Akun SSH</b>", ""]
    lines.append("Total aktif : <b>%d</b>" % len(users))
    if LIMIT:
        lines.append("Limit panel : %s" % LIMIT)
    if users:
        shown = users[:30]
        lines.append("")
        lines.append("<code>%s</code>" % "\n".join(shown))
        if len(users) > len(shown):
            lines.append("<i>... dan %d lainnya</i>" % (len(users) - len(shown)))
    if expired:
        lines.append("")
        lines.append("\u23f0 Kedaluwarsa: %d" % len(expired))
    return "\n".join(lines)


def disk_info():
    out = run("df -h | grep -Ev 'tmpfs|udev|overlay'")
    lines = ["\U0001F4BE <b>Penggunaan Disk</b>", "", "<code>%s</code>" % out]
    return "\n".join(lines)


# ---------------------------------------------------------------- telegram
def api(method, payload=None, timeout=35):
    url = "https://api.telegram.org/bot%s/%s" % (TOKEN, method)
    data = None
    headers = {}
    if payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        log("HTTP %s pada %s: %s" % (exc.code, method, body[:200]))
        return None
    except Exception as exc:  # noqa: BLE001
        log("error %s: %s" % (method, exc))
        return None


def send(chat_id, text):
    api("sendMessage", {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True,
    })


HELP = (
    "\U0001F916 <b>%s</b>\n\n"
    "Perintah tersedia:\n"
    "/status \u2014 info server (uptime, RAM, disk)\n"
    "/services \u2014 status layanan\n"
    "/users \u2014 daftar akun SSH\n"
    "/disk \u2014 penggunaan disk\n"
    "/ping \u2014 cek bot hidup\n"
    "/id \u2014 lihat chat ID kamu\n"
    "/help \u2014 bantuan ini"
)


def handle(msg):
    chat = msg.get("chat", {})
    chat_id = chat.get("id")
    from_id = (msg.get("from") or {}).get("id")
    text = (msg.get("text") or "").strip()
    if not text.startswith("/"):
        return

    cmd = text.split()[0].split("@")[0].lower()

    if cmd in ("/start", "/help"):
        send(chat_id, HELP % BOT_NAME)
        return

    if cmd == "/id":
        send(chat_id, "\U0001F194 Chat ID: <code>%s</code>" % chat_id)
        return

    if ADMINS and from_id not in ADMINS:
        send(chat_id, "\u26d4 Kamu tidak punya akses ke bot ini.")
        return

    if cmd == "/status":
        send(chat_id, server_status())
    elif cmd == "/services":
        send(chat_id, services_status())
    elif cmd == "/users":
        send(chat_id, users_info())
    elif cmd == "/disk":
        send(chat_id, disk_info())
    elif cmd == "/ping":
        send(chat_id, "\U0001F3D3 Pong! Bot aktif.")
    else:
        send(chat_id, "Perintah tidak dikenal. Ketik /help")


def single_instance():
    """Cegah dua instance bot berjalan bersamaan."""
    if os.path.exists(LOCK_FILE):
        try:
            with open(LOCK_FILE) as f:
                pid = int((f.read() or "0").strip() or 0)
        except (OSError, ValueError):
            pid = 0
        if pid and os.path.exists("/proc/%d" % pid):
            log("instance lain sudah jalan (PID %d), keluar." % pid)
            return False
    try:
        with open(LOCK_FILE, "w") as f:
            f.write(str(os.getpid()))
    except OSError:
        pass
    return True


def main():
    load_config()

    if not TOKEN:
        log("Token bot tidak ditemukan di %s" % AUTH_FILE)
        log("Format yang benar:  Toket: <token>   lalu   Admin_ID: <id>")
        return 1

    if not ADMINS:
        log("PERINGATAN: Admin_ID kosong — semua orang bisa memakai perintah.")

    if not single_instance():
        return 0

    me = api("getMe")
    if not me or not me.get("ok"):
        log("Token tidak valid atau jaringan bermasalah.")
        return 1
    bot_user = me["result"].get("username", "?")
    log("Bot mulai: @%s | admin=%s | nama=%s" % (bot_user, sorted(ADMINS) or "-", BOT_NAME))

    offset = 0
    while True:
        try:
            resp = api("getUpdates", {
                "offset": offset,
                "timeout": 25,
                "allowed_updates": ["message"],
            }, timeout=40)
            if not resp or not resp.get("ok"):
                time.sleep(5)
                continue
            for upd in resp.get("result", []):
                offset = upd["update_id"] + 1
                msg = upd.get("message")
                if msg:
                    try:
                        handle(msg)
                    except Exception as exc:  # noqa: BLE001
                        log("gagal proses pesan: %s" % exc)
        except KeyboardInterrupt:
            log("dihentikan manual.")
            break
        except Exception as exc:  # noqa: BLE001
            log("loop error: %s" % exc)
            time.sleep(5)

    try:
        os.remove(LOCK_FILE)
    except OSError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
