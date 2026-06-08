#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# ============================================================
#  Keenetic Zapret2 Manager (KZM2)
#  keenetic_zapret2_manager.sh
# ============================================================
#
#  Zapret2 DPI bypass engine installation, management and
#  automation script for Keenetic routers (Entware/OpenWrt).
#
#  Author  : RevolutionTR
#  GitHub  : https://github.com/RevolutionTR/keenetic-zapret2-manager
#  License : GNU General Public License v3.0 or later
#
#  Copyright (C) 2026 RevolutionTR
#  All rights reserved.
#
#  This program is free software: you can redistribute it and/or
#  modify it under the terms of the GNU General Public License as
#  published by the Free Software Foundation, either version 3 of
#  the License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# ============================================================
# BETIK BILGILENDIRME                                 
# Notepad++ da Duzen > Satir Sonunu Donustur > UNIX (LF)
# -------------------------------------------------------------------
# Script Kimligi (Repo/Surum)
# -------------------------------------------------------------------
SCRIPT_NAME="keenetic_zapret2_manager.sh"
# Version scheme: vYY.M.D[.N]  (YY=year, M=month, D=day, N=daily revision)
SCRIPT_VERSION="v26.6.8"
SCRIPT_REPO="https://github.com/RevolutionTR/keenetic-zapret2-manager"
KZM2_SCRIPT_PATH="/opt/lib/opkg/keenetic_zapret2_manager.sh"
SCRIPT_AUTHOR="RevolutionTR"
# Daemon icin +x gerekli; "sh script.sh" ile calisinca izin olmasa da menu acilir
# ama healthmon baslatilamaz. Script her calistiginda otomatik duzelt.
[ -x "$KZM2_SCRIPT_PATH" ] || chmod +x "$KZM2_SCRIPT_PATH" 2>/dev/null
# -------------------------------------------------------------------
# -------------------------------------------------------------------
# BEGIN_SESSION_GUARD_V3
# Amac:
# - SSH / shellinabox oturumu kopunca (/dev/pts/* (deleted)) scriptin
#   arkada asili kalmasini engellemek
# - Ayni anda birden fazla script instance'ini engellemek
# -------------------------------------------------------------------
KZM2_LOCKDIR="/tmp/kzm2_mgr.lock"
KZM2_SELF_PID="$$"
# Acquire lock (mkdir is atomic)
# NOTE: Internal daemon modes must bypass the main session lock,
# otherwise they cannot start while the UI script is open.
KZM2_SKIP_LOCK="0"
case "$1" in
    --healthmon-daemon) KZM2_SKIP_LOCK="1" ; HEALTHMON_DAEMON="1" ;;
    --telegram-daemon)
        _self_pid="$$"
        _tg_lockdir="/tmp/kzm2_telegram_daemon.lock"
        # Tum eski telegram-daemon processleri oldur (tek getUpdates instance)
        _old_pids="$(ps 2>/dev/null | grep -- '--telegram-daemon' | grep -v grep | awk '{print $1}')"
        for _op in $_old_pids; do
            [ -n "$_op" ] && [ "$_op" != "$_self_pid" ] && kill -9 "$_op" 2>/dev/null
        done
        sleep 1
        # Atomic lock: ayni anda ikinci bot baslamasin
        if ! mkdir "$_tg_lockdir" 2>/dev/null; then
            _lock_pid="$(cat "$_tg_lockdir/pid" 2>/dev/null)"
            if [ -n "$_lock_pid" ] && [ "$_lock_pid" != "$_self_pid" ] && kill -0 "$_lock_pid" 2>/dev/null; then
                exit 0
            fi
            rm -rf "$_tg_lockdir" 2>/dev/null
            mkdir "$_tg_lockdir" 2>/dev/null || exit 0
        fi
        echo "$_self_pid" > "$_tg_lockdir/pid" 2>/dev/null
        # Gercek PID'i hemen yaz — watchdog sleep sirasinda botu olu sanmasin
        echo "$_self_pid" > /tmp/kzm2_telegram_bot.pid
        trap 'rm -rf /tmp/kzm2_telegram_daemon.lock 2>/dev/null; rm -f /tmp/kzm2_telegram_bot.pid 2>/dev/null' EXIT INT TERM
        # Telegram sunucusunun eski long-poll oturumunu kapatmasi icin bekle (409 onlemi)
        sleep 5
        KZM2_SKIP_LOCK="1"
        ;;
    --self-test)        KZM2_SKIP_LOCK="1" ; KZM2_SELF_TEST="1" ;;
    --update-gui)       KZM2_SKIP_LOCK="1" ;;
    --gui-status)      KZM2_SKIP_LOCK="1" ; KZM2_GUI_STATUS_GEN="1" ;;
    --cgi-action)      KZM2_SKIP_LOCK="1" ;;
    --netfilter-hook)  KZM2_SKIP_LOCK="1" ;;
    --dev|--developer)  KZM2_DEV_CHECK="1" ;;
    --opkg-upgrade)    KZM2_SKIP_LOCK="1" ;;
esac
# Developer / Self-test flags
KZM2_SELF_TEST="${KZM2_SELF_TEST:-0}"
KZM2_DEV_CHECK="${KZM2_DEV_CHECK:-0}"
kzm2_self_test() {
    local f="$0"
    local fail=0 warn=0
    _pass() { echo "PASS $*"; }
    _warn() { echo "WARN $*"; warn=$((warn+1)); }
    _fail() { echo "FAIL $*"; fail=$((fail+1)); }
    echo "=== KZM2 Self-Test ==="
    echo "File: $f"
    # 1) Syntax
    if sh -n "$f" 2>/tmp/kzm2_selftest_syntax.err; then
        _pass "syntax: sh -n OK"
    else
        _fail "syntax: sh -n FAILED (see /tmp/kzm2_selftest_syntax.err)"
    fi
    # 2) Turkish letters (byte-level) — HTML/CGI heredoc bolumlerini atla
    local found_tr=0 pat
    for pat in \
      $'\xC5\x9E' $'\xC5\x9F' \
      $'\xC4\x9E' $'\xC4\x9F' \
      $'\xC4\xB0' $'\xC4\xB1' \
      $'\xC3\x96' $'\xC3\xB6' \
      $'\xC3\x87' $'\xC3\xA7' \
      $'\xC3\x9C' $'\xC3\xBC'
    do
      if grep -qoba "$pat" "$f" >/dev/null 2>&1; then
        found_tr=1
        break
      fi
    done
    if [ "$found_tr" -eq 1 ]; then
        _fail "TR letters detected - keep ASCII for menus"
    else
        _pass "TR letters: none (byte-verified)"
    fi
    # 3) Translation coverage: used TXT_* keys must have _TR and _EN
    local miss="/tmp/kzm2_selftest_missing.txt"
    : > "$miss"
    grep -oE '(^|[^A-Z0-9_])T[[:space:]]+TXT_[A-Z0-9_]+' "$f" 2>/dev/null \
      | sed -E 's/^.*T[[:space:]]+(TXT_[A-Z0-9_]+).*$/\1/' \
      | sort -u \
      | while IFS= read -r k; do
            grep -qE "^${k}_TR=" "$f" 2>/dev/null || echo "${k}_TR" >> "$miss"
            grep -qE "^${k}_EN=" "$f" 2>/dev/null || echo "${k}_EN" >> "$miss"
        done
    if [ -s "$miss" ]; then
        _fail "missing translations found (see $miss)"
        head -n 30 "$miss" | sed 's/^/  - /'
        local cnt
        cnt="$(wc -l < "$miss" 2>/dev/null)"
        [ -n "$cnt" ] && [ "$cnt" -gt 30 ] && echo "  ... (+$((cnt-30)) more)"
    else
        _pass "translations: all used TXT_* have TR+EN"
        rm -f "$miss" 2>/dev/null
    fi
    # 4) read -p usage (not supported in BusyBox ash)
    local readp_count
    readp_count="$(grep -E "read[[:space:]]+-r?[[:space:]]*-p|read[[:space:]]+-p" "$f" 2>/dev/null \
        | grep -v '[[:space:]]*#\|_fail\|_pass\|_warn' | wc -l | tr -d ' ')"
    readp_count="${readp_count:-0}"
    if [ "$readp_count" -gt 0 ]; then
        _fail "read -p detected ($readp_count occurrence(s)) - use 'printf + read -r' instead"
        grep -nE "read[[:space:]]+-r?[[:space:]]*-p|read[[:space:]]+-p" "$f" 2>/dev/null \
            | grep -v '[[:space:]]*#\|_fail\|_pass\|_warn' | head -n 10 | sed 's/^/  line /'
    else
        _pass "read -p: none detected"
    fi
    # 5) Telegram config (optional)
    if [ -f /opt/etc/telegram.conf ]; then
        . /opt/etc/telegram.conf 2>/dev/null
        if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
            _pass "telegram: config present"
        else
            _warn "telegram: config exists but token/chat_id missing"
        fi
    else
        _warn "telegram: /opt/etc/telegram.conf not found (optional)"
    fi
    # 6) HealthMon auto-start (optional)
    if [ -f /opt/etc/healthmon.conf ]; then
        . /opt/etc/healthmon.conf 2>/dev/null
        if [ "${HM_ENABLE:-0}" = "1" ]; then
            local pid
            pid="$(cat /tmp/kzm2_healthmon.pid 2>/dev/null)"
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                _pass "healthmon: enabled and running (pid=$pid)"
            else
                _warn "healthmon: enabled but not running"
            fi
        else
            _pass "healthmon: disabled"
        fi
    else
        _warn "healthmon: /opt/etc/healthmon.conf not found (optional)"
    fi
    # 7) Zapret2 installation
    if [ -x "/opt/zapret2/init.d/sysv/zapret2" ]; then
        local _nfqws="/opt/zapret2/nfq2/nfqws2"
        local _init="/opt/etc/init.d/S90-zapret2"
        if [ ! -x "$_nfqws" ]; then
            _fail "zapret2: nfqws2 binary missing ($_nfqws)"
        elif [ ! -e "$_init" ]; then
            _warn "zapret2: S90-zapret2 init link missing"
        else
            _pass "zapret2: installed (nfqws2 OK, S90-zapret2 OK)"
        fi
    else
        _pass "zapret2: not installed (skipped)"
    fi
    # 8) Telegram bot process (only if bot enabled)
    local _tg_bot_en
    _tg_bot_en="$(grep -s '^TG_BOT_ENABLE=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')"
    if [ "$_tg_bot_en" = "1" ]; then
        local _bot_pid
        _bot_pid="$(cat /tmp/kzm2_telegram_bot.pid 2>/dev/null)"
        if [ -n "$_bot_pid" ] && kill -0 "$_bot_pid" 2>/dev/null; then
            _pass "telegram bot: enabled and running (pid=$_bot_pid)"
        else
            _warn "telegram bot: enabled but not running"
        fi
    else
        _pass "telegram bot: disabled (skipped)"
    fi
    # 9) Web Panel (only if installed)
    if [ -f "/opt/www/kzm2/index.html" ] && command -v lighttpd >/dev/null 2>&1; then
        # cron kaydi
        if crontab -l 2>/dev/null | grep -q 'kzm2_status_gen.sh'; then
            _pass "webpanel: cron entry present"
        else
            _warn "webpanel: kzm2_status_gen.sh cron entry missing"
        fi
        # kzm2_status_gen.sh binary
        if [ -x "/opt/bin/kzm2_status_gen.sh" ]; then
            _pass "webpanel: kzm2_status_gen.sh present"
        else
            _warn "webpanel: kzm2_status_gen.sh missing"
        fi
        # kzm_status.json tazelik (2 dakika = 120 saniye)
        local _json="/opt/var/run/kzm2_status.json"
        local _json_real="/tmp/kzm_status.json"
        [ -f "$_json_real" ] || _json_real="$_json"
        if [ -f "$_json_real" ]; then
            local _now _mtime _age
            _now="$(date +%s 2>/dev/null)"
            _mtime="$(date -r "$_json_real" +%s 2>/dev/null)"
            if [ -n "$_now" ] && [ -n "$_mtime" ]; then
                _age=$((_now - _mtime))
                if [ "$_age" -le 300 ]; then
                    _pass "webpanel: kzm_status.json fresh (${_age}s ago)"
                else
                    _warn "webpanel: kzm_status.json stale (${_age}s ago, cron may be stopped)"
                fi
            else
                _pass "webpanel: kzm_status.json present"
            fi
        else
            _warn "webpanel: kzm_status.json missing (cron not yet run?)"
        fi
    else
        _pass "webpanel: not installed (skipped)"
    fi
    # 10) wan_if dosyasi
    if [ -f "/opt/zapret2/wan_if" ]; then
        local _wif
        _wif="$(cat /opt/zapret2/wan_if 2>/dev/null | tr -d '[:space:]')"
        if [ -n "$_wif" ]; then
            _pass "wan_if: present ($_wif)"
        else
            _warn "wan_if: file exists but empty"
        fi
    else
        _warn "wan_if: not found (WAN interface not configured)"
    fi
    # 11) 000-zapret2.sh netfilter hook
    if [ -f "/opt/etc/ndm/netfilter.d/000-zapret2.sh" ]; then
        _pass "netfilter: 000-zapret2.sh present"
    else
        _warn "netfilter: 000-zapret2.sh missing (netfilter hook not installed)"
    fi
    # iptables NFQUEUE kural kontrolu
    _nfq_rules="$(iptables -t mangle -L POSTROUTING -n 2>/dev/null | grep -c NFQUEUE)"
    if [ "${_nfq_rules:-0}" -gt 0 ]; then
        _pass "iptables: ${_nfq_rules} NFQUEUE kural mevcut"
    else
        _warn "iptables: NFQUEUE kural yok (zapret2 calismiyor olabilir)"
    fi
    # bitmap:port kernel modulu kontrolu
    if ipset create _kzm2_st_bmp bitmap:port range 0-65535 2>/dev/null; then
        ipset destroy _kzm2_st_bmp 2>/dev/null
        _pass "bitmap:port: kernel modulu kullanilabilir"
    else
        ipset destroy _kzm2_st_bmp 2>/dev/null
        _warn "bitmap:port: kullanilabilir degil (zapret2 port kurallari eklenemeyebilir)"
    fi
    # zport_tcp ipset kontrolu (sadece ALL modunda kritik)
    _client_mode="$(cat /opt/zapret2/ipset_clients_mode 2>/dev/null | tr -d '[:space:]')"
    if ipset list zport_tcp >/dev/null 2>&1; then
        _pass "zport_tcp: ipset mevcut"
    elif [ "$_client_mode" = "list" ]; then
        _pass "zport_tcp: ipset yok ama IPSET modunda kullanilmiyor"
    else
        _warn "zport_tcp: ipset yok (zapret2 henuz baslamadi veya bitmap:port eksik)"
    fi
    # 12) Kullanilmayan TXT_* kontrolu kaldirildi - bilinen anahtarlar mevcut
    echo "=== Summary: FAIL=$fail WARN=$warn ==="
    if [ "$fail" -gt 0 ]; then
        return 1
    elif [ "$warn" -gt 0 ]; then
        return 2
    fi
    return 0
}
# Run self-test and exit
if [ "$KZM2_SELF_TEST" = "1" ]; then
    kzm2_self_test
    exit $?
fi
# Optional developer check (silent). No dependency for users.
if [ "$KZM2_DEV_CHECK" = "1" ] && [ -x /opt/etc/kzm2_guard.sh ]; then
    /opt/bin/sh /opt/etc/kzm2_guard.sh "$0" >/dev/null 2>&1
fi
if [ "$KZM2_SKIP_LOCK" != "1" ]; then
    if ! mkdir "$KZM2_LOCKDIR" 2>/dev/null; then
        if [ -f "$KZM2_LOCKDIR/pid" ] && kill -0 "$(cat "$KZM2_LOCKDIR/pid" 2>/dev/null)" 2>/dev/null; then
            _lock_pid="$(cat "$KZM2_LOCKDIR/pid" 2>/dev/null)"
            _lock_lang="$(cat /opt/zapret2/lang 2>/dev/null)"
            if [ "$_lock_lang" = "en" ]; then
                printf 'WARNING: Script is already running (PID: %s).\n' "$_lock_pid"
                printf 'Terminate the current session and continue? (y/n): '
            else
                printf 'UYARI: Betik zaten calisiyor (PID: %s).\n' "$_lock_pid"
                printf 'Mevcut oturumu sonlandirip devam etmek ister misiniz? (e/h): '
            fi
            read -r _lock_ans </dev/tty
            case "$_lock_ans" in
                e|E|y|Y)
                    kill "$_lock_pid" 2>/dev/null || true
                    sleep 1
                    rm -rf "$KZM2_LOCKDIR" 2>/dev/null
                    mkdir "$KZM2_LOCKDIR" 2>/dev/null || exit 1
                    ;;
                *)
                    exit 0
                    ;;
            esac
        fi
        # Stale lock
        rm -rf "$KZM2_LOCKDIR" 2>/dev/null
        mkdir "$KZM2_LOCKDIR" 2>/dev/null || exit 1
    fi
    echo "$KZM2_SELF_PID" > "$KZM2_LOCKDIR/pid"
    # Session guard + cleanup only for the main interactive instance
    kzm2_cleanup() {
        rm -rf "$KZM2_LOCKDIR" 2>/dev/null
    }
    # Forceful exit helper: in BusyBox ash, "exit" inside a trap handler may fail
    # to terminate the shell when deep in nested function calls (e.g., during
    # healthmon_start's sleep loop). kill -KILL $$ guarantees termination.
    _kzm2_force_exit() {
        kzm2_cleanup
        trap - EXIT INT TERM HUP 2>/dev/null
        kill -KILL $$ 2>/dev/null
        exit "$1" 2>/dev/null
    }
    # Always cleanup the lock
    trap 'kzm2_cleanup' EXIT
    # Extra traps: ensure Ctrl-C (INT) and disconnect signals actually EXIT
    trap '_kzm2_force_exit 130' INT
    trap '_kzm2_force_exit 143' TERM
    trap '_kzm2_force_exit 129' HUP
    trap '_kzm2_force_exit 148' TSTP
    trap '_kzm2_force_exit 150' TTIN
    trap '_kzm2_force_exit 151' TTOU
    # END_SESSION_GUARD_V3
fi
# -------------------------------------------------------------------
# Dogru Dizin Uyarisi (keenetic / keenetic-zapret)
# -------------------------------------------------------------------
#------ Komple Kaldirma ---------------------------------------------------------------
# KZM2 + Zapret2 tam temiz kaldirma (UNSAFE / irreversible)
# Not: "Zapret2yi Kaldir" (mevcut) rutini aynen calisir, sonra KZM kalintilari temizlenir.
# TR/EN Dictionary (Komple Kaldirma)
TXT_KZM2_FULL_UNINSTALL_TITLE_TR="KZM2 + Zapret2 Kaldirma (Tam Temiz)"
TXT_KZM2_FULL_UNINSTALL_TITLE_EN="KZM2 + Zapret2 Uninstall (Full Clean)"
TXT_KZM2_FULL_UNINSTALL_WARN1_TR="Bu islem Zapret2'yi kaldirir ve KZM'nin HealthMon/Telegram ayarlarini, init dosyalarini ve log/state dosyalarini temizler."
TXT_KZM2_FULL_UNINSTALL_WARN1_EN="This will uninstall Zapret2 and clean KZM2 HealthMon/Telegram configs, init files, and log/state files."
TXT_KZM2_FULL_UNINSTALL_WARN2_TR="Islem geri alinamaz. Devam etmeden once yedek aldiginizdan emin olun."
TXT_KZM2_FULL_UNINSTALL_WARN2_EN="This action is irreversible. Make sure you have a backup before continuing."
TXT_KZM2_FULL_UNINSTALL_PROMPT1_TR="Devam etmek icin BUYUK HARFLE 'EVET' yazin (iptal icin Enter): "
TXT_KZM2_FULL_UNINSTALL_PROMPT1_EN="Type 'YES' (uppercase) to continue (press Enter to cancel): "
TXT_KZM2_FULL_UNINSTALL_PROMPT2_TR="Son onay: BUYUK HARFLE 'KALDIR' yazin (iptal icin Enter): "
TXT_KZM2_FULL_UNINSTALL_PROMPT2_EN="Final confirm: type 'REMOVE' (uppercase) (press Enter to cancel): "
TXT_KZM2_FULL_UNINSTALL_CANCEL_TR="Iptal edildi."
TXT_KZM2_FULL_UNINSTALL_CANCEL_EN="Cancelled."
TXT_KZM2_FULL_UNINSTALL_HINT_TR="Iptal icin ENTER'a basin."
TXT_KZM2_FULL_UNINSTALL_HINT_EN="Press ENTER to cancel."
TXT_KZM2_FULL_UNINSTALL_PHASE1_TR="1/2: Zapret2 kaldiriliyor..."
TXT_KZM2_FULL_UNINSTALL_PHASE1_EN="1/2: Uninstalling Zapret2..."
TXT_KZM2_FULL_UNINSTALL_PHASE2_TR="2/2: KZM kalintilari temizleniyor..."
TXT_KZM2_FULL_UNINSTALL_PHASE2_EN="2/2: Cleaning KZM leftovers..."
TXT_KZM2_FULL_UNINSTALL_STEP1_TR="1/2: Zapret2 kaldiriliyor (mevcut kaldirma rutini)..."
TXT_KZM2_FULL_UNINSTALL_STEP1_EN="1/2: Removing Zapret2 (existing uninstall routine)..."
TXT_KZM2_FULL_UNINSTALL_STEP2_TR="2/2: KZM kalintilari temizleniyor..."
TXT_KZM2_FULL_UNINSTALL_STEP2_EN="2/2: Cleaning KZM leftovers..."
TXT_KZM2_FULL_UNINSTALL_DONE_TR="Tam temiz kaldirma tamamlandi."
TXT_KZM2_FULL_UNINSTALL_DONE_EN="Full clean uninstall completed."
TXT_KZM2_FULL_UNINSTALL_NOTE_TR="Not: Bu islemin ardindan betik artik calismayacaktir."
TXT_KZM2_FULL_UNINSTALL_NOTE_EN="Note: After this, the script will no longer be available."
TXT_KZM2_FULL_UNINSTALL_SCRIPT_NOTE_TR="Betik dosyasi guvenlik nedeniyle silinmedi. Isterseniz manuel olarak silebilirsiniz."
TXT_KZM2_FULL_UNINSTALL_SCRIPT_NOTE_EN="Script file was not removed for safety. You may delete it manually if desired."
kzm2_full_uninstall() {
	    clear
	    print_line "=" 120
	    echo "$(T TXT_KZM2_FULL_UNINSTALL_TITLE)"
	    print_line "=" 120
	    echo ""
    print_status WARN "$(T TXT_KZM2_FULL_UNINSTALL_WARN1)"
    print_status WARN "$(T TXT_KZM2_FULL_UNINSTALL_WARN2)"
    echo ""
    print_status INFO "$(T TXT_KZM2_FULL_UNINSTALL_HINT)"
    echo ""
	    printf "%s" "$(T TXT_KZM2_FULL_UNINSTALL_PROMPT1)"
	    read -r _ans1
	    if [ -z "$_ans1" ] || ( [ "$_ans1" != "EVET" ] && [ "$_ans1" != "YES" ] ); then
        print_status INFO "$(T TXT_KZM2_FULL_UNINSTALL_CANCEL)"
        press_enter_to_continue
        return 0
    fi
	    printf "%s" "$(T TXT_KZM2_FULL_UNINSTALL_PROMPT2)"
	    read -r _ans2
	    if [ -z "$_ans2" ] || ( [ "$_ans2" != "KALDIR" ] && [ "$_ans2" != "REMOVE" ] ); then
        print_status INFO "$(T TXT_KZM2_FULL_UNINSTALL_CANCEL)"
        press_enter_to_continue
        return 0
    fi
    echo ""
    print_status INFO "$(T TXT_KZM2_FULL_UNINSTALL_STEP1)"
    uninstall_zapret2 1
    echo ""
    print_status INFO "$(T TXT_KZM2_FULL_UNINSTALL_STEP2)"
    # GUI kaldir (kurulu olsun olmasin, iz birakma)
    if kzm_gui_is_installed 2>/dev/null; then
        print_status INFO "$(T TXT_GUI_REMOVING)"
        kill $(pgrep lighttpd 2>/dev/null) 2>/dev/null || true
        /opt/etc/init.d/S80lighttpd stop >/dev/null 2>&1 || true
        rm -f /opt/etc/init.d/S80lighttpd 2>/dev/null
        rm -rf "$KZM2_GUI_DIR" 2>/dev/null
        rm -rf /opt/etc/lighttpd 2>/dev/null
        rm -f "$KZM2_GUI_STATUS_SCRIPT" "$KZM2_GUI_STATUS_JSON" 2>/dev/null
        rm -f /opt/var/run/kzm2_hw_model /opt/var/run/kzm2_hw_firmware 2>/dev/null
        rm -f /opt/var/log/lighttpd_error.log /opt/var/log/lighttpd_access.log 2>/dev/null
        rm -f /opt/var/run/lighttpd.pid 2>/dev/null
        rm -f "$KZM2_GUI_CONF_CUSTOM" 2>/dev/null
        iptables -D INPUT -p tcp --dport "$KZM2_GUI_PORT" -j ACCEPT 2>/dev/null || true
        opkg remove lighttpd lighttpd-mod-cgi 2>/dev/null || true
        rm -f /opt/etc/lighttpd/conf.d/30-cgi.conf 2>/dev/null
        rmdir /opt/etc/lighttpd/conf.d 2>/dev/null
        rmdir /opt/etc/lighttpd 2>/dev/null
        kzm_gui_remove_cron 2>/dev/null || true
        print_status PASS "$(T TXT_GUI_REMOVED)"
    fi
    # Stop HealthMon daemon ONCE (watchdog botu yeniden baslatmasin diye once HealthMon olduruluyor)
    if [ -f /tmp/kzm2_healthmon.pid ]; then
        _pid="$(cat /tmp/kzm2_healthmon.pid 2>/dev/null)"
        [ -n "$_pid" ] && kill "$_pid" 2>/dev/null
        sleep 1
        [ -n "$_pid" ] && kill -9 "$_pid" 2>/dev/null
        rm -f /tmp/kzm2_healthmon.pid 2>/dev/null
    fi
    ps 2>/dev/null | awk '/--healthmon-daemon/ && !/awk/{print $1}' | while read -r _p; do
        [ -n "$_p" ] && kill -9 "$_p" 2>/dev/null
    done
    rm -rf /tmp/kzm2_healthmon.lock 2>/dev/null
    # Stop Telegram bot daemon if running
    telegram_bot_stop 2>/dev/null || true
    ps 2>/dev/null | awk '/--telegram-daemon/ && !/awk/{print $1}' | while read -r _p; do
        [ -n "$_p" ] && kill -9 "$_p" 2>/dev/null
    done
    rm -f /tmp/kzm2_telegram_bot.pid /tmp/kzm2_telegram_bot.log 2>/dev/null
    rm -f /tmp/kzm2_tgbot_resp.json /tmp/kzm2_nfqws_drops.prev 2>/dev/null
    rm -f /tmp/kzm2_healthmon.last_script_ver /tmp/kzm2_install_easy.log 2>/dev/null
    rm -rf /tmp/kzm2_telegram_daemon.lock 2>/dev/null
    # Remove HealthMon / Telegram configs (KZM-owned)
    rm -f /opt/etc/healthmon.conf /opt/etc/healthmon.conf.bak 2>/dev/null
    rm -f /opt/etc/telegram.conf 2>/dev/null
    # Remove init autostart (if created by KZM)
    rm -f /opt/etc/init.d/S99kzm2_healthmon 2>/dev/null
    # Remove state/log files (KZM/HealthMon/WANMon)
    rm -f /opt/etc/kzm2_update.state 2>/dev/null
    rm -f /tmp/kzm2_autoupdate.log 2>/dev/null
    rm -f /tmp/kzm2_healthmon.log 2>/dev/null
    rm -f /tmp/kzm2_opkg_upgrade.log /tmp/kzm2_opkg_upgrade.ts 2>/dev/null
    rm -f /tmp/healthmon_* /tmp/wanmon.* 2>/dev/null
    # OPKG upgrade cron satirini kaldir
    if crontab -l 2>/dev/null | grep -q '# KZM_OPKG_UPGRADE'; then
        local _tmp="/tmp/kzm_full_uninstall_cron.$$"
        crontab -l 2>/dev/null | grep -v '^#' | grep -v '# KZM_OPKG_UPGRADE' | grep -v '^[[:space:]]*$' > "$_tmp"
        crontab "$_tmp"; rm -f "$_tmp"
    fi
    # Remove helper/wrapper commands created by this script
    rm -f /opt/bin/keenetic-zapret2 /opt/bin/kzm2 /opt/bin/KZM2 /opt/bin/keenetic-zapret /opt/bin/kzm /opt/bin/KZM 2>/dev/null
    # Remove KZM2 DPI profile exports if /opt/zapret2 cleanup was skipped for any reason
    rm -rf /opt/zapret2/dpi_profiles 2>/dev/null
    # Remove KZM backup files (script backups)
    rm -f /opt/lib/opkg/keenetic_zapret2_manager.sh.bak_* 2>/dev/null
    # Script file is NOT removed (safety)
    echo ""
    print_status OK "$(T TXT_KZM2_FULL_UNINSTALL_DONE)"
    print_status INFO "$(T TXT_KZM2_FULL_UNINSTALL_SCRIPT_NOTE)"
    press_enter_to_continue
    exit 0
}
# -------------------------------------------------------------------
# Dogru Dizin Uyarisi (keenetic / keenetic-zapret)
# -------------------------------------------------------------------
check_script_location_once() {
    local EXPECTED="/opt/lib/opkg/keenetic_zapret2_manager.sh"
    local CURRENT="$(readlink -f "$0" 2>/dev/null)"
    [ -z "$CURRENT" ] && return
    if [ "$CURRENT" != "$EXPECTED" ]; then
        echo
        printf "%b %s
" \
            "${CLR_RED}UYARI:${CLR_RESET}" \
            "$(T TXT_WARN_BAD_PATH)"
        echo
        echo "$(T TXT_WARN_MOVE)"
        echo "$(T TXT_WARN_CONTINUE)"
        echo
        printf '%s' "$(T TXT_WARN_CHOICE)"; read -r sel
        case "$sel" in
            1)
                if mv "$CURRENT" "$EXPECTED" 2>/dev/null; then
                    chmod +x "$EXPECTED" 2>/dev/null
                    if [ ! -x "$EXPECTED" ]; then
                        echo
                        printf "%b
" "${CLR_RED}$(T TXT_WARN_CHMOD_FAIL)${CLR_RESET}"
                        press_enter_to_continue
                        return
                    fi
                    echo
                    printf "%b
" "${CLR_GREEN}$(T TXT_WARN_MOVED_OK)${CLR_RESET}"
                    exec "$EXPECTED"
                else
                    echo
                    printf "%b
" "${CLR_RED}$(T TXT_WARN_MOVE_FAIL)${CLR_RESET}"
                    press_enter_to_continue
                fi
                ;;
            0|"")
                return
                ;;
            *)
                return
                ;;
        esac
    fi
}
# -------------------------------------------------------------------
# -------------------------------------------------------------------
# CLI KISAYOL (keenetic / keenetic-zapret)
# -------------------------------------------------------------------
ensure_cli_shortcut() {
    # Script her seferinde tam path ile calistirilmasin diye
    # /opt/bin altina kisa komutlar ekler (idempotent).
    local CURRENT TARGET WRAP1 WRAP2 WRAP3
    CURRENT="$(readlink -f "$0" 2>/dev/null)"
    TARGET="/opt/lib/opkg/keenetic_zapret2_manager.sh"
    [ -f "$TARGET" ] || TARGET="$CURRENT"
    WRAP1="/opt/bin/keenetic-zapret2"
    WRAP2="/opt/bin/kzm2"
    WRAP3="/opt/bin/KZM2"
    WRAP4="/opt/bin/keenetic-zapret"
    WRAP5="/opt/bin/kzm"
    WRAP6="/opt/bin/KZM"
    # Eski KZM1 kalintilari temizle (her calistirmada)
    rm -f /opt/bin/kzm /opt/bin/KZM /opt/bin/keenetic-zapret 2>/dev/null
    rm -f /opt/lib/opkg/keenetic_zapret_otomasyon_ipv6_ipset.sh 2>/dev/null
    # keenetic-zapret2: ana wrapper, her zaman guncelle
    cat > "$WRAP1" <<EOF
#!/opt/bin/sh
exec /opt/bin/sh "$TARGET" "\$@"
EOF
    chmod +x "$WRAP1" 2>/dev/null
    # kzm2 sadece yoksa olustur
    if [ ! -e "$WRAP2" ]; then
        ln -s "$WRAP1" "$WRAP2" 2>/dev/null || cp -a "$WRAP1" "$WRAP2"
        chmod +x "$WRAP2" 2>/dev/null
    fi
    # KZM2 sadece yoksa olustur
    if [ ! -e "$WRAP3" ]; then
        ln -s "$WRAP1" "$WRAP3" 2>/dev/null || cp -a "$WRAP1" "$WRAP3"
        chmod +x "$WRAP3" 2>/dev/null
    fi
    # Eski aliskanlik kisayollari — KZM1 kalintisi silinince yeniden olustur
    if [ ! -e "$WRAP4" ]; then
        ln -s "$WRAP1" "$WRAP4" 2>/dev/null || cp -a "$WRAP1" "$WRAP4"
        chmod +x "$WRAP4" 2>/dev/null
    fi
    if [ ! -e "$WRAP5" ]; then
        ln -s "$WRAP1" "$WRAP5" 2>/dev/null || cp -a "$WRAP1" "$WRAP5"
        chmod +x "$WRAP5" 2>/dev/null
    fi
    if [ ! -e "$WRAP6" ]; then
        ln -s "$WRAP1" "$WRAP6" 2>/dev/null || cp -a "$WRAP1" "$WRAP6"
        chmod +x "$WRAP6" 2>/dev/null
    fi
    return 0
}
# Ilk calistirmada CLI kisayolunu garanti altina al (daemon/cron modlarinda atla)
case "$1" in
    --healthmon-daemon|--telegram-daemon|--opkg-upgrade|--netfilter-hook|--cgi-action|--gui-status) ;;
    *) ensure_cli_shortcut ;;
esac
# -------------------------------------------------------------------
# Zapret2 IPv6 destegi secimi (y/n). Varsayilan: n
ZAPRET_IPV6="n"
# -------------------------------------------------------------------
# Dil (TR/EN) Secimi ve Sozluk
# -------------------------------------------------------------------
LANG_FILE="/opt/zapret2/lang"
LANG="tr"
# -------------------------------------------------------------------
# Renkler (ANSI) - sadece terminal (TTY) ise etkin
# -------------------------------------------------------------------
# NO_COLOR=1 -> renk kapali
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ "${NO_COLOR:-0}" != "1" ]; then
    CLR_CYAN="$(printf '\033[36m')"
    CLR_YELLOW="$(printf '\033[33m')"
    CLR_GREEN="$(printf '\033[32m')"
    CLR_RED="$(printf '\033[31m')"
    CLR_ORANGE="$(printf '\033[38;5;214m')"
    CLR_BOLD="$(printf '\033[1m')"
    CLR_DIM="$(printf '\033[2m')"
    CLR_RESET="$(printf '\033[0m')"
else
    CLR_CYAN=""
    CLR_YELLOW=""
    CLR_GREEN=""
    CLR_RED=""
    CLR_ORANGE=""
    CLR_BOLD=""
    CLR_DIM=""
    CLR_RESET=""
fi
# -------------------------------------------------------------------
# UI: Dinamik cizgi (terminal genisligine gore)
#  - UI_COLS=100 ile elle zorlanabilir
#  - tput/stty yoksa 80 kolon varsayilir
# -------------------------------------------------------------------
get_term_cols() {
    # Prefer UI_COLS override
    if [ -n "${UI_COLS:-}" ]; then
        printf '%s' "${UI_COLS}"
        return 0
    fi
    # Prefer tput, fallback to stty, fallback to 80
    c="$(tput cols 2>/dev/null)"
    if [ -n "$c" ]; then
        printf '%s' "$c"
        return 0
    fi
    c="$(stty size 2>/dev/null | awk '{print $2}')"
    if [ -n "$c" ]; then
        printf '%s' "$c"
        return 0
    fi
    printf '%s' "80"
    return 0
}
print_line() {
    # Usage: print_line "="  OR  print_line "-"
    ch="${1:-=}"
    cols="$(get_term_cols)"
    [ -z "$cols" ] && cols=80
    # minimum width
    if [ "$cols" -lt 50 ] 2>/dev/null; then cols=50; fi
    # print repeated character up to terminal width
    printf "%*s\n" "$cols" "" | tr " " "$ch"
}
# Screen helper
clear_screen() {
    # Prefer 'clear' if available; otherwise reset the terminal
    if command -v clear >/dev/null 2>&1; then
        clear
    else
        printf '\033c'
    fi
}
hc_word() {
    # PASS/WARN/FAIL kelimesini renklendirir (renk kapaliysa sade basar)
    case "$1" in
        PASS) printf '%b' "${CLR_GREEN}PASS${CLR_RESET}" ;;
        WARN) printf '%b' "${CLR_YELLOW}WARN${CLR_RESET}" ;;
        INFO) printf '%b' "${CLR_CYAN}INFO${CLR_RESET}" ;;
        FAIL) printf '%b' "${CLR_RED}FAIL${CLR_RESET}" ;;
        *)    printf '%s' "$1" ;;
    esac
}
# --- Health helpers (used by Health Score layout) ---
_nslookup_t() {
    # nslookup with 5s timeout via background+kill (timeout komutu gerekmez)
    nslookup "$1" "$2" >/dev/null 2>&1 &
    local _pid=$! _i=0
    while [ "$_i" -lt 5 ]; do
        if ! kill -0 "$_pid" 2>/dev/null; then
            wait "$_pid" 2>/dev/null
            return $?
        fi
        sleep 1
        _i=$(( _i + 1 ))
    done
    kill "$_pid" 2>/dev/null
    return 1
}
_nslookup_ip() {
    # nslookup ile IP coz, sonucu stdout'a yaz (5s timeout, temp dosya ile)
    local _tmp="/tmp/nslookup_ip_$$"
    nslookup "$1" "$2" 2>/dev/null | awk '/^Address [0-9]+:/{print $3; exit}' > "$_tmp" &
    local _pid=$! _i=0
    while [ "$_i" -lt 5 ]; do
        if ! kill -0 "$_pid" 2>/dev/null; then
            cat "$_tmp" 2>/dev/null
            rm -f "$_tmp"
            return 0
        fi
        sleep 1
        _i=$(( _i + 1 ))
    done
    kill "$_pid" 2>/dev/null
    rm -f "$_tmp"
    return 1
}
check_dns_local() {
    _nslookup_t github.com 127.0.0.1
}
check_dns_external() {
    _nslookup_t github.com 8.8.8.8
}
check_dns_consistency() {
    local dns_local_ip dns_pub_ip
    dns_local_ip="$(_nslookup_ip github.com 127.0.0.1)"
    dns_pub_ip="$(_nslookup_ip github.com 8.8.8.8)"
    [ -n "$dns_local_ip" ] && [ -n "$dns_pub_ip" ] && [ "$dns_local_ip" = "$dns_pub_ip" ]
}
check_ntp() {
    local now_epoch
    now_epoch="$(date +%s 2>/dev/null)"
    [ -n "$now_epoch" ] && [ "$now_epoch" -gt 1609459200 ] 2>/dev/null
}
check_github() {
    local code
    code="$(curl -I -m 5 -s -o /dev/null -w '%{http_code}' https://api.github.com/ 2>/dev/null)"
    case "$code" in
        2*|3*) return 0 ;;
        *) return 1 ;;
    esac
}
check_opkg() {
    command -v opkg >/dev/null 2>&1 && opkg --version >/dev/null 2>&1
}
# print_status LEVEL MESSAGE
# LEVEL: PASS/WARN/INFO/FAIL (colored via hc_word)
print_status() {
    local _lvl _msg
    _lvl="$1"; shift
    _msg="$*"
    # If colors are disabled, hc_word will return plain text
    printf "%s %s\n" "$(hc_word "$_lvl")" "$_msg"
}
color_mode_name() {
    # outputs colored mode name for menu display
    local _m="$1"
    [ -z "$_m" ] && _m="$(get_mode_filter)"
    case "$_m" in
        autohostlist) printf '%b' "${CLR_GREEN}$(T _ 'Otomatik Liste' 'Auto Hostlist')${CLR_RESET}" ;;
        hostlist)     printf '%b' "${CLR_CYAN}$(T _ 'Manuel Liste' 'Hostlist')${CLR_RESET}" ;;
        none|"")      printf '%b' "${CLR_YELLOW}$(T _ 'Listesiz' 'No Filter')${CLR_RESET}" ;;
        *)            printf '%b' "$_m" ;;
    esac
}
# Zapret2 installed version (from file). Safe if not installed.
ZAPRET_VERSION_FILE="/opt/zapret2/version"
kzm2_get_zapret_version() {
    local v _bin
    v="$(T TXT_UNKNOWN "$TXT_UNKNOWN_TR" "$TXT_UNKNOWN_EN")"
    if [ -r "$ZAPRET_VERSION_FILE" ]; then
        v="$(head -n 1 "$ZAPRET_VERSION_FILE" 2>/dev/null | tr -d '\r\n')"
    fi
    if [ -z "$v" ] || [ "$v" = "$(T TXT_UNKNOWN "$TXT_UNKNOWN_TR" "$TXT_UNKNOWN_EN")" ]; then
        _bin="/opt/zapret2/nfq2/nfqws2"
        if [ -x "$_bin" ]; then
            v="$("$_bin" --version 2>/dev/null | head -n 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            [ -z "$v" ] && v="Zapret2"
        fi
    fi
    [ -n "$v" ] || v="$(T TXT_UNKNOWN "$TXT_UNKNOWN_TR" "$TXT_UNKNOWN_EN")"
    printf "%s" "$v"
}
# ---- Main banner live status helpers (safe, minimal) ----
kzm2_banner_ndmc_ok() {
    command -v ndmc >/dev/null 2>&1 || return 1
    ndmc -c 'show version' >/dev/null 2>&1
}
kzm2_banner_get_ndmc_field() {
    # $1: field name (e.g., "model:")
    [ -n "$1" ] || return 1
    ndmc -c 'show version' 2>/dev/null | tr -d '\r' | awk -v f="$1" '$1==f{ $1=""; sub(/^[ \t]+/,""); print; exit }'
}
# KN numarasindan cihaz adi dondurur
_kzm2_kn_to_name() {
    case "$1" in
        KN-1010) echo "Keenetic Giga (KN-1010)"           ;;
        KN-1011) echo "Keenetic Giga (KN-1011)"           ;;
        KN-1012) echo "Keenetic Hero (KN-1012)"           ;;
        KN-1110) echo "Keenetic Start (KN-1110)"          ;;
        KN-1111) echo "Keenetic Start (KN-1111)"          ;;
        KN-1112) echo "Keenetic Start (KN-1112)"          ;;
        KN-1121) echo "Keenetic Starter (KN-1121)"        ;;
        KN-1210) echo "Keenetic 4G (KN-1210)"             ;;
        KN-1211) echo "Keenetic 4G (KN-1211)"             ;;
        KN-1212) echo "Keenetic 4G (KN-1212)"             ;;
        KN-1213) echo "Keenetic 4G (KN-1213)"             ;;
        KN-1221) echo "Keenetic Launcher (KN-1221)"       ;;
        KN-1310) echo "Keenetic Lite (KN-1310)"           ;;
        KN-1311) echo "Keenetic Lite (KN-1311)"           ;;
        KN-1410) echo "Keenetic Omni (KN-1410)"           ;;
        KN-1510) echo "Keenetic City (KN-1510)"           ;;
        KN-1511) echo "Keenetic City (KN-1511)"           ;;
        KN-1610) echo "Keenetic Air (KN-1610)"            ;;
        KN-1611) echo "Keenetic Air (KN-1611)"            ;;
        KN-1613) echo "Keenetic Air (KN-1613)"            ;;
        KN-1621) echo "Keenetic Explorer (KN-1621)"       ;;
        KN-1710) echo "Keenetic Extra (KN-1710)"          ;;
        KN-1711) echo "Keenetic Extra (KN-1711)"          ;;
        KN-1713) echo "Keenetic Extra (KN-1713)"          ;;
        KN-1714) echo "Keenetic Extra (KN-1714)"          ;;
        KN-1721) echo "Keenetic Carrier (KN-1721)"        ;;
        KN-1810) echo "Keenetic Ultra (KN-1810)"          ;;
        KN-1811) echo "Keenetic Titan (KN-1811)"          ;;
        KN-1812) echo "Keenetic Titan (KN-1812)"          ;;
        KN-1910) echo "Keenetic Viva (KN-1910)"           ;;
        KN-1912) echo "Keenetic Viva (KN-1912)"           ;;
        KN-1913) echo "Keenetic Viva (KN-1913)"           ;;
        KN-2010) echo "Keenetic DSL (KN-2010)"            ;;
        KN-2012) echo "Keenetic Launcher DSL (KN-2012)"   ;;
        KN-2110) echo "Keenetic Duo (KN-2110)"            ;;
        KN-2112) echo "Keenetic Extra DSL / Skipper DSL (KN-2112)" ;;
        KN-2113) echo "Keenetic Speedster DSL (KN-2113)"  ;;
        KN-2210) echo "Keenetic Runner 4G (KN-2210)"      ;;
        KN-2211) echo "Keenetic Runner 4G (KN-2211)"      ;;
        KN-2212) echo "Keenetic Runner 4G (KN-2212)"      ;;
        KN-2310) echo "Keenetic Hero 4G (KN-2310)"        ;;
        KN-2311) echo "Keenetic Hero 4G+ (KN-2311)"       ;;
        KN-2312) echo "Keenetic Hopper 4G+ (KN-2312)"     ;;
        KN-2410) echo "Keenetic Giga SE (KN-2410)"        ;;
        KN-2510) echo "Keenetic Ultra SE (KN-2510)"       ;;
        KN-2610) echo "Keenetic Giant (KN-2610)"          ;;
        KN-2710) echo "Keenetic Peak (KN-2710)"           ;;
        KN-2810) echo "Keenetic Orbiter Pro (KN-2810)"    ;;
        KN-2910) echo "Keenetic Skipper 4G (KN-2910)"     ;;
        KN-2911) echo "Keenetic Speedster 4G+ (KN-2911)"  ;;
        KN-3010) echo "Keenetic Speedster (KN-3010)"      ;;
        KN-3012) echo "Keenetic Speedster (KN-3012)"      ;;
        KN-3013) echo "Keenetic Speedster (KN-3013)"      ;;
        KN-3210) echo "Keenetic Buddy 4 (KN-3210)"        ;;
        KN-3211) echo "Keenetic Buddy 4 (KN-3211)"        ;;
        KN-3310) echo "Keenetic Buddy 5 (KN-3310)"        ;;
        KN-3311) echo "Keenetic Buddy 5 (KN-3311)"        ;;
        KN-3410) echo "Keenetic Buddy 5S (KN-3410)"       ;;
        KN-3411) echo "Keenetic Buddy 6 (KN-3411)"        ;;
        KN-3510) echo "Keenetic Voyager Pro (KN-3510)"    ;;
        KN-3610) echo "Keenetic Hopper DSL (KN-3610)"     ;;
        KN-3611) echo "Keenetic Hopper DSL (KN-3611)"     ;;
        KN-3710) echo "Keenetic Sprinter (KN-3710)"       ;;
        KN-3711) echo "Keenetic Sprinter (KN-3711)"       ;;
        KN-3712) echo "Keenetic Sprinter SE (KN-3712)"    ;;
        KN-3810) echo "Keenetic Hopper (KN-3810)"         ;;
        KN-3811) echo "Keenetic Hopper (KN-3811)"         ;;
        KN-3812) echo "Keenetic Hopper SE (KN-3812)"      ;;
        KN-3910) echo "Keenetic Challenger (KN-3910)"     ;;
        KN-3911) echo "Keenetic Challenger SE (KN-3911)"  ;;
        KN-4010) echo "Keenetic Racer (KN-4010)"          ;;
        KN-4110) echo "Keenetic Hero 5G (KN-4110)"        ;;
        KN-4210) echo "Keenetic Titan SE (KN-4210)"       ;;
        KN-4310) echo "Keenetic Atlas SE (KN-4310)"       ;;
        KN-4410) echo "Keenetic Buddy 6 SE (KN-4410)"     ;;
        KN-4910) echo "Keenetic Explorer 4G (KN-4910)"    ;;
        *)        echo "Keenetic $1"                       ;;
    esac
}
kzm2_banner_get_system() {
    local m="" _ver="" _sys="" _kn=""
    # 1) ndmc show version
    _ver="$(ndmc -c show version 2>/dev/null | tr -d '\r')"
    if [ -n "$_ver" ]; then
        # Once description: ara — tam isim burada (ornek: "Keenetic Titan (KN-1811)")
        m="$(printf '%s\n' "$_ver" | awk -F': ' '
            /description:/ {
                gsub(/^[ \t]+|[ \t]+$/, "", $2);
                if ($2 != "") { print $2; exit }
            }')"
        # description yoksa diger alanlara bak
        [ -z "$m" ] && m="$(printf '%s\n' "$_ver" | awk -F': ' '
            /model:|product:|device:|hardware:|board:/ {
                gsub(/^[ \t]+|[ \t]+$/, "", $2);
                if ($2 != "") { print $2; exit }
            }')"
        if [ -n "$m" ]; then
            case "$m" in
                KN-[0-9]*) _kzm2_kn_to_name "$m"; return 0 ;;
                Keenetic*) echo "$m"; return 0 ;;
                *) echo "Keenetic $m"; return 0 ;;
            esac
        fi
        _kn="$(printf '%s\n' "$_ver" | grep -Eo 'KN-[0-9]{3,5}' | head -1)"
        [ -n "$_kn" ] && { _kzm2_kn_to_name "$_kn"; return 0; }
    fi
    # 2) ndmc show system
    _sys="$(ndmc -c show system 2>/dev/null | tr -d '\r')"
    if [ -n "$_sys" ]; then
        m="$(printf '%s\n' "$_sys" | awk -F': ' '
            /description:/ {
                gsub(/^[ \t]+|[ \t]+$/, "", $2);
                if ($2 != "") { print $2; exit }
            }')"
        [ -z "$m" ] && m="$(printf '%s\n' "$_sys" | awk -F': ' '
            /model:|product:|device:|hardware:|board:/ {
                gsub(/^[ \t]+|[ \t]+$/, "", $2);
                if ($2 != "") { print $2; exit }
            }')"
        if [ -n "$m" ]; then
            case "$m" in
                KN-[0-9]*) _kzm2_kn_to_name "$m"; return 0 ;;
                Keenetic*) echo "$m"; return 0 ;;
                *) echo "Keenetic $m"; return 0 ;;
            esac
        fi
        _kn="$(printf '%s\n' "$_sys" | grep -Eo 'KN-[0-9]{3,5}' | head -1)"
        [ -n "$_kn" ] && { _kzm2_kn_to_name "$_kn"; return 0; }
    fi
    # 3) /proc/device-tree/model veya /sys/firmware/devicetree/base/model
    for _f in /proc/device-tree/model /sys/firmware/devicetree/base/model; do
        [ -r "$_f" ] || continue
        m="$(tr -d '\000' <"$_f" 2>/dev/null)"
        [ -z "$m" ] && continue
        _kn="$(echo "$m" | grep -Eo 'KN-[0-9]{3,5}' | head -1)"
        [ -n "$_kn" ] && { _kzm2_kn_to_name "$_kn"; return 0; }
        echo "$m"; return 0
    done
    # 4) /etc/components.xml — model="KN-XXXX"
    if [ -r /etc/components.xml ]; then
        _kn="$(grep -o 'model="KN-[0-9]*"' /etc/components.xml 2>/dev/null | head -1 | grep -o 'KN-[0-9]*')"
        [ -n "$_kn" ] && { _kzm2_kn_to_name "$_kn"; return 0; }
    fi
    # 5) MTD U-Config partition — ndmhwid=KN-XXXX
    # /proc/mtd'den "U-Config" adli bolumu bul, sadece ilk 64KB oku
    if [ -r /proc/mtd ]; then
        local _mtddev
        _mtddev="$(awk -F'[: "]+' '/U-Config/{print "/dev/"$1"ro"; exit}' /proc/mtd 2>/dev/null)"
        if [ -n "$_mtddev" ] && [ -r "$_mtddev" ]; then
            _kn="$(dd if="$_mtddev" bs=1024 count=64 2>/dev/null | strings | grep -o 'KN-[0-9]*' | head -1)"
            [ -n "$_kn" ] && { _kzm2_kn_to_name "$_kn"; return 0; }
        fi
    fi
    echo "Keenetic"
}
kzm2_banner_get_firmware() {
    # /etc/components.xml'den firmware versiyonu ve kanal bilgisini okur
    # Cikti: "5.0.6 (Onizleme)" gibi
    local _xml _version _sandbox _channel_tr
    [ -r /etc/components.xml ] || return 1
    _xml="$(cat /etc/components.xml 2>/dev/null)" || return 1
    # Kisa versiyon: <title>5.0.6</title>
    _version="$(printf '%s' "$_xml" | grep -o '<title>[^<]*</title>' | head -1 | sed 's/<title>//;s/<\/title>//')"
    [ -z "$_version" ] && _version="$(printf '%s' "$_xml" | grep -o 'version="[^"]*"' | head -1 | sed 's/version="//;s/"//')"
    [ -z "$_version" ] && return 1
    # Kanal: sandbox="stable|preview|alpha"
    _sandbox="$(printf '%s' "$_xml" | grep -o 'sandbox="[^"]*"' | head -1 | sed 's/sandbox="//;s/"//')"
    # Kanal adini yerellestir
    case "$_sandbox" in
        stable)  _channel_tr="$(T _ 'Kararli'     'Stable')"     ;;
        lts)     _channel_tr="LTS"                               ;;
        archive) _channel_tr="$(T _ 'Arsiv' 'Archive')"             ;;
        preview) _channel_tr="$(T _ 'Onizleme'    'Preview')"    ;;
        alpha)   _channel_tr="$(T _ 'Gelistirici' 'Developer')"  ;;
        *)       _channel_tr="$_sandbox"                          ;;
    esac
    if [ -n "$_channel_tr" ]; then
        printf '%s (%s)' "$_version" "$_channel_tr"
    else
        printf '%s' "$_version"
    fi
}
kzm2_banner_get_wan_dev() {
    local dev=""
    dev="$(get_wan_if 2>/dev/null)"
    if [ -z "$dev" ] && [ -f "$WAN_IF_FILE" ]; then
        # Dosya var ama bos = kullanici tum arayuzler secmis
        printf "%s" "$(T _ 'Tum Arayuzler' 'All Interfaces')"
        return 0
    fi
    [ -z "$dev" ] && dev="$(healthmon_detect_wan_iface_ndm 2>/dev/null)"
    # Fallback: parse default route robustly (avoid returning 'link')
    if [ -z "$dev" ]; then
        dev="$(ip route 2>/dev/null | awk '$1=="default"{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    fi
    printf "%s" "$dev"
}
kzm2_banner_get_wan_state() {
    local dev="$1"
    local up
    # Bos veya "Tum Arayuzler" = tum arayuzler modu, durum kontrolu yapma
    [ -z "$dev" ] && { echo "UP"; return 0; }
    echo "$dev" | grep -qE "Arayuz|Interfaces" && { echo "UP"; return 0; }
    up="$(ip link show "$dev" 2>/dev/null | head -n 1)"
    echo "$up" | grep -q 'LOWER_UP' && { echo "UP"; return 0; }
    echo "$up" | grep -q '<.*UP' && { echo "UP"; return 0; }
    echo "DOWN"
}
kzm2_banner_get_zapret_state() {
    if is_zapret2_running; then
        echo "RUNNING"
    else
        echo "STOPPED"
    fi
}
kzm2_banner_fmt_wan_state() {
    # $1: UP|DOWN
    case "$1" in
        UP)   printf '%b' "${CLR_GREEN}$(T TXT_MAIN_UP)${CLR_RESET}" ;;
        *)    printf '%b' "${CLR_RED}$(T TXT_MAIN_DOWN)${CLR_RESET}" ;;
    esac
}
# IP adresini siniflandir: public / cgnat / private
kzm2_classify_ip() {
    local ip="$1"
    # CGNAT: 100.64.0.0/10
    case "$ip" in
        100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*)
            echo "cgnat"; return ;;
    esac
    # Private: 10.x, 192.168.x, 172.16-31.x
    case "$ip" in
        10.*|192.168.*) echo "private"; return ;;
    esac
    case "$ip" in
        172.1[6-9].*|172.2[0-9].*|172.3[01].*) echo "private"; return ;;
    esac
    echo "public"
}
# IP'yi renkli formatla (alt-shell uyumu icin hardcoded escape)
kzm2_fmt_ip() {
    local ip="$1" type
    type="$(kzm2_classify_ip "$ip")"
    case "$type" in
        cgnat)   printf '\033[1;33m%s\033[0m \033[33m[CGNAT]\033[0m'  "$ip" ;;
        private) printf '\033[1;33m%s\033[0m \033[33m[NAT]\033[0m'    "$ip" ;;
        *)       printf '\033[1;32m%s\033[0m'                            "$ip" ;;
    esac
}
kzm2_banner_fmt_zapret_state() {
    # $1: RUNNING|STOPPED
    case "$1" in
        RUNNING) printf '%b' "${CLR_GREEN}$(T TXT_MAIN_RUNNING)${CLR_RESET}" ;;
        *)       printf '%b' "${CLR_RED}$(T TXT_MAIN_STOPPED)${CLR_RESET}" ;;
    esac
}
kzm2_banner_fmt_keendns_state() {
    # $1: direct|cloud|unknown/empty
    case "$1" in
        direct) printf '%b' "${CLR_GREEN}$(T TXT_KEENDNS_DIRECT)${CLR_RESET}" ;;
        cloud)  printf '%b' "${CLR_YELLOW}$(T TXT_KEENDNS_CLOUD)${CLR_RESET}" ;;
        *)      printf '%b' "${CLR_RED}$(T TXT_KEENDNS_UNKNOWN)${CLR_RESET}" ;;
    esac
}
# Sozluk: TXT_*_TR / TXT_*_EN
TXT_MAIN_TITLE_TR="KEENETIC ZAPRET2 YONETIM ARACI (KZM2)"
TXT_MAIN_TITLE_EN="KEENETIC ZAPRET2 MANAGEMENT TOOL (KZM2)"
TXT_OPTIMIZED_TR=" Varsayilan ayarlar TT altyapisinda test edilerek optimize edilmistir."
TXT_OPTIMIZED_EN=" Default settings are tested and optimized for TT infrastructure."
TXT_DPI_WARNING_TR=" DPI profil basarimi; ISS, hat tipine gore degiskenlik gosterebilir."
TXT_DPI_WARNING_EN=" DPI profile effectiveness may vary by ISP, line type."
TXT_ISS_LABEL_TR="ISS"
TXT_ISS_LABEL_EN="ISP"
TXT_DPI_MISMATCH_TR="ISS ile eslesmeyebilir! Menu 9'dan profil secin."
TXT_DPI_MISMATCH_EN="May not match ISP! Select profile from Menu 9."
TXT_DEVELOPER_TR=" Gelistirici : RevolutionTR"
TXT_DEVELOPER_EN=" Developer  : RevolutionTR"
TXT_GITHUB_TR=" GitHub      : github.com/RevolutionTR/keenetic-zapret2-manager"
TXT_GITHUB_EN=" GitHub     : github.com/RevolutionTR/keenetic-zapret2-manager"
# TXT_EDITOR_TR=" Duzenleyen  : RevolutionTR"
# TXT_EDITOR_EN=" Maintainer : RevolutionTR"
TXT_VERSION_TR=" KZM2 Surum  : ${SCRIPT_VERSION}"
TXT_VERSION_EN=" KZM2 Version: ${SCRIPT_VERSION}"
TXT_ZAPRET_VERSION_PREFIX_TR=" Zapret2 Surum: "
TXT_ZAPRET_VERSION_PREFIX_EN=" Zapret2 Ver : "
TXT_UNKNOWN_TR="Kurulu Degil"
TXT_UNKNOWN_EN="Not Installed"
TXT_MAIN_SYS_LABEL_TR="Sistem"
TXT_MAIN_SYS_LABEL_EN="System"
TXT_MAIN_WAN_LABEL_TR="WAN"
TXT_MAIN_WAN_LABEL_EN="WAN"
TXT_MAIN_ZAPRET_LABEL_TR="Zapret2"
TXT_MAIN_ZAPRET_LABEL_EN="Zapret2"
TXT_MAIN_UP_TR="ACIK"
TXT_MAIN_UP_EN="UP"
TXT_MAIN_DOWN_TR="KAPALI"
TXT_MAIN_DOWN_EN="DOWN"
TXT_MAIN_RUNNING_TR="CALISIYOR"
TXT_MAIN_RUNNING_EN="RUNNING"
TXT_MAIN_STOPPED_TR="DURDU"
TXT_MAIN_STOPPED_EN="STOPPED"
TXT_DESC1_TR="Bu arac, Keenetic cihazlarinda Zapret2 kurulumunu,"
TXT_DESC1_EN="This tool unifies Zapret2 installation,"
TXT_DESC2_TR="yonetimini ve sistem izlemeyi tek noktada toplayan"
TXT_DESC2_EN="management, and system monitoring"
TXT_DESC3_TR="gelismis bir yonetim cozumudur."
TXT_DESC3_EN="into a centralized solution for Keenetic devices."
TXT_MENU_HEADER_TR="------------------- ANA MENU --------------------------------------------------------------"
TXT_MENU_HEADER_EN="-------------------- MAIN MENU ------------------------------------------------------------"
TXT_MENU_1_TR=" 1. Zapret2'yi Yukle"
TXT_MENU_1_EN=" 1. Install Zapret2"
TXT_MENU_2_TR=" 2. Zapret2'yi Kaldir"
TXT_MENU_2_EN=" 2. Uninstall Zapret2"
TXT_MENU_3_TR=" 3. Zapret2'yi Baslat"
TXT_MENU_3_EN=" 3. Start Zapret2"
TXT_MENU_4_TR=" 4. Zapret2'yi Durdur (Kalici Durdurma icin: Menu 16>4>5 zapret2 oto-start kapatin)"
TXT_MENU_4_EN=" 4. Stop Zapret2 (Permanent: Menu 16>4>5 disable zapret2 auto-start)"
TXT_MENU_5_TR=" 5. Zapret2'yi Yeniden Baslat"
TXT_MENU_5_EN=" 5. Restart Zapret2"
TXT_MENU_6_TR=" 6. Zapret2 Guncelleme Kontrolu (Guncel/Kurulu - GitHub)"
TXT_MENU_6_EN=" 6. Zapret2 Update Check (Latest/Installed - GitHub)"
TXT_MENU_7_TR=" 7. Zapret2 IPv6 Destegi (Sihirbaz)"
TXT_MENU_7_EN=" 7. Zapret2 IPv6 support (Wizard)"
TXT_MENU_8_TR=" 8. Zapret2 / KZM2 Yedekle / Geri Yukle"
TXT_MENU_8_EN=" 8. Zapret2 / KZM2 Backup / Restore"
TXT_MENU_9_TR=" 9. DPI Profili / WAN Arayuzu"
TXT_MENU_9_EN=" 9. DPI Profile / WAN Interface"
TXT_ACTIVE_DPI_TR=" Aktif DPI Profili"
TXT_ACTIVE_DPI_EN=" Active DPI Profile"
TXT_ACTIVE_DPI_AUTO_TR=" Blockcheck (Otomatik)"
TXT_ACTIVE_DPI_AUTO_EN=" Blockcheck (Auto)"
TXT_ACTIVE_DPI_DEFAULT_TR=" Varsayilan / Manuel"
TXT_ACTIVE_DPI_DEFAULT_EN=" Default / Manual"
TXT_ACTIVE_DPI_PARAMS_TR=" Parametreler"
TXT_ACTIVE_DPI_PARAMS_EN=" Parameters"
TXT_DPI_AUTO_NOTE_TR=" Not: Blockcheck (Otomatik) aktifken asagidaki 1-8 profilleri pasiftir."
TXT_DPI_AUTO_NOTE_EN=" Note: While Blockcheck (Auto) is active, profiles 1-8 below are inactive."
TXT_DPI_BASE_TR=" (Temel)"
TXT_DPI_BASE_EN=" (Base)"
TXT_DPI_BASE_PROFILE_TR=" Temel Profil"
TXT_DPI_BASE_PROFILE_EN=" Base Profile"
TXT_DPI_AUTO_DISABLE_PROMPT_TR="Blockcheck (Otomatik) aktif. Manuel profile gecmek otomatik modu kapatir. Devam edilsin mi? (e/h) [e]: "
TXT_DPI_AUTO_DISABLE_PROMPT_EN="Blockcheck (Auto) is active. Switching to a manual profile will disable auto mode. Continue? (y/n) [y]: "
TXT_BLOCKCHECK_APPLY_TR=" Bu ayarlari DPI profili olarak uygulamak ister misiniz? (e/h) [e]: "
TXT_BLOCKCHECK_APPLY_EN=" Apply these settings as DPI profile? (y/n) [y]: "
TXT_BLOCKCHECK_APPLIED_TR=" Ayarlar uygulandi ve Zapret2 yeniden baslatildi."
TXT_BLOCKCHECK_APPLIED_EN=" Settings applied and Zapret2 restarted."
TXT_BLOCKCHECK_NO_STRAT_TR=" UYARI: Uygulanabilir nfqws stratejisi bulunamadi."
TXT_BLOCKCHECK_NO_STRAT_EN=" WARNING: No applicable nfqws strategy found."
TXT_BLOCKCHECK_TPWS_WARN_TR=" UYARI: Bulunan strateji tpws. Guvenli oldugu icin otomatik uygulanmayacak. (Simdilik sadece nfqws destekleniyor.)"
TXT_BLOCKCHECK_TPWS_WARN_EN=" WARNING: Found strategy is tpws. It will NOT be applied automatically for safety. (For now only nfqws is supported.)"
TXT_MENU_10_TR="10. Betik Guncelleme Kontrolu (Guncel/Kurulu - GitHub)"
TXT_MENU_10_EN="10. Script Update Check (Latest/Installed - GitHub)"
TXT_MENU_11_TR="11. Hostlist / Autohostlist (Filtreleme)"
TXT_MENU_11_EN="11. Hostlist / Autohostlist (Filtering)"
TXT_MENU_12_TR="12. IPSET (Statik IP kullanan cihazlarla calisir - DHCP desteklenmez!)"
TXT_MENU_12_EN="12. IPSET (Works with static IP devices - DHCP is not supported!)"
TXT_MENU_13_TR="13. Betik: Yedekten Geri Don (Rollback)"
TXT_MENU_13_EN="13. Script: Roll Back from Backup"
TXT_MENU_14_TR="14. Ag Tanilama ve Sistem Kontrolu (DNS/NTP/GitHub/OPKG/Disk/Zapret2)"
TXT_MENU_14_EN="14. Network Diagnostics & System Check (DNS/NTP/GitHub/OPKG/Disk/Zapret2)"
TXT_MENU_15_TR="15. Bildirimler (Telegram)"
TXT_MENU_15_EN="15. Notifications (Telegram)"
TXT_MENU_16_TR="16. Sistem Sagligi ve Izleme (CPU/RAM/Disk/Load/Zapret2)"
TXT_MENU_16_EN="16. System Health and Monitoring (CPU/RAM/Disk/Load/Zapret2)"
# -------------------------------------------------------------------
# Telegram notifications
# -------------------------------------------------------------------
TXT_TG_SETTINGS_TITLE_TR="Telegram Bildirim Ayarlari"
TXT_TG_SETTINGS_TITLE_EN="Telegram Notification Settings"
TXT_TG_TIME_LABEL_TR="Zaman "
TXT_TG_TIME_LABEL_EN="Time  "
TXT_TG_MODEL_LABEL_TR="Model "
TXT_TG_MODEL_LABEL_EN="Model "
TXT_TG_WAN_LABEL_TR="WAN IP"
TXT_TG_WAN_LABEL_EN="WAN IP"
TXT_TG_LAN_LABEL_TR="LAN IP"
TXT_TG_LAN_LABEL_EN="LAN IP"
TXT_TG_DEVICE_LABEL_TR="Cihaz"
TXT_TG_DEVICE_LABEL_EN="Router"
TXT_TG_EVENT_LABEL_TR="Olay"
TXT_TG_EVENT_LABEL_EN="Event"
TXT_TG_STATUS_ACTIVE_TR="Bildirimler: AKTIF (Token ve ChatID kayitli)"
TXT_TG_STATUS_ACTIVE_EN="Notifications: ACTIVE (Token and ChatID saved)"
TXT_TG_STATUS_NOT_CONFIG_TR="Durum: AYARLANMAMIS"
TXT_TG_STATUS_NOT_CONFIG_EN="Status: NOT CONFIGURED"
TXT_TG_SAVE_UPDATE_TR="Token/ChatID Kaydet-Guncelle"
TXT_TG_SAVE_UPDATE_EN="Save/Update Token & ChatID"
TXT_TG_SEND_TEST_TR="Test Mesaji Gonder"
TXT_TG_SEND_TEST_EN="Send Test Message"
TXT_TG_DELETE_RESET_TR="Ayar Dosyasini Sil (Reset)"
TXT_TG_DELETE_RESET_EN="Delete Config (Reset)"
TXT_TG_ENTER_TOKEN_TR="Bot Token girin (yapistir):"
TXT_TG_ENTER_TOKEN_EN="Enter Bot Token (paste):"
TXT_TG_ENTER_CHATID_TR="Chat ID girin (or: -100...):"
TXT_TG_ENTER_CHATID_EN="Enter Chat ID (or: -100...):"
TXT_TG_SAVED_OK_TR="Ayarlar kaydedildi."
TXT_TG_SAVED_OK_EN="Settings saved."
TXT_TG_SAVE_FAIL_TR="Kaydetme basarisiz!"
TXT_TG_SAVE_FAIL_EN="Save failed!"
TXT_TG_TEST_SENT_TR="Test mesaji gonderildi."
TXT_TG_TEST_SENT_EN="Test message sent."
TXT_TG_NOT_CONFIGURED_TR="Telegram ayari yapilmamis."
TXT_TG_NOT_CONFIGURED_EN="Telegram not configured."
TXT_TG_RESET_OK_TR="Ayarlar sifirlandi."
TXT_TG_RESET_OK_EN="Settings reset."
TXT_TG_TEST_FAIL_CONFIG_FIRST_TR="Test gonderilemedi. Once Token/ChatID ayarlayin."
TXT_TG_TEST_FAIL_CONFIG_FIRST_EN="Test failed. Configure Token/ChatID first."
TXT_TG_CONFIG_DELETED_TR="Ayar dosyasi silindi."
TXT_TG_CONFIG_DELETED_EN="Config deleted."
TXT_TG_TEST_SAVED_MSG_TR="✅ Telegram Test: Ayarlar kaydedildi"
TXT_TG_TEST_SAVED_MSG_EN="✅ Telegram Test: Settings saved"
TXT_TG_TEST_OK_MSG_TR="✅ Telegram Test: Bildirim calisiyor"
TXT_TG_TEST_OK_MSG_EN="✅ Telegram Test: Notifications working"
# -------------------------------------------------------------------
# Health Monitor (Mod B) notifications
# -------------------------------------------------------------------
TXT_HM_TITLE_TR="Sistem Sagligi ve Izleme"
TXT_HM_TITLE_EN="System Health and Monitoring"
TXT_HM_BANNER_LABEL_TR="Saglik Mon."
TXT_HM_BANNER_LABEL_EN="Health Mon."
TXT_TGBOT_BANNER_LABEL_TR="Telegram Bot"
TXT_TGBOT_BANNER_LABEL_EN="Telegram Bot"
TXT_TGBOT_BANNER_ACTIVE_TR="AKTIF"
TXT_TGBOT_BANNER_ACTIVE_EN="ACTIVE"
TXT_TGBOT_BANNER_INACTIVE_TR="KAPALI"
TXT_TGBOT_BANNER_INACTIVE_EN="INACTIVE"
TXT_GUI_BANNER_LABEL_TR="Web Panel"
TXT_GUI_BANNER_LABEL_EN="Web Panel"
TXT_GUI_BANNER_ACTIVE_TR="AKTIF"
TXT_GUI_BANNER_ACTIVE_EN="ACTIVE"
TXT_GUI_BANNER_INACTIVE_TR="KAPALI"
TXT_GUI_BANNER_INACTIVE_EN="INACTIVE"
TXT_SCHED_BANNER_LABEL_TR="Tekrar Baslat"
TXT_SCHED_BANNER_LABEL_EN="Sched.Reboot"
TXT_HM_MENU_LINE2_TR="Disk(/opt) >= %DISK%%%  |  RAM <= %RAM% MB  |  Load (uptime)"
TXT_HM_MENU_LINE2_EN="Disk(/opt) >= %DISK%%%  |  RAM <= %RAM% MB  |  Load via uptime"
TXT_HM_MENU_LINE3_TR="Zapret2 denetimi: %WD%  |  Aralik: %INT%s"
TXT_HM_MENU_LINE3_EN="Zapret2 watchdog: %WD%  |  Interval: %INT%s"
TXT_HM_CFG_TITLE_TR="Saglik Ayarlari"
TXT_HM_CFG_TITLE_EN="Health Settings"
TXT_HM_CFG_ITEM5_TR="Zapret2 denetimi"
TXT_HM_CFG_ITEM5_EN="Zapret2 watchdog"
TXT_HM_CFG_ITEM6_TR="Guncelleme kontrolu"
TXT_HM_CFG_ITEM6_EN="Update check"
TXT_HM_CFG_ITEM7_TR="Oto guncelleme modu"
TXT_HM_CFG_ITEM7_EN="Auto update mode"
TXT_HM_CFG_ITEM8_TR="Aralik (sn)"
TXT_HM_CFG_ITEM8_EN="Interval (sec)"
TXT_HM_CFG_ITEM9_TR="Cooldown (sn)"
TXT_HM_CFG_ITEM9_EN="Cooldown (sec)"
TXT_HM_CFG_ITEM10_TR="Heartbeat (sn)"
TXT_HM_CFG_ITEM10_EN="Heartbeat (sec)"
TXT_HM_CFG_ITEM11_TR="WAN izleme"
TXT_HM_CFG_ITEM11_EN="WAN monitor"
TXT_HM_CFG_ITEM12_TR="NFQUEUE kuyruk denetimi"
TXT_HM_CFG_ITEM12_EN="NFQUEUE qlen watchdog"
TXT_HM_CFG_ITEM14_TR="Debug modu"
TXT_HM_CFG_ITEM14_EN="Debug mode"
TXT_HM_CFG_ITEM15_TR="Onerilen Ayarlari Uygula"
TXT_HM_CFG_ITEM15_EN="Apply Recommended Settings"
TXT_HM_PROMPT_WANMON_ENABLE_TR="WAN izleme aktif mi?"
TXT_HM_PROMPT_WANMON_ENABLE_EN="Enable WAN monitoring?"
TXT_HM_PROMPT_WANMON_FAIL_TH_TR="DOWN algilama esigi (adet)"
TXT_HM_PROMPT_WANMON_FAIL_TH_EN="DOWN detect threshold (count)"
TXT_HM_PROMPT_WANMON_OK_TH_TR="UP dogrulama esigi (adet)"
TXT_HM_PROMPT_WANMON_OK_TH_EN="UP confirm threshold (count)"
TXT_HM_WAN_DOWN_MSG_TR="🚫 WAN KAPALI (%IF%)"
TXT_HM_WAN_DOWN_MSG_EN="🚫 WAN DOWN (%IF%)"
TXT_HM_WAN_UP_MSG_TR="✅ WAN UP (%IF%)\nKesinti: %DUR%"
TXT_HM_WAN_UP_MSG_EN="✅ WAN UP (%IF%)\nOutage: %DUR%"
# WAN monitor - rich UP notification (Down/Up/Duration labels)
TXT_HM_WAN_UP_TITLE_TR="✅ WAN ACIK (%IF%)"
TXT_HM_WAN_UP_TITLE_EN="✅ WAN UP (%IF%)"
TXT_HM_WAN_DOWN_TIME_LABEL_TR="Kapali"
TXT_HM_WAN_DOWN_TIME_LABEL_EN="Down"
TXT_HM_WAN_UP_TIME_LABEL_TR="Acik"
TXT_HM_WAN_UP_TIME_LABEL_EN="Up"
TXT_HM_WAN_DUR_LABEL_TR="Sure"
TXT_HM_WAN_DUR_LABEL_EN="Duration"
TXT_HM_STATUS_DISK_OPT_TR="Disk(/opt)"
TXT_HM_STATUS_DISK_OPT_EN="Disk(/opt)"
TXT_HM_STATUS_TITLE_TR="Sistem Sagligi ve Izleme Durumu"
TXT_HM_STATUS_TITLE_EN="System Health and Monitoring Status"
TXT_HM_STATUS_SEC_SETTINGS_TR="[AYARLAR]"
TXT_HM_STATUS_SEC_SETTINGS_EN="[SETTINGS]"
TXT_HM_STATUS_SEC_THRESH_TR="[ESIKLER]"
TXT_HM_STATUS_SEC_THRESH_EN="[THRESHOLDS]"
TXT_HM_STATUS_SEC_ZAPRET_TR="[ZAPRET2]"
TXT_HM_STATUS_SEC_ZAPRET_EN="[ZAPRET2]"
TXT_HM_STATUS_SEC_NOW_TR="[SIMDI]"
TXT_HM_STATUS_SEC_NOW_EN="[NOW]"
TXT_HM_STATUS_ZAPRET_AR_TR="Oto Yeniden Baslat"
TXT_HM_STATUS_ZAPRET_AR_EN="Auto-Restart"
TXT_HM_STATUS_CPU_TR="CPU"
TXT_HM_STATUS_CPU_EN="CPU"
TXT_HM_STATUS_ZAPRET_TR="Zapret2"
TXT_HM_STATUS_ZAPRET_EN="Zapret2"
TXT_HM_ZAPRET_UP_SHORT_TR="acik"
TXT_HM_ZAPRET_UP_SHORT_EN="up"
TXT_HM_ZAPRET_DOWN_SHORT_TR="kapali"
TXT_HM_ZAPRET_DOWN_SHORT_EN="down"
TXT_HM_ZAPRET_NA_SHORT_TR="n/a"
TXT_HM_ZAPRET_NA_SHORT_EN="n/a"
TXT_HM_STATUS_SECTION_CFG_TR="Ayarlar"
TXT_HM_STATUS_SECTION_CFG_EN="Settings"
TXT_HM_STATUS_SECTION_NOW_TR="Anlik Durum"
TXT_HM_STATUS_SECTION_NOW_EN="Live Status"
TXT_HM_STATUS_UPDATECHECK_TR="Guncelleme kontrolu"
TXT_HM_STATUS_UPDATECHECK_EN="Update check"
TXT_HM_STATUS_AUTOUPDATE_TR="Oto guncelleme"
TXT_HM_STATUS_AUTOUPDATE_EN="Auto update"
TXT_HM_WORD_ON_TR="ACIK"
TXT_HM_WORD_ON_EN="ON"
TXT_HM_WORD_OFF_TR="KAPALI"
TXT_HM_WORD_OFF_EN="OFF"
TXT_HM_MODE0_TR="KAPALI"
TXT_HM_MODE0_EN="OFF"
TXT_HM_MODE1_TR="BILDIR"
TXT_HM_MODE1_EN="Notify"
TXT_HM_MODE2_TR="OTO KUR"
TXT_HM_MODE2_EN="Auto install"
TXT_HM_FLAG_EVERY_TR="her"
TXT_HM_FLAG_EVERY_EN="every"
TXT_HM_FLAG_MODE_TR="mod"
TXT_HM_FLAG_MODE_EN="mode"
TXT_HM_FLAG_ENABLED_TR="acik"
TXT_HM_FLAG_ENABLED_EN="en"
TXT_HM_STATUS_TR="Durum:"
TXT_HM_STATUS_EN="Status:"
TXT_HM_ENABLE_DISABLE_TR="Ac / Kapat"
TXT_HM_ENABLE_DISABLE_EN="Enable / Disable"
TXT_HM_SHOW_STATUS_TR="Durum Goster"
TXT_HM_SHOW_STATUS_EN="Show Status"
TXT_HM_SEND_TEST_TR="Test Bildirimi (Telegram)"
TXT_HM_SEND_TEST_EN="Send Test Notification (Telegram)"
TXT_HM_CONFIG_THRESHOLDS_TR="Esikleri Ayarla"
TXT_HM_CONFIG_THRESHOLDS_EN="Configure Thresholds"
TXT_HM_ENABLED_TR="Sistem Sagligi ve Izleme acildi."
TXT_HM_ENABLED_EN="Health Monitor enabled."
TXT_HM_DISABLED_TR="Sistem Sagligi ve Izleme kapatildi."
TXT_HM_DISABLED_EN="Health Monitor disabled."
TXT_HM_RESTART_TR="Yeniden Baslat"
TXT_HM_RESTART_EN="Restart"
TXT_HM_RESTARTED_TR="Sistem Sagligi ve Izleme yeniden baslatildi."
TXT_HM_RESTARTED_EN="Health Monitor restarted."
TXT_HM_TEST_MSG_TR="📌 HealthMon %TS%\n✅ Saglik Izleme testi\n🧠 CPU: %CPU%%\n📊 Yuk: %LOAD%\n🧮 RAM bos: %RAM% MB\n💾 Disk(/opt): %DISK%%"
TXT_HM_TEST_MSG_EN="📌 HealthMon %TS%\n✅ Health Monitor test\n🧠 CPU: %CPU%%\n📊 Load: %LOAD%\n🧮 RAM free: %RAM% MB\n💾 Disk(/opt): %DISK%%"
TXT_HM_CPU_WARN_MSG_TR="📌 HealthMon %TS%\n⚠️ CPU UYARI: %CPU%%\n🧠 CPU: %CPU%%\n📊 Yuk: %LOAD%\n🧮 RAM bos: %RAM% MB\n💾 Disk(/opt): %DISK%%"
TXT_HM_CPU_WARN_MSG_EN="📌 HealthMon %TS%\n⚠️ CPU WARN: %CPU%%\n🧠 CPU: %CPU%%\n📊 Load: %LOAD%\n🧮 RAM free: %RAM% MB\n💾 Disk(/opt): %DISK%%"
TXT_HM_CPU_CRIT_MSG_TR="📌 HealthMon %TS%\n🚨 CPU KRITIK: %CPU%%\n🧠 CPU: %CPU%%\n📊 Yuk: %LOAD%\n🧮 RAM bos: %RAM% MB\n💾 Disk(/opt): %DISK%%"
TXT_HM_CPU_CRIT_MSG_EN="📌 HealthMon %TS%\n🚨 CPU CRIT: %CPU%%\n🧠 CPU: %CPU%%\n📊 Load: %LOAD%\n🧮 RAM free: %RAM% MB\n💾 Disk(/opt): %DISK%%"
TXT_HM_DISK_WARN_MSG_TR="📌 HealthMon %TS%\n⚠️ Disk dolu: /opt %DISK%%%\n🧠 CPU: %CPU%%\n📊 Yuk: %LOAD%\n🧮 RAM bos: %RAM% MB"
TXT_HM_DISK_WARN_MSG_EN="📌 HealthMon %TS%\n⚠️ Disk high: /opt %DISK%%%\n🧠 CPU: %CPU%%\n📊 Load: %LOAD%\n🧮 RAM free: %RAM% MB"
TXT_HM_RAM_WARN_MSG_TR="📌 HealthMon %TS%\n⚠️ RAM dusuk: %RAM% MB\n🧠 CPU: %CPU%%\n📊 Yuk: %LOAD%\n💾 Disk(/opt): %DISK%%"
TXT_HM_RAM_WARN_MSG_EN="📌 HealthMon %TS%\n⚠️ Low RAM: %RAM% MB\n🧠 CPU: %CPU%%\n📊 Load: %LOAD%\n💾 Disk(/opt): %DISK%%"
TXT_HM_ZAPRET_DOWN_MSG_TR="📌 HealthMon %TS%\n🚨 Zapret2 durmus olabilir!\n🧠 CPU: %CPU%%\n📊 Yuk: %LOAD%\n🧮 RAM bos: %RAM% MB\n💾 Disk(/opt): %DISK%%\n📡 DPI: %DPI%"
TXT_HM_ZAPRET_DOWN_MSG_EN="📌 HealthMon %TS%\n🚨 Zapret2 may be down!\n🧠 CPU: %CPU%%\n📊 Load: %LOAD%\n🧮 RAM free: %RAM% MB\n💾 Disk(/opt): %DISK%%\n📡 DPI: %DPI%"
TXT_HM_ZAPRET_FW_MISSING_MSG_TR="📌 HealthMon %TS%\n⚠️ NFQUEUE kurallari eksikti, yenilendi!\n🧠 CPU: %CPU%%\n📊 Yuk: %LOAD%\n🧮 RAM bos: %RAM% MB\n💾 Disk(/opt): %DISK%%\n📡 DPI: %DPI%"
TXT_HM_ZAPRET_FW_MISSING_MSG_EN="📌 HealthMon %TS%\n⚠️ NFQUEUE rules were missing, renewed!\n🧠 CPU: %CPU%%\n📊 Load: %LOAD%\n🧮 RAM free: %RAM% MB\n💾 Disk(/opt): %DISK%%\n📡 DPI: %DPI%"
TXT_HM_ZAPRET_UP_MSG_TR="📌 HealthMon %TS%\n✅ Zapret2 tekrar calisiyor.\n🧠 CPU: %CPU%%\n📊 Yuk: %LOAD%\n🧮 RAM bos: %RAM% MB\n💾 Disk(/opt): %DISK%%\n📡 DPI: %DPI%"
TXT_HM_ZAPRET_UP_MSG_EN="📌 HealthMon %TS%\n✅ Zapret2 is running again.\n🧠 CPU: %CPU%%\n📊 Load: %LOAD%\n🧮 RAM free: %RAM% MB\n💾 Disk(/opt): %DISK%%\n📡 DPI: %DPI%"
TXT_HM_DISK_HEALTH_DOWN_MSG_TR="📌 HealthMon %TS%\n⚠️ Disk bakimi gerekiyor: /opt\n💾 Durum: %REASON%\n🧠 CPU: %CPU%%\n📊 Yuk: %LOAD%\n🧮 RAM bos: %RAM% MB"
TXT_HM_DISK_HEALTH_DOWN_MSG_EN="📌 HealthMon %TS%\n⚠️ Disk maintenance required: /opt\n💾 Status: %REASON%\n🧠 CPU: %CPU%%\n📊 Load: %LOAD%\n🧮 RAM free: %RAM% MB"
TXT_HM_DISK_HEALTH_UP_MSG_TR="📌 HealthMon %TS%\n✅ Disk sagligi normale dondu: /opt\n🧠 CPU: %CPU%%\n📊 Yuk: %LOAD%\n🧮 RAM bos: %RAM% MB"
TXT_HM_DISK_HEALTH_UP_MSG_EN="📌 HealthMon %TS%\n✅ Disk health restored: /opt\n🧠 CPU: %CPU%%\n📊 Load: %LOAD%\n🧮 RAM free: %RAM% MB"
TXT_HM_DISK_HEALTH_RO_TR="Salt okunur (read-only)"
TXT_HM_DISK_HEALTH_RO_EN="Read-only mount"
TXT_HM_DISK_HEALTH_IO_TR="Kritik I/O hatasi"
TXT_HM_DISK_HEALTH_IO_EN="Critical I/O error"
TXT_HM_DISK_HEALTH_JOURNAL_TR="Journal hatasi (e2fsck onerilir)"
TXT_HM_DISK_HEALTH_JOURNAL_EN="Journal error (e2fsck recommended)"
TXT_HM_DISK_HEALTH_USBDISCON_TR="USB baglantisi koptu"
TXT_HM_DISK_HEALTH_USBDISCON_EN="USB disconnected"
TXT_HM_DISK_HEALTH_USBPROTO_TR="USB protokol hatasi"
TXT_HM_DISK_HEALTH_USBPROTO_EN="USB protocol error"
TXT_HM_STATUS_RUNNING_TR="Calisiyor:"
TXT_HM_STATUS_RUNNING_EN="Running:"
TXT_HM_RUN_ON_TR="AKTIF"
TXT_HM_RUN_ON_EN="ON"
TXT_HM_RUN_OFF_TR="KAPALI"
TXT_HM_RUN_OFF_EN="OFF"
TXT_HM_BANNER_WARN_TR="Otomatik guncelleme ve watchdog devre disi. Aktif etmek icin Menu 16."
TXT_HM_BANNER_WARN_EN="Auto-update and watchdog disabled. Enable via Menu 16."
TXT_ISP_DNS_WARN_TR="ISP DNS: %DNS% olarak tespit edildi. Zapret2 bypass engellenebilir!"
TXT_ISP_DNS_WARN_EN="ISP DNS: %DNS% detected. Zapret2 bypass may be blocked!"
TXT_HM_ENABLE_LABEL_TR="etkin"
TXT_HM_ENABLE_LABEL_EN="enable"
TXT_HM_STATUS_INTERVAL_TR="Aralik"
TXT_HM_STATUS_INTERVAL_EN="Interval"
TXT_HM_STATUS_CPU_WARN_TR="CPU UYARI"
TXT_HM_STATUS_CPU_WARN_EN="CPU WARN"
TXT_HM_STATUS_CPU_CRIT_TR="CPU KRITIK"
TXT_HM_STATUS_CPU_CRIT_EN="CPU CRIT"
TXT_HM_STATUS_DISK_WARN_TR="Disk(/opt) UYARI"
TXT_HM_STATUS_DISK_WARN_EN="Disk(/opt) WARN"
TXT_HM_STATUS_RAM_WARN_TR="RAM UYARI"
TXT_HM_STATUS_RAM_WARN_EN="RAM WARN"
TXT_HM_STATUS_ZAPRET_WD_TR="Zapret2 denetimi"
TXT_HM_STATUS_ZAPRET_WD_EN="Zapret2 watchdog"
TXT_HM_STATUS_ZAPRET_CD_TR="Zapret2 bekleme"
TXT_HM_STATUS_ZAPRET_CD_EN="Zapret2 cooldown"
TXT_HM_STATUS_COOLDOWN_TR="Bekleme"
TXT_HM_STATUS_COOLDOWN_EN="Cooldown"
TXT_HM_STATUS_NOW_TR="Simdi ->"
TXT_HM_STATUS_NOW_EN="Now ->"
TXT_HM_STATUS_LOAD_TR="Yuk"
TXT_HM_STATUS_LOAD_EN="Load"
TXT_HM_STATUS_RAM_FREE_TR="RAM bos"
TXT_HM_STATUS_RAM_FREE_EN="RAM free"
TXT_TG_ERR_TOKEN_FORMAT_TR="Token formati hatali (:) yok)."
TXT_TG_ERR_TOKEN_FORMAT_EN="Invalid token format (missing :)."
TXT_TG_ERR_CHATID_NUM_TR="ChatID sayi olmali."
TXT_TG_ERR_CHATID_NUM_EN="ChatID must be numeric."
TXT_TG_SAVED_AND_TEST_OK_TR="Kaydedildi ve test mesaji gonderildi."
TXT_TG_SAVED_AND_TEST_OK_EN="Saved and test message sent."
TXT_TG_SAVED_BUT_TEST_FAIL_TR="Kaydedildi ama test gonderilemedi. Token/ChatID veya interneti kontrol edin."
TXT_TG_SAVED_BUT_TEST_FAIL_EN="Saved but test failed. Check token/chatid or internet."
TXT_HM_TEST_SENT_TR="Test bildirimi gonderildi."
TXT_HM_TEST_SENT_EN="Test notification sent."
TXT_HM_NEED_TG_TR="Telegram ayarlanamamis olabilir. Once menu 15 ile ayarlayin."
TXT_HM_NEED_TG_EN="Telegram may be unconfigured. Configure via menu 15."
TXT_HM_PROMPT_CPU_WARN_TR="CPU WARN esigi (%) [or: 70]:"
TXT_HM_PROMPT_CPU_WARN_EN="CPU WARN threshold (%) [e.g. 70]:"
TXT_HM_PROMPT_CPU_WARN_DUR_TR="CPU WARN sure (sn) [or: 180]:"
TXT_HM_PROMPT_CPU_WARN_DUR_EN="CPU WARN duration (sec) [e.g. 180]:"
TXT_HM_PROMPT_CPU_CRIT_TR="CPU CRIT esigi (%) [or: 90]:"
TXT_HM_PROMPT_CPU_CRIT_EN="CPU CRIT threshold (%) [e.g. 90]:"
TXT_HM_PROMPT_CPU_CRIT_DUR_TR="CPU CRIT sure (sn) [or: 60]:"
TXT_HM_PROMPT_CPU_CRIT_DUR_EN="CPU CRIT duration (sec) [e.g. 60]:"
TXT_HM_PROMPT_DISK_WARN_TR="Disk esigi (/opt, %) [or: 90]:"
TXT_HM_PROMPT_DISK_WARN_EN="Disk threshold (/opt, %) [e.g. 90]:"
TXT_HM_PROMPT_RAM_WARN_TR="RAM esigi (MB) [or: 40]:"
TXT_HM_PROMPT_RAM_WARN_EN="RAM threshold (MB) [e.g. 40]:"
TXT_HM_PROMPT_ZAPRET_WD_TR="Zapret2 denetimi (1=acik,0=kapali) [or: 1]:"
TXT_HM_PROMPT_ZAPRET_WD_EN="Zapret2 watchdog (1=on,0=off) [e.g. 1]:"
TXT_HM_PROMPT_ZAPRET_COOLDOWN_TR="Zapret2 cooldown (sn) [or: 120]:"
TXT_HM_PROMPT_ZAPRET_COOLDOWN_EN="Zapret2 cooldown (sec) [e.g. 120]:"
TXT_HM_PROMPT_ZAPRET_AUTORESTART_TR="Zapret2 otomatik yeniden baslatma? (0/1) [or: 0]:"
TXT_HM_PROMPT_ZAPRET_AUTORESTART_EN="Zapret2 auto-restart? (0/1) [e.g. 0]:"
TXT_HM_PROMPT_INTERVAL_TR="Kontrol araligi (sn) [or: 30]:"
TXT_HM_PROMPT_INTERVAL_EN="Check interval (sec) [e.g. 30]:"
TXT_HM_PROMPT_UPDATECHECK_ENABLE_TR="Guncelleme kontrolu (1=acik,0=kapali) [or: 1]:"
TXT_HM_PROMPT_UPDATECHECK_ENABLE_EN="Update check (1=on,0=off) [e.g. 1]:"
TXT_HM_PROMPT_UPDATECHECK_SEC_TR="Update check araligi (sn) [or: 21600]:"
TXT_HM_PROMPT_UPDATECHECK_SEC_EN="Update check interval (sec) [e.g. 21600]:"
TXT_UPD_ZKM_NEW_TR="[Guncelleme]
📦 Paket  : KZM2
🔖 Mevcut : %CUR%
🆕 Yeni   : %NEW%
🔗 Link   : %URL%
Simdi kur? (menu 10)"
TXT_UPD_ZKM_NEW_EN="[Update]
📦 Package : KZM2
🔖 Current : %CUR%
🆕 Latest  : %NEW%
🔗 Link    : %URL%
Install now? (menu 10)"
TXT_UPD_ZAPRET_NEW_TR="[Guncelleme]
Zapret2 guncellemesi icin Ana Menu > 6 secenegi kullanin
📦 Paket  : Zapret2
🔖 Kurulu : %CUR%
🆕 Yeni   : %NEW%
🔗 Link   : %URL%"
TXT_UPD_ZAPRET_NEW_EN="[Update]
Use Main Menu > Option 6 to update Zapret2
📦 Package  : Zapret2
🔖 Installed: %CUR%
🆕 Latest   : %NEW%
🔗 Link     : %URL%"
TXT_UPD_ZAPRET_ROLLED_TR="[Uyari] Zapret2 geri cekilmis surum
Ana Menu > 6 ile GitHub surumunu yeniden yukleyin
📦 Paket  : Zapret2
⚠️ Kurulu : %CUR% (geri cekilmis)
✅ Stabil : %NEW%"
TXT_UPD_ZAPRET_ROLLED_EN="[Warning] Zapret2 pulled release
Use Main Menu > 6 to reinstall from GitHub
📦 Package  : Zapret2
⚠️ Installed: %CUR% (pulled)
✅ Stable  : %NEW%"
TXT_UPD_ZKM_AUTO_OK_TR="[OtoGuncelleme]\nKZM2 otomatik kurulum basarili.\nBetigi yeniden calistirin.\n\n📦 Paket  : KZM2\n🔖 Mevcut : %CUR%\n🆕 Yeni   : %NEW%\n🔗 Link   : %URL%"
TXT_UPD_ZKM_AUTO_OK_EN="[AutoUpdate]\nKZM2 auto install OK.\nPlease re-run the script.\n\n📦 Package  : KZM2\n🔖 Current  : %CUR%\n🆕 Latest   : %NEW%\n🔗 Link     : %URL%"
TXT_UPD_ZKM_UP_TO_DATE_TR="[Guncelleme]
📦 Paket : KZM2
🔄 Durum : Guncel ✅
🔖 Surum : %CUR%

[Saglik]
💾 Disk (/opt) : %DISK_HEALTH%"
TXT_UPD_ZKM_UP_TO_DATE_EN="[Update]
📦 Package : KZM2
🔄 Status  : Up to date ✅
🔖 Version : %CUR%

[Health]
💾 Disk (/opt) : %DISK_HEALTH%"
TXT_UPD_ZKM_AUTO_FAIL_TR="[OtoGuncelleme]\n❌ KZM2 otomatik kurulum BASARISIZ.\n⚠️ Lutfen elle guncelleyin (menu 10).\n\n📦 Paket  : KZM2\n🔖 Mevcut : %CUR%\n🆕 Yeni   : %NEW%\n🔗 Link   : %URL%"
TXT_UPD_ZKM_AUTO_FAIL_EN="[AutoUpdate]\n❌ KZM2 auto install FAILED.\n⚠️ Please update manually (menu 10).\n\n📦 Package : KZM2\n🔖 Current : %CUR%\n🆕 Latest  : %NEW%\n🔗 Link    : %URL%"
TXT_HM_PROMPT_AUTOUPDATE_MODE_TR="Otomatik guncelleme modu (0=KAPALI,1=BILDIR,2=OTO KUR) [or: 2]:"
TXT_HM_PROMPT_AUTOUPDATE_MODE_EN="Auto update mode (0=OFF,1=Notify,2=Auto install) [e.g. 2]:"
TXT_HM_AUTOUPDATE_MODE_HINT_TR="0=KAPALI,1=BILDIR,2=OTO KUR"
TXT_HM_AUTOUPDATE_MODE_HINT_EN="0=OFF,1=Notify,2=Auto install"
TXT_HM_AUTOUPDATE_WARN_TITLE_TR="UYARI:"
TXT_HM_AUTOUPDATE_WARN_TITLE_EN="WARNING:"
TXT_HM_AUTOUPDATE_WARN_L1_TR="Auto install modu betigi otomatik gunceller."
TXT_HM_AUTOUPDATE_WARN_L1_EN="Auto install will update the script automatically."
TXT_HM_AUTOUPDATE_WARN_L2_TR="Ileri seviye kullanicilar icin onerilir."
TXT_HM_AUTOUPDATE_WARN_L2_EN="Recommended for advanced users."
TXT_HM_AUTOUPDATE_WARN_L3_TR="Devam? (e/h): "
TXT_HM_AUTOUPDATE_WARN_L3_EN="Continue? (y/n): "
TXT_HM_AUTOUPDATE_SET_MSG_TR="Otomatik guncelleme modu ayarlandi: %MODE%"
TXT_HM_AUTOUPDATE_SET_MSG_EN="Auto update mode set: %MODE%"
TXT_HM_SYSLOG_CRIT_MSG_TR="📌 Keenetic Sistem Log Uyarisi\n🔐 %CNT% yeni kritik olay:\n%LOG%\n\n📎 Not: Bu mesajin KZM2 veya Zapret2 ile ilgisi yoktur. Keenetic sistem log'undan gelen onemli bir olay oldugu icin bilgi amacli yollanmistir."
TXT_HM_SYSLOG_CRIT_MSG_EN="📌 Keenetic System Log Alert\n🔐 %CNT% new critical event:\n%LOG%\n\n📎 Note: This message is not related to KZM2 or Zapret2. It is sent for informational purposes as an important event detected in the Keenetic system log."
TXT_HM_SYSLOG_IKE_MSG_TR="📌 Keenetic Sistem Log Uyarisi\n🛡️ IKE baglanti denemesi: %CNT% yeni girisim\n\n📎 Not: Bu mesajin KZM2 veya Zapret2 ile ilgisi yoktur. Keenetic sistem log'undan gelen onemli bir olay oldugu icin bilgi amacli yollanmistir."
TXT_HM_SYSLOG_IKE_MSG_EN="📌 Keenetic System Log Alert\n🛡️ IKE connection attempt: %CNT% new\n\n📎 Note: This message is not related to KZM2 or Zapret2. It is sent for informational purposes as an important event detected in the Keenetic system log."
TXT_HM_SYSLOG_TLS_MSG_TR="⚠️ Zapret2 TLS Mudahalesi Uyarisi\n🔒 Son %MIN% dakikada %CNT% adet TLS baglanti hatasi tespit edildi.\n\nBu hata Zapret2 bypass'inin TLS baglantilarini bozdugunun isareti olabilir. ISS'inizde DPI olmayabilir veya TTL degeriniz cok yuksek olabilir.\n\nOneri: Blockcheck2 calistirin (Menu B) veya Zapret2'yi gecici olarak durdurun (Menu 4) ve baglantinizi test edin."
TXT_HM_SYSLOG_TLS_MSG_EN="⚠️ Zapret2 TLS Interference Warning\n🔒 %CNT% TLS connection errors detected in the last %MIN% minutes.\n\nThis may indicate that Zapret2 bypass is interfering with TLS connections. Your ISP may not have DPI or your TTL value may be too high.\n\nSuggestion: Run Blockcheck2 (Menu B) or temporarily stop Zapret2 (Menu 4) and test your connection."
TXT_HM_NFQWS_ALERT_MSG_TR="⚠️ nfqws2 Kuyruk Uyarisi\n📦 queue=%QL% drops=%DR%\n\nNFQUEUE kuyrugundan paket dusuyor veya kuyruk dolmaya basladi. Bu ag yavaslamasi veya DPI bypass sorununa isaret edebilir.\n\nDetay icin Menu 16 - 4 uzerinden Debug modunu acin."
TXT_HM_NFQWS_ALERT_MSG_EN="⚠️ nfqws2 Queue Alert\n📦 queue=%QL% drops=%DR%\n\nPackets are being dropped or the NFQUEUE is starting to fill up. This may indicate network slowdown or DPI bypass issues.\n\nFor details enable Debug mode via Menu 16 - 4."
TXT_HM_NFQWS_ALERT_OK_MSG_TR="✅ nfqws2 Kuyruk Normal\n📦 queue=0 drops=0\n\nNFQUEUE kuyrugu normale dondu."
TXT_HM_NFQWS_ALERT_OK_MSG_EN="✅ nfqws2 Queue Normal\n📦 queue=0 drops=0\n\nNFQUEUE queue returned to normal."
TXT_HM_NFQWS_ALERT_ITEM_TR="nfqws2 Kuyruk Alarmi"
TXT_HM_NFQWS_ALERT_ITEM_EN="nfqws2 Queue Alert"
TXT_HM_PROMPT_COOLDOWN_TR="Bildirim soguma (sn) [or: 600]:"
TXT_HM_PROMPT_COOLDOWN_EN="Notification cooldown (sec) [e.g. 600]:"
# Health check menu
TXT_HEALTH_TITLE_TR="Saglik Kontrolu"
TXT_HEALTH_TITLE_EN="Health Check"
TXT_HEALTH_OVERALL_TR="Genel Durum"
TXT_HEALTH_OVERALL_EN="Overall Status"
TXT_HEALTH_SCORE_TR="Saglik Skoru (Health Score)"
TXT_HEALTH_SCORE_EN="Health Score"
TXT_HEALTH_RATING_EXCELLENT_TR="Mukemmel"
TXT_HEALTH_RATING_EXCELLENT_EN="Excellent"
TXT_HEALTH_RATING_GREAT_TR="Cok iyi"
TXT_HEALTH_RATING_GREAT_EN="Great"
TXT_HEALTH_RATING_GOOD_TR="Iyi"
TXT_HEALTH_RATING_GOOD_EN="Good"
TXT_HEALTH_RATING_OK_TR="Orta"
TXT_HEALTH_RATING_OK_EN="OK"
TXT_HEALTH_RATING_BAD_TR="Zayif"
TXT_HEALTH_RATING_BAD_EN="Poor"
TXT_HEALTH_SECTION_SUMMARY_TR="Durum Ozeti"
TXT_HEALTH_SECTION_SUMMARY_EN="Status Summary"
TXT_HEALTH_SECTION_NETDNS_TR="Ag & DNS"
TXT_HEALTH_SECTION_NETDNS_EN="Network & DNS"
TXT_HEALTH_SECTION_SYSTEM_TR="Sistem"
TXT_HEALTH_SECTION_SYSTEM_EN="System"
TXT_HEALTH_SECTION_SERVICES_TR="Servisler"
TXT_HEALTH_SECTION_SERVICES_EN="Services"
TXT_HEALTH_WAN_STATUS_TR="WAN durumu"
TXT_HEALTH_WAN_STATUS_EN="WAN status"
TXT_HEALTH_WAN_IPV4_TR="WAN IPv4 adresi"
TXT_HEALTH_WAN_IPV4_EN="WAN IPv4 address"
TXT_HEALTH_WAN_IPV6_TR="WAN IPv6 adresi"
TXT_HEALTH_WAN_IPV6_EN="WAN IPv6 address"
TXT_HEALTH_DNS_MODE_TR="DNS Modu"
TXT_HEALTH_DNS_MODE_EN="DNS Mode"
TXT_HEALTH_DNS_SEC_TR="DNS Guvenlik Seviyesi"
TXT_HEALTH_DNS_SEC_EN="DNS Security Level"
TXT_HEALTH_DNS_PROVIDERS_TR="DNS Saglayicilar"
TXT_HEALTH_DNS_PROVIDERS_EN="DNS Providers"
TXT_DNS_MODE_DOH_TR="DoH"
TXT_DNS_MODE_DOH_EN="DoH"
TXT_DNS_MODE_DOT_TR="DoT"
TXT_DNS_MODE_DOT_EN="DoT"
TXT_DNS_MODE_PLAIN_TR="Plain"
TXT_DNS_MODE_PLAIN_EN="Plain"
TXT_DNS_MODE_MIXED_TR="DoH+DoT"
TXT_DNS_MODE_MIXED_EN="DoH+DoT"
TXT_DNS_SEC_HIGH_TR="YUKSEK"
TXT_DNS_SEC_HIGH_EN="HIGH"
TXT_DNS_SEC_LOW_TR="DUSUK"
TXT_DNS_SEC_LOW_EN="LOW"
TXT_TG_DOWN_LABEL_TR="Kapali"
TXT_TG_DOWN_LABEL_EN="Down"
TXT_TG_UP_LABEL_TR="Acik"
TXT_TG_UP_LABEL_EN="Up"
TXT_TG_DURATION_LABEL_TR="Sure"
TXT_TG_DURATION_LABEL_EN="Duration"
# TR/EN Dictionary (Telegram Bot)
TXT_TGBOT_MENU_TITLE_TR="KZM2 Ana Menu"
TXT_TGBOT_MENU_TITLE_EN="KZM2 Main Menu"
TXT_TGBOT_BTN_STATUS_TR="Durum"
TXT_TGBOT_BTN_STATUS_EN="Status"
TXT_TGBOT_BTN_ZAPRET_TR="Zapret2"
TXT_TGBOT_BTN_ZAPRET_EN="Zapret2"
TXT_TGBOT_BTN_SYSTEM_TR="Sistem"
TXT_TGBOT_BTN_SYSTEM_EN="System"
TXT_TGBOT_BTN_LOGS_TR="Loglar"
TXT_TGBOT_BTN_LOGS_EN="Logs"
TXT_TGBOT_LOG_MENU_TITLE_TR="Log Secenekleri"
TXT_TGBOT_LOG_MENU_TITLE_EN="Log Options"
TXT_TGBOT_BTN_KZMLOG_TR="HealthMon Log"
TXT_TGBOT_BTN_KZMLOG_EN="HealthMon Log"
TXT_TGBOT_BTN_SYSLOG_TR="Sistem Log"
TXT_TGBOT_BTN_SYSLOG_EN="System Log"
TXT_TGBOT_BTN_TGBOTLOG_TR="TG Bot Log"
TXT_TGBOT_BTN_TGBOTLOG_EN="TG Bot Log"
TXT_TGBOT_BTN_DEBUGLOG_TR="Debug Log"
TXT_TGBOT_BTN_DEBUGLOG_EN="Debug Log"
TXT_TGBOT_BTN_BACK_TR="Geri"
TXT_TGBOT_BTN_BACK_EN="Back"
TXT_TGBOT_BTN_START_TR="Baslat"
TXT_TGBOT_BTN_START_EN="Start"
TXT_TGBOT_BTN_STOP_TR="Durdur"
TXT_TGBOT_BTN_STOP_EN="Stop"
TXT_TGBOT_BTN_RESTART_TR="Yeniden Baslat"
TXT_TGBOT_BTN_RESTART_EN="Restart"
TXT_TGBOT_BTN_REBOOT_TR="Yeniden Baslat (Router)"
TXT_TGBOT_BTN_REBOOT_EN="Reboot Router"
TXT_TGBOT_BTN_REBOOT_CONFIRM_TR="Onayla - Yeniden Baslat"
TXT_TGBOT_BTN_REBOOT_CONFIRM_EN="Confirm Reboot"
TXT_TGBOT_BTN_CANCEL_TR="Iptal"
TXT_TGBOT_BTN_CANCEL_EN="Cancel"
TXT_TGBOT_BTN_KZM_UPDATE_TR="KZM2 Guncelle"
TXT_TGBOT_BTN_KZM_UPDATE_EN="Update KZM2"
TXT_TGBOT_BTN_KZM_BACKUP_TR="KZM2 Yedekle"
TXT_TGBOT_BTN_KZM_BACKUP_EN="Backup KZM2"
TXT_TGBOT_KZM_BACKUP_OK_TR="✅ Yedek Telegram'a gonderildi."
TXT_TGBOT_KZM_BACKUP_OK_EN="✅ Backup sent to Telegram."
TXT_TGBOT_KZM_BACKUP_FAIL_TR="❌ Yedek gonderilemedi."
TXT_TGBOT_KZM_BACKUP_FAIL_EN="❌ Failed to send backup."
TXT_TGBOT_BTN_ZAP_UPDATE_TR="Zapret2 Guncelle"
TXT_TGBOT_BTN_ZAP_UPDATE_EN="Update Zapret2"
TXT_TGBOT_STATUS_RUNNING_TR="Calisiyor"
TXT_TGBOT_STATUS_RUNNING_EN="Running"
TXT_TGBOT_STATUS_STOPPED_TR="Durduruldu"
TXT_TGBOT_STATUS_STOPPED_EN="Stopped"
TXT_TGBOT_STATUS_UNKNOWN_TR="Bilinmiyor"
TXT_TGBOT_STATUS_UNKNOWN_EN="Unknown"
TXT_TGBOT_REBOOT_SENT_TR="Yeniden baslatma komutu gonderildi."
TXT_TGBOT_REBOOT_SENT_EN="Reboot command sent."
TXT_TGBOT_ZAPRET_STARTED_TR="Zapret2 baslatildi."
TXT_TGBOT_ZAPRET_STARTED_EN="Zapret2 started."
TXT_TGBOT_ZAPRET_STOPPED_TR="Zapret2 durduruldu."
TXT_TGBOT_ZAPRET_STOPPED_EN="Zapret2 stopped."
TXT_TGBOT_ZAPRET_RESTARTED_TR="Zapret2 yeniden baslatildi."
TXT_TGBOT_ZAPRET_RESTARTED_EN="Zapret2 restarted."
TXT_TGBOT_UPDATE_STARTED_TR="Guncelleme baslatildi, lutfen bekleyin..."
TXT_TGBOT_UPDATE_STARTED_EN="Update started, please wait..."
TXT_TGBOT_UPDATE_DONE_TR="Guncelleme tamamlandi."
TXT_TGBOT_UPDATE_DONE_EN="Update completed."
TXT_TGBOT_UPDATE_FAIL_TR="Guncelleme basarisiz."
TXT_TGBOT_UPDATE_FAIL_EN="Update failed."
TXT_TGBOT_ALREADY_UPTODATE_TR="KZM2 zaten guncel."
TXT_TGBOT_ALREADY_UPTODATE_EN="KZM2 is already up to date."
TXT_TGBOT_ZAP_ALREADY_UPTODATE_TR="Zapret2 zaten guncel."
TXT_TGBOT_ZAP_ALREADY_UPTODATE_EN="Zapret2 is already up to date."
TXT_TGBOT_ZAP_NEWER_TR="UYARI: Kurulu surum GitHub'dakinden yeni (Surum geri cekilmis olabilir)."
TXT_TGBOT_ZAP_NEWER_EN="WARNING: Installed version is newer than GitHub (version may have been rolled back)."
TXT_TGBOT_NO_LOGS_TR="Log bulunamadi."
TXT_TGBOT_NO_LOGS_EN="No logs found."
TXT_TGBOT_MENU_ZAPRET_TITLE_TR="Zapret2 Yonetimi"
TXT_TGBOT_MENU_ZAPRET_TITLE_EN="Zapret2 Management"
TXT_TGBOT_MENU_KZM_TITLE_TR="KZM2 Yonetimi"
TXT_TGBOT_MENU_KZM_TITLE_EN="KZM2 Management"
TXT_TGBOT_BTN_KZM_TR="KZM2"
TXT_TGBOT_BTN_KZM_EN="KZM2"
TXT_TGBOT_MENU_SISTEM_TITLE_TR="Sistem"
TXT_TGBOT_MENU_SISTEM_TITLE_EN="System"
TXT_TGBOT_BTN_NET_DEVICES_TR="Ag Cihazlari"
TXT_TGBOT_BTN_NET_DEVICES_EN="Network Devices"
TXT_TGBOT_BTN_WIFI_TR="Wifi Yonetim"
TXT_TGBOT_BTN_WIFI_EN="Wifi Management"
TXT_TGBOT_NET_DEVICES_TITLE_TR="Bagli Cihazlar"
TXT_TGBOT_NET_DEVICES_TITLE_EN="Connected Devices"
TXT_TGBOT_NET_NO_DEVICES_TR="Bagli cihaz bulunamadi."
TXT_TGBOT_NET_NO_DEVICES_EN="No connected devices found."
TXT_TGBOT_CLIENT_ACCESS_DENY_TR="Erisimi Engelle"
TXT_TGBOT_CLIENT_ACCESS_DENY_EN="Block Access"
TXT_TGBOT_CLIENT_ACCESS_PERMIT_TR="Erisime Izin Ver"
TXT_TGBOT_CLIENT_ACCESS_PERMIT_EN="Allow Access"
TXT_TGBOT_CLIENT_RENAME_TR="Ismi Degistir"
TXT_TGBOT_CLIENT_RENAME_EN="Rename Device"
TXT_TGBOT_CLIENT_RENAME_PROMPT_TR="Cihaz icin yeni isim girin. Iptal icin /iptal yaz."
TXT_TGBOT_CLIENT_RENAME_PROMPT_EN="Enter new name for the device. Type /iptal to cancel."
TXT_TGBOT_CLIENT_RENAME_DONE_TR="Isim guncellendi."
TXT_TGBOT_CLIENT_RENAME_DONE_EN="Name updated."
TXT_TGBOT_CLIENT_RENAME_CANCEL_TR="Isim degistirme iptal edildi."
TXT_TGBOT_CLIENT_RENAME_CANCEL_EN="Rename cancelled."
TXT_TGBOT_CLIENT_STATUS_ACTIVE_TR="Bagli"
TXT_TGBOT_CLIENT_STATUS_ACTIVE_EN="Connected"
TXT_TGBOT_CLIENT_STATUS_INACTIVE_TR="Bagli degil"
TXT_TGBOT_CLIENT_STATUS_INACTIVE_EN="Not connected"
TXT_TGBOT_CLIENT_ACCESS_LABEL_TR="Erisim"
TXT_TGBOT_CLIENT_ACCESS_LABEL_EN="Access"
TXT_TGBOT_CLIENT_ACCESS_OK_TR="Acik"
TXT_TGBOT_CLIENT_ACCESS_OK_EN="Allowed"
TXT_TGBOT_CLIENT_ACCESS_BLOCKED_TR="Engelli"
TXT_TGBOT_CLIENT_ACCESS_BLOCKED_EN="Blocked"
TXT_TGBOT_WIFI_TITLE_TR="Wifi Durumu"
TXT_TGBOT_WIFI_TITLE_EN="Wifi Status"
TXT_TGBOT_WIFI_NO_IF_TR="Wifi arayuzu bulunamadi."
TXT_TGBOT_WIFI_NO_IF_EN="No wifi interface found."
TXT_TGBOT_SISTEM_HEADER_ISIM_TR="Isim"
TXT_TGBOT_SISTEM_HEADER_ISIM_EN="Name"
TXT_TGBOT_SISTEM_HEADER_MODEL_TR="Model"
TXT_TGBOT_SISTEM_HEADER_MODEL_EN="Model"
TXT_TGBOT_DEVICE_KEENDNS_LABEL_TR="KeenDNS"
TXT_TGBOT_DEVICE_KEENDNS_LABEL_EN="KeenDNS"
TXT_TGBOT_DEVICE_RELEASE_LABEL_TR="Release"
TXT_TGBOT_DEVICE_RELEASE_LABEL_EN="Release"
TXT_TGBOT_DEVICE_TRAFFIC_LABEL_TR="Trafik (WAN)"
TXT_TGBOT_DEVICE_TRAFFIC_LABEL_EN="Traffic (WAN)"
TXT_TGBOT_BTN_SELFTEST_TR="Selftest"
TXT_TGBOT_BTN_SELFTEST_EN="Selftest"
TXT_TGBOT_SELFTEST_PASS_TR="PASS=0 - Tum testler basarili."
TXT_TGBOT_SELFTEST_PASS_EN="PASS=0 - All tests passed."
TXT_TGBOT_SELFTEST_FAIL_TR="Selftest hata buldu."
TXT_TGBOT_SELFTEST_FAIL_EN="Selftest found errors."
TXT_TGBOT_SELFTEST_WARN_TR="Selftest uyari buldu. Detaylar icin log dosyasini inceleyin."
TXT_TGBOT_SELFTEST_WARN_EN="Selftest found warnings. Check the log file for details."
TXT_TGBOT_MENU_LOGS_TITLE_TR="Son Loglar"
TXT_TGBOT_MENU_LOGS_TITLE_EN="Recent Logs"
TXT_TGBOT_BOT_ENABLE_TR="Bot aktif mi"
TXT_TGBOT_BOT_ENABLE_EN="Bot enabled"
TXT_TGBOT_POLL_SEC_TR="Polling araligi (saniye)"
TXT_TGBOT_POLL_SEC_EN="Polling interval (seconds)"
TXT_TGBOT_MENU_BOT_TITLE_TR="Telegram Bot Yonetimi"
TXT_TGBOT_MENU_BOT_TITLE_EN="Telegram Bot Management"
TXT_TGBOT_BOT_STATUS_ACTIVE_TR="AKTIF - 2 yonlu haberlesme calisiyor"
TXT_TGBOT_BOT_STATUS_ACTIVE_EN="ACTIVE - 2-way communication running"
TXT_TGBOT_BOT_STATUS_INACTIVE_TR="Bot KAPALI"
TXT_TGBOT_BOT_STATUS_INACTIVE_EN="Bot DISABLED"
TXT_TGBOT_ENABLE_BOT_TR="Botu Etkinlestir / Ayarla"
TXT_TGBOT_ENABLE_BOT_EN="Enable / Configure Bot"
TXT_TGBOT_DISABLE_BOT_TR="Botu Devre Disi Birak"
TXT_TGBOT_DISABLE_BOT_EN="Disable Bot"
TXT_TGBOT_RESTART_BOT_TR="Botu Yeniden Baslat"
TXT_TGBOT_RESTART_BOT_EN="Restart Bot"
TXT_TGBOT_ENTER_POLL_TR="Polling araligi saniye cinsinden girin (varsayilan 5): "
TXT_TGBOT_ENTER_POLL_EN="Enter polling interval in seconds (default 5): "
TXT_TGBOT_BOT_STARTED_TR="Bot baslatildi."
TXT_TGBOT_BOT_STARTED_EN="Bot started."
TXT_TGBOT_BOT_STOPPED_TR="Bot durduruldu."
TXT_TGBOT_BOT_STOPPED_EN="Bot stopped."
TXT_TGBOT_BOT_NOT_CONFIG_TR="Bot yapilandirilmamis. Once Telegram token ve chat ID girin."
TXT_TGBOT_BOT_NOT_CONFIG_EN="Bot not configured. Enter Telegram token and chat ID first."
TXT_TGBOT_BTN_WAN_RESET_TR="WAN Sureli Kapatma"
TXT_TGBOT_BTN_WAN_RESET_EN="Timed WAN Shutdown"
TXT_TGBOT_BTN_PINGCHECK_OFF_TR="Ping Kontrolu Kapat"
TXT_TGBOT_BTN_PINGCHECK_OFF_EN="Disable Ping Check"
TXT_TGBOT_BTN_PINGCHECK_ON_TR="Ping Kontrolu Ac"
TXT_TGBOT_BTN_PINGCHECK_ON_EN="Enable Ping Check"
TXT_TGBOT_PINGCHECK_OFF_OK_TR="❌ Ping Kontrolu kapatildi."
TXT_TGBOT_PINGCHECK_OFF_OK_EN="❌ Ping Check disabled."
TXT_TGBOT_PINGCHECK_ON_OK_TR="✅ Ping Kontrolu acildi."
TXT_TGBOT_PINGCHECK_ON_OK_EN="✅ Ping Check enabled."
TXT_TGBOT_PINGCHECK_ALREADY_OFF_TR="❌ Ping Kontrolu zaten kapali."
TXT_TGBOT_PINGCHECK_ALREADY_OFF_EN="❌ Ping Check is already disabled."
TXT_TGBOT_PINGCHECK_FAIL_TR="⚠️ Ping Kontrolu degistirilemedi."
TXT_TGBOT_PINGCHECK_FAIL_EN="⚠️ Failed to change Ping Check."
TXT_TGBOT_BTN_CONFIRM_TR="Onayla"
TXT_TGBOT_BTN_CONFIRM_EN="Confirm"
TXT_TGBOT_WAN_RESET_SELECT_TR="WAN kac dakika kapatilsin?"
TXT_TGBOT_WAN_RESET_SELECT_EN="How long to disable WAN?"
TXT_TGBOT_WAN_RESET_CONFIRM_TR="WAN %MIN% dk kapatilacak. Onayliyor musun?"
TXT_TGBOT_WAN_RESET_CONFIRM_EN="WAN will be off for %MIN% min. Confirm?"
TXT_TGBOT_WAN_RESET_STARTED_TR="WAN kapatildi. %MIN% dk sonra yeniden baglanacak."
TXT_TGBOT_WAN_RESET_STARTED_EN="WAN disabled. Will reconnect in %MIN% min."
TXT_TGBOT_WAN_NO_IF_TR="WAN arayuzu bulunamadi."
TXT_TGBOT_WAN_NO_IF_EN="WAN interface not found."
TXT_TGBOT_ROUTER_ID_LABEL_TR="Router Kimlik"
TXT_TGBOT_ROUTER_ID_LABEL_EN="Router ID"
TXT_HEALTH_DNS_LOCAL_TR="DNS (Yerel cozucu 127.0.0.1)"
TXT_HEALTH_DNS_LOCAL_EN="DNS (Local resolver 127.0.0.1)"
TXT_HEALTH_SCRIPT_PATH_TR="Betik Konumu (Dogru yerde mi?)"
TXT_HEALTH_SCRIPT_PATH_EN="Script location (Correct path?)"
TXT_HEALTH_DNS_PUBLIC_TR="DNS (8.8.8.8)"
TXT_HEALTH_DNS_PUBLIC_EN="DNS (8.8.8.8)"
TXT_HEALTH_TIME_TR="Saat / NTP"
TXT_HEALTH_TIME_EN="Time / NTP"
TXT_HEALTH_GITHUB_TR="GitHub erisimi (api.github.com)"
TXT_HEALTH_GITHUB_EN="GitHub access (api.github.com)"
TXT_HEALTH_OPKG_TR="OPKG durumu"
TXT_HEALTH_OPKG_EN="OPKG status"
TXT_HEALTH_DISK_TR="Disk doluluk (/opt)"
TXT_HEALTH_DISK_EN="Disk usage (/opt)"
TXT_HEALTH_ZAPRET_TR="Zapret2 servis durumu"
TXT_HEALTH_ZAPRET_EN="Zapret2 service status"
TXT_HEALTH_SHA256_KZM_TR="KZM2 dosya butunlugu (SHA256)"
TXT_HEALTH_SHA256_KZM_EN="KZM2 file integrity (SHA256)"
TXT_HEALTH_SHA256_ZAP_TR="Zapret2 surum durumu"
TXT_HEALTH_SHA256_ZAP_EN="Zapret2 version status"
TXT_HEALTH_SHA256_OK_TR="Dogrulandi"
TXT_HEALTH_SHA256_OK_EN="Verified"
TXT_HEALTH_SHA256_FAIL_TR="Eslesmiyor / Dogrulanmamis"
TXT_HEALTH_SHA256_FAIL_EN="Mismatch / Not verified"
TXT_HEALTH_SHA256_UNKNOWN_TR="Henuz kontrol edilmedi (Menu 10)"
TXT_HEALTH_SHA256_UNKNOWN_EN="Not checked yet (Menu 10)"
TXT_HEALTH_SHA256_ZAP_UNKNOWN_TR="Henuz kontrol edilmedi (Menu 6)"
TXT_HEALTH_SHA256_ZAP_UNKNOWN_EN="Not checked yet (Menu 6)"
TXT_HEALTH_DNS_MATCH_TR="DNS tutarliligi"
TXT_HEALTH_DNS_MATCH_EN="DNS consistency"
TXT_HEALTH_DNS_MATCH_NOTE_TR="Farkli IP'ler normal olabilir"
TXT_HEALTH_DNS_MATCH_NOTE_EN="Different IPs can be normal"
TXT_HEALTH_ROUTE_TR="Varsayilan rota (default gateway)"
TXT_HEALTH_ROUTE_EN="Default route (gateway)"
TXT_HEALTH_PING_TR="Internet erisimi (ping 1.1.1.1)"
TXT_HEALTH_PING_EN="Internet connect (ping 1.1.1.1)"
TXT_HEALTH_RAM_TR="RAM durumu (MemAvailable)"
TXT_HEALTH_RAM_EN="RAM status (MemAvailable)"
TXT_HEALTH_RAM_DETAIL_TR="RAM (kullanilan/bos/toplam)"
TXT_HEALTH_RAM_DETAIL_EN="RAM (used/free/total)"
TXT_HEALTH_RAM_BUFFER_TR="RAM Buffer/Cache"
TXT_HEALTH_RAM_BUFFER_EN="RAM Buffer/Cache"
TXT_HEALTH_SWAP_TR="Swap (kullanilan/toplam)"
TXT_HEALTH_SWAP_EN="Swap (used/total)"
TXT_HEALTH_TEMP_TR="SoC Sicakligi"
TXT_HEALTH_TEMP_EN="SoC Temperature"
TXT_HEALTH_DISK_TMP_TR="Disk doluluk (/tmp)"
TXT_HEALTH_DISK_TMP_EN="Disk usage (/tmp)"
TXT_HEALTH_DISK_HEALTH_TR="Disk sagligi (/opt)"
TXT_HEALTH_DISK_HEALTH_EN="Disk health (/opt)"
TXT_HEALTH_DISK_RO_TR="Salt okunur! Disk veya dosya sistemi hatali olabilir."
TXT_HEALTH_DISK_RO_EN="Read-only! Disk or filesystem may be damaged."
TXT_HEALTH_DISK_IO_ERR_TR="Kritik I/O hatasi tespit edildi (dmesg)"
TXT_HEALTH_DISK_IO_ERR_EN="Critical I/O error detected (dmesg)"
TXT_HEALTH_DISK_OK_TR="Saglikli"
TXT_HEALTH_DISK_OK_EN="Healthy"
TXT_HEALTH_DISK_JOURNAL_TR="Journal hatasi - e2fsck onerilir"
TXT_HEALTH_DISK_JOURNAL_EN="Journal error - e2fsck recommended"
TXT_HEALTH_DISK_USBDISCON_TR="USB baglantisi koptu (yeniden baglandi)"
TXT_HEALTH_DISK_USBDISCON_EN="USB disconnected (reconnected)"
TXT_HEALTH_DISK_USBPROTO_TR="USB protokol hatasi tespit edildi"
TXT_HEALTH_DISK_USBPROTO_EN="USB protocol error detected"
TXT_HEALTH_LAN_IP_TR="LAN IP"
TXT_HEALTH_LAN_IP_EN="LAN IP"
TXT_HEALTH_ENTWARE_TR="Entware (/opt)"
TXT_HEALTH_ENTWARE_EN="Entware (/opt)"
TXT_HEALTH_CURL_TR="curl"
TXT_HEALTH_CURL_EN="curl"
TXT_HEALTH_LIGHTTPD_TR="Web Panel (lighttpd)"
TXT_HEALTH_LIGHTTPD_EN="Web Panel (lighttpd)"
TXT_HEALTH_HEALTHMON_TR="HealthMon daemon"
TXT_HEALTH_HEALTHMON_EN="HealthMon daemon"
TXT_HEALTH_TGBOT_TR="Telegram Bot"
TXT_HEALTH_TGBOT_EN="Telegram Bot"
TXT_HEALTH_LOAD_TR="Sistem yuk (load avg)"
TXT_HEALTH_LOAD_EN="System load (load avg)"
TXT_MENU14_TITLE_TR="Ag Tanilama ve Sistem Kontrolu"
TXT_MENU14_TITLE_EN="Network Diagnostics & System Check"
TXT_MENU14_OPT1_TR="1. Kontrol Calistir"
TXT_MENU14_OPT1_EN="1. Run Diagnostics"
TXT_MENU14_OPT2_TR="2. OPKG Listesini Yenile"
TXT_MENU14_OPT2_EN="2. Refresh OPKG Package List"
TXT_MENU14_OPT3_TR="3. DoT/DoH DNS Yapilandir (Guvenli DNS)"
TXT_MENU14_OPT3_EN="3. Configure DoT/DoH DNS (Secure DNS)"
TXT_MENU14_OPT4_TR="4. Bilesen Kontrolu (OPKG/iptables/ipset/vs)"
TXT_MENU14_OPT4_EN="4. Component Check (OPKG/iptables/ipset/etc)"
TXT_MENU14_DNS_TITLE_TR="Guvenli DNS Yapilandirmasi (DoT/DoH)"
TXT_MENU14_DNS_TITLE_EN="Secure DNS Configuration (DoT/DoH)"
TXT_MENU14_DNS_CONFIRM_TR="Bu islem eksik olan ve en cok tercih edilen DoT/DoH DNS sunucularini ekleyecek. Devam? (e/h):"
TXT_MENU14_DNS_CONFIRM_EN="This will add missing and most preferred DoT/DoH DNS servers. Continue? (y/n):"
TXT_MENU14_DNS_VPN_WARN_TR="VPN kullaniyorsaniz DNS sizintisini onlemek icin VPN arayuzunuze ozel DNS atayiniz."
TXT_MENU14_DNS_VPN_WARN_EN="If you use VPN, assign a dedicated DNS to your VPN interface to prevent DNS leaks."
TXT_MENU14_DNS_FILTER_WARN_TR="UYARI: Internet Filtresi aktif. Bazi DNS sunuculari eklenemeyebilir."
TXT_MENU14_DNS_FILTER_WARN_EN="WARNING: Internet Filter is active. Some DNS servers may not be added."
TXT_MENU14_DNS_ALREADY_TR="Tum DNS sunuculari zaten yapilandirilmis."
TXT_MENU14_DNS_ALREADY_EN="All DNS servers are already configured."
TXT_MENU14_DNS_ADDED_TR="Eklendi"
TXT_MENU14_DNS_ADDED_EN="Added"
TXT_MENU14_DNS_EXISTS_TR="Zaten mevcut, atlaniyor"
TXT_MENU14_DNS_EXISTS_EN="Already exists, skipping"
TXT_MENU14_DNS_SAVED_TR="DNS yapilandirmasi kaydedildi."
TXT_MENU14_DNS_SAVED_EN="DNS configuration saved."
TXT_MENU14_DNS_REBIND_TR="Rebind korumasi"
TXT_MENU14_DNS_REBIND_EN="Rebind protection"
TXT_DNS_MGMT_TITLE_TR="DNS Yonetimi (DoT/DoH)"
TXT_DNS_MGMT_TITLE_EN="DNS Management (DoT/DoH)"
TXT_DNS_MGMT_CURRENT_TR="Mevcut Sunucular"
TXT_DNS_MGMT_CURRENT_EN="Current Servers"
TXT_DNS_GRP_FILTRESIZ_TR="Filtresiz"
TXT_DNS_GRP_FILTRESIZ_EN="Unfiltered"
TXT_DNS_GRP_GIZLILIK_TR="Gizlilik"
TXT_DNS_GRP_GIZLILIK_EN="Privacy"
TXT_DNS_GRP_REKLAM_TR="Reklam"
TXT_DNS_GRP_REKLAM_EN="Ad Block"
TXT_DNS_GRP_AILE_TR="Aile"
TXT_DNS_GRP_AILE_EN="Family"
TXT_DNS_MGMT_NONE_TR="Hic guvenli DNS sunucusu yapilandirilmamis."
TXT_DNS_MGMT_NONE_EN="No secure DNS servers configured."
TXT_DNS_MGMT_OPT1_TR="Hazir Paket Ekle"
TXT_DNS_MGMT_OPT1_EN="Add Preset Package"
TXT_DNS_MGMT_OPT2_TR="Manuel Ekle"
TXT_DNS_MGMT_OPT2_EN="Add Manually"
TXT_DNS_MGMT_OPT3_TR="Sunucu Sil"
TXT_DNS_MGMT_OPT3_EN="Delete Server"
TXT_DNS_MGMT_PRESET_TITLE_TR="Hazir DNS Paketi Ekle"
TXT_DNS_MGMT_PRESET_TITLE_EN="Add Preset DNS Package"
TXT_DNS_MGMT_PRESET_EXISTS_TR="Zaten mevcut"
TXT_DNS_MGMT_PRESET_EXISTS_EN="Already exists"
TXT_DNS_MGMT_ADDED_TR="Eklendi"
TXT_DNS_MGMT_ADDED_EN="Added"
TXT_DNS_MGMT_DEL_TITLE_TR="Sunucu Sil"
TXT_DNS_MGMT_DEL_TITLE_EN="Delete Server"
TXT_DNS_MGMT_DEL_NONE_TR="Silinecek bilinen DNS sunucusu bulunamadi."
TXT_DNS_MGMT_DEL_NONE_EN="No known DNS servers found to delete."
TXT_DNS_MGMT_DELALL_WARN_TR="TUM guvenli DNS sunuculari silinecek. Emin misiniz? (e/h):"
TXT_DNS_MGMT_DELALL_WARN_EN="ALL secure DNS servers will be deleted. Are you sure? (y/n):"
TXT_DNS_MGMT_DELALL_DONE_TR="Tum DNS sunuculari silindi ve ayarlar kaydedildi."
TXT_DNS_MGMT_DELALL_DONE_EN="All DNS servers deleted and settings saved."
TXT_DNS_MGMT_SAVED_TR="Ayarlar kaydedildi."
TXT_DNS_MGMT_SAVED_EN="Settings saved."
TXT_DNS_MGMT_DELETED_TR="Silindi"
TXT_DNS_MGMT_DELETED_EN="Deleted"
TXT_DNS_MGMT_OPT4_TR="Tumunu Temizle"
TXT_DNS_MGMT_OPT4_EN="Delete All"
TXT_DNS_MGMT_OPT5_TR="Rebind Koruma"
TXT_DNS_MGMT_OPT5_EN="Rebind Protection"
TXT_DNS_MGMT_MANUAL_TITLE_TR="Manuel DNS Sunucusu Ekle"
TXT_DNS_MGMT_MANUAL_TITLE_EN="Add DNS Server Manually"
TXT_DNS_MGMT_MANUAL_IP_TR="IP adresi girin:"
TXT_DNS_MGMT_MANUAL_IP_EN="Enter IP address:"
TXT_DNS_MGMT_MANUAL_SNI_TR="SNI/hostname girin (bos birakabilirsiniz):"
TXT_DNS_MGMT_MANUAL_SNI_EN="Enter SNI/hostname (can be left empty):"
TXT_DNS_MGMT_MANUAL_URL_TR="DoH URL girin (ornek: https://dns.example.com/dns-query):"
TXT_DNS_MGMT_MANUAL_URL_EN="Enter DoH URL (example: https://dns.example.com/dns-query):"
TXT_DNS_MGMT_MANUAL_INVALID_TR="Gecersiz giris, iptal edildi."
TXT_DNS_MGMT_MANUAL_INVALID_EN="Invalid input, cancelled."
TXT_DNS_MGMT_REBIND_ON_TR="ACIK"
TXT_DNS_MGMT_REBIND_ON_EN="ON"
TXT_DNS_MGMT_REBIND_OFF_TR="KAPALI"
TXT_DNS_MGMT_REBIND_OFF_EN="OFF"
TXT_DNS_MGMT_REBIND_ENABLED_TR="Rebind koruma aktif edildi."
TXT_DNS_MGMT_REBIND_ENABLED_EN="Rebind protection enabled."
TXT_DNS_MGMT_REBIND_DISABLED_TR="Rebind koruma devre disi birakildi."
TXT_DNS_MGMT_REBIND_DISABLED_EN="Rebind protection disabled."
TXT_OPKG_UPDATING_TR="OPKG paket listesi yenileniyor..."
TXT_OPKG_UPDATING_EN="Refreshing OPKG package list..."
TXT_OPKG_UPDATED_TR="OPKG paket listesi yenilendi."
TXT_OPKG_UPDATED_EN="OPKG package list refreshed."
TXT_OPKG_UPDATE_FAIL_TR="OPKG listesi yenilenemedi."
TXT_OPKG_UPDATE_FAIL_EN="Failed to refresh OPKG list."
TXT_OPKG_ALL_CURRENT_TR="Tum paketler guncel. Yukseltilecek paket yok."
TXT_OPKG_ALL_CURRENT_EN="All packages up to date. Nothing to upgrade."
TXT_OPKG_UPGRADABLE_TR="yukseltilecek paket bulundu:"
TXT_OPKG_UPGRADABLE_EN="upgradable package(s) found:"
TXT_OPKG_UPGRADE_WARN_TR="UYARI: opkg upgrade tum paketleri gunceller."
TXT_OPKG_UPGRADE_WARN_EN="WARNING: opkg upgrade will update ALL packages."
TXT_OPKG_UPGRADE_WARN2_TR="Keenetic'te bagimlilik cakismasi veya sistem bozulmasi yasanabilir."
TXT_OPKG_UPGRADE_WARN2_EN="Dependency conflicts or system breakage may occur on Keenetic."
TXT_OPKG_UPGRADE_CONFIRM_TR="Devam etmek ister misiniz? (e/h): "
TXT_OPKG_UPGRADE_CONFIRM_EN="Do you want to continue? (y/n): "
TXT_OPKG_UPGRADING_TR="Paketler yukseltiliyor, lutfen bekleyin..."
TXT_OPKG_UPGRADING_EN="Upgrading packages, please wait..."
TXT_OPKG_UPGRADED_TR="opkg upgrade tamamlandi."
TXT_OPKG_UPGRADED_EN="opkg upgrade completed."
TXT_OPKG_UPGRADE_FAIL_TR="opkg upgrade basarisiz oldu."
TXT_OPKG_UPGRADE_FAIL_EN="opkg upgrade failed."
TXT_ROLLBACK_TITLE_TR="Betik: Yedekten Geri Don (Rollback)"
TXT_ROLLBACK_TITLE_EN="Script: Roll Back from Backup"
# -----------------------------
# Common UI
# -----------------------------
TXT_CHOICE_TR="Secim:"
TXT_CHOICE_EN="Choice:"
TXT_INVALID_CHOICE_TR="Gecersiz secim!"
TXT_INVALID_CHOICE_EN="Invalid choice!"
TXT_CANCELLED_TR="Iptal edildi."
TXT_CANCELLED_EN="Cancelled."
TXT_ERROR_TR="Hata"
TXT_ERROR_EN="Error"
TXT_RESTORE_RESTART_WARN_TR="Uyari: Yeniden baslatma gerekebilir."
TXT_RESTORE_RESTART_WARN_EN="Warning: A restart may be required."
TXT_TMPDIR_CREATE_FAIL_TR="Gecici dizin olusturulamadi!"
TXT_TMPDIR_CREATE_FAIL_EN="Failed to create temporary directory!"
# -----------------------------
# Rollback / Local backups
# -----------------------------
TXT_ROLLBACK_NO_LOCAL_BACKUP_TR="Yerel yedek bulunamadi."
TXT_ROLLBACK_NO_LOCAL_BACKUP_EN="No local backup found."
TXT_ROLLBACK_CLEAN_LOCAL_BACKUPS_TR="Yedekleri Temizle"
TXT_ROLLBACK_CLEAN_LOCAL_BACKUPS_EN="Clean Backups"
TXT_ROLLBACK_CLEAN_DONE_TR="Temizlendi: %s yedek silindi."
TXT_ROLLBACK_CLEAN_DONE_EN="Cleaned: %s backup(s) deleted."
TXT_ROLLBACK_CLEAN_NONE_TR="Temizlenecek yerel yedek bulunamadi."
TXT_ROLLBACK_CLEAN_NONE_EN="No local backups to clean."
# -----------------------------
# Blockcheck reports
# -----------------------------
TXT_BLOCKCHECK_CLEAN_DONE_TR="Temizlendi: %s test sonucu silindi."
TXT_BLOCKCHECK_CLEAN_DONE_EN="Cleaned: %s test result(s) deleted."
TXT_BLOCKCHECK_CLEAN_NONE_TR="Temizlenecek test sonucu bulunamadi."
TXT_BLOCKCHECK_CLEAN_NONE_EN="No test results to clean."
TXT_BACK_TR="Geri"
TXT_BACK_EN="Back"
TXT_ROLLBACK_NO_BACKUP_TR="Yedek bulunamadi: /opt/lib/opkg/keenetic_zapret2_manager.sh.bak_*"
TXT_ROLLBACK_NO_BACKUP_EN="No backups found: /opt/lib/opkg/keenetic_zapret2_manager.sh.bak_*"
TXT_ROLLBACK_SELECT_TR="Geri donmek istediginiz yedegi secin:"
TXT_ROLLBACK_SELECT_EN="Select the backup you want to restore:"
TXT_ROLLBACK_RESTORED_TR="Geri yukleme tamamlandi. Lutfen betigi yeniden calistirin."
TXT_ROLLBACK_RESTORED_EN="Rollback completed. Please re-run the script."
TXT_ROLLBACK_CANCELLED_TR="Islem iptal edildi."
TXT_ROLLBACK_CANCELLED_EN="Cancelled."
TXT_ROLLBACK_GH_LIST_TR="GitHub'dan surum sec (Son 10)"
TXT_ROLLBACK_GH_LIST_EN="Pick version from GitHub (last 10)"
TXT_ROLLBACK_GH_TAG_TR="Surum etiketi yaz (Orn: v26.1.24.3)"
TXT_ROLLBACK_GH_TAG_EN="Enter a release tag (e.g. v26.1.24.3)"
TXT_ROLLBACK_GH_LOADING_TR="GitHub surum listesi aliniyor..."
TXT_ROLLBACK_GH_LOADING_EN="Fetching GitHub release list..."
TXT_ROLLBACK_LOCAL_MENU_TR="Yerel Depolama (Yedekler)"
TXT_ROLLBACK_LOCAL_MENU_EN="Local Storage (Backups)"
TXT_ROLLBACK_CLEAN_TR="Yedekleri Temizle"
TXT_ROLLBACK_CLEAN_EN="Clean Backups"
TXT_ROLLBACK_CLEAN_NONE_TR="Temizlenecek yedek yok."
TXT_ROLLBACK_CLEAN_NONE_EN="No backups to clean."
TXT_ROLLBACK_CLEAN_DONE_TR="Yedek dosyalari temizlendi."
TXT_ROLLBACK_CLEAN_DONE_EN="Backup files cleaned."
TXT_ROLLBACK_MAIN_PICK_TR="Secim: "
TXT_ROLLBACK_MAIN_PICK_EN="Choice: "
TXT_ROLLBACK_GH_NONE_TR="GitHub'dan uygun release bulunamadi."
TXT_ROLLBACK_GH_NONE_EN="No suitable releases found on GitHub."
TXT_ROLLBACK_GH_SELECT_TR="Kurmak istediginiz surumu secin"
TXT_ROLLBACK_GH_SELECT_EN="Select the version to install"
TXT_ROLLBACK_GH_TAGPROMPT_TR="Surum etiketini girin (orn: v26.1.24.3):"
TXT_ROLLBACK_GH_TAGPROMPT_EN="Enter release tag (e.g. v26.1.24.3):"
TXT_ROLLBACK_GH_DOWNLOADING_TR="Secilen surum indiriliyor..."
TXT_ROLLBACK_GH_DOWNLOADING_EN="Downloading selected version..."
TXT_ROLLBACK_GH_DONE_TR="Kurulum tamamlandi. Lutfen betigi yeniden calistirin."
TXT_ROLLBACK_GH_DONE_EN="Install completed. Please re-run the script."
TXT_BACKUP_MENU_TITLE_TR="Zapret2 Yedekleme / Geri Yukleme"
TXT_BACKUP_MENU_TITLE_EN="Zapret2 Backup / Restore"
TXT_BACKUP_BASE_PATH_TR="Yedek konumu:"
TXT_BACKUP_BASE_PATH_EN="Backup location:"
TXT_ZAPRET_SETTINGS_BACKUP_DIR_TR="Yedek konumu:"
TXT_ZAPRET_SETTINGS_BACKUP_DIR_EN="Backup location:"
TXT_YES_TR="Evet"
TXT_YES_EN="Yes"
TXT_NO_TR="Hayir"
TXT_NO_EN="No"
TXT_ZAPRET_SETTINGS_CLEAN_MENU_TR="Yedekleri Temizle"
TXT_ZAPRET_SETTINGS_CLEAN_MENU_EN="Clean Backups"
# --- Backup/Restore (Zapret2 Settings) ---
TXT_ZAPRET_SETTINGS_RESTORE_TITLE_TR="Zapret2 Ayarlari Geri Yukleme"
TXT_ZAPRET_SETTINGS_RESTORE_TITLE_EN="Restore Zapret2 Settings"
TXT_SELECT_BACKUP_TO_RESTORE_TR="Geri yuklemek icin yedegi secin:"
TXT_SELECT_BACKUP_TO_RESTORE_EN="Select a backup to restore:"
TXT_ZAPRET_RESTORE_SUBMENU_TITLE_TR="Zapret2 Yedekleme / Geri Yukleme"
TXT_ZAPRET_RESTORE_SUBMENU_TITLE_EN="Zapret2 Backup / Restore"
TXT_RESTORE_SCOPE_FULL_TR="Tam Yedegi Geri Yukle (Hepsi)"
TXT_RESTORE_SCOPE_FULL_EN="Restore Full Backup (All)"
TXT_RESTORE_SCOPE_DPI_TR="Sadece DPI Profili / Ayarlari Geri Yukle"
TXT_RESTORE_SCOPE_DPI_EN="Restore DPI Profile/Settings Only"
TXT_RESTORE_SCOPE_HOSTLIST_TR="Sadece Hostlist / Autohostlist Dosyalarini Geri Yukle"
TXT_RESTORE_SCOPE_HOSTLIST_EN="Restore Hostlist/Autohostlist Files Only"
TXT_RESTORE_SCOPE_IPSET_TR="Sadece IPSET Listelerini Geri Yukle"
TXT_RESTORE_SCOPE_IPSET_EN="Restore IPSET Sets Only"
TXT_RESTORE_SCOPE_NFQWS_TR="Sadece Zapret2 Config (nfqws) Geri Yukle"
TXT_RESTORE_SCOPE_NFQWS_EN="Restore Zapret2 Config (nfqws) Only"
TXT_RESTORE_SCOPE_KZM_TR="KZM2 Ayarlarini Geri Yukle (HealthMon + Telegram)"
TXT_RESTORE_SCOPE_KZM_EN="Restore KZM2 Settings (HealthMon + Telegram)"
TXT_BACKUP_NO_BACKUPS_FOUND_TR="Yedek bulunamadi."
TXT_BACKUP_NO_BACKUPS_FOUND_EN="No backups found."
TXT_BACKUP_SUB_BACKUP_TR="1. IPSET Yedekle"
TXT_BACKUP_SUB_BACKUP_EN="1. IPSET Backup"
TXT_BACKUP_SUB_RESTORE_TR="2. IPSET Geri Yukle"
TXT_BACKUP_SUB_RESTORE_EN="2. IPSET Restore"
TXT_BACKUP_SUB_SHOW_TR="3. IPSET Yedekleri Goster"
TXT_BACKUP_SUB_SHOW_EN="3. Show IPSET Backups"
TXT_BACKUP_SUB_CFG_BACKUP_TR="4. Zapret2 / KZM2 Ayarlarini Yedekle"
TXT_BACKUP_SUB_CFG_BACKUP_EN="4. Backup Zapret2 / KZM2 Settings"
TXT_BACKUP_SUB_CFG_RESTORE_TR="5. Zapret2 / KZM2 Ayarlarini Geri Yukle"
TXT_BACKUP_SUB_CFG_RESTORE_EN="5. Restore Zapret2 / KZM2 Settings"
TXT_BACKUP_SUB_CFG_SHOW_TR="6. Zapret2 Ayar Yedeklerini Goster"
TXT_BACKUP_SUB_CFG_SHOW_EN="6. Show Settings Backups"
TXT_BACKUP_SUB_TG_SEND_TR="7. Yedegi Telegram'a Gonder"
TXT_BACKUP_SUB_TG_SEND_EN="7. Send Backup via Telegram"
TXT_BACKUP_CFG_NO_FILES_TR="Yedeklenecek Zapret2/KZM2 ayar dosyasi bulunamadi."
TXT_BACKUP_CFG_NO_FILES_EN="No Zapret2/KZM2 settings files found to backup."
TXT_BACKUP_CFG_BACKED_UP_TR="Zapret2/KZM2 ayarlari yedeklendi: %s"
TXT_BACKUP_CFG_BACKED_UP_EN="Zapret2/KZM2 settings backed up: %s"
TXT_BACKUP_CFG_NO_BACKUPS_TR="Zapret2/KZM2 ayar yedegi bulunamadi."
TXT_BACKUP_CFG_NO_BACKUPS_EN="No Zapret2/KZM2 settings backup found."
TXT_BACKUP_CFG_RESTORED_TR="Zapret2 ayarlari geri yuklendi: %s"
TXT_BACKUP_CFG_RESTORED_EN="Zapret2 settings restored: %s"
TXT_BACKUP_RESTORE_SUBMENU_TITLE_TR="Zapret2 Ayarlarini Geri Yukle"
TXT_BACKUP_RESTORE_SUBMENU_TITLE_EN="Restore Zapret2 Settings"
TXT_BACKUP_RESTORE_FULL_TR="Tam Yedegi Geri Yukle (Hepsi)"
TXT_BACKUP_RESTORE_FULL_EN="Restore Full Backup"
TXT_BACKUP_RESTORE_DPI_TR="Sadece DPI Profili / Ayarlari Geri Yukle"
TXT_BACKUP_RESTORE_DPI_EN="Restore DPI Settings Only"
TXT_BACKUP_RESTORE_HOSTLIST_TR="Sadece Hostlist / Autohostlist Dosyalarini Geri Yukle"
TXT_BACKUP_RESTORE_HOSTLIST_EN="Restore Hostlist / Autohostlist Only"
TXT_BACKUP_RESTORE_IPSET_TR="Sadece IPSET Listelerini Geri Yukle"
TXT_BACKUP_RESTORE_IPSET_EN="Restore IPSET Settings Only"
TXT_BACKUP_RESTORE_NFQWS_TR="Sadece Zapret2 Config (nfqws) Geri Yukle"
TXT_BACKUP_RESTORE_NFQWS_EN="Restore Zapret2 Config (nfqws) Only"
TXT_BACKUP_RESTORE_EXTRACTING_TR="Yedek aciliyor..."
TXT_BACKUP_RESTORE_EXTRACTING_EN="Extracting backup..."
TXT_BACKUP_RESTORE_FAILED_TR="Geri yukleme basarisiz!"
TXT_BACKUP_RESTORE_FAILED_EN="Restore failed!"
TXT_BACKUP_RESTORE_DONE_TR="Geri yukleme tamamlandi."
TXT_BACKUP_RESTORE_DONE_EN="Restore completed."
TXT_BACKUP_RESTORE_NOTHING_TR="Geri yuklenecek dosya bulunamadi."
TXT_BACKUP_RESTORE_NOTHING_EN="Nothing to restore."
TXT_BACKUP_RESTORE_STATS_TR="Geri yuklenen: %s | Bulunamayan/Hata: %s"
TXT_BACKUP_RESTORE_STATS_EN="Restored: %s | Missing/Error: %s"
TXT_BACKUP_RESTORE_SCOPE_TR="Geri yukleme kapsamini secin:"
TXT_BACKUP_RESTORE_SCOPE_EN="Select restore scope:"
TXT_BACKUP_SCOPE_HOSTLISTS_TR="1. Sadece host listeleri (hostlist/autohostlist)"
TXT_BACKUP_SCOPE_HOSTLISTS_EN="1. Host lists only (hostlist/autohostlist)"
TXT_BACKUP_SCOPE_CONFIG_TR="2. Sadece ayarlar (config)"
TXT_BACKUP_SCOPE_CONFIG_EN="2. Settings only (config)"
TXT_BACKUP_SCOPE_FULL_TR="3. Tam geri yukleme (ayarlar + listeler)"
TXT_BACKUP_SCOPE_FULL_EN="3. Full restore (settings + lists)"
TXT_BACKUP_SCOPE_CANCEL_TR="0. Iptal"
TXT_BACKUP_SCOPE_CANCEL_EN="0. Cancel"
TXT_BACKUP_SUB_BACK_TR="0. Geri"
TXT_BACKUP_SUB_BACK_EN="0. Back"
TXT_BACKUP_SUB_BACK_LIST_TR="0. Geri"
TXT_BACKUP_SUB_BACK_LIST_EN="0. Back"
TXT_BACKUP_NO_SRC_TR="HATA: /opt/zapret2/ipset/ altinda yedeklenecek .txt dosyasi bulunamadi."
TXT_BACKUP_NO_SRC_EN="ERROR: No .txt files found under /opt/zapret2/ipset/ to backup."
TXT_BACKUP_DONE_TR="Yedekleme tamamlandi."
TXT_BACKUP_DONE_EN="Backup completed."
TXT_RESTORE_DONE_TR="Geri yukleme tamamlandi."
TXT_RESTORE_DONE_EN="Restore completed."
TXT_RESTORE_RESTARTING_TR="Zapret2 yeniden baslatiliyor..."
TXT_RESTORE_RESTARTING_EN="Restarting Zapret2..."
TXT_RESTORE_RESTART_OK_TR="Zapret2 yeniden baslatildi."
TXT_RESTORE_RESTART_OK_EN="Zapret2 restarted."
TXT_RESTORE_RESTART_FAIL_TR="UYARI: Zapret2 yeniden baslatilamadi."
TXT_RESTORE_RESTART_FAIL_EN="WARNING: Zapret2 could not be restarted."
TXT_BACKUP_NO_BACKUP_TR="HATA: Yedek bulunamadi."
TXT_BACKUP_NO_BACKUP_EN="ERROR: No backups found."
TXT_BACKUP_TG_NO_CONFIG_TR="Telegram yapilandirilmamis. Once Menu 15'ten ayarlarin."
TXT_BACKUP_TG_NO_CONFIG_EN="Telegram not configured. Set it up via Menu 15 first."
TXT_BACKUP_TG_SENDING_TR="Yedek Telegram'a gonderiliyor..."
TXT_BACKUP_TG_SENDING_EN="Sending backup to Telegram..."
TXT_BACKUP_TG_OK_TR="Yedek basariyla gonderildi."
TXT_BACKUP_TG_OK_EN="Backup sent successfully."
TXT_BACKUP_TG_FAIL_TR="HATA: Gonderim basarisiz oldu."
TXT_BACKUP_TG_FAIL_EN="ERROR: Failed to send backup."
TXT_BACKUP_TG_NO_FILE_TR="Gonderilecek yedek dosyasi bulunamadi. Once 4. secenekle yedek alin."
TXT_BACKUP_TG_NO_FILE_EN="No backup file found to send. Create a backup first via option 4."
TXT_SELECT_FILE_TR="Dosya secin"
TXT_SELECT_FILE_EN="Select a file"
TXT_SELECT_ACTION_TR="Seciminizi yapin"
TXT_SELECT_ACTION_EN="Make your selection"
# --- Menu strings (TR/EN) ---
TXT_BLOCKCHECK_TEST_MENU_TR="Blockcheck Test Menusu"
TXT_BLOCKCHECK_TEST_MENU_EN="Blockcheck Test Menu"
TXT_BACKUP_BASE_PATH_TR="Yedek konumu:"
TXT_BACKUP_BASE_PATH_EN="Backup location:"
TXT_ZAPRET_SETTINGS_BACKUP_DIR_TR="Yedek konumu:"
TXT_ZAPRET_SETTINGS_BACKUP_DIR_EN="Backup location:"
TXT_YES_TR="Evet"
TXT_YES_EN="Yes"
TXT_NO_TR="Hayir"
TXT_NO_EN="No"
TXT_ROLLBACK_NO_LOCAL_BACKUP_TR="Yerel yedek bulunamadi."
TXT_ROLLBACK_NO_LOCAL_BACKUP_EN="No local backup found."
TXT_ZAPRET_SETTINGS_CLEAN_MENU_TR="Yedekleri Temizle"
TXT_ZAPRET_SETTINGS_CLEAN_MENU_EN="Clean Backups"
TXT_ZAPRET_SETTINGS_CLEAN_CONFIRM_TR="Zapret2 ayar yedekleri silinsin mi? (tar.gz)"
TXT_ZAPRET_SETTINGS_CLEAN_CONFIRM_EN="Delete zapret2 settings backups? (tar.gz)"
TXT_ZAPRET_SETTINGS_CLEAN_NONE_TR="Silinecek zapret2 ayar yedegi bulunamadi."
TXT_ZAPRET_SETTINGS_CLEAN_NONE_EN="No zapret2 settings backups found to delete."
TXT_ZAPRET_SETTINGS_CLEAN_DONE_TR="Zapret2 ayar yedekleri temizlendi."
TXT_ZAPRET_SETTINGS_CLEAN_DONE_EN="Zapret2 settings backups have been cleaned."
TXT_ZAPRET_SETTINGS_CLEAN_FAIL_TR="Yedekler silinemedi!"
TXT_ZAPRET_SETTINGS_CLEAN_FAIL_EN="Failed to delete backups!"
# -------------------------------------------------------------------
# Hostlist / Autohostlist (Menu 11) - i18n
# -------------------------------------------------------------------
TXT_HL_TITLE_TR="Hostlist / Autohostlist Menusu"
TXT_HL_TITLE_EN="Hostlist / Autohostlist Menu"
TXT_SCOPE_MODE_TR="Kapsam Modu (Global/Akilli)"
TXT_SCOPE_MODE_EN="Scope Mode (Global/Smart)"
TXT_SCOPE_GLOBAL_DESC_TR="Tum Agda Aktif - Mevcut Davranis"
TXT_SCOPE_GLOBAL_DESC_EN="Active Across the Whole Network - Current Behavior"
TXT_SCOPE_SMART_DESC_TR="Sadece DPI Olan Hostlar - autohostlist"
TXT_SCOPE_SMART_DESC_EN="Only DPI-Affected hosts - autohostlist"
TXT_SCOPE_GLOBAL_TR="Global"
TXT_SCOPE_GLOBAL_EN="Global"
TXT_SCOPE_SMART_TR="Akilli"
TXT_SCOPE_SMART_EN="Smart"
TXT_SCOPE_BACK_TR="Geri"
TXT_SCOPE_BACK_EN="Back"
TXT_SCOPE_PROMPT_TR="Seciminiz (0-2): "
TXT_SCOPE_PROMPT_EN="Select (0-2): "
TXT_SCOPE_CHANGED_TR="Kapsam Modu Degistirildi: %s"
TXT_SCOPE_CHANGED_EN="Scope Mode Changed: %s"
TXT_SCOPE_INVALID_TR="Gecersiz Secim."
TXT_SCOPE_INVALID_EN="Invalid Choice."
TXT_HL_CURRENT_MODE_TR="Filtreleme Modu : "
TXT_HL_CURRENT_MODE_EN="Filter Mode     : "
TXT_HL_SCOPE_MODE_TR="Kapsam Modu     : "
TXT_HL_SCOPE_MODE_EN="Scope Mode      : "
TXT_HL_COUNTS_TR="User/Excl./Auto : "
TXT_HL_COUNTS_EN="User/Excl./Auto : "
TXT_HL_OPT_1_TR="Filtreleme Modunu Degistir"
TXT_HL_OPT_1_EN="Change Filtering Mode"
TXT_HL_OPT_2_TR="User hostlist: Domain Ekle"
TXT_HL_OPT_2_EN="User hostlist: Add Domain"
TXT_HL_OPT_3_TR="User hostlist: Domain Sil"
TXT_HL_OPT_3_EN="User hostlist: Remove Domain"
TXT_HL_OPT_4_TR="Exclude (Domain): Ekle (Islenmesin)"
TXT_HL_OPT_4_EN="Exclude: Add Domain (Do not Process)"
TXT_HL_OPT_5_TR="Exclude (Domain): Sil"
TXT_HL_OPT_5_EN="Exclude: Remove (Domain)"
TXT_HL_OPT_6_TR="Listeleri Goster"
TXT_HL_OPT_6_EN="Show Lists"
TXT_HL_OPT_7_TR="Otomatik Listeyi Temizle"
TXT_HL_OPT_7_EN="Clear Auto List"
TXT_HL_WARN_AUTOCLEAR_1_TR="UYARI: Otomatik listeyi temizlemek tum ogrenilen domainleri silecek!"
TXT_HL_WARN_AUTOCLEAR_1_EN="WARNING: Clearing the auto list will delete all learned domains!"
TXT_HL_WARN_AUTOCLEAR_2_TR="Bu islem geri alinamaz."
TXT_HL_WARN_AUTOCLEAR_2_EN="This action cannot be undone."
TXT_HL_BULK_HINT_TR="Birden fazla domain girebilirsiniz (virgul/noktalivirgul/bosluk ile ayirin)."
TXT_HL_BULK_HINT_EN="You can enter multiple domains (separate with comma/semicolon/space)."
TXT_HL_BULK_HINT2_TR="Alt alta yapistirabilirsiniz. Yapistirma veya giris bittikten sonra bir kez daha ENTER'a basin (bos satir)."
TXT_HL_BULK_HINT2_EN="You can paste multiple lines. After pasting or typing, press ENTER once more on an empty line to finish."
TXT_HL_CANCELLED_TR="Iptal edildi."
TXT_HL_CANCELLED_EN="Cancelled."
TXT_HL_OPT_8_TR="Kapsam Modunu Degistir (Global/Akilli)"
TXT_HL_OPT_8_EN="Change Scope Mode (Global/Smart)"
TXT_HL_OPT_0_TR="Geri"
TXT_HL_OPT_0_EN="Back"
# Hostlist / Autohostlist (MODE_FILTER) sub-menu
TXT_HL_MODE_TITLE_TR="Hostlist / Autohostlist (MODE_FILTER)"
TXT_HL_MODE_TITLE_EN="Hostlist / Autohostlist (MODE_FILTER)"
TXT_HL_MODE_NONE_DESC_TR="Filtre Yok"
TXT_HL_MODE_NONE_DESC_EN="No Filtering"
TXT_HL_MODE_HOSTLIST_DESC_TR="Sadece Listedeki Domainler"
TXT_HL_MODE_HOSTLIST_DESC_EN="Only Domains in List"
TXT_HL_MODE_AUTO_DESC_TR="Otomatik Ogren + Liste"
TXT_HL_MODE_AUTO_DESC_EN="Auto-Learn + List"
TXT_HL_ACTIVE_MARK_TR=" [36m(AKTIF)[0m"
TXT_HL_ACTIVE_MARK_EN=" [36m(ACTIVE)[0m"
TXT_HL_PICK_TR="Secim: "
TXT_HL_PICK_EN="Choice: "
TXT_HL_WARN_EMPTY_TR="UYARI: User hostlist bos. Hostlist modunda etki goremeyebilirsiniz."
TXT_HL_WARN_EMPTY_EN="WARNING: User hostlist is empty. Hostlist mode may have no effect."
TXT_HL_SET_OK_TR="MODE_FILTER Ayarlandi:"
TXT_HL_SET_OK_EN="MODE_FILTER Set:"
TXT_HL_SET_FAIL_TR="HATA: MODE_FILTER Ayarlanamadi"
TXT_HL_SET_FAIL_EN="ERROR: Failed to set MODE_FILTER"
TXT_HL_RESTART_TR="Zapret2 yeniden baslatildi."
TXT_HL_RESTART_EN="Zapret2 restarted."
TXT_HL_DONE_TR="Tamam."
TXT_HL_DONE_EN="Done."
TXT_HL_BAD_TR="Gecersiz secim."
TXT_HL_BAD_EN="Invalid choice."
TXT_HL_NEED_TR="Gerekli: "
TXT_HL_NEED_EN="Required: "
TXT_HL_LIST_USER_TR="User Hostlist          "
TXT_HL_LIST_USER_EN="User Hostlist          "
TXT_HL_LIST_EXCLUDE_DOM_TR="Exclude (Domain)       "
TXT_HL_LIST_EXCLUDE_DOM_EN="Exclude (Domain)       "
TXT_HL_LIST_EXCLUDE_IP_TR="Exclude (IP/Subnet)    "
TXT_HL_LIST_EXCLUDE_IP_EN="Exclude (IP/Subnet)    "
TXT_HL_LIST_LOCALNETS_TR="Yerel Aglar (LocalNets)"
TXT_HL_LIST_LOCALNETS_EN="Local Networks         "
TXT_HL_LIST_AUTO_TR="Auto Hostlist          "
TXT_HL_LIST_AUTO_EN="Auto Hostlist          "
TXT_HL_DOMAIN_ADD_TR="Domain eklendi: "
TXT_HL_DOMAIN_ADD_EN="Domain added: "
TXT_HL_DOMAIN_DEL_TR="Domain silindi: "
TXT_HL_DOMAIN_DEL_EN="Domain removed: "
TXT_HL_CLEARED_TR="Auto list temizlendi."
TXT_HL_CLEARED_EN="Auto list cleared."
# Hostlist prompts & messages
TXT_HL_ERR_NOT_INSTALLED_TR="HATA: Zapret2 yuklu degil."
TXT_HL_ERR_NOT_INSTALLED_EN="ERROR: Zapret2 is not installed."
TXT_HL_PROMPT_ADD_TR="Eklenecek Domain (0=iptal): "
TXT_HL_PROMPT_ADD_EN="Domain to Add (0=cancel): "
TXT_HL_PROMPT_DEL_TR="Silinecek Domain (0=iptal): "
TXT_HL_PROMPT_DEL_EN="Domain to Remove (0=cancel): "
TXT_HL_INVALID_DOMAIN_TR="Gecersiz Domain."
TXT_HL_INVALID_DOMAIN_EN="Invalid Domain."
TXT_HL_MSG_ADDED_TR="Eklendi: "
TXT_HL_MSG_ADDED_EN="Added: "
TXT_HL_MSG_REMOVED_TR="Silindi: "
TXT_HL_MSG_REMOVED_EN="Removed: "
TXT_HL_WARN_EMPTY_STRICT_TR="UYARI: User hostlist bos. Bu durumda zapret2, exclude haric tum hostlari isleyebilir. Devam etmek icin en az bir domain ekleyin veya exclude kullanin."
TXT_HL_WARN_EMPTY_STRICT_EN="WARNING: User hostlist is empty. In this case, zapret2 may process all hosts except exclude. Add at least one domain or use exclude before enabling."
TXT_MENU_B_TR=" B. Blockcheck Test (Otomatik DPI)"
TXT_MENU_B_EN=" B. Blockcheck Test (Auto DPI)"
TXT_BLOCKCHECK_TEST_TITLE_TR="Blockcheck Test Menusu"
TXT_BLOCKCHECK_TEST_TITLE_EN="Blockcheck Test Menu"
TXT_BLOCKCHECK_SUMMARY_TR="Blockcheck Test (Otomatik DPI Profili)"
TXT_BLOCKCHECK_SUMMARY_EN="Blockcheck Test (Auto DPI Profile)"
TXT_BLOCKCHECK_CLEAN_TR="Test Sonuclarini Temizle"
TXT_BLOCKCHECK_CLEAN_EN="Clean Test Results"
TXT_BLOCKCHECK_EXPORT_TR="Aktif DPI Profilini Disa Aktar"
TXT_BLOCKCHECK_EXPORT_EN="Export Active DPI Profile"
TXT_BLOCKCHECK_EXPORT_TITLE_TR="Aktif DPI Profili Disa Aktar"
TXT_BLOCKCHECK_EXPORT_TITLE_EN="Export Active DPI Profile"
TXT_BLOCKCHECK_EXPORT_FILE_TR="Cikti dosyasi"
TXT_BLOCKCHECK_EXPORT_FILE_EN="Output file"
TXT_BLOCKCHECK_EXPORT_NO_RUNTIME_TR="UYARI: nfqws2 calismiyor. Config dosyasindaki profil gosteriliyor."
TXT_BLOCKCHECK_EXPORT_NO_RUNTIME_EN="WARNING: nfqws2 is not running. Showing profile from config."
TXT_BLOCKCHECK_EXPORT_EMPTY_TR="HATA: Aktif DPI parametresi bulunamadi."
TXT_BLOCKCHECK_EXPORT_EMPTY_EN="ERROR: Active DPI parameters not found."
TXT_BLOCKCHECK_EXPORT_HINT_TR="Bu blogu GitHub issue veya Telegram'da paylasabilirsiniz."
TXT_BLOCKCHECK_EXPORT_HINT_EN="You can share this block on GitHub issue or Telegram."
TXT_BLOCKCHECK_CLEAN_NONE_TR="Temizlenecek test raporu yok."
TXT_BLOCKCHECK_CLEAN_NONE_EN="No test reports to clean."
TXT_BLOCKCHECK_CLEAN_DONE_TR="Test raporlari temizlendi."
TXT_BLOCKCHECK_CLEAN_DONE_EN="Test reports cleaned."
TXT_BLOCKCHECK_SUMMARY_SAVED_TR="Ozet rapor kaydedildi:"
TXT_BLOCKCHECK_SUMMARY_SAVED_EN="Summary saved:"
TXT_BLOCKCHECK_SUMMARY_NOT_FOUND_TR="UYARI: SUMMARY bolumu bulunamadi."
TXT_BLOCKCHECK_SUMMARY_NOT_FOUND_EN="WARNING: SUMMARY section not found."
TXT_BLK_HM_AUTORESTART_PAUSED_TR="HealthMon otomatik baslama gecici olarak devre disi birakildi."
TXT_BLK_HM_AUTORESTART_PAUSED_EN="HealthMon auto-restart temporarily disabled."
TXT_BLK_HM_AUTORESTART_RESTORED_TR="HealthMon otomatik baslama eski haline getirildi."
TXT_BLK_HM_AUTORESTART_RESTORED_EN="HealthMon auto-restart restored."
# Blockcheck (Summary) - action screen (i18n)
TXT_BLOCKCHECK_FOUND_TR="Blockcheck sonucu bulundu:"
TXT_BLOCKCHECK_FOUND_EN="Blockcheck result found:"
TXT_BLOCKCHECK_MOST_STABLE_TR="Bu ISS icin en stabil parametre:"
TXT_BLOCKCHECK_MOST_STABLE_EN="Most stable parameter for this ISP:"
TXT_BLOCKCHECK_SCORE_TR="DPI Saglik Skoru:"
TXT_BLOCKCHECK_SCORE_EN="DPI Health Score:"
TXT_BLOCKCHECK_SCORE_DNS_OK_TR="DNS tutarli"
TXT_BLOCKCHECK_SCORE_DNS_OK_EN="DNS consistent"
TXT_BLOCKCHECK_SCORE_TLS12_OK_TR="TLS12 OK"
TXT_BLOCKCHECK_SCORE_TLS12_OK_EN="TLS12 OK"
TXT_BLOCKCHECK_SCORE_UDP_WEAK_TR="UDP 443 zayif"
TXT_BLOCKCHECK_SCORE_UDP_WEAK_EN="UDP 443 weak"
TXT_BLOCKCHECK_ACTION_MENU_TR="[1] Uygula
[2] Parametreyi incele
[3] Sadece kaydet
[0] Vazgec"
TXT_BLOCKCHECK_ACTION_MENU_EN="[1] Apply
[2] Inspect parameter
[3] Save only
[0] Cancel"
TXT_BLOCKCHECK_ACTION_PROMPT_TR="Secim: "
TXT_BLOCKCHECK_ACTION_PROMPT_EN="Choice: "
TXT_PROMPT_SELECTION_TR=" Secim: "
TXT_PROMPT_SELECTION_EN=" Selection: "
TXT_MENU_L_TR=" L. Dil Degistir (TR/EN)"
TXT_MENU_L_EN=" L. Switch Language (TR/EN)"
TXT_MENU_R_TR=" R. Zamanlanmis Gorevler (Cron)"
TXT_MENU_R_EN=" R. Scheduled Tasks (Cron)"
TXT_MENU_U_TR=" U. KZM2 + Zapret2 Kaldir (Tam Temiz)"
TXT_MENU_U_EN=" U. KZM2 + Zapret2 Uninstall (Full Clean)"
TXT_MENU_0_TR=" 0. Cikis"
TXT_MENU_0_EN=" 0. Exit"
TXT_MENU_FOOT_TR="--------------------------------------------------------------------------------------------"
TXT_MENU_FOOT_EN="--------------------------------------------------------------------------------------------"
TXT_PROMPT_MAIN_TR=" Seciminizi Yapin (0-17, B, L, R, U): "
TXT_PROMPT_MAIN_EN=" Select an Option (0-17, B, L, R, U): "
TXT_LANG_NOW_TR="Dil: Turkce"
TXT_LANG_NOW_EN="Language: English"
# IPSET menu
TXT_IPSET_TITLE_TR=" Zapret2 IPSET (Istemci Secimi)"
TXT_IPSET_TITLE_EN=" Zapret2 IPSET (Client Selection)"
TXT_IPSET_1_TR=" 1. Mevcut IP Listesini Goster"
TXT_IPSET_1_EN=" 1. Show Current IP List"
TXT_IPSET_2_TR=" 2. Tum Aga Uygula (client Filtresi Kapali)"
TXT_IPSET_2_EN=" 2. Apply to Whole Network (Client Filter Off)"
TXT_IPSET_3_TR=" 3. Secili IP'lere Uygula (IP gir)"
TXT_IPSET_3_EN=" 3. Apply to Selected IPs (enter IPs)"
TXT_IPSET_4_TR=" 4. Listeye Tek IP Ekle"
TXT_IPSET_4_EN=" 4. Add a Single IP to list"
TXT_IPSET_5_TR=" 5. Listeden Tek IP Sil"
TXT_IPSET_5_EN=" 5. Remove a Single IP from list"
TXT_IPSET_6_TR=" 6. No Zapret2 (Muafiyet) Yonetimi"
TXT_IPSET_6_EN=" 6. No Zapret2 (Exemption) Management"
TXT_IPSET_7_TR=" 7. VPN Sunucu Subneti Ekle"
TXT_IPSET_7_EN=" 7. Add VPN Server Subnet"
TXT_IPSET_0_TR=" 0. Ana Menuye Don"
TXT_IPSET_0_EN=" 0. Back to Main Menu"
TXT_PROMPT_IPSET_TR=" Seciminizi Yapin (0-7): "
TXT_PROMPT_IPSET_EN=" Select an Option (0-7): "
TXT_PROMPT_IPSET_BASIC_TR=" Seciminizi Yapin (0-3, 6-7): "
TXT_PROMPT_IPSET_BASIC_EN=" Select an Option (0-3, 6-7): "
TXT_NOZAPRET_TITLE_TR="No Zapret2 (Muafiyet) Yonetimi"
TXT_NOZAPRET_TITLE_EN="No Zapret2 (Exemption) Management"
TXT_NOZAPRET_DESC_TR="Bu listedeki IP'ler Zapret2 isleminden MUAF tutulur (ornegin IPTV kutulari)"
TXT_NOZAPRET_DESC_EN="IPs in this list are EXEMPT from Zapret2 processing (e.g. IPTV boxes)"
TXT_NOZAPRET_1_TR=" 1. Muafiyet Listesini Goster"
TXT_NOZAPRET_1_EN=" 1. Show Exemption List"
TXT_NOZAPRET_2_TR=" 2. IP Ekle (Zapret2'den Muaf Tut)"
TXT_NOZAPRET_2_EN=" 2. Add IP (Exempt from Zapret2)"
TXT_NOZAPRET_3_TR=" 3. IP Sil"
TXT_NOZAPRET_3_EN=" 3. Remove IP"
TXT_NOZAPRET_4_TR=" 4. Listeyi Temizle"
TXT_NOZAPRET_4_EN=" 4. Clear List"
TXT_NOZAPRET_0_TR=" 0. Geri"
TXT_NOZAPRET_0_EN=" 0. Back"
TXT_NOZAPRET_PROMPT_TR=" Seciminizi Yapin (0-4): "
TXT_NOZAPRET_PROMPT_EN=" Select an Option (0-4): "
TXT_NOZAPRET_ADD_TR="Muaf tutulacak IP'i girin (Enter=iptal): "
TXT_NOZAPRET_ADD_EN="Enter IP to exempt (Enter=cancel): "
TXT_NOZAPRET_DEL_TR="Silmek istediginiz IP'i girin (Enter=iptal): "
TXT_NOZAPRET_DEL_EN="Enter IP to remove (Enter=cancel): "
TXT_NOZAPRET_EMPTY_TR="Muafiyet listesi bos."
TXT_NOZAPRET_EMPTY_EN="Exemption list is empty."
TXT_NOZAPRET_ADDED_TR="Tamam: IP muafiyet listesine eklendi."
TXT_NOZAPRET_ADDED_EN="OK: IP added to exemption list."
TXT_NOZAPRET_EXISTS_TR="Bu IP zaten listede."
TXT_NOZAPRET_EXISTS_EN="This IP is already in the list."
TXT_NOZAPRET_REMOVED_TR="Tamam: IP muafiyet listesinden silindi."
TXT_NOZAPRET_REMOVED_EN="OK: IP removed from exemption list."
TXT_NOZAPRET_NOTFOUND_TR="IP listede bulunamadi."
TXT_NOZAPRET_NOTFOUND_EN="IP not found in list."
TXT_NOZAPRET_CLEARED_TR="Tamam: Muafiyet listesi temizlendi."
TXT_NOZAPRET_CLEARED_EN="OK: Exemption list cleared."
TXT_NOZAPRET_CONFIRM_CLEAR_TR="Tum muafiyet listesini silmek istiyor musunuz? (e/h): "
TXT_NOZAPRET_CONFIRM_CLEAR_EN="Delete entire exemption list? (y/n): "
TXT_NOZAPRET_INVALID_IP_TR="Gecersiz IP adresi!"
TXT_NOZAPRET_INVALID_IP_EN="Invalid IP address!"
TXT_NOZAPRET_IPSET_ACTIVE_TR="  IPSET Aktif Uyeler:"
TXT_NOZAPRET_IPSET_ACTIVE_EN="  IPSET Active Members:"
TXT_NOZAPRET_IPSET_EMPTY_TR="  (IPSET bos veya tanimsiz)"
TXT_NOZAPRET_IPSET_EMPTY_EN="  (IPSET empty or undefined)"
# Ceviri secici
# --- EK DIL METINLERI (TR/EN) ---
TXT_PRESS_ENTER_TR="Devam etmek icin Enter'a basin..."
TXT_PRESS_ENTER_EN="Press Enter to continue..."
# --- Script path warning ---
TXT_WARN_BAD_PATH_TR="UYARI: Betik beklenen dizinde degil!"
TXT_WARN_BAD_PATH_EN="WARNING: Script is not in the expected directory!"
TXT_WARN_MOVE_TR="[1] Dogru yere tasi"
TXT_WARN_MOVE_EN="[1] Move to correct location"
TXT_WARN_CONTINUE_TR="[0] Devam et"
TXT_WARN_CONTINUE_EN="[0] Continue"
TXT_WARN_CHOICE_TR="Secim: "
TXT_WARN_CHOICE_EN="Choice: "
TXT_WARN_MOVED_OK_TR="Betik dogru dizine tasindi."
TXT_WARN_MOVED_OK_EN="Script moved to the correct location."
TXT_WARN_MOVE_FAIL_TR="HATA: Betik tasinamadi."
TXT_WARN_MOVE_FAIL_EN="ERROR: Failed to move the script."
TXT_WARN_CHMOD_FAIL_TR="HATA: Calistirma izni verilemedi."
TXT_WARN_CHMOD_FAIL_EN="ERROR: Could not set executable permission."
TXT_SCRIPT_INSTALLED_TR="Kurulu Betik Surumu : "
TXT_SCRIPT_INSTALLED_EN="Installed Script Ver : "
TXT_GITHUB_LATEST_SIMPLE_TR="GitHub Guncel Surum : "
TXT_GITHUB_LATEST_SIMPLE_EN="GitHub Latest Ver  : "
TXT_GITHUB_NOINFO_TR="Bilgi alinamadi"
TXT_GITHUB_NOINFO_EN="Unable to fetch info"
TXT_REPO_LABEL_TR="Repo               : "
TXT_REPO_LABEL_EN="Repo               : "
TXT_EMPTY_TR="(bos)"
TXT_EMPTY_EN="(empty)"
TXT_IPSET_MODE_LIST_TR="Mod: Secili IP"
TXT_IPSET_MODE_LIST_EN="Mode: Selected IPs"
TXT_IPSET_MODE_ALL_TR="Mod: Tum Ag"
TXT_IPSET_MODE_ALL_EN="Mode: Whole Network"
TXT_IPSET_ALL_NETWORK_TR="Zapret2 tum ag genelinde aktif. Secili IP listesi kullanilmiyor."
TXT_IPSET_ALL_NETWORK_EN="Zapret2 is active network-wide. Selected IP list is not in use."
TXT_IP_LIST_FILE_TR="IP Listesi (dosya): "
TXT_IP_LIST_FILE_EN="IP List (file): "
TXT_IPSET_MEMBERS_TR="IPSET Uyeleri (aktif): "
TXT_IPSET_MEMBERS_EN="IPSET Members (active): "
TXT_VERSION_INSTALLED_TR="Kurulu Surum: "
TXT_VERSION_INSTALLED_EN="Installed Version: "
TXT_CHECKING_GITHUB_TR="GitHub uzerinden en guncel surum sorgulaniyor..."
TXT_CHECKING_GITHUB_EN="Checking latest version on GitHub..."
TXT_GITHUB_LATEST_TR="Guncel"
TXT_GITHUB_LATEST_EN="Latest"
TXT_DEVICE_VERSION_TR="Kurulu"
TXT_DEVICE_VERSION_EN="Installed"
TXT_UPTODATE_TR="En guncel surumu kullaniyorsunuz."
TXT_UPTODATE_EN="You are using the latest version."
TXT_ZAP_NEWER_LOCAL_TR="Kurulu surum GitHub'dakinden YENI (geri cekilmis olabilir). GitHub surumunu yeniden yuklemek ister misiniz? (e/h): "
TXT_ZAP_NEWER_LOCAL_EN="Installed version is NEWER than GitHub (may have been pulled). Reinstall GitHub version? (y/n): "
TXT_ZAP_NEWER_LOCAL_WARN_TR="UYARI: Kurulu surum GitHub'da mevcut degil veya geri cekilmis."
TXT_ZAP_NEWER_LOCAL_WARN_EN="WARNING: Installed version is not available on GitHub or was pulled back."
TXT_GITHUB_FAIL_TR="HATA: GitHub uzerinden surum bilgisi alinamadi."
TXT_GITHUB_FAIL_EN="ERROR: Could not fetch version info from GitHub."
TXT_ZAP_UPDATE_CONFIRM_TR="Guncellemek istiyor musunuz? (e/h): "
TXT_ZAP_UPDATE_CONFIRM_EN="Do you want to update? (y/n): "
TXT_ZAP_UPDATE_DOWNLOADING_TR="Zapret2 indiriliyor..."
TXT_ZAP_UPDATE_DOWNLOADING_EN="Downloading Zapret2..."
TXT_ZAP_UPDATE_EXTRACTING_TR="Arsiv aciliyor..."
TXT_ZAP_UPDATE_EXTRACTING_EN="Extracting archive..."
TXT_ZAP_UPDATE_APPLYING_TR="Binary dosyalar yukleniyor..."
TXT_ZAP_UPDATE_APPLYING_EN="Applying binaries..."
TXT_ZAP_UPDATE_OK_TR="Zapret2 basariyla guncellendi."
TXT_ZAP_UPDATE_OK_EN="Zapret2 updated successfully."
TXT_ZAP_UPDATE_FAIL_DL_TR="HATA: Zapret2 indirilemedi."
TXT_ZAP_UPDATE_FAIL_DL_EN="ERROR: Failed to download Zapret2."
TXT_ZAP_UPDATE_FAIL_EX_TR="HATA: Arsiv acilamadi."
TXT_ZAP_UPDATE_FAIL_EX_EN="ERROR: Failed to extract archive."
TXT_ZAP_UPDATE_FAIL_BIN_TR="HATA: Binary dosyalar kopyalanamadi."
TXT_ZAP_UPDATE_FAIL_BIN_EN="ERROR: Failed to apply binaries."
TXT_ZAP_UPDATE_SHA256_OK_TR="SHA256 dogrulamasi basarili."
TXT_ZAP_UPDATE_SHA256_OK_EN="SHA256 verification passed."
TXT_ZAP_UPDATE_SHA256_FAIL_TR="SHA256 dogrulamasi basarisiz! Dosya bozuk veya degistirilmis olabilir."
TXT_ZAP_UPDATE_SHA256_FAIL_EN="SHA256 verification failed! File may be corrupt or tampered."
TXT_ZAP_UPDATE_SHA256_SKIP_TR="SHA256 bilgisi alinamadi, dogrulama atlandi."
TXT_ZAP_UPDATE_SHA256_SKIP_EN="SHA256 not available from GitHub, verification skipped."
TXT_ZAP_UPDATE_CANCELLED_TR="Guncelleme iptal edildi."
TXT_ZAP_UPDATE_CANCELLED_EN="Update cancelled."
TXT_ZAP_UPDATE_NO_INSTALLED_TR="Zapret2 kurulu degil. Once kurulum yapin."
TXT_ZAP_UPDATE_NO_INSTALLED_EN="Zapret2 is not installed. Please install first."
TXT_ADD_IP_TR="Eklenecek IP (Enter=Vazgec): "
TXT_ADD_IP_EN="IP to add (Enter=Cancel): "
TXT_DEL_IP_TR="Silinecek IP (Enter=Vazgec): "
TXT_DEL_IP_EN="IP to remove (Enter=Cancel): "
# --- KeenDNS Izleme ---
TXT_KEENDNS_BANNER_LABEL_TR="KeenDNS"
TXT_KEENDNS_BANNER_LABEL_EN="KeenDNS"
TXT_KEENDNS_DIRECT_TR="Dogrudan Erisim"
TXT_KEENDNS_DIRECT_EN="Direct Access"
TXT_KEENDNS_CLOUD_TR="Yalnizca Cloud"
TXT_KEENDNS_CLOUD_EN="Cloud Only"
TXT_KEENDNS_NONE_TR="KeenDNS kaydi yok"
TXT_KEENDNS_NONE_EN="No KeenDNS record"
TXT_KEENDNS_UNKNOWN_TR="Bilinmiyor"
TXT_KEENDNS_UNKNOWN_EN="Unknown"
TXT_KEENDNS_LOST_TR="⚠️ KeenDNS Uyari\n🔗 %s\n☁️ Dogrudan erisim kesildi, yalnizca cloud aktif."
TXT_KEENDNS_CGN_LOST_TR="⚠️ KeenDNS Uyari\n🔗 %s\n☁️ Cloud erisimi kesildi (CGN/direkt erisim yok)."
TXT_KEENDNS_CGN_LOST_EN="⚠️ KeenDNS Alert\n🔗 %s\n☁️ Cloud access lost (CGN / no direct access)."
TXT_KEENDNS_CGN_BACK_TR="✅ KeenDNS Geri Geldi\n🔗 %s\n☁️ Cloud erisimi yeniden aktif."
TXT_KEENDNS_CGN_BACK_EN="✅ KeenDNS Restored\n🔗 %s\n☁️ Cloud access is active again."
TXT_KEENDNS_LOST_EN="⚠️ KeenDNS Alert\n🔗 %s\n☁️ Direct access lost, cloud only."
TXT_KEENDNS_BACK_TR="✅ KeenDNS Geri Geldi\n🔗 %s\n🌐 Dogrudan erisim yeniden aktif."
TXT_KEENDNS_BACK_EN="✅ KeenDNS Restored\n🔗 %s\n🌐 Direct access is active again."
TXT_KEENDNS_FAIL_TR="❌ KeenDNS Erisim Yok\n🔗 %s\n🚫 Domain disaridan erisilebilir degil."
TXT_KEENDNS_FAIL_EN="❌ KeenDNS Unreachable\n🔗 %s\n🚫 Domain is not accessible from outside."
TXT_KEENDNS_REACH_TR="✅ KeenDNS Erisim Geri Geldi\n%s\nDomain tekrar disaridan erisilebilir."
TXT_KEENDNS_REACH_EN="✅ KeenDNS Reachable Again\n%s\nDomain is accessible from outside again."
# Component Check translations
TXT_COMP_CHECK_TITLE_TR="=== Keenetic Bilesenler Kontrolu ==="
TXT_COMP_CHECK_TITLE_EN="=== Keenetic Components Check ==="
TXT_COMP_OPKG_TR="OPKG (Entware)"
TXT_COMP_OPKG_EN="OPKG (Entware)"
TXT_COMP_OPKG_REQ_TR="OPKG (Entware) - ZORUNLU!"
TXT_COMP_OPKG_REQ_EN="OPKG (Entware) - REQUIRED!"
TXT_COMP_IPV6_TR="IPv6 destegi (ip6tables)"
TXT_COMP_IPV6_EN="IPv6 support (ip6tables)"
TXT_COMP_IPV6_REQ_TR="IPv6 destegi - ZORUNLU!"
TXT_COMP_IPV6_REQ_EN="IPv6 support - REQUIRED!"
TXT_COMP_IPV6_SHORT_TR="IPv6 destegi"
TXT_COMP_IPV6_SHORT_EN="IPv6 support"
TXT_COMP_IPTABLES_TR="iptables"
TXT_COMP_IPTABLES_EN="iptables"
TXT_COMP_IPTABLES_REQ_TR="iptables - ZORUNLU!"
TXT_COMP_IPTABLES_REQ_EN="iptables - REQUIRED!"
TXT_COMP_NFQUEUE_TR="Netfilter Queue modulleri"
TXT_COMP_NFQUEUE_EN="Netfilter Queue modules"
TXT_COMP_NFQUEUE_WARN_TR="Netfilter kernel modulleri yuklu degil - Zapret2 servisi baslamaz!"
TXT_COMP_NFQUEUE_WARN_EN="Netfilter kernel modules not installed - Zapret2 service will not start!"
TXT_COMP_CURL_TR="curl (guncelleme icin)"
TXT_COMP_CURL_EN="curl (for updates)"
TXT_COMP_WGET_TR="wget (guncelleme icin)"
TXT_COMP_WGET_EN="wget (for updates)"
TXT_COMP_CURL_REQ_TR="curl veya wget - ZORUNLU!"
TXT_COMP_CURL_REQ_EN="curl or wget - REQUIRED!"
TXT_COMP_OR_TR="veya"
TXT_COMP_OR_EN="or"
TXT_COMP_IPSET_TR="ipset"
TXT_COMP_IPSET_EN="ipset"
TXT_COMP_IPSET_REQ_TR="ipset - ZORUNLU!"
TXT_COMP_IPSET_REQ_EN="ipset - REQUIRED!"
TXT_COMP_STORAGE_USB_TR="Harici depolama - USB (/opt bagli)"
TXT_COMP_STORAGE_USB_EN="External storage - USB (/opt mounted)"
TXT_COMP_STORAGE_INTERNAL_TR="Dahili depolama - eMMC/SD (/opt bagli)"
TXT_COMP_STORAGE_INTERNAL_EN="Internal storage - eMMC/SD (/opt mounted)"
TXT_COMP_STORAGE_EMMC_HINT_TR="      (Not: USB kullanimi onerilir - eMMC yipranma riski)"
TXT_COMP_STORAGE_EMMC_HINT_EN="      (Note: USB recommended - eMMC wear risk)"
TXT_COMP_STORAGE_GENERIC_TR="Depolama (/opt bagli)"
TXT_COMP_STORAGE_GENERIC_EN="Storage (/opt mounted)"
TXT_COMP_STORAGE_TMPFS_TR="/opt tmpfs - yeniden baslatmada kayip"
TXT_COMP_STORAGE_TMPFS_EN="/opt on tmpfs - lost on reboot"
TXT_COMP_STORAGE_REC_TR="Depolama - onerilir (USB/eMMC)"
TXT_COMP_STORAGE_REC_EN="Storage - recommended (USB/eMMC)"
TXT_COMP_STORAGE_INTERNAL_SD_TR="Dahili depolama - eMMC/NAND (/opt bagli)"
TXT_COMP_STORAGE_INTERNAL_SD_EN="Internal storage - eMMC/NAND (/opt mounted)"
TXT_COMP_STORAGE_NVME_TR="Dahili depolama - NVMe SSD (/opt bagli)"
TXT_COMP_STORAGE_NVME_EN="Internal storage - NVMe SSD (/opt mounted)"
TXT_COMP_STORAGE_INTERNAL_HINT_TR="      (Not: Harici USB kullanimi onerilir.)"
TXT_COMP_STORAGE_INTERNAL_HINT_EN="      (Note: External USB is recommended.)"
TXT_COMP_CRIT_FAIL_TR="KRITIK bilesenler eksik. Zapret2 calismayacak!"
TXT_COMP_CRIT_FAIL_EN="CRITICAL components missing. Zapret2 will NOT work!"
TXT_COMP_MISSING_TR="Eksik bilesenler:"
TXT_COMP_MISSING_EN="Missing components:"
TXT_COMP_INSTALL_FROM_TR="Bu bilesenler Keenetic Web UI uzerinden yuklenmelidir:"
TXT_COMP_INSTALL_FROM_EN="These components must be installed from Keenetic Web UI:"
TXT_COMP_INSTALL_PATH_TR="Keenetic Web UI > Yonetim > Genel Sistem Ayarlari > Bilesen Secenekleri > Guncelle"
TXT_COMP_INSTALL_PATH_EN="Keenetic Web UI > Management > General System Settings > Component Options > Update"
TXT_COMP_REBOOT_WARN_TR="UYARI: Bilesenler yuklendikten sonra cihaz yeniden baslatilir!"
TXT_COMP_REBOOT_WARN_EN="WARNING: Device will restart after installing components!"
TXT_COMP_REQUIRED_TR="Gerekli bilesenler:"
TXT_COMP_REQUIRED_EN="Required components:"
TXT_COMP_OPT_WARN_TR="Bazi OPSIYONEL bilesenler eksik. Zapret2 calisir ama tam fonksiyonel olmayabilir."
TXT_COMP_OPT_WARN_EN="Some OPTIONAL components missing. Zapret2 will work but may not be fully functional."
TXT_COMP_ALL_OK_TR="Tum gerekli bilesenler mevcut!"
TXT_COMP_ALL_OK_EN="All required components present!"
TXT_COMP_XTABLES_TR="Netfilter Xtables-addons genisletme paketleri"
TXT_COMP_XTABLES_EN="Netfilter Xtables-addons extension packages"
TXT_COMP_XTABLES_WARN_TR="Xtables-addons yuklu degil - Zapret2 servisi baslamaz!"
TXT_COMP_XTABLES_WARN_EN="Xtables-addons not installed - Zapret2 service will not start!"
TXT_COMP_TC_TR="Trafik Kontrol (tc) kernel modulleri"
TXT_COMP_TC_EN="Traffic Control (tc) kernel modules"
TXT_COMP_TC_WARN_TR="Trafik Kontrol modulleri yuklu degil - Zapret2 servisi baslamaz!"
TXT_COMP_TC_WARN_EN="Traffic Control modules not installed - Zapret2 service will not start!"
TXT_COMP_PRESS_ENTER_TR="Devam etmek icin Enter..."
TXT_COMP_PRESS_ENTER_EN="Press Enter to continue..."
T() {
    # Kullanim:
    #   T KEY                 -> sozlukten KEY_TR / KEY_EN
    #   T KEY "TR metin" "EN metin" -> verilen metinler (sozluge ihtiyac yok)
    local k="$1"
    local tr="$2"
    local en="$3"
    [ -z "$k" ] && return 0
    # Eger TR/EN parametreleri verilmisse onlari kullan
    if [ -n "$tr" ] || [ -n "$en" ]; then
        if [ "$LANG" = "en" ]; then
            [ -n "$en" ] && printf '%s' "$en" || printf '%s' "${tr:-$k}"
        else
            [ -n "$tr" ] && printf '%s' "$tr" || printf '%s' "${en:-$k}"
        fi
        return 0
    fi
    # Sozluk degiskenlerinden oku
    local v=""
    if [ "$LANG" = "en" ]; then
        eval "v="\${${k}_EN}""
        [ -z "$v" ] && eval "v="\${${k}_TR}""
    else
        eval "v="\${${k}_TR}""
        [ -z "$v" ] && eval "v="\${${k}_EN}""
    fi
    [ -z "$v" ] && v="$k"
    printf '%s' "$v"
}
# Enter'a basinca devam et (TR/EN)
press_enter_to_continue() {
    # Robust pause: always read from controlling TTY so it cannot be skipped by buffered stdin.
    # We keep clear after the keypress because menus redraw anyway.
    # EOF guard: if terminal is gone (SSH/Telnet disconnect), exit cleanly.
    printf '%s' "$(T press_enter "$TXT_PRESS_ENTER_TR" "$TXT_PRESS_ENTER_EN")"; read -r _ </dev/tty || exit 0
    clear
}
load_lang() {
    if [ -f "$LANG_FILE" ]; then
        LANG="$(cat "$LANG_FILE" 2>/dev/null | tr -d '\r\n\t ' )"
    fi
    case "$LANG" in
        en|EN) LANG="en" ;;
        *)     LANG="tr" ;;
    esac
}
toggle_lang() {
    load_lang
    if [ "$LANG" = "en" ]; then LANG="tr"; else LANG="en"; fi
    mkdir -p /opt/zapret2 2>/dev/null
    echo "$LANG" > "$LANG_FILE" 2>/dev/null
}
lang_label() {
    if [ "$LANG" = "en" ]; then
        echo "$TXT_LANG_NOW_EN"
    else
        echo "$TXT_LANG_NOW_TR"
    fi
}
load_lang
# IPSET (istemci bazli) ayarlari
IPSET_CLIENT_NAME="zapret2_clients"
IPSET_CLIENT_FILE="/opt/zapret2/ipset_clients.txt"
IPSET_CLIENT_MODE_FILE="/opt/zapret2/ipset_clients_mode"  # all | list
# No Zapret2 (muafiyet) ayarlari
NOZAPRET_IPSET_NAME="nozapret"
NOZAPRET_FILE="/opt/zapret2/ipset/nozapret.txt"
# WAN arayuzu (cikis) secimi / otomatik algilama
WAN_IF_FILE="/opt/zapret2/wan_if"
detect_recommended_wan_if() {
    # Varsayilan route'dan arayuz algila. WireGuard/tun gibi arayuzleri mumkunse secme.
    ip route show default 2>/dev/null | awk '
        $1=="default" {
            dev=""
            for(i=1;i<=NF;i++) if($i=="dev") dev=$(i+1)
            if(dev!="") {
                if(dev !~ /^(wg|nwg|tun|tap)/) { print dev; exit }
                if(fallback=="") fallback=dev
            }
        }
        END { if(fallback!="") print fallback }
    '
}
get_wan_if() {
    local w=""
    if [ -f "$WAN_IF_FILE" ]; then
        w="$(cat "$WAN_IF_FILE" 2>/dev/null | tr -d '\033' | tr -cd '[:alnum:]._/-' | tr -d '\n')"
        # Dosya var ama bos = kullanici "tum arayuzler" secmis, bos don
        echo "$w"
    else
        # Dosya yok = henuz secilmemis, onerilen don
        detect_recommended_wan_if
    fi
}
# WAN arayuzu icin ifindex bilgisi (install_easy.sh arayuz secimi icin)
get_ifindex_by_iface() {
    local ifc="$1"
    [ -z "$ifc" ] && return 1
    cat "/sys/class/net/${ifc}/ifindex" 2>/dev/null
}
# Zapret2 config icinde IFACE_WAN degerini secilen WAN arayuzu ile esitle
sync_zapret_iface_wan_config() {
    local ifc="$(cat "$WAN_IF_FILE" 2>/dev/null)"  # get_wan_if degil, ham oku
    [ ! -d /opt/zapret2 ] && return 0
    [ ! -f /opt/zapret2/config ] && return 0
    if grep -q '^IFACE_WAN=' /opt/zapret2/config 2>/dev/null; then
        sed -i "s/^IFACE_WAN=.*/IFACE_WAN=${ifc}/" /opt/zapret2/config 2>/dev/null
    else
        echo "IFACE_WAN=${ifc}" >> /opt/zapret2/config 2>/dev/null
    fi
}
# NFQUEUE kurallarinda eski/yanlis arayuz kalintilarini temizle (sadece secili WAN kalsin)
cleanup_nfqueue_rules_except_selected_wan() {
    local WAN="$(get_wan_if)"
    [ -z "$WAN" ] && return 0
    # yalnizca NFQUEUE iceren kurallari tara; secili WAN disindakileri sil
    iptables -t mangle -S 2>/dev/null | grep -F ' -j NFQUEUE' | while IFS= read -r line; do
        # line: -A CHAIN ...
        if echo "$line" | grep -Eq -- "(^-A (INPUT|FORWARD) -i ${WAN} )|(-A POSTROUTING -o ${WAN} )"; then
            continue
        fi
        # baska bir arayuze bagli kurali silmeyi dene
        local del
        del="$(echo "$line" | sed 's/^-A /-D /')"
        iptables -t mangle $del 2>/dev/null
    done
}
select_wan_if() {
    # Kurulumda (ve gerekirse sonradan) WAN arayuzunu belirle.
    local rec="$(detect_recommended_wan_if)"
    [ -z "$rec" ] && rec="ppp0"
    print_line "-"
    printf " ${CLR_ORANGE}%s${CLR_RESET}\n" "$(T TXT_WAN_SEL_TITLE)"
    echo "$(T TXT_WAN_SEL_EXAMPLE)"
    echo "$(T TXT_WAN_SEL_CURRENT) $(get_wan_if)"
    echo "$(T TXT_WAN_SEL_RECOMMENDED) $rec"
    print_line "-"
    printf "${CLR_GREEN}%s${CLR_RESET}" "$(tpl_render "$(T TXT_WAN_SEL_PROMPT)" REC "$rec")"
    read -r ans
    [ -z "$ans" ] && ans="$rec"
    # "any" veya "0" girilirse tum arayuzler = bos birak
    [ "$ans" = "any" ] || [ "$ans" = "0" ] && ans=""
    # bazen kopyala-yapistir ile sonuna nokta gelebiliyor (ppp0.)
    if [ -n "$ans" ] && [ ! -d "/sys/class/net/$ans" ] && [ -d "/sys/class/net/${ans%\.}" ]; then
        ans="${ans%.}"
    fi
    mkdir -p /opt/zapret2 2>/dev/null
    echo "$ans" > "$WAN_IF_FILE" 2>/dev/null
    echo "$(T TXT_WAN_SEL_SELECTED) $(get_wan_if)"
}
enforce_wan_if_nfqueue_rules() {
    # NFQUEUE kurallarini sadece secili WAN arayuzunde etkinlestirerek WireGuard vb. arayuzlerde sorunlari azaltir.
    local WAN="$(get_wan_if)"
    [ -z "$WAN" ] && return 0
    # mangle/POSTROUTING: -o WAN ekle
    iptables -t mangle -S POSTROUTING 2>/dev/null | grep -F -- " -j NFQUEUE" | grep -F -- "--queue-num 300" | while read -r rule; do
        echo "$rule" | grep -qE ' -o [^ ]+' && continue
        del="$(echo "$rule" | sed 's/^-A /-D /')"
        iptables -t mangle $del 2>/dev/null
        add="$(echo "$rule" | sed "s/ -j NFQUEUE/ -o $WAN -j NFQUEUE/")"
        iptables -t mangle $add 2>/dev/null
    done
    # filter INPUT/FORWARD: -i WAN ekle (varsa)
    for chain in INPUT FORWARD; do
        iptables -S "$chain" 2>/dev/null | grep -F -- " -j NFQUEUE" | grep -F -- "--queue-num 300" | while read -r rule; do
            echo "$rule" | grep -qE ' -i [^ ]+' && continue
            del="$(echo "$rule" | sed 's/^-A /-D /')"
            iptables $del 2>/dev/null
            add="$(echo "$rule" | sed "s/ -j NFQUEUE/ -i $WAN -j NFQUEUE/")"
            iptables $add 2>/dev/null
        done
    done
    return 0
}
# --- Keenetic: persistently pin NFQUEUE POSTROUTING rules to real WAN (-o ppp0/wgX) ---
_cleanup_post_up_hook() {
    # keenetic_fw_post_up.sh hook'u etki etmiyordu (Keenetic firewall reset'i degisiklikleri siliyordu)
    # ve zapret2.real'i patch etmek zapret2 guncellemelerinde bozuluyordu. Temizle.
    local _real="/opt/zapret2/init.d/sysv/zapret2.real"
    local _hook="/opt/zapret2/keenetic_fw_post_up.sh"
    # zapret2.real'den hook satirlarini kaldir
    if [ -f "$_real" ] && grep -q "keenetic_fw_post_up" "$_real" 2>/dev/null; then
        local _bak="${_real}.bak_pre_cleanup"
        cp -a "$_real" "$_bak" 2>/dev/null
        grep -v "keenetic_fw_post_up" "$_bak" > "$_real" 2>/dev/null
        chmod +x "$_real" 2>/dev/null
    fi
    # Hook dosyasini sil
    rm -f "$_hook" 2>/dev/null
}
# --- DPI PROFIL SECIMI (NFQWS2_OPT) ---
DPI_PROFILE_FILE="/opt/zapret2/dpi_profile"
DPI_PROFILE_ORIGIN_FILE="/opt/zapret2/dpi_profile_origin"
DPI_PROFILE_PARAMS_FILE="/opt/zapret2/dpi_profile_params"
BLOCKCHECK_AUTO_PARAMS_FILE="/opt/zapret2/blockcheck_auto_params"
get_dpi_origin() {
    local o="manual"
    [ -f "$DPI_PROFILE_ORIGIN_FILE" ] && o="$(cat "$DPI_PROFILE_ORIGIN_FILE" 2>/dev/null)"
    case "$o" in
        auto|manual) echo "$o" ;;
        *) echo "manual" ;;
    esac
}
set_dpi_origin() {
    mkdir -p "$(dirname "$DPI_PROFILE_ORIGIN_FILE")" 2>/dev/null
    echo "$1" > "$DPI_PROFILE_ORIGIN_FILE" 2>/dev/null
}
set_dpi_params() {
    mkdir -p "$(dirname "$DPI_PROFILE_PARAMS_FILE")" 2>/dev/null
    printf "%s" "$1" > "$DPI_PROFILE_PARAMS_FILE" 2>/dev/null
}
get_dpi_params() {
    [ -f "$DPI_PROFILE_PARAMS_FILE" ] && cat "$DPI_PROFILE_PARAMS_FILE" 2>/dev/null
}
get_dpi_profile() {
    local p="tt_default"
    [ -f "$DPI_PROFILE_FILE" ] && p="$(cat "$DPI_PROFILE_FILE" 2>/dev/null | tr -d '\r\n')"
    case "$p" in
        tt_default|tt_fiber|superonline_fiber|blockcheck_auto|custom|none) echo "$p" ;;
        # Legacy KZM1-derived profiles are intentionally not exposed/applied in KZM2.
        # They require explicit Zapret2/nfqws2 conversion and field testing.
        tt_alt|sol|sol_alt|sol_fiber|turkcell_mob|vodafone_mob) echo "tt_default" ;;
        *) echo "tt_default" ;;
    esac
}
set_dpi_profile() {
    mkdir -p "$(dirname "$DPI_PROFILE_FILE")" 2>/dev/null
    echo "$1" > "$DPI_PROFILE_FILE" 2>/dev/null
}
dpi_profile_name_tr() {
    case "$1" in
        tt_default)        echo "Varsayilan Zapret2 (TTL2 fake)";;
        tt_fiber)          echo "Turk Telekom Fiber (TTL2 fake)";;
        superonline_fiber) echo "Superonline Fiber (TTL6 hostcase)";;
        blockcheck_auto)   echo "Blockcheck Otomatik (Auto)";;
        none)              echo "Gecis Modu (Bypass Yok)";;
        custom)            echo "Ozel NFQWS2_OPT";;
        tt_alt|sol|sol_alt|sol_fiber|turkcell_mob|vodafone_mob) echo "Eski KZM profili (devre disi)";;
        *) echo "$1";;
    esac
}
dpi_profile_name_en() {
    case "$1" in
        tt_default)        echo "Default Zapret2 (TTL2 fake)";;
        tt_fiber)          echo "Turk Telekom Fiber (TTL2 fake)";;
        superonline_fiber) echo "Superonline Fiber (TTL6 hostcase)";;
        blockcheck_auto)   echo "Blockcheck Auto";;
        none)              echo "Passthrough (No Bypass)";;
        custom)            echo "Custom NFQWS2_OPT";;
        tt_alt|sol|sol_alt|sol_fiber|turkcell_mob|vodafone_mob) echo "Legacy KZM profile (disabled)";;
        *) echo "$1";;
    esac
}
kzm2_dpi_get_arg() {
    # $1=block, $2=long argument name without leading -- (payload|filter-l7)
    local _block="$1" _arg="$2"
    printf '%s' "$_block" | sed -n "s/.*--${_arg}=\([^ ][^ ]*\).*/\1/p" | head -n 1
}

kzm2_dpi_get_field() {
    # $1=block, $2=lua field prefix (blob|ip_ttl|repeats)
    printf '%s' "$1" | sed -n "s/.*$2=\([^: ][^: ]*\).*/\1/p" | head -n 1
}

kzm2_dpi_get_desync() {
    # $1=block; returns first lua-desync method (fake, multidisorder, etc.)
    printf '%s' "$1" | sed -n 's/.*--lua-desync=\([^: ][^: ]*\).*/\1/p' | head -n 1
}

kzm2_dpi_print_kv() {
    # $1=label, $2=value
    [ -n "$2" ] || return 0
    printf '    %-10s : %s\n' "$1" "$2"
}

kzm2_dpi_print_block() {
    local _title="$1" _block="$2" _payload="" _desync="" _blob="" _ttl="" _rep=""
    [ -n "$_block" ] || return 0

    _payload="$(kzm2_dpi_get_arg "$_block" "payload")"
    _desync="$(kzm2_dpi_get_desync "$_block")"
    _blob="$(kzm2_dpi_get_field "$_block" "blob")"
    _ttl="$(kzm2_dpi_get_field "$_block" "ip_ttl")"
    _rep="$(kzm2_dpi_get_field "$_block" "repeats")"

    printf '\n%b%s%b\n' "${CLR_CYAN}${CLR_BOLD}" "$_title" "${CLR_RESET}"
    kzm2_dpi_print_kv "Payload" "$_payload"
    kzm2_dpi_print_kv "Desync" "$_desync"
    kzm2_dpi_print_kv "Blob" "$_blob"
    kzm2_dpi_print_kv "IP TTL" "$_ttl"
    kzm2_dpi_print_kv "Repeats" "$_rep"
}

show_active_dpi_info() {
    local origin="$(get_dpi_origin)"
    local origin_label=""
    local _params="" _http="" _rest="" _tls="" _quic=""

    if [ "$origin" = "auto" ]; then
        origin_label="$(T TXT_ACTIVE_DPI_AUTO)"
    else
        origin_label="$(T TXT_ACTIVE_DPI_DEFAULT)"
    fi

    printf '\n%s : %s\n' "$(T TXT_ACTIVE_DPI)" "$origin_label"

    if [ -s "$DPI_PROFILE_PARAMS_FILE" ]; then
        _params="$(cat "$DPI_PROFILE_PARAMS_FILE" 2>/dev/null)"
        printf '%b%s%b\n' "${CLR_ORANGE}${CLR_BOLD}" "$(T TXT_ACTIVE_DPI_PARAMS)" "${CLR_RESET}"

        _http="${_params%% --new *}"
        if [ "$_params" != "$_http" ]; then
            _rest="${_params#* --new }"
            _tls="${_rest%% --new *}"
            if [ "$_rest" != "$_tls" ]; then
                _quic="${_rest#* --new }"
            fi
        fi

        if [ -n "$_http" ] && [ -n "$_tls" ]; then
            kzm2_dpi_print_block "HTTP (TCP 80)" "$_http"
            print_line "-"
            kzm2_dpi_print_block "TLS (TCP 443)" "$_tls"
            print_line "-"
            kzm2_dpi_print_block "QUIC (UDP 443)" "$_quic"
        else
            # Fallback: bilinmeyen/manuel format varsa tasma yapmadan parcala
            printf '  %s\n' "$_params" | fold -s -w 110 | sed 's/^/  /'
        fi
    fi
}

select_dpi_profile() {
    local cur="$(get_dpi_profile)"
    local origin="$(get_dpi_origin)"
    print_line "-"
    echo " $(T dpi_title "DPI Profili Secimi" "DPI Profile Selection")"
    print_line "-"
    local _cur_label_tr="Su Anki DPI"
    local _cur_label_en="Current DPI"
    local _cur_name="$(T dpi_curp "$(dpi_profile_name_tr "$cur")" "$(dpi_profile_name_en "$cur")")"

    if [ "$origin" = "auto" ]; then
        # Auto: show current as Blockcheck, and show base profile separately
        printf '%b%-16s%b : %b%s%b\n' "${CLR_GREEN}${CLR_BOLD}" "$(T dpi_current "$_cur_label_tr" "$_cur_label_en")" "${CLR_RESET}" "${CLR_GREEN}${CLR_BOLD}" "$(T TXT_ACTIVE_DPI_AUTO)" "${CLR_RESET}"
        printf '%-16s :  %s\n' "$(T TXT_DPI_BASE_PROFILE)" "$_cur_name"
    else
        printf '%b%-16s%b : %b%s%b\n' "${CLR_GREEN}${CLR_BOLD}" "$(T dpi_current "$_cur_label_tr" "$_cur_label_en")" "${CLR_RESET}" "${CLR_GREEN}${CLR_BOLD}" "$_cur_name" "${CLR_RESET}"
    fi

    print_line "-"
    show_active_dpi_info
    print_line "-"
        # Menu satirlarinda:
    # - Varsayilan profil (tt_default) her zaman "Default/Varsayilan" olarak isaretlenir
    # - Kullanilan profil "ACTIVE/AKTIF" olarak isaretlenir
    for _id in tt_default tt_fiber superonline_fiber blockcheck_auto none; do
        _num=""
        case "$_id" in
            tt_default)        _num="1" ;;
            tt_fiber)          _num="2" ;;
            superonline_fiber) _num="3" ;;
            blockcheck_auto)   _num="4" ;;
            none)              _num="5" ;;
        esac
        _name_tr="$(dpi_profile_name_tr "$_id")"
        _name_en="$(dpi_profile_name_en "$_id")"
        _suf_tr=""
        _suf_en=""
        # varsayilan isareti
        if [ "$_id" = "tt_default" ]; then
            _suf_tr=" (Varsayilan)"
            _suf_en=" (Default)"
        fi
# aktif/taban isareti
if [ "$origin" = "auto" ]; then
    # Blockcheck otomatik modunda "AKTIF" etiketi listeye yazilmaz.
    # Bunun yerine mevcut (taban) profil "TABAN/BASE" olarak gosterilir.
    if [ "$cur" = "$_id" ]; then
        _suf_tr="${_suf_tr} (Temel)"
        _suf_en="${_suf_en} (Base)"
    fi
else
    # Manuel mod: secili profil "ACTIVE/AKTIF" olarak isaretlenir
    if [ "$cur" = "$_id" ]; then
        if [ "$origin" = "auto" ]; then
            _suf_tr="${_suf_tr} (Temel)"
            _suf_en="${_suf_en} (Base)"
        else
            _suf_tr="${_suf_tr} ${CLR_CYAN}(AKTIF)${CLR_RESET}"
            _suf_en="${_suf_en} ${CLR_CYAN}(ACTIVE)${CLR_RESET}"
        fi
    fi
fi
        printf ' %s. %s\n' "$_num" "$(T dpi_prof_${_id} "${_name_tr}${_suf_tr}" "${_name_en}${_suf_en}")"
    done
    printf ' 0. %s\n' "$(T back_main 'Ana Menuye Don' 'Back')"
    print_line "-"
    printf '%s' "$(T dpi_prompt "Seciminizi yapin (0-5): " "Select an option (0-5): ")"; read -r sel || return 1
    # sanitize selection (avoid "0 applies 1" edge cases)
    sel="$(echo "$sel" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [ -z "$sel" ] || [ "$sel" = "0" ]; then
        return 1
    fi
    # If auto profile is active, switching to a numbered profile disables auto (by user's choice)
    if [ "$origin" = "auto" ] && echo "$sel" | grep -Eq '^[1-4]$'; then
        local _ans
        printf '%s' "$(T TXT_DPI_AUTO_DISABLE_PROMPT)"; read -r _ans
        local _def_yes="y"
        [ "$LANG" = "tr" ] && _def_yes="e"
        _ans="${_ans:-$_def_yes}"
        case "$_ans" in
            e|E|y|Y) : ;;
            *) return 1 ;;
        esac
    fi
    case "$sel" in
        1)
            set_dpi_profile tt_default
            set_dpi_origin "manual"
            : > "$DPI_PROFILE_PARAMS_FILE" 2>/dev/null
            rm -f "$BLOCKCHECK_AUTO_PARAMS_FILE" 2>/dev/null
            ;;
        2)
            set_dpi_profile tt_fiber
            set_dpi_origin "manual"
            : > "$DPI_PROFILE_PARAMS_FILE" 2>/dev/null
            rm -f "$BLOCKCHECK_AUTO_PARAMS_FILE" 2>/dev/null
            ;;
        3)
            set_dpi_profile superonline_fiber
            set_dpi_origin "manual"
            : > "$DPI_PROFILE_PARAMS_FILE" 2>/dev/null
            rm -f "$BLOCKCHECK_AUTO_PARAMS_FILE" 2>/dev/null
            ;;
        4)
            if [ -s "$BLOCKCHECK_AUTO_PARAMS_FILE" ]; then
                set_dpi_profile blockcheck_auto
                set_dpi_origin "auto"
            else
                echo "$(T _ 'Blockcheck Auto sonucu bulunamadi. Once B > 2 calistirin.' 'Blockcheck Auto result not found. Run B > 2 first.')"
                press_enter_to_continue
                return 1
            fi
            ;;
        5)
            set_dpi_profile none
            set_dpi_origin "manual"
            ;;
        0) return 1 ;;
        *) return 1 ;;
    esac
    # DPI profiline gore NFQWS parametrelerini guncelle
    return 0
}
apply_dpi_profile_now() {
    if ! is_zapret2_installed; then
        echo "$(T err_not_inst "HATA: Zapret2 yuklu degil." "ERROR: Zapret2 is not installed.")"
        press_enter_to_continue
        return 1
    fi
    update_nfqws_parameters
    restart_zapret2 >/dev/null 2>&1 || true
    if [ "$(get_dpi_profile)" != "none" ]; then
        enforce_client_mode_rules >/dev/null 2>&1 || true
        enforce_wan_if_nfqueue_rules >/dev/null 2>&1 || true
    fi
    kzm2_export_active_dpi_profile >/dev/null 2>&1 || true
    healthmon_log "$(date '+%Y-%m-%d %H:%M:%S') | dpi_profile_change | profile=$(get_dpi_profile) | scope=$(get_scope_mode) | new_opt=$(grep '^NFQWS2_OPT=' /opt/zapret2/config 2>/dev/null | cut -d'"' -f2) | src=terminal"
    echo "$(T dpi_applied "DPI profili uygulandi." "DPI profile applied.")"
}
get_client_mode() {
    local m="all"
    [ -f "$IPSET_CLIENT_MODE_FILE" ] && m="$(cat "$IPSET_CLIENT_MODE_FILE" 2>/dev/null)"
    [ -z "$m" ] && m="all"
    echo "$m"
}
ipset_ensure_and_load_clients() {
    command -v ipset >/dev/null 2>&1 || return 1
    ipset list "$IPSET_CLIENT_NAME" >/dev/null 2>&1 || ipset create "$IPSET_CLIENT_NAME" hash:ip >/dev/null 2>&1
    [ -f "$IPSET_CLIENT_FILE" ] || return 0
    # Bosluk/virgul/tab/... ayiricilarini destekle
    tr ' \t,;' '\n' < "$IPSET_CLIENT_FILE" | awk 'NF{print $0}' | while read -r ip; do
        ipset add "$IPSET_CLIENT_NAME" "$ip" -exist >/dev/null 2>&1
    done
    return 0
}

# /opt disk sagligi kontrolu — tum disk_health bloklarinda ortak kullanilir
# Cikti: _dh_status (PASS/WARN/FAIL), _dh_reason (aciklama metni)
# Kullanim: kzm2_disk_health_check && echo "$_dh_status: $_dh_reason"
kzm2_disk_health_check() {
    _dh_status="PASS"
    _dh_reason=""
    # Read-only kontrolu (FAIL)
    if mount 2>/dev/null | grep -q "on /opt .*ro,"; then
        _dh_status="FAIL"
        _dh_reason="ro"
        return 0
    fi
    # /opt'un bagli oldugu cihazi bul (sda1, ubi0 vb.)
    local _dev_full _dev_base _is_usb
    _dev_full="$(mount 2>/dev/null | awk '/on \/opt /{print $1}' | sed 's|/dev/||' | head -1)"
    _dev_base="$(printf '%s' "$_dev_full" | sed 's/[0-9]*$//')"
    # USB depolama cihazi mi? (dmesg'de usb-storage + dev adi geciyorsa)
    _is_usb=0
    [ -n "$_dev_base" ] && dmesg 2>/dev/null | grep -q "usb-storage.*${_dev_base}" && _is_usb=1
    if [ -n "$_dev_full" ]; then
        # Kritik I/O hatasi (FAIL)
        if dmesg 2>/dev/null | grep -q "critical medium error.*dev ${_dev_base}"; then
            _dh_status="FAIL"
            _dh_reason="io_error"
            return 0
        fi
        # EXT4 journal hatasi (WARN)
        if dmesg 2>/dev/null | grep -q "EXT4-fs (${_dev_full}): error loading journal"; then
            _dh_status="WARN"
            _dh_reason="journal_error"
            return 0
        fi
        # USB baglantisi koptu (WARN) — sadece USB cihazlarda
        if [ "$_is_usb" = "1" ] && dmesg 2>/dev/null | grep -q "USB disconnect"; then
            _dh_status="WARN"
            _dh_reason="usb_disconnect"
            return 0
        fi
        # USB protokol hatasi (WARN) — sadece USB cihazlarda
        if [ "$_is_usb" = "1" ] && dmesg 2>/dev/null | grep -q "USBDEVFS_CONTROL failed"; then
            _dh_status="WARN"
            _dh_reason="usb_proto"
            return 0
        fi
    fi
    return 0
}

add_ipset_nfqueue_rules() {
    local WAN="$(get_wan_if)"
    local Q="${1:-300}"
    local tcp_out="6" tcp_in="4" udp_out="3" _v
    [ -z "$WAN" ] && WAN=""

    # Zapret2 default paket limitlerini koru. Aksi halde secili IP modunda
    # baglantinin tum paketleri NFQUEUE'ya girer ve qlen sisebilir.
    if [ -f /opt/zapret2/config ]; then
        _v="$(grep '^NFQWS2_TCP_PKT_OUT=' /opt/zapret2/config 2>/dev/null | cut -d= -f2 | tr -d '"[:space:]')"
        echo "$_v" | grep -qE '^[0-9]+$' && tcp_out="$_v"
        _v="$(grep '^NFQWS2_TCP_PKT_IN=' /opt/zapret2/config 2>/dev/null | cut -d= -f2 | tr -d '"[:space:]')"
        echo "$_v" | grep -qE '^[0-9]+$' && tcp_in="$_v"
        _v="$(grep '^NFQWS2_UDP_PKT_OUT=' /opt/zapret2/config 2>/dev/null | cut -d= -f2 | tr -d '"[:space:]')"
        echo "$_v" | grep -qE '^[0-9]+$' && udp_out="$_v"
    fi

    local _nozapret_dst="" _nozapret_src="" _mark_excl=""
    ipset list nozapret >/dev/null 2>&1 && \
        _nozapret_dst="-m set ! --match-set nozapret dst" && \
        _nozapret_src="-m set ! --match-set nozapret src"
    _mark_excl="-m mark ! --mark 0x40000000/0x40000000"

    # Sadece secili istemciler icin; connbytes ile yalnizca ilk paketleri isle.
    iptables -t mangle -I POSTROUTING 1 ${WAN:+-o $WAN} -p udp -m multiport --dports 443 \
        $_mark_excl \
        -m set --match-set "$IPSET_CLIENT_NAME" src \
        -m connbytes --connbytes 1:$udp_out --connbytes-dir original --connbytes-mode packets \
        $_nozapret_dst \
        -j NFQUEUE --queue-num "$Q" --queue-bypass >/dev/null 2>&1
    iptables -t mangle -I POSTROUTING 1 ${WAN:+-o $WAN} -p tcp -m multiport --dports 80,443 \
        $_mark_excl \
        -m set --match-set "$IPSET_CLIENT_NAME" src \
        -m connbytes --connbytes 1:$tcp_out --connbytes-dir original --connbytes-mode packets \
        $_nozapret_dst \
        -j NFQUEUE --queue-num "$Q" --queue-bypass >/dev/null 2>&1
    iptables -I INPUT 1 ${WAN:+-i $WAN} -p tcp -m multiport --sports 80,443 \
        -m set --match-set "$IPSET_CLIENT_NAME" dst \
        -m connbytes --connbytes 1:$tcp_in --connbytes-dir reply --connbytes-mode packets \
        $_nozapret_src \
        -j NFQUEUE --queue-num "$Q" --queue-bypass >/dev/null 2>&1
    iptables -I FORWARD 1 ${WAN:+-i $WAN} -p tcp -m multiport --sports 80,443 \
        -m set --match-set "$IPSET_CLIENT_NAME" dst \
        -m connbytes --connbytes 1:$tcp_in --connbytes-dir reply --connbytes-mode packets \
        $_nozapret_src \
        -j NFQUEUE --queue-num "$Q" --queue-bypass >/dev/null 2>&1
    # UDP incoming: zapret-auto.lua QUIC icin gelen yanitlara da bakmali
    local udp_in="3"
    [ -f /opt/zapret2/config ] && {
        _v="$(grep '^NFQWS2_UDP_PKT_IN=' /opt/zapret2/config 2>/dev/null | cut -d= -f2 | tr -d '"[:space:]')"
        echo "$_v" | grep -qE '^[0-9]+$' && udp_in="$_v"
    }
    iptables -I FORWARD 1 ${WAN:+-i $WAN} -p udp -m multiport --sports 443 \
        -m set --match-set "$IPSET_CLIENT_NAME" dst \
        -m connbytes --connbytes 1:$udp_in --connbytes-dir reply --connbytes-mode packets \
        $_nozapret_src \
        -j NFQUEUE --queue-num "$Q" --queue-bypass >/dev/null 2>&1
    # FIN/RST giden: nfqws2 conntrack'in baglanti kapanisini bilmesi icin.
    # NOT: Sunucudan gelen RST (FORWARD incoming) eklenmez — DPI RST ile karisip
    # bypass'i bozabilir.
    iptables -t mangle -I POSTROUTING 1 ${WAN:+-o $WAN} -p tcp -m multiport --dports 80,443 \
        $_mark_excl \
        -m set --match-set "$IPSET_CLIENT_NAME" src \
        --tcp-flags FIN FIN \
        $_nozapret_dst \
        -j NFQUEUE --queue-num "$Q" --queue-bypass >/dev/null 2>&1
    iptables -t mangle -I POSTROUTING 1 ${WAN:+-o $WAN} -p tcp -m multiport --dports 80,443 \
        $_mark_excl \
        -m set --match-set "$IPSET_CLIENT_NAME" src \
        --tcp-flags RST RST \
        $_nozapret_dst \
        -j NFQUEUE --queue-num "$Q" --queue-bypass >/dev/null 2>&1
}
del_ipset_nfqueue_rules() {
    # Eski connbytes'siz ve yeni connbytes'li tum zapret2_clients NFQUEUE
    # kurallarini dinamik sil. Global Zapret2 kurallarina dokunma.
    iptables -t mangle -S 2>/dev/null | grep -F "match-set $IPSET_CLIENT_NAME" | grep -F ' -j NFQUEUE' | while IFS= read -r rule; do
        del="$(echo "$rule" | sed 's/^-A /-D /')"
        iptables -t mangle $del >/dev/null 2>&1
    done
    iptables -S 2>/dev/null | grep -F "match-set $IPSET_CLIENT_NAME" | grep -F ' -j NFQUEUE' | while IFS= read -r rule; do
        del="$(echo "$rule" | sed 's/^-A /-D /')"
        iptables $del >/dev/null 2>&1
    done
}
enforce_client_mode_rules() {
    # start-fw bazen genel (tum ag) NFQUEUE kurallarini basabiliyor.
    # MODE=list ise: tum qnum=300 NFQUEUE'leri temizle ve sadece ipset kurallarini bas.
    # MODE=all  ise: ipset'e bagli kurallari temizle (genel kalsin).
    local mode="$(get_client_mode)"
    local Q="300"
    command -v iptables >/dev/null 2>&1 || return 0
    if [ "$mode" = "list" ]; then
        flush_all_nfqueue_rules "$Q"
        ipset_ensure_and_load_clients || true
        add_ipset_nfqueue_rules "$Q"
        # Uygulanan connbytes degerlerini logla (debug icin)
        local _wan _tcp_out _tcp_in _udp_out
        _wan="$(get_wan_if)"
        _tcp_out="$(grep '^NFQWS2_TCP_PKT_OUT=' /opt/zapret2/config 2>/dev/null | cut -d= -f2 | tr -d '"[:space:]')"
        _tcp_in="$(grep '^NFQWS2_TCP_PKT_IN=' /opt/zapret2/config 2>/dev/null | cut -d= -f2 | tr -d '"[:space:]')"
        _udp_out="$(grep '^NFQWS2_UDP_PKT_OUT=' /opt/zapret2/config 2>/dev/null | cut -d= -f2 | tr -d '"[:space:]')"
        [ -z "$_tcp_out" ] && _tcp_out="6"
        [ -z "$_tcp_in" ] && _tcp_in="4"
        [ -z "$_udp_out" ] && _udp_out="3"
        healthmon_log "$(date '+%Y-%m-%d %H:%M:%S') | client_rules_applied | mode=list | wan=${_wan:-any} | tcp_out=$_tcp_out | tcp_in=$_tcp_in | udp_out=$_udp_out"
    else
        # all modda ipset hedefli kurallari temizle
        del_ipset_nfqueue_rules >/dev/null 2>&1
        healthmon_log "$(date '+%Y-%m-%d %H:%M:%S') | client_rules_applied | mode=all | ipset_rules_removed"
    fi
    # nozapret RETURN kurali --netfilter-hook handler ve start_zapret2 icinde uygulanir.
}
# Cekirdek modulu yapilandirmasini gunceller
# TR/EN Dictionary (WAN Interface Selection & Cleanup)
TXT_WAN_SEL_TITLE_TR="Zapret2 cikis arayuzu secimi"
TXT_WAN_SEL_TITLE_EN="Zapret2 output interface selection"
TXT_WAN_SEL_EXAMPLE_TR=" (Ornek: ppp0 = WAN, wg0/wg1 = WireGuard)"
TXT_WAN_SEL_EXAMPLE_EN=" (Example: ppp0 = WAN, wg0/wg1 = WireGuard)"
TXT_WAN_SEL_CURRENT_TR=" Su Anki:"
TXT_WAN_SEL_CURRENT_EN=" Current:"
TXT_WAN_SEL_RECOMMENDED_TR=" Onerilen:"
TXT_WAN_SEL_RECOMMENDED_EN=" Recommended:"
TXT_WAN_SEL_PROMPT_TR="Arayuz adini yazin (Enter = %REC%): "
TXT_WAN_SEL_PROMPT_EN="Enter interface name (Enter = %REC%): "
TXT_WAN_SEL_SELECTED_TR="Secildi:"
TXT_WAN_SEL_SELECTED_EN="Selected:"
TXT_CLEANUP_REMOVING_TR="Indirilen Zapret2 arsivi ve gereksiz binary dosyalari siliniyor..."
TXT_CLEANUP_REMOVING_EN="Removing downloaded Zapret2 archive and unnecessary binary files..."
TXT_CLEANUP_REMOVED_TR="Indirilen Zapret2 arsivi ve gereksiz binary dosyalari silindi."
TXT_CLEANUP_REMOVED_EN="Downloaded Zapret2 archive and unnecessary binary files removed."
# TR/EN Dictionary (Kernel & Firewall & Zapret2 Service)
TXT_KERN_MOD_ADD_FAIL_TR="HATA: Kernel modulu yukleme dosyasina eklenemedi."
TXT_KERN_MOD_ADD_FAIL_EN="ERROR: Failed to write to kernel module load file."
TXT_KERN_MOD_CHMOD_FAIL_TR="HATA: Kernel modulu yukleme dosyasina calistirma izni verilemedi."
TXT_KERN_MOD_CHMOD_FAIL_EN="ERROR: Failed to set execute permission on kernel module load file."
TXT_KERN_MOD_OK_TR="Kernel modulu yukleme dosyasina eklendi."
TXT_KERN_MOD_OK_EN="Kernel module load file updated."
TXT_FW_WRITE_FAIL_TR="HATA: Guvenlik duvari izni verilirken hata olustu."
TXT_FW_WRITE_FAIL_EN="ERROR: Failed to write firewall permission file."
TXT_FW_CHMOD_FAIL_TR="HATA: Guvenlik duvari izni dosyasina calistirma izni verilemedi."
TXT_FW_CHMOD_FAIL_EN="ERROR: Failed to set execute permission on firewall file."
TXT_FW_OK_TR="Guvenlik duvari izni verildi."
TXT_FW_OK_EN="Firewall permission granted."
TXT_AUTOSTART_OK_TR="Zapret2 otomatik baslatma etkinlestirildi."
TXT_AUTOSTART_OK_EN="Zapret2 autostart enabled."
TXT_AUTOSTART_FAIL_TR="UYARI: Zapret2 otomatik baslatma etkinlestirilemedi."
TXT_AUTOSTART_FAIL_EN="WARNING: Failed to enable Zapret2 autostart."
TXT_TOTAL_PKT_FAIL_TR="HATA: Toplam paket kontrolu devre disi birakilirken hata olustu."
TXT_TOTAL_PKT_FAIL_EN="ERROR: Failed to disable total packet check."
TXT_TOTAL_PKT_CHMOD_FAIL_TR="HATA: Toplam paket kontrolu devre disi birakma dosyasina calistirma izni verilemedi."
TXT_TOTAL_PKT_CHMOD_FAIL_EN="ERROR: Failed to set execute permission on total packet disable file."
TXT_COMPAT_FAIL_TR="HATA: Keenetic icin uyumlu hale getirilemedi."
TXT_COMPAT_FAIL_EN="ERROR: Failed to apply Keenetic compatibility settings."
TXT_UDP_FIX_FAIL_TR="HATA: Keenetic UDP duzeltmesi eklenemedi."
TXT_UDP_FIX_FAIL_EN="ERROR: Failed to apply Keenetic UDP fix."
TXT_START_NOT_INSTALLED_TR="Zapret2 yuklu degil. Baslatma islemi yapilamiyor."
TXT_START_NOT_INSTALLED_EN="Zapret2 is not installed. Cannot start."
TXT_START_ALREADY_TR="Zapret2 servisi zaten calisiyor."
TXT_START_ALREADY_EN="Zapret2 service is already running."
TXT_START_OK_TR="Zapret2 servisi baslatildi."
TXT_START_OK_EN="Zapret2 service started."
TXT_START_FAIL_TR="HATA: Zapret2 servisi baslatilirken hata olustu."
TXT_START_FAIL_EN="ERROR: Failed to start Zapret2 service."
TXT_STOP_NOT_INSTALLED_TR="Zapret2 yuklu degil. Durdurma islemi yapilamiyor."
TXT_STOP_NOT_INSTALLED_EN="Zapret2 is not installed. Cannot stop."
TXT_STOP_STOPPING_TR="Zapret2 durduruluyor (NFQWS2 + NFQUEUE)..."
TXT_STOP_STOPPING_EN="Stopping Zapret2 (NFQWS2 + NFQUEUE)..."
TXT_STOP_NFQWS_WARN_TR="UYARI: nfqws2 hala calisiyor (otomatik yeniden baslatiliyor olabilir)."
TXT_STOP_NFQWS_WARN_EN="WARNING: nfqws2 is still running (may be auto-restarting)."
TXT_STOP_NFQUEUE_WARN_TR="UYARI: NFQUEUE kurali hala var (otomatik yeniden basiliyor olabilir)."
TXT_STOP_NFQUEUE_WARN_EN="WARNING: NFQUEUE rule still exists (may be auto-restarting)."
TXT_STOP_OK_TR="Zapret2 durduruldu."
TXT_STOP_OK_EN="Zapret2 stopped."
TXT_RESTART_NOT_INSTALLED_TR="Zapret2 yuklu degil. Yeniden baslatma islemi yapilamiyor."
TXT_RESTART_NOT_INSTALLED_EN="Zapret2 is not installed. Cannot restart."
TXT_ZAPRET_NOT_INSTALLED_TR="HATA: Zapret2 yuklu degil."
TXT_ZAPRET_NOT_INSTALLED_EN="ERROR: Zapret2 is not installed."
TXT_IPV6_NOT_INSTALLED_TR="HATA: Zapret2 yuklu degil. Once kurulum yapin."
TXT_IPV6_NOT_INSTALLED_EN="ERROR: Zapret2 is not installed. Please install first."
TXT_IPV6_WIZARD_START_TR="Zapret2 yapilandirma sihirbazi calistiriliyor (IPv6: %VAL%)..."
TXT_IPV6_WIZARD_START_EN="Running Zapret2 configuration wizard (IPv6: %VAL%)..."
TXT_IPV6_CFG_FAIL_TR="HATA: Zapret2 yapilandirma betigi calistirilirken hata olustu."
TXT_IPV6_CFG_FAIL_EN="ERROR: Failed to run Zapret2 configuration script."
TXT_UNINSTALL_NOT_INSTALLED_TR="Zapret2 yuklu degil. Kaldirma islemi yapilamaz."
TXT_UNINSTALL_NOT_INSTALLED_EN="Zapret2 is not installed. Nothing to remove."
TXT_UNINSTALL_REMOVING_TR="Zapret2 kaldiriliyor..."
TXT_UNINSTALL_REMOVING_EN="Removing Zapret2..."
TXT_UNINSTALL_OK_TR="Zapret2 basariyla kaldirildi."
TXT_UNINSTALL_OK_EN="Zapret2 removed successfully."
TXT_INSTALL_ALREADY_TR="Zapret2 zaten yuklu."
TXT_INSTALL_ALREADY_EN="Zapret2 is already installed."
TXT_INSTALL_INSTALLING_TR="Zapret2 yukleniyor..."
TXT_INSTALL_INSTALLING_EN="Installing Zapret2..."
TXT_INSTALL_OK_TR="Zapret2 basariyla yuklendi."
TXT_INSTALL_OK_EN="Zapret2 installed successfully."
TXT_INSTALL_DONE_TR="Zapret2 basariyla kuruldu ve yapilandirildi."
TXT_INSTALL_DONE_EN="Zapret2 successfully installed and configured."
TXT_INSTALL_PKG_FAIL_TR="HATA: Gerekli paketler yuklenemedi veya guncellenemedi."
TXT_INSTALL_PKG_FAIL_EN="ERROR: Failed to install or update required packages."
TXT_INSTALL_CFG_FAIL_TR="HATA: Zapret2 yapilandirma betigi calistirilirken hata olustu."
TXT_INSTALL_CFG_FAIL_EN="ERROR: Failed to run Zapret2 configuration script."
TXT_INSTALL_COMPAT_WARN_TR="UYARI: Keenetic uyumlulugu ayarlanirken bir sorun olustu."
TXT_INSTALL_COMPAT_WARN_EN="WARNING: An issue occurred while applying Keenetic compatibility settings."
TXT_INSTALL_CFG_RUNNING_TR="Zapret2 yapilandirma betigi calistiriliyor..."
TXT_INSTALL_CFG_RUNNING_EN="Running Zapret2 configuration script..."
TXT_INSTALL_KEENETIC_CFG_TR="Zapret2'nin Keenetic cihazlarda calisabilmesi icin gerekli yapilandirmalar yapiliyor..."
TXT_INSTALL_KEENETIC_CFG_EN="Applying required configurations for Zapret2 to run on Keenetic devices..."
# Zapret2 icin gerekli kernel modullerini yukler
# Bazi cihazlarda OPKG yeniden kurulumundan sonra modprobe yolu bozuk olabilir
# Bu fonksiyon /lib/modules/ altindan insmod ile yuklemeyi dener
kzm2_load_zapret2_kmods() {
    local _kver _dir _m
    _kver="$(uname -r)"
    _dir="/lib/modules/${_kver}"
    for _m in \
        ip_set \
        ip_set_hash_ip \
        ip_set_hash_net \
        ip_set_bitmap_port \
        nfnetlink \
        nfnetlink_queue \
        xt_set \
        xt_multiport \
        xt_connbytes \
        xt_mark \
        xt_NFQUEUE
    do
        lsmod 2>/dev/null | awk '{print $1}' | grep -qx "$_m" && continue
        insmod "${_dir}/${_m}.ko" >/dev/null 2>&1 || modprobe "$_m" >/dev/null 2>&1
    done
    # bitmap:port testi — temel kontrol
    ipset destroy _kzm2_bmp_test 2>/dev/null
    if ! ipset create _kzm2_bmp_test bitmap:port range 0-65535 2>/dev/null; then
        ipset destroy _kzm2_bmp_test 2>/dev/null
        return 1
    fi
    ipset destroy _kzm2_bmp_test 2>/dev/null
    return 0
}
update_kernel_module_config() {
    # Idempotent kontrol — zaten eklenmisse tekrar ekleme
    if grep -q "KZM2_KERNEL_MODULES_BEGIN" /opt/zapret2/init.d/sysv/zapret2 2>/dev/null; then
        echo "$(T TXT_KERN_MOD_OK)"
        return 0
    fi
    awk '
      BEGIN { inserted=0 }
      {
        print $0
        if (!inserted && $0 == "{") {
          getline nextline
          if (prev_line == "do_start()") {
            print "    # KZM2_KERNEL_MODULES_BEGIN"
            print "    for _m in ip_set ip_set_hash_ip ip_set_hash_net ip_set_bitmap_port nfnetlink nfnetlink_queue xt_set xt_multiport xt_connbytes xt_mark; do"
            print "        lsmod | sed -n \"s/ .*//p\" | grep -qx \"${_m}\" && continue"
            print "        insmod /lib/modules/$(uname -r)/${_m}.ko &> /dev/null || modprobe \"${_m}\" &> /dev/null || true"
            print "    done"
            print ""
            print "    if lsmod | grep \"xt_NFQUEUE \" &> /dev/null ;  then"
            print "        echo \"xt_NFQUEUE.ko is already loaded\""
            print "    else"
            print "        if insmod /lib/modules/$(uname -r)/xt_NFQUEUE.ko &> /dev/null; then"
            print "            echo \"xt_NFQUEUE.ko loaded\""
            print "        else"
            print "            echo \"Cannot find xt_NFQUEUE.ko kernel module, aborting\""
            print "            exit 1"
            print "        fi"
            print "    fi"
            print ""
            print "    # KZM2_KERNEL_MODULES_END"
            inserted=1
          }
          print nextline
        }
        prev_line = $0
      }
    ' /opt/zapret2/init.d/sysv/zapret2 > /tmp/zapret_new && mv /tmp/zapret_new /opt/zapret2/init.d/sysv/zapret2 || {
        echo "$(T TXT_KERN_MOD_ADD_FAIL)"
        return 1
    }
    chmod +x /opt/zapret2/init.d/sysv/zapret2 || {
        echo "$(T TXT_KERN_MOD_CHMOD_FAIL)"
        return 1
    }
    # Marker dogrulamasi — blok gercekten eklendi mi?
    if ! grep -q "KZM2_KERNEL_MODULES_BEGIN" /opt/zapret2/init.d/sysv/zapret2 2>/dev/null; then
        echo "$(T TXT_KERN_MOD_ADD_FAIL)"
        return 1
    fi
    echo "$(T TXT_KERN_MOD_OK)"
    return 0
}
# NFQWS parametrelerini gunceller
update_nfqws_parameters() {
    local profile="$(get_dpi_profile)"
    local ipv6="n"
    # Source of truth for Zapret2 IPv6 support is /opt/zapret2/config:
    #   DISABLE_IPV6=0 -> IPv6 support ON
    #   DISABLE_IPV6=1 -> IPv6 support OFF
    # Do not rely on NFQWS2_OPT/ip6_ttl or ip6tables runtime state here.
    _zapret2_ipv6_enabled 2>/dev/null && ipv6="y"
    # Kapsam modu: global (tum ag) | smart (yalnizca listeler/auto)
    local scope="$(get_scope_mode)"
    local mf="$(get_mode_filter)"
    local HOST_MARKER=""
    case "$mf" in
        hostlist|autohostlist)
            # Zapret2 expands <HOSTLIST> to --hostlist/--hostlist-auto according to MODE_FILTER.
            # MODE_FILTER alone is not enough; without this marker autohostlist never attaches.
            HOST_MARKER="<HOSTLIST>"
            ;;
        *)
            # Smart scope also needs hostlist/autohostlist placeholders for filtered operation.
            [ "$scope" = "smart" ] && HOST_MARKER="<HOSTLIST>"
            ;;
    esac

    # Zapret2 / nfqws2 calisan format:
    #   --filter-l7 + --payload + --lua-desync=fake:blob=...:ip_ttl=N:repeats=N
    # Sadece --lua-desync=fake:ip_ttl=N syntax olarak calisir ama pratikte etkisiz kalabiliyor.
    local TTL="2"
    local TCP_EXTRA=""
    local UDP_EXTRA=""
    local TCP_DESYNC="fake"
    local UDP_DESYNC="fake"
    local TCP_REPEATS="1"
    local UDP_REPEATS="6"
    local SPLITPOS=""
    local AUTO_PARAMS=""

    if [ "$profile" = "blockcheck_auto" ] && [ -s "$BLOCKCHECK_AUTO_PARAMS_FILE" ]; then
        AUTO_PARAMS="$(cat "$BLOCKCHECK_AUTO_PARAMS_FILE" 2>/dev/null | tr '\n' ' ' | sed 's/^ *//; s/ *$//')"
        AUTO_PARAMS="$(echo "$AUTO_PARAMS" | sed 's/^nfqws2\{0,1\}[[:space:]]\+//')"
    fi

    case "$profile" in
        tt_default)         TTL="2" ;;
        tt_fiber)           TTL="2" ;;
        superonline_fiber)  TTL="6"; TCP_DESYNC="hostcase"; NO_UDP="1" ;;
        blockcheck_auto) : ;;
        custom)          : ;;
        none)            : ;;
        # Legacy KZM1 profiles are disabled until explicitly converted/tested for Zapret2.
        tt_alt|sol|sol_alt|sol_fiber|turkcell_mob|vodafone_mob)
                           TTL="2"; profile="tt_default" ;;
        *)                 TTL="2"; profile="tt_default" ;;
    esac

    # Fresh install / legacy migration guard:
    # get_dpi_profile() can default to tt_default even when dpi_profile file does not exist.
    # Persist that safe default so Web Panel/status JSON never shows Unknown on first install.
    local _raw_profile=""
    _raw_profile="$(cat "$DPI_PROFILE_FILE" 2>/dev/null | tr -d '\r\n')"
    case "$_raw_profile" in
        tt_default|tt_fiber|superonline_fiber|blockcheck_auto|custom) : ;;
        *) set_dpi_profile "$profile" ;;
    esac
    if [ ! -s "$DPI_PROFILE_ORIGIN_FILE" ]; then
        set_dpi_origin "manual"
    fi

    _kzm2_ttl_args() {
        local _ttl="$1" _s=""
        [ -n "$_ttl" ] && _s=":ip_ttl=${_ttl}"
        if [ "$ipv6" = "y" ] || [ "$ipv6" = "Y" ]; then
            [ -n "$_ttl" ] && _s="${_s}:ip6_ttl=${_ttl}"
        fi
        printf '%s' "$_s"
    }

    _kzm2_desync_http() {
        case "$TCP_DESYNC" in
            multisplit) printf '%s' "multisplit${SPLITPOS}$(_kzm2_ttl_args "$TTL")${TCP_EXTRA}" ;;
            hostcase)   printf '%s' "http_hostcase:spell=hoSt" ;;
            *)          printf '%s' "fake:blob=fake_default_http$(_kzm2_ttl_args "$TTL"):repeats=${TCP_REPEATS}${TCP_EXTRA}" ;;
        esac
    }

    _kzm2_desync_tls() {
        if [ "$TCP_DESYNC" = "multisplit" ]; then
            printf '%s' "multisplit${SPLITPOS}$(_kzm2_ttl_args "$TTL")${TCP_EXTRA}"
        else
            printf '%s' "fake:blob=fake_default_tls$(_kzm2_ttl_args "$TTL"):repeats=${TCP_REPEATS}${TCP_EXTRA}"
        fi
    }

    _kzm2_desync_quic() {
        printf '%s' "fake:blob=fake_default_quic$(_kzm2_ttl_args "$TTL"):repeats=${UDP_REPEATS}${UDP_EXTRA}"
    }

    build_line() {
        # $1 proto(tcp/udp) $2 port(s) $3 l7 $4 payload $5 desync $6 extra endflag(--new or empty)
        local proto="$1" ports="$2" l7="$3" payload="$4" desync="$5" endflag="$6"
        local line="--filter-${proto}=${ports}"
        [ -n "$HOST_MARKER" ] && line="${line} ${HOST_MARKER}"
        if [ -n "$AUTO_PARAMS" ]; then
            # Blockcheck2 sonucu zaten nfqws2/lua parametreleri dondurur.
            line="${line} ${AUTO_PARAMS}"
        else
            [ -n "$l7" ] && line="${line} --filter-l7=${l7}"
            [ -n "$payload" ] && line="${line} --payload=${payload}"
            line="${line} --lua-desync=${desync}"
        fi
        [ -n "$endflag" ] && line="${line} ${endflag}"
        echo "$line"
    }

    local L1 L2 L3 AUTO_FULL
    AUTO_FULL=""
    # NO_UDP profillerde (superonline_fiber vb) UDP satiri eklenmez, L2 --new almaz
    local _l2_end="--new"
    [ "${NO_UDP:-0}" = "1" ] && _l2_end=""
    if [ "$profile" = "none" ]; then
        # Gecis modu: fake paket yok, trafik dogrudan gecsin
        NFQWS_BLOCK="NFQWS2_OPT=\"\""
        set_dpi_params ""
    elif [ "$profile" = "blockcheck_auto" ] && printf '%s' "$AUTO_PARAMS" | grep -q -- '--filter-'; then
        AUTO_FULL="$AUTO_PARAMS"
        AUTO_PARAMS=""
        # IPv6 aktifse blockcheck_auto params sadece ip_ttl=N iceriyor olabilir
        # (test IPVS=4 ile yapildi). ip6_ttl=N ekle ki IPv6 trafikte de DPI bypass calissin.
        if [ "$ipv6" = "y" ] || [ "$ipv6" = "Y" ]; then
            if ! printf '%s' "$AUTO_FULL" | grep -q ':ip6_ttl='; then
                AUTO_FULL="$(printf '%s' "$AUTO_FULL" | \
                    sed 's/:ip_ttl=\([0-9][0-9]*\)/:ip_ttl=\1:ip6_ttl=\1/g')"
            fi
        else
            # Menu 7 disables Zapret2 IPv6 by setting DISABLE_IPV6=1.
            # Blockcheck params may have been saved while IPv6 was ON, so
            # remove stale ip6_ttl immediately when rebuilding NFQWS2_OPT.
            AUTO_FULL="$(printf '%s' "$AUTO_FULL" | sed 's/:ip6_ttl=[0-9][0-9]*//g')"
        fi
        # Keep saved auto params normalized with current Menu 7 IPv6 state.
        printf "%s
" "$AUTO_FULL" > "$BLOCKCHECK_AUTO_PARAMS_FILE" 2>/dev/null
    fi
    if [ "$profile" != "none" ]; then
    L1="$(build_line tcp 80  http http_req          "$(_kzm2_desync_http)" "--new")"
    L2="$(build_line tcp 443 tls  tls_client_hello "$(_kzm2_desync_tls)"  "$_l2_end")"
    if [ "${NO_UDP:-0}" = "1" ]; then
        L3=""
    else
        L3="$(build_line udp 443 quic quic_initial     "$(_kzm2_desync_quic)" "")"
    fi
    if [ -n "$AUTO_FULL" ]; then
        # AUTO_FULL already contains complete HTTP + TLS + QUIC filter chain.
        # It must be written as a single quoted NFQWS2_OPT value.  Older
        # KZM2 builds missed the quotes here, so zapret2 parsed the config
        # incorrectly after Blockcheck > Apply.
        # Keep hostlist/autohostlist alive: inject <HOSTLIST> after each filter if missing.
        if [ -n "$HOST_MARKER" ] && ! printf '%s' "$AUTO_FULL" | grep -q '<HOSTLIST>'; then
            AUTO_FULL="$(printf '%s' "$AUTO_FULL" | sed 's/--filter-tcp=80/--filter-tcp=80 <HOSTLIST>/g; s/--filter-tcp=443/--filter-tcp=443 <HOSTLIST>/g; s/--filter-udp=443/--filter-udp=443 <HOSTLIST>/g')"
        fi
        NFQWS_BLOCK="NFQWS2_OPT=\"${AUTO_FULL} \""
    else
        NFQWS_BLOCK="NFQWS2_OPT=\"${L1} ${L2} ${L3} \""
    fi
    fi  # end if [ "$profile" != "none" ]

    # Keep SSH/Web Panel display in sync with the actual config we just generated.
    if [ "$profile" != "none" ]; then
    if [ -n "$AUTO_FULL" ]; then
        set_dpi_params "$AUTO_FULL"
    else
        set_dpi_params "${L1} ${L2} ${L3}"
    fi
    fi

    ensure_zapret_config >/dev/null 2>&1
    if [ ! -f /opt/zapret2/config ]; then
        echo "$(T nfqws_cfg_missing "UYARI: /opt/zapret2/config bulunamadi." "WARNING: /opt/zapret2/config not found.")"
        return 1
    fi
    # Config degisiklik logu: yazilmadan once eski degeri oku
    local _old_opt
    _old_opt="$(grep '^NFQWS2_OPT=' /opt/zapret2/config 2>/dev/null | cut -d'"' -f2)"
    local tmp="/tmp/zapret_config.$$"
    awk -v repl="$NFQWS_BLOCK" '
        BEGIN { cleanup=0 }
        /^NFQWS2_OPT="/ {
            print repl
            cleanup=1
            next
        }
        cleanup==1 {
            if ($0 ~ /"[[:space:]]*$/) cleanup=0
            next
        }
        { print }
    ' /opt/zapret2/config > "$tmp" && mv "$tmp" /opt/zapret2/config
    if grep -q '^NFQWS2_OPT="' /opt/zapret2/config 2>/dev/null; then
        # Config degisikligini healthmon log'a yaz
        local _new_opt
        _new_opt="$(grep '^NFQWS2_OPT=' /opt/zapret2/config 2>/dev/null | cut -d'"' -f2)"
        if [ "$_old_opt" != "$_new_opt" ]; then
            healthmon_log "$(date '+%Y-%m-%d %H:%M:%S') | dpi_profile_change | profile=$profile | scope=$(get_scope_mode) | new_opt=$_new_opt"
        fi
        echo "$(T nfqws_updated "NFQWS2 parametreleri basariyla guncellendi." "NFQWS2 parameters updated successfully.")"
        echo "$(T dpi_active "Aktif DPI Profili" "Active DPI Profile"): $(T dpi_ap "$(dpi_profile_name_tr "$profile")" "$(dpi_profile_name_en "$profile")")"
        return 0
    else
        echo "$(T nfqws_fail "UYARI: Guncelleme basarisiz oldu, dosyayi kontrol edin." "WARNING: Update failed, please check the file.")"
        return 1
    fi
}
# Netfilter scriptini gunceller
allow_firewall() {
    # Betik icerigini dosyaya yazar
    echo '#!/bin/sh
[ "$table" != "mangle" ] && [ "$table" != "nat" ] && exit 0
KZM2_SKIP_LOCK=1 sh /opt/lib/opkg/keenetic_zapret2_manager.sh --netfilter-hook >/dev/null 2>&1
exit 0' > /opt/etc/ndm/netfilter.d/000-zapret2.sh || {
        echo "$(T TXT_FW_WRITE_FAIL)"
        return 1
    }
    # Dosyayi calistirilabilir yapar
    chmod +x /opt/etc/ndm/netfilter.d/000-zapret2.sh || {
        echo "$(T TXT_FW_CHMOD_FAIL)"
        return 1
    }
    
    echo "$(T TXT_FW_OK)"
    return 0
}
# Check Keenetic components required for Zapret2
check_keenetic_components() {
    local missing_critical=0
    local missing_optional=0
    local all_components=""
    # PATH genislet: Entware ve sistem araclari her zaman erisilebilir olsun
    export PATH="/opt/sbin:/opt/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}"
    # opkg update tek seferlik - eksik paketler kurulmadan once liste guncellenmeli
    if command -v opkg >/dev/null 2>&1; then
        opkg update >/dev/null 2>&1
    fi
    
    echo ""
    echo "$(T TXT_COMP_CHECK_TITLE)"
    print_line "-"
    
    # 1. OPKG (Entware) - CRITICAL
    if check_opkg; then
        print_status PASS "$(T TXT_COMP_OPKG)"
    else
        print_status FAIL "$(T TXT_COMP_OPKG_REQ)"
        missing_critical=1
        all_components="${all_components}  - OPKG (Entware)\n"
    fi
    
    # 2. IPv6 Support - CRITICAL
    if command -v ip6tables >/dev/null 2>&1 && ip6tables --version >/dev/null 2>&1; then
        print_status PASS "$(T TXT_COMP_IPV6)"
    else
        # opkg ile otomatik kurulum dene
        print_status INFO "$(T _ 'ip6tables bulunamadi, opkg ile kuruluyor...' 'ip6tables not found, installing via opkg...')"
        opkg install iptables >/dev/null 2>&1
        if command -v ip6tables >/dev/null 2>&1 && ip6tables --version >/dev/null 2>&1; then
            print_status PASS "$(T TXT_COMP_IPV6)"
        else
            print_status FAIL "$(T TXT_COMP_IPV6_REQ)"
            missing_critical=1
            all_components="${all_components}  - $(T TXT_COMP_IPV6_SHORT)\n"
        fi
    fi
    
    # 3. iptables - CRITICAL
    if command -v iptables >/dev/null 2>&1 && iptables --version >/dev/null 2>&1; then
        print_status PASS "$(T TXT_COMP_IPTABLES)"
    else
        # opkg ile otomatik kurulum dene (ip6tables kontrolunden once gelmesi halinde)
        print_status INFO "$(T _ 'iptables bulunamadi, opkg ile kuruluyor...' 'iptables not found, installing via opkg...')"
        opkg install iptables >/dev/null 2>&1
        if command -v iptables >/dev/null 2>&1 && iptables --version >/dev/null 2>&1; then
            print_status PASS "$(T TXT_COMP_IPTABLES)"
        else
            print_status FAIL "$(T TXT_COMP_IPTABLES_REQ)"
            missing_critical=1
            all_components="${all_components}  - iptables\n"
        fi
    fi
    
    # 4. Netfilter kernel modules - CRITICAL
    # Zapret2'yin zorunlu tuttugu modul: xt_multiport
    # Tespit sirasi: lsmod > modinfo > /lib/modules *.ko dosyasi
    _nfmod_ok=0
    if lsmod 2>/dev/null | grep -qE "^xt_multiport"; then
        _nfmod_ok=1
    elif modinfo xt_multiport >/dev/null 2>&1; then
        _nfmod_ok=1
    elif find /lib/modules -name "xt_multiport.ko" 2>/dev/null | grep -q .; then
        _nfmod_ok=1
    fi
    if [ "$_nfmod_ok" -eq 1 ]; then
        print_status PASS "$(T TXT_COMP_NFQUEUE)"
    else
        print_status FAIL "$(T TXT_COMP_NFQUEUE_WARN)"
        missing_critical=1
        all_components="${all_components}  - $(T TXT_COMP_NFQUEUE)\n"
    fi
    
    # 5. curl or wget - CRITICAL
    if command -v curl >/dev/null 2>&1; then
        if curl --version >/dev/null 2>&1; then
            print_status PASS "$(T TXT_COMP_CURL)"
        else
            print_status WARN "$(T _ 'curl binary var ama calismiyor - libnghttp2 eksik olabilir.' 'curl binary exists but fails - libnghttp2 may be missing.')"
            opkg install libnghttp2 >/dev/null 2>&1
            if curl --version >/dev/null 2>&1; then
                print_status PASS "$(T TXT_COMP_CURL)"
            else
                print_status FAIL "$(T _ 'curl calismiyor! opkg install libnghttp2 calistiriniz.' 'curl not working! Run: opkg install libnghttp2')"
                missing_critical=1
                all_components="${all_components}  - libnghttp2\n"
            fi
        fi
    elif command -v wget >/dev/null 2>&1; then
        print_status PASS "$(T TXT_COMP_WGET)"
    else
        print_status INFO "$(T _ 'curl/wget bulunamadi, opkg ile kuruluyor...' 'curl/wget not found, installing via opkg...')"
        opkg install curl >/dev/null 2>&1
        if command -v curl >/dev/null 2>&1 && curl --version >/dev/null 2>&1; then
            print_status PASS "$(T TXT_COMP_CURL)"
        elif command -v wget >/dev/null 2>&1; then
            print_status PASS "$(T TXT_COMP_WGET)"
        else
            print_status FAIL "$(T TXT_COMP_CURL_REQ)"
            missing_critical=1
            all_components="${all_components}  - curl $(T TXT_COMP_OR) wget\n"
        fi
    fi
    
    # 6. ipset - CRITICAL
    if command -v ipset >/dev/null 2>&1 && ipset --version >/dev/null 2>&1; then
        print_status PASS "$(T TXT_COMP_IPSET)"
    else
        print_status INFO "$(T _ 'ipset bulunamadi, opkg ile kuruluyor...' 'ipset not found, installing via opkg...')"
        opkg install ipset >/dev/null 2>&1
        if command -v ipset >/dev/null 2>&1 && ipset --version >/dev/null 2>&1; then
            print_status PASS "$(T TXT_COMP_IPSET)"
        else
            print_status FAIL "$(T TXT_COMP_IPSET_REQ)"
            missing_critical=1
            all_components="${all_components}  - ipset\n"
        fi
    fi
    
    # 7. Xtables-addons - CRITICAL (Keenetic OPKG bileseni)
    # Eksik olursa zapret servisi baslatma hatasi verir
    # Tespit sirasi: opkg kaydi > /lib/modules *.ko > lsmod > xtables .so
    _xtables_ok=0
    if opkg list-installed 2>/dev/null | grep -q "^kmod-ipt-xtables-extra\|^xtables-addons"; then
        _xtables_ok=1
    elif find /lib/modules -name "xt_condition.ko" -o -name "xt_ipp2p.ko" \
         -o -name "xt_iface.ko" -o -name "xt_fuzzy.ko" 2>/dev/null | grep -q .; then
        _xtables_ok=1
    elif lsmod 2>/dev/null | grep -qE "^xt_condition|^xt_fuzzy|^xt_iface|^xt_ipp2p"; then
        _xtables_ok=1
    elif ls /lib/xtables/libxt_condition.so \
            /usr/lib/xtables/libxt_condition.so \
            /usr/lib/iptables/libxt_condition.so 2>/dev/null | grep -q .; then
        _xtables_ok=1
    fi
    if [ "$_xtables_ok" -eq 1 ]; then
        print_status PASS "$(T TXT_COMP_XTABLES)"
    else
        print_status FAIL "$(T TXT_COMP_XTABLES_WARN)"
        missing_critical=1
        all_components="${all_components}  - $(T TXT_COMP_XTABLES)\n"
    fi
    # 8. Traffic Control kernel modules - CRITICAL (Keenetic OPKG bileseni)
    # Eksik olursa zapret servisi baslatma hatasi verir
    # Tespit sirasi: opkg kaydi > /lib/modules *.ko > lsmod > tc komutu
    _tc_ok=0
    if opkg list-installed 2>/dev/null | grep -q "^kmod-sched\|^kmod-tc\|^kmod-trafik"; then
        _tc_ok=1
    elif find /lib/modules -name "sch_ingress.ko" -o -name "sch_htb.ko" \
         -o -name "sch_hfsc.ko" -o -name "cls_u32.ko" 2>/dev/null | grep -q .; then
        _tc_ok=1
    elif lsmod 2>/dev/null | grep -qiE "^sch_|^cls_|^ntc"; then
        _tc_ok=1
    elif command -v tc >/dev/null 2>&1; then
        _tc_ok=1
    fi
    if [ "$_tc_ok" -eq 1 ]; then
        print_status PASS "$(T TXT_COMP_TC)"
    else
        print_status WARN "$(T TXT_COMP_TC_WARN)"
    fi
    # 9. wget-ssl
    if opkg list-installed 2>/dev/null | grep -q '^wget-ssl'; then
        print_status PASS "$(T _ 'wget-ssl' 'wget-ssl')"
    else
        print_status WARN "$(T _ 'wget-ssl bulunamadi' 'wget-ssl not found')"
        missing_optional=1
    fi
    # 10. coreutils-sort
    if opkg list-installed 2>/dev/null | grep -q '^coreutils-sort'; then
        print_status PASS "$(T _ 'coreutils-sort' 'coreutils-sort')"
    else
        print_status WARN "$(T _ 'coreutils-sort bulunamadi' 'coreutils-sort not found')"
        missing_optional=1
    fi
    # 11. grep
    if command -v grep >/dev/null 2>&1; then
        if grep --version >/dev/null 2>&1; then
            print_status PASS "$(T _ 'grep' 'grep')"
        else
            print_status WARN "$(T _ 'grep binary var ama calismiyor - libpcre2 eksik olabilir (opkg install libpcre2).' 'grep binary exists but fails - libpcre2 may be missing (opkg install libpcre2).')"
            opkg install libpcre2 >/dev/null 2>&1
            if grep --version >/dev/null 2>&1; then
                print_status PASS "$(T _ 'grep (libpcre2 guncellendi)' 'grep (libpcre2 updated)')"
            else
                print_status WARN "$(T _ 'grep hala calismiyor - opkg install libpcre2 deneyin.' 'grep still failing - try: opkg install libpcre2.')"
                missing_optional=1
            fi
        fi
    else
        print_status WARN "$(T _ 'grep bulunamadi' 'grep not found')"
        missing_optional=1
    fi
    # 12. gzip
    if command -v gzip >/dev/null 2>&1; then
        print_status PASS "$(T _ 'gzip' 'gzip')"
    else
        print_status WARN "$(T _ 'gzip bulunamadi' 'gzip not found')"
        missing_optional=1
    fi
    # 13. cron
    if command -v crond >/dev/null 2>&1 || command -v cron >/dev/null 2>&1; then
        print_status PASS "$(T _ 'cron' 'cron')"
    else
        print_status WARN "$(T _ 'cron bulunamadi' 'cron not found')"
        missing_optional=1
    fi
    # 14. nfqws binary - sadece Zapret2 kuruluysa kontrol et
    if is_zapret2_installed; then
        if [ -x "/opt/zapret2/nfq2/nfqws2" ]; then
            print_status PASS "$(T _ 'nfqws2 binary' 'nfqws2 binary')"
        else
            print_status WARN "$(T _ 'nfqws2 binary bulunamadi - Zapret2 yeniden kurulumu onerilir' 'nfqws2 binary not found - Reinstalling Zapret2 is recommended')"
        fi
    fi
    # 10. Storage - OPTIONAL (for persistence)
    # Adim 1: /proc/mounts'ta /opt icin ayri bir mount satiri ara
    local _opt_line=""
    _opt_line=$(awk '$2=="/opt"{print; exit}' /proc/mounts 2>/dev/null)
    local opt_dev=""
    local opt_fstype=""
    if [ -n "$_opt_line" ]; then
        opt_dev=$(printf '%s' "$_opt_line" | awk '{print $1}')
        opt_fstype=$(printf '%s' "$_opt_line" | awk '{print $3}')
    fi
    # /dev/sdX icin removable flag kontrol: 1=USB(cikabilir), 0=dahili
    _is_usb_removable() {
        local _bdev
        _bdev=$(basename "$1" | sed 's/[0-9]*$//')
        local _removable=0
        if [ -f "/sys/block/${_bdev}/removable" ]; then
            _removable=$(cat "/sys/block/${_bdev}/removable" 2>/dev/null)
        fi
        [ "$_removable" = "1" ]
    }
    if [ -n "$opt_dev" ]; then
        # /opt ayri mount edilmis - device tipine gore karar ver
        if echo "$opt_dev" | grep -q "^/dev/sd"; then
            if _is_usb_removable "$opt_dev"; then
                print_status PASS "$(T TXT_COMP_STORAGE_USB)"
            else
                # Dahili /dev/sdX (bazi modellerde eMMC USB controller'a bagli)
                print_status INFO "$(T TXT_COMP_STORAGE_INTERNAL_SD)"
                echo "$(T TXT_COMP_STORAGE_EMMC_HINT)"
            fi
        elif echo "$opt_dev" | grep -q "^/dev/mmcblk"; then
            print_status INFO "$(T TXT_COMP_STORAGE_INTERNAL)"
            echo "$(T TXT_COMP_STORAGE_EMMC_HINT)"
        elif echo "$opt_dev" | grep -q "^/dev/nvme"; then
            print_status INFO "$(T TXT_COMP_STORAGE_NVME)"
        elif echo "$opt_fstype" | grep -qE "^tmpfs$"; then
            print_status WARN "$(T TXT_COMP_STORAGE_TMPFS)"
            missing_optional=1
        elif echo "$opt_fstype" | grep -qE "^(overlay|overlayfs|ubifs)$" || \
             echo "$opt_dev" | grep -qE "^(overlay|ubi[0-9])"; then
            print_status WARN "$(T TXT_COMP_STORAGE_INTERNAL_SD)"
            echo "$(T TXT_COMP_STORAGE_INTERNAL_HINT)"
            missing_optional=1
        else
            print_status PASS "$(T TXT_COMP_STORAGE_GENERIC)"
        fi
    else
        # Adim 2: /opt ayri mount degil - df ile rootfs mount noktasini kontrol et
        # df son sutunu (Mounted on): "/" ise /opt rootfs'in parcasi = dahili flash
        local _opt_mounton=""
        _opt_mounton=$(df -P /opt 2>/dev/null | awk 'NR==2{print $NF}')
        if [ "$_opt_mounton" = "/" ]; then
            # /opt, kok dizinin altinda bir klasor = Keenetic dahili flash
            print_status WARN "$(T TXT_COMP_STORAGE_INTERNAL_SD)"
            echo "$(T TXT_COMP_STORAGE_INTERNAL_HINT)"
            missing_optional=1
        elif [ -n "$_opt_mounton" ]; then
            # Mount var ama /proc/mounts'ta gorunmedi (edge case)
            print_status PASS "$(T TXT_COMP_STORAGE_GENERIC)"
        else
            # /opt mevcut degil veya tespit edilemedi
            print_status WARN "$(T TXT_COMP_STORAGE_REC)"
            missing_optional=1
        fi
    fi
    
    # ipset bitmap:port kernel modulu kontrolu
    if ipset create _kzm2_bmp_chk bitmap:port range 0-65535 2>/dev/null; then
        ipset destroy _kzm2_bmp_chk 2>/dev/null
        print_status PASS "$(T _ 'ipset bitmap:port kernel modulu' 'ipset bitmap:port kernel module')"
    else
        ipset destroy _kzm2_bmp_chk 2>/dev/null
        print_status WARN "$(T _ 'ipset bitmap:port modulu yuklu degil — kzm2_load_zapret2_kmods ile yukleniyor' 'ipset bitmap:port module not loaded — loading via kzm2_load_zapret2_kmods')"
        kzm2_load_zapret2_kmods 2>/dev/null
        if ipset create _kzm2_bmp_chk2 bitmap:port range 0-65535 2>/dev/null; then
            ipset destroy _kzm2_bmp_chk2 2>/dev/null
            print_status PASS "$(T _ 'ipset bitmap:port yuklendi' 'ipset bitmap:port loaded')"
        else
            ipset destroy _kzm2_bmp_chk2 2>/dev/null
            print_status FAIL "$(T _ 'ipset bitmap:port yuklenemedi — Zapret2 port kurallari eklenemeyebilir' 'ipset bitmap:port failed to load — Zapret2 port rules may not apply')"
            missing_critical=1
        fi
    fi

    print_line "-"

    if [ "$missing_critical" -eq 1 ]; then
        echo ""
        print_status FAIL "$(T TXT_COMP_CRIT_FAIL)"
        echo ""
        echo "$(T TXT_COMP_MISSING)"
        printf "$all_components"
        echo ""
        echo "$(T TXT_COMP_INSTALL_FROM)"
        echo "  $(T TXT_COMP_INSTALL_PATH)"
        echo ""
        echo "$(T TXT_COMP_REBOOT_WARN)"
        echo ""
        echo "$(T TXT_COMP_REQUIRED)"
        echo "  - OPKG"
        echo "  - $(T TXT_COMP_IPV6_SHORT)"
        echo "  - iptables"
        echo "  - ipset"
        echo "  - curl"
        echo "  - $(T TXT_COMP_XTABLES)"
        echo "  - $(T TXT_COMP_TC)"
        echo ""
        return 1
    elif [ "$missing_optional" -eq 1 ]; then
        echo ""
        print_status WARN "$(T TXT_COMP_OPT_WARN)"
        echo ""
        return 0
    else
        echo ""
        print_status PASS "$(T TXT_COMP_ALL_OK)"
        echo ""
        return 0
    fi
}
# Zapret2'yin otomatik baslamasini ayarlar
add_auto_start_zapret2() { # KZM2: opkg handles autostart
    ln -fs /opt/zapret2/init.d/sysv/zapret2 /opt/etc/init.d/S90-zapret2 && \
    echo "$(T TXT_AUTOSTART_OK)" || \
    { echo "$(T TXT_AUTOSTART_FAIL)"; return 0; }
}
# Total paket engellemeyi devre disi birakmayi ayarlar
disable_total_packet() {
    # Betik icerigini dosyaya yazar
    echo '#!/bin/sh
start() {
    sysctl -w net.netfilter.nf_conntrack_checksum=0 &> /dev/null
}
stop() {
    sysctl -w net.netfilter.nf_conntrack_checksum=1 &> /dev/null
}
case "$1" in
    '''start''')
        start
        ;;
    '''stop''')
        stop
        ;;
    *)
        stop
        start
        ;;
esac
exit 0' > /opt/etc/init.d/S00fix || {
        echo "$(T TXT_TOTAL_PKT_FAIL)"
        return 1
    }
    # Dosyayi calistirilabilir yapar
    chmod +x /opt/etc/init.d/S00fix || {
        echo "$(T TXT_TOTAL_PKT_CHMOD_FAIL)"
        return 1
    }
    
    echo "$(T _ 'Toplam paket kontrolu devre disi birakildi.' 'Total packet check disabled.')"
    return 0
}
# Keenetic uyumlulugunu etkinlestirir
keenetic_compatibility() {
    sed -i "s/^#WS_USER=nobody/WS_USER=nobody/" /opt/zapret2/config.default && \
    echo "$(T _ 'Keenetic icin uyumlu hale getirildi.' 'Keenetic compatibility applied.')" || \
    { echo "$(T TXT_COMPAT_FAIL)"; return 1; }
}
# Keenetic UDP duzeltmesini ekler
fix_keenetic_udp() {
    cp -af /opt/zapret2/init.d/custom.d.examples.linux/10-keenetic-udp-fix /opt/zapret2/init.d/sysv/custom.d/10-keenetic-udp-fix && \
    echo "$(T _ 'Keenetic UDP duzeltmesi eklendi.' 'Keenetic UDP fix applied.')" || \
    { echo "$(T TXT_UDP_FIX_FAIL)"; return 1; }
}

# Zapret2 Lua/binary permission fix
# nfqws2 drops privileges to nobody before loading Lua files.
# If /opt/zapret2 or lua directories are not traversable, nfqws2 exits with:
# "LUA file ... not accessible".
fix_zapret2_runtime_permissions() {
    # Permission hardening for nfqws2. nfqws2 runs with --user=nobody and
    # must be able to traverse /opt/zapret2 and read Lua/config files.
    [ -d /opt/zapret2 ] || return 0

    chmod 755 /opt /opt/zapret2 2>/dev/null

    if command -v find >/dev/null 2>&1; then
        find /opt/zapret2 -type d -exec chmod 755 {} \; 2>/dev/null
        find /opt/zapret2/lua -type f -name '*.lua' -exec chmod 644 {} \; 2>/dev/null
        find /opt/zapret2/lua -type f -name '*.lua.gz' -exec chmod 644 {} \; 2>/dev/null
        find /opt/zapret2/binaries -type d -exec chmod 755 {} \; 2>/dev/null
        find /opt/zapret2/binaries -type f -name 'nfqws2' -exec chmod 755 {} \; 2>/dev/null
        find /opt/zapret2 -type f -name '*.sh' -exec chmod 755 {} \; 2>/dev/null
        find /opt/zapret2/init.d -type f -exec chmod 755 {} \; 2>/dev/null
    else
        [ -d /opt/zapret2/lua ] && chmod 755 /opt/zapret2/lua 2>/dev/null
        [ -d /opt/zapret2/lua ] && chmod 644 /opt/zapret2/lua/*.lua /opt/zapret2/lua/*.lua.gz 2>/dev/null
        chmod 755 /opt/zapret2/nfq2 /opt/zapret2/binaries 2>/dev/null
        chmod 755 /opt/zapret2/binaries/* 2>/dev/null
        chmod 755 /opt/zapret2/binaries/*/nfqws2 2>/dev/null
        chmod 755 /opt/zapret2/*.sh /opt/zapret2/init.d/sysv/zapret2* 2>/dev/null
    fi

    chmod 755 /opt/zapret2/nfq2 /opt/zapret2/binaries 2>/dev/null
    chmod 755 /opt/zapret2/binaries/linux-arm64/nfqws2 2>/dev/null
    chmod 755 /opt/zapret2/init.d/sysv/zapret2 /opt/zapret2/init.d/sysv/zapret2.real 2>/dev/null
    chmod 644 /opt/zapret2/config /opt/zapret2/config.default /opt/zapret2/version 2>/dev/null
    # KZM2 durum dosyalari (nobody tarafindan okunabilmeli)
    chmod 644 /opt/zapret2/dpi_profile /opt/zapret2/dpi_profile_origin \
              /opt/zapret2/dpi_profile_params /opt/zapret2/blockcheck_auto_params \
              /opt/zapret2/hostlist_mode /opt/zapret2/scope_mode \
              /opt/zapret2/ipset_clients_mode /opt/zapret2/wan_if \
              /opt/zapret2/lang /opt/zapret2/theme 2>/dev/null
    chmod 644 /opt/zapret2/blockcheck_result.json 2>/dev/null
    # ipset dizini ve host listesi dosyalari (nobody tarafindan okunabilmeli)
    mkdir -p /opt/zapret2/ipset 2>/dev/null
    chmod 755 /opt/zapret2/ipset 2>/dev/null
    # Dosyalar restore'dan eksik gelebilir — garanti olustur
    touch /opt/zapret2/ipset/zapret-hosts-user.txt \
          /opt/zapret2/ipset/zapret-hosts-user-exclude.txt \
          /opt/zapret2/ipset/zapret-hosts-auto.txt 2>/dev/null
    chmod 644 /opt/zapret2/ipset/*.txt /opt/zapret2/ipset/*.gz 2>/dev/null
    # zapret-hosts-user.txt ve zapret-hosts-user-exclude.txt: root sahibi, nobody okuyabilmeli
    chown root /opt/zapret2/ipset/zapret-hosts-user.txt \
               /opt/zapret2/ipset/zapret-hosts-user-exclude.txt 2>/dev/null
    # zapret-hosts-auto.txt: nfqws2 hem okur hem yazar — nobody sahibi ve yaz izni olmali
    chown nobody /opt/zapret2/ipset/zapret-hosts-auto.txt 2>/dev/null
    chmod 664 /opt/zapret2/ipset/zapret-hosts-auto.txt 2>/dev/null
    # nfq2 dizinindeki binary calistirilabilir olmali
    chmod 755 /opt/zapret2/nfq2/nfqws2 2>/dev/null
    # /opt/etc/init.d/ icindeki KZM2 autostart scriptleri calistirilabilir olmali
    # (restore sonrasi izinleri bozulabilir)
    chmod 755 /opt/etc/init.d/S99kzm2_healthmon 2>/dev/null
    chmod 755 /opt/etc/init.d/S98kzm2_telegram 2>/dev/null
    chmod 755 /opt/etc/init.d/S90-zapret2 2>/dev/null
    return 0
}

# -------------------------------------------------------------------
# Zapret2 Calisma / Baslatma / Durdurma Yardimcilari
# -------------------------------------------------------------------
# (DURDUR modunda) otomatik yeniden baslamayi engellemek icin gecici bayrak.
# /tmp reboot ile temizlenir, yani router reboot edince otomatik baslatma devam eder.
ZAPRET_PAUSE_FLAG="/tmp/.zapret2_paused"
zapret_pause()  { : > "$ZAPRET_PAUSE_FLAG" 2>/dev/null; }
zapret_resume() { rm -f "$ZAPRET_PAUSE_FLAG" 2>/dev/null; }
install_zapret_pause_guard() {
    # /opt/zapret2/init.d/sysv/zapret2 wrapper'ina "pause" kontrolu ekler.
    # start/start-fw/restart/restart-fw cagrilari pause varken no-op olur.
    # stop her zaman calismaya devam eder.
    local Z="/opt/zapret2/init.d/sysv/zapret2"
    local R="/opt/zapret2/init.d/sysv/zapret2.real"
    [ -x "$Z" ] || return 0
    # Daha once wrapper yapilmadiysa yedekle
    if [ ! -f "$R" ]; then
        cp -f "$Z" "$R" 2>/dev/null || return 0
        chmod +x "$R" 2>/dev/null
    fi
    cat > "$Z" <<'EOF'
#!/opt/bin/sh
REAL="/opt/zapret2/init.d/sysv/zapret2.real"
PAUSE="/tmp/.zapret2_paused"
if [ -f "$PAUSE" ]; then
  case "$1" in
    start|start-fw|restart|restart-fw)
      exit 0
    ;;
    esac
fi
exec "$REAL" "$@"
EOF
    chmod 755 "$Z" 2>/dev/null || chmod +x "$Z" 2>/dev/null
    # chmod basarisiz olursa tekrar dene (filesystem gecikmesi olabilir)
    [ -x "$Z" ] || { sleep 1; chmod 755 "$Z" 2>/dev/null; }
}
# NFQUEUE kurallarini (genel + ipset) temizlemek icin line-number tabanli guvenli temizleyici
# BusyBox ortaminda awk sorun cikarmasin diye sed/head kullaniliyor.
flush_nfqueue_by_linenum() {
    local table="$1" chain="$2" ln
    while true; do
        if [ -n "$table" ]; then
            ln="$(iptables -t "$table" -L "$chain" -n --line-numbers 2>/dev/null \
                | sed -n "/NFQUEUE/{s/^ *\\([0-9]\\+\\).*/\\1/p; q}")"
            [ -n "$ln" ] || break
            iptables -t "$table" -D "$chain" "$ln" 2>/dev/null
        else
            ln="$(iptables -L "$chain" -n --line-numbers 2>/dev/null \
                | sed -n "/NFQUEUE/{s/^ *\\([0-9]\\+\\).*/\\1/p; q}")"
            [ -n "$ln" ] || break
            iptables -D "$chain" "$ln" 2>/dev/null
        fi
    done
}
flush_all_nfqueue_rules() {
    # Sadece queue 300 (zapret2) kurallarini temizle.
    # Keenetic'in kendi ndmmark/queue-64511 kurallarina DOKUNMA.
    command -v iptables >/dev/null 2>&1 || return 0
    local _chains_mangle="POSTROUTING PREROUTING OUTPUT INPUT FORWARD"
    local _chains_filter="INPUT FORWARD OUTPUT"
    local _r _del
    for _pass in 1 2; do
        for ch in $_chains_mangle; do
            iptables -t mangle -S "$ch" 2>/dev/null | grep -F -- "--queue-num 300" | grep -F -- "-j NFQUEUE" | while IFS= read -r _r; do
                _del="$(echo "$_r" | sed 's/^-A /-D /')"
                iptables -t mangle $_del >/dev/null 2>&1
            done
        done
        for ch in $_chains_filter; do
            iptables -S "$ch" 2>/dev/null | grep -F -- "--queue-num 300" | grep -F -- "-j NFQUEUE" | while IFS= read -r _r; do
                _del="$(echo "$_r" | sed 's/^-A /-D /')"
                iptables $_del >/dev/null 2>&1
            done
        done
    done
}
flush_all_ip6tables_nfqueue_rules() {
    command -v ip6tables >/dev/null 2>&1 || return 0
    local _chains_mangle="POSTROUTING PREROUTING OUTPUT INPUT FORWARD"
    local _chains_filter="INPUT FORWARD OUTPUT"
    local _r _del
    for _pass in 1 2; do
        for ch in $_chains_mangle; do
            ip6tables -t mangle -S "$ch" 2>/dev/null | grep -F -- "--queue-num 300" | grep -F -- "-j NFQUEUE" | while IFS= read -r _r; do
                _del="$(echo "$_r" | sed 's/^-A /-D /')"
                ip6tables -t mangle $_del >/dev/null 2>&1
            done
        done
        for ch in $_chains_filter; do
            ip6tables -S "$ch" 2>/dev/null | grep -F -- "--queue-num 300" | grep -F -- "-j NFQUEUE" | while IFS= read -r _r; do
                _del="$(echo "$_r" | sed 's/^-A /-D /')"
                ip6tables $_del >/dev/null 2>&1
            done
        done
    done
}
# Zapret2 servisinin calisip calismadigini kontrol eder (nfqws prosesine gore)
is_zapret2_running() {
    [ "$(cat /opt/zapret2/dpi_profile 2>/dev/null | tr -d '[:space:]')" = "none" ] && return 0
    pidof nfqws2 >/dev/null 2>&1 && return 0
    pgrep -f "/opt/zapret2/.*/nfqws2" >/dev/null 2>&1 && return 0
    ps w 2>/dev/null | grep -F '/opt/zapret2/' | grep -F 'nfqws2' | grep -v grep >/dev/null 2>&1
}
# Zapret2'yin iptables kural varligini kontrol eder (filter veya mangle)
# Process calisiyor olsa bile kural yoksa trafik islenmez
_zapret2_iptables_ok() {
    [ "$(cat /opt/zapret2/dpi_profile 2>/dev/null | tr -d '[:space:]')" = "none" ] && return 0
    iptables -t mangle -S 2>/dev/null | \
        grep -qE -- '-j NFQUEUE.*(zport_tcp|zport_udp|zapret2_clients|nozapret)|.*(zport_tcp|zport_udp|zapret2_clients|nozapret).*-j NFQUEUE' && return 0

    iptables -S 2>/dev/null | \
        grep -qE -- '-j NFQUEUE.*(zport_tcp|zport_udp|zapret2_clients|nozapret)|.*(zport_tcp|zport_udp|zapret2_clients|nozapret).*-j NFQUEUE' && return 0

    return 1
}
# Zapret2'yin yuklu olup olmadigini kontrol eder
is_zapret2_installed() {
    [ -x "/opt/zapret2/init.d/sysv/zapret2" ] || \
    [ -x "/opt/zapret2/nfq2/nfqws2" ]
}
KZM2_IP_EXCLUDE_SET="zapret2_ip_exclude"
KZM2_IP6_EXCLUDE_SET="zapret2_ip6_exclude"
kzm2_sync_ip_exclude_sets() {
    command -v ipset >/dev/null 2>&1 || return 0
    ensure_hostlist_files >/dev/null 2>&1
    ipset list "$KZM2_IP_EXCLUDE_SET" >/dev/null 2>&1 || ipset create "$KZM2_IP_EXCLUDE_SET" hash:net family inet 2>/dev/null
    ipset flush "$KZM2_IP_EXCLUDE_SET" >/dev/null 2>&1
    { [ -f "$HOSTLIST_LOCALNETS" ] && cat "$HOSTLIST_LOCALNETS"; [ -f "$HOSTLIST_EXCLUDE_IP" ] && cat "$HOSTLIST_EXCLUDE_IP"; } | \
        awk 'NF && $0 !~ /^[[:space:]]*#/ && $0 !~ /:/{print}' | while read -r _ip; do
            ipset add "$KZM2_IP_EXCLUDE_SET" "$_ip" -exist >/dev/null 2>&1
        done
    ipset list "$KZM2_IP6_EXCLUDE_SET" >/dev/null 2>&1 || ipset create "$KZM2_IP6_EXCLUDE_SET" hash:net family inet6 2>/dev/null
    ipset flush "$KZM2_IP6_EXCLUDE_SET" >/dev/null 2>&1
    { [ -f "$HOSTLIST_LOCALNETS" ] && cat "$HOSTLIST_LOCALNETS"; [ -f "$HOSTLIST_EXCLUDE_IP" ] && cat "$HOSTLIST_EXCLUDE_IP"; } | \
        awk 'NF && $0 !~ /^[[:space:]]*#/ && $0 ~ /:/{print}' | while read -r _ip; do
            ipset add "$KZM2_IP6_EXCLUDE_SET" "$_ip" -exist >/dev/null 2>&1
        done
    return 0
}
kzm2_remove_ip_exclude_rules() {
    local _wan
    _wan="$(get_wan_if 2>/dev/null)"
    while iptables -t mangle -D POSTROUTING ${_wan:+-o $_wan} -m set --match-set "$KZM2_IP_EXCLUDE_SET" dst -j RETURN 2>/dev/null; do :; done
    while iptables -t mangle -D POSTROUTING -m set --match-set "$KZM2_IP_EXCLUDE_SET" dst -j RETURN 2>/dev/null; do :; done
    while iptables -t mangle -D PREROUTING ${_wan:+-i $_wan} -m set --match-set "$KZM2_IP_EXCLUDE_SET" src -j RETURN 2>/dev/null; do :; done
    while iptables -t mangle -D PREROUTING -m set --match-set "$KZM2_IP_EXCLUDE_SET" src -j RETURN 2>/dev/null; do :; done
    if command -v ip6tables >/dev/null 2>&1; then
        while ip6tables -t mangle -D POSTROUTING ${_wan:+-o $_wan} -m set --match-set "$KZM2_IP6_EXCLUDE_SET" dst -j RETURN 2>/dev/null; do :; done
        while ip6tables -t mangle -D POSTROUTING -m set --match-set "$KZM2_IP6_EXCLUDE_SET" dst -j RETURN 2>/dev/null; do :; done
        while ip6tables -t mangle -D PREROUTING ${_wan:+-i $_wan} -m set --match-set "$KZM2_IP6_EXCLUDE_SET" src -j RETURN 2>/dev/null; do :; done
        while ip6tables -t mangle -D PREROUTING -m set --match-set "$KZM2_IP6_EXCLUDE_SET" src -j RETURN 2>/dev/null; do :; done
    fi
}
kzm2_apply_ip_exclude_rules() {
    command -v iptables >/dev/null 2>&1 || return 0
    command -v ipset >/dev/null 2>&1 || return 0
    local _wan
    _wan="$(get_wan_if 2>/dev/null)"
    kzm2_sync_ip_exclude_sets >/dev/null 2>&1
    kzm2_remove_ip_exclude_rules >/dev/null 2>&1
    iptables -t mangle -I POSTROUTING 1 ${_wan:+-o $_wan} -m set --match-set "$KZM2_IP_EXCLUDE_SET" dst -j RETURN 2>/dev/null
    iptables -t mangle -I PREROUTING 1 ${_wan:+-i $_wan} -m set --match-set "$KZM2_IP_EXCLUDE_SET" src -j RETURN 2>/dev/null
    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -t mangle -I POSTROUTING 1 ${_wan:+-o $_wan} -m set --match-set "$KZM2_IP6_EXCLUDE_SET" dst -j RETURN 2>/dev/null
        ip6tables -t mangle -I PREROUTING 1 ${_wan:+-i $_wan} -m set --match-set "$KZM2_IP6_EXCLUDE_SET" src -j RETURN 2>/dev/null
    fi
}
# Zapret2 servisini baslatir
start_zapret2() {
    if ! is_zapret2_installed; then
        echo "$(T TXT_START_NOT_INSTALLED)"
        return 1
    fi
    # none profili: nfqws2 ve NFQUEUE kurallari olmadan calisir
    if [ "$(cat /opt/zapret2/dpi_profile 2>/dev/null | tr -d '[:space:]')" = "none" ]; then
        zapret_resume
        killall nfqws2 2>/dev/null; sleep 1
        flush_all_nfqueue_rules 2>/dev/null
        nozapret_apply_rules 2>/dev/null
        kzm2_apply_ip_exclude_rules 2>/dev/null
        echo "$(T TXT_START_OK)"
        return 0
    fi
    # Init script eksikse yeniden olustur (blockcheck sonrasi nadiren olabilir)
    if [ ! -x "/opt/zapret2/init.d/sysv/zapret2" ]; then
        install_zapret_pause_guard 2>/dev/null
    fi
    ln -fs /opt/zapret2/init.d/sysv/zapret2 /opt/etc/init.d/S90-zapret2 2>/dev/null
    # Start edilecekse pause kaldir
    zapret_resume
    install_zapret_pause_guard
    # Tum runtime izinlerini duzelt (nfqws2 nobody user ile calisir)
    fix_zapret2_runtime_permissions
    # Zapret2 icin gerekli kernel modullerini yukle (bitmap:port dahil)
    kzm2_load_zapret2_kmods >/dev/null 2>&1
    if is_zapret2_running; then
        # Process calisiyor ama lua uyumsuzlugu olabilir — kontrol et
        local _nfq_bin="/opt/zapret2/nfq2/nfqws2"
        local _lua_lib="/opt/zapret2/lua/zapret-lib.lua"
        if [ -x "$_nfq_bin" ] && [ -f "$_lua_lib" ]; then
            local _bin_ver _lua_ver
            _bin_ver="$("$_nfq_bin" --version 2>&1 | grep -o 'lua_compat_ver [0-9]*' | awk '{print $2}')"
            _lua_ver="$(grep -m1 '^NFQWS2_COMPAT_VER_REQUIRED=' "$_lua_lib" | cut -d= -f2)"
            if [ -n "$_bin_ver" ] && [ -n "$_lua_ver" ] && [ "$_bin_ver" != "$_lua_ver" ]; then
                print_status WARN "$(T _ 'Lua uyumsuzlugu tespit edildi. Zapret2 yeniden baslatiliyor...' 'Lua incompatibility detected. Restarting Zapret2...')"
                stop_zapret2 >/dev/null 2>&1
                zapret_resume
                start_zapret2
                return $?
            fi
        fi
        # Kurallar eksik olabilir — tamir et
        /opt/zapret2/init.d/sysv/zapret2 start-fw >/dev/null 2>&1
        enforce_client_mode_rules >/dev/null 2>&1
        enforce_wan_if_nfqueue_rules >/dev/null 2>&1
        kzm2_apply_ip_exclude_rules >/dev/null 2>&1
        echo "$(T TXT_START_ALREADY)"
        return 0
    fi
	/opt/zapret2/init.d/sysv/zapret2 start >/dev/null 2>&1
	/opt/zapret2/init.d/sysv/zapret2 start-fw >/dev/null 2>&1
	# custom.d hook'un her zaman mevcut olmasini garantile
	write_client_ipset_hook >/dev/null 2>&1
	sleep 1
	# start-fw, moddan bagimsiz olarak genel NFQUEUE kurallarini basabilir.
	# Burada MODE=list ise genel kurallari temizleyip sadece IPSET kurallarini birakiriz.
	enforce_client_mode_rules >/dev/null 2>&1
	enforce_wan_if_nfqueue_rules >/dev/null 2>&1
	kzm2_apply_ip_exclude_rules >/dev/null 2>&1
    if is_zapret2_running; then
        echo "$(T TXT_START_OK)"
        # Autohostlist bos ise NFQUEUE kurali olmayabilir, uyar
        _hmode="$(cat /opt/zapret2/hostlist_mode 2>/dev/null | tr -d '[:space:]')"
        _hfile="/opt/zapret2/ipset/zapret-hosts-auto.txt"
        if [ "$_hmode" = "autohostlist" ] && [ ! -s "$_hfile" ]; then
            print_status WARN "$(T _ 'Autohostlist bos: trafik henuz islenmeyecek, siteler kullanildikca liste dolacak.' 'Autohostlist empty: traffic will not be filtered yet, list will fill as sites are visited.')"
        fi
        return 0
    fi
    echo "$(T TXT_START_FAIL)"
    # Lua uyumsuzlugu kontrolu: binary compat ver ile lua REQUIRED farkliysa otomatik duzelt
    local _nfq_bin="/opt/zapret2/nfq2/nfqws2"
    local _lua_lib="/opt/zapret2/lua/zapret-lib.lua"
    if [ -x "$_nfq_bin" ] && [ -f "$_lua_lib" ]; then
        local _bin_ver _lua_ver
        _bin_ver="$("$_nfq_bin" --version 2>&1 | grep -o 'lua_compat_ver [0-9]*' | awk '{print $2}')"
        _lua_ver="$(grep -m1 '^NFQWS2_COMPAT_VER_REQUIRED=' "$_lua_lib" | cut -d= -f2)"
        if [ -n "$_bin_ver" ] && [ -n "$_lua_ver" ] && [ "$_bin_ver" != "$_lua_ver" ]; then
            print_status WARN "$(T _ 'Lua uyumsuzlugu tespit edildi. Zapret2 lua scriptleri guncelleniyor...' 'Lua incompatibility detected. Updating Zapret2 lua scripts...')"
            local _zver _tmpdir _tarball _url _srcdir
            _zver="$(cat /opt/zapret2/version 2>/dev/null | tr -d '[:space:]')"
            if [ -n "$_zver" ]; then
                _tmpdir="/opt/tmp/zapret_lua_fix_$$"
                _tarball="zapret2-${_zver}.tar.gz"
                _url="https://github.com/bol-van/zapret2/releases/download/${_zver}/${_tarball}"
                mkdir -p "$_tmpdir"
                if curl -fsS -L "$_url" -o "${_tmpdir}/${_tarball}" 2>/dev/null; then
                    if tar -xzf "${_tmpdir}/${_tarball}" -C "$_tmpdir" 2>/dev/null; then
                        _srcdir="$(find "$_tmpdir" -maxdepth 1 -mindepth 1 -type d | head -n1)"
                        if [ -d "${_srcdir}/lua" ]; then
                            cp -r "${_srcdir}/lua/." /opt/zapret2/lua/ 2>/dev/null
                            fix_zapret2_runtime_permissions >/dev/null 2>&1
                            print_status PASS "$(T _ 'Lua scriptleri guncellendi. Yeniden baslatiliyor...' 'Lua scripts updated. Restarting...')"
                            rm -rf "$_tmpdir"
                            /opt/zapret2/init.d/sysv/zapret2 start >/dev/null 2>&1
                            /opt/zapret2/init.d/sysv/zapret2 start-fw >/dev/null 2>&1
                            sleep 1
                            enforce_client_mode_rules >/dev/null 2>&1
                            enforce_wan_if_nfqueue_rules >/dev/null 2>&1
                            kzm2_apply_ip_exclude_rules >/dev/null 2>&1
                            if is_zapret2_running; then
                                echo "$(T TXT_START_OK)"
                                return 0
                            fi
                        fi
                    fi
                fi
                rm -rf "$_tmpdir" 2>/dev/null
            fi
        fi
    fi
    return 1
}
# Zapret2 servisini durdurur (kalici durdurma: otomatik restart'i da engeller)
stop_zapret2() {
    local _remove_autostart="${1:-0}"
    if ! is_zapret2_installed; then
        echo "$(T TXT_STOP_NOT_INSTALLED)"
        return 1
    fi
    echo "$(T TXT_STOP_STOPPING)"
    # Pause ON: netfilter hook/otomatik restart tetiklense bile start* no-op olur.
    zapret_pause
    install_zapret_pause_guard
    /opt/zapret2/init.d/sysv/zapret2 stop-fw >/dev/null 2>&1
    /opt/zapret2/init.d/sysv/zapret2 stop    >/dev/null 2>&1
    killall nfqws2 >/dev/null 2>&1
    killall -9 nfqws2 >/dev/null 2>&1
    # Her ihtimale karsi kalan NFQUEUE / exclude RETURN kurallarini da temizle
    kzm2_remove_ip_exclude_rules >/dev/null 2>&1
    flush_all_nfqueue_rules
    flush_all_ip6tables_nfqueue_rules
    sleep 1
    if is_zapret2_running; then
        echo "$(T TXT_STOP_NFQWS_WARN)"
    else
        echo "OK: NFQWS2 YOK"
    fi
    if iptables-save | grep -q "NFQUEUE"; then
        echo "$(T TXT_STOP_NFQUEUE_WARN)"
    else
        echo "OK: NFQUEUE YOK"
    fi
    echo "$(T TXT_STOP_OK)"
    [ "$_remove_autostart" = "1" ] && rm -f /opt/etc/init.d/S90-zapret2 2>/dev/null
    return 0
}
# Zapret2 servisini yeniden baslatir (guvenli)
restart_zapret2() {
    if ! is_zapret2_installed; then
        echo "$(T TXT_RESTART_NOT_INSTALLED)"
        return 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') | zapret_restart | triggered" >> /tmp/kzm2_healthmon.log 2>/dev/null
    stop_zapret2
    zapret_resume
    start_zapret2
}
# --- KURULU VERSIYONU GORUNTULE (6. MADDE) ---
check_zapret_version() {
    if ! is_zapret2_installed; then echo "$(T TXT_ZAPRET_NOT_INSTALLED)"; return 1; fi
    if [ -f "/opt/zapret2/version" ]; then
        echo "$(T ver_installed "$TXT_VERSION_INSTALLED_TR" "$TXT_VERSION_INSTALLED_EN")$(cat /opt/zapret2/version)"
    else
        echo "Surum dosyasi bulunamadi. Lutfen script ile yeniden kurulum yapin."
    fi
    press_enter_to_continue
    clear
}
# --- ZAPRET GUNCELLEME (6. MADDE) ---
update_zapret2() {
    local repo="bol-van/zapret2"
    local api="https://api.github.com/repos/${repo}/releases/latest"
    local tmpdir="/opt/tmp/zapret_update_$$"
    # GitHub API'den hem tag_name hem asset SHA256 al (tek istek)
    local api_raw latest tarball expected_sha256
    api_raw="$(curl -fsS "$api" 2>/dev/null)"
    latest="$(printf '%s\n' "$api_raw" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    [ -z "$latest" ] && { print_status FAIL "$(T TXT_GITHUB_FAIL)"; return 1; }
    # Kurulu surum ile karsilastir
    local _installed_ver
    _installed_ver="$(cat /opt/zapret2/version 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$_installed_ver" ]; then
        if [ "$_installed_ver" = "$latest" ]; then
            print_status INFO "$(T _ 'Zapret2 zaten guncel' 'Zapret2 is already up to date') ($_installed_ver)"
            return 2
        elif ver_is_newer "$_installed_ver" "$latest" 2>/dev/null; then
            print_status WARN "$(T _ 'Kurulu surum daha yeni, guncelleme atlandi' 'Installed version is newer, update skipped') ($_installed_ver > $latest)"
            return 3
        fi
    fi
    tarball="zapret2-${latest}.tar.gz"
    local url="https://github.com/${repo}/releases/download/${latest}/${tarball}"
    # Asset SHA256 digest'ini API'den cek (format: "digest":"sha256:HASH")
    expected_sha256="$(printf '%s\n' "$api_raw" | grep -A5 "\"${tarball}\"" | \
        sed -n 's/.*"digest"[[:space:]]*:[[:space:]]*"sha256:\([^"]*\)".*/\1/p' | head -n1)"
    print_status INFO "$(T TXT_ZAP_UPDATE_DOWNLOADING)"
    mkdir -p "$tmpdir" || { print_status FAIL "$(T TXT_ZAP_UPDATE_FAIL_DL)"; return 1; }
    if ! curl -fsS -L "$url" -o "${tmpdir}/${tarball}" 2>/dev/null; then
        rm -rf "$tmpdir"
        print_status FAIL "$(T TXT_ZAP_UPDATE_FAIL_DL)"
        return 1
    fi
    # SHA256 dogrulamasi
    if [ -n "$expected_sha256" ]; then
        local actual_sha256
        actual_sha256="$(sha256sum "${tmpdir}/${tarball}" 2>/dev/null | cut -d' ' -f1)"
        if [ "$actual_sha256" = "$expected_sha256" ]; then
            print_status PASS "$(T TXT_ZAP_UPDATE_SHA256_OK)"
            printf 'ok' > /opt/etc/kzm2_sha256_zapret.state
        else
            rm -rf "$tmpdir"
            print_status FAIL "$(T TXT_ZAP_UPDATE_SHA256_FAIL)"
            printf 'fail' > /opt/etc/kzm2_sha256_zapret.state
            return 1
        fi
    else
        print_status WARN "$(T TXT_ZAP_UPDATE_SHA256_SKIP)"
    fi
    print_status INFO "$(T TXT_ZAP_UPDATE_EXTRACTING)"
    if ! tar -xzf "${tmpdir}/${tarball}" -C "$tmpdir" 2>/dev/null; then
        rm -rf "$tmpdir"
        print_status FAIL "$(T TXT_ZAP_UPDATE_FAIL_EX)"
        return 1
    fi
    print_status INFO "$(T TXT_ZAP_UPDATE_APPLYING)"
    local srcdir
    srcdir="$(find "$tmpdir" -maxdepth 1 -mindepth 1 -type d | head -n1)"
    if [ -z "$srcdir" ] || [ ! -d "${srcdir}/binaries" ]; then
        rm -rf "$tmpdir"
        print_status FAIL "$(T TXT_ZAP_UPDATE_FAIL_BIN)"
        return 1
    fi
    if ! cp -r "${srcdir}/binaries/." /opt/zapret2/binaries/ 2>/dev/null; then
        rm -rf "$tmpdir"
        print_status FAIL "$(T TXT_ZAP_UPDATE_FAIL_BIN)"
        return 1
    fi
    # Lua scriptlerini de guncelle (binary ile uyumlu olmali)
    if [ -d "${srcdir}/lua" ]; then
        cp -r "${srcdir}/lua/." /opt/zapret2/lua/ 2>/dev/null
    fi
    # Diger zapret2 dizinlerini guncelle (kullanici dosyalarina dokunmadan)
    for _dir in blockcheck2.d common files nfq2 ip2net mdig; do
        [ -d "${srcdir}/${_dir}" ] && cp -r "${srcdir}/${_dir}/." /opt/zapret2/${_dir}/ 2>/dev/null
    done
    # ipset icindeki scriptleri guncelle (txt dosyalarina dokunma)
    if [ -d "${srcdir}/ipset" ]; then
        find "${srcdir}/ipset" -maxdepth 1 -name "*.sh" | while IFS= read -r _f; do
            cp "$_f" /opt/zapret2/ipset/ 2>/dev/null
        done
        find "${srcdir}/ipset" -maxdepth 1 -name "*.helper" | while IFS= read -r _f; do
            cp "$_f" /opt/zapret2/ipset/ 2>/dev/null
        done
    fi
    if [ -f "${srcdir}/install_bin.sh" ]; then
        cp "${srcdir}/install_bin.sh" /opt/zapret2/install_bin.sh 2>/dev/null
        sh /opt/zapret2/install_bin.sh >/dev/null 2>&1 || true
    fi
    printf '%s\n' "$latest" > /opt/zapret2/version 2>/dev/null
    rm -rf "$tmpdir"
    cleanup_files_after_extracted
    print_status PASS "$(T TXT_ZAP_UPDATE_OK)"
    # Binary surum dogrulamasi
    local nfqws_bin="/opt/zapret2/nfq2/nfqws2"
    if [ -x "$nfqws_bin" ]; then
        local bin_ver
        bin_ver="$("$nfqws_bin" --version 2>&1 | head -n1)"
        [ -n "$bin_ver" ] && printf "     %s: %s\n" "$(T _ 'Binary' 'Binary')" "$bin_ver"
    fi
    fix_zapret2_runtime_permissions
    restart_zapret2 >/dev/null 2>&1 || true
    printf 'ok' > /opt/etc/kzm2_sha256_zapret.state 2>/dev/null
    return 0
}
check_remote_update() {
    if ! is_zapret2_installed; then
        print_status FAIL "$(T TXT_ZAP_UPDATE_NO_INSTALLED)"
        press_enter_to_continue
        return 1
    fi
    print_status INFO "$(T TXT_CHECKING_GITHUB)"
    local repo="bol-van/zapret2"
    local api="https://api.github.com/repos/${repo}/releases/latest"
    local REMOTE_VER LOCAL_VER
    REMOTE_VER="$(curl -fsS "$api" 2>/dev/null | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    if [ -z "$REMOTE_VER" ]; then
        print_status FAIL "$(T TXT_GITHUB_FAIL)"
        press_enter_to_continue
        return 1
    fi
    LOCAL_VER="$(cat /opt/zapret2/version 2>/dev/null)"
    [ -z "$LOCAL_VER" ] && LOCAL_VER="$(T _ 'Bilinmiyor' 'Unknown')"
    # Renkleri duruma gore ata
    local CLR_REMOTE CLR_LOCAL
    if [ "$REMOTE_VER" = "$LOCAL_VER" ]; then
        # Guncel: ikisi de yesil
        CLR_REMOTE="${CLR_BOLD}${CLR_GREEN}"; CLR_LOCAL="${CLR_BOLD}${CLR_GREEN}"
    elif ver_is_newer "$REMOTE_VER" "$LOCAL_VER"; then
        # Normal guncelleme: remote yeni (yesil), local eski (sari)
        CLR_REMOTE="${CLR_BOLD}${CLR_GREEN}"; CLR_LOCAL="${CLR_BOLD}${CLR_YELLOW}"
    else
        # Geri cekilen release: local daha yeni ama hatali (kirmizi), remote stabil (yesil)
        CLR_REMOTE="${CLR_BOLD}${CLR_GREEN}"; CLR_LOCAL="${CLR_BOLD}${CLR_RED}"
    fi
    print_line "-"
    printf " %-10s: %b%s%b\n" "$(T TXT_GITHUB_LATEST)" "$CLR_REMOTE" "$REMOTE_VER" "${CLR_RESET}"
    printf " %-10s: %b%s%b\n" "$(T TXT_DEVICE_VERSION)" "$CLR_LOCAL" "$LOCAL_VER" "${CLR_RESET}"
    # Binary surum bilgisi
    local nfqws_bin="/opt/zapret2/nfq2/nfqws2"
    if [ -x "$nfqws_bin" ]; then
        local bin_ver
        bin_ver="$("$nfqws_bin" --version 2>&1 | head -n1)"
        [ -n "$bin_ver" ] && printf " %-10s: %s\n" "INFO" "$bin_ver"
    fi
    print_line "-"
    if [ "$REMOTE_VER" = "$LOCAL_VER" ]; then
        printf 'ok' > /opt/etc/kzm2_sha256_zapret.state
        print_status PASS "$(T TXT_UPTODATE)"
        press_enter_to_continue
        return 0
    fi
    if ver_is_newer "$REMOTE_VER" "$LOCAL_VER"; then
        # Normal guncelleme: GitHub daha yeni
        print_status WARN "$(T _ 'Yeni surum mevcut!' 'New version available!')"
        echo ""
        printf "%s" "$(T TXT_ZAP_UPDATE_CONFIRM)"
        read -r ans
        case "$ans" in
            e|E|y|Y)
                echo ""
                update_zapret2
                ;;
            *)
                print_status INFO "$(T TXT_ZAP_UPDATE_CANCELLED)"
                ;;
        esac
    else
        # Kurulu surum GitHub'dakinden yeni: geri cekilmis release senaryosu
        print_status WARN "$(T TXT_ZAP_NEWER_LOCAL_WARN)"
        echo ""
        printf "%s" "$(T TXT_ZAP_NEWER_LOCAL)"
        read -r ans
        case "$ans" in
            e|E|y|Y)
                echo ""
                update_zapret2
                ;;
            *)
                print_status INFO "$(T TXT_ZAP_UPDATE_CANCELLED)"
                ;;
        esac
    fi
    press_enter_to_continue
}
# --- ZAPRET IPV6 DURUM KONTROLU ---
_zapret2_ipv6_enabled() {
    # KZM2 source of truth: /opt/zapret2/config
    #   DISABLE_IPV6=0 -> IPv6 support ON
    #   DISABLE_IPV6=1 -> IPv6 support OFF
    # Menu 7 changes this value, so all IPv6 decisions must read it.
    # Do NOT infer from ip6_ttl in NFQWS2_OPT or ip6tables runtime rules.
    local _v
    [ -f /opt/zapret2/config ] || return 1
    _v="$(grep -E '^DISABLE_IPV6=' /opt/zapret2/config 2>/dev/null | tail -n 1 | cut -d= -f2- | tr -d '\042\047[:space:]')"
    [ "$_v" = "0" ]
}
check_zapret_ipv6_status() {
    if [ ! -f "/opt/zapret2/config" ]; then
        echo "$(T ipv6_status_unknown 'Zapret2 IPv6 durumu: Bilinmiyor (config yok)' 'Zapret2 IPv6 status: Unknown (config missing)')"
        return 1
    fi
    if _zapret2_ipv6_enabled; then
        echo "${CLR_BOLD}${CLR_GREEN}$(T ipv6_status_on 'Zapret2 IPv6 destegi: ACIK' 'Zapret2 IPv6 support: ON')${CLR_RESET}"
    else
        echo "${CLR_BOLD}${CLR_RED}$(T ipv6_status_off 'Zapret2 IPv6 destegi: KAPALI' 'Zapret2 IPv6 support: OFF')${CLR_RESET}"
    fi
    return 0
}
# --- ZAPRET IPV6 DESTEGI (8. MADDE) ---
# Not: Bu ayar "router'da IPv6 ac/kapat" degildir.
# Zapret2'yin kendi kurulum sihirbazindaki "enable ipv6 support" secenegini yonetir.
configure_zapret_ipv6_support() {
    if ! is_zapret2_installed; then
        echo "$(T TXT_IPV6_NOT_INSTALLED)"
        press_enter_to_continue
        clear
        return 1
    fi
    echo "$(T ipv6_cfg_title 'Zapret2 icin IPv6 destegi ayarlanacak.' 'IPv6 support for Zapret2 will be configured.')"
    echo "$(T ipv6_cfg_desc 'Bu, Zapret2 IPv6 (ip6tables) tarafinda da kural/yonlendirme kurar.' 'This enables Zapret2 to also set up rules/routing on the IPv6 (ip6tables) side.')"
    check_zapret_ipv6_status
    echo ""
    printf '%s' "$(T ipv6_cfg_prompt 'IPv6 destegi etkinlestirilsin mi? (e/h) [h]: ' 'Enable IPv6 support? (y/n) [n]: ')"; read -r ans
    IPV6_ANSWER="n"
    case "$ans" in
        [eEyY]) IPV6_ANSWER="y" ;;
        *)    IPV6_ANSWER="n" ;;
    esac
    # Secimi global degiskene yaz (install_easy cevabi icin)
    ZAPRET_IPV6="$IPV6_ANSWER"
# Mevcut IPv6 durumunu config'deki DISABLE_IPV6 satirindan algila
CURRENT_IPV6="n"
_zapret2_ipv6_enabled && CURRENT_IPV6="y"
# Kullanici secimi mevcut durumla ayniysa bile NFQWS2_OPT yeniden yazilir.
# Eski Blockcheck Auto kaydinda ip6_ttl kalmis olabilir; Menu 7 durumu
# DISABLE_IPV6 uzerinden kaynak kabul edilir ve config aninda senkronlanir.
if [ "$IPV6_ANSWER" = "$CURRENT_IPV6" ]; then
    update_nfqws_parameters >/dev/null 2>&1 || true
    restart_zapret2 >/dev/null 2>&1 || true
    echo "$(T ipv6_no_change 'Degisiklik yok (IPv6 destegi zaten bu durumda). DPI parametreleri senkronlandi.' 'No change (IPv6 support is already in this state). DPI parameters synchronized.')"
    press_enter_to_continue
    clear
    return 0
fi
echo "$(tpl_render "$(T TXT_IPV6_WIZARD_START)" VAL "$IPV6_ANSWER")"
    # Zapret2 v0.9.5.2+ install_easy.sh LAN/WAN interface sorabilir.
    # KZM2 varsayilan NONE/ANY gecip ardindan WAN kurallarini kendisi uygular.
    # Soru sirasi: guvenlik duvari -> IPv6 -> filtre modu -> nfqws2 -> duzenleme -> LAN/WAN (varsa)
    run_zapret2_install_easy "$IPV6_ANSWER" || {
        echo "$(T TXT_IPV6_CFG_FAIL)"
        echo "Log: /tmp/kzm2_install_easy.log"
        press_enter_to_continue
        clear
        return 1
    }
    # Bizim Keenetic-ozel dokunuslarimizi tekrar uygula
    fix_keenetic_udp
    update_kernel_module_config
    update_nfqws_parameters
    disable_total_packet
    allow_firewall
    add_auto_start_zapret2
    fix_zapret2_runtime_permissions
    # Eski keenetic_fw_post_up hook'u temizle (etki etmiyordu, zapret2.real patch'i riskli)
    _cleanup_post_up_hook
    # Servisi tazele
    restart_zapret2
    [ "$(get_dpi_profile)" != "none" ] && enforce_wan_if_nfqueue_rules >/dev/null 2>&1
    echo "IPv6 destegi ayari tamamlandi."
    press_enter_to_continue
    clear
    return 0
}
# --- ZAPRET ISTEMCI IPSET FILTRELEME (9. MADDE) ---
# Amac: Zapret2'yin (NFQUEUE) kuralini sadece belirli LAN istemcilerine uygulamak.
# - "Tum ag": filtre kapali, zapret herkes icin calisir.
# - "Secili IP'ler": sadece girilen IPv4 istemci IP'leri zapret'ten gecer.
IPSET_CLIENT_NAME="zapret2_clients"
IPSET_CLIENT_FILE="/opt/zapret2/ipset_clients.txt"
IPSET_CLIENT_MODE_FILE="/opt/zapret2/ipset_clients_mode"  # all | list
ZAPRET_CLIENT_HOOK="/opt/zapret2/init.d/sysv/custom.d/90-keenetic-client-ipset"
write_client_ipset_hook() {
    # Zapret2'yin custom.d mekanizmasi, start-fw / restart-fw sirasinda bu betikleri calistirir.
    # Bu hook, her FW yenilemesinde iptables NFQUEUE kurallarina ipset match ekler/kaldirir.
    cat > "$ZAPRET_CLIENT_HOOK" <<'EOF'
#!/bin/sh
IPSET_NAME="zapret2_clients"
IPSET_FILE="/opt/zapret2/ipset_clients.txt"
MODE_FILE="/opt/zapret2/ipset_clients_mode"  # all | list
IP_EXCLUDE_SET="zapret2_ip_exclude"
IP6_EXCLUDE_SET="zapret2_ip6_exclude"
IP_EXCLUDE_FILE="/opt/zapret2/ipset/zapret-ip-exclude.txt"
LOCALNETS_FILE="/opt/zapret2/ipset/zapret-hosts-localnets.txt"
QNUM="300"
command -v iptables >/dev/null 2>&1 || exit 0
command -v ipset >/dev/null 2>&1 || exit 0
MODE="all"
[ -f "$MODE_FILE" ] && MODE="$(cat "$MODE_FILE" 2>/dev/null)"
[ -z "$MODE" ] && MODE="all"
ipset_ensure_and_maybe_sync() {
    ipset list "$IPSET_NAME" >/dev/null 2>&1 || ipset create "$IPSET_NAME" hash:ip 2>/dev/null
    # Eger dosya varsa "kaynak gercek" dosyadir -> set'i dosyaya gore senkronla.
    if [ -f "$IPSET_FILE" ]; then
        ipset flush "$IPSET_NAME" >/dev/null 2>&1
        tr ' \t,;\r\n' '\n' < "$IPSET_FILE" | awk 'NF{print $0}' | while read -r ip; do
            ipset add "$IPSET_NAME" "$ip" -exist >/dev/null 2>&1
        done
    fi
}
# Belirli chain'de NFQUEUE kural(lar)ini guvenli bicimde sil
del_nfqueue_chain() {
    local table="$1" chain="$2" grep_pat="$3"
    if [ -n "$table" ]; then
        iptables -t "$table" -S "$chain" 2>/dev/null | grep -F "NFQUEUE" | grep -F -- "$grep_pat" | while read -r rule; do
            iptables -t "$table" $(echo "$rule" | sed 's/^-A /-D /') >/dev/null 2>&1
        done
    else
        iptables -S "$chain" 2>/dev/null | grep -F "NFQUEUE" | grep -F -- "$grep_pat" | while read -r rule; do
            iptables $(echo "$rule" | sed 's/^-A /-D /') >/dev/null 2>&1
        done
    fi
}
# IpSet'e bagli NFQUEUE kurallarini ekle (ustten insert)
add_ipset_rules() {
    # Keenetic'te bazen default route satiri "default dev ppp0 scope link" seklinde gelir.
    # Bu yuzden arayuzu, "dev" alanini bularak cekiyoruz.
    WAN="$(ip route 2>/dev/null | awk '/^default/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    iptables -t mangle -I POSTROUTING 1 ${WAN:+-o $WAN} -p tcp -m multiport --dports 80,443 \
        -m set --match-set "$IPSET_NAME" src \
        -j NFQUEUE --queue-num "$QNUM" --queue-bypass >/dev/null 2>&1
    iptables -t mangle -I POSTROUTING 1 ${WAN:+-o $WAN} -p udp -m multiport --dports 443 \
        -m set --match-set "$IPSET_NAME" src \
        -j NFQUEUE --queue-num "$QNUM" --queue-bypass >/dev/null 2>&1
}
# Genel NFQUEUE (qnum 300) kurallarini temizle
del_general_nfqueue_qnum300() {
    del_nfqueue_chain mangle POSTROUTING "--queue-num $QNUM"
    del_nfqueue_chain "" INPUT "--queue-num $QNUM"
    del_nfqueue_chain "" FORWARD "--queue-num $QNUM"
}
# Sadece ipset'e bagli kurallari temizle (match-set zapret2_clients)
del_ipset_nfqueue_rules() {
    del_nfqueue_chain mangle POSTROUTING "match-set $IPSET_NAME"
    del_nfqueue_chain "" INPUT "match-set $IPSET_NAME"
    del_nfqueue_chain "" FORWARD "match-set $IPSET_NAME"
}
if [ "$MODE" = "list" ]; then
    # LIST mod: tum ag etkilenmesin diye genel NFQUEUE'leri kaldir, sadece IPSET kurallarini birak.
    del_general_nfqueue_qnum300
    ipset_ensure_and_maybe_sync
    add_ipset_rules
else
    # ALL mod: IPSET'e bagli ozel kurallar varsa kaldir, genel kurallar kalsin.
    del_ipset_nfqueue_rules
fi
# Destination IP/Subnet exclude: localnets + user zapret-ip-exclude.txt
sync_ip_exclude() {
    ipset list "$IP_EXCLUDE_SET" >/dev/null 2>&1 || ipset create "$IP_EXCLUDE_SET" hash:net family inet 2>/dev/null
    ipset flush "$IP_EXCLUDE_SET" >/dev/null 2>&1
    { [ -f "$LOCALNETS_FILE" ] && cat "$LOCALNETS_FILE"; [ -f "$IP_EXCLUDE_FILE" ] && cat "$IP_EXCLUDE_FILE"; } | awk 'NF && $0 !~ /^[[:space:]]*#/ && $0 !~ /:/{print}' | while read -r ip; do ipset add "$IP_EXCLUDE_SET" "$ip" -exist >/dev/null 2>&1; done
    ipset list "$IP6_EXCLUDE_SET" >/dev/null 2>&1 || ipset create "$IP6_EXCLUDE_SET" hash:net family inet6 2>/dev/null
    ipset flush "$IP6_EXCLUDE_SET" >/dev/null 2>&1
    { [ -f "$LOCALNETS_FILE" ] && cat "$LOCALNETS_FILE"; [ -f "$IP_EXCLUDE_FILE" ] && cat "$IP_EXCLUDE_FILE"; } | awk 'NF && $0 !~ /^[[:space:]]*#/ && $0 ~ /:/{print}' | while read -r ip; do ipset add "$IP6_EXCLUDE_SET" "$ip" -exist >/dev/null 2>&1; done
}
remove_ip_exclude_rules() {
    WAN="$(ip route 2>/dev/null | awk '/^default/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    # RETURN kurallari NFQUEUE icermedigi icin del_nfqueue_chain bunlari silemez.
    # Her start-fw/custom.d calismasinda once tum eski exclude RETURN kurallarini temizle.
    while iptables -t mangle -D POSTROUTING ${WAN:+-o $WAN} -m set --match-set "$IP_EXCLUDE_SET" dst -j RETURN 2>/dev/null; do :; done
    while iptables -t mangle -D POSTROUTING -m set --match-set "$IP_EXCLUDE_SET" dst -j RETURN 2>/dev/null; do :; done
    while iptables -t mangle -D PREROUTING ${WAN:+-i $WAN} -m set --match-set "$IP_EXCLUDE_SET" src -j RETURN 2>/dev/null; do :; done
    while iptables -t mangle -D PREROUTING -m set --match-set "$IP_EXCLUDE_SET" src -j RETURN 2>/dev/null; do :; done
    if command -v ip6tables >/dev/null 2>&1; then
        while ip6tables -t mangle -D POSTROUTING ${WAN:+-o $WAN} -m set --match-set "$IP6_EXCLUDE_SET" dst -j RETURN 2>/dev/null; do :; done
        while ip6tables -t mangle -D POSTROUTING -m set --match-set "$IP6_EXCLUDE_SET" dst -j RETURN 2>/dev/null; do :; done
        while ip6tables -t mangle -D PREROUTING ${WAN:+-i $WAN} -m set --match-set "$IP6_EXCLUDE_SET" src -j RETURN 2>/dev/null; do :; done
        while ip6tables -t mangle -D PREROUTING -m set --match-set "$IP6_EXCLUDE_SET" src -j RETURN 2>/dev/null; do :; done
    fi
}
add_ip_exclude_rules() {
    WAN="$(ip route 2>/dev/null | awk '/^default/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    remove_ip_exclude_rules
    sync_ip_exclude
    iptables -t mangle -I POSTROUTING 1 ${WAN:+-o $WAN} -m set --match-set "$IP_EXCLUDE_SET" dst -j RETURN >/dev/null 2>&1
    iptables -t mangle -I PREROUTING 1 ${WAN:+-i $WAN} -m set --match-set "$IP_EXCLUDE_SET" src -j RETURN >/dev/null 2>&1
    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -t mangle -I POSTROUTING 1 ${WAN:+-o $WAN} -m set --match-set "$IP6_EXCLUDE_SET" dst -j RETURN >/dev/null 2>&1
        ip6tables -t mangle -I PREROUTING 1 ${WAN:+-i $WAN} -m set --match-set "$IP6_EXCLUDE_SET" src -j RETURN >/dev/null 2>&1
    fi
}
add_ip_exclude_rules
exit 0
EOF
    chmod +x "$ZAPRET_CLIENT_HOOK" 2>/dev/null
    return 0
}
show_ipset_client_status() {
    MODE="all"
    [ -f "$IPSET_CLIENT_MODE_FILE" ] && MODE="$(cat "$IPSET_CLIENT_MODE_FILE" 2>/dev/null)"
    [ -z "$MODE" ] && MODE="all"
    if [ "$MODE" = "list" ]; then
        print_line "="
        printf '%b%s%b\n' "${CLR_CYAN}${CLR_BOLD}" "$(T ipset_mode_list "$TXT_IPSET_MODE_LIST_TR" "$TXT_IPSET_MODE_LIST_EN")" "${CLR_RESET}"
        print_line "="
        echo ""
        
        # IP Listesi Dosyasi
        printf '%b%-25s:%b ' "${CLR_ORANGE}${CLR_BOLD}" "$(T ip_list_file "$TXT_IP_LIST_FILE_TR" "$TXT_IP_LIST_FILE_EN")" "${CLR_RESET}"
        if [ -f "$IPSET_CLIENT_FILE" ] && [ -s "$IPSET_CLIENT_FILE" ]; then
            local ip_count="$(wc -l < "$IPSET_CLIENT_FILE" 2>/dev/null | tr -d ' ')"
            printf '%b%d IP%b\n' "${CLR_GREEN}" "$ip_count" "${CLR_RESET}"
            echo ""
            # awk ile numaralandirma - daha guvenli
            awk -v cyan="${CLR_CYAN}" -v reset="${CLR_RESET}" '
                NF > 0 {
                    printf "  %s%2d.%s %s\n", cyan, NR, reset, $0
                }' "$IPSET_CLIENT_FILE"
        else
            printf '%b%s%b\n' "${CLR_RED}" "$(T empty "$TXT_EMPTY_TR" "$TXT_EMPTY_EN")" "${CLR_RESET}"
        fi
        
        echo ""
        print_line "-"
        
        # IPSET Uyeleri (dosyadan goster — subnet girisleri dogru gorunsun)
        printf '%b%-25s:%b ' "${CLR_ORANGE}${CLR_BOLD}" "$(T ipset_members "$TXT_IPSET_MEMBERS_TR" "$TXT_IPSET_MEMBERS_EN")" "${CLR_RESET}"
        if [ -f "$IPSET_CLIENT_FILE" ] && [ -s "$IPSET_CLIENT_FILE" ]; then
            local member_count="$(grep -c '[0-9]' "$IPSET_CLIENT_FILE" 2>/dev/null | tr -d ' ')"
            printf '%b%d IP%b\n' "${CLR_GREEN}" "$member_count" "${CLR_RESET}"
            echo ""
            awk -v cyan="${CLR_CYAN}" -v reset="${CLR_RESET}" '
                NF > 0 {
                    printf "  %s%2d.%s %s\n", cyan, NR, reset, $0
                }' "$IPSET_CLIENT_FILE"
        else
            printf '%b%s%b\n' "${CLR_RED}" "$(T empty "$TXT_EMPTY_TR" "$TXT_EMPTY_EN")" "${CLR_RESET}"
        fi
        
        print_line "-"
        # No Zapret2 (Muafiyet) Uyeleri
        printf '%b%-25s:%b ' "${CLR_ORANGE}${CLR_BOLD}" "$(T nozapret_members 'No Zapret2 (Muafiyet)' 'No Zapret2 (Exempt)')" "${CLR_RESET}"
        local noz_members="$(ipset list "$NOZAPRET_IPSET_NAME" 2>/dev/null | sed -n '/^Members:/,$p' | tail -n +2)"
        if [ -f "$NOZAPRET_FILE" ] && [ -s "$NOZAPRET_FILE" ]; then
            local noz_count="$(grep -c '[0-9]' "$NOZAPRET_FILE" 2>/dev/null | tr -d ' ')"
            printf '%b%d IP%b\n' "${CLR_GREEN}" "$noz_count" "${CLR_RESET}"
            echo ""
            awk -v cyan="${CLR_CYAN}" -v reset="${CLR_RESET}" '
                NF > 0 {
                    printf "  %s%2d.%s %s\n", cyan, NR, reset, $0
                }' "$NOZAPRET_FILE"
        else
            printf '%b%s%b\n' "${CLR_RED}" "$(T empty "$TXT_EMPTY_TR" "$TXT_EMPTY_EN")" "${CLR_RESET}"
        fi
        print_line "="
    else
        print_line "="
        printf '%b%s%b\n' "${CLR_CYAN}${CLR_BOLD}" "$(T ipset_mode_all "$TXT_IPSET_MODE_ALL_TR" "$TXT_IPSET_MODE_ALL_EN")" "${CLR_RESET}"
        print_line "="
        echo ""
        printf '%b%s%b\n' "${CLR_GREEN}" "$(T ipset_all_network "$TXT_IPSET_ALL_NETWORK_TR" "$TXT_IPSET_ALL_NETWORK_EN")" "${CLR_RESET}"
        print_line "-"
        # No Zapret2 (Muafiyet) Uyeleri - Tum Ag modunda da goster
        printf '%b%-25s:%b ' "${CLR_ORANGE}${CLR_BOLD}" "$(T nozapret_members 'No Zapret2 (Muafiyet)' 'No Zapret2 (Exempt)')" "${CLR_RESET}"
        if [ -f "$NOZAPRET_FILE" ] && [ -s "$NOZAPRET_FILE" ]; then
            local noz_count2="$(grep -c '[0-9]' "$NOZAPRET_FILE" 2>/dev/null | tr -d ' ')"
            printf '%b%d IP%b\n' "${CLR_GREEN}" "$noz_count2" "${CLR_RESET}"
            echo ""
            awk -v cyan="${CLR_CYAN}" -v reset="${CLR_RESET}" '
                NF > 0 {
                    printf "  %s%2d.%s %s\n", cyan, NR, reset, $0
                }' "$NOZAPRET_FILE"
        else
            printf '%b%s%b\n' "${CLR_RED}" "$(T empty "$TXT_EMPTY_TR" "$TXT_EMPTY_EN")" "${CLR_RESET}"
        fi
        print_line "="
    fi
}
apply_ipset_client_settings() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | zapret_restart | triggered (ipset)" >> /tmp/kzm2_healthmon.log 2>/dev/null
    write_client_ipset_hook >/dev/null 2>&1
    if [ -x "/opt/zapret2/init.d/sysv/zapret2" ]; then
        # restart-fw yerine stop-fw + start-fw (daha deterministik)
        /opt/zapret2/init.d/sysv/zapret2 stop-fw >/dev/null 2>&1
        /opt/zapret2/init.d/sysv/zapret2 start-fw >/dev/null 2>&1
        # MODE all/list durumunu kesin uygula
        [ "$(get_dpi_profile)" != "none" ] && enforce_client_mode_rules >/dev/null 2>&1
        # nfqws yoksa daemonu da baslat
        if ! is_zapret2_running; then
            /opt/zapret2/init.d/sysv/zapret2 start >/dev/null 2>&1
        fi
    fi
    return 0
}

# Append a line safely even if the target file does not end with a newline.
# Prevents corrupt joins like: 192.168.1.60172.16.2.0/24
kzm_file_ensure_trailing_newline() {
    _kzm_f="$1"
    [ -f "$_kzm_f" ] && [ -s "$_kzm_f" ] || return 0
    _kzm_last="$(tail -c 1 "$_kzm_f" 2>/dev/null)"
    [ -n "$_kzm_last" ] && printf '\n' >> "$_kzm_f"
    return 0
}

kzm_append_unique_line() {
    _kzm_f="$1"
    _kzm_line="$2"
    [ -n "$_kzm_f" ] && [ -n "$_kzm_line" ] || return 1
    touch "$_kzm_f" 2>/dev/null || return 1
    grep -Fqx "$_kzm_line" "$_kzm_f" 2>/dev/null && return 0
    kzm_file_ensure_trailing_newline "$_kzm_f"
    printf '%s\n' "$_kzm_line" >> "$_kzm_f"
}

# Normalize IPv4 CIDR values read from Keenetic VPN interfaces.
# Keenetic may report interface IP (example: 172.16.6.1/24),
# but zapret2 client list must store the network CIDR (172.16.6.0/24).
kzm_normalize_ipv4_cidr() {
    _kzm_cidr="$1"
    [ -n "$_kzm_cidr" ] || return 1
    printf '%s' "$_kzm_cidr" | awk -F'[./]' '
        NF>=5 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $4 ~ /^[0-9]+$/ && $5 ~ /^[0-9]+$/ {
            if ($5 == 32) { printf "%s.%s.%s.%s/32", $1,$2,$3,$4; exit }
            if ($5 == 24) { printf "%s.%s.%s.0/24", $1,$2,$3; exit }
            if ($5 == 16) { printf "%s.%s.0.0/16", $1,$2; exit }
            if ($5 == 8)  { printf "%s.0.0.0/8", $1; exit }
        }
        { printf "%s", $0 }
    '
}

# Check existing list by comparing normalized CIDR forms.
kzm_cidr_exists_normalized() {
    _kzm_f="$1"
    _kzm_cidr="$2"
    [ -f "$_kzm_f" ] || return 1
    _kzm_norm="$(kzm_normalize_ipv4_cidr "$_kzm_cidr")"
    [ -n "$_kzm_norm" ] || return 1
    while IFS= read -r _kzm_line; do
        [ -n "$_kzm_line" ] || continue
        [ "$(kzm_normalize_ipv4_cidr "$_kzm_line")" = "$_kzm_norm" ] && return 0
    done < "$_kzm_f"
    return 1
}

manage_ipset_clients() {
    if ! is_zapret2_installed; then
        echo "$(T TXT_IPV6_NOT_INSTALLED)"
        press_enter_to_continue
        clear
        return 1
    fi
    while true; do
        print_line "-"
        echo "$(T TXT_IPSET_TITLE)"
        print_line "-"
        MODE="$(cat "$IPSET_CLIENT_MODE_FILE" 2>/dev/null)"
        [ -z "$MODE" ] && MODE="all"
        if [ "$MODE" = "list" ]; then
            printf '%b%s%b\n' "${CLR_ORANGE}${CLR_BOLD}" "$(T ipset_mode 'Mod: Secili IP' 'Mode: Selected IPs')" "${CLR_RESET}"
        else
            printf '%b%s%b\n' "${CLR_GREEN}${CLR_BOLD}" "$(T ipset_mode 'Mod: Tum ag' 'Mode: Whole network')" "${CLR_RESET}"
        fi
        echo ""
        echo "$(T TXT_IPSET_1)"
        echo "$(T TXT_IPSET_2)"
        # Option 3: dosya doluysa farkli etiket goster
        if [ -f "$IPSET_CLIENT_FILE" ] && [ -s "$IPSET_CLIENT_FILE" ]; then
            echo "$(T _ ' 3. Secili IPlere Uygula (mevcut liste kullanilir)' ' 3. Apply to Selected IPs (use existing list)')"
        else
            echo "$(T TXT_IPSET_3)"
        fi
        if [ "$MODE" = "list" ] || { [ -f "$IPSET_CLIENT_FILE" ] && [ -s "$IPSET_CLIENT_FILE" ]; }; then
            echo "$(T TXT_IPSET_4)"
            echo "$(T TXT_IPSET_5)"
        fi
        echo "$(T TXT_IPSET_6)"
        echo "$(T TXT_IPSET_7)"
        echo "$(T TXT_IPSET_0)"
        print_line "-"
        if [ "$MODE" = "list" ]; then
            printf "$(T TXT_PROMPT_IPSET)"
        elif [ -f "$IPSET_CLIENT_FILE" ] && [ -s "$IPSET_CLIENT_FILE" ]; then
            printf "$(T TXT_PROMPT_IPSET)"
        else
            printf "$(T TXT_PROMPT_IPSET_BASIC)"
        fi
        read -r ipset_choice || return 0
        echo ""
        case "$ipset_choice" in
            2)
                echo "all" > "$IPSET_CLIENT_MODE_FILE"
                apply_ipset_client_settings
                echo "$(T _ 'Tamam: Zapret2 tum ag icin calisacak.' 'Done: Zapret2 will apply to the whole network.')"
                press_enter_to_continue
                clear
                ;;
            3)
                # Dosya zaten doluysa direkt list modunu aktifle
                if [ -f "$IPSET_CLIENT_FILE" ] && [ -s "$IPSET_CLIENT_FILE" ]; then
                    local _cnt="$(grep -c '[0-9]' "$IPSET_CLIENT_FILE" 2>/dev/null | tr -d ' ')"
                    local _msg_tr="Mevcut liste kullaniliyor: $_cnt IP. Tekli IP eklemek icin menu 4'u kullanin."
                    local _msg_en="Using existing list: $_cnt IPs. Use option 4 to add a single IP."
                    echo "$(T _ "$_msg_tr" "$_msg_en")"
                    echo "list" > "$IPSET_CLIENT_MODE_FILE" 2>/dev/null
                    apply_ipset_client_settings
                    echo "$(T _ 'Tamam: Zapret2 sadece listeli IPlere uygulanacak.' 'Done: Zapret2 will apply only to listed IPs.')"
                    press_enter_to_continue
                    clear
                    continue
                fi
                # Dosya bos veya yok — IP iste
                echo "$(T ipset_bulk_hint 'Not: Tek IP eklemek icin menu 4u kullanin.' 'Note: To add a single IP, use option 4.')"
                echo "Ornek: 192.168.1.10 192.168.1.20 (bosluk/virgul ile ayirabilirsiniz)"
                printf '%s' "IP'leri girin (Enter=iptal): "; read -r ips
                if [ -z "$ips" ]; then
                    echo "$(T ipset_cancelled 'Iptal edildi. Degisiklik yapilmadi.' 'Cancelled. No changes made.')"
                else
                    tmp_ips="/tmp/ipset_clients.$$"
                    echo "$ips" | tr ',;' '  ' | tr ' ' '\n' | sed '/^$/d' > "$tmp_ips"
                    if [ ! -s "$tmp_ips" ]; then
                        rm -f "$tmp_ips" 2>/dev/null
                        echo "$(T ipset_invalid 'Gecersiz IP listesi. Degisiklik yapilmadi.' 'Invalid IP list. No changes made.')"
                    else
                        # Gecersiz formattaki satirlari filtrele (sadece IPv4 kabul et)
                        tmp_ips_valid="/tmp/ipset_clients_valid.$$"
                        invalid_count=0
                        while IFS= read -r _line; do
                            [ -z "$_line" ] && continue
                            if echo "$_line" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
                                echo "$_line" >> "$tmp_ips_valid"
                            else
                                invalid_count=$((invalid_count + 1))
                            fi
                        done < "$tmp_ips"
                        rm -f "$tmp_ips"
                        tmp_ips="$tmp_ips_valid"
                        [ "$invalid_count" -gt 0 ] && echo "$(T _ "$invalid_count gecersiz satir atildi." "$invalid_count invalid line(s) skipped.")"
                        if [ ! -s "$tmp_ips" ]; then
                            rm -f "$tmp_ips" 2>/dev/null
                            echo "$(T ipset_invalid 'Gecersiz IP listesi. Degisiklik yapilmadi.' 'Invalid IP list. No changes made.')"
                        else
                        # No Zapret2 listesinde olan IP'leri filtrele (catisma onleme)
                        if [ -f "$NOZAPRET_FILE" ] && [ -s "$NOZAPRET_FILE" ]; then
                            filtered="/tmp/ipset_clients_filtered.$$"
                            clash_list=""
                            while IFS= read -r ip; do
                                [ -z "$ip" ] && continue
                                if grep -Fqx "$ip" "$NOZAPRET_FILE" 2>/dev/null; then
                                    clash_list="${clash_list} $ip"
                                else
                                    echo "$ip" >> "$filtered"
                                fi
                            done < "$tmp_ips"
                            rm -f "$tmp_ips"
                            if [ -n "$clash_list" ]; then
                                echo "$(T ipset_clash_warn 'Uyari: Su IP(ler) No Zapret2 listesinde oldugu icin eklenmedi:' 'Warning: The following IP(s) are in No Zapret2 list and were skipped:')$clash_list"
                            fi
                            tmp_ips="$filtered"
                        fi
                        if [ -s "$tmp_ips" ]; then
                            mv "$tmp_ips" "$IPSET_CLIENT_FILE" 2>/dev/null
                            echo "list" > "$IPSET_CLIENT_MODE_FILE" 2>/dev/null
                            apply_ipset_client_settings
                            echo "Tamam: Zapret2 sadece bu IP'lere uygulanacak."
                        else
                            rm -f "$tmp_ips" 2>/dev/null
                            echo "$(T ipset_invalid 'Gecersiz IP listesi. Degisiklik yapilmadi.' 'Invalid IP list. No changes made.')"
                        fi
                        fi  # gecersiz IP filtresi sonrasi bos kontrol
                    fi
                fi
                press_enter_to_continue
                clear
                ;;
            1)
                if [ "$MODE" = "list" ]; then
                    show_ipset_client_status
                else
                    echo "IP listesi sadece Secili IP'lere Uygula (mode=list) aktifken gosterilir."
                    show_ipset_client_status
                fi
                press_enter_to_continue
                clear
                ;;
            4)
                MODE="$(cat "$IPSET_CLIENT_MODE_FILE" 2>/dev/null)"
                [ -z "$MODE" ] && MODE="all"
                if [ "$MODE" != "list" ]; then
                    echo "$(T _ 'Bu menu sadece Secili IP modunda kullanilabilir. Once 3u secin.' 'This option is only available in Selected IPs mode. Select option 3 first.')"
                else
                printf '%s' "$(T add_ip_prompt "$TXT_ADD_IP_TR" "$TXT_ADD_IP_EN")"; read -r oneip
                if [ -z "$oneip" ]; then
                    echo "$(T cancelled 'Islem iptal edildi.' 'Cancelled.')"
                    press_enter_to_continue
                    clear
                    continue
                fi
                if echo "$oneip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}(/([0-9]|[1-2][0-9]|3[0-2]))?$'; then
                    touch "$IPSET_CLIENT_FILE" 2>/dev/null
                    kzm_append_unique_line "$IPSET_CLIENT_FILE" "$oneip"
                    apply_ipset_client_settings
                    if [ -f "$NOZAPRET_FILE" ] && grep -Fqx "$oneip" "$NOZAPRET_FILE" 2>/dev/null; then
                        tmpf="/tmp/nozapret_clash.$$"
                        grep -Fvx "$oneip" "$NOZAPRET_FILE" > "$tmpf" 2>/dev/null
                        cp "$tmpf" "$NOZAPRET_FILE" 2>/dev/null
                        rm -f "$tmpf"
                        ipset del "$NOZAPRET_IPSET_NAME" "$oneip" 2>/dev/null
                        nozapret_apply_rules
                        echo "$(T _ 'Tamam: IP eklendi. No Zapret2 listesinden cikarildi.' 'Done: IP added. Removed from No Zapret2 list.')"
                    else
                        echo "$(T _ 'Tamam: IP eklendi.' 'Done: IP added.')"
                    fi
                else
                    echo "$(T _ 'Gecersiz IP!' 'Invalid IP!')"
                fi
                fi
                press_enter_to_continue
                clear
                ;;
            5)
                MODE="$(cat "$IPSET_CLIENT_MODE_FILE" 2>/dev/null)"
                [ -z "$MODE" ] && MODE="all"
                if [ "$MODE" != "list" ]; then
                    echo "$(T _ 'Bu menu sadece Secili IP modunda kullanilabilir. Once 3u secin.' 'This option is only available in Selected IPs mode. Select option 3 first.')"
                else
                printf '%s' "$(T del_ip_prompt "$TXT_DEL_IP_TR" "$TXT_DEL_IP_EN")"; read -r oneip
                if [ -z "$oneip" ]; then
                    echo "$(T cancelled 'Islem iptal edildi.' 'Cancelled.')"
                    press_enter_to_continue
                    clear
                    continue
                fi
                if [ -f "$IPSET_CLIENT_FILE" ]; then
                    tmpf="/tmp/ipset_clients.$$"
                    grep -Fvx "$oneip" "$IPSET_CLIENT_FILE" > "$tmpf" 2>/dev/null
                    cp "$tmpf" "$IPSET_CLIENT_FILE" 2>/dev/null; rm -f "$tmpf"
                    apply_ipset_client_settings
                    echo "$(T _ 'Tamam: IP silindi.' 'Done: IP removed.')"
                else
                    echo "$(T _ 'IP listesi dosyasi yok.' 'IP list file not found.')"
                fi
                fi
                press_enter_to_continue
                clear
                ;;
            6)
                manage_nozapret_menu
                clear
                ;;
            7)
                # VPN sunucu subnetlerini listele ve ekle
                _vpn_list=""
                _vpn_idx=0
                # WireGuard sunucularini tara
                for _wg in $(LD_LIBRARY_PATH= ndmc -c 'show interface' 2>/dev/null | awk '/interface-name:.*Wireguard/{print $NF}'); do
                    _wg_info="$(LD_LIBRARY_PATH= ndmc -c "show interface ${_wg}" 2>/dev/null)"
                    _wg_link="$(printf '%s\n' "$_wg_info" | awk '/^[[:space:]]+link:/{print $2; exit}')"
                    _wg_addr="$(printf '%s\n' "$_wg_info" | awk '/^[[:space:]]+address:/{print $2; exit}')"
                    _wg_desc="$(printf '%s\n' "$_wg_info" | awk '/^[[:space:]]+description:/{$1=""; sub(/^[ \t]+/,"",$0); print; exit}')"
                    _wg_local="$(printf '%s\n' "$_wg_info" | awk '/local-endpoint-address:/{print $2; exit}')"
                    [ -z "$_wg_addr" ] && continue
                    # Sadece aktif (link: up) olanlari goster
                    [ "$_wg_link" != "up" ] && continue
                    # local-endpoint-address dolu olanlar client (Proton gibi) — atla
                    [ -n "$_wg_local" ] && [ "$_wg_local" != "0.0.0.0" ] && continue
                    # Prefix yoksa /24 ekle; interface IP ise network CIDR'a cevir
                    case "$_wg_addr" in
                        */*) _wg_subnet="$(kzm_normalize_ipv4_cidr "$_wg_addr")" ;;
                        *)   _wg_subnet="$(kzm_normalize_ipv4_cidr "${_wg_addr}/24")" ;;
                    esac
                    _vpn_idx=$((_vpn_idx+1))
                    _already=""; kzm_cidr_exists_normalized "$IPSET_CLIENT_FILE" "$_wg_subnet" 2>/dev/null && _already=" ${CLR_GREEN}$(T _ "[EKLENDI]" "[ADDED]")${CLR_RESET}"
                    _vpn_list="${_vpn_list}${_vpn_idx}) ${_wg_desc:-$_wg} - ${_wg_subnet}${_already}\n"
                    eval "_vpn_subnet_${_vpn_idx}=${_wg_subnet}"
                done
                # IKEv2 sunucusunu tara
                _ike_info="$(LD_LIBRARY_PATH= ndmc -c 'show crypto map VirtualIPServerIKE2' 2>/dev/null)"
                if [ -n "$_ike_info" ]; then
                    _ike_begin="$(printf '%s\n' "$_ike_info" | awk '/begin:/{print $2; exit}')"
                    _ike_end="$(printf '%s\n' "$_ike_info" | awk '/end:/{print $2; exit}')"
                    if [ -n "$_ike_begin" ]; then
                        _ike_subnet="$(printf '%s\n' "$_ike_begin" | sed 's/\.[0-9][0-9]*$/.0/')"/24
                        _vpn_idx=$((_vpn_idx+1))
                        _already=""; grep -qxF "$_ike_subnet" "$IPSET_CLIENT_FILE" 2>/dev/null && _already=" ${CLR_GREEN}$(T _ "[EKLENDI]" "[ADDED]")${CLR_RESET}"
                        _vpn_list="${_vpn_list}${_vpn_idx}) IKEv2/IPsec - ${_ike_subnet}${_already}\n"
                        eval "_vpn_subnet_${_vpn_idx}=${_ike_subnet}"
                    fi
                fi
                # L2TP/IPsec sunucusunu tara
                _l2tp_range="$(LD_LIBRARY_PATH= ndmc -c 'show running-config' 2>/dev/null | awk '/l2tp-server range/{print $3; exit}')"
                if [ -n "$_l2tp_range" ]; then
                    _l2tp_subnet="$(printf '%s\n' "$_l2tp_range" | sed 's/\.[0-9][0-9]*$/.0/')"/24
                    _vpn_idx=$((_vpn_idx+1))
                    _already=""; grep -qxF "$_l2tp_subnet" "$IPSET_CLIENT_FILE" 2>/dev/null && _already=" ${CLR_GREEN}$(T _ "[EKLENDI]" "[ADDED]")${CLR_RESET}"
                    _vpn_list="${_vpn_list}${_vpn_idx}) L2TP/IPsec - ${_l2tp_subnet}${_already}\n"
                    eval "_vpn_subnet_${_vpn_idx}=${_l2tp_subnet}"
                fi
                if [ "$_vpn_idx" -eq 0 ]; then
                    print_status WARN "$(T _ 'Aktif VPN sunucu bulunamadi.' 'No active VPN server found.')"
                    press_enter_to_continue
                    clear
                    continue
                fi
                print_line "-"
                printf "$(T _ 'VPN Sunucu Subnetleri:\n' 'VPN Server Subnets:\n')"
                printf '%b' "$_vpn_list"
                echo ""
                printf '%s' "$(T _ 'Secim (0=iptal): ' 'Select (0=cancel): ')"; read -r _vpn_choice
                if [ -z "$_vpn_choice" ] || [ "$_vpn_choice" = "0" ]; then
                    clear; continue
                fi
                eval "_add_subnet=\${_vpn_subnet_${_vpn_choice}:-}"
                if [ -z "$_add_subnet" ]; then
                    print_status WARN "$(T _ 'Gecersiz secim.' 'Invalid selection.')"
                    press_enter_to_continue
                    clear
                    continue
                fi
                touch "$IPSET_CLIENT_FILE" 2>/dev/null
                _add_subnet="$(kzm_normalize_ipv4_cidr "$_add_subnet")"
                if kzm_cidr_exists_normalized "$IPSET_CLIENT_FILE" "$_add_subnet" 2>/dev/null; then
                    print_status INFO "$(T _ 'Bu subnet zaten listede.' 'This subnet is already in the list.')"
                else
                    kzm_append_unique_line "$IPSET_CLIENT_FILE" "$_add_subnet"
                    apply_ipset_client_settings
                    print_status PASS "$(T _ 'Subnet eklendi.' 'Subnet added.'): $_add_subnet"
                fi
                press_enter_to_continue
                clear
                ;;
            0)
                echo "Ana menuye donuluyor..."
                break
                ;;
            *)
                echo "$(T invalid_main 'Gecersiz secim! Lutfen 0 ile 11 arasinda bir sayi veya L girin.' 'Invalid choice! Please enter a number between 0 and 11 or L.')"
                press_enter_to_continue
                clear
                ;;
        esac
        echo ""
    done
    return 0
}
# -------------------------------------------------------------------
# nozapret (Muafiyet) Alt-Menusu
# -------------------------------------------------------------------
# ipset'i olusturur (yoksa) ve dosyadan yukler
nozapret_ensure_and_load() {
    ipset list "$NOZAPRET_IPSET_NAME" >/dev/null 2>&1 || \
        ipset create "$NOZAPRET_IPSET_NAME" hash:ip 2>/dev/null
    if [ -f "$NOZAPRET_FILE" ]; then
        while IFS= read -r line; do
            line="${line%%#*}"
            line="$(echo "$line" | tr -d '[:space:]')"
            [ -z "$line" ] && continue
            ipset -exist add "$NOZAPRET_IPSET_NAME" "$line" 2>/dev/null
        done < "$NOZAPRET_FILE"
    fi
}
# iptables RETURN kurali ekler (nozapret listesindeki IP'ler Zapret2'den muaf)
nozapret_apply_rules() {
    local wan_if
    wan_if="$(get_wan_if 2>/dev/null)"
    # Eski kurallari temizle
    nozapret_remove_rules
    # ipset'i yukle
    nozapret_ensure_and_load
    # RETURN kurali: nozapret listesindeki kaynak IP'ler NFQUEUE'ya gitmez
    if [ -n "$wan_if" ]; then
        iptables -t mangle -I POSTROUTING -o "$wan_if" \
            -m set --match-set "$NOZAPRET_IPSET_NAME" src \
            -j RETURN 2>/dev/null
    else
        iptables -t mangle -I POSTROUTING \
            -m set --match-set "$NOZAPRET_IPSET_NAME" src \
            -j RETURN 2>/dev/null
    fi
}
# iptables kurallarini temizler
nozapret_remove_rules() {
    local _wan="$(get_wan_if 2>/dev/null)"
    # Interface ile eklenenmis kurallari temizle
    [ -n "$_wan" ] && while iptables -t mangle -D POSTROUTING -o "$_wan" \
        -m set --match-set "$NOZAPRET_IPSET_NAME" src \
        -j RETURN 2>/dev/null; do :; done
    # Interface olmadan eklenenmis kurallari temizle
    while iptables -t mangle -D POSTROUTING \
        -m set --match-set "$NOZAPRET_IPSET_NAME" src \
        -j RETURN 2>/dev/null; do :; done
}
# Mevcut muafiyet listesini gosterir
nozapret_show_status() {
    print_line "-"
    printf '%b %s%b\n' "${CLR_CYAN}${CLR_BOLD}" "$(T TXT_NOZAPRET_TITLE)" "${CLR_RESET}"
    print_line "-"
    if [ ! -f "$NOZAPRET_FILE" ] || [ ! -s "$NOZAPRET_FILE" ]; then
        echo "  $(T TXT_NOZAPRET_EMPTY)"
    else
        local i=0
        while IFS= read -r line; do
            line="${line%%#*}"
            line="$(echo "$line" | tr -d '[:space:]')"
            [ -z "$line" ] && continue
            i=$((i+1))
            printf '  %b%2d.%b %s\n' "${CLR_ORANGE}${CLR_BOLD}" "$i" "${CLR_RESET}" "$line"
        done < "$NOZAPRET_FILE"
        if [ "$i" -eq 0 ]; then
            echo "  $(T TXT_NOZAPRET_EMPTY)"
        fi
    fi
    print_line "-"
}
# nozapret alt-menusu
manage_nozapret_menu() {
    while true; do
        clear
        print_line "="
        printf '%b  %s%b\n' "${CLR_CYAN}${CLR_BOLD}" "$(T TXT_NOZAPRET_TITLE)" "${CLR_RESET}"
        echo ""
        printf '  %s\n' "$(T TXT_NOZAPRET_DESC)"
        print_line "="
        echo "$(T TXT_NOZAPRET_1)"
        echo "$(T TXT_NOZAPRET_2)"
        echo "$(T TXT_NOZAPRET_3)"
        echo "$(T TXT_NOZAPRET_4)"
        echo "$(T TXT_NOZAPRET_0)"
        print_line "-"
        printf "$(T TXT_NOZAPRET_PROMPT)"
        read -r noz_choice || return 0
        echo ""
        case "$noz_choice" in
            1)
                nozapret_show_status
                press_enter_to_continue
                ;;
            2)
                printf "$(T TXT_NOZAPRET_ADD)"
                read -r noz_ip
                if [ -z "$noz_ip" ]; then
                    echo "$(T cancelled 'Iptal edildi.' 'Cancelled.')"
                elif echo "$noz_ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
                    mkdir -p "$(dirname "$NOZAPRET_FILE")"
                    touch "$NOZAPRET_FILE"
                    if grep -Fqx "$noz_ip" "$NOZAPRET_FILE" 2>/dev/null; then
                        echo "$(T TXT_NOZAPRET_EXISTS)"
                    else
                        echo "$noz_ip" >> "$NOZAPRET_FILE"
                        nozapret_apply_rules
                        # Ayni IP zapret2_clients listesinde varsa cikar (catisma onleme)
                        if [ -f "$IPSET_CLIENT_FILE" ] && grep -Fqx "$noz_ip" "$IPSET_CLIENT_FILE" 2>/dev/null; then
                            tmpf="/tmp/ipset_clients_clash.$$"
                            grep -Fvx "$noz_ip" "$IPSET_CLIENT_FILE" > "$tmpf" 2>/dev/null
                            cp "$tmpf" "$IPSET_CLIENT_FILE" 2>/dev/null; rm -f "$tmpf"
                            apply_ipset_client_settings
                            echo "$(T TXT_NOZAPRET_ADDED) $(T ipset_clash_removed 'Not: IP, Secili IP listesinden de cikarildi.' 'Note: IP also removed from Selected IPs list.')"
                        else
                            echo "$(T TXT_NOZAPRET_ADDED)"
                        fi
                    fi
                else
                    echo "$(T TXT_NOZAPRET_INVALID_IP)"
                fi
                press_enter_to_continue
                ;;
            3)
                printf "$(T TXT_NOZAPRET_DEL)"
                read -r noz_ip
                if [ -z "$noz_ip" ]; then
                    echo "$(T cancelled 'Iptal edildi.' 'Cancelled.')"
                elif [ -f "$NOZAPRET_FILE" ] && grep -Fqx "$noz_ip" "$NOZAPRET_FILE" 2>/dev/null; then
                    tmpf="/tmp/nozapret_del.$$"
                    grep -Fvx "$noz_ip" "$NOZAPRET_FILE" > "$tmpf" 2>/dev/null
                    cp "$tmpf" "$NOZAPRET_FILE" 2>/dev/null; rm -f "$tmpf"
                    ipset del "$NOZAPRET_IPSET_NAME" "$noz_ip" 2>/dev/null
                    nozapret_apply_rules
                    echo "$(T TXT_NOZAPRET_REMOVED)"
                else
                    echo "$(T TXT_NOZAPRET_NOTFOUND)"
                fi
                press_enter_to_continue
                ;;
            4)
                printf "$(T TXT_NOZAPRET_CONFIRM_CLEAR)"
                read -r confirm
                case "$confirm" in
                    e|E|y|Y)
                        rm -f "$NOZAPRET_FILE"
                        ipset flush "$NOZAPRET_IPSET_NAME" 2>/dev/null
                        nozapret_remove_rules
                        echo "$(T TXT_NOZAPRET_CLEARED)"
                        ;;
                    *)
                        echo "$(T cancelled 'Iptal edildi.' 'Cancelled.')"
                        ;;
                esac
                press_enter_to_continue
                ;;
            0)
                break
                ;;
            *)
                echo "$(T invalid_main 'Gecersiz secim!' 'Invalid choice!')"
                press_enter_to_continue
                ;;
        esac
    done
}
# Kurulumdan sonra gereksiz dosyalari temizler
cleanup_files_after_extracted() {
    echo "$(T TXT_CLEANUP_REMOVING)"
    for file in \
        /opt/zapret2/binaries/mac64 \
        /opt/zapret2/binaries/linux-ppc \
        /opt/zapret2/binaries/linux-lexra \
        /opt/zapret2/binaries/linux-x86 \
        /opt/zapret2/binaries/linux-x86_64 \
        /opt/zapret2/binaries/freebsd-x86_64 \
        /opt/zapret2/binaries/android-arm \
        /opt/zapret2/binaries/android-arm64 \
        /opt/zapret2/binaries/android-x86 \
        /opt/zapret2/binaries/android-x86_64 \
        /opt/zapret2/binaries/windows-x86 \
        /opt/zapret2/binaries/windows-x86_64 \
        /opt/tmp/zapret2-*.tar.gz
    do
        [ -e "$file" ] && rm -rf "$file"
    done
    echo "$(T TXT_CLEANUP_REMOVED)"
}
# Kaldirma sirasinda kalan iptables/ipset kalintilarini temizler (zapret kaldirildiktan sonra bile kural kalabiliyor)
cleanup_zapret_firewall_leftovers() {
    command -v iptables >/dev/null 2>&1 || return 0
    local Q="300"
    _del_nfqueue_lines() {
        local table="$1" chain="$2" ln
        while true; do
            if [ -n "$table" ]; then
                ln="$(iptables -t "$table" -L "$chain" -n --line-numbers 2>/dev/null \
                    | grep -E "NFQUEUE" | grep -E "num $Q|queue-num $Q" | head -n 1 | awk '{print $1}')"
                [ -n "$ln" ] || break
                iptables -t "$table" -D "$chain" "$ln" 2>/dev/null
            else
                ln="$(iptables -L "$chain" -n --line-numbers 2>/dev/null \
                    | grep -E "NFQUEUE" | grep -E "num $Q|queue-num $Q" | head -n 1 | awk '{print $1}')"
                [ -n "$ln" ] || break
                iptables -D "$chain" "$ln" 2>/dev/null
            fi
        done
    }
    # mangle
    for c in PREROUTING INPUT FORWARD OUTPUT POSTROUTING; do
        _del_nfqueue_lines mangle "$c"
    done
    # filter
    for c in INPUT FORWARD OUTPUT; do
        _del_nfqueue_lines "" "$c"
    done
    # ipset kalintilari
    if command -v ipset >/dev/null 2>&1; then
        for s in zapret zapret2_clients nozapret ipban; do
            ipset list "$s" >/dev/null 2>&1 && ipset flush "$s" >/dev/null 2>&1
            ipset list "$s" >/dev/null 2>&1 && ipset destroy "$s" >/dev/null 2>&1
        done
    fi
    # netfilter hook kalintilari (disabled dosyalar dahil)
rm -f /opt/etc/ndm/netfilter.d/000-zapret2.sh           /opt/etc/ndm/netfilter.d/000-zapret2.sh.disabled           /opt/etc/ndm/netfilter.d/001-zapret-force-nfqueue.sh           /opt/etc/ndm/netfilter.d/001-zapret-force-nfqueue.sh.disabled           /opt/etc/ndm/netfilter.d/001-zapret-force-nfqueue.sh.disabled.disabled           /opt/etc/ndm/netfilter.d/001-zapret-ipset.sh           /opt/etc/ndm/netfilter.d/001-zapret-ipset.sh.disabled           /opt/etc/ndm/netfilter.d/001-zapret-ipset.sh.disabled.disabled 2>/dev/null
# autostart linkleri (varsa)
rm -f /opt/etc/init.d/S90-zapret2 /opt/etc/init.d/S00fix 2>/dev/null
rm -f /tmp/.zapret2_paused 2>/dev/null
return 0
}
# Kaldirmadan sonra kalan dosyalari temizler
# --- UNINSTALL KALINTI TEMIZLIGI: NFQUEUE (qnum 300) ---
remove_nfqueue_rules_300() {
    command -v iptables >/dev/null 2>&1 || return 0
    # mangle
    for c in PREROUTING INPUT FORWARD OUTPUT POSTROUTING; do
        while true; do
            ln="$(iptables -t mangle -L "$c" -n --line-numbers 2>/dev/null | sed -n "s/^ *\\([0-9]\\+\\) .*NFQUEUE num 300 .*/\\1/p" | head -n 1)"
            [ -n "$ln" ] || break
            iptables -t mangle -D "$c" "$ln" 2>/dev/null
        done
    done
    # filter
    for c in INPUT FORWARD OUTPUT; do
        while true; do
            ln="$(iptables -L "$c" -n --line-numbers 2>/dev/null | sed -n "s/^ *\\([0-9]\\+\\) .*NFQUEUE num 300 .*/\\1/p" | head -n 1)"
            [ -n "$ln" ] || break
            iptables -D "$c" "$ln" 2>/dev/null
        done
    done
}
cleanup_files_after_uninstall() {
    cleanup_zapret_firewall_leftovers
    rm -rf /opt/zapret2 \
           /opt/etc/init.d/S00fix \
           /opt/etc/init.d/S90-zapret2 \
           /opt/etc/ndm/netfilter.d/000-zapret2.sh &>/dev/null  
    return 0
}
# Uninstall sonrasi sistem temiz mi kontrol eder
# Donus: 0 = temiz, 1 = kalinti var
verify_zapret_clean() {
    local _dirty=0
    # nfqws2 hala calisiyor mu? (herhangi bir yolda)
    if pgrep -f "nfqws2" >/dev/null 2>&1; then
        _dirty=1
    fi
    # NFQUEUE kurali kaldi mi?
    if command -v iptables >/dev/null 2>&1 && iptables-save 2>/dev/null | grep -q "NFQUEUE"; then
        _dirty=1
    fi
    # ipset kalintisi?
    if command -v ipset >/dev/null 2>&1; then
        for _s in zapret zapret2_clients nozapret ipban; do
            ipset list "$_s" >/dev/null 2>&1 && { _dirty=1; break; }
        done
    fi
    # /opt/zapret2 hala var mi?
    [ -d /opt/zapret2 ] && _dirty=1
    return $_dirty
}
# Zapret2 kurulu olmasa bile (kaldirmadan sonra) NFQUEUE/IPSET kalintilarini temizler
cleanup_only_leftovers() {
    print_line "-"
    echo " Kalinti Temizligi (Zapret2 olmasa da calisir)"
    print_line "-"
    echo "Bu islem, NFQUEUE iptables kurallarini ve zapret2'ye ait ipset/netfilter kalintilarini temizler."
    printf '%s' "$(T _ 'Devam edilsin mi? (e/h): ' 'Continue? (y/n): ')"; read -r _c
    echo "$_c" | grep -qi '^[ey]' || { echo "$(T _ 'Iptal edildi.' 'Cancelled.')"; return 0; }
    cleanup_zapret_firewall_leftovers
    remove_nfqueue_rules_300
    # ipset mod dosyalari (opsiyonel)
    rm -f /opt/zapret2/ipset_clients_mode /opt/zapret2/ipset_clients.txt /opt/zapret2/wan_if 2>/dev/null
    echo "Kalinti temizligi tamamlandi."
    press_enter_to_continue
    clear
    return 0
}
# Zapret2'yi kaldirir
# _silent=1 ise onay sorulmaz, press_enter/clear yapilmaz (kzm2_full_uninstall icin)
uninstall_zapret2() {
    local _silent="${1:-0}"
if ! is_zapret2_installed; then
        echo "$(T TXT_UNINSTALL_NOT_INSTALLED)"
        echo ""
        if verify_zapret_clean; then
            echo "$(T _ 'Sistem temiz, kalinti bulunamadi.' 'System is clean, no leftovers found.')"
            [ "$_silent" = "1" ] || press_enter_to_continue
            [ "$_silent" = "1" ] || clear
            return 0
        fi
        echo "$(T _ 'Ama NFQUEUE/IPSET gibi kalintilar kalmis olabilir.' 'But NFQUEUE/IPSET leftovers may still exist.')"
        printf "%s" "$(T _ 'Kalintilari temizlemek ister misiniz? (e/h): ' 'Clean up leftovers? (y/n): ')"; read -r _cc
        if echo "$_cc" | grep -qi '^[ey]'; then
            killall nfqws2 >/dev/null 2>&1
            killall -9 nfqws2 >/dev/null 2>&1
            cleanup_zapret_firewall_leftovers
            remove_nfqueue_rules_300
            rm -rf /opt/zapret2 /opt/bin/nfqws /opt/sbin/nfqws 2>/dev/null
            echo "$(T _ 'Kalintilar temizlendi.' 'Leftovers cleaned.')"
        else
            echo "$(T _ 'Iptal edildi.' 'Cancelled.')"
        fi
        [ "$_silent" = "1" ] || press_enter_to_continue
        [ "$_silent" = "1" ] || clear
        return 0
    fi
    if [ "$_silent" != "1" ]; then
        printf "%s" "$(T _ 'Zapret2 kaldirilsin mi? (e/h): ' 'Remove Zapret2? (y/n): ')"; read -r uninstall_confirmation
        case "$uninstall_confirmation" in
            e|E|y|Y) ;;
            *) echo "$(T _ 'Iptal edildi.' 'Cancelled.')"; return 0 ;;
        esac
    fi
    is_zapret2_running && stop_zapret2 1
    cleanup_zapret_firewall_leftovers
    echo "$(T TXT_UNINSTALL_REMOVING)"
    if ! echo "y" | /opt/zapret2/uninstall_easy.sh >/dev/null 2>&1; then
        if [ "$_silent" = "1" ]; then
            echo "$(T _ 'Kendi kaldirma aracimiz calistiriliyor...' 'Running built-in cleanup...')"
            cleanup_files_after_uninstall
        else
            printf "%s" "$(T _ 'Zapret2 kaldirma betigi bulunamadi. Kendi aracimizla kaldirilsin mi? (e/h): ' 'Zapret2 uninstall script not found. Use built-in cleanup? (y/n): ')"; read -r manual_cleanup_confirmation
            if echo "$manual_cleanup_confirmation" | grep -qi '^[ey]'; then
                echo "$(T _ 'Kendi kaldirma aracimiz calistiriliyor...' 'Running built-in cleanup...')"
                cleanup_files_after_uninstall
                return 0
            else
                echo "$(T _ 'Iptal edildi.' 'Cancelled.')"
                return 1
            fi
        fi
    fi
    cleanup_files_after_uninstall
    # Verification: hala kalinti var mi? Varsa sessiz ikinci pass.
    if ! verify_zapret_clean; then
        killall -9 nfqws2 >/dev/null 2>&1
        flush_all_nfqueue_rules
        cleanup_zapret_firewall_leftovers
        rm -rf /opt/zapret2 /opt/bin/nfqws /opt/sbin/nfqws 2>/dev/null
    fi
    echo "$(T TXT_UNINSTALL_OK)"
    [ "$_silent" = "1" ] || press_enter_to_continue
    [ "$_silent" = "1" ] || clear
    return 0
}

run_zapret2_install_easy() {
    # Zapret2 install_easy.sh on Keenetic may ask an extra unsupported-system
    # confirmation before firewall/IPv6 questions. Zapret2 v0.9.5.2+ may also
    # ask LAN/WAN interface questions. KZM2 accepts defaults (LAN=NONE, WAN=ANY)
    # and enforces the selected WAN rules after installation.
    # First try the standard sequence, then retry with a leading "y" if needed.
    local _ipv6="${1:-n}"
    local _log="/tmp/kzm2_install_easy.log"
    [ -x /opt/zapret2/install_easy.sh ] || chmod +x /opt/zapret2/install_easy.sh 2>/dev/null
    : > "$_log" 2>/dev/null
    (
        echo "1"            # firewall: iptables
        echo "$_ipv6"        # IPv6 support
        echo "1"            # filtering mode: none
        echo "y"            # enable NFQWS2
        echo "n"            # edit config: no
        echo ""             # LAN interface: default NONE (if asked)
        echo ""             # WAN interface: default ANY (if asked)
    ) | /opt/zapret2/install_easy.sh >"$_log" 2>&1
    [ "$?" -eq 0 ] && return 0
    printf '
--- retry: unsupported-system confirmation ---
' >>"$_log" 2>/dev/null
    (
        echo "y"            # continue on unsupported generic linux/Keenetic
        echo "1"            # firewall: iptables
        echo "$_ipv6"        # IPv6 support
        echo "1"            # filtering mode: none
        echo "y"            # enable NFQWS2
        echo "n"            # edit config: no
        echo ""             # LAN interface: default NONE (if asked)
        echo ""             # WAN interface: default ANY (if asked)
    ) | /opt/zapret2/install_easy.sh >>"$_log" 2>&1
    return $?
}
# Zapret2'yi kurar
install_zapret2() {
    if is_zapret2_installed; then
        echo "$(T TXT_INSTALL_ALREADY)"
        return 1
    fi
    echo "$(T _ 'OPKG paketleri denetleniyor, eksik olan varsa indirilip kurulacaktir...' 'Checking OPKG packages, missing ones will be downloaded and installed...')"
    opkg update >/dev/null 2>&1
    opkg install coreutils-sort curl wget-ssl grep gzip ipset iptables kmod_ndms xtables-addons_legacy cron >/dev/null 2>&1 || \
    { echo "$(T TXT_INSTALL_PKG_FAIL)"; return 1; }

    # Component check after package installation
    if ! check_keenetic_components; then
        return 1
    fi
    
    echo "$(T TXT_INSTALL_INSTALLING)"
    ZAPRET2_API_URL="https://api.github.com/repos/bol-van/zapret2/releases/latest"
    ZAP_DATA=$(curl -s "$ZAPRET2_API_URL")
    # Sadece ana tarball'u sec: zapret2-vX.Y.Z.tar.gz
    # openwrt-embedded, arch-specific varyantlari atla
    ZAPRET2_ARCHIVE_URL=$(printf '%s\n' "$ZAP_DATA" \
        | grep '"browser_download_url".*tar\.gz"' \
        | grep -v 'openwrt-embedded\|mipsel\|mips\|aarch64\|armv7\|x86_64\|lexra\|openwrt' \
        | head -n1 \
        | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')
    # Fallback: eger filtre cok agresifse ilk tar.gz'i dene
    [ -z "$ZAPRET2_ARCHIVE_URL" ] && \
        ZAPRET2_ARCHIVE_URL=$(printf '%s\n' "$ZAP_DATA" \
            | grep '"browser_download_url".*tar\.gz"' \
            | grep -v 'openwrt-embedded' \
            | head -n1 \
            | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')
    ZAPRET2_VER=$(printf '%s\n' "$ZAP_DATA" \
        | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
    ZAPRET2_ARCHIVE_NAME=$(basename "$ZAPRET2_ARCHIVE_URL")
    ARCHIVE="/opt/tmp/$ZAPRET2_ARCHIVE_NAME"
    DIR="/opt/zapret2"
    if [ -z "$ZAPRET2_ARCHIVE_URL" ]; then
        echo "$(T _ 'HATA: Zapret2 en guncel surumu alinamadi. GitHub API erisilebilir mi?' 'ERROR: Could not fetch latest Zapret2 version. Is GitHub API accessible?')"
        return 1
    fi
    print_status INFO "$(T _ "Indiriliyor: $ZAPRET2_ARCHIVE_NAME ($ZAPRET2_VER)" "Downloading: $ZAPRET2_ARCHIVE_NAME ($ZAPRET2_VER)")"
    mkdir -p /opt/tmp
    curl -L -o "$ARCHIVE" "$ZAPRET2_ARCHIVE_URL" 2>/dev/null || \
        { echo "$(T _ 'HATA: Arsiv indirilemedi.' 'ERROR: Failed to download archive.')"; return 1; }
    rm -rf "$DIR"
    tar -xzf "$ARCHIVE" -C /opt/tmp >/dev/null 2>&1 || \
        { echo "$(T _ 'HATA: Arsiv acilamadi.' 'ERROR: Failed to extract archive.')"; return 1; }
    EXTRACTED_DIR=$(tar -tzf "$ARCHIVE" 2>/dev/null | head -1 | cut -f1 -d"/")
    mv "/opt/tmp/$EXTRACTED_DIR" "$DIR" || \
        { echo "$(T _ 'HATA: Dosya tasinamadi.' 'ERROR: Failed to move files.')"; return 1; }
    # Surum bilgisini kaydet
    echo "$ZAPRET2_VER" > /opt/zapret2/version
    echo "$(T TXT_INSTALL_OK)"
    cleanup_files_after_extracted
    keenetic_compatibility || echo "$(T TXT_INSTALL_COMPAT_WARN)"
    printf "%s " "$(T _ 'Zapret2 icin IPv6 destegi etkinlestirilsin mi? (e/h):' 'Enable IPv6 support for Zapret2? (y/n):')"; read -r ipv6_ans
    if echo "$ipv6_ans" | grep -qi "^[ey]"; then
        ZAPRET_IPV6="y"
    else
        ZAPRET_IPV6="n"
    fi
    echo "$(T TXT_INSTALL_CFG_RUNNING)"
    IPV6_ANSWER="$ZAPRET_IPV6"
    # WAN arayuzunu belirle
    select_wan_if
    # install_easy.sh zapret2'de TPWS yok - sadece nfqws2 aktif.
    # Zapret2 v0.9.5.2+ LAN/WAN interface sorabilir.
    # KZM2 varsayilan NONE/ANY gecip ardindan WAN kurallarini kendisi uygular.
    # Soru sirasi (zapret2 install_easy.sh):
    #   1. Guvenlik duvari (iptables=1 / nftables=2)
    #   2. IPv6 (y/n)
    #   3. Filtreleme modu (none=1)
    #   4. NFQWS2 etkinlestir (y/n)
    #   5. Yapilandirmayi duzenle (y/n)
    #   6. LAN interface (Enter=NONE, sorulursa)
    #   7. WAN interface (Enter=ANY, sorulursa)
    run_zapret2_install_easy "$IPV6_ANSWER" || \
    { echo "$(T TXT_INSTALL_CFG_FAIL)"; echo "Log: /tmp/kzm2_install_easy.log"; return 1; }
    
    echo "$(T TXT_INSTALL_KEENETIC_CFG)"
    fix_keenetic_udp
    update_kernel_module_config
    update_nfqws_parameters
    disable_total_packet
    allow_firewall
    add_auto_start_zapret2
    fix_zapret2_runtime_permissions
    kzm2_load_zapret2_kmods >/dev/null 2>&1
    echo "$(T TXT_INSTALL_DONE)"
    sync_zapret_iface_wan_config
    restart_zapret2
    cleanup_nfqueue_rules_except_selected_wan
    # HealthMon henuz aktif degilse kurulumda otomatik etkinlestir
    healthmon_load_config 2>/dev/null
    if [ "${HM_ENABLE:-0}" != "1" ]; then
        HM_ENABLE="1"
        HM_ZAPRET_AUTORESTART="1"
        healthmon_write_config 2>/dev/null
        healthmon_autostart_install 2>/dev/null
        healthmon_start 2>/dev/null
    fi
    press_enter_to_continue
	clear 
    return 0 
}
# --- Betik (Manager) Surum Kontrolu (GitHub Releases) ---
get_manager_latest_version() {
    # GitHub API: releases/latest -> tag_name
    # curl yoksa wget denenir
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "https://api.github.com/repos/RevolutionTR/keenetic-zapret2-manager/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n 1
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "https://api.github.com/repos/RevolutionTR/keenetic-zapret2-manager/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n 1
    else
        echo ""
    fi
}
# --- Version compare helper (returns 0 if $1 > $2) ---
ver_is_newer() {
    # usage: ver_is_newer "v26.1.24.2" "v26.1.24"
    local _va _vb _a1 _a2 _a3 _a4 _b1 _b2 _b3 _b4
    _va="$(echo "${1#v}" | tr -cd '0-9.')"
    _vb="$(echo "${2#v}" | tr -cd '0-9.')"
    _a1=0; _a2=0; _a3=0; _a4=0
    _b1=0; _b2=0; _b3=0; _b4=0
    IFS=. read -r _a1 _a2 _a3 _a4 <<EOF2
$_va
EOF2
    IFS=. read -r _b1 _b2 _b3 _b4 <<EOF2
$_vb
EOF2
    _a1=${_a1:-0}; _a2=${_a2:-0}; _a3=${_a3:-0}; _a4=${_a4:-0}
    _b1=${_b1:-0}; _b2=${_b2:-0}; _b3=${_b3:-0}; _b4=${_b4:-0}
    [ "$_a1" -gt "$_b1" ] && return 0
    [ "$_a1" -lt "$_b1" ] && return 1
    [ "$_a2" -gt "$_b2" ] && return 0
    [ "$_a2" -lt "$_b2" ] && return 1
    [ "$_a3" -gt "$_b3" ] && return 0
    [ "$_a3" -lt "$_b3" ] && return 1
    [ "$_a4" -gt "$_b4" ] && return 0
    return 1
}
download_file() {
    # usage: download_file URL OUTFILE
    _url="$1"; _out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -L -s -o "$_out" "$_url" && [ -s "$_out" ] && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$_out" "$_url" && [ -s "$_out" ] && return 0
    fi
    return 1
}
# Resolve current KZM2 script path safely (daemon/telegram/web compatible)
kzm2_resolve_script_path() {
    local _p
    for _p in "$KZM2_SCRIPT_PATH" /opt/lib/opkg/keenetic_zapret2_manager.sh "$(readlink -f "$0" 2>/dev/null)"; do
        [ -n "$_p" ] || continue
        [ -f "$_p" ] || continue
        grep -q 'Keenetic Zapret2 Manager' "$_p" 2>/dev/null || continue
        printf '%s' "$_p"
        return 0
    done
    printf '%s' "$KZM2_SCRIPT_PATH"
}
# Read current installed script version from disk (daemon-safe; handles manual edits)
kzm2_get_installed_script_version() {
    local v="" _p
    _p="$(kzm2_resolve_script_path)"
    v="$(grep -m1 '^SCRIPT_VERSION=' "$_p" 2>/dev/null | cut -d'"' -f2)"
    [ -z "$v" ] && v="$SCRIPT_VERSION"
    echo "$v"
}
# Basarili KZM guncellemesinden sonra Telegram bot ve HealthMon'u yeniden baslatir.
# Sadece manuel guncelleme (interaktif) icin cagrilir.
_kzm2_restart_services_after_update() {
    # Izinleri duzelt (restore/guncelleme sonrasi bozulmus olabilir)
    fix_zapret2_runtime_permissions 2>/dev/null || true
    if ps 2>/dev/null | grep -q '[t]elegram-daemon'; then
        print_status INFO "$(T _ 'Telegram bot yeniden baslatiliyor...' 'Restarting Telegram bot...')"
        telegram_bot_stop
        telegram_bot_start
    fi
    if healthmon_is_running 2>/dev/null; then
        print_status INFO "$(T _ 'HealthMon yeniden baslatiliyor...' 'Restarting HealthMon...')"
        healthmon_stop
        healthmon_start
    fi
    if [ -d "$KZM2_GUI_DIR" ]; then
        print_status INFO "$(T _ 'Web Panel guncelleniyor...' 'Updating Web Panel...')"
        (export KZM2_SKIP_LOCK=1; sh "/opt/lib/opkg/keenetic_zapret2_manager.sh" --update-gui </dev/null >/dev/null 2>&1)
        print_status PASS "$(T _ 'Web Panel guncellendi.' 'Web Panel updated.')"
    fi
}
update_manager_script() {
    local _force="${1:-0}"  # 1 = SHA uyusmazligi nedeniyle zorunlu yeniden indirme
    TARGET_SCRIPT="$KZM2_SCRIPT_PATH"
    local repo="RevolutionTR/keenetic-zapret2-manager"
    local api="https://api.github.com/repos/${repo}/releases/latest"
    local script_name="keenetic_zapret2_manager.sh"
    DL_URL="https://github.com/${repo}/releases/latest/download/${script_name}"
    TMP_FILE="/tmp/keenetic_zapret_manager_update.$$"
    LOCAL_VER="$(kzm2_get_installed_script_version)"
    [ -z "$LOCAL_VER" ] && LOCAL_VER="$SCRIPT_VERSION"
    BACKUP_FILE="${TARGET_SCRIPT}.bak_${LOCAL_VER#v}_$(date +%Y%m%d_%H%M%S 2>/dev/null).sh"
    # GitHub API'den SHA256 digest al (tek istek)
    local api_raw expected_sha256
    api_raw="$(curl -fsS "$api" 2>/dev/null)"
    expected_sha256="$(printf '%s\n' "$api_raw" | grep -A30 "\"${script_name}\"" | \
        sed -n 's/.*"digest"[[:space:]]*:[[:space:]]*"sha256:\([^"]*\)".*/\1/p' | head -n1)"
    echo "$(T mgr_update_start 'Betik indiriliyor (GitHub)...' 'Downloading script (GitHub)...')"
    if ! download_file "$DL_URL" "$TMP_FILE"; then
        echo "$(T mgr_update_dl_fail 'Indirme basarisiz (curl/wget/SSL kontrol edin).' 'Download failed (check curl/wget/SSL).')"
        rm -f "$TMP_FILE" 2>/dev/null
        return 1
    fi
    # SHA256 dogrulamasi
    if [ -n "$expected_sha256" ]; then
        local actual_sha256
        actual_sha256="$(sha256sum "$TMP_FILE" 2>/dev/null | cut -d' ' -f1)"
        if [ "$actual_sha256" = "$expected_sha256" ]; then
            print_status PASS "$(T TXT_ZAP_UPDATE_SHA256_OK)"
            printf 'ok' > /opt/etc/kzm2_sha256_zapret.state
        else
            rm -f "$TMP_FILE" 2>/dev/null
            print_status FAIL "$(T TXT_ZAP_UPDATE_SHA256_FAIL)"
            printf 'fail' > /opt/etc/kzm2_sha256_zapret.state
            return 1
        fi
    else
        print_status WARN "$(T TXT_ZAP_UPDATE_SHA256_SKIP)"
    fi
    # Basic sanity: should look like a shell script and include expected markers
    if ! grep -q "SCRIPT_VERSION" "$TMP_FILE" 2>/dev/null; then
        echo "$(T mgr_update_bad 'Indirilen dosya beklenen formatta degil, iptal edildi.' 'Downloaded file is not in expected format, aborting.')"
        rm -f "$TMP_FILE" 2>/dev/null
        return 1
    fi
    # Syntax check (best-effort)
    if sh -n "$TMP_FILE" >/dev/null 2>&1; then
        :
    else
        echo "$(T mgr_update_syntax 'Indirilen dosyada syntax hatasi var, iptal edildi.' 'Downloaded file has syntax errors, aborting.')"
        rm -f "$TMP_FILE" 2>/dev/null
        return 1
    fi
# Version guard: never auto-downgrade.
REMOTE_FILE_VER="$(grep -m1 '^SCRIPT_VERSION=' "$TMP_FILE" 2>/dev/null | cut -d'"' -f2)"
if [ -z "$REMOTE_FILE_VER" ]; then
    echo "$(T mgr_update_bad 'Indirilen dosyada surum bilgisi okunamadi, iptal edildi.' 'Unable to read version from downloaded file, aborting.')"
    rm -f "$TMP_FILE" 2>/dev/null
    return 1
fi
# Allow only if remote is newer than local — force modunda SHA uyusmazligi icin atla.
if [ "$_force" != "1" ] && ! ver_is_newer "$REMOTE_FILE_VER" "$LOCAL_VER"; then
    echo "$(T mgr_update_skip 'Guncelleme atlandi (downgrade engellendi).' 'Update skipped (downgrade blocked).') $(T _ 'Kurulu:' 'Local:') $LOCAL_VER, $(T _ 'GitHub:' 'Remote:') $REMOTE_FILE_VER"
    rm -f "$TMP_FILE" 2>/dev/null
    return 2
fi
    # Backup current script if present
    if [ -f "$TARGET_SCRIPT" ]; then
        # Backup limit: keep max 3, remove oldest if exceeded
        _bak_dir="$(dirname "$TARGET_SCRIPT")"
        _bak_pattern="keenetic_zapret2_manager.sh.bak_*"
        _bak_count=$(find "$_bak_dir" -maxdepth 1 -type f -name "$_bak_pattern" 2>/dev/null | wc -l | tr -d ' ')
        if [ "${_bak_count:-0}" -ge 3 ] 2>/dev/null; then
            find "$_bak_dir" -maxdepth 1 -type f -name "$_bak_pattern" 2>/dev/null | \
                sort | head -n $((_bak_count - 2)) | while IFS= read -r _f; do
                    rm -f "$_f" 2>/dev/null
                done
        fi
        cp -f "$TARGET_SCRIPT" "$BACKUP_FILE" 2>/dev/null
        echo "$(T mgr_update_backup 'Yedek alindi:' 'Backup created:') $BACKUP_FILE"
    fi
    # Replace
    cp -f "$TMP_FILE" "$TARGET_SCRIPT" 2>/dev/null && chmod +x "$TARGET_SCRIPT" 2>/dev/null
    rm -f "$TMP_FILE" 2>/dev/null
    printf 'ok' > /opt/etc/kzm2_sha256_kzm.state 2>/dev/null
    echo ""
    print_line "="
    printf '%b%s%b\n' "${CLR_ORANGE}${CLR_BOLD}" "$(T _ '  GUNCELLEME TAMAMLANDI' '  UPDATE COMPLETED')" "${CLR_RESET}"
    printf '%b%s%b\n' "${CLR_GREEN}${CLR_BOLD}" "$(T _ '  Cikis yapip KZM2 yi yeniden calistirin.' '  Please exit and re-run KZM2.')" "${CLR_RESET}"
    print_line "="
    echo ""
    return 0
}
check_manager_update() {
    print_status INFO "$(T TXT_CHECKING_GITHUB)"
    local repo="RevolutionTR/keenetic-zapret2-manager"
    local script_name="keenetic_zapret2_manager.sh"
    local api="https://api.github.com/repos/${repo}/releases/latest"
    local REMOTE_VER LOCAL_VER api_raw CLR_REMOTE CLR_LOCAL sha256sums_url expected_sha256 actual_sha256
    api_raw="$(curl -sS "$api" 2>/dev/null)"
    REMOTE_VER="$(printf '%s\n' "$api_raw" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    if [ -z "$REMOTE_VER" ]; then
        print_status FAIL "$(T TXT_GITHUB_FAIL)"
        press_enter_to_continue
        return 1
    fi
    LOCAL_VER="$(kzm2_get_installed_script_version)"
    [ -z "$LOCAL_VER" ] && LOCAL_VER="$SCRIPT_VERSION"
    # Renkleri duruma gore ata
    if ver_is_newer "$REMOTE_VER" "$LOCAL_VER"; then
        CLR_REMOTE="${CLR_BOLD}${CLR_GREEN}"; CLR_LOCAL="${CLR_BOLD}${CLR_YELLOW}"
    elif ver_is_newer "$LOCAL_VER" "$REMOTE_VER"; then
        CLR_REMOTE="${CLR_BOLD}${CLR_YELLOW}"; CLR_LOCAL="${CLR_BOLD}${CLR_GREEN}"
    else
        CLR_REMOTE="${CLR_BOLD}${CLR_GREEN}"; CLR_LOCAL="${CLR_BOLD}${CLR_GREEN}"
    fi
    # SHA256SUMS dosyasini GitHub release'ten indir ve karsilastir
    sha256sums_url="https://github.com/${repo}/releases/download/${REMOTE_VER}/SHA256SUMS"
    expected_sha256="$(curl -fsSL "$sha256sums_url" 2>/dev/null | grep "${script_name}" | cut -d' ' -f1)"
    actual_sha256="$(sha256sum "$KZM2_SCRIPT_PATH" 2>/dev/null | cut -d' ' -f1)"
    print_line "-"
    printf " %-10s: %b%s%b\n" "$(T TXT_GITHUB_LATEST)" "$CLR_REMOTE" "$REMOTE_VER" "${CLR_RESET}"
    printf " %-10s: %b%s%b\n" "$(T TXT_DEVICE_VERSION)" "$CLR_LOCAL" "$LOCAL_VER" "${CLR_RESET}"
    if [ -n "$expected_sha256" ] && [ -n "$actual_sha256" ]; then
        if [ "$actual_sha256" = "$expected_sha256" ]; then
            printf " %-10s: %b%s%b\n" "PASS" "${CLR_GREEN}${CLR_BOLD}" "$(T TXT_ZAP_UPDATE_SHA256_OK)" "${CLR_RESET}"
            printf 'ok' > /opt/etc/kzm2_sha256_kzm.state
        else
            printf " %-10s: %b%s%b\n" "WARN" "${CLR_ORANGE}${CLR_BOLD}" "$(T TXT_ZAP_UPDATE_SHA256_FAIL)" "${CLR_RESET}"
            printf 'fail' > /opt/etc/kzm2_sha256_kzm.state
            printf " %-10s: %s\n" "GitHub" "$expected_sha256"
            printf " %-10s: %s\n" "Kurulu" "$actual_sha256"
        fi
    elif [ -n "$actual_sha256" ]; then
        printf " %-10s: %s\n" "INFO" "$actual_sha256"
    fi
    print_line "-"
    if [ "$REMOTE_VER" = "$LOCAL_VER" ]; then
        # SHA farkliysa yeniden indirme teklif et
        if [ -n "$expected_sha256" ] && [ -n "$actual_sha256" ] && [ "$expected_sha256" != "$actual_sha256" ]; then
            print_status WARN "$(T _ 'Surum ayni ancak dosya degismis (SHA uyusmazligi).' 'Version matches but file has changed (SHA mismatch).')"
            printf "%s" "$(T _ 'Yeniden indirmek ister misiniz? (e/h): ' 'Re-download? (y/n): ')"
            read -r _sha_ans
            case "$_sha_ans" in
                e|E|y|Y)
                    echo ""
                    update_manager_script "1" && _kzm2_restart_services_after_update
                    ;;
                *)
                    print_status INFO "$(T TXT_ZAP_UPDATE_CANCELLED)"
                    ;;
            esac
        else
            print_status PASS "$(T TXT_UPTODATE)"
        fi
        press_enter_to_continue
        return 0
    fi
    if ver_is_newer "$LOCAL_VER" "$REMOTE_VER"; then
        # Kurulu surum GitHub'dan daha yeni (gelistirici build)
        print_status INFO "$(T _ 'Kurulu surum GitHub surununden daha yeni (gelistirici build).' 'Installed version is newer than GitHub release (developer build).')"
        press_enter_to_continue
        return 0
    fi
    # Remote > Local: guncelleme mevcut
    print_status WARN "$(T _ 'Yeni surum mevcut!' 'New version available!')"
    echo ""
    printf "%s" "$(T _ 'Guncellemek ister misiniz? (e/h): ' 'Update now? (y/n): ')"
    read -r _ans
    case "$_ans" in
        e|E|y|Y)
            echo ""
            update_manager_script && _kzm2_restart_services_after_update
            ;;
        *)
            print_status INFO "$(T TXT_ZAP_UPDATE_CANCELLED)"
            ;;
    esac
    press_enter_to_continue
}
# --- Ana Menu Fonksiyonu ---
# -------------------------------------------------------------------
# Hostlist / Autohostlist (MODE_FILTER) Yonetimi
# -------------------------------------------------------------------
HOSTLIST_DIR="/opt/zapret2/ipset"
HOSTLIST_USER="${HOSTLIST_DIR}/zapret-hosts-user.txt"
HOSTLIST_EXCLUDE_DOM="${HOSTLIST_DIR}/zapret-hosts-user-exclude.txt"
# Zapret2 ayrimi:
# - localnets: sistem koruma subnetleri (dokunulmaz)
# - ip-exclude: kullanicinin ekledigi dis IP/CIDR muafiyetleri
HOSTLIST_LOCALNETS="${HOSTLIST_DIR}/zapret-hosts-localnets.txt"
HOSTLIST_EXCLUDE_IP="${HOSTLIST_DIR}/zapret-ip-exclude.txt"
HOSTLIST_AUTO="${HOSTLIST_DIR}/zapret-hosts-auto.txt"
HOSTLIST_MODE_FILE="/opt/zapret2/hostlist_mode"
HOSTLIST_AUTO_DEBUG="/opt/zapret2/nfqws_autohostlist.log"
SCOPE_MODE_FILE="/opt/zapret2/scope_mode"
_kzm2_default_localnets() {
    cat <<'EOF'
127.0.0.0/8
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
169.254.0.0/16
100.64.0.0/10
::1
fc00::/7
fe80::/10
EOF
}
_kzm2_prune_localnets_from_user_lists() {
    # $@: files. Exact-match delete only for default local/private subnet entries.
    local _f _tmp _defs
    _defs="/tmp/kzm2_localnets.$$"
    _kzm2_default_localnets > "$_defs" 2>/dev/null
    for _f in "$@"; do
        [ -f "$_f" ] || continue
        _tmp="/tmp/kzm2_prune.$$"
        awk 'NR==FNR{a[$0]=1;next} !($0 in a)' "$_defs" "$_f" > "$_tmp" 2>/dev/null && mv "$_tmp" "$_f"
        rm -f "$_tmp" 2>/dev/null
    done
    rm -f "$_defs" 2>/dev/null
}
ensure_hostlist_files() {
    [ -d "$HOSTLIST_DIR" ] || mkdir -p "$HOSTLIST_DIR" >/dev/null 2>&1
    [ -f "$HOSTLIST_USER" ] || : > "$HOSTLIST_USER"
    # Sistem local/private subnet korumalari: kullanici listesi degil, ayri dosyada tutulur.
    if [ ! -f "$HOSTLIST_LOCALNETS" ]; then
        cat > "$HOSTLIST_LOCALNETS" <<'EOF'
127.0.0.0/8
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
169.254.0.0/16
100.64.0.0/10
::1
fc00::/7
fe80::/10
EOF
    fi
    # Kullanici dis IP/CIDR exclude listesi. Localnet satirlari burada tutulmaz.
    [ -f "$HOSTLIST_EXCLUDE_IP" ] || : > "$HOSTLIST_EXCLUDE_IP"
    # Domain exclude (our menu manages this)
    [ -f "$HOSTLIST_EXCLUDE_DOM" ] || : > "$HOSTLIST_EXCLUDE_DOM"
    # Eski/yanlis buildlerden kalan localnet satirlarini user listelerinden temizle.
    _kzm2_prune_localnets_from_user_lists "$HOSTLIST_EXCLUDE_DOM" "$HOSTLIST_EXCLUDE_IP"
    # AUTO dosyasi zapret tarafindan doldurulur; yoksa gosterebilmek icin olusturuyoruz
    [ -f "$HOSTLIST_AUTO" ] || : > "$HOSTLIST_AUTO"
}
ensure_zapret_config() {
    # zapret upstream expects /opt/zapret2/config (optional). If missing, try to create it.
    if [ -f /opt/zapret2/config ]; then
        return 0
    fi
    if [ -f /opt/zapret2/config.default ]; then
        cp -f /opt/zapret2/config.default /opt/zapret2/config >/dev/null 2>&1 && return 0
    fi
    # minimal safe config (only what we touch)
    cat > /opt/zapret2/config <<'EOF'
# this file is included from init scripts
# change values here
# filtering mode : none|ipset|hostlist|autohostlist
MODE_FILTER=none
# use <HOSTLIST> and <HOSTLIST_NOAUTO> placeholders to engage standard hostlists and autohostlist in ipset dir
# hostlist markers are replaced to empty string if MODE_FILTER does not satisfy
# <HOSTLIST_NOAUTO> appends ipset/zapret-hosts-auto.txt as normal list
# nfqws options (filled/updated by management script)
NFQWS2_PORTS_TCP=80,443
NFQWS2_PORTS_UDP=443
NFQWS2_TCP_PKT_OUT=6
NFQWS2_TCP_PKT_IN=4
NFQWS2_UDP_PKT_OUT=3
NFQWS2_UDP_PKT_IN=3
NFQWS2_OPT=""
EOF
    [ -f /opt/zapret2/config ]
}
get_scope_mode() {
    # global|smart (default: global)
    if [ -f "$SCOPE_MODE_FILE" ]; then
        sm="$(head -n1 "$SCOPE_MODE_FILE" 2>/dev/null | tr -d '\r\n' | tr 'A-Z' 'a-z')"
        case "$sm" in
            global|smart) echo "$sm"; return 0 ;;
        esac
    fi
    echo "global"
}
pretty_scope_mode() {
    # UI helper: keep stored values (global/smart) but show localized label
    case "$(get_scope_mode)" in
        global) printf '%b' "${CLR_CYAN}$(T TXT_SCOPE_GLOBAL)${CLR_RESET}" ;;
        smart)  printf '%b' "${CLR_GREEN}$(T TXT_SCOPE_SMART)${CLR_RESET}" ;;
        *)      echo "$(get_scope_mode)" ;;
    esac
}
set_scope_mode() {
    # $1: global|smart
    [ -z "$1" ] && return 1
    case "$1" in
        global|smart) ;;
        *) return 1 ;;
    esac
    echo "$1" > "$SCOPE_MODE_FILE" 2>/dev/null || return 1
    return 0
}
get_mode_filter() {
    # priority: state file -> zapret config -> default none
    if [ -f "$HOSTLIST_MODE_FILE" ]; then
        mf="$(head -n1 "$HOSTLIST_MODE_FILE" 2>/dev/null | tr -d '\r\n' | tr 'A-Z' 'a-z')"
        case "$mf" in
            none|hostlist|autohostlist|ipset) echo "$mf"; return 0 ;;
        esac
    fi
    if [ -f /opt/zapret2/config ]; then
        mf="$(sed -n 's/^MODE_FILTER=\(.*\)$/\1/p' /opt/zapret2/config 2>/dev/null | head -n1)"
        [ -n "$mf" ] && { echo "$mf"; return 0; }
    fi
    echo "none"
}
set_mode_filter() {
    # $1: none|hostlist|autohostlist|ipset
    [ -z "$1" ] && return 1
    ensure_hostlist_files
    # persist for this script (works even if /opt/zapret2/config is absent)
    echo "$1" > "$HOSTLIST_MODE_FILE" 2>/dev/null || return 1
    # best-effort: also write to zapret config if present/creatable (for compatibility)
    ensure_zapret_config >/dev/null 2>&1
    if [ -f /opt/zapret2/config ]; then
        if grep -q '^MODE_FILTER=' /opt/zapret2/config 2>/dev/null; then
            sed -i "s/^MODE_FILTER=.*/MODE_FILTER=$1/" /opt/zapret2/config 2>/dev/null
        else
            echo "MODE_FILTER=$1" >> /opt/zapret2/config
        fi
    fi
    return 0
}
normalize_domain() {
    # stdin or $1; output normalized domain or empty
    d="$1"
    [ -z "$d" ] && read -r d
    d="$(echo "$d" | tr -d '\r' | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    d="$(echo "$d" | sed 's#^[a-z]\+://##')"
    d="$(echo "$d" | sed 's#/.*$##')"
    d="$(echo "$d" | sed 's/^\.*//')"
    # basic allow: letters digits dot hyphen, must contain a dot or be wildcard like *.domain.tld (we store without *)
    d="$(echo "$d" | sed 's/^\*\.\(.*\)$/\1/')"
    echo "$d" | grep -Eq '^[a-z0-9][a-z0-9.-]*[a-z0-9]$' || { echo ""; return 1; }
    echo "$d"
}
file_has_line() {
    # $1 file $2 line exact
    [ -f "$1" ] || return 1
    grep -Fxq -- "$2" "$1" 2>/dev/null
}
add_line_unique() {
    # $1 file $2 line
    [ -f "$1" ] || : > "$1"
    if ! file_has_line "$1" "$2"; then
        printf "%s\n" "$2" >> "$1"
    fi
}
remove_line_exact() {
    # $1 file $2 line
    [ -f "$1" ] || return 0
    tmp="/tmp/hostlist.$$"
    grep -Fvx -- "$2" "$1" 2>/dev/null > "$tmp" && mv "$tmp" "$1"
}
hostlist_stats() {
    # $1 file
    [ -f "$1" ] || { echo "0"; return; }
    awk 'NF && $0 !~ /^[[:space:]]*#/' "$1" 2>/dev/null | wc -l | tr -d ' '
}
hostlist_stats_filtered() {
    # $1 file, $2 all|domain|ip
    [ -f "$1" ] || { echo "0"; return; }
    awk -v mode="${2:-all}" '
    function isip(s) { return (s ~ /:/ || s ~ /\// || s ~ /^[0-9]+(\.[0-9]+){3}$/) }
    NF && $0 !~ /^[[:space:]]*#/ {
        if (mode=="domain" && isip($0)) next
        if (mode=="ip" && !isip($0)) next
        n++
    }
    END { print n+0 }' "$1" 2>/dev/null
}
show_hostlist_tail() {
    # $1=file $2=title_key (TXT_HL_LIST_*) $3=all|domain|ip
    [ "$KZM2_PAGE_ABORT" = "1" ] && return
    local f="$1" tk="$2" filter="${3:-all}"
    local c unit
    c="$(hostlist_stats_filtered "$f" "$filter")"
    [ "$filter" = "ip" ] && unit="$(T _ 'kayit' 'entries')" || unit="$(T _ 'domain' 'domains')"
    print_line "-"; kzm2_page_line
    printf '%b%-25s:%b ' "${CLR_ORANGE}${CLR_BOLD}" "$(T "$tk")" "${CLR_RESET}"
    if [ "$c" -eq 0 ]; then
        printf '%b%s%b\n' "${CLR_RED}" "$(T TXT_EMPTY)" "${CLR_RESET}"
        kzm2_page_line
    else
        printf '%b%d %s%b\n' "${CLR_GREEN}" "$c" "$unit" "${CLR_RESET}"
        kzm2_page_line
        [ "$KZM2_PAGE_ABORT" = "1" ] && return
        echo ""; kzm2_page_line
        while IFS= read -r _hl_line; do
            [ "$KZM2_PAGE_ABORT" = "1" ] && return
            printf '%s\n' "$_hl_line"
            kzm2_page_line
        done << HLEOF
$(awk -v cyan="${CLR_CYAN}" -v reset="${CLR_RESET}" -v mode="$filter" '
    function isip(s) { return (s ~ /:/ || s ~ /\// || s ~ /^[0-9]+(\.[0-9]+){3}$/) }
    NF && $0 !~ /^[[:space:]]*#/ {
        if (mode=="domain" && isip($0)) next
        if (mode=="ip" && !isip($0)) next
        n++
        printf "  %s%2d.%s %s\n", cyan, n, reset, $0
    }' "$f" 2>/dev/null)
HLEOF
    fi
}
# KZM2_PAGE_LINES: show_hostlist_tail tarafindan kullanilan global sayac
# kzm2_page_check: her satir basilinca cagrilir, sayfa dolunca duraklar
KZM2_PAGE_LINES=0
KZM2_PAGE_ROWS=0
KZM2_PAGE_ABORT=0
kzm2_page_init() {
    KZM2_PAGE_ABORT=0
    KZM2_PAGE_LINES=0
    KZM2_PAGE_ROWS="$(stty size 2>/dev/null | awk '{print $1}')"
    { [ -z "$KZM2_PAGE_ROWS" ] || [ "$KZM2_PAGE_ROWS" -lt 5 ]; } && KZM2_PAGE_ROWS=24
    KZM2_PAGE_ROWS=$(( KZM2_PAGE_ROWS - 3 ))
}
kzm2_page_line() {
    [ "$KZM2_PAGE_ABORT" = "1" ] && return
    KZM2_PAGE_LINES=$(( KZM2_PAGE_LINES + 1 ))
    if [ "$KZM2_PAGE_LINES" -ge "$KZM2_PAGE_ROWS" ]; then
        printf '\033[7m-- Devam: ENTER | Cik: q --\033[0m '
        read -r _pans </dev/tty
        case "$_pans" in q|Q) KZM2_PAGE_ABORT=1; printf '\n'; return ;; esac
        KZM2_PAGE_LINES=0
    fi
}
choose_mode_filter_interactive() {
    cur="$(get_mode_filter)"
    # NOTE:
    # This function is used inside command substitution:
    #   mode="$(choose_mode_filter_interactive)"
    # If we print the menu to STDOUT, the caller will capture it and the UI will look "frozen".
    # Therefore, ALL menu/UI output goes to STDERR. Only the final selected mode is echoed to STDOUT.
    {
        print_line "-"
        echo "$(T TXT_HL_MODE_TITLE)"
        print_line "-"
        printf '%b\n' "$(T TXT_HL_CURRENT_MODE)$(color_mode_name "$cur")"
        echo ""
        _a1=""; _a2=""; _a3=""
[ "$cur" = "none" ] && _a1="$(T TXT_HL_ACTIVE_MARK)"
[ "$cur" = "hostlist" ] && _a2="$(T TXT_HL_ACTIVE_MARK)"
[ "$cur" = "autohostlist" ] && _a3="$(T TXT_HL_ACTIVE_MARK)"
echo " 1. none     ($(T TXT_HL_MODE_NONE_DESC))${_a1}"
echo " 2. hostlist ($(T TXT_HL_MODE_HOSTLIST_DESC))${_a2}"
echo " 3. autohostlist ($(T TXT_HL_MODE_AUTO_DESC))${_a3}"
echo " 0. $(T TXT_SCOPE_BACK)"
        echo ""
        printf "%s" "$(T TXT_HL_PICK)"
    } >&2
    # Prefer reading from TTY (works reliably even in $(...)). Fallback to normal stdin.
    if [ -r /dev/tty ]; then
        read -r msel </dev/tty || msel=""
    else
        read -r msel || msel=""
    fi
    case "$msel" in
        1) echo "none" ;;
        2) echo "hostlist" ;;
        3) echo "autohostlist" ;;
        0) echo "" ;;
        *) echo "__invalid__" ;;
    esac
}
apply_mode_filter() {
    # $1 mode
    mode="$1"
    [ -z "$mode" ] && return 0
    ensure_hostlist_files
    # hostlist/autohostlist modunda, listeler BOS ise zapret "include yok" gibi davranabilir (exclude haric herseyi isler).
    # Bu sebeple kullaniciyi uyar.
    if [ "$mode" = "hostlist" ] || [ "$mode" = "autohostlist" ]; then
        ucnt="$(hostlist_stats "$HOSTLIST_USER")"
        if [ "$ucnt" -eq 0 ]; then
            echo "$(T TXT_HL_WARN_EMPTY_STRICT)"
            press_enter_to_continue
        fi
    fi
    if set_mode_filter "$mode"; then
        echo "$(T TXT_HL_SET_OK) $mode"
        # Rebuild NFQWS2_OPT so <HOSTLIST> placeholders are added/removed immediately.
        update_nfqws_parameters >/dev/null 2>&1
        restart_zapret2 >/dev/null 2>&1
        echo "$(T TXT_HL_RESTART)"
    else
        echo "$(T TXT_HL_SET_FAIL)"
    fi
}
apply_scope_mode() {
    # $1 scope: global|smart
    scope="$1"
    [ -z "$scope" ] && return 0
    ensure_hostlist_files
    if ! set_scope_mode "$scope"; then
        echo "$(T TXT_HL_SET_FAIL)"
        return 1
    fi
    case "$scope" in
        global)
            # Global mod: her seye uygula (mevcut davranis). MODE_FILTER anlamsiz kalmasin diye none yap.
            set_mode_filter none >/dev/null 2>&1
            ;;
        smart)
            # Smart modun amaci: sadece gerekli hostlarda calis (otomatik ogrenme icin autohostlist)
            set_mode_filter autohostlist >/dev/null 2>&1
            ;;
    esac
    # NFQWS2_OPT satirlarini kapsam moduna gore yeniden yaz
    update_nfqws_parameters >/dev/null 2>&1
    restart_zapret2 >/dev/null 2>&1
    echo "$(T TXT_HL_RESTART)"
    return 0
}
manage_hostlist_menu() {
    if ! is_zapret2_installed; then
        echo "$(T TXT_HL_ERR_NOT_INSTALLED)"
        press_enter_to_continue
        clear
        return 1
    fi
    ensure_hostlist_files
    while true; do
        clear
        cur="$(get_mode_filter)"
        ucnt="$(hostlist_stats "$HOSTLIST_USER")"
        ecnt="$(hostlist_stats_filtered "$HOSTLIST_EXCLUDE_DOM" domain)"
        acnt="$(hostlist_stats "$HOSTLIST_AUTO")"
        print_line "=" 
        echo "$(T TXT_HL_TITLE)"
        print_line "=" 
        printf '%b\n' "$(T TXT_HL_CURRENT_MODE)$(color_mode_name "$cur")"
        printf '%b\n' "$(T TXT_HL_SCOPE_MODE)$(pretty_scope_mode)"
        echo "$(T TXT_HL_COUNTS)${ucnt}/${ecnt}/${acnt}"
        print_line "-"
        echo " 1. $(T TXT_HL_OPT_6)"
        echo " 2. $(T TXT_HL_OPT_1)"
        echo " 3. $(T TXT_HL_OPT_2)"
        echo " 4. $(T TXT_HL_OPT_3)"
        echo " 5. $(T TXT_HL_OPT_4)"
        echo " 6. $(T TXT_HL_OPT_5)"
        echo " 7. $(T TXT_HL_OPT_7)"
        echo " 8. $(T TXT_HL_OPT_8)"
        echo " 0. $(T TXT_HL_OPT_0)"
        print_line "-"
        printf "%s" "$(T TXT_HL_PICK)"
        read -r sel || return 0
        case "$sel" in
            1)
                kzm2_page_init
                show_hostlist_tail "$HOSTLIST_USER"         TXT_HL_LIST_USER all
                # Zapret2 may store local IP/CIDR protection entries in the same exclude file.
                # Keep the CLI view separated so domain excludes do not show system IP/subnet entries.
                show_hostlist_tail "$HOSTLIST_EXCLUDE_DOM"   TXT_HL_LIST_EXCLUDE_DOM domain
                show_hostlist_tail "$HOSTLIST_LOCALNETS"     TXT_HL_LIST_LOCALNETS ip
                show_hostlist_tail "$HOSTLIST_EXCLUDE_IP"    TXT_HL_LIST_EXCLUDE_IP ip
                show_hostlist_tail "$HOSTLIST_AUTO"         TXT_HL_LIST_AUTO all
                [ "$KZM2_PAGE_ABORT" != "1" ] && { print_line "-"; press_enter_to_continue; }
                clear
                ;;
            2)
                mode="$(choose_mode_filter_interactive)"
                [ "$mode" = "__invalid__" ] && { echo "$(T invalid_main 'Gecersiz secim!' 'Invalid choice!')"; continue; }
                [ -n "$mode" ] && apply_mode_filter "$mode"
                if type press_enter_to_continue >/dev/null 2>&1; then
                    press_enter_to_continue
                else
                    press_enter_to_continue
                fi
                clear
                ;;
            3)
echo "$(T TXT_HL_BULK_HINT)"
printf "%b%s%b\n" "${CLR_ORANGE}" "$(T TXT_HL_BULK_HINT2)" "${CLR_RESET}"
added=0
already=0
invalid=0
cancelled=0
# Prompt only once so multi-line paste doesn't spam the screen.
# Read until an empty line. "0" cancels.
echo ""
printf "%s" "$(T TXT_HL_PROMPT_ADD)"
while :; do
    IFS= read -r d || break
    # Normalize input (CRLF terminals + trim)
    d="$(printf '%s' "$d" | tr -d '
' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    # Cancel (0 / 00 / 000 ...) and return to menu immediately
    if [ -n "$d" ]; then
        case "$d" in
            *[!0]*) : ;;   # not all zeros
            *)
                cancelled=1
                echo "$(T TXT_HL_CANCELLED)"
                break
                ;;
        esac
    fi
    [ -z "$d" ] && break
    # Split current line by comma/semicolon/whitespace
    for one in $(echo "$d" | tr ',;	' '   '); do
        nd="$(normalize_domain "$one")"
        # Reject entries without a dot (prevents accidentally adding "0", "00", etc.)
        case "$nd" in
            *.*) : ;;
            *) nd="";;
        esac
        if [ -z "$nd" ]; then
            invalid=$((invalid+1))
            continue
        fi
        [ -f "$HOSTLIST_USER" ] || : > "$HOSTLIST_USER"
        if grep -Fqx "$nd" "$HOSTLIST_USER" 2>/dev/null; then
            already=$((already+1))
            continue
        fi
        echo "$nd" >> "$HOSTLIST_USER"
        echo "$(T TXT_HL_MSG_ADDED)$nd"
        added=$((added+1))
    done
done
if [ "$cancelled" -eq 1 ]; then
    # Cancel should return to menu immediately (no extra prompt)
    sleep 1
    clear
    continue
fi
echo "$(T X 'Ozet:' 'Summary:') $(T X 'Eklendi' 'Added')=$added, $(T X 'Zaten vardi' 'Already existed')=$already, $(T X 'Gecersiz' 'Invalid')=$invalid"
[ "$added" -gt 0 ] && { update_nfqws_parameters >/dev/null 2>&1; restart_zapret2 >/dev/null 2>&1; }
if type press_enter_to_continue >/dev/null 2>&1; then
    press_enter_to_continue
else
    press_enter_to_continue
fi
clear
    ;;
            4)
                printf '%s' "$(T TXT_HL_PROMPT_DEL)"; read -r d
                [ "$d" = "0" ] && continue
                nd="$(normalize_domain "$d")"
                [ -z "$nd" ] && { echo "$(T TXT_HL_INVALID_DOMAIN)"; continue; }
                remove_line_exact "$HOSTLIST_USER" "$nd"
                echo "$(T TXT_HL_MSG_REMOVED)$nd"
                update_nfqws_parameters >/dev/null 2>&1
                restart_zapret2 >/dev/null 2>&1
                ;;
            5)
echo "$(T TXT_HL_BULK_HINT)"
printf "%b%s%b\n" "${CLR_ORANGE}" "$(T TXT_HL_BULK_HINT2)" "${CLR_RESET}"
added=0
already=0
invalid=0
cancelled=0
# Prompt only once so multi-line paste doesn't spam the screen.
# Read until an empty line. "0" cancels.
echo ""
printf "%s" "$(T TXT_HL_PROMPT_ADD)"
while :; do
    IFS= read -r d || break
    # Normalize input (CRLF terminals + trim)
    d="$(printf '%s' "$d" | tr -d '
' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    # Cancel (0 / 00 / 000 ...) and return to menu immediately
    if [ -n "$d" ]; then
        case "$d" in
            *[!0]*) : ;;   # not all zeros
            *)
                cancelled=1
                echo "$(T TXT_HL_CANCELLED)"
                break
                ;;
        esac
    fi
    [ -z "$d" ] && break
    # Split current line by comma/semicolon/whitespace
    for one in $(echo "$d" | tr ',;	' '   '); do
        nd="$(normalize_domain "$one")"
        # Reject entries without a dot (prevents accidentally adding "0", "00", etc.)
        case "$nd" in
            *.*) : ;;
            *) nd="";;
        esac
        if [ -z "$nd" ]; then
            invalid=$((invalid+1))
            continue
        fi
        [ -f "$HOSTLIST_EXCLUDE_DOM" ] || : > "$HOSTLIST_EXCLUDE_DOM"
        if grep -Fqx "$nd" "$HOSTLIST_EXCLUDE_DOM" 2>/dev/null; then
            already=$((already+1))
            continue
        fi
        echo "$nd" >> "$HOSTLIST_EXCLUDE_DOM"
        echo "$(T TXT_HL_MSG_ADDED)$nd"
        added=$((added+1))
    done
done
if [ "$cancelled" -eq 1 ]; then
    # Cancel should return to menu immediately (no extra prompt)
    sleep 1
    clear
    continue
fi
echo "$(T X 'Ozet:' 'Summary:') $(T X 'Eklendi' 'Added')=$added, $(T X 'Zaten vardi' 'Already existed')=$already, $(T X 'Gecersiz' 'Invalid')=$invalid"
[ "$added" -gt 0 ] && { update_nfqws_parameters >/dev/null 2>&1; restart_zapret2 >/dev/null 2>&1; }
if type press_enter_to_continue >/dev/null 2>&1; then
    press_enter_to_continue
else
    press_enter_to_continue
fi
clear
    ;;
            6)
                printf '%s' "$(T TXT_HL_PROMPT_DEL)"; read -r d
                [ "$d" = "0" ] && continue
                nd="$(normalize_domain "$d")"
                [ -z "$nd" ] && { echo "$(T TXT_HL_INVALID_DOMAIN)"; continue; }
                remove_line_exact "$HOSTLIST_EXCLUDE_DOM" "$nd"
                echo "$(T TXT_HL_MSG_REMOVED)$nd"
                update_nfqws_parameters >/dev/null 2>&1
                restart_zapret2 >/dev/null 2>&1
                ;;
            7)
                print_line "-"
                printf '%b
' "${CLR_BOLD}${CLR_RED}$(T TXT_HL_WARN_AUTOCLEAR_1)${CLR_RESET}"
                printf '%b
' "${CLR_BOLD}${CLR_RED}$(T TXT_HL_WARN_AUTOCLEAR_2)${CLR_RESET}"
                # Autohostlist modunda ek uyari
                _cur_hmode="$(cat /opt/zapret2/hostlist_mode 2>/dev/null | tr -d '[:space:]')"
                if [ "$_cur_hmode" = "autohostlist" ]; then
                    print_status WARN "$(T _ 'Mod: autohostlist — liste temizlenince Zapret2 yeniden baslatilana kadar trafik filtrelenmez.' 'Mode: autohostlist — after clearing, traffic will not be filtered until list refills.')"
                fi
                print_line "-"
                printf "%s" "$(T confirm_autolist_q 'Onayliyor musunuz? (e=Evet, h=Hayir, 0=Geri): ' 'Confirm? (y=Yes, n=No, 0=Back): ')"
                read -r ans
                case "$ans" in
                    0) ;;
                    e|E|y|Y)
                        : > "$HOSTLIST_AUTO"
                        echo "$(T TXT_HL_CLEARED)"
                        update_nfqws_parameters >/dev/null 2>&1
                        restart_zapret2
                        ;;
                    *)
                        echo "$(T cancelled 'Islem iptal edildi.' 'Cancelled.')"
                        ;;
                esac
                if type press_enter_to_continue >/dev/null 2>&1; then
                    press_enter_to_continue
                else
                    press_enter_to_continue
                fi
                clear
                ;;
            8)
                print_line "-"
                printf '%b
' "${CLR_BOLD}${CLR_CYAN}$(T TXT_SCOPE_MODE): $(pretty_scope_mode)${CLR_RESET}"
                print_line "-"
                echo ""
                gdesc="$(T TXT_SCOPE_GLOBAL_DESC)"
            sdesc="$(T TXT_SCOPE_SMART_DESC)"
echo " 1. $(T TXT_SCOPE_GLOBAL) (${gdesc})"
echo " 2. $(T TXT_SCOPE_SMART)  (${sdesc})"
                echo " 0. $(T TXT_SCOPE_BACK)"
                echo ""
                printf "%s" "$(T TXT_HL_PICK)"
                if [ -r /dev/tty ]; then
                    read -r ssel </dev/tty || ssel=""
                else
                    read -r ssel || ssel=""
                fi
case "$ssel" in
                    1) apply_scope_mode global ;;
                    2) apply_scope_mode smart ;;
                    0) : ;;
                    *) echo "$(T invalid_main 'Gecersiz secim!' 'Invalid choice!')" ;;
                esac
                if type press_enter_to_continue >/dev/null 2>&1; then
                    press_enter_to_continue
                else
                    press_enter_to_continue
                fi
                clear
                ;;
            0)
                clear
                return 0
                ;;
            *)
                echo "$(T invalid_main 'Gecersiz secim!' 'Invalid choice!')"
                ;;
        esac
        echo ""
    done
}
# --- Betik: Yedekten Geri Don (Rollback) ---
github_fetch_release_kv_last10() {
    # outputs lines: tag|url  (tag list; not release assets)
    local API
    API="https://api.github.com/repos/RevolutionTR/keenetic-zapret2-manager/tags?per_page=10"
    {
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL -H "User-Agent: keenetic-zapret2-manager" "$API"
        elif command -v wget >/dev/null 2>&1; then
            wget -qO- "$API"
        else
            return 1
        fi
    } | tr '\r\n' ' ' | sed 's/\"name\":/\n\"name\":/g' | awk -F'\"' '
        $0 ~ /"name":/ {
            tag=$4
            if (tag != "") {
                print tag "|" "https://raw.githubusercontent.com/RevolutionTR/keenetic-zapret2-manager/" tag "/keenetic_zapret2_manager.sh"
            }
        }
    '
}
github_fetch_release_url_by_tag() {
    # $1 = tag => prints raw url (may 404 if tag does not exist)
    local TAG
    TAG="$1"
    [ -n "$TAG" ] || return 1
    echo "https://raw.githubusercontent.com/RevolutionTR/keenetic-zapret2-manager/$TAG/keenetic_zapret2_manager.sh"
}
github_install_script_from_url() {
    # $1=tag (for backup name), $2=url
    local TAG URL TARGET TS BAK TMP
    TAG="$1"
    URL="$2"
    TARGET="/opt/lib/opkg/keenetic_zapret2_manager.sh"
    [ -f "$TARGET" ] || TARGET="$(readlink -f "$0" 2>/dev/null)"
    [ -n "$URL" ] || return 1
    TS="$(date +%Y%m%d_%H%M%S 2>/dev/null)"
    [ -z "$TS" ] && TS="$(date +%Y%m%d%H%M%S 2>/dev/null)"
    BAK="${TARGET}.bak_${TAG}_${TS}.sh"
    TMP="/tmp/keenetic_zapret_manager_dl.$$"
    echo "$(T TXT_ROLLBACK_GH_DOWNLOADING)"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$URL" -o "$TMP" || { rm -f "$TMP"; return 1; }
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$TMP" "$URL" || { rm -f "$TMP"; return 1; }
    else
        return 1
    fi
    head -n 1 "$TMP" 2>/dev/null | grep -q "^#!" || { rm -f "$TMP"; return 1; }
    if [ -f "$TARGET" ]; then
        cp -f "$TARGET" "$BAK" 2>/dev/null
        chmod +x "$BAK" 2>/dev/null
    fi
    cp -f "$TMP" "$TARGET" 2>/dev/null && chmod +x "$TARGET" 2>/dev/null
    rm -f "$TMP" 2>/dev/null
    echo "$(T TXT_ROLLBACK_GH_DONE)"
    press_enter_to_continue
    return 0
}
github_install_from_releases_last10() {
    local LIST TMP i sel line tag url
    echo "$(T TXT_ROLLBACK_GH_LOADING)"
    LIST="$(github_fetch_release_kv_last10 2>/dev/null)"
    if [ -z "$LIST" ]; then
        echo "$(T TXT_ROLLBACK_GH_NONE)"
        press_enter_to_continue
        return 0
    fi
    TMP="/tmp/keenetic_zapret_releases.$$"
    printf "%s\n" "$LIST" > "$TMP" 2>/dev/null
    print_line "-"
    i=1
    while IFS= read -r line; do
        tag="${line%%|*}"
        echo " $i. $tag"
        i=$((i+1))
    done < "$TMP"
    echo " 0. $(T TXT_BACK)"
    print_line "-"
    printf "%s: " "$(T TXT_ROLLBACK_GH_SELECT)"
    read sel
    if [ "$sel" = "0" ] || [ -z "$sel" ]; then
        rm -f "$TMP" 2>/dev/null
        echo "$(T TXT_ROLLBACK_CANCELLED)"
        press_enter_to_continue
        return 0
    fi
    case "$sel" in
        *[!0-9]*)
            rm -f "$TMP" 2>/dev/null
            echo "$(T TXT_INVALID_CHOICE)"
            press_enter_to_continue
            return 0
            ;;
    esac
    i=1
    while IFS= read -r line; do
        if [ "$i" = "$sel" ]; then
            tag="${line%%|*}"
            url="${line#*|}"
            rm -f "$TMP" 2>/dev/null
            github_install_script_from_url "$tag" "$url"
            if [ $? -ne 0 ]; then
                echo "$(T TXT_GITHUB_FAIL)"
                press_enter_to_continue
                return 0
            fi
            echo "$(T TXT_ROLLBACK_GH_DONE)"
            press_enter_to_continue
            return 0
        fi
        i=$((i+1))
    done < "$TMP"
    rm -f "$TMP" 2>/dev/null
    echo "$(T TXT_INVALID_CHOICE)"
    press_enter_to_continue
    return 0
}
github_install_from_tag_prompt() {
    local TAG URL
    printf "%s " "$(T TXT_ROLLBACK_GH_TAGPROMPT)"
    read TAG
    if [ "$TAG" = "0" ]; then
        echo "$(T TXT_ROLLBACK_CANCELLED)"
        press_enter_to_continue
        return 0
    fi
    if [ -z "$TAG" ]; then
        echo "$(T TXT_ROLLBACK_CANCELLED)"
        press_enter_to_continue
        return 0
    fi
    URL="$(github_fetch_release_url_by_tag "$TAG" 2>/dev/null)"
    if [ -z "$URL" ]; then
        echo "$(T TXT_ROLLBACK_GH_NONE)"
        press_enter_to_continue
        return 0
    fi
    github_install_script_from_url "$TAG" "$URL"
    if [ $? -ne 0 ]; then
        echo "$(T TXT_GITHUB_FAIL)"
        press_enter_to_continue
        return 0
    fi
    echo "$(T TXT_ROLLBACK_GH_DONE)"
    press_enter_to_continue
    return 0
}
clean_backup_files() {
    local dir="/opt/lib/opkg"
    local pattern="keenetic_zapret2_manager.sh.bak*"
    local count
    count="$(find "$dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${count:-0}" = "0" ]; then
        echo "$(T TXT_ROLLBACK_CLEAN_NONE)"
        return 0
    fi
    find "$dir" -maxdepth 1 -type f -name "$pattern" -delete 2>/dev/null
    echo "$(T TXT_ROLLBACK_CLEAN_DONE) (${count})"
}
clean_blockcheck_reports() {
    local dir="/opt/zapret2"
    local pattern="blockcheck_*.txt"
    local count
    count="$(find "$dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${count:-0}" = "0" ]; then
        echo "$(T TXT_BLOCKCHECK_CLEAN_NONE)"
        return 0
    fi
    find "$dir" -maxdepth 1 -type f -name "$pattern" -delete 2>/dev/null
    echo "$(T TXT_BLOCKCHECK_CLEAN_DONE) (${count})"
}
rollback_local_storage_menu() {
    local TARGET="/opt/lib/opkg/keenetic_zapret2_manager.sh"
    local BACKUP_PATTERN="/opt/lib/opkg/keenetic_zapret2_manager.sh.bak_*"
    while true; do
        clear
        print_line
        echo "$(T TXT_ROLLBACK_LOCAL_MENU)"
        print_line
        BACKUP_FILES="$(ls -1t $BACKUP_PATTERN 2>/dev/null)"
        if [ -z "$BACKUP_FILES" ]; then
            echo "$(T TXT_ROLLBACK_NO_LOCAL_BACKUP)"
        else
            local i=1
            for file in $BACKUP_FILES; do
                echo " $i. $(basename "$file")"
                i=$((i+1))
            done
        fi
        print_line
        echo " c) $(T TXT_ROLLBACK_CLEAN)"
        echo " 0) $(T TXT_BACK)"
        print_line
        printf '%s' "$(T TXT_ROLLBACK_MAIN_PICK) "; read -r sel || return 0
        sel=$(echo "$sel" | tr -d '[:space:]')
        case "$sel" in
            c|C)
                clean_backup_files
                press_enter_to_continue
                return
            ;;
            0|"")
                echo "$(T TXT_ROLLBACK_CANCELLED)"
                press_enter_to_continue
                return
            ;;
        esac
        if [ -z "$BACKUP_FILES" ]; then
            echo "$(T TXT_INVALID_CHOICE)"
            press_enter_to_continue
            continue
        fi
        local found=0
        local idx=1
        for file in $BACKUP_FILES; do
            if [ "$idx" = "$sel" ]; then
                found=1
                cp -f "$file" "$TARGET" 2>/dev/null && chmod +x "$TARGET" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo "$(T TXT_ROLLBACK_RESTORED)"
                else
                    echo "$(T TXT_ERROR)"
                fi
                press_enter_to_continue
                return
            fi
            idx=$((idx+1))
        done
        if [ "$found" -eq 0 ]; then
            echo "$(T TXT_INVALID_CHOICE)"
            press_enter_to_continue
        fi
    done
}
script_rollback_menu() {
    local sel
    while :; do
        clear
        print_line "=" 
        echo "$(T TXT_ROLLBACK_TITLE)"
        print_line "=" 
        echo " 1. $(T TXT_ROLLBACK_LOCAL_MENU)"
        echo " 2. $(T TXT_ROLLBACK_GH_LIST)"
        echo " 3. $(T TXT_ROLLBACK_GH_TAG)"
        echo " 0. $(T TXT_BACK)"
        print_line "-"
        printf "%s" "$(T TXT_ROLLBACK_MAIN_PICK)"
        read sel
        case "$sel" in
            0|"")
                echo "$(T TXT_ROLLBACK_CANCELLED)"
                press_enter_to_continue
                return 0
                ;;
            1)
                rollback_local_storage_menu
                continue
                ;;
            2|G|g)
                github_install_from_releases_last10
                continue
                ;;
            3|T|t)
                github_install_from_tag_prompt
                continue
                ;;
            *)
                echo "$(T TXT_INVALID_CHOICE)"
                press_enter_to_continue
                ;;
        esac
    done
}
display_menu() {
    echo
    echo
    # ---- Baslik (versiyon YOK - altta zaten var) ----
    printf "  %b%s%b\n" "${CLR_BOLD}${CLR_CYAN}" "$(T TXT_MAIN_TITLE)" "${CLR_RESET}"
    print_line "-"
    # ---- Bilgi satirlari ----
    local _sys _wan_dev _wan_state _zap_state
    _sys="$(kzm2_banner_get_system)"
    _wan_dev="$(kzm2_banner_get_wan_dev)"
    [ -z "$_wan_dev" ] && _wan_dev="-"
    _wan_state="$(kzm2_banner_get_wan_state "$_wan_dev")"
    _zap_state="$(kzm2_banner_get_zapret_state)"
    # Etiket genisligi: TR'de 'OPKG Guncelleme' = 15 karakter
    local _lw=15
    [ "$LANG" = "en" ] && _lw=15
    printf "  %b%-*s%b : %b%s%b\n"      "${CLR_BOLD}" "$_lw" "$(T TXT_MAIN_SYS_LABEL)"                        "${CLR_RESET}" "${CLR_ORANGE}" "$_sys"                                           "${CLR_RESET}"
    _fw="$(kzm2_banner_get_firmware 2>/dev/null)"
    [ -n "$_fw" ] && printf "  %b%-*s%b : %b%b%s%b\n" "${CLR_BOLD}" "$_lw" "$(T _ 'Firmware' 'Firmware')" "${CLR_RESET}" "${CLR_BOLD}" "${CLR_CYAN}" "$_fw" "${CLR_RESET}"
    local _wan_ipv4 _wan_ipv6 _wan_ip_str _wan_ip_dev
    # Tum Arayuzler modunda gercek WAN arayuzunu bul
    if [ -z "$(cat "$WAN_IF_FILE" 2>/dev/null | tr -d '\n')" ] && [ -f "$WAN_IF_FILE" ]; then
        _wan_ip_dev="$(ip -4 route show default 2>/dev/null | awk '/^default/{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    else
        _wan_ip_dev="$_wan_dev"
    fi
    _wan_ipv4="$(ip -4 addr show "$_wan_ip_dev" 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)"
    _wan_ipv6="$(ip -6 addr show "$_wan_ip_dev" 2>/dev/null | awk '/inet6 / && !/fe80/{print $2; exit}' | cut -d/ -f1)"
    _wan_ip_str=""
    [ -n "$_wan_ipv4" ] && _wan_ip_str=" | $(kzm2_fmt_ip "$_wan_ipv4")"
    [ -n "$_wan_ipv6" ] && _wan_ip_str="${_wan_ip_str} | ${CLR_CYAN}${_wan_ipv6}${CLR_RESET}"
    printf "  %b%-*s%b : %b%s%b | %b%s\n"   "${CLR_BOLD}" "$_lw" "$(T TXT_MAIN_WAN_LABEL)" \
        "${CLR_RESET}" "${CLR_RESET}" "$_wan_dev" "${CLR_RESET}" \
        "$(kzm2_banner_fmt_wan_state "$_wan_state")${_wan_ip_str}"
    local _kdns_raw _kdns_access
    _kdns_raw="$(LD_LIBRARY_PATH= ndmc -c 'show ndns' 2>/dev/null)"
    _kdns_access="$(printf '%s\n' "$_kdns_raw" | awk '/^[[:space:]]*access:/ {print $2; exit}')"
    if [ -n "$_kdns_access" ]; then
        local _kdns_name _kdns_domain
        _kdns_name="$(printf '%s\n' "$_kdns_raw"   | awk '/^[[:space:]]*name:/   {print $2; exit}')"
        _kdns_domain="$(printf '%s\n' "$_kdns_raw" | awk '/^[[:space:]]*domain:/ {print $2; exit}')"
        printf "  %b%-*s%b : %s | %b\n" "${CLR_BOLD}" "$_lw" "$(T TXT_KEENDNS_BANNER_LABEL)"             "${CLR_RESET}" "${_kdns_name}.${_kdns_domain}" "$(kzm2_banner_fmt_keendns_state "$_kdns_access")"
    fi
    # Zamanli reboot varsa goster
    local _sched_cur
    _sched_cur="$(crontab -l 2>/dev/null | grep '# KZM_REBOOT' 2>/dev/null)"
    if [ -n "$_sched_cur" ]; then
        local _sm _sh _sd _shh _smm _sname
        _sm="$(printf '%s\n' "$_sched_cur" | awk '{print $1}')"
        _sh="$(printf '%s\n' "$_sched_cur" | awk '{print $2}')"
        _sd="$(printf '%s\n' "$_sched_cur" | awk '{print $5}')"
        _shh="$(printf '%02d' "$_sh" 2>/dev/null)"
        _smm="$(printf '%02d' "$_sm" 2>/dev/null)"
        if [ "$_sd" = "*" ]; then
            printf "  %b%-*s%b : %b%b%s%b\n" \
                "${CLR_BOLD}" "$_lw" "$(T TXT_SCHED_BANNER_LABEL)" "${CLR_RESET}" \
                "${CLR_ORANGE}" "${CLR_BOLD}" "${_shh}:${_smm}" "${CLR_RESET}"
        else
            if [ "$LANG" = "en" ]; then
                case "$_sd" in
                    0|7) _sname="Sun" ;; 1) _sname="Mon" ;; 2) _sname="Tue" ;;
                    3) _sname="Wed" ;; 4) _sname="Thu" ;; 5) _sname="Fri" ;; 6) _sname="Sat" ;;
                    *) _sname="$_sd" ;;
                esac
            else
                case "$_sd" in
                    0|7) _sname="Paz" ;; 1) _sname="Pzt" ;; 2) _sname="Sal" ;;
                    3) _sname="Car" ;; 4) _sname="Per" ;; 5) _sname="Cum" ;; 6) _sname="Cmt" ;;
                    *) _sname="$_sd" ;;
                esac
            fi
            printf "  %b%-*s%b : %b%b%s%b (%s)\n" \
                "${CLR_BOLD}" "$_lw" "$(T TXT_SCHED_BANNER_LABEL)" "${CLR_RESET}" \
                "${CLR_ORANGE}" "${CLR_BOLD}" "${_shh}:${_smm}" "${CLR_RESET}" "$_sname"
        fi
    fi
    # Zamanlanmis OPKG upgrade varsa goster
    local _opkg_sched_cur
    _opkg_sched_cur="$(crontab -l 2>/dev/null | grep '# KZM_OPKG_UPGRADE' 2>/dev/null)"
    if [ -n "$_opkg_sched_cur" ]; then
        local _om _oh _odom _ohh _omm _olabel
        _om="$(printf '%s\n' "$_opkg_sched_cur" | awk '{print $1}')"
        _oh="$(printf '%s\n' "$_opkg_sched_cur" | awk '{print $2}')"
        _odom="$(printf '%s\n' "$_opkg_sched_cur" | awk '{print $3}')"
        _ohh="$(printf '%02d' "$_oh" 2>/dev/null)"
        _omm="$(printf '%02d' "$_om" 2>/dev/null)"
        case "$_odom" in
            "1,15")
                if [ "$LANG" = "en" ]; then _olabel="2 weeks"; else _olabel="2 hafta"; fi ;;
            "1")
                if [ "$LANG" = "en" ]; then _olabel="monthly"; else _olabel="aylik"; fi ;;
            *)
                if [ "$LANG" = "en" ]; then _olabel="weekly"; else _olabel="haftalik"; fi ;;
        esac
        printf "  %b%-*s%b : %b%b%s%b (%s)\n" \
            "${CLR_BOLD}" "$_lw" "$(T TXT_OPKG_SCHED_BANNER_LABEL)" "${CLR_RESET}" \
            "${CLR_ORANGE}" "${CLR_BOLD}" "${_ohh}:${_omm}" "${CLR_RESET}" "$_olabel"
    fi
    printf "  %b%-*s%b : %b%b\n"        "${CLR_BOLD}" "$_lw" "$(T TXT_MAIN_ZAPRET_LABEL)"                     "${CLR_RESET}" "${CLR_RESET}"  "$(kzm2_banner_fmt_zapret_state "$_zap_state")"
    healthmon_load_config 2>/dev/null
    if healthmon_is_running 2>/dev/null; then
        printf "  %b%-*s%b : %b%s%b\n"  "${CLR_BOLD}" "$_lw" "$(T TXT_HM_BANNER_LABEL)" \
            "${CLR_RESET}" "${CLR_GREEN}"  "$(T TXT_HM_RUN_ON)"  "${CLR_RESET}"
    else
        printf "  %b%-*s%b : %b%s%b\n"  "${CLR_BOLD}" "$_lw" "$(T TXT_HM_BANNER_LABEL)" \
            "${CLR_RESET}" "${CLR_RED}"    "$(T TXT_HM_RUN_OFF)" "${CLR_RESET}"
        printf "  %-*s   %b%s%b\n"  "$_lw" "" \
            "${CLR_ORANGE}" "$(T TXT_HM_BANNER_WARN)" "${CLR_RESET}"
    fi
    # HealthMon aktif ama AutoRes veya WAN izleme kapali ise uyar
    if healthmon_is_running 2>/dev/null; then
        if [ "${HM_ZAPRET_AUTORESTART:-0}" != "1" ]; then
            printf "  %-*s   %b%s%b\n" "$_lw" "" \
                "${CLR_ORANGE}" "$(T _ 'Zapret2 oto-restart KAPALI (Menu 16 > 4 > 5)' 'Zapret2 auto-restart DISABLED (Menu 16 > 4 > 5)')" "${CLR_RESET}"
        fi
        if [ "${HM_WANMON_ENABLE:-0}" != "1" ]; then
            printf "  %-*s   %b%s%b\n" "$_lw" "" \
                "${CLR_ORANGE}" "$(T _ 'WAN izleme KAPALI (Menu 16 > 4 > 11)' 'WAN monitoring DISABLED (Menu 16 > 4 > 11)')" "${CLR_RESET}"
        fi
    fi
    # ISP DNS kontrolu
    _isp_dns="$(LD_LIBRARY_PATH= ndmc -c 'show ip name-server' 2>/dev/null | awk '/address:/{print $2}' | tr '\n' ' ' | sed 's/ $//;s/ / - /g')"
    if [ -n "$_isp_dns" ]; then
        printf "  %b%-*s%b : %b%s%b\n" "${CLR_BOLD}" "$_lw" "ISP DNS" "${CLR_RESET}" "${CLR_ORANGE}" "$(tpl_render "$(T TXT_ISP_DNS_WARN)" DNS "$_isp_dns")" "${CLR_RESET}"
    fi
    # Telegram Bot - her zaman goster
    if [ "$(grep -s '^TG_BOT_ENABLE=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')" = "1" ]; then
        if [ -f "/tmp/kzm2_telegram_bot.pid" ] && kill -0 "$(cat "/tmp/kzm2_telegram_bot.pid" 2>/dev/null)" 2>/dev/null; then
            printf "  %b%-*s%b : %b%s%b\n" "${CLR_BOLD}" "$_lw" "$(T TXT_TGBOT_BANNER_LABEL)" \
                "${CLR_RESET}" "${CLR_GREEN}" "$(T TXT_TGBOT_BANNER_ACTIVE)" "${CLR_RESET}"
        else
            printf "  %b%-*s%b : %b%s%b\n" "${CLR_BOLD}" "$_lw" "$(T TXT_TGBOT_BANNER_LABEL)" \
                "${CLR_RESET}" "${CLR_RED}"   "$(T TXT_TGBOT_BANNER_INACTIVE)" "${CLR_RESET}"
        fi
    else
        printf "  %b%-*s%b : %b%s%b\n" "${CLR_BOLD}" "$_lw" "$(T TXT_TGBOT_BANNER_LABEL)" \
            "${CLR_RESET}" "${CLR_DIM}" "$(T TXT_TG_NOT_CONFIGURED)" "${CLR_RESET}"
    fi
    # Web Panel - her zaman goster
    if kzm_gui_is_running 2>/dev/null; then
        kzm_gui_load_config 2>/dev/null
        local _gui_lan_ip
        _gui_lan_ip="$(kzm_gui_get_lan_ip 2>/dev/null)"
        [ -z "$_gui_lan_ip" ] && _gui_lan_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
        printf "  %b%-*s%b : %b%s%b %b%s%b\n" "${CLR_BOLD}" "$_lw" "$(T TXT_GUI_BANNER_LABEL)" \
            "${CLR_RESET}" "${CLR_GREEN}" "$(T TXT_GUI_BANNER_ACTIVE)" "${CLR_RESET}" \
            "${CLR_DIM}" "(http://${_gui_lan_ip}:${KZM2_GUI_PORT})" "${CLR_RESET}"
    elif [ -f "/opt/etc/lighttpd/lighttpd.conf" ]; then
        printf "  %b%-*s%b : %b%s%b\n" "${CLR_BOLD}" "$_lw" "$(T TXT_GUI_BANNER_LABEL)" \
            "${CLR_RESET}" "${CLR_RED}" "$(T TXT_GUI_BANNER_INACTIVE)" "${CLR_RESET}"
    else
        printf "  %b%-*s%b : %b%s%b\n" "${CLR_BOLD}" "$_lw" "$(T TXT_GUI_BANNER_LABEL)" \
            "${CLR_RESET}" "${CLR_DIM}" "$(T TXT_GUI_NOT_INSTALLED)" "${CLR_RESET}"
    fi
    local _kzm_sha_state _zap_sha_state _clr_kzm _clr_zap
    _kzm_sha_state="$(cat /opt/etc/kzm2_sha256_kzm.state 2>/dev/null)"
    _zap_sha_state="$(cat /opt/etc/kzm2_sha256_zapret.state 2>/dev/null)"
    [ "$_kzm_sha_state" = "ok" ] && _clr_kzm="${CLR_GREEN}" || _clr_kzm="${CLR_ORANGE}"
    [ "$_zap_sha_state" = "ok" ] && _clr_zap="${CLR_GREEN}" || _clr_zap="${CLR_ORANGE}"
    printf "  %b%-*s%b : %b%b%s%b\n"      "${CLR_BOLD}" "$_lw" "$(T _ 'KZM2 Surum'   'KZM2 Version'    )"        "${CLR_RESET}" "${CLR_BOLD}" "$_clr_kzm" "${SCRIPT_VERSION}"                               "${CLR_RESET}"
    printf "  %b%-*s%b : %b%b%s%b\n"      "${CLR_BOLD}" "$_lw" "$(T _ 'Zapret2 Surum' 'Zapret2 Version'  )"       "${CLR_RESET}" "${CLR_BOLD}" "$_clr_zap" "$(kzm2_get_zapret_version)"                       "${CLR_RESET}"
    # ISS tespiti - cache kullan
    local _iss_cache="/opt/var/run/kzm2_iss.cache"
    if [ -f "$_iss_cache" ]; then
        _iss_domain="$(cat "$_iss_cache" 2>/dev/null | tr -d '[:space:]')"
    else
        _iss_domain="$(LD_LIBRARY_PATH= ndmc -c 'show running-config' 2>/dev/null | grep 'authentication identity' | grep -o '@[^[:space:]]*' | head -1)"
        [ -n "$_iss_domain" ] && printf '%s' "$_iss_domain" > "$_iss_cache" 2>/dev/null
    fi
    _iss_name=""
    case "$_iss_domain" in
        @ttnet)      _iss_name="Turk Telekom (TT Net)" ;;
        @superonline|@fiber) _iss_name="Superonline (SOL)" ;;
        @vodafone)   _iss_name="Vodafone" ;;
        @kablofiber) _iss_name="Kablonet Fiber (Turksat)" ;;
        @kablonet)   _iss_name="Kablonet (Turksat)" ;;
        @turksat)    _iss_name="Kablonet (Turksat)" ;;
        @turk.net)   _iss_name="TurkNet (Turk Net)" ;;
        @doping)     _iss_name="Millenicom (Doping)" ;;
        @dsmart)     _iss_name="D-Smart" ;;
        @netspeed|@netspeedas) _iss_name="Netspeed" ;;
        @isnet|@is.net) _iss_name="Isnet" ;;
        @griddsl)    _iss_name="Grid Telekom" ;;
        @doruknet|@doruk) _iss_name="Doruknet" ;;
        @orisdsl.net|@vaepro.net) _iss_name="Oris Telekom" ;;
        @gnet)       _iss_name="Gibirnet" ;;
        @comnet)     _iss_name="Comnet" ;;
        @fixnet)     _iss_name="Fixnet" ;;
        @tiklanet)   _iss_name="Tiklanet" ;;
        @poyrazwifi) _iss_name="Poyraz Wifi" ;;
        @pelikan)    _iss_name="Pelikannet" ;;
        @atlantis)   _iss_name="Atlantisnet" ;;
        @extranet)   _iss_name="Extranet" ;;
        @pananet)    _iss_name="Pananet" ;;
        @tbtnet)     _iss_name="Tbtnet" ;;
        "")          _iss_name="" ;;
        *)           _iss_name="$(printf '%s' "$_iss_domain" | sed 's/@//')" ;;
    esac
    if [ -n "$_iss_name" ]; then
        printf "  %b%-*s%b : %s\n" "${CLR_BOLD}" "$_lw" "$(T TXT_ISS_LABEL)" "${CLR_RESET}" "$_iss_name"
    fi
    _dpi_cur="$(get_dpi_profile 2>/dev/null)"
    if is_zapret2_installed; then
        if [ -n "$_dpi_cur" ]; then
            _dpi_label="$(T dpi_curp "$(dpi_profile_name_tr "$_dpi_cur")" "$(dpi_profile_name_en "$_dpi_cur")")"
            # ISS DPI li ama profil tt_default ise turuncu uyari
            _dpi_mismatch=0
            case "$_iss_domain" in
                @superonline|@fiber|@vodafone|@kablofiber|@kablonet|@turksat)
                    [ "$_dpi_cur" = "tt_default" ] && _dpi_mismatch=1 ;;
            esac
            if [ "$_dpi_mismatch" = "1" ]; then
                printf "  %b%-*s%b : %b%s — %s%b\n" "${CLR_BOLD}" "$_lw" "$(T _ 'DPI Profili' 'DPI Profile')" "${CLR_RESET}" "${CLR_ORANGE}" "$_dpi_label" "$(T TXT_DPI_MISMATCH)" "${CLR_RESET}"
            else
                printf "  %b%-*s%b : %b%s%b\n" "${CLR_BOLD}" "$_lw" "$(T _ 'DPI Profili' 'DPI Profile')" "${CLR_RESET}" "${CLR_CYAN}" "$_dpi_label" "${CLR_RESET}"
            fi
        fi
        # Filtreleme modu
        _mf="$(get_mode_filter 2>/dev/null)"
        case "$_mf" in
            autohostlist) _mf_clr="${CLR_GREEN}"  ; _mf_lbl="$(T _ 'Otomatik Liste' 'Auto Hostlist')" ;;
            hostlist)     _mf_clr="${CLR_CYAN}"   ; _mf_lbl="$(T _ 'Manuel Liste'   'Hostlist'      )" ;;
            none)         _mf_clr="${CLR_YELLOW}" ; _mf_lbl="$(T _ 'Listesiz'       'No Filter'     )" ;;
            *)            _mf_clr="${CLR_DIM}"    ; _mf_lbl="$_mf" ;;
        esac
        printf "  %b%-*s%b : %b%s%b\n" "${CLR_BOLD}" "$_lw" "$(T _ 'Filtreleme' 'Filter Mode')" "${CLR_RESET}" "$_mf_clr" "$_mf_lbl" "${CLR_RESET}"
        # Kapsam modu
        _sm="$(get_scope_mode 2>/dev/null)"
        case "$_sm" in
            smart)  _sm_clr="${CLR_GREEN}"  ;;
            global) _sm_clr="${CLR_ORANGE}" ;;
            *)      _sm_clr="${CLR_DIM}"    ;;
        esac
        printf "  %b%-*s%b : %b%s%b\n" "${CLR_BOLD}" "$_lw" "$(T _ 'Kapsam Modu' 'Scope Mode')" "${CLR_RESET}" "$_sm_clr" "$(pretty_scope_mode)" "${CLR_RESET}"
        # IPSET Modu
        local _ipset_mode _ipset_label _ipset_clr
        _ipset_mode="$(cat "$IPSET_CLIENT_MODE_FILE" 2>/dev/null | tr -d '[:space:]')"
        [ -z "$_ipset_mode" ] && _ipset_mode="all"
        if [ "$_ipset_mode" = "list" ]; then
            local _ipset_cnt="$(grep -c '[0-9]' "$IPSET_CLIENT_FILE" 2>/dev/null | tr -d ' ')"
            [ -z "$_ipset_cnt" ] && _ipset_cnt="0"
            _ipset_label="$(T _ "Secili IP ($_ipset_cnt)" "Selected IPs ($_ipset_cnt)")"
            _ipset_clr="${CLR_CYAN}"
        else
            _ipset_label="$(T _ 'Tum Ag' 'Whole Network')"
            _ipset_clr="${CLR_GREEN}"
        fi
        printf "  %b%-*s%b : %b%s%b\n" "${CLR_BOLD}" "$_lw" "$(T _ 'IPSET Modu' 'IPSET Mode')" "${CLR_RESET}" "$_ipset_clr" "$_ipset_label" "${CLR_RESET}"
    fi
    printf "  %b%-*s%b : %b%s%b\n"      "${CLR_BOLD}" "$_lw" "$(T _ 'GitHub'       'GitHub'          )"       "${CLR_RESET}" "${CLR_DIM}"   "github.com/RevolutionTR/keenetic-zapret2-manager"  "${CLR_RESET}"
    print_line "="
    # Aciklama satirlari — her biri ayri satirda, kisa
    printf "  %b%s%b\n" "${CLR_DIM}" "$(T TXT_DESC1)" "${CLR_RESET}"
    printf "  %b%s%b\n" "${CLR_DIM}" "$(T TXT_DESC2)" "${CLR_RESET}"
    printf "  %b%s%b\n" "${CLR_DIM}" "$(T TXT_DESC3)" "${CLR_RESET}"
    # TXT_OPTIMIZED ve TXT_DPI_WARNING " " ile basliyor — " %b%s" ile toplam 2 bosluk olur
    printf " %b%s%b\n" "${CLR_DIM}" "$(T TXT_OPTIMIZED)" "${CLR_RESET}"
    printf " %b%s%b\n" "${CLR_DIM}" "$(T dpi_warn "$TXT_DPI_WARNING_TR" "$TXT_DPI_WARNING_EN")" "${CLR_RESET}"
    print_line "-"
    # _mi: menu item — numara TURUNCU, metin dim
    _mi() {
        local _raw="$1"
        local _num _txt _main _note
        _num="${_raw%%.*}."
        _txt="${_raw#*.}"
        # Parantez varsa: ana metin bold, parantez ici dim
        case "$_txt" in
            *" ("*")"*)
                _main="${_txt% (*}"
                _note=" (${_txt##* (}"
                printf "  %b%s%b%b%s%b%b%s%b\n" \
                    "${CLR_ORANGE}" "$_num"  "${CLR_RESET}" \
                    "${CLR_BOLD}"   "$_main" "${CLR_RESET}" \
                    "${CLR_DIM}"    "$_note" "${CLR_RESET}"
                ;;
            *)
                printf "  %b%s%b%b%s%b\n" \
                    "${CLR_ORANGE}" "$_num" "${CLR_RESET}" \
                    "${CLR_BOLD}"   "$_txt" "${CLR_RESET}"
                ;;
        esac
    }
    # Cizgi: terminal genisligine gore dinamik "- - - - ..." 
    local _cols _sep
    _cols="$(get_term_cols 2>/dev/null)"
    [ -z "$_cols" ] && _cols=80
    [ "$_cols" -lt 50 ] 2>/dev/null && _cols=50
    _sep="$(printf '%*s' "$_cols" '' | tr ' ' '-' | sed 's/--/- /g;s/ $//')"
    # ---- ZAPRET YONETIMI (1-8) ----
    printf "  %b%s%b\n" "${CLR_CYAN}" "$(T _ 'ZAPRET2 YONETIMI' 'ZAPRET2 MANAGEMENT')" "${CLR_RESET}"
    printf "%b%s%b\n"   "${CLR_DIM}"  "$_sep" "${CLR_RESET}"
    _mi "$(T TXT_MENU_1)"
    _mi "$(T TXT_MENU_2)"
    _mi "$(T TXT_MENU_3)"
    _mi "$(T TXT_MENU_4)"
    _mi "$(T TXT_MENU_5)"
    _mi "$(T TXT_MENU_6)"
    _mi "$(T TXT_MENU_7)"
    _mi "$(T TXT_MENU_8)"
    echo
    # ---- SISTEM & ARACLAR (9-16) ----
    printf "  %b%s%b\n" "${CLR_CYAN}" "$(T _ 'SISTEM & ARACLAR' 'SYSTEM & TOOLS')" "${CLR_RESET}"
    printf "%b%s%b\n"   "${CLR_DIM}"  "$_sep" "${CLR_RESET}"
    _mi "$(T TXT_MENU_9)"
    _mi "$(T TXT_MENU_10)"
    _mi "$(T TXT_MENU_11)"
    _mi "$(T TXT_MENU_12)"
    _mi "$(T TXT_MENU_13)"
    _mi "$(T TXT_MENU_14)"
    _mi "$(T TXT_MENU_15)"
    _mi "$(T TXT_MENU_16)"
    _mi "$(T TXT_MENU_17)"
    echo
    # ---- DIGER ----
    printf "  %b%s%b\n" "${CLR_CYAN}" "$(T _ 'DIGER' 'OTHER')" "${CLR_RESET}"
    printf "%b%s%b\n"   "${CLR_DIM}"  "$_sep" "${CLR_RESET}"
    _mi "$(T TXT_MENU_B)"
    _mi "$(T TXT_MENU_L)  ($(lang_label))"
    _mi "$(T TXT_MENU_R)"
    _mi "$(T TXT_MENU_U)"
    _mi "$(T TXT_MENU_0)"
    print_line "-"
    echo
    printf "$(T TXT_PROMPT_MAIN)"
}
# --- DNS YONETIMI ---
# Master liste: KEY|TYPE|ADD_CMD|DEL_CMD|PAKET
_dns_master_list() {
    printf '%s
' \
        "8.8.8.8@dns.google|DoT|dns-proxy tls upstream 8.8.8.8 sni dns.google|no dns-proxy tls upstream 8.8.8.8|Google|Filtresiz" \
        "8.8.4.4@dns.google|DoT|dns-proxy tls upstream 8.8.4.4 sni dns.google|no dns-proxy tls upstream 8.8.4.4|Google|Filtresiz" \
        "dns.google/dns-query|DoH|dns-proxy https upstream https://dns.google/dns-query dnsm|no dns-proxy https upstream https://dns.google/dns-query|Google|Filtresiz" \
        "1.1.1.1@one.one.one.one|DoT|dns-proxy tls upstream 1.1.1.1 sni one.one.one.one|no dns-proxy tls upstream 1.1.1.1|Cloudflare|Filtresiz" \
        "1.0.0.1@one.one.one.one|DoT|dns-proxy tls upstream 1.0.0.1 sni one.one.one.one|no dns-proxy tls upstream 1.0.0.1|Cloudflare|Filtresiz" \
        "cloudflare-dns.com/dns-query|DoH|dns-proxy https upstream https://cloudflare-dns.com/dns-query dnsm|no dns-proxy https upstream https://cloudflare-dns.com/dns-query|Cloudflare|Filtresiz" \
        "1.1.1.1/dns-query|DoH|dns-proxy https upstream https://1.1.1.1/dns-query dnsm|no dns-proxy https upstream https://1.1.1.1/dns-query|Cloudflare|Filtresiz" \
        "1.0.0.1/dns-query|DoH|dns-proxy https upstream https://1.0.0.1/dns-query dnsm|no dns-proxy https upstream https://1.0.0.1/dns-query|Cloudflare|Filtresiz" \
        "1.1.1.2@security.cloudflare-dns.com|DoT|dns-proxy tls upstream 1.1.1.2 sni security.cloudflare-dns.com|no dns-proxy tls upstream 1.1.1.2|CF_Families|Aile" \
        "1.0.0.2@security.cloudflare-dns.com|DoT|dns-proxy tls upstream 1.0.0.2 sni security.cloudflare-dns.com|no dns-proxy tls upstream 1.0.0.2|CF_Families|Aile" \
        "9.9.9.9@dns.quad9.net|DoT|dns-proxy tls upstream 9.9.9.9 sni dns.quad9.net|no dns-proxy tls upstream 9.9.9.9|Quad9|Gizlilik" \
        "149.112.112.112@dns.quad9.net|DoT|dns-proxy tls upstream 149.112.112.112 sni dns.quad9.net|no dns-proxy tls upstream 149.112.112.112|Quad9|Gizlilik" \
        "94.140.14.14@dns.adguard-dns.com|DoT|dns-proxy tls upstream 94.140.14.14 sni dns.adguard-dns.com|no dns-proxy tls upstream 94.140.14.14|AdGuard|Reklam" \
        "94.140.15.15@dns.adguard-dns.com|DoT|dns-proxy tls upstream 94.140.15.15 sni dns.adguard-dns.com|no dns-proxy tls upstream 94.140.15.15|AdGuard|Reklam" \
        "dns.mullvad.net/dns-query|DoH|dns-proxy https upstream https://dns.mullvad.net/dns-query dnsm|no dns-proxy https upstream https://dns.mullvad.net/dns-query|Mullvad|Gizlilik" \
        "185.228.168.9@family-filter-dns.cleanbrowsing.org|DoT|dns-proxy tls upstream 185.228.168.9 sni family-filter-dns.cleanbrowsing.org|no dns-proxy tls upstream 185.228.168.9|CleanBrowsing|Aile" \
        "185.228.169.9@family-filter-dns.cleanbrowsing.org|DoT|dns-proxy tls upstream 185.228.169.9 sni family-filter-dns.cleanbrowsing.org|no dns-proxy tls upstream 185.228.169.9|CleanBrowsing|Aile"
}
# Mevcut DNS sunucularini goster
# $1: raw show dns-proxy ciktisi
dns_show_current() {
    local _raw="$1"
    local _found=0
    local _entry _key _type _pkg _grp
    local _groups=""
    print_line "-"
    printf " %b%s:%b
" "${CLR_BOLD}" "$(T TXT_DNS_MGMT_CURRENT)" "${CLR_RESET}"
    while IFS= read -r _entry; do
        _key="${_entry%%|*}"
        _rest="${_entry#*|}"
        _type="${_rest%%|*}"
        _rest2="${_rest#*|}"; _rest3="${_rest2#*|}"; _rest4="${_rest3#*|}"
        _pkg="${_rest4%%|*}"
        _grp="${_rest4##*|}"
        local _grep_key
        _grep_key="${_key%%@*}"
        local _matched=0
        case "$_type" in
            DoT) echo "$_raw" | grep -qF "# ${_grep_key}@" && _matched=1 ;;
            DoH) echo "$_raw" | grep -qF "uri: https://${_grep_key}" && _matched=1 ;;
        esac
        if [ "$_matched" = "1" ]; then
            # Grup rengi ve cevirisi
            local _gc _grp_label
            case "$_grp" in
                Filtresiz) _gc="${CLR_GREEN}";  _grp_label="$(T TXT_DNS_GRP_FILTRESIZ)" ;;
                Gizlilik)  _gc="${CLR_CYAN}";   _grp_label="$(T TXT_DNS_GRP_GIZLILIK)" ;;
                Reklam)    _gc="${CLR_ORANGE}";  _grp_label="$(T TXT_DNS_GRP_REKLAM)" ;;
                Aile)      _gc="${CLR_YELLOW}";  _grp_label="$(T TXT_DNS_GRP_AILE)" ;;
                *)         _gc="${CLR_DIM}";     _grp_label="$_grp" ;;
            esac
            printf "  %b%-5s%b %-42s %b(%s)%b
" "${CLR_GREEN}" "[$_type]" "${CLR_RESET}" "$_key" "$_gc" "$_grp_label" "${CLR_RESET}"
            _found=$((_found+1))
            # Aktif gruplari topla
            echo "$_groups" | grep -qF "$_grp" || _groups="${_groups}${_grp} "
        fi
    done << MASTEREOF
$(_dns_master_list)
MASTEREOF
    if [ "$_found" -eq 0 ]; then
        printf "  %b%s%b
" "${CLR_DIM}" "$(T TXT_DNS_MGMT_NONE)" "${CLR_RESET}"
    fi
    # Karisik grup uyarisi
    local _gcount
    _gcount=$(printf '%s' "$_groups" | wc -w)
    if [ "$_gcount" -gt 1 ]; then
        printf "
  %b[!] %s%b
" "${CLR_ORANGE}" "$(T _ 'Farkli filtre gruplari aktif! DNS karisikligi yasanabilir.' 'Multiple filter groups active! DNS conflicts may occur.')" "${CLR_RESET}"
    fi
    print_line "-"
    return "$_found"
}
# Hazir paket ekle
dns_add_preset_menu() {
    while true; do
        local _raw
        _raw="$(LD_LIBRARY_PATH= ndmc -c 'show dns-proxy' 2>/dev/null)"
        clear
        print_line "="
        printf " %b%s%b
" "${CLR_CYAN}" "$(T TXT_DNS_MGMT_PRESET_TITLE)" "${CLR_RESET}"
        dns_show_current "$_raw"
        echo ""
        printf " %b 1.%b %-28s%s\n" "${CLR_BOLD}" "${CLR_RESET}" "$(T _ 'Standart (Filtresiz)' 'Standard (No Filter)')" "Google + Cloudflare"
        printf " %b 2.%b %-28s%s\n" "${CLR_BOLD}" "${CLR_RESET}" "$(T _ 'Gizlilik Odakli' 'Privacy Focused')" "Quad9 + Mullvad"
        printf " %b 3.%b %-28s%s\n" "${CLR_BOLD}" "${CLR_RESET}" "$(T _ 'Reklam Engelleyici' 'Ad Blocker')" "AdGuard DoT"
        printf " %b 4.%b %-28s%s\n" "${CLR_BOLD}" "${CLR_RESET}" "$(T _ 'Aile Filtresi' 'Family Filter')" "CF Families + CleanBrowsing"
        printf " %b 0.%b %s\n" "${CLR_BOLD}" "${CLR_RESET}" "$(T _ 'Geri' 'Back')"
        echo ""
        printf '%s ' "$(T _ 'Secim:' 'Choice:')"
        read -r _ch </dev/tty
        case "$_ch" in
            1) _dns_add_package "Google" "$_raw"
               _dns_add_package "Cloudflare" "$_raw"
               press_enter_to_continue ;;
            2) _dns_add_package "Quad9" "$_raw"
               _dns_add_package "Mullvad" "$_raw"
               _dns_add_package "Dns0eu" "$_raw"
               press_enter_to_continue ;;
            3) _dns_add_package "AdGuard" "$_raw"
               press_enter_to_continue ;;
            4) _dns_add_package "CF_Families" "$_raw"
               _dns_add_package "CleanBrowsing" "$_raw"
               press_enter_to_continue ;;
            0) return 0 ;;
        esac
    done
}
# Belirli paketi ekle
# $1: paket adi (Google|Cloudflare|CF_Families|NextDNS|Comss)
_dns_add_package() {
    local _pkg="$1" _raw="$2"
    local _changed=0 _entry _key _type _add _del _p
    print_line "-"
    while IFS= read -r _entry; do
        _p="$(printf '%s' "$_entry" | cut -d'|' -f5)"
        [ "$_p" = "$_pkg" ] || continue
        _key="${_entry%%|*}"
        _rest="${_entry#*|}"
        _type="${_rest%%|*}"
        _rest2="${_rest#*|}"
        _add="${_rest2%%|*}"
        _grep_key="${_key%%@*}"
        _apmatch=0
        case "$_type" in
            DoT) echo "$_raw" | grep -qF "# ${_grep_key}@" && _apmatch=1 ;;
            DoH) echo "$_raw" | grep -qF "uri: https://${_grep_key}" && _apmatch=1 ;;
        esac
        if [ "$_apmatch" = "1" ]; then
            printf "  %b%-5s%b %-40s : %b%s%b
" "${CLR_CYAN}" "[$_type]" "${CLR_RESET}" "$_key"                 "${CLR_DIM}" "$(T TXT_DNS_MGMT_PRESET_EXISTS)" "${CLR_RESET}"
        else
            LD_LIBRARY_PATH= ndmc -c "$_add" >/dev/null 2>&1
            printf "  %b%-5s%b %-40s : %b%s%b
" "${CLR_CYAN}" "[$_type]" "${CLR_RESET}" "$_key"                 "${CLR_GREEN}" "$(T TXT_DNS_MGMT_ADDED)" "${CLR_RESET}"
            _changed=1
        fi
    done << MASTEREOF
$(_dns_master_list)
MASTEREOF
    if [ "$_changed" -eq 1 ]; then
        LD_LIBRARY_PATH= ndmc -c "system configuration save" >/dev/null 2>&1
        print_status PASS "$(T TXT_DNS_MGMT_SAVED)"
    fi
    print_line "-"
}
# Sunucu sil - aktif bilinen sunuculari listele, secim al
dns_delete_menu() {
    local _raw
    _raw="$(LD_LIBRARY_PATH= ndmc -c 'show dns-proxy' 2>/dev/null)"
    clear
    print_line "="
    printf " %b%s%b
" "${CLR_CYAN}" "$(T TXT_DNS_MGMT_DEL_TITLE)" "${CLR_RESET}"
    print_line "-"
    # Aktif sunuculari numaralandirarak listele
    local _num=0 _entry _key _type _del _grep_key
    local _keys="" _dels=""
    while IFS= read -r _entry; do
        _key="${_entry%%|*}"
        _rest="${_entry#*|}"
        _type="${_rest%%|*}"
        _rest2="${_rest#*|}"
        _rest3="${_rest2#*|}"
        _del="${_rest3%%|*}"
        _grep_key="${_key%%@*}"
        _dmatch=0
        case "$_type" in
            DoT) echo "$_raw" | grep -qF "# ${_grep_key}@" && _dmatch=1 ;;
            DoH) echo "$_raw" | grep -qF "uri: https://${_grep_key}" && _dmatch=1 ;;
        esac
        if [ "$_dmatch" = "1" ]; then
            _num=$((_num+1))
            printf "  %b%2d.%b %b%-5s%b %s
" "${CLR_BOLD}" "$_num" "${CLR_RESET}"                 "${CLR_CYAN}" "[$_type]" "${CLR_RESET}" "$_key"
            _keys="${_keys}${_num}:${_key}|"
            _dels="${_dels}${_num}:${_del}|"
        fi
    done << MASTEREOF
$(_dns_master_list)
MASTEREOF
    if [ "$_num" -eq 0 ]; then
        print_status INFO "$(T TXT_DNS_MGMT_DEL_NONE)"
        press_enter_to_continue
        return 0
    fi
    print_line "-"
    printf '%s ' "$(T _ 'Silmek istediginiz numara (0=Geri):' 'Enter number to delete (0=Back):')"
    read -r _sel </dev/tty
    case "$_sel" in
        0) return 0 ;;
    esac
    # Secilen numara icin del komutu bul
    local _found_del="" _found_key=""
    local _item
    printf '%s' "$_dels" | tr '|' '
' | while IFS= read -r _item; do
        [ -z "$_item" ] && continue
        local _n="${_item%%:*}"
        local _d="${_item#*:}"
        if [ "$_n" = "$_sel" ]; then
            printf '%s' "$_d"
            return 0
        fi
    done
    # Pipe subshell calistigi icin dogrudan ata
    local _del_cmd
    _del_cmd="$(printf '%s' "$_dels" | tr '|' '
' | awk -F: -v n="$_sel" 'NF>=2 && $1==n {print substr($0,length($1)+2)}')"
    _found_key="$(printf '%s' "$_keys" | tr '|' '
' | awk -F: -v n="$_sel" 'NF>=2 && $1==n {print substr($0,length($1)+2)}')"
    if [ -z "$_del_cmd" ]; then
        print_status WARN "$(T _ 'Gecersiz secim.' 'Invalid selection.')"
        press_enter_to_continue
        return 0
    fi
    LD_LIBRARY_PATH= ndmc -c "$_del_cmd" >/dev/null 2>&1
    LD_LIBRARY_PATH= ndmc -c "system configuration save" >/dev/null 2>&1
    printf "  %s : %b%s%b
" "$_found_key" "${CLR_GREEN}" "$(T TXT_DNS_MGMT_DELETED)" "${CLR_RESET}"
    print_status PASS "$(T TXT_DNS_MGMT_SAVED)"
    press_enter_to_continue
}
# Tum bilinen DNS sunucularini temizle
dns_delete_all() {
    local _raw
    _raw="$(LD_LIBRARY_PATH= ndmc -c 'show dns-proxy' 2>/dev/null)"
    echo ""
    printf '%b%s%b ' "${CLR_RED}" "$(T TXT_DNS_MGMT_DELALL_WARN)" "${CLR_RESET}"
    read -r _ans </dev/tty
    if ! echo "$_ans" | grep -qi "^[ey]"; then
        echo "$(T _ 'Iptal edildi.' 'Cancelled.')"
        press_enter_to_continue
        return 0
    fi
    local _changed=0 _entry _key _del _grep_key
    while IFS= read -r _entry; do
        _key="${_entry%%|*}"
        _rest="${_entry#*|}"
        _type2="${_rest%%|*}"
        _rest2="${_rest#*|}"
        _rest3="${_rest2#*|}"
        _del="${_rest3%%|*}"
        _grep_key="${_key%%@*}"
        _damatch=0
        case "$_type2" in
            DoT) echo "$_raw" | grep -qF "# ${_grep_key}@" && _damatch=1 ;;
            DoH) echo "$_raw" | grep -qF "uri: https://${_grep_key}" && _damatch=1 ;;
        esac
        if [ "$_damatch" = "1" ]; then
            LD_LIBRARY_PATH= ndmc -c "$_del" >/dev/null 2>&1
            printf "  %s : %b%s%b
" "$_key" "${CLR_RED}" "$(T TXT_DNS_MGMT_DELETED)" "${CLR_RESET}"
            _changed=1
        fi
    done << MASTEREOF
$(_dns_master_list)
MASTEREOF
    if [ "$_changed" -eq 1 ]; then
        LD_LIBRARY_PATH= ndmc -c "system configuration save" >/dev/null 2>&1
        print_status PASS "$(T TXT_DNS_MGMT_DELALL_DONE)"
    else
        print_status INFO "$(T TXT_DNS_MGMT_NONE)"
    fi
    press_enter_to_continue
}
# Manuel DNS sunucusu ekle
dns_add_manual() {
    clear
    print_line "="
    printf " %b%s%b\n" "${CLR_CYAN}" "$(T TXT_DNS_MGMT_MANUAL_TITLE)" "${CLR_RESET}"
    print_line "-"
    printf " %b 1.%b DoT  [DNS over TLS  - port 853]\n" "${CLR_BOLD}" "${CLR_RESET}"
    printf " %b 2.%b DoH  [DNS over HTTPS - port 443]\n" "${CLR_BOLD}" "${CLR_RESET}"
    printf " %b 0.%b $(T _ 'Geri' 'Back')\n" "${CLR_BOLD}" "${CLR_RESET}"
    echo ""
    printf '%s ' "$(T _ 'Tip secin:' 'Select type:')"
    read -r _type </dev/tty
    case "$_type" in
        0) return 0 ;;
        1)
            printf '%s ' "$(T TXT_DNS_MGMT_MANUAL_IP)"
            read -r _ip </dev/tty
            [ -z "$_ip" ] && { print_status WARN "$(T TXT_DNS_MGMT_MANUAL_INVALID)"; press_enter_to_continue; return 0; }
            printf '%s ' "$(T TXT_DNS_MGMT_MANUAL_SNI)"
            read -r _sni </dev/tty
            local _cmd
            if [ -n "$_sni" ]; then
                _cmd="dns-proxy tls upstream $_ip sni $_sni"
            else
                _cmd="dns-proxy tls upstream $_ip"
            fi
            LD_LIBRARY_PATH= ndmc -c "$_cmd" >/dev/null 2>&1
            LD_LIBRARY_PATH= ndmc -c "system configuration save" >/dev/null 2>&1
            printf "  [DoT] %s%s : %b%s%b\n" "$_ip" "${_sni:+@$_sni}" "${CLR_GREEN}" "$(T TXT_DNS_MGMT_ADDED)" "${CLR_RESET}"
            print_status PASS "$(T TXT_DNS_MGMT_SAVED)"
            ;;
        2)
            printf '%s ' "$(T TXT_DNS_MGMT_MANUAL_URL)"
            read -r _url </dev/tty
            [ -z "$_url" ] && { print_status WARN "$(T TXT_DNS_MGMT_MANUAL_INVALID)"; press_enter_to_continue; return 0; }
            case "$_url" in https://*) ;; *) _url="https://$_url" ;; esac
            LD_LIBRARY_PATH= ndmc -c "dns-proxy https upstream $_url dnsm" >/dev/null 2>&1
            LD_LIBRARY_PATH= ndmc -c "system configuration save" >/dev/null 2>&1
            printf "  [DoH] %s : %b%s%b\n" "$_url" "${CLR_GREEN}" "$(T TXT_DNS_MGMT_ADDED)" "${CLR_RESET}"
            print_status PASS "$(T TXT_DNS_MGMT_SAVED)"
            ;;
        *)
            print_status WARN "$(T TXT_DNS_MGMT_MANUAL_INVALID)"
            ;;
    esac
    press_enter_to_continue
}
# Rebind koruma toggle
dns_rebind_toggle() {
    local _raw _rc
    _raw="$(LD_LIBRARY_PATH= ndmc -c 'show dns-proxy' 2>/dev/null)"
    _rc="$(LD_LIBRARY_PATH= ndmc -c 'show running-config' 2>/dev/null)"
    # Acik: norebind_ctl = on VE running-config'de "no rebind-protect" YOK
    if echo "$_raw" | grep -q "norebind_ctl = on" && ! echo "$_rc" | grep -q "no rebind-protect"; then
        # Kapat
        LD_LIBRARY_PATH= ndmc -c "no dns-proxy rebind-protect" >/dev/null 2>&1
        LD_LIBRARY_PATH= ndmc -c "system configuration save" >/dev/null 2>&1
        print_status INFO "$(T TXT_DNS_MGMT_REBIND_DISABLED)"
    else
        # Ac
        LD_LIBRARY_PATH= ndmc -c "dns-proxy rebind-protect auto" >/dev/null 2>&1
        LD_LIBRARY_PATH= ndmc -c "system configuration save" >/dev/null 2>&1
        print_status PASS "$(T TXT_DNS_MGMT_REBIND_ENABLED)"
    fi
    press_enter_to_continue
}
# Ana DNS yonetim menusu
dns_management_menu() {
    while true; do
        local _raw _rc _rebind_st
        _raw="$(LD_LIBRARY_PATH= ndmc -c 'show dns-proxy' 2>/dev/null)"
        _rc="$(LD_LIBRARY_PATH= ndmc -c 'show running-config' 2>/dev/null)"
        if echo "$_raw" | grep -q "norebind_ctl = on" && ! echo "$_rc" | grep -q "no rebind-protect"; then
            _rebind_st="${CLR_GREEN}${CLR_BOLD}$(T TXT_DNS_MGMT_REBIND_ON)${CLR_RESET}"
        else
            _rebind_st="${CLR_RED}${CLR_BOLD}$(T TXT_DNS_MGMT_REBIND_OFF)${CLR_RESET}"
        fi
        clear
        print_line "="
        printf " %b%s%b\n" "${CLR_CYAN}" "$(T TXT_DNS_MGMT_TITLE)" "${CLR_RESET}"
        dns_show_current "$_raw"
        echo ""
        printf " %b 1.%b $(T TXT_DNS_MGMT_OPT1) %b[Google / Cloudflare / CF Families / NextDNS]%b\n" "${CLR_BOLD}" "${CLR_RESET}" "${CLR_DIM}" "${CLR_RESET}"
        printf " %b 2.%b $(T TXT_DNS_MGMT_OPT2) %b[IP + SNI veya DoH URL]%b\n" "${CLR_BOLD}" "${CLR_RESET}" "${CLR_DIM}" "${CLR_RESET}"
        printf " %b 3.%b $(T TXT_DNS_MGMT_OPT3)\n" "${CLR_BOLD}" "${CLR_RESET}"
        printf " %b 4.%b $(T TXT_DNS_MGMT_OPT4)\n" "${CLR_BOLD}" "${CLR_RESET}"
        printf " %b 5.%b $(T TXT_DNS_MGMT_OPT5) [%b]%b\n" "${CLR_BOLD}" "${CLR_RESET}" "$_rebind_st" "${CLR_RESET}"
        printf " %b 0.%b $(T _ 'Geri' 'Back')\n" "${CLR_BOLD}" "${CLR_RESET}"
        echo ""
        printf " %b%s%b\n" "${CLR_ORANGE}" "$(T TXT_MENU14_DNS_VPN_WARN)" "${CLR_RESET}"
        echo ""
        printf '%s ' "$(T _ 'Secim:' 'Choice:')"
        read -r _ch </dev/tty
        case "$_ch" in
            1) dns_add_preset_menu ;;
            2) dns_add_manual ;;
            3) dns_delete_menu ;;
            4) dns_delete_all ;;
            5) dns_rebind_toggle ;;
            0) return 0 ;;
        esac
    done
}
# --- OPKG GUNCELLEME ---
configure_secure_dns() {
    clear
    print_line "="
    printf " %b%s%b\n" "${CLR_CYAN}" "$(T TXT_MENU14_DNS_TITLE)" "${CLR_RESET}"
    print_line "="
    # Mevcut durumu al
    local _raw _rc
    _raw="$(LD_LIBRARY_PATH= ndmc -c 'show dns-proxy' 2>/dev/null)"
    _rc="$(LD_LIBRARY_PATH= ndmc -c 'show running-config' 2>/dev/null)"
    # Internet Filtresi aktif mi kontrol et
    local _filter_active=0
    if echo "$_raw" | grep -qiE "filter.engine|filter.assign"; then
        _filter_active=1
    fi
    if [ "$_filter_active" -eq 1 ]; then
        print_status WARN "$(T TXT_MENU14_DNS_FILTER_WARN)"
    fi
    print_line "-"
    # Oncelikle mevcut durumu goster
    local _need_add=0
    # rebind-protect
    if echo "$_raw" | grep -q "norebind_ctl = on" || echo "$_rc" | grep -q "rebind-protect"; then
        printf " %-45s %b%-5s%b: %b%s%b\n" "$(T TXT_MENU14_DNS_REBIND)" \
            "${CLR_CYAN}" "[---]" "${CLR_RESET}" \
            "${CLR_DIM}" "$(T TXT_MENU14_DNS_EXISTS)" "${CLR_RESET}"
    else
        printf " %-45s %b%-5s%b: %b%s%b\n" "$(T TXT_MENU14_DNS_REBIND)" \
            "${CLR_CYAN}" "[---]" "${CLR_RESET}" \
            "${CLR_ORANGE}" "$(T _ 'Eksik' 'Missing')" "${CLR_RESET}"
        _need_add=1
    fi
    local _entry _key _type
    for _entry in \
        "8.8.8.8@dns.google|DoT|dns-proxy tls upstream 8.8.8.8 sni dns.google" \
        "8.8.4.4@dns.google|DoT|dns-proxy tls upstream 8.8.4.4 sni dns.google" \
        "1.1.1.1|DoT|dns-proxy tls upstream 1.1.1.1" \
        "1.0.0.1@one.one.one.one|DoT|dns-proxy tls upstream 1.0.0.1 sni one.one.one.one" \
        "cloudflare-dns.com/dns-query@dnsm|DoH|dns-proxy https upstream https://cloudflare-dns.com/dns-query dnsm" \
        "dns.google/dns-query@dnsm|DoH|dns-proxy https upstream https://dns.google/dns-query dnsm"
    do
        _key="${_entry%%|*}"
        _type="$(echo "$_entry" | cut -d'|' -f2)"
        if echo "$_raw" | grep -qF "$_key"; then
            printf " %-45s %b%-5s%b: %b%s%b\n" "$_key" \
                "${CLR_CYAN}" "[$_type]" "${CLR_RESET}" \
                "${CLR_DIM}" "$(T TXT_MENU14_DNS_EXISTS)" "${CLR_RESET}"
        else
            printf " %-45s %b%-5s%b: %b%s%b\n" "$_key" \
                "${CLR_CYAN}" "[$_type]" "${CLR_RESET}" \
                "${CLR_ORANGE}" "$(T _ 'Eksik' 'Missing')" "${CLR_RESET}"
            _need_add=1
        fi
    done
    print_line "-"
    # VPN DNS leak uyarisi - her zaman goster
    echo ""
    printf " %b%s%b\n" "${CLR_ORANGE}" "$(T TXT_MENU14_DNS_VPN_WARN)" "${CLR_RESET}"
    echo ""
    # Hepsi mevcutsa bitir
    if [ "$_need_add" -eq 0 ]; then
        print_status INFO "$(T TXT_MENU14_DNS_ALREADY)"
        press_enter_to_continue
        return 0
    fi
    # Onay al
    printf '%s ' "$(T TXT_MENU14_DNS_CONFIRM)"
    read -r _ans
    if ! echo "$_ans" | grep -qi "^[ey]"; then
        echo "$(T _ 'Iptal edildi.' 'Cancelled.')"
        press_enter_to_continue
        return 0
    fi
    print_line "-"
    local _changed=0
    # rebind-protect ekle
    if ! echo "$_raw" | grep -q "norebind_ctl = on" && ! echo "$_rc" | grep -q "rebind-protect"; then
        LD_LIBRARY_PATH= ndmc -c "dns-proxy rebind-protect auto" >/dev/null 2>&1
        printf " %-45s %b%-5s%b: %b%s%b\n" "$(T TXT_MENU14_DNS_REBIND)" \
            "${CLR_CYAN}" "[---]" "${CLR_RESET}" \
            "${CLR_GREEN}" "$(T TXT_MENU14_DNS_ADDED)" "${CLR_RESET}"
        _changed=1
    fi
    # Upstream'leri ekle
    local _cmd
    for _entry in \
        "8.8.8.8@dns.google|DoT|dns-proxy tls upstream 8.8.8.8 sni dns.google" \
        "8.8.4.4@dns.google|DoT|dns-proxy tls upstream 8.8.4.4 sni dns.google" \
        "1.1.1.1|DoT|dns-proxy tls upstream 1.1.1.1" \
        "1.0.0.1@one.one.one.one|DoT|dns-proxy tls upstream 1.0.0.1 sni one.one.one.one" \
        "cloudflare-dns.com/dns-query@dnsm|DoH|dns-proxy https upstream https://cloudflare-dns.com/dns-query dnsm" \
        "dns.google/dns-query@dnsm|DoH|dns-proxy https upstream https://dns.google/dns-query dnsm"
    do
        _key="${_entry%%|*}"
        _type="$(echo "$_entry" | cut -d'|' -f2)"
        _cmd="$(echo "$_entry" | cut -d'|' -f3-)"
        if ! echo "$_raw" | grep -qF "$_key"; then
            LD_LIBRARY_PATH= ndmc -c "$_cmd" >/dev/null 2>&1
            printf " %-45s %b%-5s%b: %b%s%b\n" "$_key" \
                "${CLR_CYAN}" "[$_type]" "${CLR_RESET}" \
                "${CLR_GREEN}" "$(T TXT_MENU14_DNS_ADDED)" "${CLR_RESET}"
            _changed=1
        fi
    done
    print_line "-"
    if [ "$_changed" -eq 1 ]; then
        LD_LIBRARY_PATH= ndmc -c "system configuration save" >/dev/null 2>&1
        print_status PASS "$(T TXT_MENU14_DNS_SAVED)"
    else
        print_status INFO "$(T TXT_MENU14_DNS_ALREADY)"
    fi
    press_enter_to_continue
}
run_opkg_update() {
    print_line "-"
    print_status INFO "$(T TXT_OPKG_UPDATING)"
    if opkg update 2>/dev/null; then
        print_status PASS "$(T TXT_OPKG_UPDATED)"
    else
        print_status WARN "$(T TXT_OPKG_UPDATE_FAIL)"
        press_enter_to_continue
        return 1
    fi
    local _upgradable
    _upgradable="$(opkg list-upgradable 2>/dev/null)"
    if [ -z "$_upgradable" ]; then
        print_status INFO "$(T TXT_OPKG_ALL_CURRENT)"
        press_enter_to_continue
        return 0
    fi
    local _count
    _count="$(printf '%s\n' "$_upgradable" | grep -c .)"
    print_status INFO "${_count} $(T TXT_OPKG_UPGRADABLE)"
    echo
    printf '%s\n' "$_upgradable"
    echo
    print_line "-"
    printf '%b%s%b\n' "${CLR_ORANGE}${CLR_BOLD}" "$(T TXT_OPKG_UPGRADE_WARN)" "${CLR_RESET}"
    printf '%b%s%b\n' "${CLR_ORANGE}" "$(T TXT_OPKG_UPGRADE_WARN2)" "${CLR_RESET}"
    echo
    printf '%s' "$(T TXT_OPKG_UPGRADE_CONFIRM)"
    local _ans
    read -r _ans </dev/tty
    case "$_ans" in
        e|E|y|Y)
            print_status INFO "$(T TXT_OPKG_UPGRADING)"
            if opkg upgrade 2>&1; then
                print_status PASS "$(T TXT_OPKG_UPGRADED)"
            else
                print_status WARN "$(T TXT_OPKG_UPGRADE_FAIL)"
            fi
            ;;
        *)
            print_status INFO "$(T TXT_CANCELLED)"
            ;;
    esac
    press_enter_to_continue
}
# --- AG TANILAMA ALT MENUSU ---
network_diag_menu() {
    while true; do
        clear
        print_line "="
        echo "$(T TXT_MENU14_TITLE)"
        print_line "="
        echo " $(T TXT_MENU14_OPT1)"
        echo " $(T TXT_MENU14_OPT2)"
        echo " $(T TXT_MENU14_OPT3)"
        echo " $(T TXT_MENU14_OPT4)"
        echo " 0. $(T TXT_BACK)"
        print_line "="
        printf '%s' "$(T TXT_CHOICE) "
        read -r _c || return 0
        case "$_c" in
            1) run_health_check ;;
            2) clear; run_opkg_update ;;
            3) dns_management_menu ;;
            4) clear; check_keenetic_components
               # Eksik opsiyonel paketleri tespit et ve kur
               _fix_missing=""
               opkg list-installed 2>/dev/null | grep -q '^wget-ssl' || _fix_missing="$_fix_missing wget-ssl"
               opkg list-installed 2>/dev/null | grep -q '^coreutils-sort' || _fix_missing="$_fix_missing coreutils-sort"
               command -v grep >/dev/null 2>&1 || _fix_missing="$_fix_missing grep"
               command -v gzip >/dev/null 2>&1 || _fix_missing="$_fix_missing gzip"
               { command -v crond >/dev/null 2>&1 || command -v cron >/dev/null 2>&1; } || _fix_missing="$_fix_missing cron"
               if [ -n "$_fix_missing" ]; then
                   echo ""
                   printf "%s" "$(T _ 'Eksik paketleri kurmak ister misiniz? (e/h): ' 'Install missing packages? (y/n): ')"
                   read -r _fix_ans </dev/tty
                   if echo "$_fix_ans" | grep -qi '^[ey]'; then
                       opkg update >/dev/null 2>&1
                       opkg install $_fix_missing >/dev/null 2>&1 && \
                           print_status PASS "$(T _ 'Paketler kuruldu.' 'Packages installed.')" || \
                           print_status WARN "$(T _ 'Kurulum basarisiz. Internet baglantisini kontrol edin.' 'Installation failed. Check internet connection.')"
                   fi
               fi
               press_enter_to_continue ;;
            0) return 0 ;;
            *) print_status WARN "$(T TXT_INVALID_CHOICE)"; sleep 1 ;;
        esac
    done
}
# --- SAGLIK KONTROLU (HEALTH CHECK) ---
run_health_check() {
    clear
    printf "\n %b%s%b\n" "${CLR_CYAN}" "$(T TXT_HEALTH_TITLE)" "${CLR_RESET}"
    print_line "="
    local HC_NET="/tmp/healthcheck_net.$$"
    local HC_SYS="/tmp/healthcheck_sys.$$"
    local HC_SVC="/tmp/healthcheck_svc.$$"
    : > "$HC_NET"; : > "$HC_SYS"; : > "$HC_SVC"
    local total_n=0 pass_n=0 warn_n=0 fail_n=0 info_n=0
    add_line() {
        local file="$1" label="$2" value="$3" status="$4"
        printf " %-35s : %s%s\n" "$label" "$(hc_word "$status")" "$value" >> "$file"
        total_n=$((total_n+1))
        case "$status" in
            PASS) pass_n=$((pass_n+1)) ;;
            WARN) warn_n=$((warn_n+1)) ;;
            FAIL) fail_n=$((fail_n+1)) ;;
            INFO) info_n=$((info_n+1)) ;;
        esac
    }
    # ----------------------------
    # WAN STATUS (counts as a check)
    # ----------------------------
    local WAN_IF=""
    WAN_IF="$(get_wan_if 2>/dev/null)"
    [ -z "$WAN_IF" ] && WAN_IF="$(healthmon_detect_wan_iface_ndm 2>/dev/null)"
    [ -z "$WAN_IF" ] && WAN_IF="PPPoE0"
    local wan_link="" wan_conn="" wan_state=""
    wan_link="$(hm_ndmc_cmd "show interface $WAN_IF" 2>/dev/null | awk '/^[ \t]*link:/ {print $2; exit}')"
    wan_conn="$(hm_ndmc_cmd "show interface $WAN_IF" 2>/dev/null | awk '/^[ \t]*connected:/ {print $2; exit}')"
    if [ -z "$wan_link" ] && [ -z "$wan_conn" ]; then
        # fallback (best-effort)
        if ip link show "$WAN_IF" >/dev/null 2>&1; then
            wan_link="up"
            wan_conn="yes"
        else
            wan_link="down"
            wan_conn="no"
        fi
    fi
    if [ "$wan_link" = "up" ] && [ "$wan_conn" = "yes" ]; then
        wan_state="PASS"
    else
        wan_state="FAIL"
    fi
    add_line "$HC_NET" "$(T TXT_HEALTH_WAN_STATUS)" " ($WAN_IF)" "$wan_state"
    # WAN IP adresleri
    local wan_ipv4 wan_ipv6 wan_ip_type wan_ip_label
    wan_ipv4="$(ip -4 addr show "$WAN_IF" 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)"
    wan_ipv6="$(ip -6 addr show "$WAN_IF" 2>/dev/null | awk '/inet6 / && !/fe80/{print $2; exit}' | cut -d/ -f1)"
    if [ -n "$wan_ipv4" ]; then
        wan_ip_type="$(kzm2_classify_ip "$wan_ipv4")"
        case "$wan_ip_type" in
            cgnat)   wan_ip_label=" ${CLR_YELLOW}[CGNAT]${CLR_RESET}" ;;
            private) wan_ip_label=" ${CLR_ORANGE}[NAT]${CLR_RESET}" ;;
            *)       wan_ip_label=" ${CLR_GREEN}[Public]${CLR_RESET}" ;;
        esac
        add_line "$HC_NET" "$(T TXT_HEALTH_WAN_IPV4)" " ${wan_ipv4}${wan_ip_label}" "INFO"
    fi
    [ -n "$wan_ipv6" ] && add_line "$HC_NET" "$(T TXT_HEALTH_WAN_IPV6)" " ${wan_ipv6}" "INFO"
    # ----------------------------
    # DNS MODE / SECURITY / PROVIDERS (meta lines, NOT counted)
    # ----------------------------
    local doh_list dot_list dot_on dns_mode dns_sec dns_providers
    doh_list="$(ps w 2>/dev/null | awk '
        /https_dns_proxy/ && !/awk/{
          r=""
          for(i=1;i<=NF;i++) if($i=="-r") r=$(i+1)
          if(r!=""){
            gsub(/^https:\/\//,"",r); gsub(/\/.*$/,"",r)
            print r
          }
        }' | sort -u 2>/dev/null | tr "\n" "," | sed 's/,$//')"
    # Keenetic dns-proxy'den tum saglayicilari oku
    local _dns_proxy_raw
    _dns_proxy_raw="$(LD_LIBRARY_PATH= ndmc -c 'show dns-proxy' 2>/dev/null)"
    # dns_server satirlarindan @sonrasi SNI al (dnsm ve bos haric)
    local _dot_providers
    _dot_providers="$(printf '%s\n' "$_dns_proxy_raw" | grep 'dns_server.*@' | \
        sed 's/.*@//' | sed 's/[[:space:]].*//' | grep -v '^dnsm$' | grep -v '^$' | sort -u)"
    # server-https uri'lerinden domain al
    local _doh_providers
    _doh_providers="$(printf '%s\n' "$_dns_proxy_raw" | grep 'uri:' | \
        sed 's|.*https://||' | grep -v '^$' | sort -u)"
    # Ikisini birlestir ve tekrarlananlar temizle
    dot_list="$(printf '%s\n%s\n' "$_dot_providers" "$_doh_providers" | \
        sed '/^$/d' | sort -u | tr '\n' ',' | sed 's/,$//')"
    if netstat -lntp 2>/dev/null | grep -qE ':[[:space:]]*853[[:space:]]'; then
        dot_on="1"
    else
        dot_on="0"
    fi
    # Tum saglayicilari birlestir (https_dns_proxy + dns-proxy)
    local all_providers=""
    [ -n "$doh_list" ] && all_providers="$doh_list"
    if [ -n "$dot_list" ]; then
        if [ -n "$all_providers" ]; then
            all_providers="${all_providers},${dot_list}"
        else
            all_providers="$dot_list"
        fi
    fi
    all_providers="$(printf '%s\n' "$all_providers" | tr ',' '\n' | sed '/^$/d' | sort -u | tr '\n' ',' | sed 's/,$//')"
    if [ -n "$doh_list" ] && [ "$dot_on" = "1" ]; then
        dns_mode="$(T TXT_DNS_MODE_MIXED)"
    elif [ -n "$doh_list" ]; then
        dns_mode="$(T TXT_DNS_MODE_DOH)"
    elif [ "$dot_on" = "1" ]; then
        dns_mode="$(T TXT_DNS_MODE_DOT)"
    else
        dns_mode="$(T TXT_DNS_MODE_PLAIN)"
    fi
    if [ -n "$doh_list" ] || [ "$dot_on" = "1" ]; then
        dns_sec="$(T TXT_DNS_SEC_HIGH)"
    else
        dns_sec="$(T TXT_DNS_SEC_LOW)"
    fi
    dns_providers="${all_providers:-unknown}"
    if [ -n "$all_providers" ]; then
        dns_providers="$(printf '%s\n' "$all_providers" | tr ',' '\n' | sed '/^$/d' | head -n 8 | tr '\n' ',' | sed 's/,$//')"
    fi
    # DNS checks (existing behavior)
    local dns_local_ok="PASS"
    if check_dns_local; then
        dns_local_ok="PASS"
    else
        dns_local_ok="FAIL"
    fi
    local dns_8888_ok="PASS"
    if check_dns_external; then
        dns_8888_ok="PASS"
    else
        dns_8888_ok="FAIL"
    fi
    local dns_cons_ok="INFO"
    local dns_cons_msg="($(T TXT_HEALTH_DNS_MATCH_NOTE))"
    if check_dns_consistency; then
        dns_cons_ok="PASS"
        dns_cons_msg=""
    fi
    local route_ok="PASS"
    local route_msg="($(ip route | awk '/default/ {print $3; exit}'))"
    if [ -z "$route_msg" ] || [ "$route_msg" = "()" ]; then
        route_ok="FAIL"
        route_msg="(yok)"
    fi
    local script_ok="PASS"
    local SCRIPT_PATH_EXPECTED="/opt/lib/opkg/keenetic_zapret2_manager.sh"
    local SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
    local script_msg="(${SCRIPT_PATH})"
    if [ "$SCRIPT_PATH" != "$SCRIPT_PATH_EXPECTED" ]; then
        script_ok="WARN"
        script_msg="(Beklenen: ${SCRIPT_PATH_EXPECTED} | Su an: ${SCRIPT_PATH})"
    fi
    local ping_ok="PASS"
    local ping_msg=""
    if ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
        ping_ok="PASS"
    else
        ping_ok="FAIL"
        ping_msg="(ping 1.1.1.1)"
    fi
    local ram_ok="PASS"
    local ram_avail_kb="$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')"
    local ram_avail_mb="$((ram_avail_kb/1024))"
    local ram_msg="(~${ram_avail_mb}MB)"
    if [ "$ram_avail_mb" -lt 100 ]; then
        ram_ok="WARN"
    fi
    local load_ok="PASS"
    local load_val load_val5 load_val15
    read -r load_val load_val5 load_val15 _ < /proc/loadavg 2>/dev/null
    local load_nproc="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)"
    [ -z "$load_nproc" ] || [ "$load_nproc" -eq 0 ] 2>/dev/null && load_nproc=1
    if awk -v l="$load_val" -v n="$load_nproc" 'BEGIN{exit (l>=n)?0:1}'; then
        load_ok="WARN"
    elif awk -v l="$load_val" -v n="$load_nproc" 'BEGIN{exit (l>=n*0.7)?0:1}'; then
        load_ok="WARN"
    fi
    # nproc bazli renk
    _lv_color() {
        local _v="$1" _n="$load_nproc" _c
        local _warn_t
        _warn_t="$(awk -v n="$_n" 'BEGIN{printf "%.2f", n*0.7}')"
        if awk -v v="$_v" -v n="$_n" 'BEGIN{exit (v+0>=n+0)?0:1}'; then
            _c="${CLR_RED}"
        elif awk -v v="$_v" -v t="$_warn_t" 'BEGIN{exit (v+0>=t+0)?0:1}'; then
            _c="${CLR_YELLOW}"
        else
            _c="${CLR_GREEN}"
        fi
        printf "%b%s%b" "$_c" "$_v" "${CLR_RESET}"
    }
    local _lv1 _lv5 _lv15
    _lv1="$(_lv_color "$load_val")"
    _lv5="$(_lv_color "$load_val5")"
    _lv15="$(_lv_color "$load_val15")"
    local load_msg="$(T _ '1dk' '1min'): $_lv1 | $(T _ '5dk' '5min'): $_lv5 | $(T _ '15dk' '15min'): $_lv15  ($(T _ 'Esik' 'Threshold'): ${CLR_CYAN}${load_nproc}${CLR_RESET} CPU $(T _ 'OS gorunen' 'OS visible'))"
    # CPU sicakligi
    local temp_ok="INFO" temp_val="" temp_msg="—"
    for _tf in /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$_tf" ] || continue
        _tv="$(cat "$_tf" 2>/dev/null)"
        if [ -n "$_tv" ]; then
            temp_val="$(awk -v t="$_tv" 'BEGIN{printf "%.0f", t/1000}')"
            break
        fi
    done
    [ -n "$temp_val" ] && temp_msg="$temp_val $(T _ 'Santigrat Derece' 'Degrees Celsius')"
    local ntp_ok="PASS"
    local ntp_msg="($(date '+%Y-%m-%d %H:%M:%S'))"
    if ! check_ntp; then
        ntp_ok="WARN"
    fi
    local gh_ok="PASS"
    local gh_msg="(HTTP 200)"
    if ! check_github; then
        gh_ok="WARN"
        gh_msg="(fail)"
    fi
    local opkg_ok="PASS"
    if ! check_opkg; then opkg_ok="WARN"; fi
    local disk_ok="PASS"
    local disk_pct="$(healthmon_disk_used_pct /opt)"
    local disk_free="$(df -k /opt 2>/dev/null | awk 'NR==2 {print $4}')"
    local disk_free_mb="$((disk_free/1024))"
    local _dopt_used _dopt_total_kb _dopt_total
    _dopt_used="$(df -k /opt 2>/dev/null | awk 'NR==2 {printf "%d", $3/1024}')"
    _dopt_total_kb="$(df -k /opt 2>/dev/null | awk 'NR==2 {print $2}')"
    if [ "${_dopt_total_kb:-0}" -ge 1048576 ] 2>/dev/null; then
        _dopt_total="$(awk -v v="$_dopt_total_kb" 'BEGIN{printf "%.1fGB", v/1048576}')"
    else
        _dopt_total="$(awk -v v="$_dopt_total_kb" 'BEGIN{printf "%.1fMB", v/1024}')"
    fi
    local disk_msg="${_dopt_used}MB / ${_dopt_total} (${disk_pct}%)"
    if [ "$disk_pct" != "<1" ] && [ -n "$disk_pct" ] && [ "$disk_pct" -gt 90 ] 2>/dev/null; then
        disk_ok="WARN"
    fi
    # /opt disk sagligi: ortak helper ile kontrol
    local disk_health_ok="PASS" disk_health_msg
    kzm2_disk_health_check
    disk_health_ok="$_dh_status"
    case "$_dh_reason" in
        ro)             disk_health_msg="$(T TXT_HEALTH_DISK_RO)" ;;
        io_error)       disk_health_msg="$(T TXT_HEALTH_DISK_IO_ERR)" ;;
        journal_error)  disk_health_msg="$(T TXT_HEALTH_DISK_JOURNAL)" ;;
        usb_disconnect) disk_health_msg="$(T TXT_HEALTH_DISK_USBDISCON)" ;;
        usb_proto)      disk_health_msg="$(T TXT_HEALTH_DISK_USBPROTO)" ;;
        *)              disk_health_msg="$(T TXT_HEALTH_DISK_OK)" ;;
    esac
    # RAM detay
    local ram_total_kb ram_free_kb ram_used_kb ram_buf_kb
    ram_total_kb="$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')"
    ram_free_kb="$(grep '^MemFree:' /proc/meminfo 2>/dev/null | awk '{print $2}')"
    ram_buf_kb="$(grep '^Buffers:' /proc/meminfo 2>/dev/null | awk '{print $2}')"
    local ram_cached_kb
    ram_cached_kb="$(grep '^Cached:' /proc/meminfo 2>/dev/null | awk '{print $2}' | head -1)"
    ram_used_kb=$(( ram_total_kb - ram_avail_kb ))
    local ram_total_mb=$(( ram_total_kb / 1024 ))
    local ram_used_mb2=$(( ram_used_kb / 1024 ))
    local ram_buf_mb=$(( (ram_buf_kb + ram_cached_kb) / 1024 ))
    local ram_detail_msg="${ram_used_mb2}MB / ${ram_avail_mb}MB $(T _ 'bos' 'free') / ${ram_total_mb}MB $(T _ 'toplam' 'total')"
    # Swap
    local swap_total_kb swap_free_kb swap_used_kb swap_msg swap_ok="PASS"
    swap_total_kb="$(grep SwapTotal /proc/meminfo 2>/dev/null | awk '{print $2}')"
    swap_free_kb="$(grep SwapFree /proc/meminfo 2>/dev/null | awk '{print $2}')"
    swap_used_kb=$(( swap_total_kb - swap_free_kb ))
    local swap_total_mb=$(( swap_total_kb / 1024 ))
    local swap_used_mb=$(( swap_used_kb / 1024 ))
    swap_msg="${swap_used_mb}MB / ${swap_total_mb}MB"
    # Disk /tmp
    local disk_tmp_pct disk_tmp_free disk_tmp_free_mb disk_tmp_ok="PASS"
    disk_tmp_pct="$(df -k /tmp 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
    disk_tmp_free="$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $4}')"
    disk_tmp_free_mb=$(( ${disk_tmp_free:-0} / 1024 ))
    [ -n "$disk_tmp_pct" ] && [ "$disk_tmp_pct" -gt 90 ] 2>/dev/null && disk_tmp_ok="WARN"
    local _dt_used _dt_total_kb _dt_total
    _dt_used="$(df -k /tmp 2>/dev/null | awk 'NR==2 {printf "%d", $3/1024}')"
    _dt_total_kb="$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $2}')"
    if [ "${_dt_total_kb:-0}" -ge 1048576 ] 2>/dev/null; then
        _dt_total="$(awk -v v="$_dt_total_kb" 'BEGIN{printf "%.1fGB", v/1048576}')"
    else
        _dt_total="$(awk -v v="$_dt_total_kb" 'BEGIN{printf "%.1fMB", v/1024}')"
    fi
    local disk_tmp_msg="${_dt_used}MB / ${_dt_total} (${disk_tmp_pct:-?}%)"
    # LAN IP
    local lan_ip lan_ip_msg="—"
    lan_ip="$(ip -4 addr show br0 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)"
    [ -z "$lan_ip" ] && lan_ip="$(ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)"
    [ -n "$lan_ip" ] && lan_ip_msg="$lan_ip"
    # Entware /opt
    local entware_ok="PASS" entware_msg
    if [ -f /opt/bin/opkg ] || [ -d /opt/etc ]; then
        entware_msg="$(T _ 'Kurulu' 'Installed') (/opt)"
    else
        entware_ok="FAIL"
        entware_msg="$(T _ 'Bulunamadi' 'Not found')"
    fi
    # curl
    local curl_ok="PASS" curl_msg
    if command -v curl >/dev/null 2>&1; then
        if curl --version >/dev/null 2>&1; then
            curl_msg="$(T _ 'Kurulu' 'Installed') ($(command -v curl))"
        else
            curl_ok="FAIL"
            curl_msg="$(T _ 'Binary var ama calismiyor - eksik kutuphane olabilir (opkg install libnghttp2)' 'Binary exists but fails to run - missing library (opkg install libnghttp2)')"
        fi
    else
        curl_ok="WARN"
        curl_msg="$(T _ 'Bulunamadi' 'Not found')"
    fi
    # lighttpd / Web Panel
    local lighttpd_ok="INFO" lighttpd_msg
    if pgrep lighttpd >/dev/null 2>&1; then
        lighttpd_ok="PASS"
        lighttpd_msg="$(T _ 'Calisiyor' 'Running') ($(pgrep lighttpd | head -1))"
    elif command -v lighttpd >/dev/null 2>&1; then
        lighttpd_ok="WARN"
        lighttpd_msg="$(T _ 'Kurulu ama calismiyor' 'Installed but not running')"
    else
        lighttpd_msg="$(T _ 'Kurulu degil' 'Not installed')"
    fi
    # HealthMon
    local hm_ok="INFO" hm_msg
    healthmon_load_config 2>/dev/null
    if healthmon_is_running 2>/dev/null; then
        hm_ok="PASS"
        hm_msg="$(T _ 'Calisiyor' 'Running') (PID: $(cat /tmp/kzm2_healthmon.pid 2>/dev/null))"
    elif [ "${HM_ENABLE:-0}" = "1" ]; then
        hm_ok="WARN"
        hm_msg="$(T _ 'Acik ama calismiyor' 'Enabled but not running')"
    else
        hm_msg="$(T _ 'Kapali' 'Disabled')"
    fi
    # Telegram Bot
    local tgbot_ok="INFO" tgbot_msg
    local _tg_en
    _tg_en="$(grep -s '^TG_BOT_ENABLE=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')"
    if [ -f /tmp/kzm2_telegram_bot.pid ] && kill -0 "$(cat /tmp/kzm2_telegram_bot.pid 2>/dev/null)" 2>/dev/null; then
        tgbot_ok="PASS"
        tgbot_msg="$(T _ 'Calisiyor' 'Running') (PID: $(cat /tmp/kzm2_telegram_bot.pid 2>/dev/null))"
    elif [ "$_tg_en" = "1" ]; then
        tgbot_ok="WARN"
        tgbot_msg="$(T _ 'Acik ama calismiyor' 'Enabled but not running')"
    else
        tgbot_msg="$(T _ 'Kapali / Yapilandirilmamis' 'Disabled / Not configured')"
    fi
    local zap_ok="PASS"
    if ! is_zapret2_running; then zap_ok="FAIL"; fi
    # ----------------------------
    # SECTION: Network & DNS
    # ----------------------------
    # meta lines first (not counted)
    printf " %-35s : %s\n" "$(T TXT_HEALTH_DNS_MODE)" "$dns_mode" >> "$HC_NET"
    printf " %-35s : %s\n" "$(T TXT_HEALTH_DNS_SEC)" "$dns_sec" >> "$HC_NET"
    # DNS Saglayicilar: uzun olabilir, terminal genisligine gore sardir
    {
        _dns_lbl="$(T TXT_HEALTH_DNS_PROVIDERS)"
        _dns_tw="$(tput cols 2>/dev/null)"
        [ -z "$_dns_tw" ] || [ "$_dns_tw" -lt 40 ] 2>/dev/null && _dns_tw="${COLUMNS:-120}"
        _dns_avail=$(( _dns_tw - 39 ))
        [ "$_dns_avail" -lt 20 ] && _dns_avail=40
        _dns_ind="$(printf '%*s' 39 '')"
        printf '%s' "$dns_providers" | awk -v avail="$_dns_avail" -v lbl="$_dns_lbl" -v ind="$_dns_ind" '
        BEGIN { RS=","; cur=""; first=1 }
        { item=$0; gsub(/[[:space:]]/,"",item); if (!item) next
          t=(cur==""?item:cur","item)
          if (length(t)<=avail) { cur=t }
          else {
            if (cur!="") {
              if (first) { printf " %-35s : %s\n",lbl,cur; first=0 }
              else printf "%s%s\n",ind,cur
            }
            cur=item
          }
        }
        END { if (cur!="") { if (first) printf " %-35s : %s\n",lbl,cur; else printf "%s%s\n",ind,cur } }
        '
    } >> "$HC_NET"
    add_line "$HC_NET" "$(T TXT_HEALTH_DNS_LOCAL)" "" "$dns_local_ok"
    add_line "$HC_NET" "$(T TXT_HEALTH_DNS_PUBLIC)" "" "$dns_8888_ok"
    add_line "$HC_NET" "$(T TXT_HEALTH_DNS_MATCH)" " $dns_cons_msg" "$dns_cons_ok"
    # ISP DNS kontrolu
    _isp_dns_check="$(LD_LIBRARY_PATH= ndmc -c 'show ip name-server' 2>/dev/null | awk '/address:/{print $2}' | tr '\n' ' ' | sed 's/ $//;s/ / - /g')"
    if [ -n "$_isp_dns_check" ]; then
        add_line "$HC_NET" "$(T _ 'ISP DNS' 'ISP DNS')" " ($_isp_dns_check) - $(T _ 'Zapret2 bypass engellenebilir' 'Zapret2 bypass may be blocked')" "WARN"
    else
        add_line "$HC_NET" "$(T _ 'ISP DNS' 'ISP DNS')" " $(T _ 'Yok - DNS sifreleme aktif' 'None - DNS encryption active')" "PASS"
    fi
    add_line "$HC_NET" "$(T TXT_HEALTH_ROUTE)" " $route_msg" "$route_ok"
    add_line "$HC_NET" "$(T TXT_HEALTH_LAN_IP)" " $lan_ip_msg" "INFO"
    # ----------------------------
    # SECTION: System
    # ----------------------------
    add_line "$HC_SYS" "$(T TXT_HEALTH_SCRIPT_PATH)" " $script_msg" "$script_ok"
    add_line "$HC_SYS" "$(T TXT_HEALTH_PING)" " $ping_msg" "$ping_ok"
    add_line "$HC_SYS" "$(T TXT_HEALTH_RAM)" " $ram_msg" "$ram_ok"
    add_line "$HC_SYS" "$(T TXT_HEALTH_RAM_DETAIL)" " $ram_detail_msg" "INFO"
    add_line "$HC_SYS" "$(T TXT_HEALTH_RAM_BUFFER)" " ${ram_buf_mb}MB" "INFO"
    add_line "$HC_SYS" "$(T TXT_HEALTH_SWAP)" " $swap_msg" "$swap_ok"
    add_line "$HC_SYS" "$(T TXT_HEALTH_LOAD)" " $load_msg" "$load_ok"
    add_line "$HC_SYS" "$(T TXT_HEALTH_TEMP)" " $temp_msg" "$temp_ok"
    add_line "$HC_SYS" "$(T TXT_HEALTH_DISK)" " $disk_msg" "$disk_ok"
    add_line "$HC_SYS" "$(T TXT_HEALTH_DISK_HEALTH)" " $disk_health_msg" "$disk_health_ok"
    add_line "$HC_SYS" "$(T TXT_HEALTH_DISK_TMP)" " $disk_tmp_msg" "$disk_tmp_ok"
    add_line "$HC_SYS" "$(T TXT_HEALTH_TIME)" " $ntp_msg" "$ntp_ok"
    # ----------------------------
    # SECTION: Services
    # ----------------------------
    add_line "$HC_SVC" "$(T TXT_HEALTH_ENTWARE)" " $entware_msg" "$entware_ok"
    add_line "$HC_SVC" "$(T TXT_HEALTH_CURL)" " $curl_msg" "$curl_ok"
    add_line "$HC_SVC" "$(T TXT_HEALTH_LIGHTTPD)" " $lighttpd_msg" "$lighttpd_ok"
    add_line "$HC_SVC" "$(T TXT_HEALTH_HEALTHMON)" " $hm_msg" "$hm_ok"
    add_line "$HC_SVC" "$(T TXT_HEALTH_TGBOT)" " $tgbot_msg" "$tgbot_ok"
    add_line "$HC_SVC" "$(T TXT_HEALTH_GITHUB)" " $gh_msg" "$gh_ok"
    add_line "$HC_SVC" "$(T TXT_HEALTH_OPKG)" "" "$opkg_ok"
    add_line "$HC_SVC" "$(T TXT_HEALTH_ZAPRET)" "" "$zap_ok"
    # KeenDNS durumu (ndns varsa goster, yoksa INFO)
    local kdns_raw kdns_name kdns_domain kdns_access kdns_can_direct
    kdns_raw="$(LD_LIBRARY_PATH= ndmc -c 'show ndns' 2>/dev/null)"
    kdns_name="$(printf '%s\n' "$kdns_raw"   | awk '/^[[:space:]]*name:/   {print $2; exit}')"
    kdns_domain="$(printf '%s\n' "$kdns_raw" | awk '/^[[:space:]]*domain:/ {print $2; exit}')"
    kdns_access="$(printf '%s\n' "$kdns_raw" | awk '/^[[:space:]]*access:/ {print $2; exit}')"
    kdns_can_direct="$(printf '%s\n' "$kdns_raw" | awk '/^[[:space:]]*direct:/ {print $2; exit}')"
    if [ -z "$kdns_name" ]; then
        add_line "$HC_SVC" "KeenDNS" " ($(T TXT_KEENDNS_NONE))" "INFO"
    else
        local kdns_fqdn="${kdns_name}.${kdns_domain}"
        local kdns_dest kdns_port kdns_http_code kdns_reach
        kdns_dest="$(printf '%s\n' "$kdns_raw" | awk '/^[[:space:]]*destination:/ {print $2; exit}')"
        kdns_port="$(printf '%s\n' "$kdns_dest" | awk -F: '{print $NF}')"
        [ -z "$kdns_port" ] && kdns_port="443"
        [ "$kdns_port" = "443" ] && kdns_proto="https" || kdns_proto="http"
        kdns_http_code="$(curl -sk --max-time 5 -o /dev/null -w "%{http_code}"             "${kdns_proto}://${kdns_fqdn}:${kdns_port}" 2>/dev/null)"
        case "$kdns_http_code" in
            2*|3*|401|403) kdns_reach="yes" ;;
            *)             kdns_reach="no"  ;;
        esac
        if [ "$kdns_access" = "direct" ] && [ "$kdns_reach" = "no" ]; then
            # Direct modda curl basarisiz > gercek sorun
            add_line "$HC_SVC" "KeenDNS" " (${kdns_fqdn} - ${CLR_RED}$(T TXT_KEENDNS_UNKNOWN)${CLR_RESET})" "FAIL"
        elif [ "$kdns_access" = "direct" ]; then
            add_line "$HC_SVC" "KeenDNS" " (${kdns_fqdn} - ${CLR_GREEN}$(T TXT_KEENDNS_DIRECT)${CLR_RESET})" "PASS"
        elif [ "$kdns_can_direct" = "no" ]; then
            # CGN / direct imkansiz > cloud kritik, kaybederse erisim tamamen gider
            add_line "$HC_SVC" "KeenDNS" " (${kdns_fqdn} - ${CLR_YELLOW}$(T TXT_KEENDNS_CLOUD)${CLR_RESET})" "WARN"
        else
            # direct: yes ama henuz cloud > OTO gecis yapacak, gecici
            add_line "$HC_SVC" "KeenDNS" " (${kdns_fqdn} - ${CLR_YELLOW}$(T TXT_KEENDNS_CLOUD)${CLR_RESET})" "INFO"
        fi
    fi
    # ----------------------------
    # SHA256 DOSYA BUTUNLUGU (state dosyasindan, hizli)
    # ----------------------------
    local _sha_kzm _sha_zap _sha_kzm_status _sha_zap_status
    _sha_kzm="$(cat /opt/etc/kzm2_sha256_kzm.state 2>/dev/null)"
    _sha_zap="$(cat /opt/etc/kzm2_sha256_zapret.state 2>/dev/null)"
    case "$_sha_kzm" in
        ok)   _sha_kzm_status="PASS"; _sha_kzm_msg=" $(T TXT_HEALTH_SHA256_OK)" ;;
        fail) _sha_kzm_status="WARN"; _sha_kzm_msg=" $(T TXT_HEALTH_SHA256_FAIL)" ;;
        *)    _sha_kzm_status="INFO"; _sha_kzm_msg=" $(T TXT_HEALTH_SHA256_UNKNOWN)" ;;
    esac
    case "$_sha_zap" in
        ok)   _sha_zap_status="PASS"; _sha_zap_msg=" $(T TXT_HEALTH_SHA256_OK)" ;;
        fail) _sha_zap_status="WARN"; _sha_zap_msg=" $(T TXT_HEALTH_SHA256_FAIL)" ;;
        *)    _sha_zap_status="INFO"; _sha_zap_msg=" $(T TXT_HEALTH_SHA256_ZAP_UNKNOWN)" ;;
    esac
    add_line "$HC_SVC" "$(T TXT_HEALTH_SHA256_KZM)" "$_sha_kzm_msg" "$_sha_kzm_status"
    add_line "$HC_SVC" "$(T TXT_HEALTH_SHA256_ZAP)" "$_sha_zap_msg" "$_sha_zap_status"
    # ----------------------------
    # SCORE + SUMMARY
    # ----------------------------
    local ok_n=$((pass_n+info_n))
    local score rating_key rating_txt
    score="$(awk -v ok="$ok_n" -v total="$total_n" 'BEGIN{ if(total<=0){printf "0.0"} else {printf "%.1f", (ok/total)*10} }')"
    rating_key="TXT_HEALTH_RATING_OK"
    if awk -v s="$score" 'BEGIN{exit (s>=9.5)?0:1}'; then
        rating_key="TXT_HEALTH_RATING_EXCELLENT"
    elif awk -v s="$score" 'BEGIN{exit (s>=8.5)?0:1}'; then
        rating_key="TXT_HEALTH_RATING_GREAT"
    elif awk -v s="$score" 'BEGIN{exit (s>=7.0)?0:1}'; then
        rating_key="TXT_HEALTH_RATING_GOOD"
    elif awk -v s="$score" 'BEGIN{exit (s>=5.0)?0:1}'; then
        rating_key="TXT_HEALTH_RATING_OK"
    else
        rating_key="TXT_HEALTH_RATING_BAD"
    fi
    rating_txt="$(T "$rating_key")"
    # Skora gore renk ve etiket sec
    local score_clr score_emoji
    if awk -v s="$score" 'BEGIN{exit (s>=9.5)?0:1}'; then
        score_clr="${CLR_GREEN}"; score_emoji="MUKEMMEL"
    elif awk -v s="$score" 'BEGIN{exit (s>=8.5)?0:1}'; then
        score_clr="${CLR_GREEN}"; score_emoji="COK IYI"
    elif awk -v s="$score" 'BEGIN{exit (s>=7.0)?0:1}'; then
        score_clr="${CLR_ORANGE}"; score_emoji="IYI"
    elif awk -v s="$score" 'BEGIN{exit (s>=5.0)?0:1}'; then
        score_clr="${CLR_YELLOW}"; score_emoji="ORTA"
    else
        score_clr="${CLR_RED}"; score_emoji="KOTU"
    fi
    printf "\n %-35s : %b%b%s / 10%b  [%b%s%b]   %b(%d/%d OK)%b\n" \
        "$(T TXT_HEALTH_SCORE)" \
        "${CLR_BOLD}" "$score_clr" "$score" "${CLR_RESET}" \
        "${CLR_BOLD}${score_clr}" "$score_emoji" "${CLR_RESET}" \
        "${CLR_BOLD}${score_clr}" "$ok_n" "$total_n" "${CLR_RESET}"
    print_line "-"
    printf " %b%s%b\n" "${CLR_CYAN}" "$(T TXT_HEALTH_SECTION_NETDNS)" "${CLR_RESET}"
    print_line "-"
    cat "$HC_NET"
    print_line "-"
    printf " %b%s%b\n" "${CLR_CYAN}" "$(T TXT_HEALTH_SECTION_SYSTEM)" "${CLR_RESET}"
    print_line "-"
    cat "$HC_SYS"
    print_line "-"
    printf " %b%s%b\n" "${CLR_CYAN}" "$(T TXT_HEALTH_SECTION_SERVICES)" "${CLR_RESET}"
    print_line "-"
    cat "$HC_SVC"
    print_line "-"
    press_enter_to_continue
    rm -f "$HC_NET" "$HC_SYS" "$HC_SVC" 2>/dev/null
    clear
}
# --- BLOCKCHECK (DPI TEST) ---
run_blockcheck() {
    # $1 - scan level: 1=quick, 2=standard (default), 3=force
    local BLOCKCHECK="/opt/zapret2/blockcheck2.sh"
    local DEF_DOMAIN="pastebin.com"
    local domains report today was_running stop_ans do_stop stopped_by_us
    local hm_was_autorestart hm_pause_ans dns_check_ip hm_pause_done
    local _scan_level="${1:-2}"
    hm_was_autorestart=0
    hm_pause_done=0
    print_line "-"
    echo "$(T blk_title 'Blockcheck (DPI Test Raporu)' 'Blockcheck (DPI Test Report)')"
    print_line "-"
    if [ ! -x "$BLOCKCHECK" ]; then
        echo "$(T blk_missing 'HATA: /opt/zapret2/blockcheck2.sh bulunamadi veya calistirilabilir degil.' 'ERROR: /opt/zapret2/blockcheck2.sh not found or not executable.')"
        press_enter_to_continue
        clear
        return 1
    fi
    # Domain(ler)
    printf '%s' "$(T blk_domain 'Test edilecek domain(ler) (Enter=pastebin.com, 0=Iptal): ' 'Domain(s) to test (Enter=pastebin.com, 0=Cancel): ')"; read -r domains
    if [ "$domains" = "0" ]; then
        clear
        return 0
    fi
    [ -z "$domains" ] && domains="$DEF_DOMAIN"
	now="$(date +%Y%m%d%H%M 2>/dev/null)"
	[ -z "$now" ] && now="000000000000"
	report="/opt/zapret2/blockcheck_${now}.txt"
	LAST_BLOCKCHECK_REPORT="$report"
    # Zapret2 calisiyorsa blockcheck genelde "bypass kapali olmali" diye uyarir.
    was_running=0
    do_stop=0
    stopped_by_us=0
    if is_zapret2_running; then
        was_running=1
        echo "$(T blk_running 'Not: Blockcheck icin Zapret2 gecici olarak durduruluyor...' 'Note: Stopping Zapret2 temporarily for blockcheck...')"
        stop_zapret2 >/dev/null 2>&1
        stopped_by_us=1
        # nfqws2'nin gercekten olmesini bekle (blockcheck WARNING gostermemesi icin)
        local _wait=0
        while is_zapret2_running && [ "$_wait" -lt 5 ]; do
            sleep 1; _wait=$(( _wait + 1 ))
        done
        killall -9 nfqws2 2>/dev/null; sleep 1
    fi
    # HealthMon autorestart kontrolu
    healthmon_load_config 2>/dev/null
    if [ "${HM_ZAPRET_AUTORESTART:-0}" = "1" ]; then
        hm_was_autorestart=1
        HM_ZAPRET_AUTORESTART="0"
        healthmon_write_config 2>/dev/null
        hm_pause_done=1
        echo "$(T TXT_BLK_HM_AUTORESTART_PAUSED)"
    fi
    echo
    echo "$(T blk_running2 "Calistiriliyor... (Rapor: ${report})" "Running... (Report: ${report})")"
    print_line "-"
    # Zapret2 blockcheck2.sh interaktif akisi Zapret1'den farklidir.
    # stdin ile cevap sirasi kolayca kayar. Bu yuzden BATCH=1 kullanip
    # gerekli degiskenleri dogrudan veriyoruz:
    #   TEST=standard       -> blockcheck2.d/standard dizini
    #   DOMAINS="$domains"  -> kullanicinin sectigi domain
    #   IPVS=4              -> Keenetic/Turkiye icin varsayilan IPv4
    #   SCANLEVEL=quick     -> Ozet modunda kisa tarama
    #   SCANLEVEL=standard  -> Tam testte daha kapsamli tarama
    export SECURE_DNS=0
    export BATCH=1
    # Zapret2 tarafinda blockcheck2.d/quick dizini yok. Ozet modu icin
    # kendi dar test setimizi olusturuyoruz. Bu, standard dizininin tamamini
    # taramaz; sadece hizli sonuc veren temel adaylari calistirir.
    if [ "$_scan_level" = "1" ]; then
        _kzm_bc_dir="/opt/zapret2/blockcheck2.d/kzmquick"
        mkdir -p "$_kzm_bc_dir" 2>/dev/null
        rm -f "$_kzm_bc_dir"/*.sh 2>/dev/null
        # Zapret2 standard test scriptleri def.inc gibi ortak include dosyalari bekler.
        # kzmquick dizinine sadece .sh kopyalanirsa blockcheck2 yarida kesilir.
        for _bc_common in /opt/zapret2/blockcheck2.d/standard/*.inc /opt/zapret2/blockcheck2.d/standard/*.txt; do
            [ -f "$_bc_common" ] && cp -f "$_bc_common" "$_kzm_bc_dir/$(basename "$_bc_common")" 2>/dev/null
        done
        [ -f /opt/zapret2/blockcheck2.d/standard/10-http-basic.sh ] && cp -f /opt/zapret2/blockcheck2.d/standard/10-http-basic.sh "$_kzm_bc_dir/10-http-basic.sh" 2>/dev/null
        [ -f /opt/zapret2/blockcheck2.d/standard/20-multi.sh ] && cp -f /opt/zapret2/blockcheck2.d/standard/20-multi.sh "$_kzm_bc_dir/20-multi.sh" 2>/dev/null
        [ -f /opt/zapret2/blockcheck2.d/standard/25-fake.sh ] && cp -f /opt/zapret2/blockcheck2.d/standard/25-fake.sh "$_kzm_bc_dir/25-fake.sh" 2>/dev/null
        [ -f /opt/zapret2/blockcheck2.d/standard/90-quic.sh ] && cp -f /opt/zapret2/blockcheck2.d/standard/90-quic.sh "$_kzm_bc_dir/90-quic.sh" 2>/dev/null
        export TEST="kzmquick"
        export TEST_DEFAULT="kzmquick"
        export SCANLEVEL="quick"
    else
        export TEST="standard"
        export TEST_DEFAULT="standard"
        case "$_scan_level" in
            2) export SCANLEVEL="standard" ;;
            3) export SCANLEVEL="force" ;;
            *) export SCANLEVEL="standard" ;;
        esac
    fi
    export DOMAINS="$domains"
    export DOMAINS_DEFAULT="$domains"
    export IPVS="4"
    export REPEATS="1"
    export PARALLEL="0"
    export ENABLE_HTTP="1"
    export ENABLE_HTTPS_TLS12="1"
    export ENABLE_HTTPS_TLS13="0"
    # ENABLE_HTTP3 set edilmiyor -- blockcheck2 curl HTTP3 destegini kendisi kontrol eder (curl_supports_http3).
    # Her curl testi icin maximum sure (saniye). Set edilmezse blockcheck2 default'u
    # 15-30sn olabilir; engelli sitelerde 100+ kombinasyon x 20sn = saatler.
    export CURL_MAXTIME=8
    export TIMEOUT_CURL=8

    # BusyBox xargs bu router'da pipe icinde Illegal instruction verebildigi icin
    # PATH basina minimal xargs wrapper koyuyoruz.
    # Wrapper xargs flag'lerini (-n, -I, -P, -0 vb.) atlar; ilk non-flag argumani
    # komut olarak alir. "xargs cmd" ve "xargs -n1 cmd" desenlerini dogru karsilar.
    _xargs_wrap="/opt/etc/kzm_xargs_wrap.sh"
    {
        printf '%s\n' '#!/bin/sh'
        printf '%s\n' '# KZM2 xargs wrapper - BusyBox SIGILL workaround'
        printf '%s\n' '_cmd=""'
        printf '%s\n' 'for _a in "$@"; do'
        printf '%s\n' '    case "$_a" in'
        printf '%s\n' '        -n*|-I*|-P*|-0*|-d*|-r|-L*|-s*|-t) shift; continue ;;'
        printf '%s\n' '    esac'
        printf '%s\n' '    _cmd="$_a"; shift; break'
        printf '%s\n' 'done'
        printf '%s\n' 'if [ -z "$_cmd" ]; then'
        printf '%s\n' "    tr '\\n' ' ' | sed 's/^ *//;s/ *\$//'"
        printf '%s\n' '    exit 0'
        printf '%s\n' 'fi'
        printf '%s\n' 'while IFS= read -r _line || [ -n "$_line" ]; do'
        printf '%s\n' '    [ -n "$_line" ] && "$_cmd" "$@" $_line'
        printf '%s\n' 'done'
    } > "$_xargs_wrap"
    chmod +x "$_xargs_wrap"
    _kzm_path_dir="/tmp/kzm_path_$$"
    mkdir -p "$_kzm_path_dir"
    ln -sf "$_xargs_wrap" "$_kzm_path_dir/xargs"
    export PATH="$_kzm_path_dir:$PATH"

    # </dev/null: stdin kapatilir. BATCH=1 kapsamadigi read cagrilari sonsuza
    # beklemek yerine EOF alir ve atlanir. Full standard modunda kritik.
    if command -v tee >/dev/null 2>&1; then
        ( cd /opt/zapret2 && sh "$BLOCKCHECK" 2>&1 </dev/null ) | tee "$report"
    else
        ( cd /opt/zapret2 && sh "$BLOCKCHECK" >"$report" 2>&1 </dev/null )
        cat "$report" 2>/dev/null
    fi
    # Pipeline bittikten sonra askida kalan blockcheck alt processleri temizle.
    # Kullanici Ctrl+Z ile suspend edip geri donerse T-state processler
    # daha sonra start_zapret2 cagirarak zapret2'yi yeniden baslatabilir.
    killall blockcheck2.sh 2>/dev/null
    killall -KILL blockcheck2.sh 2>/dev/null

    unset SECURE_DNS BATCH TEST DOMAINS DOMAINS_DEFAULT IPVS TEST_DEFAULT REPEATS PARALLEL ENABLE_HTTP ENABLE_HTTPS_TLS12 ENABLE_HTTPS_TLS13 ENABLE_HTTP3 SCANLEVEL CURL_MAXTIME TIMEOUT_CURL
    export PATH="$(printf '%s' "$PATH" | sed "s|$_kzm_path_dir:||")"
    rm -rf "$_kzm_path_dir"
    print_line "-"
    echo "$(T blk_done "Bitti. Rapor dosyasi: ${report}" "Done. Report file: ${report}")"
    # HealthMon autorestart eski haline getir
    if [ "$hm_pause_done" -eq 1 ]; then
        HM_ZAPRET_AUTORESTART="$hm_was_autorestart"
        healthmon_write_config 2>/dev/null
        # Fallback: healthmon_write_config basarisizsa dogrudan sed ile duzelt
        if grep -q 'HM_ZAPRET_AUTORESTART="0"' /opt/etc/healthmon.conf 2>/dev/null; then
            sed -i 's/HM_ZAPRET_AUTORESTART="0"/HM_ZAPRET_AUTORESTART="1"/' /opt/etc/healthmon.conf 2>/dev/null
        fi
        echo "$(T TXT_BLK_HM_AUTORESTART_RESTORED)"
    fi
    # Pause flag her durumda kaldirilmali (HealthMon tekrar devreye girebilsin)
    zapret_resume 2>/dev/null
    # Daha once calisiyorduysa ve biz durdurduysak geri ac
    if [ "$was_running" -eq 1 ] && [ "$stopped_by_us" -eq 1 ]; then
        echo "$(T blk_restarting 'Zapret2 tekrar baslatiliyor...' 'Starting Zapret2 again...')"
        start_zapret2 >/dev/null 2>&1
        if is_zapret2_running; then
            echo "$(T blk_started 'Zapret2 tekrar baslatildi.' 'Zapret2 started again.')"
        else
            echo "$(T blk_startfail 'UYARI: Zapret2 tekrar baslatilamadi. Elle baslatmaniz gerekebilir.' 'WARNING: Could not restart Zapret2. You may need to start it manually.')"
        fi
    fi
    press_enter_to_continue
    clear
    return 0
}
run_blockcheck_save_summary() {
    # Run the full interactive test exactly like "Tam Test", then save only * SUMMARY * to a separate file.
    run_blockcheck 1
    local src_report ts summary_file
    src_report="${LAST_BLOCKCHECK_REPORT}"
    if [ -z "$src_report" ] || [ ! -f "$src_report" ]; then
        src_report="$(ls -1t /opt/zapret2/blockcheck_[0-9]*.txt 2>/dev/null | head -n 1)"
    # Guard: avoid using an already-summarized file as the source report
    case "$src_report" in
        */blockcheck_summary_*.txt)
            src_report="$(ls -1t /opt/zapret2/blockcheck_[0-9]*.txt 2>/dev/null | head -n 1)"
        ;;
    esac
    fi
    if [ -z "$src_report" ] || [ ! -f "$src_report" ]; then
        echo "$(T TXT_BLOCKCHECK_SUMMARY_NOT_FOUND)"
        press_enter_to_continue
        return 1
    fi
    ts="$(date +%Y%m%d%H%M%S 2>/dev/null)"
    [ -z "$ts" ] && ts="$(date +%Y%m%d%H%M%S)"
    summary_file="/opt/zapret2/blockcheck_summary_${ts}.txt"
# Build a compact summary file:
# 1) Keep the last "working strategy found ..." line (if any)
# 2) Append the * SUMMARY section (if present)
: > "$summary_file" 2>/dev/null || true
# Find the LAST "working strategy found" line (prefer the one before "clearing nfqws redirection" when possible)
clear_ln="$(grep -ni 'clearing nfqws redirection' "$src_report" 2>/dev/null | tail -n 1 | cut -d: -f1)"
ws_ln="0"
if [ -n "$clear_ln" ] && [ "$clear_ln" -gt 1 ] 2>/dev/null; then
    ws_ln="$(sed -n "1,$((clear_ln-1))p" "$src_report" 2>/dev/null | grep -ni 'working strategy found' | tail -n 1 | cut -d: -f1)"
else
    ws_ln="$(grep -ni 'working strategy found' "$src_report" 2>/dev/null | tail -n 1 | cut -d: -f1)"
fi
if [ -n "$ws_ln" ] && [ "$ws_ln" -gt 0 ] 2>/dev/null; then
    ws_line="$(sed -n "${ws_ln}p" "$src_report" 2>/dev/null)"
    [ -n "$ws_line" ] && printf "%s
" "$ws_line" >> "$summary_file"
fi
sum_ln="$(grep -ni '^\* SUMMARY' "$src_report" 2>/dev/null | tail -n 1 | cut -d: -f1)"
if [ -n "$sum_ln" ] && [ "$sum_ln" -gt 0 ] 2>/dev/null; then
    # Blockcheck'in buldugu ilk calisani kullan — ip_ttl=2 tercih etme.
    # Diger ISP'lerde (Superonline, Turkcell vb.) farkli strateji dogru olabilir.
    _s_http="$(sed -n "${sum_ln},\$p" "$src_report" 2>/dev/null | \
        grep -i '^curl_test_http ' | grep 'nfqws2' | head -n1)"

    _s_tls="$(sed -n "${sum_ln},\$p" "$src_report" 2>/dev/null | \
        grep -i '^curl_test_https_tls12 ' | grep 'nfqws2' | head -n1)"
    [ -z "$_s_tls" ] && _s_tls="$(sed -n "${sum_ln},\$p" "$src_report" 2>/dev/null | \
        grep -i '^curl_test_https_tls13 ' | grep 'nfqws2' | head -n1)"

    _s_quic="$(sed -n "${sum_ln},\$p" "$src_report" 2>/dev/null | \
        grep -Ei '^(curl_test_http3|curl_test_quic|curl_test_udp)' | \
        grep 'nfqws2' | head -n1)"

    {
        printf '* SUMMARY\n'
        [ -n "$_s_http" ] && printf '%s\n' "$_s_http"
        [ -n "$_s_tls" ] && printf '%s\n' "$_s_tls"
        [ -n "$_s_quic" ] && printf '%s\n' "$_s_quic"
        printf '\nPlease note this SUMMARY does not guarantee a magic pill for you to copy/paste and be happy.\n'
    } >> "$summary_file"
fi
if [ ! -s "$summary_file" ]; then
    # Zapret2 kisa/custom testlerde her zaman * SUMMARY uretmez.
    # Bu durumda "!!!!! AVAILABLE !!!!!" onceki nfqws2 satiri ile eslestirilir.
    _avail_line="$(awk '
        /: nfqws2 / { last=$0 }
        /!!!!! AVAILABLE !!!!!/ { if (last != "") { print last; exit } }
    ' "$src_report" 2>/dev/null)"
    if [ -n "$_avail_line" ]; then
        printf "* SUMMARY\n" > "$summary_file"
        printf "%s : working strategy found\n" "$_avail_line" >> "$summary_file"
    else
        echo "$(T TXT_BLOCKCHECK_SUMMARY_NOT_FOUND)" > "$summary_file"
    fi
fi
    # Optional: extract nfqws parameters from the summary and apply as special DPI profile "blockcheck_auto"
    local chosen_line raw_params params_filtered ans
    chosen_line=""
    # Prefer the "working strategy found ..." line if it contains nfqws/tpws
    chosen_line="$(grep -i 'working strategy found' "$summary_file" 2>/dev/null | tail -n 1)"
    if [ -z "$chosen_line" ]; then
        # Fall back to * SUMMARY block candidates (prefer https_tls12, then tls13, then http)
        chosen_line="$(grep -i 'curl_test_https_tls12' "$summary_file" 2>/dev/null | grep -Ei ' nfqws2? ' | grep -i -- '--lua-desync=' | tail -n 1)"
        [ -z "$chosen_line" ] && chosen_line="$(grep -i 'curl_test_https_tls13' "$summary_file" 2>/dev/null | grep -Ei ' nfqws2? ' | grep -i -- '--lua-desync=' | tail -n 1)"
        [ -z "$chosen_line" ] && chosen_line="$(grep -i 'curl_test_http' "$summary_file" 2>/dev/null | grep -Ei ' nfqws2? ' | grep -i -- '--lua-desync=' | tail -n 1)"
        [ -z "$chosen_line" ] && chosen_line="$(awk '
            /: nfqws2 / { last=$0 }
            /!!!!! AVAILABLE !!!!!/ { if (last != "") { print last " : working strategy found"; exit } }
        ' "$src_report" 2>/dev/null)"
    fi
    if echo "$chosen_line" | grep -qi ': *tpws '; then
        # For safety, we do not auto-apply tpws yet.
        echo "$(T blockcheck_tpws_warn "$TXT_BLOCKCHECK_TPWS_WARN_TR" "$TXT_BLOCKCHECK_TPWS_WARN_EN")"
    elif echo "$chosen_line" | grep -Eqi ': *nfqws2? '; then
        raw_params="$(echo "$chosen_line" | sed -n 's/^.*:[[:space:]]*nfqws2\{0,1\}[[:space:]]*//p' | sed 's/!//g; s/[[:space:]]\+$//')"
        # Keep only safe nfqws flags we support writing (avoid accidental config corruption)
        params_filtered=""
        for tok in $raw_params; do
            case "$tok" in
                --lua-desync=*|--payload=*|--in-range=*|--out-range=*|--filter-l7=*|--new)
                    params_filtered="${params_filtered} ${tok}"
                ;;
            esac
        done
        params_filtered="$(echo "$params_filtered" | sed 's/^ *//; s/ *$//')"
        # Zapret2 SUMMARY can contain many successful single-test strategies.
        # KZM2 must apply ONLY what Blockcheck really found for protocol blocks:
        #   - HTTP only if SUMMARY has HTTP
        #   - TLS only if SUMMARY has TLS
        #   - QUIC/UDP only if SUMMARY has QUIC/UDP
        # IPv6 is controlled separately by Menu 7 via DISABLE_IPV6 in config.
        # If Menu 7 IPv6 is ON, add ip6_ttl to found HTTP/TLS/QUIC blocks.
        local _bc_http _bc_tls _bc_quic _bc_combined _bc_ipv6
        _bc_http="$(grep -i '^curl_test_http ' "$summary_file" 2>/dev/null | grep -F -- '--payload=http_req' | head -n 1 | sed -n 's/^.* : nfqws2[[:space:]]*//p')"
        _bc_tls="$(grep -i '^curl_test_https_tls12 ' "$summary_file" 2>/dev/null | grep -F -- '--payload=tls_client_hello' | head -n 1 | sed -n 's/^.* : nfqws2[[:space:]]*//p')"
        [ -z "$_bc_tls" ] && _bc_tls="$(grep -i '^curl_test_https_tls13 ' "$summary_file" 2>/dev/null | grep -F -- '--payload=tls_client_hello' | head -n 1 | sed -n 's/^.* : nfqws2[[:space:]]*//p')"
        _bc_quic="$(grep -Ei '^(curl_test_http3|curl_test_quic|curl_test_udp)' "$summary_file" 2>/dev/null | grep -F -- '--payload=quic_initial' | head -n 1 | sed -n 's/^.* : nfqws2[[:space:]]*//p')"

        _bc_ipv6="n"
        _zapret2_ipv6_enabled 2>/dev/null && _bc_ipv6="y"
        if [ "$_bc_ipv6" = "y" ]; then
            # Blockcheck quick summary is often IPv4-only. Menu 7 is the user decision
            # for Zapret2 IPv6 support, so mirror ip_ttl=N to ip6_ttl=N on found blocks.
            [ -n "$_bc_http" ] && ! printf '%s' "$_bc_http" | grep -q ':ip6_ttl=' && _bc_http="$(printf '%s' "$_bc_http" | sed 's/:ip_ttl=\([0-9][0-9]*\)/:ip_ttl=\1:ip6_ttl=\1/g')"
            [ -n "$_bc_tls" ] && ! printf '%s' "$_bc_tls" | grep -q ':ip6_ttl=' && _bc_tls="$(printf '%s' "$_bc_tls" | sed 's/:ip_ttl=\([0-9][0-9]*\)/:ip_ttl=\1:ip6_ttl=\1/g')"
            [ -n "$_bc_quic" ] && ! printf '%s' "$_bc_quic" | grep -q ':ip6_ttl=' && _bc_quic="$(printf '%s' "$_bc_quic" | sed 's/:ip_ttl=\([0-9][0-9]*\)/:ip_ttl=\1:ip6_ttl=\1/g')"
        fi

        _bc_combined=""
        if [ -n "$_bc_http" ]; then
            _bc_combined="--filter-tcp=80 <HOSTLIST> --filter-l7=http ${_bc_http}"
        fi
        if [ -n "$_bc_tls" ]; then
            [ -n "$_bc_combined" ] && _bc_combined="${_bc_combined} --new "
            _bc_combined="${_bc_combined}--filter-tcp=443 <HOSTLIST> --filter-l7=tls ${_bc_tls}"
        fi
        if [ -n "$_bc_quic" ]; then
            [ -n "$_bc_combined" ] && _bc_combined="${_bc_combined} --new "
            _bc_combined="${_bc_combined}--filter-udp=443 <HOSTLIST> --filter-l7=quic ${_bc_quic}"
        fi

        # If structured SUMMARY entries were available, prefer the protocol-aware chain.
        # Otherwise keep the single safe candidate extracted above as fallback.
        [ -n "$_bc_combined" ] && params_filtered="$_bc_combined"
        
if [ -z "$params_filtered" ]; then
    echo "$(T TXT_BLOCKCHECK_NO_STRAT)"
else
    # Build quick stability stats from SUMMARY section (best-effort)
    # State values for GUI:
    #   dns_ok:    1=OK, 0=real DNS failure, 2=informational resolver mismatch/unknown
    #   udp_weak:  1=weak, 0=OK, 2=not tested / N/A
    local _sum_start total_tests success_tests tls12_ok dns_ok udp_weak score
    _sum_start="$(grep -n "^\* SUMMARY" "$src_report" 2>/dev/null | head -n1 | cut -d: -f1)"
    total_tests=0
    success_tests=0
    tls12_ok=0
    udp_weak=2
    if [ -n "$_sum_start" ]; then
        total_tests="$(sed -n "${_sum_start},\$p" "$src_report" 2>/dev/null | awk '/^curl_test_/ {print $1}' | sort -u | wc -l 2>/dev/null)"
        success_tests="$(sed -n "${_sum_start},\$p" "$src_report" 2>/dev/null | awk '/^curl_test_/ && / : nfqws2/ {print $1}' | sort -u | wc -l 2>/dev/null)"
        sed -n "${_sum_start},\$p" "$src_report" 2>/dev/null | grep -q '^curl_test_https_tls12 ' && tls12_ok=1
        # Short kzmquick tests may skip QUIC/UDP completely. Missing UDP lines
        # must be shown as N/A, not WARN, otherwise users think DNS/UDP is broken.
        if sed -n "${_sum_start},\$p" "$src_report" 2>/dev/null | grep -Eqi '^(curl_test_http3|curl_test_quic|curl_test_udp)'; then
            udp_weak=1
            sed -n "${_sum_start},\$p" "$src_report" 2>/dev/null | grep -Eqi '^(curl_test_http3|curl_test_quic|curl_test_udp).*nfqws2' && udp_weak=0
        fi
    fi
    [ -n "$total_tests" ] || total_tests=0
    [ -n "$success_tests" ] || success_tests=0
    [ "$total_tests" -gt 0 ] || total_tests=1
    dns_ok=1
    # Resolver mismatch can be expected when DoH/DoT or filtered DNS is used.
    # Show it as INFO/N/A in GUI instead of lowering DPI health score.
    grep -qi "POSSIBLE DNS HIJACK" "$src_report" 2>/dev/null && dns_ok=2
    grep -Eqi "system DNS is not working|DNS.*(fail|error|unavailable)" "$src_report" 2>/dev/null && dns_ok=0
    # Simple score (0-10) - informative only
    score=10
    [ "$dns_ok" = "0" ] && score=$((score-2))
    [ "${tls12_ok:-0}" = "0" ] && score=$((score-1))
    [ "$score" -lt 0 ] && score=0
    [ "$score" -gt 10 ] && score=10
    # GUI icin blockcheck sonucunu JSON olarak kaydet
    local _bcts
    _bcts="$(date +%s 2>/dev/null)"
    printf '{\n  "score": %s,\n  "dns_ok": %s,\n  "tls12_ok": %s,\n  "udp_weak": %s,\n  "tests_ok": %s,\n  "tests_total": %s,\n  "ts": %s\n}\n' \
        "$score" "$dns_ok" "${tls12_ok:-0}" "${udp_weak:-1}" "${success_tests:-0}" "${total_tests:-0}" "$_bcts" \
        > /opt/zapret2/blockcheck_result.json 2>/dev/null
    echo
    echo "$(T TXT_BLOCKCHECK_FOUND)"
    echo " $params_filtered"
    echo
    echo "$(T TXT_BLOCKCHECK_MOST_STABLE)"
    echo " $params_filtered (${success_tests}/${total_tests})"
    echo
    echo "$(T TXT_BLOCKCHECK_SCORE) ${score} / 10"
    # UI symbols: prefer Unicode on UTF-8 terminals, fallback to ASCII for PuTTY/non-UTF8
    local _sym_ok="✔" _sym_warn="⚠"
    case "${LC_ALL:-}${LANG:-}" in
    *UTF-8*|*utf8*|*Utf8*) : ;;
    *) _sym_ok="[OK]"; _sym_warn="[!]" ;;
    esac
    [ "$dns_ok" = "1" ] && printf "  %s %s\n" "$_sym_ok" "$(T TXT_BLOCKCHECK_SCORE_DNS_OK)" || printf "  %s DNS\n" "$_sym_warn"
    [ "${tls12_ok:-0}" = "1" ] && printf "  %s %s\n" "$_sym_ok" "$(T TXT_BLOCKCHECK_SCORE_TLS12_OK)" || printf "  %s TLS12\n" "$_sym_warn"
    [ "${udp_weak:-1}" = "1" ] && printf "  %s %s\n" "$_sym_warn" "$(T TXT_BLOCKCHECK_SCORE_UDP_WEAK)"
    echo
    while :; do
        echo "$(T TXT_BLOCKCHECK_ACTION_MENU)"
        printf '%s' "$(T TXT_BLOCKCHECK_ACTION_PROMPT) "; read -r ans
        ans="$(echo "$ans" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        case "$ans" in
            1)
                set_dpi_profile "blockcheck_auto"
                set_dpi_origin "auto"
                printf "%s\n" "$params_filtered" > "$BLOCKCHECK_AUTO_PARAMS_FILE" 2>/dev/null
                printf "%s\n" "$params_filtered" > "$DPI_PROFILE_PARAMS_FILE" 2>/dev/null
                update_nfqws_parameters >/dev/null 2>&1
                restart_zapret2 >/dev/null 2>&1 || /opt/etc/init.d/S90-zapret2 start >/dev/null 2>&1
                echo "$(T TXT_BLOCKCHECK_APPLIED)"
                break
            ;;
            2)
                echo
                echo "$params_filtered"
                echo
                press_enter_to_continue
            ;;
            3)
                # Save only (do not switch current profile / restart)
                printf "%s\n" "$params_filtered" > "$BLOCKCHECK_AUTO_PARAMS_FILE" 2>/dev/null
                printf "%s\n" "$params_filtered" > "$DPI_PROFILE_PARAMS_FILE" 2>/dev/null
                echo "$(T TXT_BLOCKCHECK_SUMMARY_SAVED) $summary_file"
                break
            ;;
            0|"")
                break
            ;;
            *)
                :
            ;;
        esac
    done
fi
    fi
    # Summary mode: keep only the summary file (avoid creating an extra large report file) (avoid creating an extra large report file)
    if [ -n "$src_report" ] && [ -f "$src_report" ]; then
        rm -f "$src_report" >/dev/null 2>&1
    fi
    echo "$(T TXT_BLOCKCHECK_SUMMARY_SAVED) $summary_file"
    press_enter_to_continue
}

kzm2_export_active_dpi_profile() {
    local _cmd="" _clean="" _cfg="" _out="" _out_latest="" _out_dir="/opt/zapret2/dpi_profiles"
    local _host="" _prof="" _origin="" _base="" _src="runtime" _ts=""

    _host="$(hostname 2>/dev/null)"
    [ -n "$_host" ] || _host="unknown"
    _prof="$(get_dpi_profile)"
    _origin="$(get_dpi_origin)"
    _base="$(T _ "$(dpi_profile_name_tr "$_prof")" "$(dpi_profile_name_en "$_prof")")"

    if pidof nfqws2 >/dev/null 2>&1; then
        _cmd="$(tr '\0' ' ' < /proc/$(pidof nfqws2 | awk '{print $1}')/cmdline 2>/dev/null)"
        _clean="$(printf '%s\n' "$_cmd" | awk '
            BEGIN{block=""; first=1}
            {
                for(i=1;i<=NF;i++){
                    t=$i
                    if(t ~ /^--filter-(tcp|udp)=/){
                        if(block != ""){
                            if(first){printf "%s", block; first=0} else {printf " --new %s", block}
                        }
                        block=t " <HOSTLIST>"
                    } else if(t ~ /^--filter-l7=/ || t ~ /^--payload=/ || t ~ /^--lua-desync=/){
                        if(block != "") block=block " " t
                    }
                }
            }
            END{
                if(block != ""){
                    if(first){printf "%s", block} else {printf " --new %s", block}
                }
            }')"
    else
        _src="config"
        echo "$(T TXT_BLOCKCHECK_EXPORT_NO_RUNTIME)"
    fi

    if [ -z "$_clean" ] && [ -f /opt/zapret2/config ]; then
        _cfg="$(grep '^NFQWS2_OPT=' /opt/zapret2/config 2>/dev/null | sed 's/^NFQWS2_OPT="//;s/"$//')"
        _clean="$_cfg"
        _src="config"
    fi

    if [ -z "$_clean" ]; then
        echo "$(T TXT_BLOCKCHECK_EXPORT_EMPTY)"
        return 1
    fi

    mkdir -p "$_out_dir" 2>/dev/null
    _ts="$(date +%Y%m%d_%H%M%S 2>/dev/null)"
    [ -n "$_ts" ] || _ts="manual"
    _out="$_out_dir/active_dpi_profile_${_ts}.txt"
    _out_latest="$_out_dir/active_dpi_profile_latest.txt"

    {
        echo "===== KZM2 DPI PROFILI ====="
        echo "Cihaz        : $_host"
        if [ "$_src" = "runtime" ]; then
            echo "Kaynak       : Calisan Profil"
            echo "Mod          : Aktif Runtime"
        else
            echo "Kaynak       : Config"
            echo "Mod          : Kayitli Config"
        fi
        echo "Temel Profil : $_base"
        echo
        echo "NFQWS2_OPT:"
        echo
        printf '%s
' "$_clean" | awk '
            {
                line=$0
                while (index(line," --new ") > 0) {
                    p=index(line," --new ")
                    print substr(line,1,p+5)
                    print ""
                    line=substr(line,p+7)
                }
                if (line != "") print line
            }'
        echo
        echo "===== SON ====="
    } > "$_out" 2>/dev/null

    cp -f "$_out" "$_out_latest" 2>/dev/null
    # Eski dosyalari temizle: son 3 kalsin, gerisi silinsin
    ls -t "$_out_dir"/active_dpi_profile_[0-9]*.txt 2>/dev/null | tail -n +4 | while IFS= read -r _f; do rm -f "$_f" 2>/dev/null; done

    print_line
    echo "$(T TXT_BLOCKCHECK_EXPORT_TITLE)"
    print_line
    cat "$_out_latest" 2>/dev/null
    print_line
    echo "$(T TXT_BLOCKCHECK_EXPORT_FILE): $_out_latest"
    echo "$(T _ 'Arsiv dosyasi:' 'Archive file:') $_out"
    echo "$(T TXT_BLOCKCHECK_EXPORT_HINT)"
}

blockcheck_test_menu() {
    while true; do
        clear
        print_line
        echo "$(T TXT_BLOCKCHECK_TEST_TITLE)"
        print_line
        echo " 1. $(T TXT_BLOCKCHECK_SUMMARY)"
        echo " 2. $(T TXT_BLOCKCHECK_CLEAN)"
        echo " 3. $(T TXT_BLOCKCHECK_EXPORT)"
        echo " 0. $(T TXT_BACK)"
        print_line
        printf '%s' "$(T TXT_CHOICE) "; read -r ch || return 0
        case "$ch" in
            1) run_blockcheck_save_summary ;;
            2) clean_blockcheck_reports; press_enter_to_continue ;;
            3) kzm2_export_active_dpi_profile; press_enter_to_continue ;;
            0) return ;;
            *) echo "$(T TXT_INVALID_CHOICE)"; press_enter_to_continue ;;
        esac
    done
}
# --------------------------------------------------
# Zapret2 backup/restore (.txt) - /opt/zapret2/ipset -> /opt/zapret2_backups
# --------------------------------------------------
backup_restore_menu() {
    local BACKUP_BASE SRC_DIR CUR_DIR HIST_DIR TS
    BACKUP_BASE="/opt/zapret2_backups"
    SRC_DIR="/opt/zapret2/ipset"
    CUR_DIR="${BACKUP_BASE}/current"
    HIST_DIR="${BACKUP_BASE}/history"
    mkdir -p "$CUR_DIR" "$HIST_DIR" 2>/dev/null
    while true; do
        clear
print_line "="
        echo "$(T TXT_BACKUP_MENU_TITLE)"
        print_line "-"
        printf "%s %s
" "$(T TXT_BACKUP_BASE_PATH)" "$BACKUP_BASE"
        printf "%s %s
" "$(T TXT_ZAPRET_SETTINGS_BACKUP_DIR)" "$BACKUP_BASE/zapret2_settings"
print_line "="
        echo "  $(T TXT_BACKUP_SUB_BACKUP)"
        echo "  $(T TXT_BACKUP_SUB_RESTORE)"
        echo "  $(T TXT_BACKUP_SUB_SHOW)"
        echo "  $(T TXT_BACKUP_SUB_CFG_BACKUP)"
        echo "  $(T TXT_BACKUP_SUB_CFG_RESTORE)"
        echo "  $(T TXT_BACKUP_SUB_CFG_SHOW)"
        echo "  $(T TXT_BACKUP_SUB_TG_SEND)"
        echo "  $(T TXT_BACKUP_SUB_BACK)"
        print_line "-"
        printf "%s: " "$(T TXT_SELECT_ACTION)"
        read -r CH || return 0
        case "$CH" in
            1)
                # Backup: copy all existing .txt files to current + history timestamp
                if [ ! -d "$SRC_DIR" ] || ! ls "$SRC_DIR"/*.txt >/dev/null 2>&1; then
                    echo "$(T TXT_BACKUP_NO_SRC)"
                    press_enter_to_continue
                    continue
                fi
                TS="$(date +%Y%m%d_%H%M%S)"
                mkdir -p "$HIST_DIR/$TS" 2>/dev/null
                for f in "$SRC_DIR"/*.txt; do
                    [ -f "$f" ] || continue
                    cp -a "$f" "$CUR_DIR/$(basename "$f")" 2>/dev/null
                    cp -a "$f" "$HIST_DIR/$TS/$(basename "$f")" 2>/dev/null
                done
                # Menu 12 IPSET istemci secimi / modu / VPN subnetleri / No Zapret harici liste
                for f in "$IPSET_CLIENT_FILE" "$IPSET_CLIENT_MODE_FILE"; do
                    [ -f "$f" ] || continue
                    cp -a "$f" "$CUR_DIR/$(basename "$f")" 2>/dev/null
                    cp -a "$f" "$HIST_DIR/$TS/$(basename "$f")" 2>/dev/null
                done
                print_status PASS "$(T TXT_BACKUP_DONE)"
                press_enter_to_continue
                ;;
            2)
                # Restore: let user pick a file from current backups
                if [ ! -d "$CUR_DIR" ] || ! ls "$CUR_DIR"/*.txt >/dev/null 2>&1; then
                    echo "$(T TXT_BACKUP_NO_BACKUP)"
                    press_enter_to_continue
                    continue
                fi
                restore_single_from_current "$CUR_DIR" "$SRC_DIR"
                ;;
            3)
                clear
print_line "="
                echo "$(T TXT_BACKUP_MENU_TITLE)"
        printf "%s %s\n" "$(T TXT_BACKUP_BASE_PATH)" "$BACKUP_BASE"
print_line "="
                echo
                echo "[current]"
                ls -la "$CUR_DIR" 2>/dev/null | sed -n '1,200p'
                echo
                echo "[history - last 5]"
                _hcount="$(ls -1 "$HIST_DIR" 2>/dev/null | wc -l | tr -d ' ')"
                if [ "${_hcount:-0}" -eq 0 ]; then
                    printf "  %b%s%b\n" "${CLR_DIM}" "$(T _ 'Gecmis yedek yok.' 'No history backups.')" "${CLR_RESET}"
                else
                    ls -1 "$HIST_DIR" 2>/dev/null | tail -n 5
                fi
                print_line "-"
                printf "  T) %s\n" "$(T _ 'Gecmis Yedeklerini Temizle' 'Clean History Backups')"
                printf "  0) %s\n" "$(T TXT_BACK)"
                print_line "-"
                printf "%s " "$(T TXT_CHOICE)"
                read -r _ch3 </dev/tty
                case "$_ch3" in
                    t|T)
                        if [ "${_hcount:-0}" -eq 0 ]; then
                            print_status INFO "$(T _ 'Gecmis yedek bulunamadi.' 'No history backups found.')"
                        else
                            printf "%s (%s). %s (e/h): " \
                                "$(T _ 'Gecmis yedekleri silinecek' 'History backups will be deleted')" \
                                "$_hcount" \
                                "$(T _ 'Devam' 'Continue')"
                            read -r _conf </dev/tty
                            if echo "$_conf" | grep -qi "^[ey]"; then
                                rm -rf "${HIST_DIR:?}"/* 2>/dev/null
                                print_status PASS "$(T _ 'Gecmis yedekler temizlendi.' 'History cleaned.')"
                            else
                                print_status INFO "$(T _ 'Iptal edildi.' 'Cancelled.')"
                            fi
                        fi
                        press_enter_to_continue
                        ;;
                esac
                ;;
            4)
                backup_zapret_settings "$BACKUP_BASE"
                ;;
            5) zapret_restore_menu "$BACKUP_BASE" ;;
            6)
                show_zapret_settings_backups "$BACKUP_BASE"
                ;;
            7)
                # Telegram'a gonder: once yeni yedek al, sonra gonder
                if ! telegram_ready 2>/dev/null; then
                    print_status WARN "$(T TXT_BACKUP_TG_NO_CONFIG)"
                    press_enter_to_continue
                    continue
                fi
                echo "$(T _ 'Yedek olusturuluyor...' 'Creating backup...')"
                backup_zapret_settings "$BACKUP_BASE"
                local _tg_file
                _tg_file="$(ls -t "${BACKUP_BASE}/zapret2_settings"/zapret2_settings_*.tar.gz 2>/dev/null | head -1)"
                if [ -z "$_tg_file" ]; then
                    print_status FAIL "$(T TXT_BACKUP_TG_NO_FILE)"
                    press_enter_to_continue
                    continue
                fi
                echo "$(T TXT_BACKUP_TG_SENDING)"
                local _tg_caption
                _tg_caption="$(T _ 'KZM2 Yedek' 'KZM2 Backup') | $(basename "$_tg_file") | $(date '+%Y-%m-%d %H:%M')"
                if tgbot_send_document "$TG_CHAT_ID" "$_tg_file" "$_tg_caption"; then
                    print_status PASS "$(T TXT_BACKUP_TG_OK)"
                else
                    print_status FAIL "$(T TXT_BACKUP_TG_FAIL)"
                fi
                press_enter_to_continue
                ;;
            0)
                return 0
                ;;
            *)
                ;;
        esac
    done
}
restore_single_from_current() {
    # $1: current backup dir, $2: src dir
    local CUR_DIR SRC_DIR i f files sel
    CUR_DIR="$1"
    SRC_DIR="$2"
    mkdir -p "$SRC_DIR" 2>/dev/null
    # build file list
    files=""
    for f in "$CUR_DIR"/*.txt; do
        [ -f "$f" ] || continue
        files="${files}${f}
"
    done
    if [ -z "$files" ]; then
        echo "$(T TXT_BACKUP_NO_BACKUP)"
        press_enter_to_continue
        return 0
    fi
    while true; do
        clear
print_line "="
        echo "$(T TXT_BACKUP_MENU_TITLE)"
print_line "="
        echo "$(T TXT_SELECT_FILE):"
        print_line "-"
        i=1
        for f in $files; do
            [ -f "$f" ] || continue
            echo " $i. $(basename "$f")"
            i=$((i+1))
        done
        echo " $(T TXT_BACKUP_SUB_BACK_LIST)"
        print_line "-"
        printf "%s: " "$(T TXT_SELECT_ACTION)"
        read -r sel || return 0
        [ "$sel" = "0" ] && return 0
        i=1
        for f in $files; do
            [ -f "$f" ] || continue
            if [ "$sel" = "$i" ]; then
                _bn="$(basename "$f")"
                case "$_bn" in
                    ipset_clients.txt|ipset_clients_mode)
                        cp -a "$f" "/opt/zapret2/$_bn" 2>/dev/null
                        ;;
                    *)
                        cp -a "$f" "$SRC_DIR/$_bn" 2>/dev/null
                        ;;
                esac
                apply_ipset_client_settings >/dev/null 2>&1 || true
                echo "$(T TXT_RESTORE_DONE)"
                # Restore sonrasi zapret'i yeniden baslat (kurallar tekrar uygulansin)
                if is_zapret2_installed; then
        echo "$(T TXT_RESTORE_RESTARTING)"
        # Menu 5 ile ayni akisi kullan: stop/resume/start + WAN pin kontrolleri
        if restart_zapret2; then
            echo "$(T TXT_RESTORE_RESTART_OK)"
        else
            echo "$(T TXT_RESTORE_RESTART_FAIL)"
        fi
    fi
                # Telegram bot'u restore sonrasi yeniden baslat (ayarlar degismis olabilir)
                if [ "$(grep -s '^TG_BOT_ENABLE=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')" = "1" ]; then
                    telegram_bot_stop >/dev/null 2>&1 || true
                    sleep 1
                    telegram_bot_start >/dev/null 2>&1 || true
                fi
                press_enter_to_continue
                return 0
            fi
            i=$((i+1))
        done
    done
}
backup_zapret_settings() {
    # Back up Zapret2 settings (config + key state files) into a tar.gz under BACKUP_BASE/zapret2_settings
    BACKUP_BASE="${1:-/opt/zapret2_backups}"
    DEST_DIR="$BACKUP_BASE/zapret2_settings"
    mkdir -p "$DEST_DIR" 2>/dev/null
    TS="$(date +%Y%m%d_%H%M%S)"
    ARCHIVE="$DEST_DIR/zapret2_settings_${TS}.tar.gz"
    # Build relative path list safely (only include existing files/dirs)
    RELS=""
    add_rel() {
        _p="$1"
        [ -e "$_p" ] || return 0
        RELS="$RELS ${_p#/}"
        return 0
    }
    add_rel "/opt/zapret2/config"
    add_rel "/opt/zapret2/wan_if"
    add_rel "/opt/zapret2/lang"
    add_rel "/opt/zapret2/hostlist_mode"
    add_rel "/opt/zapret2/scope_mode"
    add_rel "/opt/zapret2/ipset_clients.txt"
    add_rel "/opt/zapret2/ipset_clients_mode"
    add_rel "/opt/zapret2/dpi_profile"
    add_rel "/opt/zapret2/dpi_profile_origin"
    add_rel "/opt/zapret2/dpi_profile_params"
    add_rel "/opt/zapret2/blockcheck_auto_params"
    add_rel "/opt/zapret2/blockcheck_result.json"
    add_rel "/opt/zapret2/dpi_profiles"
    add_rel "/opt/etc/healthmon.conf"
    add_rel "/opt/etc/telegram.conf"
    add_rel "/opt/etc/kzm2_gui.conf"
    add_rel "/opt/zapret2/init.d/sysv/zapret2.real"
    add_rel "/opt/zapret2/init.d/sysv/custom.d/90-keenetic-client-ipset"
    add_rel "/opt/etc/init.d/S99kzm2_healthmon"
    # include all .txt files from ipset dir (nozapret, zapret-hosts-*, future files)
    for f in /opt/zapret2/ipset/*.txt; do
        [ -e "$f" ] || break
        add_rel "$f"
    done
    # nothing to back up?
    if [ -z "$(echo "$RELS" | tr -d ' ')" ]; then
        print_status WARN "$(T TXT_BACKUP_CFG_NO_FILES)"
        press_enter_to_continue
        return 0
    fi
    # create archive (busybox tar is usually available)
    tar -C / -czf "$ARCHIVE" $RELS 2>/dev/null
    if [ $? -ne 0 ] || [ ! -s "$ARCHIVE" ]; then
        rm -f "$ARCHIVE" 2>/dev/null
        print_status FAIL "$(T backup_tar_fail 'Yedekleme basarisiz.' 'Backup failed.')"
        press_enter_to_continue
        return 1
    fi
    print_status PASS "$(printf "$(T TXT_BACKUP_CFG_BACKED_UP)" "$ARCHIVE")"
    press_enter_to_continue
    return 0
}
clean_zapret_settings_backups() {
    BACKUP_BASE="${1:-$BACKUP_BASE}"
    # KZM2 only: never list/delete/restore legacy KZM archives.
    # Valid archive pattern: zapret2_settings_YYYYmmdd_HHMMSS.tar.gz
    local DIR_NEW="$BACKUP_BASE/zapret2_settings"
    # Screen
    command -v clear >/dev/null 2>&1 && clear || true
    echo "==========================================================="
    echo "$(T TXT_ZAPRET_SETTINGS_CLEAN_MENU)"
    echo "==========================================================="
    echo "$(T TXT_ZAPRET_SETTINGS_BACKUP_DIR) $BACKUP_BASE/zapret2_settings"
    echo "==========================================================="
    echo "$(T TXT_ZAPRET_SETTINGS_CLEAN_CONFIRM)"
    print_line
    echo " 1) $(T TXT_YES)"
    echo " 0) $(T TXT_NO)"
    print_line
    printf "%s " "$(T TXT_CHOICE)"
    local ans
    read -r ans
    case "$ans" in
        1|y|Y|e|E)
            local removed=0
            # Delete in both possible locations.
            # shellcheck disable=SC2039
            if [ -d "$DIR_NEW" ]; then
                # If there are matches, delete them.
                if ls "$DIR_NEW"/zapret2_settings_*.tar.gz >/dev/null 2>&1; then
                    rm -f "$DIR_NEW"/zapret2_settings_*.tar.gz 2>/dev/null && removed=1
                fi
            fi
            if [ "$removed" -eq 1 ]; then
                print_status PASS "$(T TXT_ZAPRET_SETTINGS_CLEAN_DONE)"
            else
                print_status WARN "$(T TXT_ZAPRET_SETTINGS_CLEAN_NONE)"
            fi
            ;;
        *)
            print_status INFO "$(T TXT_CANCELLED)"
            ;;
    esac
    press_enter_to_continue
}
list_zapret_settings_backups() {
    BACKUP_BASE="${1:-/opt/zapret2_backups}"
    DIR="$BACKUP_BASE/zapret2_settings"
    [ -d "$DIR" ] || return 1
    ls -1 "$DIR"/zapret2_settings_*.tar.gz 2>/dev/null | sort -r
}
show_zapret_settings_backups() {
    BACKUP_BASE="${1:-/opt/zapret2_backups}"
    DIR="$BACKUP_BASE/zapret2_settings"
    local _scount=0
    [ -d "$DIR" ] && _scount="$(ls -1 "$DIR"/zapret2_settings_*.tar.gz 2>/dev/null | wc -l | tr -d ' ')"
    clear
print_line "="
    echo "$(T TXT_BACKUP_MENU_TITLE)"
print_line "="
    echo
    if [ "${_scount:-0}" -eq 0 ]; then
        printf "  %b%s%b\n" "${CLR_DIM}" "$(T _ 'Zapret2 ayar yedegi yok.' 'No settings backups.')" "${CLR_RESET}"
    else
        (
            cd "$DIR" 2>/dev/null || exit 0
            ls -l zapret2_settings_*.tar.gz 2>/dev/null | sed -n '1,200p'
        )
    fi
    print_line "-"
    printf "  T) %s\n" "$(T _ 'Zapret2 Ayar Yedeklerini Temizle' 'Clean Zapret2 Settings Backups')"
    printf "  0) %s\n" "$(T TXT_BACK)"
    print_line "-"
    printf "%s " "$(T TXT_CHOICE)"
    read -r _ch6 </dev/tty
    case "$_ch6" in
        t|T)
            if [ "${_scount:-0}" -eq 0 ]; then
                print_status INFO "$(T TXT_ZAPRET_SETTINGS_CLEAN_NONE)"
            else
                printf "%s (%s). %s (e/h): " \
                    "$(T _ 'Zapret2 ayar yedekleri silinecek' 'Zapret2 settings backups will be deleted')" \
                    "$_scount" \
                    "$(T _ 'Devam' 'Continue')"
                read -r _conf6 </dev/tty
                if echo "$_conf6" | grep -qi "^[ey]"; then
                    rm -f "$DIR"/zapret2_settings_*.tar.gz 2>/dev/null
                    print_status PASS "$(T TXT_ZAPRET_SETTINGS_CLEAN_DONE)"
                else
                    print_status INFO "$(T _ 'Iptal edildi.' 'Cancelled.')"
                fi
            fi
            press_enter_to_continue
            ;;
    esac
    return 0
}
restore_zapret_settings() {
    # $1 = BACKUP_BASE (root folder that contains zapret2_settings/)
    local BACKUP_BASE="${1:-/opt/zapret2_backups}"
    local SETTINGS_DIR="${BACKUP_BASE%/}/zapret2_settings"
    clear_screen
    print_line "="
    printf "%s\n" "$(T TXT_ZAPRET_SETTINGS_RESTORE_TITLE)"
    print_line "="
    printf "%s\n" "$(T TXT_BACKUP_BASE_PATH) ${BACKUP_BASE}"
    print_line "-"
    printf "\n"
    # Zapret2 kurulu degilse engelle
    if ! is_zapret2_installed; then
        printf "%b%s %s%b\n\n" "${CLR_ORANGE}${CLR_BOLD}" "WARN" \
            "$(T _ 'Zapret2 kurulu degil. Once Menu 1 ile Zapret2 kurun, sonra restore yapin.' 'Zapret2 is not installed. Install Zapret2 via Menu 1 first, then restore.')" \
            "${CLR_RESET}"
        press_enter_to_continue
        return 1
    fi
    if [ ! -d "$SETTINGS_DIR" ]; then
        print_status WARN "$(T TXT_BACKUP_NO_BACKUPS_FOUND)"
        press_enter_to_continue
        return 1
    fi
    # List backups (newest first). Expected: zapret2_settings_YYYYmmdd_HHMMSS.tar.gz
    local backups
    backups="$(ls -1t "$SETTINGS_DIR"/zapret2_settings_*.tar.gz 2>/dev/null)"
    if [ -z "$backups" ]; then
        print_status WARN "$(T TXT_BACKUP_NO_BACKUPS_FOUND)"
        press_enter_to_continue
        return 1
    fi
    printf "%s\n" "$(T TXT_SELECT_BACKUP_TO_RESTORE)"
    print_line "-"
    local i=0 b
    for b in $backups; do
        i=$((i+1))
        printf " %2d) %s\n" "$i" "$(basename "$b")"
        [ "$i" -ge 15 ] && break
    done
    printf "\n"
    printf "  0) %s
" "$(T TXT_BACK)"
    print_line "-"
    printf "%s" "$(T TXT_CHOICE)"
    read -r sel || return 0
    [ -z "$sel" ] && return 0
    if [ "$sel" = "0" ]; then
        return 0
    fi
    if ! echo "$sel" | grep -Eq '^[0-9]+$'; then
        print_status WARN "$(T TXT_INVALID_CHOICE)"
        press_enter_to_continue
        return 1
    fi
    local chosen=""
    i=0
    for b in $backups; do
        i=$((i+1))
        if [ "$i" -eq "$sel" ]; then
            chosen="$b"
            break
        fi
        [ "$i" -ge 15 ] && break
    done
    if [ -z "$chosen" ] || [ ! -f "$chosen" ]; then
        print_status WARN "$(T TXT_INVALID_CHOICE)"
        press_enter_to_continue
        return 1
    fi
    clear_screen
    printf "%s\n" "$(T TXT_ZAPRET_RESTORE_SUBMENU_TITLE)"
    print_line "-"
    printf " 1. %s\n" "$(T TXT_RESTORE_SCOPE_FULL)"
    printf " 2. %s\n" "$(T TXT_RESTORE_SCOPE_DPI)"
    printf " 3. %s\n" "$(T TXT_RESTORE_SCOPE_HOSTLIST)"
    printf " 4. %s\n" "$(T TXT_RESTORE_SCOPE_IPSET)"
    printf " 5. %s\n" "$(T TXT_RESTORE_SCOPE_NFQWS)"
    printf " 6. %s\n" "$(T TXT_RESTORE_SCOPE_KZM)"
    print_line "-"
    printf " 0. %s\n" "$(T TXT_BACK)"
    print_line "-"
    printf "%s" "$(T TXT_CHOICE)"
    read -r scope
    [ -z "$scope" ] && return 0
    if [ "$scope" = "0" ]; then
        return 0
    fi
    local tmp="/tmp/zapret2_settings_restore.$$"
    rm -rf "$tmp" 2>/dev/null
    mkdir -p "$tmp" || { print_status FAIL "$(T TXT_BACKUP_RESTORE_FAILED)"; press_enter_to_continue; return 1; }
    # Extract to temp first (safer), then copy selected paths
    if ! tar -xzf "$chosen" -C "$tmp" >/dev/null 2>&1; then
        rm -rf "$tmp" 2>/dev/null
        print_status FAIL "$(T TXT_BACKUP_RESTORE_FAILED)"
        press_enter_to_continue
        return 1
    fi
    local src="$tmp"
    # Some archives may include leading ./ or an extra top folder. Normalize:
    if [ -d "$tmp/opt" ]; then
        src="$tmp"
    else
        # pick first directory that contains opt/
        local d
        for d in "$tmp"/*; do
            if [ -d "$d/opt" ]; then src="$d"; break; fi
        done
    fi
    # Helper: copy a path if present (dir -> merge contents; file -> overwrite)
    _copy_if_exists() {
        local p="$1"
        local src_path="$src/$p"
        local dst_path="/$p"
        if [ -d "$src_path" ]; then
            mkdir -p "$dst_path" 2>/dev/null
            # Copy directory contents to avoid nested dir like /opt/zapret2/ipset/ipset
            cp -a "$src_path/." "$dst_path/" 2>/dev/null || return 1
            return 0
        fi
        if [ -e "$src_path" ]; then
            mkdir -p "/$(dirname "$p")" 2>/dev/null
            cp -a "$src_path" "$dst_path" 2>/dev/null || return 1
            return 0
        fi
        return 1
    }
    # Varsayilan: islem basarili kabul edilir. Zorunlu parcalar yoksa/basarisizsa ok=1 yapilir.
    local ok=0
    case "$scope" in
        1) # full restore
            cp -a "$src/"* / 2>/dev/null || ok=1
            ;;
        2) # DPI settings
            _copy_if_exists "opt/zapret2/config" || ok=1
            _copy_if_exists "opt/zapret2/lang" || ok=1
            _copy_if_exists "opt/zapret2/wan_if" || ok=1
            _copy_if_exists "opt/zapret2/dpi_profile" || true
            _copy_if_exists "opt/zapret2/dpi_profile_origin" || true
            _copy_if_exists "opt/zapret2/dpi_profile_params" || true
            _copy_if_exists "opt/zapret2/blockcheck_auto_params" || true
            _copy_if_exists "opt/zapret2/dpi_profiles" || true
            ;;
        3) # hostlist / autohostlist
            _copy_if_exists "opt/zapret2/hostlist_mode" || ok=1
            _copy_if_exists "opt/zapret2/scope_mode" || true
            _copy_if_exists "opt/zapret2/ipset" || true
            ;;
        4) # ipset settings
            _copy_if_exists "opt/zapret2/ipset_clients.txt" || true
            _copy_if_exists "opt/zapret2/ipset" || true
            _copy_if_exists "opt/zapret2/ipset_clients_mode" || true
            ;;
        5) # nfqws config only
            _copy_if_exists "opt/zapret2/config" || ok=1
            ;;
        6) # KZM settings (healthmon + telegram)
            _copy_if_exists "opt/etc/healthmon.conf" || true
            _copy_if_exists "opt/etc/telegram.conf" || true
            _copy_if_exists "opt/etc/kzm2_gui.conf" || true
            _copy_if_exists "opt/zapret2/init.d/sysv/zapret2.real" || true
            _copy_if_exists "opt/zapret2/init.d/sysv/custom.d/90-keenetic-client-ipset" || true
            _copy_if_exists "opt/etc/init.d/S99kzm2_healthmon" || true
            ;;
        *)
            rm -rf "$tmp" 2>/dev/null
            print_status WARN "$(T TXT_INVALID_CHOICE)"
            press_enter_to_continue
            return 1
            ;;
    esac
    rm -rf "$tmp" 2>/dev/null
    if [ "$ok" -eq 0 ]; then
        print_status PASS "$(T TXT_BACKUP_RESTORE_DONE)"
		# Restore sonrasi zapret'i yeniden baslat (kurallar tekrar uygulansin)
		if is_zapret2_installed; then
			echo "$(T TXT_RESTORE_RESTARTING)"
			fix_zapret2_runtime_permissions
			if restart_zapret2; then
				print_status PASS "$(T TXT_RESTORE_RESTART_OK)"
			else
				print_status WARN "$(T TXT_RESTORE_RESTART_WARN)"
			fi
		fi
        # Web Panel kuruluysa dosyalari guncelle (restore'dan eski versiyon gelmis olabilir)
        if [ -d "$KZM2_GUI_DIR" ]; then
            print_status INFO "$(T _ 'Web Panel dosyalari guncelleniyor...' 'Updating Web Panel files...')"
            kzm_gui_write_html
            kzm_gui_write_cgi
            kzm_gui_write_status_script
            print_status PASS "$(T _ 'Web Panel guncellendi.' 'Web Panel updated.')"
            # crond calismiyorsa baslat
            if ! pgrep crond >/dev/null 2>&1; then
                crond 2>/dev/null || true
                sleep 1
                pgrep crond >/dev/null 2>&1 && \
                    print_status PASS "$(T _ 'crond baslatildi' 'crond started')" || \
                    print_status WARN "$(T _ 'crond baslatilamadi' 'crond could not be started')"
            fi
        fi
        # Telegram bot'u restore sonrasi yeniden baslat (telegram.conf restore edilmis olabilir)
        if [ "$(grep -s '^TG_BOT_ENABLE=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')" = "1" ]; then
            telegram_bot_stop >/dev/null 2>&1 || true
            sleep 1
            telegram_bot_start >/dev/null 2>&1 || true
            print_status PASS "$(T _ 'Telegram bot yeniden baslatildi.' 'Telegram bot restarted.')"
        fi
        # HealthMon'u restore sonrasi yeniden baslat (init dosyasi restore edilmis olabilir)
        if [ -f "/opt/etc/init.d/S99kzm2_healthmon" ]; then
            healthmon_stop >/dev/null 2>&1 || true
            sleep 1
            healthmon_start >/dev/null 2>&1 || true
        fi
    else
        print_status FAIL "$(T TXT_BACKUP_RESTORE_FAILED)"
    fi
    press_enter_to_continue
}
zapret_restore_menu() {
    local BACKUP_BASE="$1"
    restore_zapret_settings "$BACKUP_BASE"
}
# -------------------------------------------------------------------
# TELEGRAM NOTIFICATIONS (CONFIG + TEST)
# -------------------------------------------------------------------
TG_CONF_FILE="/opt/etc/telegram.conf"
telegram_load_config() {
    TG_BOT_TOKEN=""
    TG_CHAT_ID=""
    TG_BOT_ENABLE="0"
    TG_BOT_POLL_SEC="5"
    TG_ROUTER_ID=""
    [ -f "$TG_CONF_FILE" ] && . "$TG_CONF_FILE" 2>/dev/null
    # Bos ise hostname'den al
    if [ -z "$TG_ROUTER_ID" ]; then
        TG_ROUTER_ID="$(hostname 2>/dev/null)"
        [ -z "$TG_ROUTER_ID" ] && TG_ROUTER_ID="$(cat /proc/sys/kernel/hostname 2>/dev/null)"
        [ -z "$TG_ROUTER_ID" ] && TG_ROUTER_ID="keenetic"
    fi
    # validate minimal
    [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ] || return 1
    return 0
}
telegram_mask_token() {
    # prints masked token (first 6 ... last 4)
    local t="$1"
    [ -z "$t" ] && { echo "-"; return; }
    local l="${#t}"
    if [ "$l" -le 12 ]; then
        echo "***"
    else
        echo "$(echo "$t" | cut -c1-6)....$(echo "$t" | rev | cut -c1-4 | rev)"
    fi
}
# -------------------------------------------------------------------
# Telegram: Device identity header (hostname / IP / model)
# Purpose: When multiple routers use the same bot, make it obvious which
# device generated the alert.
# -------------------------------------------------------------------
TG_INCLUDE_DEVICE_HEADER="${TG_INCLUDE_DEVICE_HEADER:-1}"
TG_DEVICE_NAME=""
TG_DEVICE_LAN_IP=""
TG_DEVICE_WAN_IP=""
TG_DEVICE_MODEL=""
telegram_device_info_init() {
    # Cache device identity once per run
    [ -n "$TG_DEVICE_NAME" ] && [ -n "$TG_DEVICE_LAN_IP" ] && [ -n "$TG_DEVICE_MODEL" ] && {
        # Diger alanlar cache'lendi, sadece WAN IP'yi taze oku
        TG_DEVICE_WAN_IP=""
        local _wan_if_live=""
        _wan_if_live="$(ip -4 addr show ppp0 2>/dev/null | awk '/inet /{print "ppp0"; exit}')"
        [ -z "$_wan_if_live" ] && _wan_if_live="$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
        [ -n "$_wan_if_live" ] && TG_DEVICE_WAN_IP="$(ip -4 addr show "$_wan_if_live" 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)"
        [ -z "$TG_DEVICE_WAN_IP" ] && TG_DEVICE_WAN_IP="unknown"
        return 0
    }
    # Hostname (Keenetic "System Name")
    TG_DEVICE_NAME="$(hostname 2>/dev/null)"
    [ -z "$TG_DEVICE_NAME" ] && TG_DEVICE_NAME="$(cat /proc/sys/kernel/hostname 2>/dev/null)"
    [ -z "$TG_DEVICE_NAME" ] && TG_DEVICE_NAME="keenetic"
    # -------------------------
    # LAN IP (prefer bridge/br0)
    # -------------------------
    TG_DEVICE_LAN_IP=""
    for _if in br0 bridge0 home0; do
        _ip="$(ip -4 addr show "$_if" 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)"
        [ -n "$_ip" ] && TG_DEVICE_LAN_IP="$_ip" && break
    done
    # Fallback: first RFC1918 address on any interface
    if [ -z "$TG_DEVICE_LAN_IP" ]; then
        TG_DEVICE_LAN_IP="$(ip -4 addr show 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | \
            awk '/^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)/ {print; exit}')"
    fi
    [ -z "$TG_DEVICE_LAN_IP" ] && TG_DEVICE_LAN_IP="unknown"
    # -------------------------
    # WAN IP (best-effort)
    # - PPPoE users: ppp0 is the most reliable
    # - Otherwise: default-route interface IPv4
    # -------------------------
    TG_DEVICE_WAN_IP=""
    _wan_if=""
    # Prefer ppp0 if present
    _wan_if="$(ip -4 addr show ppp0 2>/dev/null | awk '/inet /{print "ppp0"; exit}')"
    if [ -z "$_wan_if" ]; then
        # Parse default route line: "default via X dev IF ..." or "default dev IF ..."
        _wan_if="$(ip -4 route show default 2>/dev/null | awk '{
            for(i=1;i<=NF;i++){
                if($i=="dev"){print $(i+1); exit}
            }
        }')"
    fi
    if [ -n "$_wan_if" ]; then
        TG_DEVICE_WAN_IP="$(ip -4 addr show "$_wan_if" 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)"
    fi
    [ -z "$TG_DEVICE_WAN_IP" ] && TG_DEVICE_WAN_IP="unknown"
    # -------------------------
    # Model (Keenetic / ndmc varies by firmware)
    # Try several sources in order.
    # -------------------------
    TG_DEVICE_MODEL=""
    _ver="$(LD_LIBRARY_PATH= ndmc -c show version 2>/dev/null)"
    if [ -n "$_ver" ]; then
        # 1) Once description: ara — tam isim burada
        TG_DEVICE_MODEL="$(printf '%s\n' "$_ver" | awk -F': ' '
            /description:/ {
                gsub(/^[ \t]+|[ \t]+$/, "", $2);
                if ($2 != "") { print $2; exit }
            }')"
        # description yoksa diger alanlara bak
        [ -z "$TG_DEVICE_MODEL" ] && TG_DEVICE_MODEL="$(printf '%s\n' "$_ver" | awk -F': ' '
            /model:|product:|device:|hardware:|board:/ {
                gsub(/^[ \t]+|[ \t]+$/, "", $2);
                if ($2 != "") { print $2; exit }
            }')"
        # 2) Sadece tam KN-xxxx ise tabloya bak; Keenetic ile baslamiyorsa ekle
        case "$TG_DEVICE_MODEL" in
            KN-[0-9]*)
                _kn2="$(_kzm2_kn_to_name "$TG_DEVICE_MODEL" 2>/dev/null)"
                [ -n "$_kn2" ] && TG_DEVICE_MODEL="$_kn2"
                ;;
            Keenetic*) ;;
            ?*) TG_DEVICE_MODEL="Keenetic $TG_DEVICE_MODEL" ;;
        esac
        [ -z "$TG_DEVICE_MODEL" ] && TG_DEVICE_MODEL="$(printf '%s\n' "$_ver" | grep -Eo 'KN-[0-9]{3,5}' | head -n 1)"
        # 3) "Keenetic XXX" line (fallback human name)
        if [ -z "$TG_DEVICE_MODEL" ]; then
            TG_DEVICE_MODEL="$(printf '%s\n' "$_ver" | awk '
                BEGIN{IGNORECASE=1}
                /keenetic/ {print; exit}
            ' | sed 's/^[ \t]*//;s/[ \t]*$//')"
        fi
    fi
    # 4) ndmc show system (some firmwares keep product name there)
    if [ -z "$TG_DEVICE_MODEL" ]; then
        _sys="$(LD_LIBRARY_PATH= ndmc -c show system 2>/dev/null)"
        TG_DEVICE_MODEL="$(printf '%s\n' "$_sys" | awk -F': ' '
            /description:/ {
                gsub(/^[ \t]+|[ \t]+$/, "", $2);
                if ($2 != "") { print $2; exit }
            }')"
        [ -z "$TG_DEVICE_MODEL" ] && TG_DEVICE_MODEL="$(printf '%s\n' "$_sys" | awk -F': ' '
            /model:|product:|device:|hardware:|board:/ {
                gsub(/^[ \t]+|[ \t]+$/, "", $2);
                if ($2 != "") { print $2; exit }
            }')"
        case "$TG_DEVICE_MODEL" in
            KN-[0-9]*)
                _kn2="$(_kzm2_kn_to_name "$TG_DEVICE_MODEL" 2>/dev/null)"
                [ -n "$_kn2" ] && TG_DEVICE_MODEL="$_kn2"
                ;;
            Keenetic*) ;;
            ?*) TG_DEVICE_MODEL="Keenetic $TG_DEVICE_MODEL" ;;
        esac
        [ -z "$TG_DEVICE_MODEL" ] && TG_DEVICE_MODEL="$(printf '%s\n' "$_sys" | grep -Eo 'KN-[0-9]{3,5}' | head -n 1)"
    fi
    # 5) Device-tree model (varies by platform)
    if [ -z "$TG_DEVICE_MODEL" ]; then
        for _f in /proc/device-tree/model /sys/firmware/devicetree/base/model; do
            if [ -r "$_f" ]; then
                TG_DEVICE_MODEL="$(cat "$_f" 2>/dev/null | tr -d '\000' | sed 's/^[ \t]*//;s/[ \t]*$//')"
                [ -n "$TG_DEVICE_MODEL" ] && break
            fi
        done
    fi
    [ -z "$TG_DEVICE_MODEL" ] && TG_DEVICE_MODEL="Keenetic"
    # KN-xxxx kodunu tam ada cevir - sadece tam "KN-xxxx" veya "Keenetic KN-xxxx" formatindaysa
    # Keenetic ile baslamiyorsa ekle
    case "$TG_DEVICE_MODEL" in
        KN-[0-9]*)
            _full="$(_kzm2_kn_to_name "$TG_DEVICE_MODEL" 2>/dev/null)"
            [ -n "$_full" ] && TG_DEVICE_MODEL="$_full"
            ;;
        Keenetic\ KN-[0-9]*)
            _kn_code="$(printf '%s' "$TG_DEVICE_MODEL" | grep -Eo 'KN-[0-9]{3,5}' | head -1)"
            _full="$(_kzm2_kn_to_name "$_kn_code" 2>/dev/null)"
            [ -n "$_full" ] && TG_DEVICE_MODEL="$_full"
            ;;
        Keenetic*) ;;
        ?*) TG_DEVICE_MODEL="Keenetic $TG_DEVICE_MODEL" ;;
    esac
    return 0
}
telegram_build_msg() {
    # Wrap plain messages into a consistent, multi-router friendly format.
    # $1: event text (may contain newlines)
    local event="$1"
    telegram_device_info_init
    # If it's a single line, prefix with a neutral label for backward compat.
    if [ "$(printf '%s' "$event" | wc -l 2>/dev/null)" -le 1 ]; then
        event="📣 $(T TXT_TG_EVENT_LABEL) :
$event"
    fi
    cat <<EOF
📡 $(T TXT_TG_DEVICE_LABEL) : $TG_DEVICE_NAME
🏠 $(T TXT_TG_LAN_LABEL) : $TG_DEVICE_LAN_IP
🌍 $(T TXT_TG_WAN_LABEL) : $TG_DEVICE_WAN_IP
🔧 $(T TXT_TG_MODEL_LABEL) : $TG_DEVICE_MODEL

$event
🕒 $(T TXT_TG_TIME_LABEL) : $(date '+%Y-%m-%d %H:%M:%S')
EOF
}
telegram_ready() {
    # Ensure Telegram is configured (token + chat id). Best-effort device header init.
    telegram_load_config || return 1
    telegram_device_info_init >/dev/null 2>&1
    return 0
}
telegram_send() {
    # $1 message (UTF-8)
    [ -n "$1" ] || return 1
    # Telegram basic pre-req
    telegram_ready || return 1
    # Optional: include device header + timestamp (same format as other TG alerts)
    local _tg_msg="$1"
    if [ "${TG_INCLUDE_DEVICE_HEADER:-1}" = "1" ]; then
        # Always attempt to wrap with device header; avoid brittle shell builtins checks.
        _tg_msg="$(telegram_build_msg "$_tg_msg" 2>/dev/null)"
        [ -n "$_tg_msg" ] || _tg_msg="$1"
    fi
    # Find curl in daemon PATH too
    local CURL_BIN=""
    CURL_BIN="$(command -v curl 2>/dev/null)"
    [ -z "$CURL_BIN" ] && [ -x /opt/bin/curl ] && CURL_BIN="/opt/bin/curl"
    [ -z "$CURL_BIN" ] && [ -x /usr/bin/curl ] && CURL_BIN="/usr/bin/curl"
    [ -z "$CURL_BIN" ] && [ -x /bin/curl ] && CURL_BIN="/bin/curl"
    if [ -z "$CURL_BIN" ]; then
        healthmon_log "$(healthmon_now) | telegram | curl not found"
        return 127
    fi
    # After WAN flaps, DNS may not be ready immediately (curl rc=6).
    # We wait a bit and retry with exponential backoff.
    local try=1 max_try=6 rc=0
    local backoff=1
    local host_ok=0
    while [ "$try" -le "$max_try" ]; do
        # Optional DNS readiness check (best-effort)
        host_ok=0
        if command -v nslookup >/dev/null 2>&1; then
            nslookup api.telegram.org >/dev/null 2>&1 && host_ok=1
        elif command -v getent >/dev/null 2>&1; then
            getent hosts api.telegram.org >/dev/null 2>&1 && host_ok=1
        else
            host_ok=1  # no resolver tool; skip precheck
        fi
        if [ "$host_ok" -ne 1 ]; then
            healthmon_log "$(healthmon_now) | telegram | dns not ready try=$try"
            sleep "$backoff" 2>/dev/null
            backoff=$((backoff*2)); [ "$backoff" -gt 8 ] && backoff=8
            try=$((try+1))
            continue
        fi
        "$CURL_BIN" -sS \
            --connect-timeout 5 --max-time 15 \
            --retry 3 --retry-delay 1 --retry-all-errors \
            -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TG_CHAT_ID}" \
            --data-urlencode "text=$_tg_msg" \
            -d "disable_web_page_preview=true" \
            >/dev/null 2>&1
        rc=$?
        [ "$rc" -eq 0 ] && return 0
        healthmon_log "$(healthmon_now) | telegram | send failed rc=$rc try=$try"
        sleep "$backoff" 2>/dev/null
        backoff=$((backoff*2)); [ "$backoff" -gt 8 ] && backoff=8
        try=$((try+1))
    done
    return "$rc"
}
# Compatibility: old code may call tg_send
tg_send() { telegram_send "$@"; }
tpl_render() {
    # Usage: tpl_render "template" KEY1 "val1" KEY2 "val2" ...
    # Replaces %KEY% in template with the given values (busybox ash compatible)
    local tpl="$1"
    # Built-in timestamp placeholder
    local ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
    tpl="${tpl//%TS%/${ts}}"
    shift
    while [ $# -ge 2 ]; do
        local k="$1"
        local v="$2"
        tpl="${tpl//%${k}%/${v}}"
        shift 2
    done
    printf "%b" "$tpl"
}
telegram_write_config() {
    # $1 token, $2 chatid, $3 bot_enable (opt), $4 poll_sec (opt)
    local token="$1"
    local chatid="$2"
    local bot_enable="${3:-${TG_BOT_ENABLE:-0}}"
    local poll_sec="${4:-${TG_BOT_POLL_SEC:-5}}"
    # Router ID her zaman hostname'den alinir, config'e yazilmaz
    mkdir -p /opt/etc 2>/dev/null
    umask 077
    cat >"$TG_CONF_FILE" <<EOF
TG_BOT_TOKEN="$token"
TG_CHAT_ID="$chatid"
TG_BOT_ENABLE="$bot_enable"
TG_BOT_POLL_SEC="$poll_sec"
EOF
    chmod 600 "$TG_CONF_FILE" 2>/dev/null
}
telegram_notifications_menu() {
    while true; do
        clear
        print_line "="
        echo "$(T TXT_TG_SETTINGS_TITLE)"
        print_line "="
        echo
        if telegram_load_config; then
            print_line "-"
            printf "%b\n" "${CLR_BOLD}${CLR_GREEN}$(T TXT_TG_STATUS_ACTIVE)${CLR_RESET}"
            print_line "-"
            echo "  Token : $(telegram_mask_token "$TG_BOT_TOKEN")"
            echo "  ChatID: $TG_CHAT_ID"
        else
            print_line "-"
            printf "%b\n" "${CLR_BOLD}${CLR_ORANGE}$(T TXT_TG_STATUS_NOT_CONFIG)${CLR_RESET}"
            print_line "-"
            echo "  $TG_CONF_FILE"
        fi
        echo
        print_line "-"
        echo " 1) $(T TXT_TG_SAVE_UPDATE)"
        echo " 2) $(T TXT_TG_SEND_TEST)"
        echo " 3) $(T TXT_TG_DELETE_RESET)"
        echo " 4) $(T TXT_TGBOT_MENU_BOT_TITLE)"
        echo " 0) $(T TXT_BACK)"
        print_line "-"
        printf "%s" "$(T TXT_CHOICE) "
        read -r c || return 0
        clear
        case "$c" in
            1)
                echo "$(T TXT_TG_ENTER_TOKEN)"
                read -r token
                echo "$(T TXT_TG_ENTER_CHATID)"
                read -r chatid
                # simple validation
                case "$token" in
                    *:*) : ;;
                    *) print_status FAIL "$(T TXT_TG_ERR_TOKEN_FORMAT)" ; press_enter_to_continue ; continue ;;
                esac
                case "$chatid" in
                    -[0-9]*|[0-9]*) : ;;
                    *) print_status FAIL "$(T TXT_TG_ERR_CHATID_NUM)" ; press_enter_to_continue ; continue ;;
                esac
                telegram_write_config "$token" "$chatid"
                if telegram_send "$(T TXT_TG_TEST_SAVED_MSG)"; then
                    print_status PASS "$(T TXT_TG_SAVED_AND_TEST_OK)"
                else
                    print_status WARN "$(T TXT_TG_SAVED_BUT_TEST_FAIL)"
                fi
                press_enter_to_continue
                ;;
            2)
                if telegram_send "$(T TXT_TG_TEST_OK_MSG)"; then
                    print_status PASS "$(T TXT_TG_TEST_SENT)"
                else
                    print_status FAIL "$(T TXT_TG_TEST_FAIL_CONFIG_FIRST)"
                fi
                press_enter_to_continue
                ;;
            3)
                rm -f "$TG_CONF_FILE" 2>/dev/null
                print_status PASS "$(T TXT_TG_CONFIG_DELETED)"
                press_enter_to_continue
                ;;
            4) telegram_bot_menu ;;
            0) return 0 ;;
            *) echo "$(T TXT_INVALID_CHOICE)" ; sleep 1 ;;
        esac
    done
}
# -------------------------------------------------------------------
# TELEGRAM BOT (INTERACTIVE)
# -------------------------------------------------------------------
TG_BOT_PID_FILE="/tmp/kzm2_telegram_bot.pid"
TG_BOT_LOG_FILE="/tmp/kzm2_telegram_bot.log"
TG_BOT_AUTOSTART="/opt/etc/init.d/S98kzm2_telegram"
_TGBOT_TMP="/tmp/kzm2_tgbot_resp.json"
# Low-level: call Telegram Bot API, save response to tmp file
# $1=method, $2=JSON body
# returns 0 on success, response in $_TGBOT_TMP
_tgbot_api() {
    local method="$1"
    local body="$2"
    local CURL_BIN
    CURL_BIN="$(command -v curl 2>/dev/null)"
    [ -z "$CURL_BIN" ] && [ -x /opt/bin/curl ] && CURL_BIN="/opt/bin/curl"
    [ -z "$CURL_BIN" ] && return 1
    "$CURL_BIN" -sS --connect-timeout 8 --max-time 25 \
        -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/${method}" \
        -H "Content-Type: application/json" \
        -d "$body" > "$_TGBOT_TMP" 2>/dev/null
}
# Safe text: escape backslash and double-quote for JSON string
_tgbot_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/ /g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//'
}
# Send file as document
# $1=chat_id, $2=filepath, $3=caption (optional)
tgbot_send_document() {
    local chat_id="$1"
    local filepath="$2"
    local caption="${3:-}"
    local CURL_BIN
    CURL_BIN="$(command -v curl 2>/dev/null)"
    [ -z "$CURL_BIN" ] && [ -x /opt/bin/curl ] && CURL_BIN="/opt/bin/curl"
    [ -z "$CURL_BIN" ] && return 1
    [ ! -f "$filepath" ] && return 1
    if [ -n "$caption" ]; then
        "$CURL_BIN" -sS --connect-timeout 8 --max-time 60 \
            -F "chat_id=${chat_id}" \
            -F "document=@${filepath}" \
            -F "caption=${caption}" \
            "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" >/dev/null 2>&1
    else
        "$CURL_BIN" -sS --connect-timeout 8 --max-time 60 \
            -F "chat_id=${chat_id}" \
            -F "document=@${filepath}" \
            "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" >/dev/null 2>&1
    fi
}
# Send new message with optional inline keyboard
# $1=chat_id, $2=text, $3=keyboard_json (optional, empty string = no keyboard)
tgbot_send() {
    local chat_id="$1"
    local text="$2"
    local keyboard="$3"
    local safe
    safe="$(_tgbot_escape "$text")"
    local body
    if [ -n "$keyboard" ]; then
        body="{\"chat_id\":${chat_id},\"text\":\"${safe}\",\"reply_markup\":{\"inline_keyboard\":${keyboard}}}"
    else
        body="{\"chat_id\":${chat_id},\"text\":\"${safe}\"}"
    fi
    if _tgbot_api "sendMessage" "$body"; then
        grep -q '"ok":true' "$_TGBOT_TMP" 2>/dev/null || \
            printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') | tgbot | send failed: $(head -c 120 "$_TGBOT_TMP" 2>/dev/null)" >> "$TG_BOT_LOG_FILE"
    fi
}
# Edit existing message
# $1=chat_id, $2=message_id, $3=text, $4=keyboard_json (optional)
tgbot_edit() {
    local chat_id="$1"
    local msg_id="$2"
    local text="$3"
    local keyboard="$4"
    local safe
    safe="$(_tgbot_escape "$text")"
    local body
    if [ -n "$keyboard" ]; then
        body="{\"chat_id\":${chat_id},\"message_id\":${msg_id},\"text\":\"${safe}\",\"reply_markup\":{\"inline_keyboard\":${keyboard}}}"
    else
        body="{\"chat_id\":${chat_id},\"message_id\":${msg_id},\"text\":\"${safe}\",\"reply_markup\":{\"inline_keyboard\":[]}}"
    fi
    _tgbot_api "editMessageText" "$body" >/dev/null 2>&1
}
# Answer callback query (dismiss spinner)
# $1=callback_query_id
tgbot_ack() {
    _tgbot_api "answerCallbackQuery" "{\"callback_query_id\":\"$1\"}" >/dev/null 2>&1
}
# Keyboards
tgbot_kb_main() {
    local rid="${TG_ROUTER_ID:-default}"
    printf '[[{"text":"📊 %s","callback_data":"%s:menu_status"},{"text":"⚙️ %s","callback_data":"%s:menu_sistem"}],[{"text":"🛠️ %s","callback_data":"%s:menu_kzm"},{"text":"🔧 %s","callback_data":"%s:menu_zapret"}],[{"text":"📡 %s","callback_data":"%s:menu_profil"},{"text":"📋 %s","callback_data":"%s:menu_logs"}]]' \
        "$(T TXT_TGBOT_BTN_STATUS)" "$rid" \
        "$(T TXT_TGBOT_BTN_SYSTEM)" "$rid" \
        "$(T TXT_TGBOT_BTN_KZM)" "$rid" \
        "$(T TXT_TGBOT_BTN_ZAPRET)" "$rid" \
        "$(T _ 'Profil' 'Profile')" "$rid" \
        "$(T TXT_TGBOT_BTN_LOGS)" "$rid"
}
tgbot_kb_profil() {
    local rid="${TG_ROUTER_ID:-default}"
    printf '[[{"text":"📤 %s","callback_data":"%s:profil_share"}],[{"text":"◀ %s","callback_data":"%s:menu_main"}]]' \
        "$(T _ 'Paylas' 'Share')" "$rid" \
        "$(T _ 'Ana Menu' 'Main Menu')" "$rid"
}
tgbot_kb_zapret() {    local rid="${TG_ROUTER_ID:-default}"
    printf '[[{"text":"▶️ %s","callback_data":"%s:zap_start"},{"text":"⏹ %s","callback_data":"%s:zap_stop"}],[{"text":"🔄 %s","callback_data":"%s:zap_restart"}],[{"text":"⬆️ %s","callback_data":"%s:zap_update"}],[{"text":"⬅️ %s","callback_data":"%s:menu_main"}]]'         "$(T TXT_TGBOT_BTN_START)" "$rid"         "$(T TXT_TGBOT_BTN_STOP)" "$rid"         "$(T TXT_TGBOT_BTN_RESTART)" "$rid"         "$(T TXT_TGBOT_BTN_ZAP_UPDATE)" "$rid"         "$(T TXT_TGBOT_BTN_BACK)" "$rid"
}
tgbot_kb_zapret_force() {
    local rid="${TG_ROUTER_ID:-default}"
    printf '[[{"text":"⚠️ %s","callback_data":"%s:zap_force_update"},{"text":"❌ %s","callback_data":"%s:menu_zapret"}]]'         "$(T _ 'Zorla Guncelle' 'Force Update')" "$rid"         "$(T TXT_TGBOT_BTN_CANCEL)" "$rid"
}
tgbot_kb_kzm() {
    local rid="${TG_ROUTER_ID:-default}"
    printf '[[{"text":"⬆️ %s","callback_data":"%s:sys_kzm_update"},{"text":"💾 %s","callback_data":"%s:sys_kzm_backup"}],[{"text":"⬅️ %s","callback_data":"%s:menu_main"}]]' \
        "$(T TXT_TGBOT_BTN_KZM_UPDATE)" "$rid" \
        "$(T TXT_TGBOT_BTN_KZM_BACKUP)" "$rid" \
        "$(T TXT_TGBOT_BTN_BACK)" "$rid"
}
tgbot_kb_reboot_confirm() {
    local rid="${TG_ROUTER_ID:-default}"
    printf '[[{"text":"✅ %s","callback_data":"%s:sys_reboot_do"},{"text":"❌ %s","callback_data":"%s:sys_device_detail"}]]'         "$(T TXT_TGBOT_BTN_REBOOT_CONFIRM)" "$rid"         "$(T TXT_TGBOT_BTN_CANCEL)" "$rid"
}
tgbot_kb_wan_reset_time() {
    local rid="${TG_ROUTER_ID:-default}"
    printf '[[{"text":"5 dk","callback_data":"%s:wan_rc_5"},{"text":"10 dk","callback_data":"%s:wan_rc_10"},{"text":"15 dk","callback_data":"%s:wan_rc_15"}],[{"text":"20 dk","callback_data":"%s:wan_rc_20"},{"text":"25 dk","callback_data":"%s:wan_rc_25"},{"text":"30 dk","callback_data":"%s:wan_rc_30"}],[{"text":"⬅️ %s","callback_data":"%s:menu_sistem"}]]' \
        "$rid" "$rid" "$rid" \
        "$rid" "$rid" "$rid" \
        "$(T TXT_TGBOT_BTN_BACK)" "$rid"
}
tgbot_kb_wan_reset_confirm() {
    local min="$1"
    local rid="${TG_ROUTER_ID:-default}"
    printf '[[{"text":"✅ %s","callback_data":"%s:wan_rd_%s"},{"text":"❌ %s","callback_data":"%s:sys_wan_reset"}]]' \
        "$(T TXT_TGBOT_BTN_CONFIRM)" "$rid" "$min" \
        "$(T TXT_TGBOT_BTN_CANCEL)" "$rid"
}
tgbot_kb_sistem() {
    local rid="${TG_ROUTER_ID:-default}"
    local _dev_label
    _dev_label="${TG_DEVICE_NAME:-Router}"
    [ -n "$TG_DEVICE_MODEL" ] && _dev_label="${_dev_label} (${TG_DEVICE_MODEL})"
    # Ping-check durumuna gore buton sec
    local _pc_active _pc_btn _pc_action
    if LD_LIBRARY_PATH= ndmc -c "show ping-check" 2>/dev/null | grep -q "interface:"; then
        _pc_btn="$(T TXT_TGBOT_BTN_PINGCHECK_OFF)"
        _pc_action="sys_pingcheck_off"
    else
        _pc_btn="$(T TXT_TGBOT_BTN_PINGCHECK_ON)"
        _pc_action="sys_pingcheck_on"
    fi
    printf '[[{"text":"📡 %s","callback_data":"%s:sys_net_devices"},{"text":"📶 %s","callback_data":"%s:sys_wifi"}],[{"text":"🌐 %s","callback_data":"%s:sys_wan_reset"},{"text":"🔔 %s","callback_data":"%s:%s"}],[{"text":"🟢 %s","callback_data":"%s:sys_device_detail"}],[{"text":"⬅️ %s","callback_data":"%s:menu_main"}]]' \
        "$(T TXT_TGBOT_BTN_NET_DEVICES)" "$rid" \
        "$(T TXT_TGBOT_BTN_WIFI)" "$rid" \
        "$(T TXT_TGBOT_BTN_WAN_RESET)" "$rid" \
        "$_pc_btn" "$rid" "$_pc_action" \
        "$_dev_label" "$rid" \
        "$(T TXT_TGBOT_BTN_BACK)" "$rid"
}
# Cihaz detay klavyesi: Reboot / KZM Log + Sistem Log / Selftest / Geri
tgbot_kb_device() {
    local rid="${TG_ROUTER_ID:-default}"
    printf '[[{"text":"🔁 %s","callback_data":"%s:sys_reboot_confirm"}],[{"text":"📋 %s","callback_data":"%s:sys_kzmlog"},{"text":"📄 %s","callback_data":"%s:sys_syslog"}],[{"text":"🧪 %s","callback_data":"%s:sys_selftest"}],[{"text":"⬅️ %s","callback_data":"%s:menu_sistem"}]]'         "$(T TXT_TGBOT_BTN_REBOOT)" "$rid"         "$(T TXT_TGBOT_BTN_KZMLOG)" "$rid"         "$(T TXT_TGBOT_BTN_SYSLOG)" "$rid"         "$(T TXT_TGBOT_BTN_SELFTEST)" "$rid"         "$(T TXT_TGBOT_BTN_BACK)" "$rid"
}
# Log alt menu klavyesi
tgbot_kb_logs() {
    local rid="${TG_ROUTER_ID:-default}"
    printf '[[{"text":"📋 %s","callback_data":"%s:sys_kzmlog"},{"text":"📄 %s","callback_data":"%s:sys_syslog"}],[{"text":"🤖 %s","callback_data":"%s:sys_tgbotlog"},{"text":"🐛 %s","callback_data":"%s:sys_debuglog"}],[{"text":"⬅️ %s","callback_data":"%s:menu_main"}]]' \
        "$(T TXT_TGBOT_BTN_KZMLOG)" "$rid" \
        "$(T TXT_TGBOT_BTN_SYSLOG)" "$rid" \
        "$(T TXT_TGBOT_BTN_TGBOTLOG)" "$rid" \
        "$(T TXT_TGBOT_BTN_DEBUGLOG)" "$rid" \
        "$(T TXT_TGBOT_BTN_BACK)" "$rid"
}
# Ag cihazlari: ndmc show ip hotspot ile aktif hostlari inline keyboard olarak listele
# $1=offset (sayfalama, varsayilan 0)
tgbot_net_devices_kb() {
    local offset="${1:-0}"
    local rid="${TG_ROUTER_ID:-default}"
    local page_size=10
    local hotspot_raw all_names cnt kb next_offset prev_offset nav_row
    hotspot_raw="$(LD_LIBRARY_PATH= ndmc -c 'show ip hotspot' 2>/dev/null)"
    # awk ile aktif cihaz adlarini cikart
    # Format: host: > hostname: > name: (cihaz adi)
    # hostname: bir alt-bloktur; altindaki name: cihaz adini verir
    # awk: her aktif host icin "name|mac" formatinda satir uret
    all_names="$(printf '%s\n' "$hotspot_raw" | awk '
        BEGIN { in_host=0; in_hostname=0; devname=""; devmac=""; active="" }
        /^[[:space:]]*host:/ {
            if (in_host && active=="yes" && devname!="" && devmac!="") print devname "|" devmac
            in_host=1; in_hostname=0; devname=""; devmac=""; active=""; next
        }
        in_host && /^[[:space:]]*mac:/ && devmac=="" {
            s=$0; sub(/.*mac:[[:space:]]*/,"",s); gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); devmac=s
        }
        in_host && /^[[:space:]]*hostname:/ { in_hostname=1; next }
        in_host && in_hostname && /^[[:space:]]*name:/ {
            s=$0; sub(/.*name:[[:space:]]*/,"",s); gsub(/^[[:space:]]+|[[:space:]]+$/,"",s)
            if(s!="" && s!="-") devname=s
            in_hostname=0
        }
        in_host && /^[[:space:]]*interface:/ { in_hostname=0 }
        in_host && /^[[:space:]]*active:/ {
            s=$0; sub(/.*active:[[:space:]]*/,"",s); gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); active=s
        }
        END { if (in_host && active=="yes" && devname!="" && devmac!="") print devname "|" devmac }
    ')"
    cnt="$(printf '%s\n' "$all_names" | grep -c .)"
    if [ "$cnt" -eq 0 ]; then
        printf '[[{"text":"⬅️ %s","callback_data":"%s:menu_sistem"}]]' "$(T TXT_TGBOT_BTN_BACK)" "$rid"
        return
    fi
    # Sayfa butonlarini olustur
    kb="["
    local row=0
    while IFS="|" read -r name mac; do
        [ -z "$name" ] || [ -z "$mac" ] && continue
        row=$((row+1))
        [ "$row" -le "$offset" ] && continue
        [ "$row" -gt "$((offset+page_size))" ] && continue
        # MAC icindeki : isaretini - ile degistir (callback_data uyumlulugu)
        local safe_name mac_enc
        safe_name="$(printf '%s' "$name" | sed 's/"/\\"/g')"
        mac_enc="$(printf '%s' "$mac" | tr ':' '-')"
        kb="${kb}[{\"text\":\"🟢 ${safe_name}\",\"callback_data\":\"${rid}:sys_client_${mac_enc}\"}],"
    done << NEOF
$(printf '%s\n' "$all_names")
NEOF
    kb="${kb%,}"
    # Sayfalama satiri
    nav_row=""
    next_offset=$((offset+page_size))
    prev_offset=$((offset-page_size))
    [ "$prev_offset" -lt 0 ] && prev_offset=0
    if [ "$offset" -gt 0 ] && [ "$cnt" -gt "$next_offset" ]; then
        nav_row="{\"text\":\"◀️\",\"callback_data\":\"${rid}:sys_clients_${prev_offset}\"},{\"text\":\"▶️\",\"callback_data\":\"${rid}:sys_clients_${next_offset}\"}"
    elif [ "$offset" -gt 0 ]; then
        nav_row="{\"text\":\"◀️\",\"callback_data\":\"${rid}:sys_clients_${prev_offset}\"}"
    elif [ "$cnt" -gt "$next_offset" ]; then
        nav_row="{\"text\":\"▶️\",\"callback_data\":\"${rid}:sys_clients_${next_offset}\"}"
    fi
    [ -n "$nav_row" ] && kb="${kb},[${nav_row}]"
    kb="${kb},[{\"text\":\"⬅️ $(T TXT_TGBOT_BTN_BACK)\",\"callback_data\":\"${rid}:menu_sistem\"}]]"
    printf '%s' "$kb"
}
# Wifi segmentlerini inline keyboard JSON olarak olustur
# Her AP icin bireysel show interface sorgusu - link durumu kesin dogru
tgbot_wifi_kb() {
    local rid="${TG_ROUTER_ID:-default}"
    local back_btn
    back_btn="$(T TXT_TGBOT_BTN_BACK)"
    local rc_raw _tmprc _apfile
    rc_raw="$(LD_LIBRARY_PATH= ndmc -c 'show running-config' 2>/dev/null)"
    _tmprc="/tmp/_kzm2_rc_$$.txt"
    _apfile="/tmp/_kzm2_aps_$$.txt"
    printf '%s\n' "$rc_raw" > "$_tmprc"
    : > "$_apfile"
    local _cur_id _cur_name _cur_ssid _in_ap
    _cur_id=""; _cur_name=""; _cur_ssid=""; _in_ap=0
    while IFS= read -r _rc_line; do
        case "$_rc_line" in
            interface\ WifiMaster*)
                _cur_id="${_rc_line#interface }"
                _cur_name=""; _cur_ssid=""; _in_ap=1
                ;;
            "!"*)
                if [ "$_in_ap" = "1" ] && [ -n "$_cur_name" ]; then
                    printf '%s|%s|%s\n' "$_cur_id" "$_cur_name" "$_cur_ssid" >> "$_apfile"
                fi
                _cur_id=""; _cur_name=""; _cur_ssid=""; _in_ap=0
                ;;
            *)
                if [ "$_in_ap" = "1" ]; then
                    case "$_rc_line" in
                        *"rename "*)
                            _cur_name="${_rc_line#*rename }"
                            _cur_name="${_cur_name#\"}"
                            _cur_name="${_cur_name%\"}"
                            ;;
                        *"ssid "*)
                            _cur_ssid="${_rc_line#*ssid }"
                            _cur_ssid="${_cur_ssid#\"}"
                            _cur_ssid="${_cur_ssid%\"}"
                            ;;
                    esac
                fi
                ;;
        esac
    done < "$_tmprc"
    if [ "$_in_ap" = "1" ] && [ -n "$_cur_name" ]; then
        printf '%s|%s|%s\n' "$_cur_id" "$_cur_name" "$_cur_ssid" >> "$_apfile"
    fi
    rm -f "$_tmprc" 2>/dev/null
    local out="" cnt=0
    while IFS="|" read -r _apid _apname _apssid; do
        [ -z "$_apid" ] || [ -z "$_apname" ] && continue
        local _iface_out _aplink
        _iface_out="$(LD_LIBRARY_PATH= ndmc -c "show interface ${_apname}" 2>/dev/null)"
        _aplink="$(printf '%s\n' "$_iface_out" | grep '^[[:space:]]*link:' | head -1 \
            | sed 's/.*link:[[:space:]]*//' | tr -d ' ')"
        if [ -z "$_apssid" ]; then
            _apssid="$(printf '%s\n' "$_iface_out" \
                | grep '^[[:space:]]*ssid:' | head -1 \
                | sed 's/.*ssid:[[:space:]]*//' | tr -d '"')"
        fi
        [ -z "$_apssid" ] && _apssid="$_apname"
        local _band
        case "$_apid" in
            *WifiMaster1/*) _band="5GHz" ;;
            *) _band="2.4GHz" ;;
        esac
        local _dot _tog _safename _lbl
        _safename="$(printf '%s' "$_apname" | sed 's/[^a-zA-Z0-9_]/_/g')"
        if [ "$_aplink" = "up" ]; then
            _dot="🟢"; _tog="wifi_off_${_safename}"
        else
            _dot="⚪"; _tog="wifi_on_${_safename}"
        fi
        _lbl="$(printf '%s (%s)' "$_apssid" "$_band" | sed 's/\\/\\\\/g; s/"/\\"/g')"
        [ -n "$out" ] && out="${out},"
        out="${out}[{\"text\":\"${_dot} ${_lbl}\",\"callback_data\":\"${rid}:${_tog}\"}]"
        cnt=$((cnt+1))
    done < "$_apfile"
    rm -f "$_apfile" 2>/dev/null
    if [ "$cnt" -eq 0 ]; then
        printf '[[{"text":"(bos)","callback_data":"%s:noop"}],[{"text":"⬅️ %s","callback_data":"%s:menu_sistem"}]]' \
            "$rid" "$back_btn" "$rid"
    else
        printf '[%s,[{"text":"⬅️ %s","callback_data":"%s:menu_sistem"}]]' \
            "$out" "$back_btn" "$rid"
    fi
}
# Bayt degerini okunabilir formata cevir (GB/MB/KB)
_tgbot_fmt_bytes() {
    local bytes="$1"
    [ -z "$bytes" ] && { echo "-"; return; }
    # awk ile hesapla
    echo "$bytes" | awk '{
        b = $1 + 0
        if (b >= 1099511627776) printf "%.2f TB", b/1099511627776
        else if (b >= 1073741824) printf "%.2f GB", b/1073741824
        else if (b >= 1048576) printf "%.2f MB", b/1048576
        else if (b >= 1024) printf "%.2f KB", b/1024
        else printf "%d B", b
    }'
}
# WAN arayuzunden rx/tx bytes oku (/proc/net/dev)
_tgbot_wan_traffic() {
    local wan_if="$1"
    [ -z "$wan_if" ] && { echo "- / -"; return; }
    local rx tx
    rx="$(awk -v iface="${wan_if}:" '$1==iface{print $2}' /proc/net/dev 2>/dev/null)"
    tx="$(awk -v iface="${wan_if}:" '$1==iface{print $10}' /proc/net/dev 2>/dev/null)"
    [ -z "$rx" ] && rx=0
    [ -z "$tx" ] && tx=0
    printf '⬇️%s ⬆️%s' "$(_tgbot_fmt_bytes "$rx")" "$(_tgbot_fmt_bytes "$tx")"
}
# Belirli bir MAC adresine ait hotspot host bilgisini parse eder
# Cikti: satirlar halinde key=value
_tgbot_parse_client() {
    local target_mac="$1"
    local hotspot_raw
    hotspot_raw="$(LD_LIBRARY_PATH= ndmc -c 'show ip hotspot' 2>/dev/null)"
    printf '%s\n' "$hotspot_raw" | awk -v tmac="$target_mac" '
        BEGIN { in_host=0; in_hostname=0; found=0
            mac=""; name=""; ip=""; active=""; access=""; rxbytes=""; txbytes="" }
        /^[[:space:]]*host:/ {
            if (found) { exit }
            in_host=1; in_hostname=0
            mac=""; name=""; ip=""; active=""; access=""; rxbytes=""; txbytes=""
            next
        }
        in_host && /^[[:space:]]*mac:/ && mac=="" {
            s=$0; sub(/.*mac:[[:space:]]*/,"",s); gsub(/^[[:space:]]+|[[:space:]]+$/,"",s)
            mac=s
            if (mac==tmac) found=1
        }
        in_host && found && /^[[:space:]]*ip:/ && ip=="" {
            s=$0; sub(/.*ip:[[:space:]]*/,"",s); gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); ip=s
        }
        in_host && found && /^[[:space:]]*hostname:/ { in_hostname=1; next }
        in_host && found && in_hostname && /^[[:space:]]*name:/ {
            s=$0; sub(/.*name:[[:space:]]*/,"",s); gsub(/^[[:space:]]+|[[:space:]]+$/,"",s)
            if(s!="" && s!="-") name=s
            in_hostname=0
        }
        in_host && /^[[:space:]]*interface:/ { in_hostname=0 }
        in_host && found && /^[[:space:]]*active:/ {
            s=$0; sub(/.*active:[[:space:]]*/,"",s); gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); active=s
        }
        in_host && found && /^[[:space:]]*access:/ {
            s=$0; sub(/.*access:[[:space:]]*/,"",s); gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); access=s
        }
        in_host && found && /^[[:space:]]*rxbytes:/ {
            s=$0; sub(/.*rxbytes:[[:space:]]*/,"",s); gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); rxbytes=s
        }
        in_host && found && /^[[:space:]]*txbytes:/ {
            s=$0; sub(/.*txbytes:[[:space:]]*/,"",s); gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); txbytes=s
        }
        END {
            if (found) {
                print "mac=" mac
                print "name=" name
                print "ip=" ip
                print "active=" active
                print "access=" access
                print "rxbytes=" rxbytes
                print "txbytes=" txbytes
            }
        }
    '
}
# Istemci detay mesaj metni
tgbot_client_detail_text() {
    local mac="$1"
    local info name ip active access rxbytes txbytes
    info="$(_tgbot_parse_client "$mac")"
    [ -z "$info" ] && { printf '%s' "$(T _ 'Cihaz bulunamadi.' 'Device not found.')"; return; }
    name="$(printf '%s\n' "$info" | grep '^name=' | cut -d= -f2-)"
    ip="$(printf '%s\n' "$info" | grep '^ip=' | cut -d= -f2-)"
    active="$(printf '%s\n' "$info" | grep '^active=' | cut -d= -f2-)"
    access="$(printf '%s\n' "$info" | grep '^access=' | cut -d= -f2-)"
    rxbytes="$(printf '%s\n' "$info" | grep '^rxbytes=' | cut -d= -f2-)"
    txbytes="$(printf '%s\n' "$info" | grep '^txbytes=' | cut -d= -f2-)"
    [ -z "$name" ] && name="$mac"
    [ -z "$ip" ] && ip="-"
    local status_str access_str
    if [ "$active" = "yes" ]; then
        status_str="🟢 $(T TXT_TGBOT_CLIENT_STATUS_ACTIVE)"
    else
        status_str="⚪ $(T TXT_TGBOT_CLIENT_STATUS_INACTIVE)"
    fi
    if [ "$access" = "deny" ]; then
        access_str="🚫 $(T TXT_TGBOT_CLIENT_ACCESS_BLOCKED)"
    else
        access_str="✅ $(T TXT_TGBOT_CLIENT_ACCESS_OK)"
    fi
    printf '%s\nMAC  : %s\nIP   : %s\n%s    : %s\n%s   : %s\n%s: %s\n%s: %s' \
        "📱 ${name}" \
        "$mac" \
        "$ip" \
        "$(T TXT_TGBOT_CLIENT_ACCESS_LABEL)" "$access_str" \
        "$(T _ 'Durum' 'Status')" "$status_str" \
        "$(T _ 'Indir' 'Down')" "$(_tgbot_fmt_bytes "$rxbytes")" \
        "$(T _ 'Yukle' 'Up')" "$(_tgbot_fmt_bytes "$txbytes")"
}
# Istemci detay klavyesi
tgbot_kb_client() {
    local mac="$1"
    local access="$2"
    local mac_enc rid
    mac_enc="$(printf '%s' "$mac" | tr ':' '-')"
    rid="${TG_ROUTER_ID:-default}"
    local access_btn access_cb
    if [ "$access" = "deny" ]; then
        access_btn="✅ $(T TXT_TGBOT_CLIENT_ACCESS_PERMIT)"
        access_cb="${rid}:client_permit_${mac_enc}"
    else
        access_btn="🚫 $(T TXT_TGBOT_CLIENT_ACCESS_DENY)"
        access_cb="${rid}:client_deny_${mac_enc}"
    fi
    printf '[[{"text":"%s","callback_data":"%s"}],[{"text":"✏️ %s","callback_data":"%s:client_rename_%s"}],[{"text":"⬅️ %s","callback_data":"%s:sys_net_devices"}]]' \
        "$access_btn" "$access_cb" \
        "$(T TXT_TGBOT_CLIENT_RENAME)" "$rid" "$mac_enc" \
        "$(T TXT_TGBOT_BTN_BACK)" "$rid"
}
# Cihaz detay metni (resim 2 gibi)
tgbot_device_detail_text() {
    telegram_device_info_init >/dev/null 2>&1
    local name model fw cpu_val mem_val
    name="${TG_DEVICE_NAME:-Keenetic}"
    model="${TG_DEVICE_MODEL:-}"
    fw="$(kzm2_banner_get_firmware 2>/dev/null)"
    [ -z "$fw" ] && fw="-"
    # CPU (busybox top)
    cpu_val="$(top -bn1 2>/dev/null | awk '/CPU:/{gsub(/%/,""); print int($2+$4); exit}')"
    [ -z "$cpu_val" ] && cpu_val="-"
    # MEM
    mem_val="$(free 2>/dev/null | awk '/Mem:/{printf "%d%%", ($3/$2)*100}')"
    [ -z "$mem_val" ] && mem_val="-"
    # KeenDNS
    local kdns_str kdns_raw kdns_name kdns_domain
    kdns_raw="$(LD_LIBRARY_PATH= ndmc -c 'show ndns' 2>/dev/null)"
    kdns_name="$(printf '%s' "$kdns_raw" | awk '/name:/{print $2; exit}')"
    kdns_domain="$(printf '%s' "$kdns_raw" | awk '/domain:/{print $2; exit}')"
    if [ -n "$kdns_name" ] && [ -n "$kdns_domain" ]; then
        kdns_str="${kdns_name}.${kdns_domain}"
    else
        kdns_str="-"
    fi
    # WAN trafik (boot'tan bu yana)
    local wan_if traffic_str
    wan_if="$(cat /opt/zapret2/wan_if 2>/dev/null)"
    traffic_str="$(_tgbot_wan_traffic "$wan_if")"
    # Cikti
    local out
    out="📡 $(T TXT_TG_DEVICE_LABEL) : ${name}"
    [ -n "$model" ] && out="${out} (${model})"
    out="${out}
🌐 KeenDNS : ${kdns_str}
🖥 $(T _ 'Surum' 'Release') : ${fw}
💻 CPU : ${cpu_val}%  MEM: ${mem_val}

$(T TXT_TGBOT_DEVICE_TRAFFIC_LABEL)
→ $traffic_str"
    printf '%s' "$out"
}
# System status text
tgbot_status_text() {
    local zapret_st profile_name wan_if cpu_val ram_val disk_val uptime_val hm_st tgbot_st
    # Device info header
    telegram_device_info_init >/dev/null 2>&1
    # DPI profili
    local _cur_profile
    _cur_profile="$(get_dpi_profile 2>/dev/null)"
    if [ -n "$_cur_profile" ]; then
        profile_name="$(T dpi_pname "$(dpi_profile_name_tr "$_cur_profile" 2>/dev/null)" "$(dpi_profile_name_en "$_cur_profile" 2>/dev/null)")"
    fi
    [ -z "$profile_name" ] && profile_name="$(T TXT_TGBOT_STATUS_UNKNOWN)"
    # WAN arayuzu
    wan_if="$(cat /opt/zapret2/wan_if 2>/dev/null)"
    [ -z "$wan_if" ] && wan_if="$(T _ 'Tum' 'All')"
    # CPU / RAM / Disk / Uptime
    cpu_val="$(top -bn1 2>/dev/null | awk '/CPU:/{gsub(/%/,""); print int($2+$4); exit}')"
    [ -z "$cpu_val" ] && cpu_val="-"
    ram_val="$(free 2>/dev/null | awk '/Mem:/{printf "%d/%d MB", ($3/1024), ($2/1024)}')"
    [ -z "$ram_val" ] && ram_val="-"
    disk_val="$(df -P /opt 2>/dev/null | awk 'NR==2{print $5}')"
    [ -z "$disk_val" ] && disk_val="-"
    uptime_val="$(uptime 2>/dev/null | sed 's/.*up //' | cut -d',' -f1)"
    [ -z "$uptime_val" ] && uptime_val="-"
    # Disk sagligi
    local disk_health_val
    kzm2_disk_health_check
    case "$_dh_reason" in
        ro)             disk_health_val="$(T _ 'Salt okunur!' 'Read-only!')" ;;
        io_error)       disk_health_val="$(T _ 'I/O Hatasi!' 'I/O Error!')" ;;
        journal_error)  disk_health_val="$(T TXT_HM_DISK_HEALTH_JOURNAL)" ;;
        usb_disconnect) disk_health_val="$(T TXT_HM_DISK_HEALTH_USBDISCON)" ;;
        usb_proto)      disk_health_val="$(T TXT_HM_DISK_HEALTH_USBPROTO)" ;;
        *)              disk_health_val="OK" ;;
    esac
    # HealthMon
    if [ -f /tmp/kzm2_healthmon.pid ] && kill -0 "$(cat /tmp/kzm2_healthmon.pid 2>/dev/null)" 2>/dev/null; then
        hm_st="$(T TXT_TGBOT_STATUS_RUNNING)"
    else
        hm_st="$(T TXT_TGBOT_STATUS_STOPPED)"
    fi
    # Telegram bot
    local _tgpid
    _tgpid="$(cat /tmp/kzm2_telegram_bot.pid 2>/dev/null)"
    if [ -n "$_tgpid" ] && kill -0 "$_tgpid" 2>/dev/null; then
        tgbot_st="$(T TXT_TGBOT_STATUS_RUNNING)"
    else
        tgbot_st="$(T TXT_TGBOT_STATUS_STOPPED)"
    fi
    # Zapret2
    if is_zapret2_running 2>/dev/null; then
        zapret_st="$(T TXT_TGBOT_STATUS_RUNNING)"
    else
        zapret_st="$(T TXT_TGBOT_STATUS_STOPPED)"
    fi
    # KeenDNS
    local keendns_val
    local _kdns_raw
    _kdns_raw="$(LD_LIBRARY_PATH= ndmc -c 'show ndns' 2>/dev/null)"
    if [ -n "$_kdns_raw" ]; then
        local _kdns_name _kdns_domain _kdns_access
        _kdns_name="$(printf '%s\n' "$_kdns_raw" | awk '/name:/{print $2; exit}')"
        _kdns_domain="$(printf '%s\n' "$_kdns_raw" | awk '/domain:/{print $2; exit}')"
        _kdns_access="$(printf '%s\n' "$_kdns_raw" | awk '/access:/{print $2; exit}')"
        if [ -n "$_kdns_name" ] && [ -n "$_kdns_domain" ]; then
            keendns_val="${_kdns_name}.${_kdns_domain} | ${_kdns_access:-$(T TXT_TGBOT_STATUS_UNKNOWN)}"
        fi
    fi
    [ -z "$keendns_val" ] && keendns_val="$(T TXT_TGBOT_STATUS_UNKNOWN)"
    # Versiyon
    local kzm_ver zapret_ver
    kzm_ver="$(kzm2_get_installed_script_version 2>/dev/null)"
    [ -z "$kzm_ver" ] && kzm_ver="$SCRIPT_VERSION"
    zapret_ver="$(kzm2_get_zapret_version 2>/dev/null)"
    [ -z "$zapret_ver" ] && zapret_ver="$(T TXT_TGBOT_STATUS_UNKNOWN)"
    printf "📡 $(T TXT_TG_DEVICE_LABEL) : %s\n🏠 $(T TXT_TG_LAN_LABEL) : %s\n🌍 $(T TXT_TG_WAN_LABEL) : %s\n🔧 $(T TXT_TG_MODEL_LABEL) : %s\n\n" \
        "${TG_DEVICE_NAME:-$(T TXT_TGBOT_STATUS_UNKNOWN)}" \
        "${TG_DEVICE_LAN_IP:-$(T TXT_TGBOT_STATUS_UNKNOWN)}" \
        "${TG_DEVICE_WAN_IP:-$(T TXT_TGBOT_STATUS_UNKNOWN)}" \
        "${TG_DEVICE_MODEL:-$(T TXT_TGBOT_STATUS_UNKNOWN)}"
    printf "📊 DPI : %s\n💻 CPU : %s%% | RAM: %s\n💾 Disk : %s | Uptime: %s\n🩺 Disk Sagligi : %s\n❤️ HMon : %s\n🤖 TGBot : %s\n⚡ Zapret2 : %s\n🌐 KeenDNS : %s\n🔌 WAN : %s\n📦 KZM2 : %s | Zapret2: %s" \
        "$profile_name" \
        "$cpu_val" "$ram_val" \
        "$disk_val" "$uptime_val" \
        "$disk_health_val" \
        "$hm_st" \
        "$tgbot_st" \
        "$zapret_st" \
        "$keendns_val" \
        "$wan_if" \
        "$kzm_ver" "$zapret_ver"
}
# Handle callback query action
# $1=callback_data, $2=chat_id, $3=message_id, $4=callback_id
tgbot_handle_callback() {
    local cb_data="$1"
    local chat_id="$2"
    local msg_id="$3"
    local cb_id="$4"
    # Router ID prefix kontrolu: "rid:action" formatinda
    local cb_rid cb_action
    cb_rid="$(printf '%s' "$cb_data" | cut -d':' -f1)"
    cb_action="$(printf '%s' "$cb_data" | cut -d':' -f2-)"
    # Eski format (prefix yok) veya kendi ID'si degil ise yok say
    if [ -z "$cb_action" ]; then
        # prefix yok - eski format, direkt isle (geriye donuk uyumluluk)
        cb_action="$cb_rid"
    elif [ "$cb_rid" != "${TG_ROUTER_ID:-default}" ]; then
        # Baska routerin callback'i - yoksay
        tgbot_ack "$cb_id"
        return 0
    fi
    tgbot_ack "$cb_id"
    case "$cb_action" in
        menu_main)
            tgbot_edit "$chat_id" "$msg_id" \
                "${TG_ROUTER_ID} | $(T TXT_TGBOT_MENU_TITLE)" "$(tgbot_kb_main)"
            ;;
        menu_status)
            tgbot_edit "$chat_id" "$msg_id" \
                "$(tgbot_status_text)" "$(tgbot_kb_main)"
            ;;
        menu_profil)
            local _prof="$(get_dpi_profile)"
            local _orig="$(cat /opt/zapret2/dpi_profile_origin 2>/dev/null | tr -d '[:space:]')"
            local _prof_label="$(T dpi_pname2 "$(dpi_profile_name_tr "$_prof")" "$(dpi_profile_name_en "$_prof")")"
            local _orig_label
            [ "$_orig" = "auto" ] && _orig_label="$(T _ 'blockcheck otomatik' 'blockcheck auto')" || _orig_label="$(T _ 'manuel' 'manual')"
            tgbot_edit "$chat_id" "$msg_id" \
                "$(printf '%b' "$(T _ "📡 Aktif DPI Profili\n\n🎯 Profil: $_prof_label\n📌 Kaynak: $_orig_label" "📡 Active DPI Profile\n\n🎯 Profile: $_prof_label\n📌 Source: $_orig_label")")" \
                "$(tgbot_kb_profil)"
            ;;
        profil_share)
            local _prof="$(get_dpi_profile)"
            local _orig="$(cat /opt/zapret2/dpi_profile_origin 2>/dev/null | tr -d '[:space:]')"
            local _prof_label="$(T dpi_pname3 "$(dpi_profile_name_tr "$_prof")" "$(dpi_profile_name_en "$_prof")")"
            local _orig_label
            [ "$_orig" = "auto" ] && _orig_label="$(T _ 'blockcheck otomatik' 'blockcheck auto')" || _orig_label="$(T _ 'manuel' 'manual')"
            local _nfqws_opt
            _nfqws_opt="$(grep '^NFQWS2_OPT=' /opt/zapret2/config 2>/dev/null | cut -d'"' -f2)"
            tgbot_send "$chat_id" \
                "$(printf '%b' "$(T _ "📡 DPI Profil Raporu\n\n🎯 Profil: $_prof_label\n📌 Kaynak: $_orig_label\n\n📋 NFQWS2_OPT:\n$_nfqws_opt" "📡 DPI Profile Report\n\n🎯 Profile: $_prof_label\n📌 Source: $_orig_label\n\n📋 NFQWS2_OPT:\n$_nfqws_opt")")" \
                "$(tgbot_kb_main)"
            ;;
        menu_zapret)
            tgbot_edit "$chat_id" "$msg_id" \
                "$(T TXT_TGBOT_MENU_ZAPRET_TITLE)" "$(tgbot_kb_zapret)"
            ;;
        menu_kzm)
            tgbot_edit "$chat_id" "$msg_id" \
                "${TG_ROUTER_ID} | $(T TXT_TGBOT_MENU_KZM_TITLE)" "$(tgbot_kb_kzm)"
            ;;
        menu_sistem)
            telegram_device_info_init >/dev/null 2>&1
            _dev_header="$(printf '%s: %s\n%s: %s' \
                "$(T TXT_TGBOT_SISTEM_HEADER_ISIM)" "${TG_DEVICE_NAME:-Keenetic}" \
                "$(T TXT_TGBOT_SISTEM_HEADER_MODEL)" "${TG_DEVICE_MODEL:--}")"
            tgbot_edit "$chat_id" "$msg_id" \
                "$_dev_header" "$(tgbot_kb_sistem)"
            ;;
        sys_kzmlog)
            local _log_file="/tmp/kzm2_healthmon.log"
            local _log_tmp="/tmp/tgbot_kzmlog_$$.txt"
            if [ -f "$_log_file" ] && [ -s "$_log_file" ]; then
                cp "$_log_file" "$_log_tmp" 2>/dev/null
                tgbot_send_document "$chat_id" "$_log_tmp" \
                    "📋 KZM2 HealthMon Log | ${TG_ROUTER_ID:-router}"
                rm -f "$_log_tmp" 2>/dev/null
            else
                tgbot_send "$chat_id" "$(T TXT_TGBOT_NO_LOGS)" ""
            fi
            # Dosyadan sonra log menusunu ALTA taze gonder
            tgbot_send "$chat_id" \
                "$(T TXT_TGBOT_LOG_MENU_TITLE)" "$(tgbot_kb_logs)"
            ;;
        sys_syslog)
            local _syslog_tmp="/tmp/tgbot_syslog_$$.txt"
            LD_LIBRARY_PATH= ndmc -c 'show log' 2>/dev/null > "$_syslog_tmp"
            if [ -s "$_syslog_tmp" ]; then
                tgbot_send_document "$chat_id" "$_syslog_tmp" \
                    "📄 System Log | ${TG_ROUTER_ID:-router}"
            else
                tgbot_send "$chat_id" "$(T TXT_TGBOT_NO_LOGS)" ""
            fi
            rm -f "$_syslog_tmp" 2>/dev/null
            # Dosyadan sonra log menusunu ALTA taze gonder
            tgbot_send "$chat_id" \
                "$(T TXT_TGBOT_LOG_MENU_TITLE)" "$(tgbot_kb_logs)"
            ;;
        menu_logs)
            tgbot_edit "$chat_id" "$msg_id" \
                "$(T TXT_TGBOT_LOG_MENU_TITLE)" "$(tgbot_kb_logs)"
            ;;
        sys_tgbotlog)
            local _tglog_tmp="/tmp/tgbot_tgbotlog_$$.txt"
            if [ -f "$TG_BOT_LOG_FILE" ] && [ -s "$TG_BOT_LOG_FILE" ]; then
                cp "$TG_BOT_LOG_FILE" "$_tglog_tmp" 2>/dev/null
                tgbot_send_document "$chat_id" "$_tglog_tmp" \
                    "🤖 TG Bot Log | ${TG_ROUTER_ID:-router}"
                rm -f "$_tglog_tmp" 2>/dev/null
            else
                tgbot_send "$chat_id" "$(T TXT_TGBOT_NO_LOGS)" ""
            fi
            tgbot_send "$chat_id" \
                "$(T TXT_TGBOT_LOG_MENU_TITLE)" "$(tgbot_kb_logs)"
            ;;
        sys_debuglog)
            local _dbglog_tmp="/tmp/tgbot_debuglog_$$.txt"
            if [ -f "/tmp/healthmon_debug.log" ] && [ -s "/tmp/healthmon_debug.log" ]; then
                cp "/tmp/healthmon_debug.log" "$_dbglog_tmp" 2>/dev/null
                tgbot_send_document "$chat_id" "$_dbglog_tmp"                     "🐛 Debug Log | ${TG_ROUTER_ID:-router}"
                rm -f "$_dbglog_tmp" 2>/dev/null
            else
                tgbot_send "$chat_id" "$(T _ 'Debug log bulunamadi. Debug modu kapali olabilir.' 'Debug log not found. Debug mode may be disabled.')" ""
            fi
            tgbot_send "$chat_id"                 "$(T TXT_TGBOT_LOG_MENU_TITLE)" "$(tgbot_kb_logs)"
            ;;
        zap_start)
            start_zapret2 >/dev/null 2>&1
            tgbot_edit "$chat_id" "$msg_id" \
                "$(T TXT_TGBOT_ZAPRET_STARTED)" "$(tgbot_kb_zapret)"
            ;;
        zap_stop)
            stop_zapret2 1 >/dev/null 2>&1
            tgbot_edit "$chat_id" "$msg_id" \
                "$(T TXT_TGBOT_ZAPRET_STOPPED)" "$(tgbot_kb_zapret)"
            ;;
        zap_restart)
            restart_zapret2 >/dev/null 2>&1
            tgbot_edit "$chat_id" "$msg_id" \
                "$(T TXT_TGBOT_ZAPRET_RESTARTED)" "$(tgbot_kb_zapret)"
            ;;
        zap_update)
            tgbot_edit "$chat_id" "$msg_id" "$(T TXT_TGBOT_UPDATE_STARTED)" ""
            update_zapret2 >/dev/null 2>&1
            _zap_upd_rc=$?
            case "$_zap_upd_rc" in
                0) tgbot_edit "$chat_id" "$msg_id"                     "$(T TXT_TGBOT_UPDATE_DONE) ($(cat /opt/zapret2/version 2>/dev/null | tr -d '[:space:]'))" "$(tgbot_kb_zapret)" ;;
                2) tgbot_edit "$chat_id" "$msg_id"                     "$(T TXT_TGBOT_ZAP_ALREADY_UPTODATE) ($(cat /opt/zapret2/version 2>/dev/null | tr -d '[:space:]'))" "$(tgbot_kb_zapret)" ;;
                3) tgbot_edit "$chat_id" "$msg_id" \
                    "$(T TXT_TGBOT_ZAP_NEWER) ($(cat /opt/zapret2/version 2>/dev/null | tr -d '[:space:]'))" "$(tgbot_kb_zapret_force)" ;;
                *) tgbot_edit "$chat_id" "$msg_id"                     "$(T TXT_TGBOT_UPDATE_FAIL)" "$(tgbot_kb_zapret)" ;;
            esac
            ;;
        zap_force_update)
            tgbot_edit "$chat_id" "$msg_id" "$(T TXT_TGBOT_UPDATE_STARTED)" ""
            # Versiyon dosyasini gecici olarak sil ki update_zapret2 geri cekilmis surumu kursun
            _zap_ver_bak="$(cat /opt/zapret2/version 2>/dev/null)"
            rm -f /opt/zapret2/version 2>/dev/null
            if update_zapret2 >/dev/null 2>&1; then
                tgbot_edit "$chat_id" "$msg_id"                     "$(T TXT_TGBOT_UPDATE_DONE) ($(cat /opt/zapret2/version 2>/dev/null | tr -d '[:space:]'))" "$(tgbot_kb_zapret)"
            else
                # Geri yukle
                [ -n "$_zap_ver_bak" ] && printf '%s\n' "$_zap_ver_bak" > /opt/zapret2/version 2>/dev/null
                tgbot_edit "$chat_id" "$msg_id"                     "$(T TXT_TGBOT_UPDATE_FAIL)" "$(tgbot_kb_zapret)"
            fi
            ;;
        sys_kzm_update)
            tgbot_edit "$chat_id" "$msg_id" "$(T TXT_TGBOT_UPDATE_STARTED)" ""
            update_manager_script >/dev/null 2>&1
            _upd_rc=$?
            [ "$_upd_rc" = "0" ] && [ -d "$KZM2_GUI_DIR" ] && (KZM2_SKIP_LOCK=1 sh "/opt/lib/opkg/keenetic_zapret2_manager.sh" --update-gui >/dev/null 2>&1 &)
            case "$_upd_rc" in
                0) tgbot_edit "$chat_id" "$msg_id" \
                    "$(T TXT_TGBOT_UPDATE_DONE) ($(kzm2_get_installed_script_version 2>/dev/null || echo "$SCRIPT_VERSION"))" "$(tgbot_kb_kzm)" ;;
                2) tgbot_edit "$chat_id" "$msg_id" \
                    "$(T TXT_TGBOT_ALREADY_UPTODATE) ($(kzm2_get_installed_script_version 2>/dev/null || echo "$SCRIPT_VERSION"))" "$(tgbot_kb_kzm)" ;;
                *) tgbot_edit "$chat_id" "$msg_id" \
                    "$(T TXT_TGBOT_UPDATE_FAIL)" "$(tgbot_kb_kzm)" ;;
            esac
            ;;
        sys_kzm_backup)
            tgbot_edit "$chat_id" "$msg_id" "$(T TXT_BACKUP_TG_SENDING)" ""
            local _bk_base="/opt/zapret2_backups"
            local _bk_dest="${_bk_base}/zapret2_settings"
            mkdir -p "$_bk_dest" 2>/dev/null
            local _bk_ts _bk_file
            _bk_ts="$(date +%Y%m%d_%H%M%S)"
            _bk_file="${_bk_dest}/zapret2_settings_${_bk_ts}.tar.gz"
            # Mevcut dosyalari topla ve tar.gz olustur
            local _rels=""
            for _f in /opt/zapret2/config /opt/zapret2/wan_if /opt/zapret2/lang \
                      /opt/zapret2/hostlist_mode /opt/zapret2/scope_mode \
                      /opt/zapret2/ipset_clients.txt /opt/zapret2/ipset_clients_mode \
                      /opt/zapret2/dpi_profile /opt/zapret2/dpi_profile_origin \
                      /opt/zapret2/dpi_profile_params /opt/zapret2/blockcheck_auto_params \
                      /opt/zapret2/dpi_profiles \
                      /opt/etc/healthmon.conf /opt/etc/telegram.conf /opt/etc/kzm2_gui.conf \
                      /opt/zapret2/init.d/sysv/zapret2.real \
                      /opt/zapret2/init.d/sysv/custom.d/90-keenetic-client-ipset \
                      /opt/etc/init.d/S99kzm2_healthmon; do
                [ -e "$_f" ] && _rels="$_rels ${_f#/}"
            done
            for _f in /opt/zapret2/ipset/*.txt; do
                [ -e "$_f" ] && _rels="$_rels ${_f#/}"
            done
            tar -C / -czf "$_bk_file" $_rels >/dev/null 2>&1
            if [ -s "$_bk_file" ]; then
                local _bk_caption
                _bk_caption="$(T _ 'KZM2 Yedek' 'KZM2 Backup') | $(basename "$_bk_file") | $(date '+%Y-%m-%d %H:%M')"
                if tgbot_send_document "$chat_id" "$_bk_file" "$_bk_caption"; then
                    tgbot_send "$chat_id" "$(T TXT_TGBOT_KZM_BACKUP_OK)" "$(tgbot_kb_kzm)"
                else
                    tgbot_send "$chat_id" "$(T TXT_TGBOT_KZM_BACKUP_FAIL)" "$(tgbot_kb_kzm)"
                fi
            else
                rm -f "$_bk_file" 2>/dev/null
                tgbot_send "$chat_id" "$(T TXT_TGBOT_KZM_BACKUP_FAIL)" "$(tgbot_kb_kzm)"
            fi
            ;;
        sys_net_devices)
            local _nd_total
            _nd_total="$(LD_LIBRARY_PATH= ndmc -c 'show ip hotspot' 2>/dev/null | grep -c 'active: yes')"
            [ -z "$_nd_total" ] && _nd_total=0
            tgbot_edit "$chat_id" "$msg_id" \
                "$(T TXT_TGBOT_NET_DEVICES_TITLE) (${_nd_total})" "$(tgbot_net_devices_kb 0)"
            ;;
        sys_clients_*)
            local _pg_offset
            _pg_offset="$(printf '%s' "$cb_action" | sed 's/sys_clients_//')"
            _pg_offset="${_pg_offset:-0}"
            local _nd_total2
            _nd_total2="$(LD_LIBRARY_PATH= ndmc -c 'show ip hotspot' 2>/dev/null | grep -c 'active: yes')"
            [ -z "$_nd_total2" ] && _nd_total2=0
            tgbot_edit "$chat_id" "$msg_id" \
                "$(T TXT_TGBOT_NET_DEVICES_TITLE) (${_nd_total2})" "$(tgbot_net_devices_kb "$_pg_offset")"
            ;;
        sys_wifi)
            local _wifi_kb _wifi_title _ts
            _wifi_kb="$(tgbot_wifi_kb)"
            # Segment sayisi: noop olmayan wifi buton satirlari
            local _wifi_cnt
            _wifi_cnt="$(printf '%s' "$_wifi_kb" | grep -o '"callback_data":"[^"]*:wifi_' | grep -c .)"
            # Title: her zaman farkli olmali (timestamp) - "message is not modified" hatasini onler
            _ts="$(date +%H:%M 2>/dev/null)"
            _wifi_title="$(T TXT_TGBOT_WIFI_TITLE) (${_wifi_cnt}) ${_ts}"
            tgbot_edit "$chat_id" "$msg_id" "$_wifi_title" "$_wifi_kb"
            ;;
        noop)
            # ack zaten yukarda gonderildi, ek islem yok
            ;;
        wifi_on_*|wifi_off_*)
            local _wf_safe _wf_id _wf_cmd
            if printf '%s' "$cb_action" | grep -q '^wifi_on_'; then
                _wf_safe="${cb_action#wifi_on_}"
                _wf_cmd="up"
            else
                _wf_safe="${cb_action#wifi_off_}"
                _wf_cmd="down"
            fi
            # Gercek ndmc ID bul (WifiMaster0/AccessPoint1 gibi - rename edilmis olabilir)
            _wf_id="$(LD_LIBRARY_PATH= ndmc -c "show interface ${_wf_safe}" 2>/dev/null \
                | grep "^[[:space:]]*id:" | sed "s/.*id:[[:space:]]*//" | tr -d " ")"
            [ -z "$_wf_id" ] && _wf_id="$_wf_safe"
            LD_LIBRARY_PATH= ndmc -c "interface ${_wf_id} ${_wf_cmd}" >/dev/null 2>&1
            LD_LIBRARY_PATH= ndmc -c "system configuration save" >/dev/null 2>&1
            sleep 2
            local _wf_kb _wf_cnt _wf_ts
            _wf_kb="$(tgbot_wifi_kb)"
            _wf_cnt="$(printf '%s' "$_wf_kb" | grep -o '"callback_data":"[^"]*:wifi_' | grep -c .)"
            _wf_ts="$(date +%H:%M 2>/dev/null)"
            tgbot_send "$chat_id" \
                "$(T TXT_TGBOT_WIFI_TITLE) (${_wf_cnt}) ${_wf_ts}" "$_wf_kb"
            ;;
        sys_device_detail)
            tgbot_edit "$chat_id" "$msg_id" \
                "$(tgbot_device_detail_text)" "$(tgbot_kb_device)"
            ;;
        sys_client_*)
            local _cl_mac_enc _cl_mac _cl_info _cl_access
            _cl_mac_enc="${cb_action#sys_client_}"
            _cl_mac="$(printf '%s' "$_cl_mac_enc" | tr '-' ':')"
            _cl_info="$(_tgbot_parse_client "$_cl_mac")"
            _cl_access="$(printf '%s\n' "$_cl_info" | grep '^access=' | cut -d= -f2-)"
            [ -z "$_cl_access" ] && _cl_access="permit"
            tgbot_edit "$chat_id" "$msg_id" \
                "$(tgbot_client_detail_text "$_cl_mac")" \
                "$(tgbot_kb_client "$_cl_mac" "$_cl_access")"
            ;;
        client_deny_*)
            local _cd_mac_enc _cd_mac
            _cd_mac_enc="${cb_action#client_deny_}"
            _cd_mac="$(printf '%s' "$_cd_mac_enc" | tr '-' ':')"
            LD_LIBRARY_PATH= ndmc -c "ip hotspot host ${_cd_mac} deny" >/dev/null 2>&1
            LD_LIBRARY_PATH= ndmc -c "system configuration save" >/dev/null 2>&1
            local _cd_info _cd_access
            _cd_info="$(_tgbot_parse_client "$_cd_mac")"
            _cd_access="$(printf '%s\n' "$_cd_info" | grep '^access=' | cut -d= -f2-)"
            [ -z "$_cd_access" ] && _cd_access="deny"
            tgbot_edit "$chat_id" "$msg_id" \
                "$(tgbot_client_detail_text "$_cd_mac")" \
                "$(tgbot_kb_client "$_cd_mac" "$_cd_access")"
            ;;
        client_permit_*)
            local _cp_mac_enc _cp_mac
            _cp_mac_enc="${cb_action#client_permit_}"
            _cp_mac="$(printf '%s' "$_cp_mac_enc" | tr '-' ':')"
            LD_LIBRARY_PATH= ndmc -c "ip hotspot host ${_cp_mac} permit" >/dev/null 2>&1
            LD_LIBRARY_PATH= ndmc -c "system configuration save" >/dev/null 2>&1
            local _cpr_info _cpr_access
            _cpr_info="$(_tgbot_parse_client "$_cp_mac")"
            _cpr_access="$(printf '%s\n' "$_cpr_info" | grep '^access=' | cut -d= -f2-)"
            [ -z "$_cpr_access" ] && _cpr_access="permit"
            tgbot_edit "$chat_id" "$msg_id" \
                "$(tgbot_client_detail_text "$_cp_mac")" \
                "$(tgbot_kb_client "$_cp_mac" "$_cpr_access")"
            ;;
        client_rename_*)
            local _cr_mac_enc _cr_mac
            _cr_mac_enc="${cb_action#client_rename_}"
            _cr_mac="$(printf '%s' "$_cr_mac_enc" | tr '-' ':')"
            # Pending state kaydet
            printf '%s\n' "rename:${_cr_mac}" > "/tmp/tgbot_pending_${chat_id}"
            tgbot_send "$chat_id" "$(T TXT_TGBOT_CLIENT_RENAME_PROMPT)" ""
            ;;
        sys_selftest)
            local _st_tmp="/tmp/tgbot_selftest_$$.txt" _st_script
            _st_script="$(kzm2_resolve_script_path)"
            if [ ! -f "$_st_script" ]; then
                printf 'KZM2 script not found: %s\n' "$_st_script" > "$_st_tmp"
                tgbot_send_document "$chat_id" "$_st_tmp" "❌ Selftest FAIL | ${TG_ROUTER_ID:-router}"
                tgbot_send "$chat_id" "$(T TXT_TGBOT_SELFTEST_FAIL)" "$(tgbot_kb_device)"
                rm -f "$_st_tmp" 2>/dev/null
                break
            fi
            sh "$_st_script" --self-test > "$_st_tmp" 2>&1
            _st_rc=$?
            if [ "$_st_rc" -eq 0 ]; then
                tgbot_send_document "$chat_id" "$_st_tmp" \
                    "✅ Selftest PASS | ${TG_ROUTER_ID:-router}"
                tgbot_send "$chat_id" "$(T TXT_TGBOT_SELFTEST_PASS)" "$(tgbot_kb_device)"
            elif [ "$_st_rc" -eq 2 ]; then
                tgbot_send_document "$chat_id" "$_st_tmp" \
                    "⚠️ Selftest WARN | ${TG_ROUTER_ID:-router}"
                tgbot_send "$chat_id" "$(T TXT_TGBOT_SELFTEST_WARN)" "$(tgbot_kb_device)"
            else
                tgbot_send_document "$chat_id" "$_st_tmp" \
                    "❌ Selftest FAIL | ${TG_ROUTER_ID:-router}"
                tgbot_send "$chat_id" "$(T TXT_TGBOT_SELFTEST_FAIL)" "$(tgbot_kb_device)"
            fi
            rm -f "$_st_tmp" 2>/dev/null
            ;;
        sys_reboot_confirm)
            tgbot_edit "$chat_id" "$msg_id" \
                "$(T TXT_TGBOT_BTN_REBOOT)?" "$(tgbot_kb_reboot_confirm)"
            ;;
        sys_reboot_do)
            tgbot_edit "$chat_id" "$msg_id" "$(T TXT_TGBOT_REBOOT_SENT)" ""
            sleep 2
            LD_LIBRARY_PATH= ndmc -c "system reboot" >/dev/null 2>&1 || true
            ;;
        sys_pingcheck_off)
            local _pc_wan _pc_prof
            _pc_prof="$(LD_LIBRARY_PATH= ndmc -c "show ping-check" 2>/dev/null | \
                awk '/profile:/{prof=$NF} /host:/ && prof!="default"{print prof; exit}')"
            _pc_wan="$(LD_LIBRARY_PATH= ndmc -c "show ping-check" 2>/dev/null | \
                awk '/name:/{print $NF; exit}')"
            if ! LD_LIBRARY_PATH= ndmc -c "show ping-check" 2>/dev/null | grep -q "interface:"; then
                tgbot_edit "$chat_id" "$msg_id" "$(T TXT_TGBOT_PINGCHECK_ALREADY_OFF)" "$(tgbot_kb_sistem)"
            else
                echo "$_pc_wan $_pc_prof" > /opt/etc/pingcheck_saved 2>/dev/null
                LD_LIBRARY_PATH= ndmc -c "interface $_pc_wan no ping-check profile" >/dev/null 2>&1
                LD_LIBRARY_PATH= ndmc -c "system configuration save" >/dev/null 2>&1
                tgbot_edit "$chat_id" "$msg_id" "$(T TXT_TGBOT_PINGCHECK_OFF_OK)" "$(tgbot_kb_sistem)"
            fi
            ;;
        sys_pingcheck_on)
            local _pc_saved _pc_wan _pc_prof
            _pc_saved="$(cat /opt/etc/pingcheck_saved 2>/dev/null)"
            _pc_wan="$(printf '%s' "$_pc_saved" | awk '{print $1}')"
            _pc_prof="$(printf '%s' "$_pc_saved" | awk '{print $2}')"
            if [ -z "$_pc_wan" ] || [ -z "$_pc_prof" ]; then
                tgbot_edit "$chat_id" "$msg_id" "$(T TXT_TGBOT_PINGCHECK_FAIL)" "$(tgbot_kb_sistem)"
            else
                LD_LIBRARY_PATH= ndmc -c "interface $_pc_wan ping-check profile $_pc_prof" >/dev/null 2>&1
                LD_LIBRARY_PATH= ndmc -c "system configuration save" >/dev/null 2>&1
                rm -f /opt/etc/pingcheck_saved 2>/dev/null
                tgbot_edit "$chat_id" "$msg_id" "$(T TXT_TGBOT_PINGCHECK_ON_OK)" "$(tgbot_kb_sistem)"
            fi
            ;;
        sys_wan_reset)
            tgbot_edit "$chat_id" "$msg_id" \
                "$(T TXT_TGBOT_WAN_RESET_SELECT)" "$(tgbot_kb_wan_reset_time)"
            ;;
        wan_rc_*)
            local _wr_min
            _wr_min="${cb_action#wan_rc_}"
            tgbot_edit "$chat_id" "$msg_id" \
                "$(tpl_render "$(T TXT_TGBOT_WAN_RESET_CONFIRM)" MIN "$_wr_min")" \
                "$(tgbot_kb_wan_reset_confirm "$_wr_min")"
            ;;
        wan_rd_*)
            local _wd_min _wd_ndm _wd_sec
            _wd_min="${cb_action#wan_rd_}"
            _wd_ndm="$(LD_LIBRARY_PATH= ndmc -c 'show interface' 2>/dev/null | awk '
                BEGIN{RS="Interface, name = "; FS="\n"}
                NR>1{
                    id=""; role=""
                    for(i=1;i<=NF;i++){
                        if($i ~ /^[[:space:]]*id:/){v=$i; sub(/.*id:[[:space:]]*/,"",v); gsub(/[[:space:]]/,"",v); id=v}
                        if($i ~ /^[[:space:]]*role:[[:space:]]*inet/){role="inet"}
                    }
                    if(role=="inet" && id!=""){print id; exit}
                }
            ')"
            if [ -z "$_wd_ndm" ]; then
                tgbot_edit "$chat_id" "$msg_id" \
                    "$(T TXT_TGBOT_WAN_NO_IF)" "$(tgbot_kb_wan_reset_time)"
            else
                tgbot_edit "$chat_id" "$msg_id" \
                    "$(tpl_render "$(T TXT_TGBOT_WAN_RESET_STARTED)" MIN "$_wd_min")" ""
                _wd_sec=$(( _wd_min * 60 ))
                ( LD_LIBRARY_PATH= ndmc -c "interface ${_wd_ndm} down" >/dev/null 2>&1
                  sleep "$_wd_sec"
                  LD_LIBRARY_PATH= ndmc -c "interface ${_wd_ndm} up" >/dev/null 2>&1
                ) &
            fi
            ;;
    esac
}
# setMyCommands - Telegram komut listesini ayarla
tgbot_set_commands() {
    local _token="$1"
    local _cmds
    _cmds='[{"command":"start","description":"Ana menuyu ac"},{"command":"durum","description":"Sistem durumunu goster"},{"command":"profil","description":"Aktif DPI profilini goster"},{"command":"zapret2","description":"Zapret2 yonetimi"},{"command":"sistem","description":"Sistem ve router"},{"command":"kzm2","description":"KZM2 yonetimi"},{"command":"loglar","description":"Log goruntule"},{"command":"help","description":"Yardim"}]'
    local _sc_result
    _sc_result="$(curl -fsSL -X POST "https://api.telegram.org/bot${_token}/setMyCommands" \
        -H "Content-Type: application/json" \
        -d "{\"commands\":${_cmds}}" 2>&1)"
    printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') | tgbot | setMyCommands: ${_sc_result}" >> "$TG_BOT_LOG_FILE"
}
# Main bot polling loop
telegram_bot_daemon() {
    telegram_load_config || return 1
    [ "${TG_BOT_ENABLE:-0}" != "1" ] && return 1
    local offset=0
    local raw ids update_id blk
    local cb_id cb_data cb_chat cb_msg_id msg_chat msg_text
    printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') | tgbot | started" >> "$TG_BOT_LOG_FILE"
    # Eski pending dosyalarini temizle
    rm -f /tmp/tgbot_pending_* 2>/dev/null
    tgbot_set_commands "$TG_BOT_TOKEN"
    while true; do
        load_lang
        # getUpdates
        _tgbot_api "getUpdates" \
            "{\"offset\":${offset},\"timeout\":${TG_BOT_POLL_SEC:-5},\"allowed_updates\":[\"message\",\"callback_query\"]}"
        if [ ! -s "$_TGBOT_TMP" ]; then
            sleep "${TG_BOT_POLL_SEC:-5}"
            continue
        fi
        raw="$(cat "$_TGBOT_TMP" 2>/dev/null)"
        # ok:true kontrolu
        printf '%s' "$raw" | grep -q '"ok":true' || {
            printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') | tgbot | api error: $(printf '%s' "$raw" | head -c 120)" >> "$TG_BOT_LOG_FILE"
            # 409 Conflict = ayni token ile baska getUpdates calisiyor.
            # 60 saniye bekle, Telegram session'i kapansin, sonra devam et.
            if printf '%s' "$raw" | grep -q '"error_code":409'; then
                printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') | tgbot | conflict_409 sleeping 60s pid=$$" >> "$TG_BOT_LOG_FILE"
                sleep 60
                continue
            fi
            sleep "${TG_BOT_POLL_SEC:-5}"
            continue
        }
        # update_id listesi
        ids="$(printf '%s' "$raw" | grep -o '"update_id":[0-9]*' | sed 's/"update_id"://')"
        [ -z "$ids" ] && { sleep "${TG_BOT_POLL_SEC:-5}"; continue; }
        # Tum newline'lari kaldir - tek satir yap
        raw="$(printf '%s' "$raw" | tr -d '\n\r')"
        for update_id in $ids; do
            offset=$((update_id + 1))
            # Bu update'e ait bolumu kes
            # update_id sonrasindaki ilk 800 karakteri al
            blk="$(printf '%s' "$raw" | sed "s/.*\"update_id\":${update_id}//" | cut -c1-2000)"
            # Tip: callback_query
            if printf '%s' "$blk" | grep -q '"callback_query"'; then
                cb_id="$(printf '%s' "$blk" | grep -o '"id":"[0-9]*"' | head -1 | cut -d'"' -f4)"
                cb_data="$(printf '%s' "$blk" | grep -o '"data":"[^"]*"' | tail -1 | cut -d'"' -f4)"
                cb_chat="$(printf '%s' "$blk" | grep -o '"chat":{"id":[0-9-]*' | head -1 | sed 's/.*://')"
                cb_msg_id="$(printf '%s' "$blk" | grep -o '"message_id":[0-9]*' | head -1 | sed 's/.*://')"
                printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') | tgbot | cb data=$cb_data chat=$cb_chat msg=$cb_msg_id" >> "$TG_BOT_LOG_FILE"
                if [ -n "$cb_chat" ] && [ "$cb_chat" = "$TG_CHAT_ID" ] && [ -n "$cb_data" ]; then
                    local _last_cb_file="/tmp/tgbot_last_cbid"
                    local _last_cb="$(cat "$_last_cb_file" 2>/dev/null)"
                    if [ "$cb_id" = "$_last_cb" ]; then
                        printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') | tgbot | duplicate cb_id=$cb_id skipped" >> "$TG_BOT_LOG_FILE"
                    else
                        printf '%s' "$cb_id" > "$_last_cb_file"
                        tgbot_handle_callback "$cb_data" "$cb_chat" "$cb_msg_id" "$cb_id"
                    fi
                fi
            # Tip: message
            elif printf '%s' "$blk" | grep -q '"message"'; then
                msg_chat="$(printf '%s' "$blk" | grep -o '"chat":{"id":[0-9-]*' | head -1 | sed 's/.*://')"
                msg_text="$(printf '%s' "$blk" | grep -o '"text":"[^"]*"' | head -1 | cut -d'"' -f4)"
                printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') | tgbot | msg text=$msg_text chat=$msg_chat" >> "$TG_BOT_LOG_FILE"
                if [ -n "$msg_chat" ] && [ "$msg_chat" = "$TG_CHAT_ID" ]; then
                    # Bekleyen islem var mi kontrol et (ornegin isim degistirme)
                    local _pending_file="/tmp/tgbot_pending_${msg_chat}"
                    if [ -f "$_pending_file" ]; then
                        local _pending
                        _pending="$(cat "$_pending_file" 2>/dev/null)"
                        rm -f "$_pending_file" 2>/dev/null
                        case "$_pending" in
                            rename:*)
                                local _rn_mac="${_pending#rename:}"
                                if [ "$msg_text" = "/iptal" ] || [ "$msg_text" = "/cancel" ]; then
                                    tgbot_send "$msg_chat" "$(T TXT_TGBOT_CLIENT_RENAME_CANCEL)" ""
                                else
                                    local _rn_name="$msg_text"
                                    # Telegram JSON unicode escape (\u0131 gibi) UTF-8'e donustur
                                    _rn_name="$(printf '%s' "$_rn_name" | awk '{
                                        s = $0
                                        result = ""
                                        while (match(s, /\\u[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]/)) {
                                            result = result substr(s, 1, RSTART-1)
                                            hex = substr(s, RSTART+2, 4)
                                            code = 0
                                            for (i=1; i<=4; i++) {
                                                c = substr(hex, i, 1)
                                                if (c >= "0" && c <= "9") v = c - "0"
                                                else if (c >= "a" && c <= "f") v = 10 + index("abcdef", c) - 1
                                                else if (c >= "A" && c <= "F") v = 10 + index("ABCDEF", c) - 1
                                                code = code * 16 + v
                                            }
                                            if (code < 128) {
                                                result = result sprintf("%c", code)
                                            } else if (code < 2048) {
                                                b1 = 192 + int(code/64)
                                                b2 = 128 + (code % 64)
                                                result = result sprintf("%c%c", b1, b2)
                                            } else {
                                                b1 = 224 + int(code/4096)
                                                b2 = 128 + int((code%4096)/64)
                                                b3 = 128 + (code % 64)
                                                result = result sprintf("%c%c%c", b1, b2, b3)
                                            }
                                            s = substr(s, RSTART+6)
                                        }
                                        print result s
                                    }')"
                                    # Bos kaldiysa hata ver
                                    if [ -z "$_rn_name" ]; then
                                        tgbot_send "$msg_chat" "$(T _ 'Gecersiz isim.' 'Invalid name.')" ""
                                        continue
                                    fi
                                    printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') | tgbot | rename mac=$_rn_mac name=$_rn_name" >> "$TG_BOT_LOG_FILE"
                                    local _rn_out
                                    _rn_out="$(LD_LIBRARY_PATH= ndmc -c "known host \"${_rn_name}\" ${_rn_mac}" 2>&1)"
                                    printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') | tgbot | rename ndmc: $_rn_out" >> "$TG_BOT_LOG_FILE"
                                    LD_LIBRARY_PATH= ndmc -c "system configuration save" >/dev/null 2>&1
                                    local _rn_info _rn_access
                                    _rn_info="$(_tgbot_parse_client "$_rn_mac")"
                                    _rn_access="$(printf '%s\n' "$_rn_info" | grep '^access=' | cut -d= -f2-)"
                                    [ -z "$_rn_access" ] && _rn_access="permit"
                                    tgbot_send "$msg_chat" \
                                        "$(T TXT_TGBOT_CLIENT_RENAME_DONE)
$(tgbot_client_detail_text "$_rn_mac")" \
                                        "$(tgbot_kb_client "$_rn_mac" "$_rn_access")"
                                fi
                                ;;
                        esac
                        continue
                    fi
                    case "$msg_text" in
                        /start|/menu)
                            tgbot_send "$msg_chat" \
                                "${TG_ROUTER_ID} | $(T TXT_TGBOT_MENU_TITLE)" \
                                "$(tgbot_kb_main)"
                            ;;
                        /durum|/status)
                            tgbot_send "$msg_chat" \
                                "$(tgbot_status_text)" \
                                "$(tgbot_kb_main)"
                            ;;
                        /profil|/profile)
                            local _prof="$(get_dpi_profile)"
                            local _orig="$(cat /opt/zapret2/dpi_profile_origin 2>/dev/null | tr -d '[:space:]')"
                            local _prof_label="$(T dpi_prof_label "$(dpi_profile_name_tr "$_prof")" "$(dpi_profile_name_en "$_prof")")"
                            local _orig_label
                            [ "$_orig" = "auto" ] && _orig_label="$(T _ 'blockcheck otomatik' 'blockcheck auto')" || _orig_label="$(T _ 'manuel' 'manual')"
                            tgbot_send "$msg_chat" \
                                "$(printf '%b' "$(T _ "📡 Aktif DPI Profili\n\n🎯 Profil: $_prof_label\n📌 Kaynak: $_orig_label" "📡 Active DPI Profile\n\n🎯 Profile: $_prof_label\n📌 Source: $_orig_label")")" \
                                "$(tgbot_kb_profil)"
                            ;;
                        /zapret)
                            tgbot_send "$msg_chat" \
                                "$(T TXT_TGBOT_BTN_ZAPRET)" \
                                "$(tgbot_kb_zapret)"
                            ;;
                        /sistem|/system)
                            tgbot_send "$msg_chat" \
                                "$(T TXT_TGBOT_BTN_SYSTEM)" \
                                "$(tgbot_kb_sistem)"
                            ;;
                        /kzm|/kzm2)
                            tgbot_send "$msg_chat" \
                                "$(T TXT_TGBOT_BTN_KZM)" \
                                "$(tgbot_kb_kzm)"
                            ;;
                        /loglar|/logs)
                            tgbot_send "$msg_chat" \
                                "$(T TXT_TGBOT_LOG_MENU_TITLE)" \
                                "$(tgbot_kb_logs)"
                            ;;
                        /help|/yardim)
                            tgbot_send "$msg_chat" \
                                "$(T _ '📖 KZM2 Yardim
📊 /durum — Sistemin anlik durumu
  Zapret2, HealthMon, WAN, IP bilgilerini gosterir.
📡 /profil — Aktif DPI profilini goster
  Hangi DPI profilinin calistigini ve kaynagini gosterir.
🔧 /zapret2 — Zapret2 yonetimi
  Zapret2i baslat, durdur, yeniden baslat veya guncelle.
  DPI tabanli internet kisitlamalarini asmak icin kullanilir.
⚙️ /sistem — Sistem ve router
  Bagli cihazlari gor, WiFi ac/kapat, routeri yeniden baslat.
🛠️ /kzm2 — KZM2 yonetimi
  Betigi guncelle, self-test calistir.
📋 /loglar — Log goruntulemek
  KZM2 ve sistem loglarini Telegramdan oku.
💡 Ipucu: Butonlara basarak da tum menulere ulasabilirsin.
  Komutlar sadece hizli erisim icindir.' '📖 KZM2 Help
📊 /durum — Live system status
  Shows Zapret2, HealthMon, WAN and IP info.
📡 /profil — Show active DPI profile
  Shows which DPI profile is active and its source.
🔧 /zapret2 — Zapret2 management
  Start, stop, restart or update Zapret2.
  Used to bypass DPI-based internet restrictions.
⚙️ /sistem — System and router
  View connected devices, toggle WiFi, reboot router.
🛠️ /kzm2 — KZM2 management
  Update the script, run self-test.
📋 /loglar — View logs
  Read KZM2 and system logs from Telegram.
💡 Tip: You can also use the buttons to access all menus.
  Commands are just for quick access.')" \
                                ""
                            ;;
                    esac
                fi
            fi
        done
        # long-poll timeout handles delay, no extra sleep needed
    done
}
telegram_bot_start() {
    telegram_load_config || { print_status FAIL "$(T TXT_TGBOT_BOT_NOT_CONFIG)"; return 1; }
    [ "${TG_BOT_ENABLE:-0}" != "1" ] && { print_status WARN "$(T TXT_TGBOT_BOT_NOT_CONFIG)"; return 1; }
    # Baslamadan once eski/duplicate daemonlari temizle. 409 Conflict ve cift mesajin ana sebebi budur.
    telegram_bot_stop >/dev/null 2>&1 || true
    rm -rf /tmp/kzm2_telegram_daemon.lock 2>/dev/null
    sleep 1
    if command -v nohup >/dev/null 2>&1; then
        nohup "$0" --telegram-daemon </dev/null >>"$TG_BOT_LOG_FILE" 2>&1 &
    else
        "$0" --telegram-daemon </dev/null >>"$TG_BOT_LOG_FILE" 2>&1 &
    fi
    echo $! > "$TG_BOT_PID_FILE"
    sleep 1
    local _real_pid
    _real_pid="$(ps 2>/dev/null | awk '/--telegram-daemon/ && !/awk/{print $1}' | tail -1)"
    [ -n "$_real_pid" ] && echo "$_real_pid" > "$TG_BOT_PID_FILE"
    local _pid_show
    _pid_show="$(cat "$TG_BOT_PID_FILE" 2>/dev/null)"
    print_status PASS "$(T TXT_TGBOT_BOT_STARTED)${_pid_show:+ (PID: $_pid_show)}"
}
# Bot'u durdur
telegram_bot_stop() {
    if [ -f "$TG_BOT_PID_FILE" ]; then
        local pid
        pid="$(cat "$TG_BOT_PID_FILE" 2>/dev/null)"
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null || true
            sleep 1
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
        fi
        rm -f "$TG_BOT_PID_FILE" 2>/dev/null
    fi
    # PID dosyasi disinda kalan tum --telegram-daemon processleri oldur
    ps 2>/dev/null | grep -- '--telegram-daemon' | grep -v grep | awk '{print $1}' | \
        while read -r _p; do [ -n "$_p" ] && kill -9 "$_p" 2>/dev/null || true; done
    rm -rf /tmp/kzm2_telegram_daemon.lock 2>/dev/null
    # Process gercekten olene kadar bekle (max 5 saniye)
    local _wait=0
    while [ "$_wait" -lt 5 ]; do
        if ! ps 2>/dev/null | grep -- '--telegram-daemon' | grep -v grep >/dev/null 2>&1; then
            break
        fi
        sleep 1
        _wait=$((_wait+1))
    done
    print_status PASS "$(T TXT_TGBOT_BOT_STOPPED)"
}
# Autostart - HealthMon watchdog tarafindan yonetilir, ayri init.d gerekmez
telegram_bot_setup_autostart() {
    # Eski init.d script varsa temizle — watchdog halleder
    rm -f "$TG_BOT_AUTOSTART" 2>/dev/null
}
# Bot yonetim menusu
telegram_bot_menu() {
    while true; do
        clear
        print_line "="
        echo "$(T TXT_TGBOT_MENU_BOT_TITLE)"
        print_line "="
        echo
        telegram_load_config 2>/dev/null
        if [ -f "$TG_BOT_PID_FILE" ] && kill -0 "$(cat "$TG_BOT_PID_FILE" 2>/dev/null)" 2>/dev/null; then
            printf " %-26s: %b%s%b\n" "$(T TXT_TGBOT_BOT_ENABLE)" \
                "${CLR_GREEN}${CLR_BOLD}" "$(T TXT_TGBOT_BOT_STATUS_ACTIVE)" "${CLR_RESET}"
        else
            printf " %-26s: %b%s%b\n" "$(T TXT_TGBOT_BOT_ENABLE)" \
                "${CLR_ORANGE}${CLR_BOLD}" "$(T TXT_TGBOT_BOT_STATUS_INACTIVE)" "${CLR_RESET}"
        fi
        printf " %-26s: %s\n" "$(T TXT_TGBOT_POLL_SEC)" "${TG_BOT_POLL_SEC:-5}"
        printf " %-26s: %s\n" "$(T TXT_TGBOT_ROUTER_ID_LABEL)" "${TG_ROUTER_ID}"
        echo
        print_line "-"
        echo " 1) $(T TXT_TGBOT_ENABLE_BOT)"
        echo " 2) $(T TXT_TGBOT_DISABLE_BOT)"
        echo " 3) $(T TXT_TGBOT_RESTART_BOT)"
        echo " 0) $(T TXT_BACK)"
        print_line "-"
        printf "%s" "$(T TXT_CHOICE) "
        read -r c || return 0
        clear
        case "$c" in
            1)
                printf "%s" "$(T TXT_TGBOT_ENTER_POLL)"
                read -r poll_input
                [ -z "$poll_input" ] && poll_input=5
                case "$poll_input" in
                    [0-9]*) : ;;
                    *) poll_input=5 ;;
                esac
                telegram_load_config 2>/dev/null
                telegram_write_config "$TG_BOT_TOKEN" "$TG_CHAT_ID" "1" "$poll_input"
                telegram_bot_setup_autostart "1"
                telegram_bot_stop >/dev/null 2>&1
                sleep 1
                telegram_bot_start
                press_enter_to_continue
                ;;
            2)
                telegram_load_config 2>/dev/null
                telegram_write_config "$TG_BOT_TOKEN" "$TG_CHAT_ID" "0" "${TG_BOT_POLL_SEC:-5}"
                telegram_bot_stop
                telegram_bot_setup_autostart "0"
                press_enter_to_continue
                ;;
            3)
                print_status INFO "$(T _ 'Bot durduruluyor...' 'Stopping bot...')"
                telegram_bot_stop >/dev/null 2>&1
                sleep 1
                print_status INFO "$(T _ 'Bot baslatiliyor...' 'Starting bot...')"
                telegram_bot_start
                sleep 1
                ;;
            0) return 0 ;;
            *) echo "$(T TXT_INVALID_CHOICE)" ; sleep 1 ;;
        esac
    done
}
# -------------------------------------------------------------------
# SYSTEM HEALTH MONITOR (MOD B): CPU/RAM/DISK/LOAD + ZAPRET WATCHDOG
# -------------------------------------------------------------------
HM_CONF_FILE="/opt/etc/healthmon.conf"
HM_PID_FILE="/tmp/kzm2_healthmon.pid"
HM_LOCKDIR="/tmp/kzm2_healthmon.lock"
HM_LOG_FILE="/tmp/kzm2_healthmon.log"
HM_AUTOSTART_FILE="/opt/etc/init.d/S99kzm2_healthmon"
# defaults (used if config missing)
HM_ENABLE="0"
HM_INTERVAL="60"
HM_CPU_WARN="70"
HM_CPU_WARN_DUR="180"
HM_CPU_CRIT="90"
HM_CPU_CRIT_DUR="60"
HM_DISK_WARN="90"          # percent used on /opt
HM_RAM_WARN_MB="40"        # free+buffers+cached approximation in MB
HM_ZAPRET_WATCHDOG="1"
HM_TGBOT_WATCHDOG="1"
HM_ZAPRET_COOLDOWN_SEC="120"
HM_ZAPRET_AUTORESTART="1"
HM_HEARTBEAT_SEC="300"
HM_UPDATECHECK_ENABLE="1"
HM_UPDATECHECK_SEC="21600"
HM_UPDATECHECK_REPO_ZKM="RevolutionTR/keenetic-zapret2-manager"
HM_UPDATECHECK_REPO_ZAPRET="bol-van/zapret2"
HM_COOLDOWN_SEC="600"
HM_ZAPRET_COOLDOWN_SEC="120"
# NFQUEUE qlen watchdog (qnum=300)
# qlen > HM_QLEN_WARN_TH olan ardisik tur sayisi HM_QLEN_CRIT_TURNS'e ulasirsa -> restart_zapret2
HM_QLEN_WATCHDOG="1"          # 0=disable, 1=enable
HM_QLEN_WARN_TH="50"          # paket esigi: bu degeri asarsa sayac artar
HM_QLEN_CRIT_TURNS="1"        # kac ardisik tur ust uste yuksekse aksiyon alinir
# KeenDNS curl throttle: her dongu degil, bu kadar saniyede bir curl cek
HM_KEENDNS_CURL_SEC="120"     # 0 = her dongude (eski davranis)
HM_DEBUG="0"                 # 0=disable, 1=enable — debug log modu
HM_NFQWS_ALERT="1"          # 0=disable, 1=enable — nfqws2 kuyruk alarmi
HM_SYSLOG_WATCH="0"          # 0=disable, 1=enable — sistem log izleme
HM_SYSLOG_COOLDOWN_SEC="600" # kritik olaylar icin bekleme suresi (saniye)
HM_SYSLOG_IKE_COOLDOWN_SEC="3600" # IKE bekleme suresi (saniye, varsayilan 1 saat)
healthmon_print_autoupdate_warning() {
    # Show a single WARN header, then plain indented lines (less noisy)
    print_status WARN "$(T TXT_HM_AUTOUPDATE_WARN_TITLE)"
    printf "  %s
" "$(T TXT_HM_AUTOUPDATE_WARN_L1)"
    printf "  %s
" "$(T TXT_HM_AUTOUPDATE_WARN_L2)"
}
healthmon_load_config() {
    HM_ENABLE="0"
    HM_INTERVAL="60"
    HM_CPU_WARN="70"
    HM_CPU_WARN_DUR="180"
    HM_CPU_CRIT="90"
    HM_CPU_CRIT_DUR="60"
    HM_DISK_WARN="90"
    HM_RAM_WARN_MB="40"
    HM_ZAPRET_WATCHDOG="1"
    HM_TGBOT_WATCHDOG="1"
    HM_COOLDOWN_SEC="600"
    HM_ZAPRET_COOLDOWN_SEC="120"
    HM_UPDATECHECK_ENABLE="1"
    HM_UPDATECHECK_SEC="21600"
    HM_UPDATECHECK_REPO_ZKM="RevolutionTR/keenetic-zapret2-manager"
    HM_UPDATECHECK_REPO_ZAPRET="bol-van/zapret2"
    HM_AUTOUPDATE_MODE="2"
    HM_WANMON_ENABLE="1"
    HM_WANMON_FAIL_TH="3"
    HM_WANMON_OK_TH="2"
    HM_WANMON_IFACE=""
    HM_QLEN_WATCHDOG="1"
    HM_QLEN_WARN_TH="50"
    HM_QLEN_CRIT_TURNS="1"
    HM_KEENDNS_CURL_SEC="120"
    HM_ZAPRET_AUTORESTART="1"
    HM_SYSLOG_WATCH="0"
    HM_SYSLOG_COOLDOWN_SEC="600"
    HM_SYSLOG_IKE_COOLDOWN_SEC="3600"
    HM_NFQWS_ALERT="1"
    [ -f "$HM_CONF_FILE" ] && . "$HM_CONF_FILE" 2>/dev/null
    # Sayi gerektiren degerler icin float/bos sanitize
    _hm_int() { eval "_v=\$$1"; case "${_v:-}" in *[!0-9]*|'') eval "$1=${2}";; esac; }
    _hm_int HM_WANMON_OK_TH   2
    _hm_int HM_WANMON_FAIL_TH 3
    _hm_int HM_QLEN_WARN_TH   50
    _hm_int HM_QLEN_CRIT_TURNS 1
    unset -f _hm_int 2>/dev/null
}
healthmon_write_config() {
    mkdir -p /opt/etc 2>/dev/null
    umask 077
    cat >"$HM_CONF_FILE" <<EOF
HM_ENABLE="$HM_ENABLE"
HM_INTERVAL="$HM_INTERVAL"
HM_CPU_WARN="$HM_CPU_WARN"
HM_CPU_WARN_DUR="$HM_CPU_WARN_DUR"
HM_CPU_CRIT="$HM_CPU_CRIT"
HM_CPU_CRIT_DUR="$HM_CPU_CRIT_DUR"
HM_DISK_WARN="$HM_DISK_WARN"
HM_RAM_WARN_MB="$HM_RAM_WARN_MB"
HM_ZAPRET_WATCHDOG="$HM_ZAPRET_WATCHDOG"
HM_COOLDOWN_SEC="$HM_COOLDOWN_SEC"
HM_ZAPRET_COOLDOWN_SEC="$HM_ZAPRET_COOLDOWN_SEC"
HM_ZAPRET_AUTORESTART="$HM_ZAPRET_AUTORESTART"
HM_HEARTBEAT_SEC="$HM_HEARTBEAT_SEC"
HM_UPDATECHECK_ENABLE="$HM_UPDATECHECK_ENABLE"
HM_UPDATECHECK_SEC="$HM_UPDATECHECK_SEC"
HM_UPDATECHECK_REPO_ZKM="$HM_UPDATECHECK_REPO_ZKM"
HM_UPDATECHECK_REPO_ZAPRET="$HM_UPDATECHECK_REPO_ZAPRET"
HM_AUTOUPDATE_MODE="$HM_AUTOUPDATE_MODE"
HM_WANMON_ENABLE="$HM_WANMON_ENABLE"
HM_WANMON_FAIL_TH="$HM_WANMON_FAIL_TH"
HM_WANMON_OK_TH="$HM_WANMON_OK_TH"
HM_WANMON_IFACE="$HM_WANMON_IFACE"
HM_QLEN_WATCHDOG="$HM_QLEN_WATCHDOG"
HM_QLEN_WARN_TH="$HM_QLEN_WARN_TH"
HM_QLEN_CRIT_TURNS="$HM_QLEN_CRIT_TURNS"
HM_KEENDNS_CURL_SEC="$HM_KEENDNS_CURL_SEC"
HM_DEBUG="$HM_DEBUG"
HM_NFQWS_ALERT="$HM_NFQWS_ALERT"
HM_SYSLOG_WATCH="$HM_SYSLOG_WATCH"
HM_SYSLOG_COOLDOWN_SEC="$HM_SYSLOG_COOLDOWN_SEC"
HM_SYSLOG_IKE_COOLDOWN_SEC="$HM_SYSLOG_IKE_COOLDOWN_SEC"
EOF
    chmod 600 "$HM_CONF_FILE" 2>/dev/null
}
healthmon_cpu_pct() {
    # /proc/stat delta - 0.3s aralikli iki olcum, integer sonuc
    local _c1 _c2
    _c1="$(awk '/^cpu /{print $2,$3,$4,$5,$6,$7,$8}' /proc/stat 2>/dev/null)"
    sleep 0.3 2>/dev/null || sleep 1
    _c2="$(awk '/^cpu /{print $2,$3,$4,$5,$6,$7,$8}' /proc/stat 2>/dev/null)"
    printf '%s %s
' "$_c1" "$_c2" | awk '{
        u1=$1+$2+$3; i1=$4; s1=$5+$6+$7; t1=u1+i1+s1
        u2=$8+$9+$10; i2=$11; s2=$12+$13+$14; t2=u2+i2+s2
        dt=t2-t1; di=i2-i1
        if(dt>0) printf "%d", (dt-di)*100/dt; else print "0"
    }'
}
healthmon_loadavg() {
    # returns "1m 5m 15m"
    uptime 2>/dev/null | awk -F'load average: ' '{print $2}' | tr -d '\r'
}
healthmon_disk_used_pct() {
    # $1 mountpoint
    # df -P Use% sutunu 0 dondururse (buyuk disk, az kullanim), MB bazli kontrol yap
    local _pct _used _total
    _pct="$(df -P "$1" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
    if [ "${_pct:-0}" -eq 0 ]; then
        # Kullanilan alan var mi kontrol et
        _used="$(df -P "$1" 2>/dev/null | awk 'NR==2 {print $3}')"
        if [ "${_used:-0}" -gt 0 ]; then
            printf '<1\n'
            return
        fi
    fi
    printf '%s\n' "${_pct:-0}"
}
healthmon_mem_free_mb() {
    # approximated available = MemFree+Buffers+Cached (kB) -> MB
    awk '
        /^MemFree:/ {mf=$2}
        /^Buffers:/ {b=$2}
        /^Cached:/ {c=$2}
        END { printf "%d\n", (mf+b+c)/1024 }
    ' /proc/meminfo 2>/dev/null
}
healthmon_now() { date +%s; }
# -------------------------------
# WAN Monitor (NDM/ndmc based, no ping)
# Uses: HM_WANMON_ENABLE, HM_WANMON_IFACE, HM_WANMON_FAIL_TH, HM_WANMON_OK_TH
# Requires ndmc but isolates Entware LD_LIBRARY_PATH conflicts.
# -------------------------------
hm_ndmc_cmd() { LD_LIBRARY_PATH= ndmc -c "$1" 2>/dev/null; }
hm_wanmon_get_iface() {
    # Priority:
    # 1) cached runtime iface (linux netdev)
    # 2) HM_WANMON_IFACE (user override)
    # 3) auto: use existing WAN helpers / default route (linux netdev)
    # 4) last resort: NDM PPPoE name -> map to ppp0 if present
    local cache="/tmp/wanmon.ndm_iface"
    local ifc=""
    if [ -f "$cache" ]; then
        ifc="$(cat "$cache" 2>/dev/null)"
    fi
    [ -z "$ifc" ] && ifc="$HM_WANMON_IFACE"
    if [ -z "$ifc" ]; then
        # Prefer existing helpers used elsewhere (Menu 14 / Health)
        ifc="$(get_wan_if 2>/dev/null)"
        [ -z "$ifc" ] && ifc="$(healthmon_detect_wan_iface_ndm 2>/dev/null)"
        # Fallback: parse default route robustly (avoid returning 'link')
        if [ -z "$ifc" ]; then
            ifc="$(ip route 2>/dev/null | awk '$1=="default"{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
        fi
    fi
    # If we still don't have a linux iface, try NDM PPPoE name and map to ppp0 if possible
    if [ -n "$ifc" ] && ! ip link show "$ifc" >/dev/null 2>&1; then
        local ndm_if=""
        ndm_if="$(hm_ndmc_cmd "show interface" | awk '
            BEGIN{RS="Interface, name = "; FS="
"}
            NR>1{
                name=$1; gsub(/".*/,"",name); gsub(/^[ 	"]+|[ 	"]+$/,"",name)
                is_pppoe=0
                for(i=1;i<=NF;i++){
                    if($i ~ /^[ 	]*type:[ 	]*PPPoE[ 	]*$/){ is_pppoe=1; break }
                }
                if(is_pppoe){ print name; exit }
            }
        ')"
        # Common mapping: PPPoE0 -> ppp0 (linux netdev)
        if ip link show ppp0 >/dev/null 2>&1; then
            ifc="ppp0"
        else
            # Keep empty if invalid
            ifc=""
        fi
    fi
    # Cache only valid linux netdev
    if [ -n "$ifc" ] && ip link show "$ifc" >/dev/null 2>&1; then
        echo "$ifc" >"$cache" 2>/dev/null
        chmod 600 "$cache" 2>/dev/null
    fi
    echo "$ifc"
}
hm_wanmon_is_linux_iface() {
    local ifc="$1"
    [ -z "$ifc" ] && return 1
    ip link show "$ifc" >/dev/null 2>&1
}
hm_wanmon_is_up() {
    local ifc="$1"
    [ -z "$ifc" ] && return 1
    # Linux netdev ise:
    # - PPP/IPOe gibi sanal WAN arayuzlerinde LOWER_UP tek basina yeterli degil (WAN kapali iken de UP kalabilir).
    #   Bu nedenle IPv4 adresi + default route varligini kontrol ediyoruz.
    # - Diger arayuzlerde (ethX, wlanX vb.) LOWER_UP yeterlidir.
    if ip link show "$ifc" >/dev/null 2>&1; then
        case "$ifc" in
            ppp*|ipoe*|pppoe*)
                ip -4 addr show dev "$ifc" 2>/dev/null | awk '/inet[[:space:]]/{found=1; exit} END{exit !found}' || return 1
                ip -4 route show default dev "$ifc" 2>/dev/null | grep -q '^default' || return 1
                return 0
                ;;
            *)
                ip link show "$ifc" 2>/dev/null | head -n 1 | grep -q LOWER_UP
                return
                ;;
        esac
    fi
    # ndmc fallback
    hm_ndmc_cmd "show interface $ifc" | awk '
        $1=="link:"      && l=="" {l=$2}
        $1=="connected:" && c=="" {c=$2}
        END { exit ! (l=="up" && c=="yes") }
    '
}
hm_wanmon_iface_exists() {
local ifc="$1"
[ -z "$ifc" ] && return 1
# Linux netdev ise direkt gecerlidir (ppp0, ipoe0, ethX, vb.)
if ip link show "$ifc" >/dev/null 2>&1; then
    return 0
fi
# ndmc fallback (varsa)
hm_ndmc_cmd "show interface $ifc" 2>/dev/null | grep -qE '^[[:space:]]*link:'
}
hm_fmt_hms() {
    # $1 seconds -> HH:MM:SS
    local s="$1"
    [ -z "$s" ] && s=0
    local hh=$((s/3600))
    local mm=$(((s%3600)/60))
    local ss=$((s%60))
    printf "%02d:%02d:%02d" "$hh" "$mm" "$ss"
}
hm_wanmon_tick() {
    [ "${HM_WANMON_ENABLE:-0}" = "1" ] || return 0
    local state_f="/tmp/wanmon.state"
    local down_ts_f="/tmp/wanmon.down_ts"
    local down_hms_f="/tmp/wanmon.down_hms"
    local fails_f="/tmp/wanmon.fails"
    local oks_f="/tmp/wanmon.oks"
    local ifc conf_disp
    ifc="$(hm_wanmon_get_iface)"
    conf_disp="${HM_WANMON_IFACE:-auto}"
    # one-time init log
    if [ ! -f /tmp/wanmon.inited ]; then
        healthmon_log "$(healthmon_now) | wanmon | init iface=${ifc:-N/A} conf=${conf_disp}"
        echo 1 >/tmp/wanmon.inited 2>/dev/null
        chmod 600 /tmp/wanmon.inited 2>/dev/null
    fi
    if [ -z "$ifc" ]; then
        if [ ! -f /tmp/wanmon.iface_warned ]; then
            healthmon_log "$(healthmon_now) | wanmon | iface not set, skipping"
            echo 1 >/tmp/wanmon.iface_warned 2>/dev/null
            chmod 600 /tmp/wanmon.iface_warned 2>/dev/null
        fi
        return 0
    fi
    if ! hm_wanmon_iface_exists "$ifc"; then
        if [ ! -f /tmp/wanmon.iface_bad_warned ]; then
            healthmon_log "$(healthmon_now) | wanmon | iface invalid ($ifc), skipping"
            echo 1 >/tmp/wanmon.iface_bad_warned 2>/dev/null
            chmod 600 /tmp/wanmon.iface_bad_warned 2>/dev/null
        fi
        return 0
    fi
    rm -f /tmp/wanmon.iface_warned /tmp/wanmon.iface_bad_warned 2>/dev/null
    # defaults
    [ -f "$fails_f" ] || echo 0 >"$fails_f"
    [ -f "$oks_f" ] || echo 0 >"$oks_f"
    chmod 600 "$fails_f" "$oks_f" 2>/dev/null
    local state now fails oks
    state="$(cat "$state_f" 2>/dev/null)"
    # CRITICAL FIX: Default to DOWN on first boot/startup so we can detect UP transition
    # If state file doesn't exist, assume DOWN (boot scenario)
    if [ -z "$state" ]; then
        state="DOWN"
        # Also save it so we know this is first run
        echo "DOWN" >"$state_f" 2>/dev/null
        chmod 600 "$state_f" 2>/dev/null
    fi
    fails="$(cat "$fails_f" 2>/dev/null)"; case "$fails" in ''|*[!0-9]*) fails=0;; esac
    oks="$(cat "$oks_f" 2>/dev/null)"; case "$oks" in ''|*[!0-9]*) oks=0;; esac
    now="$(healthmon_now)"
    local _wm_up=0; hm_wanmon_is_up "$ifc" && _wm_up=1
    hm_debug_log "wanmon | ifc=$ifc up=${_wm_up}"
    if [ "$_wm_up" = "1" ]; then
        # observed UP
        fails=0
        oks=$((oks+1))
        echo "$fails" >"$fails_f" 2>/dev/null
        echo "$oks" >"$oks_f" 2>/dev/null
        if [ "$state" = "DOWN" ] && [ "$oks" -ge "${HM_WANMON_OK_TH:-2}" ]; then
            # transition DOWN -> UP, send single rich UP message with duration
            local down_ts down_hms up_hms dur wan_disp
            down_ts="$(cat "$down_ts_f" 2>/dev/null)"; case "$down_ts" in ''|*[!0-9]*) down_ts="$now";; esac
            down_hms="$(cat "$down_hms_f" 2>/dev/null)"
            [ -z "$down_hms" ] && down_hms="$(date '+%H:%M:%S' 2>/dev/null)"
            up_hms="$(date '+%H:%M:%S' 2>/dev/null)"
            dur="$(hm_fmt_hms $((now - down_ts)))"
            wan_disp="$conf_disp"
            if [ -z "$wan_disp" ] || [ "$wan_disp" = "auto" ]; then
                wan_disp="$ifc"
            fi
            echo "UP" >"$state_f" 2>/dev/null
            chmod 600 "$state_f" 2>/dev/null
            rm -f "$down_ts_f" "$down_hms_f" 2>/dev/null
            telegram_send "$(printf '%s
%s : %s
%s : %s
%s : %s' \
                "$(tpl_render "$(T TXT_HM_WAN_UP_TITLE)" IF "$wan_disp")" \
                "📉 $(T TXT_HM_WAN_DOWN_TIME_LABEL)" "$down_hms" \
                "📈 $(T TXT_HM_WAN_UP_TIME_LABEL)" "$up_hms" \
                "🕐 $(T TXT_HM_WAN_DUR_LABEL)" "$dur")" &
            healthmon_log "$now | wanmon | up iface=$ifc dur=$dur"
        fi
        return 0
    fi
    # observed DOWN
    oks=0
    fails=$((fails+1))
    echo "$fails" >"$fails_f" 2>/dev/null
    echo "$oks" >"$oks_f" 2>/dev/null
    if [ "$state" = "UP" ] && [ "$fails" -ge "${HM_WANMON_FAIL_TH:-3}" ]; then
        echo "DOWN" >"$state_f" 2>/dev/null
        chmod 600 "$state_f" 2>/dev/null
        echo "$now" >"$down_ts_f" 2>/dev/null
        chmod 600 "$down_ts_f" 2>/dev/null
        echo "$(date '+%H:%M:%S' 2>/dev/null)" >"$down_hms_f" 2>/dev/null
        chmod 600 "$down_hms_f" 2>/dev/null
        healthmon_log "$now | wanmon | down iface=$ifc"
        # NOTE: No Telegram on DOWN. We notify only when it comes back UP (with duration).
    fi
}
hm_debug_log() {
    [ "${HM_DEBUG:-0}" = "1" ] || return 0
    local _ts _hr _line
    _ts="$(healthmon_now)"
    _hr="$(date -d "@${_ts}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
    _line="${_hr:-$_ts} | [DEBUG] $*"
    printf '%s\n' "$_line" >> "/tmp/healthmon_debug.log" 2>/dev/null
}
healthmon_log() {
    # $1 line
    # Epoch timestamp prefix varsa okunabilir formata cevir (BusyBox date -d @ destekliyor)
    local _line="$1"
    local _ts="${_line%% |*}"
    case "$_ts" in
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9])
            local _hr
            _hr="$(date -d "@${_ts}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
            [ -n "$_hr" ] && _line="${_hr} | ${_line#*| }"
            ;;
    esac
    # In daemon mode, stdout is redirected by init.d to /tmp/kzm2_healthmon.log,
    # so printing to stdout is the most reliable way to make logs visible immediately.
    if [ "${HEALTHMON_DAEMON:-0}" = "1" ]; then
        # Daemon: write to stdout (captured by init.d redirection)
        echo "$_line"
    else
        # Interactive or CGI: always write directly to log file
        if [ -n "$HM_LOG_FILE" ]; then
            # Log rotation: truncate to last 200 lines if file exceeds 500KB
            if [ -f "$HM_LOG_FILE" ]; then
                local _sz
                _sz=$(wc -c < "$HM_LOG_FILE" 2>/dev/null)
                if [ "${_sz:-0}" -gt 512000 ] 2>/dev/null; then
                    local _tmp="${HM_LOG_FILE}.tmp"
                    tail -n 200 "$HM_LOG_FILE" > "$_tmp" 2>/dev/null && mv "$_tmp" "$HM_LOG_FILE" 2>/dev/null
                fi
            fi
            echo "$_line" >>"$HM_LOG_FILE" 2>/dev/null
        fi
    fi
}
healthmon_should_alert() {
    # $1 key (file suffix), $2 cooldown
    local key="$1"
    local cooldown="$2"
    local f="/tmp/healthmon_last_${key}.ts"
    local now
    now=$(healthmon_now)
    local last=0
    [ -f "$f" ] && last=$(cat "$f" 2>/dev/null)
    [ -z "$last" ] && last=0
    [ $((now-last)) -ge "$cooldown" ] || return 1
    echo "$now" >"$f" 2>/dev/null
    return 0
}
healthmon_update_state_load() {
    # state to avoid repeated notifications
    HM_UPD_STATE_FILE="/opt/etc/kzm2_update.state"
    KZM2_LAST_NOTIFIED=""
    ZAPRET_LAST_NOTIFIED=""
    KZM2_LAST_AUTO_ATTEMPTED=""
    [ -f "$HM_UPD_STATE_FILE" ] && . "$HM_UPD_STATE_FILE" 2>/dev/null
}
healthmon_update_state_save() {
    mkdir -p /opt/etc 2>/dev/null
    umask 077
    cat >"$HM_UPD_STATE_FILE" <<EOF
KZM2_LAST_NOTIFIED="$KZM2_LAST_NOTIFIED"
ZAPRET_LAST_NOTIFIED="$ZAPRET_LAST_NOTIFIED"
KZM2_LAST_AUTO_ATTEMPTED="$KZM2_LAST_AUTO_ATTEMPTED"
EOF
    chmod 600 "$HM_UPD_STATE_FILE" 2>/dev/null
}
github_latest_release_tag() {
    # $1 = owner/repo
    local repo="$1"
    local api="https://api.github.com/repos/${repo}/releases/latest"
    local tag
    tag="$(curl -fsS "$api" 2>/dev/null | grep -m1 '"tag_name"' | cut -d '"' -f4)"
    if [ -n "$tag" ]; then
        echo "$tag"
        return 0
    fi
    # fallback: tags list
    api="https://api.github.com/repos/${repo}/tags?per_page=1"
    tag="$(curl -fsS "$api" 2>/dev/null | grep -m1 '"name"' | cut -d '"' -f4)"
    [ -n "$tag" ] && { echo "$tag"; return 0; }
    return 1
}
# Compare versions like v26.2.4 vs v26.2.3 (supports 3-4 numeric parts).
# Returns: 1 if A>B, -1 if A<B, 0 if equal.
kzm2_ver_cmp() {
    local A="${1#v}"; A="${A#V}"
    local B="${2#v}"; B="${B#V}"
    # trim whitespace/CRLF just in case
    A="$(printf %s "$A" | tr -d ' 	
')"
    B="$(printf %s "$B" | tr -d ' 	
')"
    # If current version is empty/unknown, treat latest as newer
    case "$B" in ''|unknown|UNKNOWN) echo 1; return 0 ;; esac
    awk -v A="$A" -v B="$B" '
        function norm(x){ gsub(/[^0-9.]/,"",x); return x }
        function splitv(s, arr,   n,i){
            s=norm(s)
            n=split(s,arr,".")
            for(i=1;i<=n;i++){
                gsub(/[^0-9]/,"",arr[i])
                if(arr[i]=="") arr[i]=0
            }
            return n
        }
        BEGIN{
            na=splitv(A,a); nb=splitv(B,b)
            n=(na>nb?na:nb)
            for(i=1;i<=n;i++){
                av=(i in a?a[i]:0)+0
                bv=(i in b?b[i]:0)+0
                if(av>bv){print 1; exit}
                if(av<bv){print -1; exit}
            }
            print 0
        }'
}
kzm2_ver_gt() { [ "$(kzm2_ver_cmp "$1" "$2")" = "1" ]; }
healthmon_updatecheck_do() {
    # Update check master switch
    [ "${HM_UPDATECHECK_ENABLE:-0}" = "1" ] || return 0
    # Auto update mode:
    # 0 = OFF (no checks)
    # 1 = Notify only
    # 2 = Auto install (KZM only)
    local upd_mode="${HM_AUTOUPDATE_MODE:-1}"
    case "$upd_mode" in
        0) return 0 ;;
        1|2) : ;;
        *) upd_mode="1" ;;
    esac
    local now last_ts f sec
    f="/tmp/healthmon_updatecheck.ts"
    now="$(healthmon_now)"
    sec="${HM_UPDATECHECK_SEC:-21600}"   # default 6h
    # Throttle: only run the GitHub API check every HM_UPDATECHECK_SEC seconds.
    last_ts="$(cat "$f" 2>/dev/null)"
    if [ -n "$last_ts" ] && [ $((now - last_ts)) -lt "$sec" ] 2>/dev/null; then
        : > /tmp/healthmon_updatecheck.defer 2>/dev/null
        return 0
    fi
    # clear defer marker and stamp last check time early to avoid tight loops on failures
    rm -f /tmp/healthmon_updatecheck.defer 2>/dev/null
    echo "$now" > "$f" 2>/dev/null
    # --- Zapret2 surum kontrolu (sadece bildirim, otomatik kurulum yok) ---
    local zap_repo zap_api zap_latest zap_cur zap_url
    zap_repo="${HM_UPDATECHECK_REPO_ZAPRET:-bol-van/zapret2}"
    zap_api="https://api.github.com/repos/${zap_repo}/releases/latest"
    zap_cur="$(cat /opt/zapret2/version 2>/dev/null)"
    if [ -n "$zap_cur" ]; then
        hm_debug_log "updatecheck . zapret2 . github_api start"
        zap_latest="$(curl -fsS "$zap_api" 2>/dev/null | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
        hm_debug_log "updatecheck . zapret2 . github_api done latest=${zap_latest:-N/A}"
        healthmon_log "$(date +%s 2>/dev/null) | updatecheck | zapret2 | cur=$zap_cur latest=${zap_latest:-N/A}"
        if [ -n "$zap_latest" ]; then
            if ver_is_newer "$zap_latest" "$zap_cur"; then
                # Normal guncelleme: yeni surum mevcut
                zap_url="https://github.com/${zap_repo}/releases/latest"
                telegram_send "$(tpl_render "$(T TXT_UPD_ZAPRET_NEW)" CUR "$zap_cur" NEW "$zap_latest" URL "$zap_url")" &
                healthmon_log "$(date +%s 2>/dev/null) | updatecheck | zapret2 | notified cur=$zap_cur latest=$zap_latest"
            elif ver_is_newer "$zap_cur" "$zap_latest"; then
                # Geri cekilmis release: kurulu surum GitHub'dan yeni
                telegram_send "$(tpl_render "$(T TXT_UPD_ZAPRET_ROLLED)" CUR "$zap_cur" NEW "$zap_latest")" &
                healthmon_log "$(date +%s 2>/dev/null) | updatecheck | zapret2 | pulled_release cur=$zap_cur stable=$zap_latest"
            fi
        fi
    fi
    # --- KZM surum kontrolu ---
    local repo api latest cur
    repo="${HM_UPDATECHECK_REPO_ZKM:-RevolutionTR/keenetic-zapret2-manager}"
    api="https://api.github.com/repos/${repo}/releases/latest"
    cur="$(kzm2_get_installed_script_version)"; [ -z "$cur" ] && cur="$SCRIPT_VERSION"
    hm_debug_log "updatecheck | kzm2 | github_api start"
    local _kzm2_api_tmp _kzm2_http
    _kzm2_api_tmp="/tmp/kzm2_updatecheck_api.$$"
    _kzm2_http="$(curl -sS -o "$_kzm2_api_tmp" -w '%{http_code}' "$api" 2>/dev/null)"
    latest="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_kzm2_api_tmp" 2>/dev/null | head -n1)"
    rm -f "$_kzm2_api_tmp" 2>/dev/null
    hm_debug_log "updatecheck | kzm2 | github_api done http=${_kzm2_http:-N/A} latest=${latest:-N/A}"
    # Always log what we saw, so "ran but did nothing" is visible.
    healthmon_log "$(date +%s 2>/dev/null) | updatecheck | kzm2 | cur=$cur latest=${latest:-N/A} mode=$upd_mode"
    if [ -z "$latest" ]; then
        # 404 = repo exists but no release yet. This is not a GitHub/network failure.
        # Keep the timestamp written above. Do not delete $f here; otherwise HealthMon
        # retries every loop and floods the log when GitHub is unreachable or no release exists.
        case "$_kzm2_http" in
            404) healthmon_log "$(date +%s 2>/dev/null) | updatecheck | kzm2 | no_release cur=$cur next_retry=${sec}s" ;;
            000|"") healthmon_log "$(date +%s 2>/dev/null) | updatecheck | kzm2 | github_unreachable cur=$cur next_retry=${sec}s" ;;
            *) healthmon_log "$(date +%s 2>/dev/null) | updatecheck | kzm2 | github_error http=$_kzm2_http cur=$cur next_retry=${sec}s" ;;
        esac
        return 0
    fi
    # Never downgrade: skip if remote is not newer than local (dev builds like v26.2.5.1 must not be replaced by v26.2.5).
    if ! ver_is_newer "$latest" "$cur"; then
        healthmon_log "$(date +%s 2>/dev/null) | updatecheck | kzm2 | up_to_date cur=$cur latest=$latest"
        local _dh_val
        kzm2_disk_health_check
        case "$_dh_reason" in
            ro)             _dh_val="$(T _ 'Salt okunur! Disk hatali olabilir.' 'Read-only! Disk may be damaged.')" ;;
            io_error)       _dh_val="$(T _ 'Kritik I/O hatasi' 'Critical I/O error')" ;;
            journal_error)  _dh_val="$(T TXT_HM_DISK_HEALTH_JOURNAL)" ;;
            usb_disconnect) _dh_val="$(T TXT_HM_DISK_HEALTH_USBDISCON)" ;;
            usb_proto)      _dh_val="$(T TXT_HM_DISK_HEALTH_USBPROTO)" ;;
            *)              _dh_val="$(T _ 'OK ✅' 'OK ✅')" ;;
        esac
        telegram_send "$(tpl_render "$(T TXT_UPD_ZKM_UP_TO_DATE)" CUR "$cur" DISK_HEALTH "$_dh_val")" &
        return 0
    fi
    # New version exists
    local url msg
    url="https://github.com/${repo}/releases/latest"
    if [ "$upd_mode" = "1" ]; then
        msg="$(tpl_render "$(T TXT_UPD_ZKM_NEW)" NEW "$latest" CUR "$cur" URL "$url")"
        telegram_send "$msg" &
        healthmon_log "$(date +%s 2>/dev/null) | updatecheck | kzm2 | notified cur=$cur latest=$latest"
        return 0
    fi
    # upd_mode=2 -> auto install
    if [ "$upd_mode" = "2" ]; then
        healthmon_log "$(date +%s 2>/dev/null) | updatecheck | kzm2 | autoinstall_start cur=$cur latest=$latest"
        if update_manager_script >/tmp/kzm2_autoupdate.log 2>&1; then
            telegram_send "$(tpl_render "$(T TXT_UPD_ZKM_AUTO_OK)" NEW "$latest" CUR "$cur" URL "$url")" &
            healthmon_log "$(date +%s 2>/dev/null) | updatecheck | kzm2 | autoinstall_ok cur=$cur latest=$latest"
            # Web Panel HTML/CGI guncelle
            (KZM2_SKIP_LOCK=1 sh "/opt/lib/opkg/keenetic_zapret2_manager.sh" --update-gui >/dev/null 2>&1 &)
            # Autoupdate sonrasi Telegram botu Menu 15 > 4 > 3 ile ayni sekilde restart et.
            # Ek flag/watchdog kullanma; cift PID race condition burada olusuyordu.
            if [ "$(grep -s '^TG_BOT_ENABLE=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')" = "1" ]; then
                rm -f /tmp/tgbot_restart_requested /tmp/tgbot_just_restarted 2>/dev/null
                healthmon_log "$(date +%s 2>/dev/null) | updatecheck | kzm2 | tgbot_menu_restart_start"
                telegram_bot_stop >/dev/null 2>&1 || true
                sleep 1
                telegram_bot_start >/dev/null 2>&1 || true
                _tg_new_pid="$(cat /tmp/kzm2_telegram_bot.pid 2>/dev/null)"
                healthmon_log "$(date +%s 2>/dev/null) | updatecheck | kzm2 | tgbot_menu_restart_done pid=${_tg_new_pid:-unknown}"
            fi
            # HealthMon restart flag - loop bir sonraki iterasyonda yakalar
            touch /tmp/healthmon_restart_requested 2>/dev/null
        else
            telegram_send "$(tpl_render "$(T TXT_UPD_ZKM_AUTO_FAIL)" CUR "$cur" NEW "$latest" URL "$url")" &
            healthmon_log "$(date +%s 2>/dev/null) | updatecheck | kzm2 | autoinstall_fail cur=$cur latest=$latest"
        fi
    fi
    return 0
}
ndmc_cmd() {
    # Important: prevent Entware /opt libs from breaking ndmc
    LD_LIBRARY_PATH= ndmc -c "$1" 2>/dev/null
}
healthmon_detect_wan_iface_ndm() {
    # Prefer explicit user config if set
    if [ -n "${HM_WANMON_IFACE:-}" ]; then
        echo "$HM_WANMON_IFACE"
        return 0
    fi
    # Prefer zapret-selected WAN info (single source of truth)
    local zif
    zif="$(cat /opt/zapret2/wan_if 2>/dev/null)"
    # If PPP-based WAN is used (ppp0/ppp1), map to first PPPoE interface known by NDM (e.g., PPPoE0)
    if echo "$zif" | grep -Eq '^ppp[0-9]*$'; then
        ndmc_cmd "show interface" | awk '
            BEGIN{RS="Interface, name = "; FS="\n"}
            NR>1{
                name=$1
                gsub(/".*/,"",name); gsub(/^[ \t"]+|[ \t"]+$/,"",name)
                type=""
                for(i=1;i<=NF;i++){
                    if($i ~ /(^|[ \t])type:[ \t]/){sub(/.*type:[ \t]*/,"",$i); type=$i}
                }
                if(type=="PPPoE"){print name; exit}
            }'
        return 0
    fi
    # Generic fallback: pick first interface marked public=yes or having "Internet" trait
    ndmc_cmd "show interface" | awk '
        BEGIN{RS="Interface, name = "; FS="\n"}
        NR>1{
            name=$1
            gsub(/".*/,"",name); gsub(/^[ \t"]+|[ \t"]+$/,"",name)
            if(name ~ /GigabitEthernet0(\/|$)/) next
            if(name ~ /^[0-9]+$/) next
            pub="no"; inet="no"
            for(i=1;i<=NF;i++){
                if($i ~ /(^|[ \t])public:[ \t]yes/){pub="yes"}
                if($i ~ /(^|[ \t])traits:[ \t].*Internet/){inet="yes"}
            }
            if(pub=="yes" || inet=="yes"){print name; exit}
        }'
}
healthmon_wan_is_up() {
    local ifc="$1"
    [ -n "$ifc" ] || return 1
    ndmc_cmd "show interface $ifc" | awk '
        $1=="link:"      {l=$2}
        $1=="connected:" {c=$2}
        END { exit ! (l=="up" && c=="yes") }
    '
}
healthmon_wan_tick() {
    hm_wanmon_tick
}
kzm2_nfqws_alert_check() {
    [ "${HM_NFQWS_ALERT:-1}" = "1" ] || return 0
    # Queue 300 yoksa (nfqws2 durmus) - yanlis recovery mesaji gonderme
    grep -q '^ *300 ' /proc/net/netfilter/nfnetlink_queue 2>/dev/null || return 0
    # WAN hazir degilse alarm gonderme (boot/restart sureci)
    _nfq_wan="$(cat /opt/zapret2/wan_if 2>/dev/null | tr -d '[:space:]')"
    [ -n "$_nfq_wan" ] && ! hm_wanmon_is_up "$_nfq_wan" 2>/dev/null && return 0
    local _ql _dr _flag _now _last _diff _msg
    _flag="/tmp/kzm2_nfqws_alert_active"
    _ql="$(awk '/^ *300/{print $3}' /proc/net/netfilter/nfnetlink_queue 2>/dev/null)"
    _dr="$(awk '/^ *300/{print $6}' /proc/net/netfilter/nfnetlink_queue 2>/dev/null)"
    local _ql_th="${HM_QLEN_WARN_TH:-50}"
    # drops kumulatif — artis var mi kontrol et
    local _dr_prev_f="/tmp/kzm2_nfqws_drops.prev"
    local _dr_prev
    _dr_prev="$(cat "$_dr_prev_f" 2>/dev/null)"
    case "${_dr_prev:-}" in ''|*[!0-9]*) _dr_prev=0 ;; esac
    echo "${_dr:-0}" > "$_dr_prev_f" 2>/dev/null
    local _dr_inc=0
    [ "${_dr:-0}" -gt "$_dr_prev" ] 2>/dev/null && _dr_inc=1
    if [ "${_ql:-0}" -gt "$_ql_th" ] || [ "$_dr_inc" = "1" ] 2>/dev/null; then
        if [ ! -f "$_flag" ]; then
            touch "$_flag" 2>/dev/null
            healthmon_log "$(date '+%Y-%m-%d %H:%M:%S') | nfqws_alert | queue=${_ql:-0} drops=${_dr:-0}"
            _msg="$(tpl_render "$(T TXT_HM_NFQWS_ALERT_MSG)" QL "${_ql:-0}" DR "${_dr:-0}")"
            telegram_send "$_msg" &
        fi
    else
        if [ -f "$_flag" ]; then
            rm -f "$_flag" 2>/dev/null
            healthmon_log "$(date '+%Y-%m-%d %H:%M:%S') | nfqws_alert | recovered"
            telegram_send "$(tpl_render "$(T TXT_HM_NFQWS_ALERT_OK_MSG)")" &
        fi
    fi
}
hm_syslog_watch_tick() {
    [ "${HM_SYSLOG_WATCH:-0}" = "1" ] || return 0
    local _log _now _cd _ike_cd
    _now=$(date +%s 2>/dev/null)
    _cd="${HM_SYSLOG_COOLDOWN_SEC:-600}"
    _ike_cd="${HM_SYSLOG_IKE_COOLDOWN_SEC:-3600}"
    _log="$(LD_LIBRARY_PATH= ndmc -c 'show log 50' 2>/dev/null)"
    [ -z "$_log" ] && return 0

    # Kritik pattern'lar: unexpectedly stopped, too many failed, AUTH_TOPEER_FAILED
    local _crit_count _prev_crit _new_crit
    _crit_count="$(printf '%s\n' "$_log" | grep -cE 'unexpectedly stopped|too many failed requests|AUTH_TOPEER_FAILED|invalid password|access to.*denied' 2>/dev/null)"
    _prev_crit="$(cat /tmp/healthmon_syslog_crit.prev 2>/dev/null)"
    [ -z "$_prev_crit" ] && _prev_crit=0
    echo "$_crit_count" > /tmp/healthmon_syslog_crit.prev
    _new_crit=$((_crit_count - _prev_crit))
    if [ "$_new_crit" -gt 0 ] 2>/dev/null; then
        local _last_crit _diff_crit
        _last_crit="$(cat /tmp/healthmon_syslog_crit.ts 2>/dev/null)"
        [ -z "$_last_crit" ] && _last_crit=0
        _diff_crit=$((_now - _last_crit))
        if [ "$_diff_crit" -ge "$_cd" ] 2>/dev/null; then
            local _sample
            _sample="$(printf '%s\n' "$_log" | grep -E 'unexpectedly stopped|too many failed requests|AUTH_TOPEER_FAILED|invalid password|access to.*denied' | tail -n 3 | sed 's/^[[:space:]]*//' | sed 's/^/• /')"
            echo "$_now" > /tmp/healthmon_syslog_crit.ts
            healthmon_log "$(date +%s 2>/dev/null) | syslog_alert | critical | new=${_new_crit}"
            telegram_send "$(tpl_render "$(T TXT_HM_SYSLOG_CRIT_MSG)" CNT "$_new_crit" LOG "$_sample")" &
        fi
    fi

    # TLS mudahalesi — Zapret2 calisiyor ve TLS hatalari sistem logunda goruluyorsa uyar
    local _tls_count _prev_tls _new_tls
    _tls_count="$(printf '%s\n' "$_log" | grep -cE 'CURLINFO_SSL_VERIFYRESULT|unable to establish TLS|SSL.*connect error|TLS.*handshake.*fail' 2>/dev/null)"
    _prev_tls="$(cat /tmp/healthmon_syslog_tls.prev 2>/dev/null)"
    [ -z "$_prev_tls" ] && _prev_tls=0
    echo "$_tls_count" > /tmp/healthmon_syslog_tls.prev
    _new_tls=$((_tls_count - _prev_tls))
    if [ "$_new_tls" -gt 2 ] 2>/dev/null && is_zapret2_running 2>/dev/null; then
        local _last_tls _diff_tls
        _last_tls="$(cat /tmp/healthmon_syslog_tls.ts 2>/dev/null)"
        [ -z "$_last_tls" ] && _last_tls=0
        _diff_tls=$((_now - _last_tls))
        if [ "$_diff_tls" -ge "1800" ] 2>/dev/null; then
            local _min_win=$(( (_cd > 1800 ? _cd : 1800) / 60 ))
            echo "$_now" > /tmp/healthmon_syslog_tls.ts
            healthmon_log "$(date +%s 2>/dev/null) | syslog_alert | tls_interference | new=${_new_tls}"
            telegram_send "$(tpl_render "$(T TXT_HM_SYSLOG_TLS_MSG)" CNT "$_new_tls" MIN "$_min_win")" &
        fi
    fi
    local _ike_count _prev_ike _new_ike
    _ike_count="$(printf '%s\n' "$_log" | grep -c 'no IKE config found' 2>/dev/null)"
    _prev_ike="$(cat /tmp/healthmon_syslog_ike.prev 2>/dev/null)"
    [ -z "$_prev_ike" ] && _prev_ike=0
    echo "$_ike_count" > /tmp/healthmon_syslog_ike.prev
    _new_ike=$((_ike_count - _prev_ike))
    if [ "$_new_ike" -gt 0 ] 2>/dev/null; then
        local _last_ike _diff_ike
        _last_ike="$(cat /tmp/healthmon_syslog_ike.ts 2>/dev/null)"
        [ -z "$_last_ike" ] && _last_ike=0
        _diff_ike=$((_now - _last_ike))
        if [ "$_diff_ike" -ge "$_ike_cd" ] 2>/dev/null; then
            echo "$_now" > /tmp/healthmon_syslog_ike.ts
            healthmon_log "$(date +%s 2>/dev/null) | syslog_alert | ike | new=${_new_ike}"
            telegram_send "$(tpl_render "$(T TXT_HM_SYSLOG_IKE_MSG)" CNT "$_new_ike")" &
        fi
    fi
}
healthmon_loop() {
    trap '' HUP 2>/dev/null
    # Stale-state cleanup on daemon start (keep PID/log intact)
    rm -f /tmp/wanmon.* /tmp/healthmon_wan.* 2>/dev/null
    rm -f /tmp/healthmon_cpu_* /tmp/healthmon_disk* /tmp/healthmon_ram* /tmp/healthmon_zapret_* /tmp/healthmon_last_* 2>/dev/null
    rm -f /tmp/healthmon_qlen.cnt /tmp/healthmon_qlen.prev /tmp/healthmon_keendns_curl.ts 2>/dev/null
    rm -f /tmp/healthmon_updatecheck.ts 2>/dev/null
    # nfqws monitor temizle — once oku, sonra sil
    local _mon_pid
    _mon_pid="$(cat /tmp/kzm2_nfqws_mon.pid 2>/dev/null)"
    [ -n "$_mon_pid" ] && kill -9 "$_mon_pid" 2>/dev/null
    rm -f /tmp/kzm2_nfqws_mon.pid 2>/dev/null
    # Syslog state: silme, mevcut sayiyi yaz — restart sonrasi eski olaylar "yeni" sayilmasin
    _sl_log="$(LD_LIBRARY_PATH= ndmc -c 'show log' 2>/dev/null)"
    printf '%s\n' "${_sl_log}" | grep -cE 'unexpectedly stopped|too many failed requests|AUTH_TOPEER_FAILED|invalid password|access to.*denied' > /tmp/healthmon_syslog_crit.prev 2>/dev/null
    printf '%s\n' "${_sl_log}" | grep -c 'no IKE config found' > /tmp/healthmon_syslog_ike.prev 2>/dev/null
    printf '%s\n' "${_sl_log}" | grep -cE 'CURLINFO_SSL_VERIFYRESULT|unable to establish TLS|SSL.*connect error|TLS.*handshake.*fail' > /tmp/healthmon_syslog_tls.prev 2>/dev/null
    rm -f /tmp/healthmon_syslog_crit.ts /tmp/healthmon_syslog_ike.ts /tmp/healthmon_syslog_tls.ts 2>/dev/null
    unset _sl_log
    # single-instance guard (robust against stale PID/lock after power loss)
    if ! mkdir "$HM_LOCKDIR" 2>/dev/null; then
        # If a healthy daemon exists, do nothing.
        if [ -f "$HM_PID_FILE" ]; then
            local _p
            _p="$(cat "$HM_PID_FILE" 2>/dev/null)"
            if [ -n "$_p" ] && kill -0 "$_p" 2>/dev/null; then
                exit 0
            fi
        fi
        # Stale lock (directory) - clear and retry once
        rm -rf "$HM_LOCKDIR" 2>/dev/null
        if ! mkdir "$HM_LOCKDIR" 2>/dev/null; then
            exit 0
        fi
    fi
    echo "$$" >"$HM_PID_FILE" 2>/dev/null
    healthmon_log "$(date +%s) | started"
    # Load config early
    healthmon_load_config
    # CRITICAL FIX: Wait for network on startup (especially after power loss/reboot)
    # This must happen BEFORE any WAN monitoring or GitHub checks
    local net_wait=0
    local net_max=120
    healthmon_log "$(date +%s) | startup | waiting for network (max ${net_max}s)"
    while [ $net_wait -lt $net_max ]; do
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            healthmon_log "$(date +%s) | startup | network ready after ${net_wait}s (ping OK)"
            break
        fi
        if command -v nslookup >/dev/null 2>&1 && nslookup google.com >/dev/null 2>&1; then
            healthmon_log "$(date +%s) | startup | network ready after ${net_wait}s (DNS OK)"
            break
        fi
        if ip route get 1.1.1.1 >/dev/null 2>&1; then
            healthmon_log "$(date +%s) | startup | network ready after ${net_wait}s (route OK)"
            break
        fi
        sleep 5
        net_wait=$((net_wait + 5))
    done
    if [ $net_wait -ge $net_max ]; then
        healthmon_log "$(date +%s) | startup | WARNING: network not ready after ${net_max}s, continuing anyway"
    fi
    # If script version changed since last run, force an early update check.
    # NOTE: This runs AFTER network wait so the forced check can actually reach GitHub.
    if [ -n "$SCRIPT_VERSION" ]; then
        _curv="$SCRIPT_VERSION"
        _lastv="$(cat /tmp/kzm2_healthmon.last_script_ver 2>/dev/null)"
        if [ "$_curv" != "$_lastv" ]; then
            echo "$_curv" > /tmp/kzm2_healthmon.last_script_ver 2>/dev/null
            rm -f /tmp/healthmon_updatecheck.ts /tmp/healthmon_updatecheck.defer 2>/dev/null
        fi
    fi
    # NOW that network is ready, run initial WAN monitoring tick
    # This will detect WAN UP state and send notification if needed
    if [ "$HM_ENABLE" = "1" ] && [ "${HM_WANMON_ENABLE:-0}" = "1" ]; then
        healthmon_log "$(date +%s) | startup | running initial WAN check"
        hm_wanmon_tick
    fi
    # state files for duration tracking
    local cpu_warn_start="/tmp/healthmon_cpu_warn.start"
    local cpu_crit_start="/tmp/healthmon_cpu_crit.start"
    local disk_start="/tmp/healthmon_disk.start"
    local ram_start="/tmp/healthmon_ram.start"
    local zapret_start="/tmp/healthmon_zapret_down.start"
    local zapret_flag="/tmp/healthmon_zapret_down.flag"
    local zapret_restart_flag="/tmp/healthmon_zapret_restart.tried"
    local disk_health_flag="/tmp/healthmon_disk_health.flag"
    local hb_ts="/tmp/healthmon_heartbeat.ts"
    while true; do
        healthmon_load_config
        load_lang
        [ "$HM_ENABLE" = "1" ] || break
        local now cpu load disk ram
        now=$(healthmon_now)
        cpu=$(healthmon_cpu_pct)
        load=$(healthmon_loadavg)
        disk=$(healthmon_disk_used_pct /opt)
        disk_num="${disk%%<*}"; [ -z "$disk_num" ] && disk_num=0
        ram=$(healthmon_mem_free_mb)
        # ---- CPU WARN ----
        if [ "$cpu" -ge "$HM_CPU_WARN" ]; then
            [ -f "$cpu_warn_start" ] || echo "$now" >"$cpu_warn_start"
            local st=$(cat "$cpu_warn_start" 2>/dev/null)
            local el=$((now-st))
            if [ "$el" -ge "$HM_CPU_WARN_DUR" ]; then
                if healthmon_should_alert "cpu_warn" "$HM_COOLDOWN_SEC"; then
                    telegram_send "$(tpl_render "$(T TXT_HM_CPU_WARN_MSG)" CPU "$cpu" LOAD "$load" RAM "$ram" DISK "$disk")" &
                        healthmon_log "$now | cpu_warn | cpu=$cpu load=$load ram=${ram}MB disk=${disk}%"
                fi
                rm -f "$cpu_warn_start" 2>/dev/null
            fi
        else
            rm -f "$cpu_warn_start" 2>/dev/null
        fi
        # ---- CPU CRIT ----
        if [ "$cpu" -ge "$HM_CPU_CRIT" ]; then
            [ -f "$cpu_crit_start" ] || echo "$now" >"$cpu_crit_start"
            local stc=$(cat "$cpu_crit_start" 2>/dev/null)
            local elc=$((now-stc))
            if [ "$elc" -ge "$HM_CPU_CRIT_DUR" ]; then
                if healthmon_should_alert "cpu_crit" "$HM_COOLDOWN_SEC"; then
                    telegram_send "$(tpl_render "$(T TXT_HM_CPU_CRIT_MSG)" CPU "$cpu" LOAD "$load" RAM "$ram" DISK "$disk")" &
                        healthmon_log "$now | cpu_crit | cpu=$cpu load=$load ram=${ram}MB disk=${disk}%"
                fi
                rm -f "$cpu_crit_start" 2>/dev/null
            fi
        else
            rm -f "$cpu_crit_start" 2>/dev/null
        fi
        # ---- DISK ----
        if [ -n "$disk_num" ] && [ "$disk_num" -ge "$HM_DISK_WARN" ]; then
            [ -f "$disk_start" ] || echo "$now" >"$disk_start"
            local sd=$(cat "$disk_start" 2>/dev/null)
            local eld=$((now-sd))
            if [ "$eld" -ge 60 ]; then
                if healthmon_should_alert "disk" "$HM_COOLDOWN_SEC"; then
                    telegram_send "$(tpl_render "$(T TXT_HM_DISK_WARN_MSG)" CPU "$cpu" LOAD "$load" RAM "$ram" DISK "$disk")" &
                        healthmon_log "$now | disk_warn | cpu=$cpu load=$load ram=${ram}MB disk=${disk}%"
                fi
                rm -f "$disk_start" 2>/dev/null
            fi
        else
            rm -f "$disk_start" 2>/dev/null
        fi
        # ---- DISK HEALTH (read-only + I/O error) ----
        local _dh_down=0 _dh_msg=""
        kzm2_disk_health_check
        case "$_dh_reason" in
            ro)             _dh_down=1; _dh_msg="$(T TXT_HM_DISK_HEALTH_RO)" ;;
            io_error)       _dh_down=1; _dh_msg="$(T TXT_HM_DISK_HEALTH_IO)" ;;
            journal_error)  _dh_down=1; _dh_msg="$(T TXT_HM_DISK_HEALTH_JOURNAL)" ;;
            usb_disconnect) _dh_down=1; _dh_msg="$(T TXT_HM_DISK_HEALTH_USBDISCON)" ;;
            usb_proto)      _dh_down=1; _dh_msg="$(T TXT_HM_DISK_HEALTH_USBPROTO)" ;;
        esac
        if [ "$_dh_down" = "1" ]; then
            if healthmon_should_alert "disk_health" "$HM_COOLDOWN_SEC"; then
                telegram_send "$(tpl_render "$(T TXT_HM_DISK_HEALTH_DOWN_MSG)" CPU "$cpu" LOAD "$load" RAM "$ram" REASON "$_dh_msg")" &
                healthmon_log "$now | disk_health_down | reason=$_dh_reason cpu=$cpu load=$load ram=${ram}MB disk=${disk}%"
                echo "1" >"$disk_health_flag" 2>/dev/null
            fi
        else
            if [ -f "$disk_health_flag" ]; then
                if healthmon_should_alert "disk_health_up" "$HM_COOLDOWN_SEC"; then
                    telegram_send "$(tpl_render "$(T TXT_HM_DISK_HEALTH_UP_MSG)" CPU "$cpu" LOAD "$load" RAM "$ram")" &
                    healthmon_log "$now | disk_health_up | cpu=$cpu load=$load ram=${ram}MB disk=${disk}%"
                fi
                rm -f "$disk_health_flag" 2>/dev/null
            fi
        fi
        # ---- RAM ----
        if [ -n "$ram" ] && [ "$ram" -le "$HM_RAM_WARN_MB" ]; then
            [ -f "$ram_start" ] || echo "$now" >"$ram_start"
            local sr=$(cat "$ram_start" 2>/dev/null)
            local elr=$((now-sr))
            if [ "$elr" -ge 60 ]; then
                if healthmon_should_alert "ram" "$HM_COOLDOWN_SEC"; then
                    telegram_send "$(tpl_render "$(T TXT_HM_RAM_WARN_MSG)" CPU "$cpu" LOAD "$load" RAM "$ram" DISK "$disk")" &
                        healthmon_log "$now | ram_warn | cpu=$cpu load=$load ram=${ram}MB disk=${disk}%"
                fi
                rm -f "$ram_start" 2>/dev/null
            fi
        else
            rm -f "$ram_start" 2>/dev/null
        fi
        # ---- Zapret2 watchdog ----
        if [ "$HM_ZAPRET_WATCHDOG" = "1" ]; then
            # Her iterasyonda sifirla — pause branch atlandiginda eski deger kalmasin
            local _zap_down=0 _zap_reason=""
            # Kullanici Manuel durdurduysa watchdog mudahale etmesin
            if [ -f "/tmp/.zapret2_paused" ]; then
                hm_debug_log "zapret_wd | paused by user, skipping"
            else
            if is_zapret2_installed; then
                if ! is_zapret2_running; then
                    _zap_down=1; _zap_reason="no_process"
                elif ! _zapret2_iptables_ok; then
                    sleep 3
                    if ! _zapret2_iptables_ok; then
                        _zap_down=1; _zap_reason="iptables_missing"
                    fi
                fi
            fi
            hm_debug_log "zapret_wd | down=${_zap_down} reason=${_zap_reason:-ok}"
            fi  # zapret_paused check
            if [ "$_zap_down" = "1" ]; then
                [ -f "$zapret_start" ] || echo "$now" >"$zapret_start"
                local sz=$(cat "$zapret_start" 2>/dev/null)
                local elz=$((now-sz))
                if [ "$elz" -ge 30 ]; then
                    # optional auto-restart: try once per down event, and only notify if restart fails
                    local restart_ok="0"
                    if [ "$HM_ZAPRET_AUTORESTART" = "1" ] && [ ! -f "$zapret_restart_flag" ]; then
                        echo "1" >"$zapret_restart_flag" 2>/dev/null
                        if [ "$_zap_reason" = "iptables_missing" ]; then
                            # Once sadece firewall kurallarini yenile (process'e dokunma)
                            /opt/zapret2/init.d/sysv/zapret2 start-fw >/dev/null 2>&1
                            sleep 1
                            # start-fw yetmediyse tam restart
                            _zapret2_iptables_ok || restart_zapret2 >/dev/null 2>&1
                        else
                            start_zapret2 >/dev/null 2>&1
                        fi
                        sleep 1
                        if is_zapret2_running && _zapret2_iptables_ok; then
                            restart_ok="1"
                            # iptables_missing start-fw ile sessizce duzeltildi, Telegram gonderme
                            if [ "$_zap_reason" != "iptables_missing" ]; then
                                if healthmon_should_alert "zapret_up" "$HM_ZAPRET_COOLDOWN_SEC"; then
                                    telegram_send "$(tpl_render "$(T TXT_HM_ZAPRET_UP_MSG)" CPU "$cpu" LOAD "$load" RAM "$ram" DISK "$disk" DPI "$(T dpi_pname "$(dpi_profile_name_tr "$(get_dpi_profile)")" "$(dpi_profile_name_en "$(get_dpi_profile)")")")" &
                                    healthmon_log "$now | zapret_autorestart_ok | reason=$_zap_reason cpu=$cpu load=$load ram=${ram}MB disk=${disk}%"
                                fi
                            else
                                healthmon_log "$now | zapret_fw_restore | reason=iptables_missing cpu=$cpu load=$load ram=${ram}MB disk=${disk}%"
                            fi
                            # clear state to allow future down events to re-attempt restart
                            rm -f "$zapret_flag" 2>/dev/null
                            rm -f "$zapret_restart_flag" 2>/dev/null
                            rm -f "$zapret_start" 2>/dev/null
                            continue
                        fi
                    fi
                    # If still down here, notify only when cooldown allows
                    if [ "$restart_ok" != "1" ]; then
                        if healthmon_should_alert "zapret_down" "$HM_ZAPRET_COOLDOWN_SEC"; then
                            if [ "$_zap_reason" = "iptables_missing" ]; then
                                telegram_send "$(tpl_render "$(T TXT_HM_ZAPRET_FW_MISSING_MSG)" CPU "$cpu" LOAD "$load" RAM "$ram" DISK "$disk" DPI "$(T dpi_pname "$(dpi_profile_name_tr "$(get_dpi_profile)")" "$(dpi_profile_name_en "$(get_dpi_profile)")")")" &
                                healthmon_log "$now | zapret_fw_missing | reason=iptables_missing cpu=$cpu load=$load ram=${ram}MB disk=${disk}%"
                            else
                                local _ar_note=""
                                [ "${HM_ZAPRET_AUTORESTART:-0}" != "1" ] && \
                                    _ar_note="$(printf '\n%s' "$(T _ '⚠️ Oto-restart KAPALI (Menu 16 > 4 > 5)' '⚠️ Auto-restart OFF (Menu 16 > 4 > 5)')")"
                                telegram_send "$(tpl_render "$(T TXT_HM_ZAPRET_DOWN_MSG)" CPU "$cpu" LOAD "$load" RAM "$ram" DISK "$disk" DPI "$(T dpi_pname "$(dpi_profile_name_tr "$(get_dpi_profile)")" "$(dpi_profile_name_en "$(get_dpi_profile)")")")${_ar_note}" &
                                healthmon_log "$now | zapret_down | reason=$_zap_reason cpu=$cpu load=$load ram=${ram}MB disk=${disk}%"
                            fi
                            echo "1" >"$zapret_flag" 2>/dev/null
                        fi
                        rm -f "$zapret_start" 2>/dev/null
                    fi
                fi
            else
                # recovered
                if [ -f "$zapret_flag" ] && is_zapret2_installed && is_zapret2_running; then
                    if healthmon_should_alert "zapret_up" "$HM_ZAPRET_COOLDOWN_SEC"; then
                        telegram_send "$(tpl_render "$(T TXT_HM_ZAPRET_UP_MSG)" CPU "$cpu" LOAD "$load" RAM "$ram" DISK "$disk" DPI "$(T dpi_pname "$(dpi_profile_name_tr "$(get_dpi_profile)")" "$(dpi_profile_name_en "$(get_dpi_profile)")")")" &
                        healthmon_log "$now | zapret_up | cpu=$cpu load=$load ram=${ram}MB disk=${disk}%"
                    fi
                    rm -f "$zapret_flag" 2>/dev/null
                    rm -f "$zapret_restart_flag" 2>/dev/null
                fi
                rm -f "$zapret_start" 2>/dev/null
            fi
        fi
        # ---- NFQUEUE qlen watchdog (qnum=300) ----
        # nfqws calisiyor gorunse de kuyruk tikanirsa (zombie working) tespit eder ve restart atar.
        # Spike/stall ayrimi: qlen esigi asildiktan sonra dusuyorsa spike (sayac sifirla),
        # artiyorsa veya sabit kaliyorsa gercek stall (sayac artar, N turda restart).
        _qlen_wan_ifc="$(cat /opt/zapret2/wan_if 2>/dev/null | tr -d '[:space:]')"
        if [ "${HM_QLEN_WATCHDOG:-1}" = "1" ] && hm_wanmon_is_up "$_qlen_wan_ifc" 2>/dev/null; then
            local qlen_th qlen_turns qlen_val qlen_cnt_f qlen_prev_f qlen_cnt qlen_prev
            qlen_th="${HM_QLEN_WARN_TH:-50}"
            qlen_turns="${HM_QLEN_CRIT_TURNS:-1}"
            qlen_cnt_f="/tmp/healthmon_qlen.cnt"
            qlen_prev_f="/tmp/healthmon_qlen.prev"
            # /proc/net/netfilter/nfnetlink_queue formati:
            # queue_num  portid  qlen  copy_mode  copy_range  ...
            # Alan 3 = qlen (0-indexed: $3)
            qlen_val="$(awk '$1 == 300 { print $3; exit }' /proc/net/netfilter/nfnetlink_queue 2>/dev/null)"
            case "$qlen_val" in ''|*[!0-9]*) qlen_val=0 ;; esac
            # Onceki qlen degerini oku
            qlen_prev="$(cat "$qlen_prev_f" 2>/dev/null)"
            case "$qlen_prev" in ''|*[!0-9]*) qlen_prev=0 ;; esac
            echo "$qlen_val" > "$qlen_prev_f" 2>/dev/null
            if [ "$qlen_val" -gt "$qlen_th" ]; then
                qlen_cnt="$(cat "$qlen_cnt_f" 2>/dev/null)"
                case "$qlen_cnt" in ''|*[!0-9]*) qlen_cnt=0 ;; esac
                if [ "$qlen_val" -lt "$qlen_prev" ]; then
                    # Kuyruk dusiyor: spike, sayaci sifirla
                    healthmon_log "$now | qlen_relief | qnum=300 qlen=$qlen_val prev=$qlen_prev cnt_reset"
                    rm -f "$qlen_cnt_f" 2>/dev/null
                else
                    # Kuyruk artiyor veya sabit: gercek stall, sayaci artir
                    qlen_cnt=$((qlen_cnt + 1))
                    echo "$qlen_cnt" > "$qlen_cnt_f" 2>/dev/null
                    healthmon_log "$now | qlen_high | qnum=300 qlen=$qlen_val prev=$qlen_prev cnt=$qlen_cnt/${qlen_turns}"
                    if [ "$qlen_cnt" -ge "$qlen_turns" ]; then
                        # Ardisik N tur yuksek/sabit: 3 sn bekle, tekrar kontrol
                        sleep 3
                        _qlen_recheck="$(awk -v q=300 '$1==q{print $3}' /proc/net/netfilter/nfnetlink_queue 2>/dev/null)"
                        case "$_qlen_recheck" in ''|*[!0-9]*) _qlen_recheck=0 ;; esac
                        if [ "$_qlen_recheck" -le "$qlen_th" ]; then
                            # 3 sn icinde duzeldi: spike, restart gerekmiyor
                            healthmon_log "$now | qlen_spike | qnum=300 qlen=$qlen_val recovered=$_qlen_recheck no_restart"
                            rm -f "$qlen_cnt_f" 2>/dev/null
                        else
                        # Hala yuksek: gercek stall, restart_zapret2
                        healthmon_log "$now | qlen_crit | qnum=300 qlen=$qlen_val cnt=$qlen_cnt triggers=restart_zapret2"
                        if healthmon_should_alert "qlen_crit" "${HM_ZAPRET_COOLDOWN_SEC:-120}"; then
                            telegram_send "$(tpl_render "$(T TXT_HM_ZAPRET_DOWN_MSG)" CPU "$cpu" LOAD "$load" RAM "$ram" DISK "$disk" DPI "$(T dpi_pname "$(dpi_profile_name_tr "$(get_dpi_profile)")" "$(dpi_profile_name_en "$(get_dpi_profile)")")") [qlen=$qlen_val]" &
                        fi
                        restart_zapret2 >/dev/null 2>&1
                        sleep 2
                        # zapret_watchdog ile cift-restart cakmasi onlemek icin state dosyalarini sifirla.
                        # zapret_watchdog bir sonraki turda is_zapret2_running=true gorur (ok) ya da
                        # 30s sayacini bastan baslatir (fail) > tek kaynaktan kontrol saglanir.
                        rm -f /tmp/healthmon_zapret_down.start /tmp/healthmon_zapret_restart.tried 2>/dev/null
                        # Restart sonrasi kontrol
                        if is_zapret2_running; then
                            healthmon_log "$now | qlen_restart_ok | qnum=300 zapret2 is running"
                            if healthmon_should_alert "qlen_restart_ok" "${HM_ZAPRET_COOLDOWN_SEC:-120}"; then
                                telegram_send "$(tpl_render "$(T TXT_HM_ZAPRET_UP_MSG)" CPU "$cpu" LOAD "$load" RAM "$ram" DISK "$disk" DPI "$(T dpi_pname "$(dpi_profile_name_tr "$(get_dpi_profile)")" "$(dpi_profile_name_en "$(get_dpi_profile)")")") [qlen watchdog ok]" &
                            fi
                        else
                            healthmon_log "$now | qlen_restart_fail | qnum=300 zapret2 still not running after restart"
                        fi
                        # Sayaci sifirla (restart sonrasi tekrar izlemeye basla)
                        rm -f "$qlen_cnt_f" 2>/dev/null
                        fi  # _qlen_recheck else
                    fi
                fi
            else
                # qlen normal: sayaci sifirla
                if [ -f "$qlen_cnt_f" ]; then
                    qlen_cnt="$(cat "$qlen_cnt_f" 2>/dev/null)"
                    [ "${qlen_cnt:-0}" -gt 0 ] && healthmon_log "$now | qlen_recovered | qnum=300 qlen=$qlen_val cnt_reset"
                    rm -f "$qlen_cnt_f" 2>/dev/null
                fi
            fi
        fi
        # ---- Heartbeat log (no Telegram) ----
        if [ -n "$HM_HEARTBEAT_SEC" ] && [ "$HM_HEARTBEAT_SEC" -gt 0 ] 2>/dev/null; then
            local last_hb=$(cat "$hb_ts" 2>/dev/null)
            [ -z "$last_hb" ] && last_hb=0
            if [ $((now-last_hb)) -ge "$HM_HEARTBEAT_SEC" ]; then
                local zst="n/a"
                if is_zapret2_installed; then
                    is_zapret2_running && zst="up" || zst="down"
                else
                    zst="not_installed"
                fi
                if [ "${HM_HEARTBEAT_SEC:-0}" -gt 0 ]; then
                    last_hb="$(cat "$hb_ts" 2>/dev/null)"
                    case "$last_hb" in
                        ''|*[!0-9]*) last_hb=0 ;;
                    esac
                    if [ $((now - last_hb)) -ge "$HM_HEARTBEAT_SEC" ]; then
                        echo "$now" > "$hb_ts" 2>/dev/null
                        chmod 600 "$hb_ts" 2>/dev/null
                        healthmon_log "$now | heartbeat | cpu=$cpu load=$load ram=${ram}MB disk=${disk}% zapret2=$zst"
                    fi
                fi
            fi
        fi
        # nfqws2 monitor — ana dongude, heartbeat bagimsiz
        local _mon_pid_f="/tmp/kzm2_nfqws_mon.pid"
        local _mon_pid
        if [ "${HM_DEBUG:-0}" = "1" ]; then
            _mon_pid="$(cat "$_mon_pid_f" 2>/dev/null)"
            if [ -z "$_mon_pid" ] || ! kill -0 "$_mon_pid" 2>/dev/null; then
                (
                    trap '' HUP TERM INT
                    _dbg_log="/tmp/healthmon_debug.log"
                    _ts_file="/tmp/kzm2_debug_started.ts"
                    # Baslangic zamanini koru — HealthMon restart edince sifirlanmasin
                    if [ -f "$_ts_file" ]; then
                        _started="$(cat "$_ts_file" 2>/dev/null)"
                        case "${_started:-}" in ''|*[!0-9]*) _started="$(date +%s)" ;; esac
                    else
                        _started="$(date +%s)"
                        echo "$_started" > "$_ts_file" 2>/dev/null
                    fi
                    _mon_end=$(( _started + 86400 ))
                    while [ "$(grep -s '^HM_DEBUG=' /opt/etc/healthmon.conf | cut -d= -f2 | tr -d '\"')" = "1" ]; do
                        if [ "$(date +%s)" -ge "$_mon_end" ]; then
                            sed -i 's/^HM_DEBUG="1"/HM_DEBUG="0"/' /opt/etc/healthmon.conf 2>/dev/null
                            printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') | nfqws_mon | 24h timeout - HM_DEBUG=0 yapildi" >> "$_dbg_log" 2>/dev/null
                            break
                        fi
                        _ql="$(awk '/^ *300/{print $3}' /proc/net/netfilter/nfnetlink_queue 2>/dev/null)"
                        _dr="$(awk '/^ *300/{print $6}' /proc/net/netfilter/nfnetlink_queue 2>/dev/null)"
                        _cpu="$(top -bn1 2>/dev/null | awk '/nfqws2/{print $8; exit}')"
                        _rules="$(iptables -t mangle -L POSTROUTING -n 2>/dev/null | grep -c NFQUEUE)"
                        _ct="$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)"
                        _ctmax="$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)"
                        _zport="$(ipset list zport_tcp >/dev/null 2>&1 && echo 1 || echo 0)"
                        _mem="$(ps 2>/dev/null | awk '/nfqws2/{print $3; exit}')"
                        _lsmod="$(lsmod 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
                        echo "$_lsmod" | grep -qw "ip_set_bitmap_port" && _bmp=1 || _bmp=0
                        echo "$_lsmod" | grep -qw "xt_NFQUEUE" && _nfq=1 || _nfq=0
                        echo "$_lsmod" | grep -qw "xt_set" && _xts=1 || _xts=0
                        echo "$_lsmod" | grep -qw "nfnetlink_queue" && _nfnq=1 || _nfnq=0
                        printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') | nfqws_mon | queue=${_ql:-?} drops=${_dr:-?} cpu=${_cpu:--}% rules=${_rules:-?} ct=${_ct:-?}/${_ctmax:-?} zport=${_zport:-?} mem=${_mem:-?} mods=bmp:${_bmp},nfq:${_nfq},xts:${_xts},nfnq:${_nfnq}" >> "$_dbg_log" 2>/dev/null
                        # Log boyutu siniri: 10.000 satiri asinca en son 8.000 satiri tut
                        _lc="$(wc -l < "$_dbg_log" 2>/dev/null)"
                        [ "${_lc:-0}" -gt 10000 ] && tail -8000 "$_dbg_log" > "${_dbg_log}.tmp" 2>/dev/null && mv "${_dbg_log}.tmp" "$_dbg_log" 2>/dev/null
                        sleep 10
                    done
                    rm -f "$_mon_pid_f" 2>/dev/null
                    rm -f "$_ts_file" 2>/dev/null
                ) &
                echo "$!" > "$_mon_pid_f" 2>/dev/null
            fi
        else
            _mon_pid="$(cat "$_mon_pid_f" 2>/dev/null)"
            if [ -n "$_mon_pid" ] && kill -0 "$_mon_pid" 2>/dev/null; then
                kill "$_mon_pid" 2>/dev/null
            fi
            rm -f "$_mon_pid_f" 2>/dev/null
            rm -f "/tmp/kzm2_debug_started.ts" 2>/dev/null
        fi
                # WAN monitor (NDM-based, no ping)
# periodic update check (GitHub)
        healthmon_updatecheck_do
        # ---- KEENDNS MONITOR ----
        local kdns_raw2 kdns_name2 kdns_domain2 kdns_access2
        kdns_raw2="$(LD_LIBRARY_PATH= ndmc -c 'show ndns' 2>/dev/null)"
        kdns_name2="$(printf '%s\n' "$kdns_raw2"   | awk '/^[[:space:]]*name:/   {print $2; exit}')"
        kdns_domain2="$(printf '%s\n' "$kdns_raw2" | awk '/^[[:space:]]*domain:/ {print $2; exit}')"
        kdns_access2="$(printf '%s\n' "$kdns_raw2" | awk '/^[[:space:]]*access:/ {print $2; exit}')"
        if [ -n "$kdns_name2" ]; then
            local kdns_fqdn="${kdns_name2}.${kdns_domain2}"
            # --- Erisim modu (direct/cloud) izleme ---
            local kdns_prev_f="/tmp/healthmon_keendns.prev"
            local kdns_prev
            kdns_prev="$(cat "$kdns_prev_f" 2>/dev/null)"
            local kdns_can_direct2
            kdns_can_direct2="$(printf '%s\n' "$kdns_raw2" | awk '/^[[:space:]]*direct:/ {print $2; exit}')"
            if [ -n "$kdns_prev" ] && [ "$kdns_prev" != "$kdns_access2" ]; then
                if [ "$kdns_access2" = "direct" ]; then
                    # direct'e dondu
                    if healthmon_should_alert "keendns_up" "$HM_COOLDOWN_SEC"; then
                        telegram_send "$(printf "$(T TXT_KEENDNS_BACK)" "$kdns_fqdn")" &
                        healthmon_log "$now | keendns_up | $kdns_fqdn"
                    fi
                elif [ "$kdns_can_direct2" = "no" ]; then
                    # CGN: cloud'a dustu, direct imkansiz > kritik alarm
                    if healthmon_should_alert "keendns_down" "$HM_COOLDOWN_SEC"; then
                        telegram_send "$(printf "$(T TXT_KEENDNS_CGN_LOST)" "$kdns_fqdn")" &
                        healthmon_log "$now | keendns_cgn_lost | $kdns_fqdn"
                    fi
                fi
                # direct:yes + cloud > OTO gecis yapacak, alarm verme
            fi
            printf '%s\n' "$kdns_access2" > "$kdns_prev_f" 2>/dev/null
            # --- Gercek erisim (curl) izleme --- THROTTLED (HM_KEENDNS_CURL_SEC) ---
            # curl her dongude degil, sadece HM_KEENDNS_CURL_SEC saniyede bir calisir.
            # Bu sayede NFQUEUE (qnum=300) kuyruklari curl yukunden korunur.
            local kdns_curl_ts_f="/tmp/healthmon_keendns_curl.ts"
            local kdns_curl_last kdns_curl_interval
            kdns_curl_last="$(cat "$kdns_curl_ts_f" 2>/dev/null)"
            case "$kdns_curl_last" in ''|*[!0-9]*) kdns_curl_last=0 ;; esac
            kdns_curl_interval="${HM_KEENDNS_CURL_SEC:-120}"
            case "$kdns_curl_interval" in ''|*[!0-9]*) kdns_curl_interval=120 ;; esac
            local kdns_dest2 kdns_port2 kdns_http2 kdns_reach2
            if [ "$kdns_curl_interval" -eq 0 ] || [ $((now - kdns_curl_last)) -ge "$kdns_curl_interval" ]; then
                echo "$now" > "$kdns_curl_ts_f" 2>/dev/null
                kdns_dest2="$(printf '%s\n' "$kdns_raw2" | awk '/^[[:space:]]*destination:/ {print $2; exit}')"
                kdns_port2="$(printf '%s\n' "$kdns_dest2" | awk -F: '{print $NF}')"
                [ -z "$kdns_port2" ] && kdns_port2="443"
                [ "$kdns_port2" = "443" ] && kdns_proto2="https" || kdns_proto2="http"
                kdns_http2="$(curl -sk --max-time 5 -o /dev/null -w "%{http_code}" "${kdns_proto2}://${kdns_fqdn}:${kdns_port2}" 2>/dev/null)"
                case "$kdns_http2" in
                    2*|3*|401|403) kdns_reach2="yes" ;;
                    *)             kdns_reach2="no"  ;;
                esac
            else
                # Throttled: onceki sonucu kullan, curl yapma
                kdns_reach2="$(cat "/tmp/healthmon_keendns_reach.prev" 2>/dev/null)"
                [ -z "$kdns_reach2" ] && kdns_reach2="yes"  # ilk turda bilinmiyor, alarm uretme
                # Log icin safe default: throttle turunda bu degerler set edilmemis olabilir
                [ -z "$kdns_port2" ]  && kdns_port2="(throttled)"
                [ -z "$kdns_http2" ]  && kdns_http2="(throttled)"
            fi
            local kdns_reach_f="/tmp/healthmon_keendns_reach.prev"
            local kdns_reach_prev
            kdns_reach_prev="$(cat "$kdns_reach_f" 2>/dev/null)"
            # Curl alarmi:
            # - direct modda: erisim kesilirse/gelirse alarm
            # - CGN (direct:no) + cloud modda: cloud erisimi kesilirse/gelirse alarm
            local kdns_do_curl_alarm="no"
            [ "$kdns_access2" = "direct" ] && kdns_do_curl_alarm="yes"
            [ "$kdns_can_direct2" = "no" ] && kdns_do_curl_alarm="yes"
            if [ "$kdns_do_curl_alarm" = "yes" ]; then
                if [ -n "$kdns_reach_prev" ] && [ "$kdns_reach_prev" != "$kdns_reach2" ]; then
                    if [ "$kdns_reach2" = "yes" ]; then
                        if healthmon_should_alert "keendns_reach" "$HM_COOLDOWN_SEC"; then
                            if [ "$kdns_can_direct2" = "no" ]; then
                                telegram_send "$(printf "$(T TXT_KEENDNS_CGN_BACK)" "$kdns_fqdn")" &
                            else
                                telegram_send "$(printf "$(T TXT_KEENDNS_REACH)" "$kdns_fqdn")" &
                            fi
                            healthmon_log "$now | keendns_reachable | $kdns_fqdn"
                        fi
                    else
                        if healthmon_should_alert "keendns_unreach" "$HM_COOLDOWN_SEC"; then
                            if [ "$kdns_can_direct2" = "no" ]; then
                                telegram_send "$(printf "$(T TXT_KEENDNS_CGN_LOST)" "$kdns_fqdn")" &
                            else
                                telegram_send "$(printf "$(T TXT_KEENDNS_FAIL)" "$kdns_fqdn")" &
                            fi
                            healthmon_log "$now | keendns_unreachable | $kdns_fqdn port=$kdns_port2 http=$kdns_http2"
                        fi
                    fi
                fi
            fi
            printf '%s\n' "$kdns_reach2" > "$kdns_reach_f" 2>/dev/null
        fi
        # ---- TELEGRAM BOT RESTART REQUEST (autoupdate sonrasi) ----
        if [ -f /tmp/tgbot_restart_requested ]; then
            rm -f /tmp/tgbot_restart_requested /tmp/tgbot_just_restarted 2>/dev/null
            ps 2>/dev/null | awk '/--telegram-daemon/ && !/awk/{print $1}' | while read -r _p; do
                [ -n "$_p" ] && kill -9 "$_p" 2>/dev/null
            done
            rm -f /tmp/kzm2_telegram_bot.pid 2>/dev/null
            rm -rf /tmp/kzm2_telegram_daemon.lock 2>/dev/null
            sleep 1
            if command -v nohup >/dev/null 2>&1; then
                nohup "$KZM2_SCRIPT_PATH" --telegram-daemon </dev/null >>"$TG_BOT_LOG_FILE" 2>&1 &
            else
                "$KZM2_SCRIPT_PATH" --telegram-daemon </dev/null >>"$TG_BOT_LOG_FILE" 2>&1 &
            fi
            sleep 3
            _req_pid="$(cat /tmp/kzm2_telegram_bot.pid 2>/dev/null)"
            healthmon_log "$now | tgbot_restart_requested | restarted pid=${_req_pid:-unknown}"
        fi
        # ---- TELEGRAM BOT WATCHDOG ----
        if [ "${HM_TGBOT_WATCHDOG:-1}" = "1" ]; then
            _tgconf="/opt/etc/telegram.conf"
            _tgbot_enable="$(grep -s '^TG_BOT_ENABLE=' "$_tgconf" | cut -d= -f2 | tr -d '"')"
            if [ "$_tgbot_enable" = "1" ]; then
                _tgpid_f="$TG_BOT_PID_FILE"
                _tgpid="$(cat "$_tgpid_f" 2>/dev/null)"
                if [ -z "$_tgpid" ] || ! kill -0 "$_tgpid" 2>/dev/null; then
                    # autoinstall az once botu yeniden baslatti — bu turu atla
                    if [ -f /tmp/tgbot_just_restarted ]; then
                        rm -f /tmp/tgbot_just_restarted 2>/dev/null
                        hm_debug_log "tgbot_wd | pid=${_tgpid:-empty} | just_restarted=yes -> skip"
                    else
                    hm_debug_log "tgbot_wd | pid=${_tgpid:-empty} | alive=no -> restart"
                    healthmon_log "$now | tgbot_watchdog | bot dead, restarting"
                    # Eski tum telegram-daemon processleri ve lock temizle
                    ps 2>/dev/null | grep -- '--telegram-daemon' | grep -v grep | awk '{print $1}' | \
                        while read -r _ppid; do [ -n "$_ppid" ] && kill -9 "$_ppid" 2>/dev/null; done
                    rm -rf /tmp/kzm2_telegram_daemon.lock 2>/dev/null
                    sleep 1
                    "$KZM2_SCRIPT_PATH" --telegram-daemon </dev/null >>"$TG_BOT_LOG_FILE" 2>&1 &
                    echo $! > "$_tgpid_f"
                    fi  # else tgbot_just_restarted
                else
                    # PID yasiyor ama duplicate varsa temizle (409/cift mesaj onlemi)
                    ps 2>/dev/null | grep -- '--telegram-daemon' | grep -v grep | awk '{print $1}' | \
                        while read -r _ppid; do
                            [ -n "$_ppid" ] && [ "$_ppid" != "$_tgpid" ] && kill -9 "$_ppid" 2>/dev/null
                        done
                fi
            fi
        fi
        # ---- WAN MONITOR ----
        hm_wanmon_tick
        # ---- LOG ROTATION ----
        # Daemon stdout is redirected to HM_LOG_FILE by init.d (>> append).
        # Truncate to last 300 lines if file exceeds 500KB to protect /tmp RAM.
        if [ -f "$HM_LOG_FILE" ]; then
            _lsz=$(wc -c < "$HM_LOG_FILE" 2>/dev/null)
            if [ "${_lsz:-0}" -gt 512000 ] 2>/dev/null; then
                _ltmp="${HM_LOG_FILE}.tmp"
                tail -n 300 "$HM_LOG_FILE" > "$_ltmp" 2>/dev/null && mv "$_ltmp" "$HM_LOG_FILE" 2>/dev/null
            fi
        fi
        # ---- AUTOHOSTLIST LOG ROTATION ----
        # Zapret2's autohostlist log lives on /opt (persistent). Cap at 1MB.
        _ahl_log="/opt/zapret2/nfqws_autohostlist.log"
        if [ -f "$_ahl_log" ]; then
            _ahl_sz=$(wc -c < "$_ahl_log" 2>/dev/null)
            if [ "${_ahl_sz:-0}" -gt 1048576 ] 2>/dev/null; then
                _ahl_tmp="${_ahl_log}.tmp"
                tail -n 500 "$_ahl_log" > "$_ahl_tmp" 2>/dev/null && mv "$_ahl_tmp" "$_ahl_log" 2>/dev/null
            fi
        fi
        # Otomatik guncelleme sonrasi self-restart
        if [ -f /tmp/healthmon_restart_requested ]; then
            rm -f /tmp/healthmon_restart_requested 2>/dev/null
            healthmon_log "$(date +%s 2>/dev/null) | healthmon | self_restart | yeni surum icin yeniden baslatiliyor"
            rm -f "$HM_PID_FILE" 2>/dev/null
            rmdir "$HM_LOCKDIR" 2>/dev/null
            (KZM2_SKIP_LOCK=1 sh "/opt/lib/opkg/keenetic_zapret2_manager.sh" --healthmon-daemon </dev/null >>/tmp/kzm2_healthmon.log 2>&1 &)
            sleep 1
            exit 0
        fi
        # ---- SYSLOG WATCH ----
        hm_syslog_watch_tick
        # ---- NFQWS ALERT ----
        kzm2_nfqws_alert_check
        sleep "$HM_INTERVAL"
    done
    rm -f "$HM_PID_FILE" 2>/dev/null
    rmdir "$HM_LOCKDIR" 2>/dev/null
}
# ---------------------------------------------------------------------------
kzm2_manual_dpi_adv_default() {
    case "$1" in
        NFQWS2_PORTS_TCP) printf '%s' '80,443' ;;
        NFQWS2_PORTS_UDP) printf '%s' '443' ;;
        NFQWS2_TCP_PKT_OUT) printf '%s' '6' ;;
        NFQWS2_TCP_PKT_IN) printf '%s' '4' ;;
        NFQWS2_UDP_PKT_OUT) printf '%s' '3' ;;
        NFQWS2_UDP_PKT_IN) printf '%s' '3' ;;
        *) printf '%s' '' ;;
    esac
}
kzm2_manual_dpi_adv_get() {
    _key="$1"
    _def="$(kzm2_manual_dpi_adv_default "$_key")"
    _val=""
    if [ -f /opt/zapret2/config ]; then
        _val="$(grep "^${_key}=" /opt/zapret2/config 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '"[:space:]')"
    fi
    [ -n "$_val" ] || _val="$_def"
    printf '%s' "$_val"
}
kzm2_manual_dpi_adv_json() {
    _src="$1"
    if [ "$_src" = "default" ]; then
        _ptcp="$(kzm2_manual_dpi_adv_default NFQWS2_PORTS_TCP)"
        _pudp="$(kzm2_manual_dpi_adv_default NFQWS2_PORTS_UDP)"
        _tout="$(kzm2_manual_dpi_adv_default NFQWS2_TCP_PKT_OUT)"
        _tin="$(kzm2_manual_dpi_adv_default NFQWS2_TCP_PKT_IN)"
        _uout="$(kzm2_manual_dpi_adv_default NFQWS2_UDP_PKT_OUT)"
        _uin="$(kzm2_manual_dpi_adv_default NFQWS2_UDP_PKT_IN)"
    else
        _ptcp="$(kzm2_manual_dpi_adv_get NFQWS2_PORTS_TCP)"
        _pudp="$(kzm2_manual_dpi_adv_get NFQWS2_PORTS_UDP)"
        _tout="$(kzm2_manual_dpi_adv_get NFQWS2_TCP_PKT_OUT)"
        _tin="$(kzm2_manual_dpi_adv_get NFQWS2_TCP_PKT_IN)"
        _uout="$(kzm2_manual_dpi_adv_get NFQWS2_UDP_PKT_OUT)"
        _uin="$(kzm2_manual_dpi_adv_get NFQWS2_UDP_PKT_IN)"
    fi
    printf '{"ok":1,"ports_tcp":"%s","ports_udp":"%s","tcp_out":"%s","tcp_in":"%s","udp_out":"%s","udp_in":"%s"}' \
        "$(kzm2_json_escape "$_ptcp")" "$(kzm2_json_escape "$_pudp")" "$_tout" "$_tin" "$_uout" "$_uin"
}
kzm2_manual_dpi_adv_validate_ports() {
    _v="$(printf '%s' "$1" | tr -d '[:space:]')"
    [ -n "$_v" ] || return 1
    printf '%s' "$_v" | grep -qE '^[0-9]+(,[0-9]+)*$' || return 1
    printf '%s' "$_v" | tr ',' '\n' | awk '{ if ($1 < 1 || $1 > 65535) bad=1 } END{ exit bad }'
}
kzm2_manual_dpi_adv_validate_num() {
    _v="$1"
    printf '%s' "$_v" | grep -qE '^[0-9]+$' || return 1
    [ "$_v" -ge 1 ] 2>/dev/null || return 1
    [ "$_v" -le 999 ] 2>/dev/null || return 1
    return 0
}
kzm2_manual_dpi_adv_validate() {
    _ptcp="$(printf '%s' "$1" | tr -d '[:space:]')"
    _pudp="$(printf '%s' "$2" | tr -d '[:space:]')"
    _tout="$3"; _tin="$4"; _uout="$5"; _uin="$6"
    kzm2_manual_dpi_adv_validate_ports "$_ptcp" || { kzm2_manual_dpi_msg "TCP port listesi gecersiz" "Invalid TCP port list"; return 1; }
    kzm2_manual_dpi_adv_validate_ports "$_pudp" || { kzm2_manual_dpi_msg "UDP port listesi gecersiz" "Invalid UDP port list"; return 1; }
    kzm2_manual_dpi_adv_validate_num "$_tout" || { kzm2_manual_dpi_msg "TCP out paket degeri gecersiz" "Invalid TCP out packet value"; return 1; }
    kzm2_manual_dpi_adv_validate_num "$_tin" || { kzm2_manual_dpi_msg "TCP in paket degeri gecersiz" "Invalid TCP in packet value"; return 1; }
    kzm2_manual_dpi_adv_validate_num "$_uout" || { kzm2_manual_dpi_msg "UDP out paket degeri gecersiz" "Invalid UDP out packet value"; return 1; }
    kzm2_manual_dpi_adv_validate_num "$_uin" || { kzm2_manual_dpi_msg "UDP in paket degeri gecersiz" "Invalid UDP in packet value"; return 1; }
    return 0
}
kzm2_manual_dpi_adv_write() {
    _ptcp="$(printf '%s' "$1" | tr -d '[:space:]')"
    _pudp="$(printf '%s' "$2" | tr -d '[:space:]')"
    _tout="$3"; _tin="$4"; _uout="$5"; _uin="$6"
    KZM2_MANUAL_DPI_ADV_BAK=""
    mkdir -p /opt/zapret2 2>/dev/null || return 1
    [ -f /opt/zapret2/config ] || : > /opt/zapret2/config || return 1
    # 3'lu rotating adv backup: .1 en yeni, .3 en eski
    rm -f /opt/zapret2/config.bak_adv.3 2>/dev/null
    [ -f /opt/zapret2/config.bak_adv.2 ] && mv /opt/zapret2/config.bak_adv.2 /opt/zapret2/config.bak_adv.3 2>/dev/null
    [ -f /opt/zapret2/config.bak_adv.1 ] && mv /opt/zapret2/config.bak_adv.1 /opt/zapret2/config.bak_adv.2 2>/dev/null
    KZM2_MANUAL_DPI_ADV_BAK="/opt/zapret2/config.bak_adv.1"
    cp -a /opt/zapret2/config "$KZM2_MANUAL_DPI_ADV_BAK" 2>/dev/null || return 1
    _tmp="/tmp/kzm2_manual_dpi_adv.$$"
    awk -v ptcp="$_ptcp" -v pudp="$_pudp" -v tout="$_tout" -v tin="$_tin" -v uout="$_uout" -v uin="$_uin" '
        BEGIN{w1=0;w2=0;w3=0;w4=0;w5=0;w6=0}
        /^NFQWS2_PORTS_TCP=/{print "NFQWS2_PORTS_TCP=" ptcp; w1=1; next}
        /^NFQWS2_PORTS_UDP=/{print "NFQWS2_PORTS_UDP=" pudp; w2=1; next}
        /^NFQWS2_TCP_PKT_OUT=/{print "NFQWS2_TCP_PKT_OUT=" tout; w3=1; next}
        /^NFQWS2_TCP_PKT_IN=/{print "NFQWS2_TCP_PKT_IN=" tin; w4=1; next}
        /^NFQWS2_UDP_PKT_OUT=/{print "NFQWS2_UDP_PKT_OUT=" uout; w5=1; next}
        /^NFQWS2_UDP_PKT_IN=/{print "NFQWS2_UDP_PKT_IN=" uin; w6=1; next}
        {print}
        END{
            if(!w1) print "NFQWS2_PORTS_TCP=" ptcp
            if(!w2) print "NFQWS2_PORTS_UDP=" pudp
            if(!w3) print "NFQWS2_TCP_PKT_OUT=" tout
            if(!w4) print "NFQWS2_TCP_PKT_IN=" tin
            if(!w5) print "NFQWS2_UDP_PKT_OUT=" uout
            if(!w6) print "NFQWS2_UDP_PKT_IN=" uin
        }' /opt/zapret2/config > "$_tmp" || { rm -f "$_tmp" 2>/dev/null; return 1; }
    # Config syntax guard: asil config'e yazmadan once shell syntax bozulmasin.
    if ! sh -n "$_tmp" >/dev/null 2>&1; then
        rm -f "$_tmp" 2>/dev/null
        return 1
    fi
    mv "$_tmp" /opt/zapret2/config 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
}

# --cgi-action: CGI tarafindan cagrilir, dogrudan fonksiyon calistirir
# ---------------------------------------------------------------------------
if [ "$1" = "--cgi-action" ]; then
    case "$2" in
        start_zapret2)    start_zapret2   2>/dev/null ;;
        stop_zapret2)     stop_zapret2 1  2>/dev/null ;;
        restart_zapret2)  restart_zapret2 2>/dev/null ;;
        healthmon_start)
            if [ -f "$KZM2_SCRIPT_PATH" ]; then
                KZM2_SKIP_LOCK=1 sh "$KZM2_SCRIPT_PATH" --healthmon-daemon &
            fi
            ;;
        healthmon_stop)
            if [ -f /tmp/kzm2_healthmon.pid ]; then
                kill "$(cat /tmp/kzm2_healthmon.pid 2>/dev/null)" 2>/dev/null
            fi
            ;;
        tg_test)
            if [ -f /opt/etc/telegram.conf ]; then
                . /opt/etc/telegram.conf 2>/dev/null
                [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ] && \
                curl -fsSL -m 10 \
                    "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
                    -d "chat_id=${TG_CHAT_ID}&text=%E2%9C%85+Telegram+Test%3A+Bildirim+calisiyor" \
                    >/dev/null 2>&1 || true
            fi
            ;;
        dns_list)
            _dnsraw="$(LD_LIBRARY_PATH= ndmc -c 'show dns-proxy' 2>/dev/null)"
            _dnsrc="$(LD_LIBRARY_PATH= ndmc -c 'show running-config' 2>/dev/null)"
            _items=""
            _comma=""
            for _dkey in                 "8.8.8.8@dns.google|DoT"                 "8.8.4.4@dns.google|DoT"                 "dns.google/dns-query|DoH"                 "1.1.1.1@one.one.one.one|DoT"                 "1.0.0.1@one.one.one.one|DoT"                 "cloudflare-dns.com/dns-query|DoH"                 "1.1.1.1/dns-query|DoH"                 "1.0.0.1/dns-query|DoH"                 "1.1.1.2@security.cloudflare-dns.com|DoT"                 "1.0.0.2@security.cloudflare-dns.com|DoT"
            do
                _dk="${_dkey%%|*}"
                _dt="${_dkey##*|}"
                _gk="${_dk%%@*}"
                # DoT icin: IP@SNI formatinda gercek DoT kaydi ara
                # DoH icin: uri: https://domain/path formatinda ara
                _found=0
                case "$_dt" in
                    DoT)
                        printf '%s' "$_dnsraw" | grep -qF "# ${_gk}@" && _found=1
                        ;;
                    DoH)
                        printf '%s' "$_dnsraw" | grep -qF "uri: https://${_gk}" && _found=1
                        ;;
                esac
                if [ "$_found" = "1" ]; then
                    _items="${_items}${_comma}$(printf '{"key":"%s","type":"%s"}' "${_dk}" "${_dt}")"
                    _comma=","
                fi
            done
            _rebind="off"
            if printf '%s' "$_dnsraw" | grep -q "norebind_ctl = on" && ! printf '%s' "$_dnsrc" | grep -q "no rebind-protect"; then
                _rebind="on"
            fi
            printf '{"ok":1,"items":[%s],"rebind":"%s"}
' "$_items" "$_rebind"
            exit 0 ;;
        dns_add_preset)
            # $3: paket adi — exit 0: eklendi, exit 2: zaten mevcut
            _cgi_pkg="$3"
            case "$_cgi_pkg" in
                Google|Cloudflare|CF_Families|Quad9|AdGuard|Mullvad|Dns0eu|CleanBrowsing)
                    _raw="$(LD_LIBRARY_PATH= ndmc -c 'show dns-proxy' 2>/dev/null)"
                    # Paketin tumu mevcut mu kontrol et
                    _all_exist=1
                    while IFS= read -r _e; do
                        _p="$(printf '%s' "$_e" | cut -d'|' -f5)"
                        [ "$_p" = "$_cgi_pkg" ] || continue
                        _k="${_e%%|*}"; _gk="${_k%%@*}"
                        printf '%s' "$_raw" | grep -qF "$_gk" || { _all_exist=0; break; }
                    done << DEOF
$(_dns_master_list)
DEOF
                    if [ "$_all_exist" -eq 1 ]; then
                        exit 2
                    fi
                    _dns_add_package "$_cgi_pkg" "$_raw"
                    LD_LIBRARY_PATH= ndmc -c "system configuration save" >/dev/null 2>&1
                    exit 0
                    ;;
            esac ;;
        dns_del)
            # $3: key (e.g. 8.8.8.8@dns.google)
            _cgi_dkey="$3"
            [ -z "$_cgi_dkey" ] && exit 0
                        while IFS= read -r _de; do
                _dk="${_de%%|*}"
                if [ "$_dk" = "$_cgi_dkey" ]; then
                    _rest="${_de#*|}"; _rest2="${_rest#*|}"; _rest3="${_rest2#*|}"
                    _dcmd="${_rest3%%|*}"
                    LD_LIBRARY_PATH= ndmc -c "$_dcmd" >/dev/null 2>&1
                    LD_LIBRARY_PATH= ndmc -c "system configuration save" >/dev/null 2>&1
                    break
                fi
            done << DEOF
$(_dns_master_list)
DEOF
            ;;
        component_check)
            _cc=""
            _ok() { _cc="${_cc}PASS $1|"; }
            _fail() { _cc="${_cc}FAIL $1|"; }
            _warn() { _cc="${_cc}WARN $1|"; }
            _info() { _cc="${_cc}INFO $1|"; }
            command -v opkg >/dev/null 2>&1 && _ok "OPKG (Entware)" || _fail "OPKG bulunamadi"
            command -v iptables >/dev/null 2>&1 && _ok "iptables" || _fail "iptables bulunamadi"
            command -v ip6tables >/dev/null 2>&1 && _ok "IPv6 deste&#287;i (ip6tables)" || _fail "IPv6 deste&#287;i (ip6tables) bulunamad&#305;"
            command -v ipset >/dev/null 2>&1 && _ok "ipset" || _fail "ipset bulunamadi"
            if command -v curl >/dev/null 2>&1; then
                if curl --version >/dev/null 2>&1; then _ok "curl (g&#252;ncelleme i&#231;in)"
                else _fail "curl - eksik k&#252;t&#252;phane (opkg install libnghttp2)"; fi
            elif command -v wget >/dev/null 2>&1; then _ok "wget (g&#252;ncelleme i&#231;in)"
            else _fail "curl/wget bulunamad&#305;"; fi
            opkg list-installed 2>/dev/null | grep -q '^wget-ssl' && _ok "wget-ssl" || _info "wget-ssl bulunamad&#305;"
            opkg list-installed 2>/dev/null | grep -q '^coreutils-sort' && _ok "coreutils-sort" || _info "coreutils-sort bulunamad&#305;"
            if command -v grep >/dev/null 2>&1; then
                if grep --version >/dev/null 2>&1; then _ok "grep"
                else _fail "grep - eksik k&#252;t&#252;phane (opkg install libpcre2)"; fi
            else _info "grep bulunamad&#305;"; fi
            command -v gzip >/dev/null 2>&1 && _ok "gzip" || _info "gzip bulunamad&#305;"
            { command -v crond >/dev/null 2>&1 || command -v cron >/dev/null 2>&1; } && _ok "cron" || _info "cron bulunamad&#305;"
            lsmod 2>/dev/null | grep -qE "^xt_multiport" && _ok "Netfilter Queue mod&#252;lleri" || { find /lib/modules -name "xt_multiport.ko" 2>/dev/null | grep -q . && _ok "Netfilter (xt_multiport)" || _fail "Netfilter Queue mod&#252;lleri bulunamad&#305;"; }
            { opkg list-installed 2>/dev/null | grep -qE "^xtables-addons|^kmod-ipt-xtables" || lsmod 2>/dev/null | grep -qE "^xt_condition|^xt_fuzzy"; } && _ok "Netfilter Xtables-addons geni&#351;letme paketleri" || _fail "Netfilter Xtables-addons bulunamad&#305;"
            { lsmod 2>/dev/null | grep -qi "sch_\|ntc\|^cls_" || grep -qi "SCH_INGRESS\|SCH_HTB\|SCH_HFSC" /proc/net/psched 2>/dev/null || grep -rqi "sch_ingress\|sch_htb\|CONFIG_NET_SCH" /proc/config.gz 2>/dev/null || ls /sys/kernel/debug/tracing 2>/dev/null | grep -q . || find /lib/modules -name "sch_*.ko" 2>/dev/null | grep -q .; } && _ok "Trafik Kontrol (tc) kernel mod&#252;lleri" || _info "Trafik Kontrol (tc) bulunamad&#305;"
            [ -x "/opt/zapret2/nfq2/nfqws2" ] && _ok "nfqws2 binary" || _info "nfqws binary bulunamadi"
            ipset destroy _kzm2_bmp_cgi 2>/dev/null
            if ipset create _kzm2_bmp_cgi bitmap:port range 0-65535 2>/dev/null; then
                ipset destroy _kzm2_bmp_cgi 2>/dev/null
                _ok "ipset bitmap:port kernel mod&#252;l&#252;"
            else
                ipset destroy _kzm2_bmp_cgi 2>/dev/null
                _fail "ipset bitmap:port mod&#252;l&#252; eksik - Zapret2 port kurallari eklenemez"
            fi

            _opt_line="$(awk '$2=="/opt"{print; exit}' /proc/mounts 2>/dev/null)"
            _opt_dev=""
            _opt_fstype=""
            if [ -n "$_opt_line" ]; then
                _opt_dev="$(printf '%s' "$_opt_line" | awk '{print $1}')"
                _opt_fstype="$(printf '%s' "$_opt_line" | awk '{print $3}')"
            fi
            # removable flag: /sys/block/sdX/removable=1 => USB, 0 => dahili
            _opt_bdev="$(printf '%s' "$_opt_dev" | sed 's|/dev/||; s/[0-9]*$//')"
            _opt_removable="$(cat "/sys/block/${_opt_bdev}/removable" 2>/dev/null)"

            if [ -n "$_opt_dev" ]; then
                if echo "$_opt_dev" | grep -q "^/dev/sd"; then
                    if [ "$_opt_removable" = "1" ]; then
                        _ok "Harici depolama - USB (/opt bagli)"
                    else
                        # /dev/sdX ama removable=0: bazi modellerde eMMC USB controller'a bagli
                        _info "Dahili depolama - eMMC/NAND (/opt bagli)"
                    fi
                elif echo "$_opt_dev" | grep -q "^/dev/mmcblk"; then
                    _info "Dahili depolama - eMMC/SD (/opt bagli)"
                elif echo "$_opt_dev" | grep -q "^/dev/nvme"; then
                    _info "Dahili depolama - NVMe SSD (/opt bagli)"
                elif echo "$_opt_fstype" | grep -qE "^tmpfs$"; then
                    _warn "/opt tmpfs - yeniden baslatmada kayip"
                elif echo "$_opt_fstype" | grep -qE "^(overlay|overlayfs|ubifs)$" || \
                     echo "$_opt_dev" | grep -qE "^(overlay|ubi[0-9])"; then
                    _warn "Dahili flash (/opt bagli) - USB surucusu onerilir"
                else
                    _ok "Depolama (/opt bagli)"
                fi
            else
                _opt_mp="$(df -P /opt 2>/dev/null | awk 'NR==2{print $NF}')"
                if [ "$_opt_mp" = "/" ]; then
                    _warn "Dahili flash - USB surucusu onerilir"
                elif [ -n "$_opt_mp" ]; then
                    _ok "Depolama (/opt bagli)"
                else
                    _warn "Depolama - onerilir (USB/eMMC)"
                fi
            fi
            # Ozet satiri ekle
            _fail_count=$(printf '%s' "$_cc" | tr '|' '\n' | grep -c '^FAIL')
            _warn_count=$(printf '%s' "$_cc" | tr '|' '\n' | grep -c '^WARN')
            if [ "$_fail_count" -gt 0 ]; then
                _cc="${_cc}SEP|RESULT FAIL Kritik bilesenlerde sorun var!|"
            elif [ "$_warn_count" -gt 0 ]; then
                _cc="${_cc}SEP|RESULT WARN Zorunlu bilesenler tamam, opsiyonel eksikler var.|"
            else
                _cc="${_cc}SEP|RESULT PASS Tum gerekli bilesenler mevcut!|"
            fi
            printf '{"ok":1,"msg":"%s"}' "$_cc"
            ;;
        dns_rebind_toggle)
            _dnsraw="$(LD_LIBRARY_PATH= ndmc -c 'show dns-proxy' 2>/dev/null)"
            _dnsrc="$(LD_LIBRARY_PATH= ndmc -c 'show running-config' 2>/dev/null)"
            if printf '%s' "$_dnsraw" | grep -q "norebind_ctl = on" && ! printf '%s' "$_dnsrc" | grep -q "no rebind-protect"; then
                LD_LIBRARY_PATH= ndmc -c "no dns-proxy rebind-protect" >/dev/null 2>&1
            else
                LD_LIBRARY_PATH= ndmc -c "dns-proxy rebind-protect auto" >/dev/null 2>&1
            fi
            LD_LIBRARY_PATH= ndmc -c "system configuration save" >/dev/null 2>&1
            sleep 1 ;;
        dpi_set)
            # $3: profil adi
            _cgi_p="$3"
            # ZAPRET_IPV6 config'den oku (--cgi-action sirasinda varsayilan "n")
            if [ -f /opt/zapret2/config ] && grep -q -- '--dpi-desync-ttl6' /opt/zapret2/config 2>/dev/null; then
                ZAPRET_IPV6="y"
            fi
            case "$_cgi_p" in
                tt_default|tt_fiber|superonline_fiber)
                    set_dpi_profile "$_cgi_p"
                    set_dpi_origin "manual"
                    update_nfqws_parameters >/dev/null 2>&1
                    restart_zapret2 >/dev/null 2>&1
                    kzm2_export_active_dpi_profile >/dev/null 2>&1 || true
                    ;;
                blockcheck_auto)
                    [ -s "$BLOCKCHECK_AUTO_PARAMS_FILE" ] || exit 0
                    set_dpi_profile "$_cgi_p"
                    set_dpi_origin "auto"
                    update_nfqws_parameters >/dev/null 2>&1
                    restart_zapret2 >/dev/null 2>&1
                    kzm2_export_active_dpi_profile >/dev/null 2>&1 || true
                    ;;
                none)
                    set_dpi_profile none
                    set_dpi_origin "manual"
                    update_nfqws_parameters >/dev/null 2>&1
                    restart_zapret2 >/dev/null 2>&1
                    kzm2_export_active_dpi_profile >/dev/null 2>&1 || true
                    healthmon_log "$(date '+%Y-%m-%d %H:%M:%S') | dpi_profile_change | profile=none | scope=$(get_scope_mode) | src=webpanel"
                    ;;
            esac
            ;;
        manual_dpi_export|manualdpi_export)
        kzm2_manual_dpi_export_web ;;
    manual_dpi_get|manualdpi_get)
            _src="$(get_param source)"
            case "$_src" in
                default) _val="$(kzm2_manual_dpi_default)" ;;
                runtime) _val="$(kzm2_manual_dpi_runtime 2>/dev/null)"; [ -n "$_val" ] || _val="$(kzm2_manual_dpi_config)" ;;
                *) _val="$(kzm2_manual_dpi_config)" ;;
            esac
            [ -n "$_val" ] || _val="$(kzm2_manual_dpi_default)"
            _val="$(kzm2_manual_dpi_pretty "$_val")"
            printf '{"ok":1,"data":"%s"}' "$(kzm2_json_escape "$_val")"
            ;;
        manual_dpi_adv_get|manualdpi_adv_get)
            _src="$(get_param source)"
            kzm2_manual_dpi_adv_json "$_src"
            ;;
        manual_dpi_adv_save|manualdpi_adv_save)
            _ptcp="$(kzm2_url_decode_basic "$(get_param_raw ports_tcp)" | tr -d '[:space:]')"
            _pudp="$(kzm2_url_decode_basic "$(get_param_raw ports_udp)" | tr -d '[:space:]')"
            _tout="$(kzm2_url_decode_basic "$(get_param_raw tcp_out)" | tr -d '[:space:]')"
            _tin="$(kzm2_url_decode_basic "$(get_param_raw tcp_in)" | tr -d '[:space:]')"
            _uout="$(kzm2_url_decode_basic "$(get_param_raw udp_out)" | tr -d '[:space:]')"
            _uin="$(kzm2_url_decode_basic "$(get_param_raw udp_in)" | tr -d '[:space:]')"
            _err_adv="$(kzm2_manual_dpi_adv_validate "$_ptcp" "$_pudp" "$_tout" "$_tin" "$_uout" "$_uin" 2>/dev/null)"
            if [ -n "$_err_adv" ]; then
                fail "$_err_adv"
            elif kzm2_manual_dpi_adv_write "$_ptcp" "$_pudp" "$_tout" "$_tin" "$_uout" "$_uin"; then
                _bak="$KZM2_MANUAL_DPI_ADV_BAK"
                if kzm2_manual_dpi_restart_checked; then
                    refresh
                    ok "$(kzm2_manual_dpi_msg 'Config de&#287;i&#351;kenleri kaydedildi ve Zapret2 yeniden ba&#351;lat&#305;ld&#305;' 'Config variables saved and Zapret2 restarted')"
                else
                    kzm2_manual_dpi_rollback "$_bak"
                    refresh
                    fail "$(kzm2_manual_dpi_msg 'Config de&#287;i&#351;kenleri uygulamada ba&#351;ar&#305;s&#305;z oldu. &#214;nceki config geri y&#252;klendi.' 'Config variables failed to apply. Previous config was restored.')"
                fi
            else
                fail "$(kzm2_manual_dpi_msg 'Config de&#287;i&#351;kenleri yaz&#305;lamad&#305;. &#214;nceki config korundu' 'Config variables could not be written. Previous config was kept')"
            fi
            ;;
        manual_dpi_save|manualdpi_save)
            _raw="$(get_param_raw opt)"
            _opt="$(kzm2_url_decode_basic "$_raw" | tr '\r\n\t' '   ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ *//; s/ *$//')"
            _err="$(kzm2_manual_dpi_validate "$_opt" 2>/dev/null)"
            if [ -n "$_err" ]; then
                fail "$_err"
            elif kzm2_manual_dpi_write "$_opt"; then
                _bak="$KZM2_MANUAL_DPI_BAK"
                if kzm2_manual_dpi_restart_checked; then
                    refresh
                    ok "$(kzm2_manual_dpi_msg 'Manuel DPI profili uyguland&#305;' 'Manual DPI profile applied')"
                else
                    kzm2_manual_dpi_rollback "$_bak"
                    refresh
                    if kzm2_manual_dpi_is_running; then fail "$(kzm2_manual_dpi_msg 'Manuel profil ba&#351;ar&#305;s&#305;z oldu. &#214;nceki &#231;al&#305;&#351;an profil geri y&#252;klendi.' 'Manual profile failed. Previous working profile was restored.')"; else fail "$(kzm2_manual_dpi_msg 'Manuel profil ba&#351;ar&#305;s&#305;z oldu ve Zapret2 ba&#351;lat&#305;lamad&#305;. SSH ile kontrol edin.' 'Manual profile failed and Zapret2 could not be started. Check via SSH.')"; fi
                fi
            else
                fail "$(kzm2_manual_dpi_msg 'Manuel DPI profili yaz&#305;lamad&#305; veya do&#287;rulanamad&#305;. &#214;nceki profil korundu' 'Manual DPI profile could not be written or validated. Previous profile was kept')"
            fi
            ;;
        health_run_bg)
            _hc_out="/tmp/kzm_health_result.json"
            printf '{"running":1}\n' > "$_hc_out"
            # crash durumunda hata JSON yaz
            trap 'printf '"'"'{"ok":0,"msg":"Kontrol sirasinda hata olustu"}'"'"' > "$_hc_out"' EXIT
            # --- yardimci: JSON string escape ---
            _js() { printf '%s' "$1" | sed 's/\\/\\\\/g;s/"/\\"/g;s/	/ /g'; }
            # --- sonuc biriktirici ---
            _items=""
            _pass=0; _warn=0; _fail=0; _info=0; _total=0
            _add() {
                # $1=section $2=label $3=value $4=status
                local _s _comma
                _s="$4"; _total=$((_total+1))
                case "$_s" in
                    PASS) _pass=$((_pass+1)) ;;
                    WARN) _warn=$((_warn+1)) ;;
                    FAIL) _fail=$((_fail+1)) ;;
                    INFO) _info=$((_info+1)) ;;
                esac
                [ -n "$_items" ] && _comma="," || _comma=""
                _items="${_items}${_comma}{\"sec\":\"$(_js "$1")\",\"lbl\":\"$(_js "$2")\",\"val\":\"$(_js "$3")\",\"st\":\"$4\"}"
            }
            # --- WAN ---
            _wan_if="$(get_wan_if 2>/dev/null)"
            [ -z "$_wan_if" ] && _wan_if="$(healthmon_detect_wan_iface_ndm 2>/dev/null)"
            [ -z "$_wan_if" ] && _wan_if="PPPoE0"
            _wan_raw="$(LD_LIBRARY_PATH= ndmc -c "show interface $_wan_if" 2>/dev/null)"
            _wan_link="$(printf '%s\n' "$_wan_raw" | awk '/link:/ {print $2; exit}')"
            _wan_conn="$(printf '%s\n' "$_wan_raw" | awk '/connected:/ {print $2; exit}')"
            if [ -z "$_wan_link" ] && [ -z "$_wan_conn" ]; then
                if ip link show "$_wan_if" >/dev/null 2>&1; then
                    _wan_link="up"; _wan_conn="yes"
                else
                    _wan_link="down"; _wan_conn="no"
                fi
            fi
            if [ "$_wan_link" = "up" ] && [ "$_wan_conn" = "yes" ]; then _wan_st="PASS"; else _wan_st="FAIL"; fi
            _add "net" "$(T TXT_HEALTH_WAN_STATUS)" "$_wan_if" "$_wan_st"
            _wan_ipv4="$(ip -4 addr show "$_wan_if" 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)"
            _wan_ipv6="$(ip -6 addr show "$_wan_if" 2>/dev/null | awk '/inet6 / && !/fe80/{print $2; exit}' | cut -d/ -f1)"
            if [ -n "$_wan_ipv4" ]; then
                _ip_type="$(kzm2_classify_ip "$_wan_ipv4")"
                case "$_ip_type" in
                    cgnat)   _ip_lbl="$_wan_ipv4 [CGNAT]" ;;
                    private) _ip_lbl="$_wan_ipv4 [NAT]" ;;
                    *)       _ip_lbl="$_wan_ipv4 [Public]" ;;
                esac
                _add "net" "$(T TXT_HEALTH_WAN_IPV4)" "$_ip_lbl" "INFO"
            fi
            [ -n "$_wan_ipv6" ] && _add "net" "$(T TXT_HEALTH_WAN_IPV6)" "$_wan_ipv6" "INFO"
            # DNS meta (INFO - sayilmaz, ayri key)
            _dns_raw="$(LD_LIBRARY_PATH= ndmc -c 'show dns-proxy' 2>/dev/null)"
            _dot_p="$(printf '%s\n' "$_dns_raw" | grep 'dns_server.*@' | sed 's/.*@//;s/[[:space:]].*//' | grep -v '^dnsm$' | grep -v '^$' | sort -u)"
            _doh_p="$(printf '%s\n' "$_dns_raw" | grep 'uri:' | sed 's|.*https://||;s|/.*||' | grep -v '^$' | sort -u)"
            _all_p="$(printf '%s\n%s\n' "$_dot_p" "$_doh_p" | sed '/^$/d' | sort -u | tr '\n' ',' | sed 's/,$//')"
            _doh_ps="$(ps w 2>/dev/null | awk '/https_dns_proxy/ && !/awk/{for(i=1;i<=NF;i++) if($i=="-r"){r=$(i+1); gsub(/^https:\/\//,"",r); gsub(/\/.*/,"",r); print r}}' | sort -u | tr '\n' ',' | sed 's/,$//')"
            [ -n "$_doh_ps" ] && { [ -n "$_all_p" ] && _all_p="${_all_p},${_doh_ps}" || _all_p="$_doh_ps"; }
            _dns_providers="$(printf '%s\n' "$_all_p" | tr ',' '\n' | sed '/^$/d' | sort -u | tr '\n' ',' | sed 's/,$//')"
            _dot_on=0; netstat -lntp 2>/dev/null | grep -qE ':853[[:space:]]' && _dot_on=1
            if [ -n "$_doh_ps" ] && [ "$_dot_on" = "1" ]; then _dns_mode="DoH+DoT"
            elif [ -n "$_doh_ps" ]; then _dns_mode="DoH"
            elif [ "$_dot_on" = "1" ]; then _dns_mode="DoT"
            else _dns_mode="Plain"; fi
            # DNS checks
            if check_dns_local; then _add "net" "$(T TXT_HEALTH_DNS_LOCAL)" "" "PASS"
            else _add "net" "$(T TXT_HEALTH_DNS_LOCAL)" "" "FAIL"; fi
            if check_dns_external; then _add "net" "$(T TXT_HEALTH_DNS_PUBLIC)" "" "PASS"
            else _add "net" "$(T TXT_HEALTH_DNS_PUBLIC)" "" "FAIL"; fi
            if check_dns_consistency; then _add "net" "$(T TXT_HEALTH_DNS_MATCH)" "" "PASS"
            else _add "net" "$(T TXT_HEALTH_DNS_MATCH)" "$(T TXT_HEALTH_DNS_MATCH_NOTE)" "INFO"; fi
            # ISP DNS kontrolu
            _isp_dns_web="$(LD_LIBRARY_PATH= ndmc -c 'show ip name-server' 2>/dev/null | awk '/address:/{print $2}' | tr '\n' ' ' | sed 's/ $//;s/ / - /g')"
            if [ -n "$_isp_dns_web" ]; then
                _add "net" "ISP DNS" "($_isp_dns_web) - $(T _ 'Zapret2 bypass engellenebilir' 'Zapret2 bypass may be blocked')" "WARN"
            else
                _add "net" "ISP DNS" "$(T _ 'Yok - DNS sifreleme aktif' 'None - DNS encryption active')" "PASS"
            fi
            # Route
            _gw="$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')"
            if [ -n "$_gw" ]; then _add "net" "$(T TXT_HEALTH_ROUTE)" "$_gw" "PASS"
            else _add "net" "$(T TXT_HEALTH_ROUTE)" "$(T _ 'yok' 'none')" "FAIL"; fi
            # --- System ---
            if ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then _add "sys" "$(T TXT_HEALTH_PING)" "" "PASS"
            else _add "sys" "$(T TXT_HEALTH_PING)" "" "FAIL"; fi
            _ram_kb="$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')"
            _ram_mb=$((_ram_kb/1024))
            if [ "$_ram_mb" -lt 100 ]; then _add "sys" "$(T TXT_HEALTH_RAM)" "${_ram_mb}MB" "WARN"
            else _add "sys" "$(T TXT_HEALTH_RAM)" "${_ram_mb}MB" "PASS"; fi
            # RAM detay
            _ram_total_kb="$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')"
            _ram_used_kb=$(( _ram_total_kb - _ram_kb ))
            _ram_total_mb=$(( _ram_total_kb / 1024 ))
            _ram_used_mb=$(( _ram_used_kb / 1024 ))
            _ram_buf_kb="$(grep '^Buffers:' /proc/meminfo 2>/dev/null | awk '{print $2}')"
            _ram_cached_kb="$(grep '^Cached:' /proc/meminfo 2>/dev/null | awk '{print $2}' | head -1)"
            _ram_buf_mb=$(( (_ram_buf_kb + _ram_cached_kb) / 1024 ))
            _swap_total_kb="$(grep SwapTotal /proc/meminfo 2>/dev/null | awk '{print $2}')"
            _swap_free_kb="$(grep SwapFree /proc/meminfo 2>/dev/null | awk '{print $2}')"
            _swap_used_mb=$(( (_swap_total_kb - _swap_free_kb) / 1024 ))
            _swap_total_mb=$(( _swap_total_kb / 1024 ))
            _add "sys" "$(T TXT_HEALTH_RAM_DETAIL)" "${_ram_used_mb}MB / ${_ram_mb}MB $(T _ 'bos' 'free') / ${_ram_total_mb}MB $(T _ 'toplam' 'total')" "INFO"
            _add "sys" "$(T TXT_HEALTH_RAM_BUFFER)" "${_ram_buf_mb}MB" "INFO"
            _add "sys" "$(T TXT_HEALTH_SWAP)" "${_swap_used_mb}MB / ${_swap_total_mb}MB" "INFO"
            _load="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
            _load5="$(awk '{print $2}' /proc/loadavg 2>/dev/null)"
            _load15="$(awk '{print $3}' /proc/loadavg 2>/dev/null)"
            _nproc_hc="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)"; [ -z "$_nproc_hc" ] || [ "$_nproc_hc" -eq 0 ] 2>/dev/null && _nproc_hc=1
            _load_status="PASS"
            awk -v l="$_load" -v n="$_nproc_hc" 'BEGIN{exit (l>=n)?0:1}' && _load_status="WARN"
            _add "sys" "$(T TXT_HEALTH_LOAD)" "$(T _ '1dk' '1min'): <b>$_load</b> | $(T _ '5dk' '5min'): <b>$_load5</b> | $(T _ '15dk' '15min'): <b>$_load15</b>  ($(T _ 'Esik' 'Threshold'): <b style='color:var(--info)'>${_nproc_hc}</b> CPU)" "$_load_status"
            _disk_pct="$(healthmon_disk_used_pct /opt)"
            _disk_free_mb="$(df -k /opt 2>/dev/null | awk 'NR==2 {printf "%d", $4/1024}')"
            if [ "$_disk_pct" != "<1" ] && [ -n "$_disk_pct" ] && [ "$_disk_pct" -gt 90 ] 2>/dev/null; then _add "sys" "$(T TXT_HEALTH_DISK)" "${_disk_pct}% (${_disk_free_mb}MB $(T _ 'bos' 'free'))" "WARN"
            else _add "sys" "$(T TXT_HEALTH_DISK)" "${_disk_pct}% (${_disk_free_mb}MB $(T _ 'bos' 'free'))" "PASS"; fi
            # Disk sagligi: ortak helper ile kontrol
            _dh_ok="PASS"; _dh_msg="$(T TXT_HEALTH_DISK_OK)"
            kzm2_disk_health_check
            _dh_ok="$_dh_status"
            case "$_dh_reason" in
                ro)             _dh_msg="$(T TXT_HEALTH_DISK_RO)" ;;
                io_error)       _dh_msg="$(T TXT_HEALTH_DISK_IO_ERR)" ;;
                journal_error)  _dh_msg="$(T TXT_HEALTH_DISK_JOURNAL)" ;;
                usb_disconnect) _dh_msg="$(T TXT_HEALTH_DISK_USBDISCON)" ;;
                usb_proto)      _dh_msg="$(T TXT_HEALTH_DISK_USBPROTO)" ;;
                *)              _dh_msg="$(T TXT_HEALTH_DISK_OK)" ;;
            esac
            _add "sys" "$(T TXT_HEALTH_DISK_HEALTH)" "$_dh_msg" "$_dh_ok"
            # Disk / ve /tmp
            _dr_pct="$(df -k / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
            _dr_free_mb="$(df -k / 2>/dev/null | awk 'NR==2 {printf "%d", $4/1024}')"
            # / genellikle Keenetic flash/overlay - her zaman dolu gorunur, INFO
            _dt_pct="$(df -k /tmp 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
            _dt_free_mb="$(df -k /tmp 2>/dev/null | awk 'NR==2 {printf "%d", $4/1024}')"
            _dt_used_mb="$(df -k /tmp 2>/dev/null | awk 'NR==2 {printf "%d", $3/1024}')"
            _dt_total_str="$(df -k /tmp 2>/dev/null | awk 'NR==2 {printf "%.1fMB", $2/1024}')"
            _add "sys" "$(T TXT_HEALTH_DISK_TMP)" "${_dt_used_mb}MB / ${_dt_total_str} (${_dt_pct}%)" "INFO"
            # SoC sicakligi
            _hc_temp=""
            for _tf in /sys/class/thermal/thermal_zone*/temp; do
                [ -f "$_tf" ] || continue
                _tv="$(cat "$_tf" 2>/dev/null)"
                if [ -n "$_tv" ]; then
                    _hc_temp="$(awk -v t="$_tv" 'BEGIN{printf "%.0f", t/1000}')"
                    break
                fi
            done
            [ -n "$_hc_temp" ] && _add "sys" "$(T TXT_HEALTH_TEMP)" "$_hc_temp $(T _ 'Santigrat Derece' 'Degrees Celsius')" "INFO"
            # LAN IP
            _hc_lan="$(ip -4 addr show br0 2>/dev/null | awk '/inet /{print $2;exit}' | cut -d/ -f1)"
            [ -z "$_hc_lan" ] && _hc_lan="$(ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2;exit}' | cut -d/ -f1)"
            [ -n "$_hc_lan" ] && _add "net" "$(T TXT_HEALTH_LAN_IP)" "$_hc_lan" "INFO"
            if check_ntp; then _add "sys" "$(T TXT_HEALTH_TIME)" "$(date '+%Y-%m-%d %H:%M')" "PASS"
            else _add "sys" "$(T TXT_HEALTH_TIME)" "$(date '+%Y-%m-%d %H:%M')" "WARN"; fi
            _kzm_exp="/opt/lib/opkg/keenetic_zapret2_manager.sh"
            _kzm_real="$(readlink -f "$KZM2_SCRIPT_PATH" 2>/dev/null || echo "$KZM2_SCRIPT_PATH")"
            if [ "$_kzm_real" = "$_kzm_exp" ]; then _add "sys" "$(T TXT_HEALTH_SCRIPT_PATH)" "$_kzm_real" "PASS"
            else _add "sys" "$(T TXT_HEALTH_SCRIPT_PATH)" "$_kzm_real" "WARN"; fi
            # --- Services ---
            # Entware
            if [ -f /opt/bin/opkg ] || [ -d /opt/etc ]; then _add "svc" "$(T TXT_HEALTH_ENTWARE)" "$(T _ 'Kurulu' 'Installed') (/opt)" "PASS"
            else _add "svc" "$(T TXT_HEALTH_ENTWARE)" "$(T _ 'Bulunamadi' 'Not found')" "FAIL"; fi
            # curl
            if command -v curl >/dev/null 2>&1; then
                if curl --version >/dev/null 2>&1; then
                    _add "svc" "$(T TXT_HEALTH_CURL)" "$(T _ 'Kurulu' 'Installed') ($(command -v curl))" "PASS"
                else
                    _add "svc" "$(T TXT_HEALTH_CURL)" "$(T _ 'Binary var ama calismiyor - eksik kutuphane (opkg install libnghttp2)' 'Binary exists but fails - missing library (opkg install libnghttp2)')" "FAIL"
                fi
            else _add "svc" "$(T TXT_HEALTH_CURL)" "$(T _ 'Bulunamadi' 'Not found')" "WARN"; fi
            # lighttpd
            if pgrep lighttpd >/dev/null 2>&1; then _add "svc" "$(T TXT_HEALTH_LIGHTTPD)" "$(T _ 'Calisiyor' 'Running') ($(pgrep lighttpd | head -1))" "PASS"
            elif command -v lighttpd >/dev/null 2>&1; then _add "svc" "$(T TXT_HEALTH_LIGHTTPD)" "$(T _ 'Kurulu ama calismiyor' 'Installed but not running')" "WARN"
            else _add "svc" "$(T TXT_HEALTH_LIGHTTPD)" "$(T _ 'Kurulu degil' 'Not installed')" "INFO"; fi
            # HealthMon
            _hc_hm_pid="$(cat /tmp/kzm2_healthmon.pid 2>/dev/null)"
            _hc_hm_en="$(grep -s '^HM_ENABLE=' /opt/etc/healthmon.conf | cut -d= -f2 | tr -d '"')"
            if [ -n "$_hc_hm_pid" ] && kill -0 "$_hc_hm_pid" 2>/dev/null; then
                _add "svc" "$(T TXT_HEALTH_HEALTHMON)" "$(T _ 'Calisiyor' 'Running') (PID: $_hc_hm_pid)" "PASS"
            elif [ "$_hc_hm_en" = "1" ]; then _add "svc" "$(T TXT_HEALTH_HEALTHMON)" "$(T _ 'Acik ama calismiyor' 'Enabled but not running')" "WARN"
            else _add "svc" "$(T TXT_HEALTH_HEALTHMON)" "$(T _ 'Kapali' 'Disabled')" "INFO"; fi
            # Telegram Bot
            _hc_tg_en="$(grep -s '^TG_BOT_ENABLE=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')"
            if [ -f /tmp/kzm2_telegram_bot.pid ] && kill -0 "$(cat /tmp/kzm2_telegram_bot.pid 2>/dev/null)" 2>/dev/null; then
                _add "svc" "$(T TXT_HEALTH_TGBOT)" "$(T _ 'Calisiyor' 'Running') (PID: $(cat /tmp/kzm2_telegram_bot.pid 2>/dev/null))" "PASS"
            elif [ "$_hc_tg_en" = "1" ]; then _add "svc" "$(T TXT_HEALTH_TGBOT)" "$(T _ 'Acik ama calismiyor' 'Enabled but not running')" "WARN"
            else _add "svc" "$(T TXT_HEALTH_TGBOT)" "$(T _ 'Kapali / Yapilandirilmamis' 'Disabled / Not configured')" "INFO"; fi
            if check_github; then _add "svc" "$(T TXT_HEALTH_GITHUB)" "" "PASS"
            else _add "svc" "$(T TXT_HEALTH_GITHUB)" "" "WARN"; fi
            if check_opkg; then _add "svc" "$(T TXT_HEALTH_OPKG)" "" "PASS"
            else _add "svc" "$(T TXT_HEALTH_OPKG)" "" "WARN"; fi
            if is_zapret2_running; then _add "svc" "$(T TXT_HEALTH_ZAPRET)" "$(T _ 'Calisiyor' 'Running')" "PASS"
            else _add "svc" "$(T TXT_HEALTH_ZAPRET)" "$(T _ 'Durduruldu' 'Stopped')" "FAIL"; fi
            # KeenDNS
            _kdns_raw="$(LD_LIBRARY_PATH= ndmc -c 'show ndns' 2>/dev/null)"
            _kdns_name="$(printf '%s
' "$_kdns_raw" | awk '/name:/ {print $2; exit}')"
            _kdns_dom="$(printf '%s
' "$_kdns_raw"  | awk '/domain:/ {print $2; exit}')"
            _kdns_acc="$(printf '%s
' "$_kdns_raw"  | awk '/access:/ {print $2; exit}')"
            _kdns_dir="$(printf '%s
' "$_kdns_raw"  | awk '/direct:/ {print $2; exit}')"
            if [ -z "$_kdns_name" ]; then
                _add "svc" "KeenDNS" "$(T TXT_KEENDNS_NONE)" "INFO"
            else
                _kdns_fqdn="${_kdns_name}.${_kdns_dom}"
                _kdns_dest="$(printf '%s
' "$_kdns_raw" | awk '/destination:/ {print $2; exit}')"
                _kdns_port="$(printf '%s
' "$_kdns_dest" | awk -F: '{print $NF}')"
                [ -z "$_kdns_port" ] && _kdns_port="443"
                [ "$_kdns_port" = "443" ] && _kp="https" || _kp="http"
                _kdns_code="$(curl -sk --max-time 5 -o /dev/null -w "%{http_code}" "${_kp}://${_kdns_fqdn}:${_kdns_port}" 2>/dev/null)"
                case "$_kdns_code" in 2*|3*|401|403) _kdns_reach="yes" ;; *) _kdns_reach="no" ;; esac
                if [ "$_kdns_acc" = "direct" ] && [ "$_kdns_reach" = "no" ]; then
                    _add "svc" "KeenDNS" "$_kdns_fqdn [$(T TXT_KEENDNS_UNKNOWN)]" "FAIL"
                elif [ "$_kdns_acc" = "direct" ]; then
                    _add "svc" "KeenDNS" "$_kdns_fqdn [$(T TXT_KEENDNS_DIRECT)]" "PASS"
                elif [ "$_kdns_dir" = "no" ]; then
                    _add "svc" "KeenDNS" "$_kdns_fqdn [$(T TXT_KEENDNS_CLOUD)]" "WARN"
                else
                    _add "svc" "KeenDNS" "$_kdns_fqdn [$(T TXT_KEENDNS_CLOUD)]" "INFO"
                fi
            fi
            # SHA256
            _sha_kzm="$(cat /opt/etc/kzm2_sha256_kzm.state 2>/dev/null)"
            _sha_zap="$(cat /opt/etc/kzm2_sha256_zapret.state 2>/dev/null)"
            case "$_sha_kzm" in ok) _add "svc" "$(T TXT_HEALTH_SHA256_KZM)" "$(T TXT_HEALTH_SHA256_OK)" "PASS" ;; fail) _add "svc" "$(T TXT_HEALTH_SHA256_KZM)" "$(T TXT_HEALTH_SHA256_FAIL)" "WARN" ;; *) _add "svc" "$(T TXT_HEALTH_SHA256_KZM)" "$(T TXT_HEALTH_SHA256_UNKNOWN)" "INFO" ;; esac
            case "$_sha_zap" in ok) _add "svc" "$(T TXT_HEALTH_SHA256_ZAP)" "$(T TXT_HEALTH_SHA256_OK)" "PASS" ;; fail) _add "svc" "$(T TXT_HEALTH_SHA256_ZAP)" "$(T TXT_HEALTH_SHA256_FAIL)" "WARN" ;; *) _add "svc" "$(T TXT_HEALTH_SHA256_ZAP)" "$(T TXT_HEALTH_SHA256_ZAP_UNKNOWN)" "INFO" ;; esac
            # Score
            _ok_n=$((_pass+_info))
            _score="$(awk -v ok="$_ok_n" -v t="$_total" 'BEGIN{if(t<=0)print "0.0"; else printf "%.1f",(ok/t)*10}')"
            _ts="$(date +%s 2>/dev/null || echo 0)"
            printf '{"ok":1,"ts":%s,"score":"%s","pass":%d,"warn":%d,"fail":%d,"info":%d,"total":%d,"dns_mode":"%s","dns_providers":"%s","items":[%s]}\n' \
                "$_ts" "$_score" "$_pass" "$_warn" "$_fail" "$_info" "$_total" \
                "$(_js "$_dns_mode")" "$(_js "$_dns_providers")" "$_items" \
                > "$_hc_out"
            trap - EXIT
            ;;
        *) ;;
    esac
    exit 0
fi
healthmon_is_running() {
  # 1) PID file check
  if [ -f "$HM_PID_FILE" ]; then
    PID="$(cat "$HM_PID_FILE" 2>/dev/null)"
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
      return 0
    fi
  fi
  # 2) Fallback: detect an existing daemon even if PID file was lost (/tmp wiped, manual edits, etc.)
  PID="$(ps 2>/dev/null | awk -v n="$SCRIPT_NAME" 'index($0,"--healthmon-daemon")>0 && index($0,n)>0 {print $1; exit}')"
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    # re-seed pid file for future checks (best-effort)
    echo "$PID" >"$HM_PID_FILE" 2>/dev/null
    return 0
  fi
  return 1
}
healthmon_autostart_install() {
    # Ensure HealthMon starts after reboot when enabled
    mkdir -p /opt/etc/init.d 2>/dev/null
    cat > "$HM_AUTOSTART_FILE" <<'EOF'
#!/opt/bin/sh
# Auto-start for KZM Health Monitor (Entware init.d)
# FIXED: Added network wait for post-reboot reliability
SCRIPT="/opt/lib/opkg/keenetic_zapret2_manager.sh"
CONF="/opt/etc/healthmon.conf"
PIDFILE="/tmp/kzm2_healthmon.pid"
LOCKDIR="/tmp/kzm2_healthmon.lock"
INITLOG="/tmp/healthmon_init.log"
log_init() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$INITLOG"
}
wait_for_network() {
  local max_wait=120
  local waited=0
  local interval=5
  
  log_init "Waiting for network..."
  
  while [ $waited -lt $max_wait ]; do
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
      log_init "Network ready (waited ${waited}s)"
      return 0
    fi
    
    if ip route get 1.1.1.1 >/dev/null 2>&1; then
      log_init "Network ready via routing (waited ${waited}s)"
      return 0
    fi
    
    sleep $interval
    waited=$((waited + interval))
  done
  
  log_init "WARNING: Network timeout after ${max_wait}s, starting anyway"
  return 1
}
cleanup_stale() {
  if [ -f "$PIDFILE" ]; then
    local old_pid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$old_pid" ] && ! kill -0 "$old_pid" 2>/dev/null; then
      log_init "Removing stale PID: $old_pid"
      rm -f "$PIDFILE" 2>/dev/null
    fi
  fi
  
  if [ -d "$LOCKDIR" ]; then
    if [ -f "$LOCKDIR/pid" ]; then
      local lock_pid=$(cat "$LOCKDIR/pid" 2>/dev/null)
      if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
        log_init "Removing stale lock: $lock_pid"
        rm -rf "$LOCKDIR" 2>/dev/null
      fi
    else
      log_init "Removing orphaned lock directory"
      rm -rf "$LOCKDIR" 2>/dev/null
    fi
  fi
}
start() {
  log_init "=== Init start ==="
  
  if [ ! -f "$CONF" ] || ! grep -q '^HM_ENABLE="1"' "$CONF" 2>/dev/null; then
    log_init "HealthMon disabled in config"
    return 0
  fi
  
  cleanup_stale
  
  if [ -f "$PIDFILE" ]; then
    local pid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      log_init "Already running (PID: $pid)"
      return 0
    fi
  fi
  
  wait_for_network
  
  log_init "Starting daemon..."
  "$SCRIPT" --healthmon-daemon </dev/null >>/tmp/kzm2_healthmon.log 2>&1 &
  
  sleep 2
  if [ -f "$PIDFILE" ]; then
    local new_pid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$new_pid" ] && kill -0 "$new_pid" 2>/dev/null; then
      log_init "Started successfully (PID: $new_pid)"
      return 0
    else
      log_init "ERROR: Startup failed (PID file exists but process dead)"
      return 1
    fi
  else
    log_init "ERROR: Startup failed (no PID file)"
    return 1
  fi
}
stop() {
  log_init "=== Init stop ==="
  if [ -f "$PIDFILE" ]; then
    local pid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$pid" ]; then
      log_init "Stopping PID: $pid"
      kill "$pid" 2>/dev/null
      sleep 1
      if kill -0 "$pid" 2>/dev/null; then
        log_init "Force killing PID: $pid"
        kill -9 "$pid" 2>/dev/null
      fi
    fi
    rm -f "$PIDFILE" 2>/dev/null
  fi
  rm -rf "$LOCKDIR" 2>/dev/null
  log_init "Stopped"
}
case "$1" in
  start) start ;;
  stop) stop ;;
  restart) stop; sleep 1; start ;;
  *) start ;;
esac
exit 0
EOF
    chmod 755 "$HM_AUTOSTART_FILE" 2>/dev/null
}
healthmon_autostart_remove() {
    rm -f "$HM_AUTOSTART_FILE" 2>/dev/null
}
healthmon_start() {
    # already running? don't spawn a 2nd daemon
    healthmon_is_running && return 0
    healthmon_load_config
    HM_ENABLE="1"
    healthmon_write_config
    healthmon_autostart_install
    # Clear stale state (safe)
    rm -f "$HM_PID_FILE" 2>/dev/null
    rm -rf "$HM_LOCKDIR" 2>/dev/null
    # Start as a detached daemon by re-invoking this script
    if command -v nohup >/dev/null 2>&1; then
        nohup "$0" --healthmon-daemon </dev/null >>/tmp/kzm2_healthmon.log 2>&1 &
    else
        "$0" --healthmon-daemon </dev/null >>/tmp/kzm2_healthmon.log 2>&1 &
    fi
    # Wait up to 5s for PID to appear and process to be alive (BusyBox-safe)
    # NOTE: Each iteration checks terminal liveness. If the controlling terminal
    # is gone (SSH/Telnet disconnect, Ctrl-C), we bail out immediately to prevent
    # the main script from getting stuck in a zombie loop.
    local i pid
    for i in 1 2 3 4 5; do
        pid="$(cat "$HM_PID_FILE" 2>/dev/null)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    # Failed to start: cleanup any stale state
    rm -f "$HM_PID_FILE" 2>/dev/null
    rm -rf "$HM_LOCKDIR" 2>/dev/null
    return 1
}
healthmon_stop() {
    HM_ENABLE="0"
    healthmon_write_config
    healthmon_autostart_remove
    # Stop daemon by PID file if present
    if [ -f "$HM_PID_FILE" ]; then
        kill "$(cat "$HM_PID_FILE" 2>/dev/null)" 2>/dev/null
        sleep 1
        kill -9 "$(cat "$HM_PID_FILE" 2>/dev/null)" 2>/dev/null
        rm -f "$HM_PID_FILE" 2>/dev/null
    fi
    # Fallback: stop any stray daemon instances (e.g., PID file missing)
    ps 2>/dev/null | awk -v n="$SCRIPT_NAME" 'index($0,"--healthmon-daemon")>0 && index($0,n)>0 {print $1}' | while read -r p; do
        [ -n "$p" ] && kill "$p" 2>/dev/null
        [ -n "$p" ] && sleep 1 && kill -9 "$p" 2>/dev/null
    done
    # Clear volatile state to avoid stale counters after reboot/power loss
    rm -f /tmp/wanmon.* /tmp/healthmon_wan.* 2>/dev/null
    rm -f /tmp/kzm2_healthmon.pid /tmp/healthmon_cpu_* /tmp/healthmon_disk* /tmp/healthmon_ram* 2>/dev/null
    rm -f /tmp/healthmon_zapret_* /tmp/healthmon_last_* /tmp/healthmon_qlen.* 2>/dev/null
    rm -f /tmp/healthmon_updatecheck.* /tmp/healthmon_keendns* /tmp/healthmon_heartbeat* 2>/dev/null
    rm -rf "$HM_LOCKDIR" 2>/dev/null
}
healthmon_status() {
    healthmon_load_config
    local isrun=0
    healthmon_is_running && isrun=1
    local run_txt
    if [ "$isrun" -eq 1 ]; then
        run_txt="$(T TXT_HM_RUN_ON)"
        run_txt="${CLR_GREEN}${run_txt}${CLR_RESET}"
    else
        run_txt="$(T TXT_HM_RUN_OFF)"
        run_txt="${CLR_RED}${run_txt}${CLR_RESET}"
    fi
    local cpu load disk ram
    cpu=$(healthmon_cpu_pct)
    load=$(healthmon_loadavg)
    disk=$(healthmon_disk_used_pct /opt)
    ram=$(healthmon_mem_free_mb)
    local pid=""
    [ -f "$HM_PID_FILE" ] && pid="$(cat "$HM_PID_FILE" 2>/dev/null)"
    # zapret state
    local zst="n/a"
    if is_zapret2_installed; then
        is_zapret2_running && zst="$(T TXT_HM_ZAPRET_UP_SHORT)" || zst="$(T TXT_HM_ZAPRET_DOWN_SHORT)"
    else
        zst="$(T TXT_HM_ZAPRET_NA_SHORT)"
    fi
    # translate auto-update mode
    local mode_txt
    case "${HM_AUTOUPDATE_MODE:-0}" in
        2) mode_txt="$(T TXT_HM_MODE2)" ;;
        1) mode_txt="$(T TXT_HM_MODE1)" ;;
        *) mode_txt="$(T TXT_HM_MODE0)" ;;
    esac
    local upd_word
    if [ "${HM_UPDATECHECK_ENABLE:-0}" = "1" ]; then
        upd_word="$(T TXT_HM_WORD_ON)"
    else
        upd_word="$(T TXT_HM_WORD_OFF)"
    fi
    local _w=24
    local _lbl
    hm_kv() {
        # $1=label, $2=value
        _lbl="$1"
        _lbl="${_lbl%:}"
        printf "  %-*s : %s\n" "$_w" "$_lbl" "$2"
    }
    clear_screen
    print_line "="
    printf "%b%s%b\n" "${CLR_CYAN}" "$(T TXT_HM_STATUS_TITLE)" "${CLR_RESET}"
    print_line "="
    echo
    # Status line
    _lbl="$(T TXT_HM_STATUS_RUNNING)"; _lbl="${_lbl%:}"
    printf "  %-*s : %s (%s=%s%s)\n" "$_w" "$_lbl" "$run_txt" "$(T TXT_HM_ENABLE_LABEL)" "$HM_ENABLE" "${pid:+, pid=$pid}"
    echo
    printf "%b%s%b\n" "${CLR_CYAN}" "$(T TXT_HM_STATUS_SEC_SETTINGS)" "${CLR_RESET}"
    print_line "-"
    hm_kv "$(T TXT_HM_STATUS_INTERVAL)" "${HM_INTERVAL}s"
    hm_kv "$(T TXT_HM_CFG_ITEM10)" "${HM_HEARTBEAT_SEC}s"
    hm_kv "$(T TXT_HM_CFG_ITEM9)" "${HM_COOLDOWN_SEC}s"
    hm_kv "$(T TXT_HM_STATUS_UPDATECHECK)" "${upd_word}=${HM_UPDATECHECK_ENABLE}, $(T TXT_HM_FLAG_EVERY)=${HM_UPDATECHECK_SEC}s"
    hm_kv "$(T TXT_HM_STATUS_AUTOUPDATE)" "${mode_txt} ($(T TXT_HM_FLAG_MODE)=${HM_AUTOUPDATE_MODE:-0})"
    echo
    printf "%b%s%b\n" "${CLR_CYAN}" "$(T TXT_HM_STATUS_SEC_THRESH)" "${CLR_RESET}"
    print_line "-"
    hm_kv "$(T TXT_HM_STATUS_CPU_WARN)" "${HM_CPU_WARN}% / ${HM_CPU_WARN_DUR}s"
    hm_kv "$(T TXT_HM_STATUS_CPU_CRIT)" "${HM_CPU_CRIT}% / ${HM_CPU_CRIT_DUR}s"
    hm_kv "$(T TXT_HM_STATUS_DISK_WARN)" "${HM_DISK_WARN}%"
    hm_kv "$(T TXT_HM_STATUS_RAM_WARN)" "<= ${HM_RAM_WARN_MB} MB"
    echo
    printf "%b%s%b\n" "${CLR_CYAN}" "$(T TXT_HM_STATUS_SEC_ZAPRET)" "${CLR_RESET}"
    print_line "-"
    hm_kv "$(T TXT_HM_STATUS_ZAPRET_WD)" "$HM_ZAPRET_WATCHDOG"
    hm_kv "$(T TXT_HM_STATUS_ZAPRET_CD)" "${HM_ZAPRET_COOLDOWN_SEC}s"
    hm_kv "$(T TXT_HM_STATUS_ZAPRET_AR)" "$HM_ZAPRET_AUTORESTART"
    hm_kv "$(T _ 'NFQUEUE kuyruk denetimi' 'NFQUEUE qlen watchdog')" "$(T _ 'denetim' 'monitor')=${HM_QLEN_WATCHDOG} $(T _ 'esik' 'thresh')=${HM_QLEN_WARN_TH} $(T _ 'tur' 'turn')=${HM_QLEN_CRIT_TURNS}"
    hm_kv "$(T TXT_HM_NFQWS_ALERT_ITEM)" "$(T _ 'alarm' 'alert')=${HM_NFQWS_ALERT:-1}"
    hm_kv "$(T _ 'WAN izleme' 'WAN monitoring')" "$(T _ 'acik' 'on')=${HM_WANMON_ENABLE:-0} $(T _ 'kesinti' 'fail')=${HM_WANMON_FAIL_TH:-3} $(T _ 'toparlanma' 'ok')=${HM_WANMON_OK_TH:-2} (${HM_WANMON_IFACE:-auto})"
    hm_kv "$(T _ 'KeenDNS curl araligi' 'KeenDNS curl interval')" "${HM_KEENDNS_CURL_SEC}s"
    hm_kv "$(T _ 'Sistem log izleme' 'System log watch')" "$(T _ "ac=${HM_SYSLOG_WATCH} cd=${HM_SYSLOG_COOLDOWN_SEC}s ike_cd=${HM_SYSLOG_IKE_COOLDOWN_SEC}s" "on=${HM_SYSLOG_WATCH} cd=${HM_SYSLOG_COOLDOWN_SEC}s ike_cd=${HM_SYSLOG_IKE_COOLDOWN_SEC}s")"
    echo
    printf "%b%s%b\n" "${CLR_CYAN}" "$(T TXT_HM_STATUS_SEC_NOW)" "${CLR_RESET}"
    print_line "-"
    local _load1 _load5 _load15 _nproc
    _load1="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
    _load5="$(awk '{print $2}' /proc/loadavg 2>/dev/null)"
    _load15="$(awk '{print $3}' /proc/loadavg 2>/dev/null)"
    _nproc="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)"
    [ -z "$_nproc" ] || [ "$_nproc" -eq 0 ] 2>/dev/null && _nproc=1
    printf "  %-24s : %s%%
" "$(T _ 'CPU Kullanimi' 'CPU Usage')" "$cpu"
    printf "  %-24s : %s: %s  | %s: %s  | %s: %s
" \
        "$(T _ 'CPU Yuku' 'CPU Load')" \
        "$(T _ '1dk' '1min')" "$_load1" \
        "$(T _ '5dk' '5min')" "$_load5" \
        "$(T _ '15dk' '15min')" "$_load15"
    printf "  %-24s : %s MB | %s %s%% | %s %s
"         "$(T TXT_HM_STATUS_RAM_FREE)" "$ram"         "$(T TXT_HM_STATUS_DISK_OPT)" "$disk"         "$(T TXT_HM_STATUS_ZAPRET)" "$zst"
    # CPU sicakligi
    local _temp_simdi=""
    for _tf in /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$_tf" ] || continue
        _tv="$(cat "$_tf" 2>/dev/null)"
        if [ -n "$_tv" ]; then
            _temp_simdi="$(awk -v t="$_tv" 'BEGIN{printf "%.0f", t/1000}')"
            break
        fi
    done
    if [ -n "$_temp_simdi" ]; then
        printf "  %-24s : %s
" "$(T _ 'SoC Sicakligi' 'SoC Temperature')"             "$_temp_simdi $(T _ 'Santigrat Derece' 'Degrees Celsius')"
    fi
    # RAM / Swap / Buffer / Disk detay
    local _st_total_kb _st_used_kb _st_buf_kb _st_cached_kb _st_swap_total _st_swap_free _st_ram_total
    _st_total_kb="$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')"
    _st_ram_total="$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')"
    _st_used_kb=$(( _st_ram_total - _st_total_kb ))
    _st_buf_kb="$(grep '^Buffers:' /proc/meminfo 2>/dev/null | awk '{print $2}')"
    _st_cached_kb="$(grep '^Cached:' /proc/meminfo 2>/dev/null | awk '{print $2}' | head -1)"
    _st_swap_total="$(grep SwapTotal /proc/meminfo 2>/dev/null | awk '{print $2}')"
    _st_swap_free="$(grep SwapFree /proc/meminfo 2>/dev/null | awk '{print $2}')"
    local _w2=24
    printf "  %-*s : %s/%s MB
" "$_w2" "$(T _ 'RAM Kullanilan' 'RAM Used')" "$(( _st_used_kb/1024 ))" "$(( _st_ram_total/1024 ))"
    printf "  %-*s : %s MB
"    "$_w2" "$(T _ 'RAM Bos (Kullanilabilir)' 'RAM Free (Available)')" "$(( _st_total_kb/1024 ))"
    printf "  %-*s : %s MB
"    "$_w2" "$(T _ 'Buffer/Cache' 'Buffer/Cache')" "$(( (_st_buf_kb+_st_cached_kb)/1024 ))"
    printf "  %-*s : %s/%s MB
" "$_w2" "$(T _ 'Swap Kullanilan' 'Swap Used')" "$(( (_st_swap_total-_st_swap_free)/1024 ))" "$(( _st_swap_total/1024 ))"
    local _dt_pct _dt_used2 _dt_total2
    _dt_pct="$(df -k /tmp 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
    _dt_used2="$(df -k /tmp 2>/dev/null | awk 'NR==2 {printf "%d", $3/1024}')"
    _dt_total2="$(df -k /tmp 2>/dev/null | awk 'NR==2 {printf "%.1fMB", $2/1024}')"
    printf "  %-*s : %sMB / %s (%s%%)
" "$_w2" "$(T _ 'Disk /tmp' 'Disk /tmp')" "${_dt_used2}" "${_dt_total2}" "${_dt_pct:-?}"
    echo
}
healthmon_test() {
    local cpu load disk ram
    cpu=$(healthmon_cpu_pct)
    load=$(healthmon_loadavg)
    disk=$(healthmon_disk_used_pct /opt)
    ram=$(healthmon_mem_free_mb)
    telegram_send "$(tpl_render "$(T TXT_HM_TEST_MSG)" CPU "$cpu" LOAD "$load" RAM "$ram" DISK "$disk")"
}
healthmon_config_menu() {
    healthmon_load_config
    # helper: ask number with current value, empty keeps current
    hm_ask_num_raw() {
        local _label="$1" _var="$2" _cur _v
        eval _cur="\${$_var}"
        printf "%s [%s]: " "$_label" "${_cur:-}"
        read -r _v
        [ -z "$_v" ] && return 0
        case "$_v" in
            ''|*[!0-9]*) echo "$(T _ 'Gecersiz deger, degistirilmedi.' 'Invalid value, not changed.')"; return 0 ;;
        esac
        eval "$_var="$_v""
        echo "$(T _ 'Kaydedildi:' 'Saved:') ${_v}"
    }
    hm_ask_num() {
        local _label="$1" _var="$2" _cur _v _sec _readable
        eval _cur="\${$_var}"
        # Mevcut degeri okunabilir formatla goster
        _readable=""
        if [ -n "$_cur" ] && [ "$_cur" -gt 0 ] 2>/dev/null; then
            if [ "$_cur" -ge 3600 ] && [ "$((_cur % 3600))" -eq 0 ]; then
                _readable=" = $((_cur/3600)) sa"
            elif [ "$_cur" -ge 60 ] && [ "$((_cur % 60))" -eq 0 ]; then
                _readable=" = $((_cur/60)) dk"
            else
                _readable=" = ${_cur} sn"
            fi
        fi
        printf "%s [%s%s] (ornek: 300s/5m/2h): " "$_label" "${_cur:-}" "$_readable"
        read -r _v
        [ -z "$_v" ] && return 0
        # Birim parse: 5m, 2h, 300s veya duz sayi
        case "$_v" in
            *h) _num="${_v%h}"; _sec=$((_num * 3600)) ;;
            *m) _num="${_v%m}"; _sec=$((_num * 60))   ;;
            *s) _num="${_v%s}"; _sec="$_num"           ;;
            *)  _sec="$_v"                              ;;
        esac
        # Sayi dogrulama
        case "$_sec" in
            *[!0-9]*)
                print_status WARN "$(T _ 'Gecersiz deger, atlandi. (ornek: 300s, 5m, 2h)' 'Invalid value, skipped. (example: 300s, 5m, 2h)')"
                ;;
            *)
                eval "$_var=\"$_sec\""
                # Onay mesaji
                if [ "$_sec" -ge 3600 ] && [ "$((_sec % 3600))" -eq 0 ]; then
                    print_status INFO "$(T _ 'Kaydedildi' 'Saved'): ${_sec}s = $((_sec/3600)) sa"
                elif [ "$_sec" -ge 60 ] && [ "$((_sec % 60))" -eq 0 ]; then
                    print_status INFO "$(T _ 'Kaydedildi' 'Saved'): ${_sec}s = $((_sec/60)) dk"
                else
                    print_status INFO "$(T _ 'Kaydedildi' 'Saved'): ${_sec}s"
                fi
                ;;
        esac
    }
    hm_ask_01() {
        local _label="$1" _var="$2" _cur _v
        eval _cur="\${$_var}"
        printf "%s (0/1) [%s]: " "$_label" "${_cur:-}"
        read -r _v
        if [ -n "$_v" ]; then
            case "$_v" in
                0|1) eval "$_var=\"$_v\"" ;;
                *) print_status WARN "$(T _ 'Gecersiz secim, atlandi.' 'Invalid choice, skipped.')" ;;
            esac
        fi
    }
    while true; do
        clear
        print_line "="
        echo "$(T TXT_HM_CFG_TITLE)"
        print_line "="
        echo
                local _w=24
        printf " %2s) %-*s : %s\n" "1" "$_w" "$(T _ 'CPU WARN % / sure' 'CPU WARN % / dur.')"  "$HM_CPU_WARN / $HM_CPU_WARN_DUR"
        printf " %2s) %-*s : %s\n" "2" "$_w" "$(T _ 'CPU CRIT % / sure' 'CPU CRIT % / dur.')"  "$HM_CPU_CRIT / $HM_CPU_CRIT_DUR"
        printf " %2s) %-*s : %s\n" "3" "$_w" "$(T _ 'Disk(/opt) esigi %' 'Disk(/opt) threshold %')" "$HM_DISK_WARN"
        printf " %2s) %-*s : %s\n" "4" "$_w" "$(T _ 'RAM esigi (MB)' 'RAM threshold (MB)')"     "$HM_RAM_WARN_MB"
        printf " %2s) %-*s : %s\n" "5" "$_w" "$(T TXT_HM_CFG_ITEM5)" "$(T _ 'denetim' 'monitor')=$HM_ZAPRET_WATCHDOG | $(T _ 'bekleme' 'cooldown')=${HM_ZAPRET_COOLDOWN_SEC}s | $(T _ 'oto-restart' 'auto-restart')=$HM_ZAPRET_AUTORESTART"
        local _en_lbl _ev_lbl
        _en_lbl="$(T TXT_HM_FLAG_ENABLED)"
        _ev_lbl="$(T TXT_HM_FLAG_EVERY)"
        printf " %2s) %-*s : %s\n" "6" "$_w" "$(T TXT_HM_CFG_ITEM6)" "${_en_lbl}=${HM_UPDATECHECK_ENABLE} ${_ev_lbl}=${HM_UPDATECHECK_SEC}s"
        printf " %2s) %-*s : %s\n" "7" "$_w" "$(T TXT_HM_CFG_ITEM7)" "$HM_AUTOUPDATE_MODE ($(T TXT_HM_AUTOUPDATE_MODE_HINT))"
        printf " %2s) %-*s : %s\n" "8" "$_w" "$(T TXT_HM_CFG_ITEM8)" "$HM_INTERVAL"
        printf " %2s) %-*s : %s\n" "9" "$_w" "$(T TXT_HM_CFG_ITEM9)" "$HM_COOLDOWN_SEC"
        printf " %2s) %-*s : %s\n" "10" "$_w" "$(T TXT_HM_CFG_ITEM10)" "$HM_HEARTBEAT_SEC"
        printf " %2s) %-*s : %s\n" "11" "$_w" "$(T TXT_HM_CFG_ITEM11)" "$(T _ 'acik' 'on')=$HM_WANMON_ENABLE $(T _ 'kesinti' 'fail')=$HM_WANMON_FAIL_TH $(T _ 'toparlanma' 'ok')=$HM_WANMON_OK_TH (${HM_WANMON_IFACE:-auto})"
        printf " %2s) %-*s : %s\n" "12" "$_w" "$(T TXT_HM_CFG_ITEM12)" "$(T _ 'denetim' 'monitor')=${HM_QLEN_WATCHDOG} $(T _ 'esik' 'thresh')=${HM_QLEN_WARN_TH} $(T _ 'tur' 'turn')=${HM_QLEN_CRIT_TURNS} | keendns=${HM_KEENDNS_CURL_SEC}s"
        printf " %2s) %-*s : %s\n" "13" "$_w" "$(T _ 'Sistem log izleme' 'System log watch')" "$(T _ "ac=${HM_SYSLOG_WATCH} cd=${HM_SYSLOG_COOLDOWN_SEC}s ike_cd=${HM_SYSLOG_IKE_COOLDOWN_SEC}s" "on=${HM_SYSLOG_WATCH} cd=${HM_SYSLOG_COOLDOWN_SEC}s ike_cd=${HM_SYSLOG_IKE_COOLDOWN_SEC}s")"
        printf " %2s) %-*s : %s\n" "14" "$_w" "$(T TXT_HM_CFG_ITEM14)" "${HM_DEBUG:-0}"
        printf " %2s) %-*s : %s\n" "15" "$_w" "$(T TXT_HM_NFQWS_ALERT_ITEM)" "${HM_NFQWS_ALERT:-1}"
        if [ -f "/opt/zapret2/wan_if" ]; then
            printf " %2s) %b%s%b\n" "16" "${CLR_BOLD}" "$(T TXT_HM_CFG_ITEM15)" "${CLR_RESET}"
        fi
echo
        printf "  %s) %s\n" "S" "$(T _ 'Kaydet ve uygula' 'Save & apply')"
        printf "  %s) %s\n" "0" "$(T _ 'Geri (kaydetmeden)' 'Back (without saving)')"
        echo
        printf '%s' "$(T _ 'Secim: ' 'Choice: ')"; read -r _c || return 0
        case "$_c" in
            1)
                hm_ask_num "$(T TXT_HM_PROMPT_CPU_WARN)" HM_CPU_WARN
                hm_ask_num "$(T TXT_HM_PROMPT_CPU_WARN_DUR)" HM_CPU_WARN_DUR
                ;;
            2)
                hm_ask_num "$(T TXT_HM_PROMPT_CPU_CRIT)" HM_CPU_CRIT
                hm_ask_num "$(T TXT_HM_PROMPT_CPU_CRIT_DUR)" HM_CPU_CRIT_DUR
                ;;
            3)
                hm_ask_num "$(T TXT_HM_PROMPT_DISK_WARN)" HM_DISK_WARN
                ;;
            4)
                hm_ask_num "$(T TXT_HM_PROMPT_RAM_WARN)" HM_RAM_WARN_MB
                ;;
            5)
                hm_ask_01 "$(T TXT_HM_PROMPT_ZAPRET_WD)" HM_ZAPRET_WATCHDOG
                hm_ask_num "$(T TXT_HM_PROMPT_ZAPRET_COOLDOWN)" HM_ZAPRET_COOLDOWN_SEC
                hm_ask_01 "$(T TXT_HM_PROMPT_ZAPRET_AUTORESTART)" HM_ZAPRET_AUTORESTART
                ;;
            6)
                hm_ask_01 "$(T TXT_HM_PROMPT_UPDATECHECK_ENABLE)" HM_UPDATECHECK_ENABLE
                hm_ask_num "$(T TXT_HM_PROMPT_UPDATECHECK_SEC)" HM_UPDATECHECK_SEC
                ;;
            7)
                printf "%s [%s]: " "$(T TXT_HM_PROMPT_AUTOUPDATE_MODE)" "${HM_AUTOUPDATE_MODE:-}"
                read -r _v
                if [ -n "$_v" ]; then
                    case "$_v" in
                        0|1) HM_AUTOUPDATE_MODE="$_v" ;;
                        2)healthmon_print_autoupdate_warning
printf '%s' "$(T TXT_HM_AUTOUPDATE_WARN_L3)"; read -r _w
                            case "$_w" in
    y|Y|e|E)
        HM_AUTOUPDATE_MODE="2"
        _msg="$(T TXT_HM_AUTOUPDATE_SET_MSG)"
        _msg="$(tpl_render "$_msg" MODE "2")"
        print_status PASS "$_msg"
        ;;
    n|N|h|H|"")
        HM_AUTOUPDATE_MODE="1"
        _msg="$(T TXT_HM_AUTOUPDATE_SET_MSG)"
        _msg="$(tpl_render "$_msg" MODE "1")"
        print_status INFO "$_msg"
        ;;
    *)
        HM_AUTOUPDATE_MODE="1"
        print_status WARN "$(T TXT_INVALID_CHOICE)"
        _msg="$(T TXT_HM_AUTOUPDATE_SET_MSG)"
        _msg="$(tpl_render "$_msg" MODE "1")"
        print_status INFO "$_msg"
        ;;
esac
                            ;;
                        *) print_status WARN "$(T TXT_INVALID_CHOICE)" ;;
                    esac
                fi
                ;;
            8)
                hm_ask_num "$(T _ 'Interval (sec)' 'Interval (sec)')" HM_INTERVAL
                ;;
            9)
                hm_ask_num "$(T _ 'Cooldown (sec)' 'Cooldown (sec)')" HM_COOLDOWN_SEC
                ;;
            10)
                hm_ask_num "$(T _ 'Heartbeat (sec)' 'Heartbeat (sec)')" HM_HEARTBEAT_SEC
                ;;
            11)
                hm_ask_01 "$(T TXT_HM_PROMPT_WANMON_ENABLE)" HM_WANMON_ENABLE
                hm_ask_num_raw "$(T TXT_HM_PROMPT_WANMON_FAIL_TH)" HM_WANMON_FAIL_TH
                hm_ask_num_raw "$(T TXT_HM_PROMPT_WANMON_OK_TH)" HM_WANMON_OK_TH
                print_status INFO "$(T _ \'NDM WAN: \' \'NDM WAN: \')$(healthmon_detect_wan_iface_ndm)"
                ;;
            12)
                hm_ask_01  "$(T _ 'NFQUEUE kuyruk denetimi (0=kapat 1=ac)' 'NFQUEUE qlen watchdog (0=off 1=on)')" HM_QLEN_WATCHDOG
                hm_ask_num_raw "$(T _ 'qlen esigi (paket sayisi)' 'qlen threshold (packet count)')" HM_QLEN_WARN_TH
                hm_ask_num_raw "$(T _ 'Ardisik yuksek tur sayisi -> restart' 'Consecutive high turns -> restart')" HM_QLEN_CRIT_TURNS
                hm_ask_num "$(T _ 'KeenDNS curl araligi (sn, 0=her tur)' 'KeenDNS curl interval (sec, 0=every loop)')" HM_KEENDNS_CURL_SEC
                ;;
            13)
                hm_ask_01  "$(T _ 'Sistem log izleme (0=kapat 1=ac)' 'System log watch (0=off 1=on)')" HM_SYSLOG_WATCH
                hm_ask_num "$(T _ 'Kritik olay cooldown (sn)' 'Critical event cooldown (sec)')" HM_SYSLOG_COOLDOWN_SEC
                hm_ask_num "$(T _ 'IKE bildirim cooldown (sn, varsayilan 3600)' 'IKE alert cooldown (sec, default 3600)')" HM_SYSLOG_IKE_COOLDOWN_SEC
                press_enter_to_continue
                ;;
            14)
                printf "%b%s%b\n" "${CLR_ORANGE}" "$(T _ 'UYARI: Bu modu sadece gelistirici sizden acmanizi istediginde veya ek log bilgisi gerektiginde acin.' 'WARNING: Only enable this mode when a developer asks you to or when additional logging is needed.')" "${CLR_RESET}"
                printf "%b%s%b\n\n" "${CLR_ORANGE}" "$(T _ 'Aksi halde sistem performansini olumsuz etkiler.' 'Otherwise it may negatively affect system performance.')" "${CLR_RESET}"
                hm_ask_01 "$(T _ 'Debug modu (0=kapat 1=ac)' 'Debug mode (0=off 1=on)')" HM_DEBUG
                ;;
            15)
                hm_ask_01 "$(T _ 'nfqws2 kuyruk alarmi (0=kapat 1=ac)' 'nfqws2 queue alert (0=off 1=on)')" HM_NFQWS_ALERT
                ;;
            16)
                if [ ! -f "/opt/zapret2/wan_if" ]; then return 0; fi
                _wan_if_rec="$(cat /opt/zapret2/wan_if 2>/dev/null | tr -d '[:space:]')"
                print_line "-"
                printf "%b%s%b\n" "${CLR_ORANGE}${CLR_BOLD}" "$(T _ 'Onerilen ayarlar uygulanacak. Onayliyor musunuz?' 'Recommended settings will be applied. Confirm?')" "${CLR_RESET}"
                echo ""
                printf "%s" "$(T _ '(e/h): ' '(y/n): ')"; read -r _ans
                echo "$_ans" | grep -qi '^[ey]' || { echo "$(T _ 'Iptal edildi.' 'Cancelled.')"; press_enter_to_continue; continue; }
                HM_ENABLE="1"
                HM_CPU_WARN="70"
                HM_CPU_WARN_DUR="180"
                HM_CPU_CRIT="90"
                HM_CPU_CRIT_DUR="60"
                HM_DISK_WARN="90"
                HM_RAM_WARN_MB="40"
                HM_ZAPRET_WATCHDOG="1"
                HM_ZAPRET_COOLDOWN_SEC="120"
                HM_ZAPRET_AUTORESTART="1"
                HM_UPDATECHECK_ENABLE="1"
                HM_UPDATECHECK_SEC="43200"
                HM_AUTOUPDATE_MODE="2"
                HM_INTERVAL="60"
                HM_COOLDOWN_SEC="600"
                HM_HEARTBEAT_SEC="300"
                HM_WANMON_ENABLE="1"
                HM_WANMON_FAIL_TH="2"
                HM_WANMON_OK_TH="2"
                HM_WANMON_IFACE="$_wan_if_rec"
                HM_QLEN_WATCHDOG="1"
                HM_QLEN_WARN_TH="50"
                HM_QLEN_CRIT_TURNS="2"
                HM_KEENDNS_CURL_SEC="120"
                HM_SYSLOG_WATCH="1"
                HM_SYSLOG_COOLDOWN_SEC="600"
                HM_SYSLOG_IKE_COOLDOWN_SEC="7200"
                HM_DEBUG="0"
                HM_NFQWS_ALERT="1"
                healthmon_write_config
                healthmon_stop 2>/dev/null
                healthmon_start
                print_status PASS "$(T _ 'Onerilen ayarlar uygulandi.' 'Recommended settings applied.')"
                press_enter_to_continue
                ;;
            s|S)
                healthmon_write_config
                if healthmon_is_running; then
                    healthmon_stop 2>/dev/null
                    healthmon_start
                fi
                print_status PASS "$(T _ 'Ayarlar kaydedildi.' 'Settings saved.')"
                return 0
                ;;
            0)
                return 0
                ;;
            *)
                print_status WARN "$(T TXT_INVALID_CHOICE)"
                sleep 1
                ;;
        esac
    done
}
# =============================================================================
# ZAMANLI YENIDEN BASLAT (Scheduled Reboot via Cron)
# =============================================================================
# TR/EN Dictionary (Scheduled Reboot)
TXT_SCHED_TITLE_TR="Zamanli Yeniden Baslat"
TXT_SCHED_TITLE_EN="Scheduled Reboot"
TXT_SCHED_STATUS_TR="Mevcut Zamanlama"
TXT_SCHED_STATUS_EN="Current Schedule"
TXT_SCHED_NONE_TR="Zamanlama yok"
TXT_SCHED_NONE_EN="No schedule set"
TXT_SCHED_CROND_WARN_TR="UYARI: cron servisi (crond) calismiyor! Zamanlama aktif olmayacak."
TXT_SCHED_CROND_WARN_EN="WARNING: cron service (crond) is not running! Schedule will not be active."
TXT_SCHED_TIME_WARN_TR="UYARI: Router saatinin dogru oldugunu kontrol edin (Sistem Ayarlari > Genel)."
TXT_SCHED_TIME_WARN_EN="WARNING: Make sure the router time is set correctly (System Settings > General)."
TXT_SCHED_MENU_1_TR="1. Mevcut Zamanlamayi Goster"
TXT_SCHED_MENU_1_EN="1. Show Current Schedule"
TXT_SCHED_MENU_2_TR="2. Gunluk Yeniden Baslat Ekle/Guncelle"
TXT_SCHED_MENU_2_EN="2. Add/Update Daily Reboot"
TXT_SCHED_MENU_3_TR="3. Haftalik Yeniden Baslat Ekle/Guncelle"
TXT_SCHED_MENU_3_EN="3. Add/Update Weekly Reboot"
TXT_SCHED_MENU_4_TR="4. Zamanlamayi Sil"
TXT_SCHED_MENU_4_EN="4. Delete Schedule"
TXT_SCHED_MENU_0_TR="0. Geri Don"
TXT_SCHED_MENU_0_EN="0. Back"
TXT_SCHED_PROMPT_TR="Seciminiz (0-4): "
TXT_SCHED_PROMPT_EN="Your choice (0-4): "
TXT_SCHED_HOUR_TR="Saat girin (0-23): "
TXT_SCHED_HOUR_EN="Enter hour (0-23): "
TXT_SCHED_MIN_TR="Dakika girin (0-59): "
TXT_SCHED_MIN_EN="Enter minute (0-59): "
TXT_SCHED_DOW_TR="Hangi gun? (0=Pazar, 1=Pzt, 2=Sal, 3=Car, 4=Per, 5=Cum, 6=Cmt): "
TXT_SCHED_DOW_EN="Which day? (0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat): "
TXT_SCHED_INVALID_HOUR_TR="Gecersiz saat! 0-23 arasinda olmali."
TXT_SCHED_INVALID_HOUR_EN="Invalid hour! Must be between 0 and 23."
TXT_SCHED_INVALID_MIN_TR="Gecersiz dakika! 0-59 arasinda olmali."
TXT_SCHED_INVALID_MIN_EN="Invalid minute! Must be between 0 and 59."
TXT_SCHED_INVALID_DOW_TR="Gecersiz gun! 0-6 arasinda olmali."
TXT_SCHED_INVALID_DOW_EN="Invalid day! Must be between 0 and 6."
TXT_SCHED_ADDED_TR="Zamanlama eklendi/guncellendi."
TXT_SCHED_ADDED_EN="Schedule added/updated."
TXT_SCHED_DELETED_TR="Zamanlama silindi."
TXT_SCHED_DELETED_EN="Schedule deleted."
TXT_SCHED_DEL_NONE_TR="Silinecek zamanlama bulunamadi."
TXT_SCHED_DEL_NONE_EN="No schedule found to delete."
TXT_SCHED_CONFIRM_DEL_TR="Zamanli yeniden baslatma silinsin mi? (e/h): "
TXT_SCHED_CONFIRM_DEL_EN="Delete scheduled reboot? (y/n): "
TXT_SCHED_DAILY_SET_TR="Gunluk yeniden baslat: Her gun saat %HOUR%"
TXT_SCHED_DAILY_SET_EN="Daily reboot: Every day at %HOUR%"
TXT_SCHED_WEEKLY_SET_TR="Haftalik yeniden baslat: Her hafta saat %HOUR% (Gun: %DOW%)"
TXT_SCHED_WEEKLY_SET_EN="Weekly reboot: Every week at %HOUR% (Day: %DOW%)"
# TR/EN Dictionary (Scheduled OPKG Upgrade)
TXT_OPKG_SCHED_TITLE_TR="[KZM2] Zamanlanmis OPKG Guncelleme"
TXT_OPKG_SCHED_TITLE_EN="[KZM2] Scheduled OPKG Upgrade"
TXT_OPKG_SCHED_STATUS_TR="Mevcut Zamanlama"
TXT_OPKG_SCHED_STATUS_EN="Current Schedule"
TXT_OPKG_SCHED_NONE_TR="Zamanlama yok"
TXT_OPKG_SCHED_NONE_EN="No schedule set"
TXT_OPKG_SCHED_MENU_1_TR="1. Haftalik (Her Pazar 03:00)"
TXT_OPKG_SCHED_MENU_1_EN="1. Weekly (Every Sunday 03:00)"
TXT_OPKG_SCHED_MENU_2_TR="2. 2 Haftada Bir (1. ve 15. gun 03:00)"
TXT_OPKG_SCHED_MENU_2_EN="2. Biweekly (1st and 15th at 03:00)"
TXT_OPKG_SCHED_MENU_3_TR="3. Aylik (Her ayin 1'i 03:00)"
TXT_OPKG_SCHED_MENU_3_EN="3. Monthly (1st of month at 03:00)"
TXT_OPKG_SCHED_MENU_4_TR="4. Zamanlamayi Sil"
TXT_OPKG_SCHED_MENU_4_EN="4. Delete Schedule"
TXT_OPKG_SCHED_MENU_0_TR="0. Geri Don"
TXT_OPKG_SCHED_MENU_0_EN="0. Back"
TXT_OPKG_SCHED_PROMPT_TR="Seciminiz (0-4): "
TXT_OPKG_SCHED_PROMPT_EN="Your choice (0-4): "
TXT_OPKG_SCHED_ADDED_TR="Zamanlama eklendi/guncellendi."
TXT_OPKG_SCHED_ADDED_EN="Schedule added/updated."
TXT_OPKG_SCHED_DELETED_TR="Zamanlama silindi."
TXT_OPKG_SCHED_DELETED_EN="Schedule deleted."
TXT_OPKG_SCHED_DEL_NONE_TR="Silinecek zamanlama bulunamadi."
TXT_OPKG_SCHED_DEL_NONE_EN="No schedule found to delete."
TXT_OPKG_SCHED_WEEKLY_SET_TR="Haftalik: Her Pazar saat %HOUR%"
TXT_OPKG_SCHED_WEEKLY_SET_EN="Weekly: Every Sunday at %HOUR%"
TXT_OPKG_SCHED_BIWEEKLY_SET_TR="2 Haftada bir: 1. ve 15. gun saat %HOUR%"
TXT_OPKG_SCHED_BIWEEKLY_SET_EN="Biweekly: 1st and 15th at %HOUR%"
TXT_OPKG_SCHED_MONTHLY_SET_TR="Aylik: Her ayin 1'i saat %HOUR%"
TXT_OPKG_SCHED_MONTHLY_SET_EN="Monthly: 1st of month at %HOUR%"
TXT_OPKG_SCHED_BANNER_LABEL_TR="OPKG Guncelleme"
TXT_OPKG_SCHED_BANNER_LABEL_EN="OPKG Upgrade"
TXT_OPKG_SCHED_RUN_START_TR="Zamanlanmis OPKG guncelleme basliyor..."
TXT_OPKG_SCHED_RUN_START_EN="Scheduled OPKG upgrade starting..."
TXT_OPKG_SCHED_RUN_NOUPDATE_TR="✅ Guncellenecek paket bulunamadi."
TXT_OPKG_SCHED_RUN_NOUPDATE_EN="✅ No packages to upgrade."
TXT_OPKG_SCHED_RUN_OK_TR="✅ OPKG guncelleme tamamlandi. Yukseltilen: %COUNT% paket."
TXT_OPKG_SCHED_RUN_OK_EN="✅ OPKG upgrade completed. Upgraded: %COUNT% packages."
TXT_OPKG_SCHED_RUN_FAIL_TR="❌ OPKG guncelleme basarisiz."
TXT_OPKG_SCHED_RUN_FAIL_EN="❌ OPKG upgrade failed."
TXT_OPKG_SCHED_TIME_WARN_TR="UYARI: Router saatinin dogru oldugunu kontrol edin (Sistem Ayarlari > Genel)."
TXT_OPKG_SCHED_TIME_WARN_EN="WARNING: Make sure the router time is set correctly (System Settings > General)."
# TR/EN Dictionary (Scheduled Tasks wrapper menu)
TXT_SCHED_TASKS_TITLE_TR="Zamanlanmis Gorevler (Cron)"
TXT_SCHED_TASKS_TITLE_EN="Scheduled Tasks (Cron)"
TXT_SCHED_TASKS_MENU_1_TR="1. Zamanli Yeniden Baslat"
TXT_SCHED_TASKS_MENU_1_EN="1. Scheduled Reboot"
TXT_SCHED_TASKS_MENU_2_TR="2. Zamanlanmis OPKG Guncelleme"
TXT_SCHED_TASKS_MENU_2_EN="2. Scheduled OPKG Upgrade"
TXT_SCHED_TASKS_MENU_0_TR="0. Geri Don"
TXT_SCHED_TASKS_MENU_0_EN="0. Back"
TXT_SCHED_TASKS_PROMPT_TR="Seciminiz (0-2): "
TXT_SCHED_TASKS_PROMPT_EN="Your choice (0-2): "
# Crontab'daki KZM reboot satirini tanimlayan etiket
KZM_REBOOT_TAG="# KZM_REBOOT"
# crond calisiyor mu kontrol et (ps -w ile)
_sched_crond_running() {
    ps -w 2>/dev/null | awk '/cron/ && !/awk/{found=1} END{exit !found}'
}
# Mevcut KZM_REBOOT satirini oku (yoksa bos doner)
_sched_get_current() {
    crontab -l 2>/dev/null | awk '/KZM_REBOOT/'
}
# Crontab'dan KZM_REBOOT satirini kaldir
_sched_remove() {
    local _tmp="/tmp/kzm_cron_remove.$$"
    crontab -l 2>/dev/null | grep -v '^#' | grep -v "$KZM_REBOOT_TAG" | grep -v '^[[:space:]]*$' > "$_tmp"
    crontab "$_tmp"
    rm -f "$_tmp"
}
# Crontab'a KZM_REBOOT satiri ekle
# $1: min  $2: hour  $3: dow (* = her gun)
_sched_write() {
    local _min="$1" _hour="$2" _dow="$3"
    local _tmp="/tmp/kzm_cron_write.$$"
    crontab -l 2>/dev/null | grep -v '^#' | grep -v "$KZM_REBOOT_TAG" | grep -v '^[[:space:]]*$' > "$_tmp"
    printf '%s %s * * %s LD_LIBRARY_PATH= ndmc -c "system reboot" %s\n' \
        "$_min" "$_hour" "$_dow" "$KZM_REBOOT_TAG" >> "$_tmp"
    crontab "$_tmp"
    rm -f "$_tmp"
}
# Mevcut satiri okunabilir formatta goster
_sched_show_current() {
    local _cur
    _cur="$(_sched_get_current)"
    if [ -z "$_cur" ]; then
        print_status INFO "$(T TXT_SCHED_NONE)"
    else
        # min hour * * dow seklinde parse et
        local _min _hour _dow
        _min="$(printf '%s\n' "$_cur" | awk '{print $1}')"
        _hour="$(printf '%s\n' "$_cur" | awk '{print $2}')"
        _dow="$(printf '%s\n' "$_cur" | awk '{print $5}')"
        local _hh _mm _time
        _hh="$(printf '%02d' "$_hour" 2>/dev/null)"
        _mm="$(printf '%02d' "$_min"  2>/dev/null)"
        _time="${CLR_ORANGE}${CLR_BOLD}${_hh}:${_mm}${CLR_RESET}"
        if [ "$_dow" = "*" ]; then
            print_status INFO "$(tpl_render "$(T TXT_SCHED_DAILY_SET)" HOUR "$_time" MIN "")"
        else
            # Gun adini bul
            local _dow_name
            if [ "$LANG" = "en" ]; then
                case "$_dow" in
                    0|7) _dow_name="Sunday" ;;
                    1)   _dow_name="Monday" ;;
                    2)   _dow_name="Tuesday" ;;
                    3)   _dow_name="Wednesday" ;;
                    4)   _dow_name="Thursday" ;;
                    5)   _dow_name="Friday" ;;
                    6)   _dow_name="Saturday" ;;
                    *)   _dow_name="$_dow" ;;
                esac
            else
                case "$_dow" in
                    0|7) _dow_name="Pazar" ;;
                    1)   _dow_name="Pazartesi" ;;
                    2)   _dow_name="Sali" ;;
                    3)   _dow_name="Carsamba" ;;
                    4)   _dow_name="Persembe" ;;
                    5)   _dow_name="Cuma" ;;
                    6)   _dow_name="Cumartesi" ;;
                    *)   _dow_name="$_dow" ;;
                esac
            fi
            local _dow_fmt="${_dow} ${CLR_ORANGE}${CLR_BOLD}${_dow_name}${CLR_RESET}"
            print_status INFO "$(tpl_render "$(T TXT_SCHED_WEEKLY_SET)" HOUR "$_time" MIN "" DOW "$_dow_fmt")"
        fi
    fi
}
scheduled_reboot_menu() {
    while true; do
        clear
        print_line "="
        printf "  %b%s%b\n" "${CLR_BOLD}${CLR_CYAN}" "$(T TXT_SCHED_TITLE)" "${CLR_RESET}"
        print_line "="
        echo
        # crond uyarisi
        if ! _sched_crond_running; then
            print_status WARN "$(T TXT_SCHED_CROND_WARN)"
            echo
        fi
        # Mevcut zamanlama
        printf "  %b%s:%b\n" "${CLR_BOLD}" "$(T TXT_SCHED_STATUS)" "${CLR_RESET}"
        _sched_show_current
        echo
        # Saat uyarisi
        print_status WARN "$(T TXT_SCHED_TIME_WARN)"
        echo
        print_line "-"
        printf "  %s\n" "$(T TXT_SCHED_MENU_1)"
        printf "  %s\n" "$(T TXT_SCHED_MENU_2)"
        printf "  %s\n" "$(T TXT_SCHED_MENU_3)"
        printf "  %s\n" "$(T TXT_SCHED_MENU_4)"
        printf "  %s\n" "$(T TXT_SCHED_MENU_0)"
        print_line "-"
        echo
        printf "%s" "$(T TXT_SCHED_PROMPT)"
        read -r _schoice
        case "$_schoice" in
            1)
                clear
                print_line "="
                printf "  %b%s%b\n" "${CLR_BOLD}${CLR_CYAN}" "$(T TXT_SCHED_TITLE)" "${CLR_RESET}"
                print_line "="
                echo
                _sched_show_current
                echo
                press_enter_to_continue
                ;;
            2)
                # Gunluk reboot — saat + dakika sor
                clear
                print_line "-"
                printf "  %b%s%b\n" "${CLR_BOLD}" "$(T TXT_SCHED_MENU_2)" "${CLR_RESET}"
                print_line "-"
                echo
                local _hour _min
                printf "%s" "$(T TXT_SCHED_HOUR)"
                read -r _hour
                if ! printf '%s\n' "$_hour" | grep -Eq '^[0-9]+$' || [ "$_hour" -lt 0 ] 2>/dev/null || [ "$_hour" -gt 23 ] 2>/dev/null; then
                    print_status FAIL "$(T TXT_SCHED_INVALID_HOUR)"
                    press_enter_to_continue
                    continue
                fi
                printf "%s" "$(T TXT_SCHED_MIN)"
                read -r _min
                if ! printf '%s\n' "$_min" | grep -Eq '^[0-9]+$' || [ "$_min" -lt 0 ] 2>/dev/null || [ "$_min" -gt 59 ] 2>/dev/null; then
                    print_status FAIL "$(T TXT_SCHED_INVALID_MIN)"
                    press_enter_to_continue
                    continue
                fi
                _sched_write "$_min" "$_hour" "*"
                print_status PASS "$(T TXT_SCHED_ADDED)"
                press_enter_to_continue
                ;;
            3)
                # Haftalik reboot — saat + dakika + gun sor
                clear
                print_line "-"
                printf "  %b%s%b\n" "${CLR_BOLD}" "$(T TXT_SCHED_MENU_3)" "${CLR_RESET}"
                print_line "-"
                echo
                local _hour _min _dow
                printf "%s" "$(T TXT_SCHED_HOUR)"
                read -r _hour
                if ! printf '%s\n' "$_hour" | grep -Eq '^[0-9]+$' || [ "$_hour" -lt 0 ] 2>/dev/null || [ "$_hour" -gt 23 ] 2>/dev/null; then
                    print_status FAIL "$(T TXT_SCHED_INVALID_HOUR)"
                    press_enter_to_continue
                    continue
                fi
                printf "%s" "$(T TXT_SCHED_MIN)"
                read -r _min
                if ! printf '%s\n' "$_min" | grep -Eq '^[0-9]+$' || [ "$_min" -lt 0 ] 2>/dev/null || [ "$_min" -gt 59 ] 2>/dev/null; then
                    print_status FAIL "$(T TXT_SCHED_INVALID_MIN)"
                    press_enter_to_continue
                    continue
                fi
                printf "%s" "$(T TXT_SCHED_DOW)"
                read -r _dow
                if ! printf '%s\n' "$_dow" | grep -Eq '^[0-6]$'; then
                    print_status FAIL "$(T TXT_SCHED_INVALID_DOW)"
                    press_enter_to_continue
                    continue
                fi
                _sched_write "$_min" "$_hour" "$_dow"
                print_status PASS "$(T TXT_SCHED_ADDED)"
                press_enter_to_continue
                ;;
            4)
                # Silme
                if [ -z "$(_sched_get_current)" ]; then
                    print_status WARN "$(T TXT_SCHED_DEL_NONE)"
                    press_enter_to_continue
                    continue
                fi
                printf "%s" "$(T TXT_SCHED_CONFIRM_DEL)"
                read -r _ans
                case "$_ans" in
                    e|E|y|Y)
                        _sched_remove
                        print_status PASS "$(T TXT_SCHED_DELETED)"
                        ;;
                    *)
                        echo "$(T _ 'Iptal edildi.' 'Cancelled.')"
                        ;;
                esac
                press_enter_to_continue
                ;;
            0|"")
                return 0
                ;;
            *)
                echo "$(T _ 'Gecersiz secim.' 'Invalid choice.')"
                press_enter_to_continue
                ;;
        esac
    done
}
# =============================================================================
# ZAMANLANMIS OPKG GUNCELLEME (Scheduled OPKG Upgrade via Cron)
# =============================================================================
KZM_OPKG_UPGRADE_TAG="# KZM_OPKG_UPGRADE"
# Mevcut KZM_OPKG_UPGRADE crontab satirini oku
_opkg_sched_get_current() {
    crontab -l 2>/dev/null | awk '/KZM_OPKG_UPGRADE/'
}
# Crontab'dan KZM_OPKG_UPGRADE satirini kaldir
_opkg_sched_remove() {
    local _tmp="/tmp/kzm_opkg_cron_remove.$$"
    crontab -l 2>/dev/null | grep -v '^#' | grep -v "$KZM_OPKG_UPGRADE_TAG" | grep -v '^[[:space:]]*$' > "$_tmp"
    crontab "$_tmp"
    rm -f "$_tmp"
}
# Mevcut OPKG zamanlamasini okunabilir formatta goster
_opkg_sched_show_current() {
    local _cur
    _cur="$(_opkg_sched_get_current)"
    if [ -z "$_cur" ]; then
        print_status INFO "$(T TXT_OPKG_SCHED_NONE)"
        return
    fi
    local _min _hour _dom _time _hh _mm
    _min="$(printf '%s\n' "$_cur" | awk '{print $1}')"
    _hour="$(printf '%s\n' "$_cur" | awk '{print $2}')"
    _dom="$(printf '%s\n' "$_cur" | awk '{print $3}')"
    _hh="$(printf '%02d' "$_hour" 2>/dev/null)"
    _mm="$(printf '%02d' "$_min"  2>/dev/null)"
    _time="${CLR_ORANGE}${CLR_BOLD}${_hh}:${_mm}${CLR_RESET}"
    case "$_dom" in
        "1,15") print_status INFO "$(tpl_render "$(T TXT_OPKG_SCHED_BIWEEKLY_SET)" HOUR "$_time")" ;;
        "1")    print_status INFO "$(tpl_render "$(T TXT_OPKG_SCHED_MONTHLY_SET)" HOUR "$_time")" ;;
        *)      print_status INFO "$(tpl_render "$(T TXT_OPKG_SCHED_WEEKLY_SET)" HOUR "$_time")" ;;
    esac
}
opkg_scheduled_upgrade_menu() {
    while true; do
        clear
        print_line "="
        printf "  %b%s%b\n" "${CLR_BOLD}${CLR_CYAN}" "$(T TXT_OPKG_SCHED_TITLE)" "${CLR_RESET}"
        print_line "="
        echo
        if ! _sched_crond_running; then
            print_status WARN "$(T TXT_SCHED_CROND_WARN)"
            echo
        fi
        printf "  %b%s:%b\n" "${CLR_BOLD}" "$(T TXT_OPKG_SCHED_STATUS)" "${CLR_RESET}"
        _opkg_sched_show_current
        echo
        print_status WARN "$(T TXT_OPKG_SCHED_TIME_WARN)"
        echo
        print_line "-"
        printf "  %s\n" "$(T TXT_OPKG_SCHED_MENU_1)"
        printf "  %s\n" "$(T TXT_OPKG_SCHED_MENU_2)"
        printf "  %s\n" "$(T TXT_OPKG_SCHED_MENU_3)"
        printf "  %s\n" "$(T TXT_OPKG_SCHED_MENU_4)"
        printf "  %s\n" "$(T TXT_OPKG_SCHED_MENU_0)"
        print_line "-"
        printf "%s" "$(T TXT_OPKG_SCHED_PROMPT)"
        read -r _sel </dev/tty
        case "$_sel" in
            1)
                # Haftalik - Pazar 03:00
                local _tmp="/tmp/kzm_opkg_cron_set.$$"
                crontab -l 2>/dev/null | grep -v '^#' | grep -v "$KZM_OPKG_UPGRADE_TAG" | grep -v '^[[:space:]]*$' > "$_tmp"
                printf '0 3 * * 0 sh /opt/lib/opkg/keenetic_zapret2_manager.sh --opkg-upgrade %s\n' \
                    "$KZM_OPKG_UPGRADE_TAG" >> "$_tmp"
                crontab "$_tmp"; rm -f "$_tmp"
                print_status PASS "$(T TXT_OPKG_SCHED_ADDED)"
                press_enter_to_continue
                ;;
            2)
                # 2 haftada bir - 1. ve 15. gun 03:00
                local _tmp="/tmp/kzm_opkg_cron_set.$$"
                crontab -l 2>/dev/null | grep -v '^#' | grep -v "$KZM_OPKG_UPGRADE_TAG" | grep -v '^[[:space:]]*$' > "$_tmp"
                printf '0 3 1,15 * * sh /opt/lib/opkg/keenetic_zapret2_manager.sh --opkg-upgrade %s\n' \
                    "$KZM_OPKG_UPGRADE_TAG" >> "$_tmp"
                crontab "$_tmp"; rm -f "$_tmp"
                print_status PASS "$(T TXT_OPKG_SCHED_ADDED)"
                press_enter_to_continue
                ;;
            3)
                # Aylik - ayin 1'i 03:00
                local _tmp="/tmp/kzm_opkg_cron_set.$$"
                crontab -l 2>/dev/null | grep -v '^#' | grep -v "$KZM_OPKG_UPGRADE_TAG" | grep -v '^[[:space:]]*$' > "$_tmp"
                printf '0 3 1 * * sh /opt/lib/opkg/keenetic_zapret2_manager.sh --opkg-upgrade %s\n' \
                    "$KZM_OPKG_UPGRADE_TAG" >> "$_tmp"
                crontab "$_tmp"; rm -f "$_tmp"
                print_status PASS "$(T TXT_OPKG_SCHED_ADDED)"
                press_enter_to_continue
                ;;
            4)
                if [ -z "$(_opkg_sched_get_current)" ]; then
                    print_status WARN "$(T TXT_OPKG_SCHED_DEL_NONE)"
                    press_enter_to_continue
                    continue
                fi
                _opkg_sched_remove
                print_status PASS "$(T TXT_OPKG_SCHED_DELETED)"
                press_enter_to_continue
                ;;
            0|"")
                return 0
                ;;
            *)
                echo "$(T _ 'Gecersiz secim.' 'Invalid choice.')"
                press_enter_to_continue
                ;;
        esac
    done
}
# =============================================================================
# ZAMANLANMIS GOREVLER wrapper menusu
# =============================================================================
scheduled_tasks_menu() {
    while true; do
        clear
        print_line "="
        printf "  %b%s%b\n" "${CLR_BOLD}${CLR_CYAN}" "$(T TXT_SCHED_TASKS_TITLE)" "${CLR_RESET}"
        print_line "="
        echo
        print_line "-"
        printf "  %s\n" "$(T TXT_SCHED_TASKS_MENU_1)"
        printf "  %s\n" "$(T TXT_SCHED_TASKS_MENU_2)"
        printf "  %s\n" "$(T TXT_SCHED_TASKS_MENU_0)"
        print_line "-"
        printf "%s" "$(T TXT_SCHED_TASKS_PROMPT)"
        read -r _sel </dev/tty
        case "$_sel" in
            1) scheduled_reboot_menu ;;
            2) opkg_scheduled_upgrade_menu ;;
            0|"") return 0 ;;
            *)
                echo "$(T _ 'Gecersiz secim.' 'Invalid choice.')"
                press_enter_to_continue
                ;;
        esac
    done
}
health_monitor_menu() {
    while true; do
        print_line "="
        echo
        healthmon_load_config
        local run_state="0"
        healthmon_is_running && run_state="1"
        local run_label
        [ "$run_state" = "1" ] && run_label="$(T TXT_HM_RUN_ON)" || run_label="$(T TXT_HM_RUN_OFF)"
        print_line "-"
        if [ "$run_state" = "1" ]; then
            printf "%b
" "${CLR_BOLD}${CLR_GREEN}$(T TXT_HM_STATUS) ${run_label} ($(T TXT_HM_ENABLE_LABEL)=${HM_ENABLE})${CLR_RESET}"
        else
            printf "%b
" "${CLR_BOLD}${CLR_RED}$(T TXT_HM_STATUS) ${run_label} ($(T TXT_HM_ENABLE_LABEL)=${HM_ENABLE})${CLR_RESET}"
        fi
        print_line "-"
        printf "%-22s| %s\n" \
            "CPU WARN %${HM_CPU_WARN}/${HM_CPU_WARN_DUR}s" \
            "CPU CRIT %${HM_CPU_CRIT}/${HM_CPU_CRIT_DUR}s"
        printf "%-22s| %-21s| %s\n" \
            "Disk(/opt) >= ${HM_DISK_WARN}%" \
            "RAM <= ${HM_RAM_WARN_MB} MB" \
            "$(T _ 'Yuk' 'Load'): $(uptime 2>/dev/null | awk -F'load average: ' '{print $2}' | tr -d '\r')"
        printf "%-22s| %s\n" \
            "$(T _ "Zapret2 denetimi: ${HM_ZAPRET_WATCHDOG}" "Zapret2 watchdog: ${HM_ZAPRET_WATCHDOG}")" \
            "$(T _ "Aralik: ${HM_INTERVAL}s" "Interval: ${HM_INTERVAL}s")"
        # Telegram Bot durumu
        if [ "$(grep -s '^TG_BOT_ENABLE=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')" = "1" ]; then
            if [ -f "/tmp/kzm2_telegram_bot.pid" ] && kill -0 "$(cat "/tmp/kzm2_telegram_bot.pid" 2>/dev/null)" 2>/dev/null; then
                printf "%-22s| %b%s%b\n" "Telegram Bot" \
                    "${CLR_GREEN}" "$(T TXT_TGBOT_BANNER_ACTIVE) (PID: $(cat /tmp/kzm2_telegram_bot.pid 2>/dev/null))" "${CLR_RESET}"
            else
                printf "%-22s| %b%s%b\n" "Telegram Bot" \
                    "${CLR_RED}" "$(T TXT_TGBOT_BANNER_INACTIVE)" "${CLR_RESET}"
            fi
        else
            printf "%-22s| %b%s%b\n" "Telegram Bot" \
                "${CLR_DIM}" "$(T TXT_TG_NOT_CONFIGURED)" "${CLR_RESET}"
        fi
        echo
        print_line "-"
        echo " 1) $(T TXT_HM_ENABLE_DISABLE)"
        echo " 2) $(T TXT_HM_SHOW_STATUS)"
        echo " 3) $(T TXT_HM_SEND_TEST)"
        echo " 4) $(T TXT_HM_CONFIG_THRESHOLDS)"
        echo " 5) $(T TXT_HM_RESTART)"
        echo " 0) $(T TXT_BACK)"
        print_line "-"
        printf "%s" "$(T TXT_CHOICE) "
        read -r c || return 0
        clear
        case "$c" in
1)
    # Toggle based on *actual* daemon state (not only HM_ENABLE flag)
    # This prevents "OFF ($(T TXT_HM_ENABLE_LABEL)=1)" showing, then option 1 trying to stop a non-running daemon.
    if healthmon_is_running; then
        healthmon_stop
        print_status PASS "$(T TXT_HM_DISABLED)"
    else
        if healthmon_start; then
            print_status PASS "$(T TXT_HM_ENABLED)"
        else
            print_status FAIL "$(T TXT_HM_ENABLED)"
        fi
    fi
    press_enter_to_continue
    ;;
            2)
                healthmon_status
                press_enter_to_continue
                ;;
            3)
                if healthmon_test; then
                    print_status PASS "$(T TXT_HM_TEST_SENT)"
                else
                    print_status WARN "$(T TXT_HM_NEED_TG)"
                fi
                press_enter_to_continue
                ;;
4)
    healthmon_config_menu
    press_enter_to_continue
    ;;
5)
    healthmon_stop
    if healthmon_start; then
        print_status PASS "$(T TXT_HM_RESTARTED)"
    else
        print_status FAIL "$(T TXT_HM_RESTARTED)"
    fi
    press_enter_to_continue
    ;;
            0) return 0 ;;
            *) echo "$(T TXT_INVALID_CHOICE)" ; sleep 1 ;;
        esac
    done
}
check_script_location_once
# ===========================================================================
# TR/EN Dictionary (Web Panel GUI)
# ===========================================================================
TXT_MENU_17_TR="17. Web Panel (GUI)"
TXT_MENU_17_EN="17. Web Panel (GUI)"
TXT_GUI_TITLE_TR="Web Panel (GUI)"
TXT_GUI_TITLE_EN="Web Panel (GUI)"
TXT_GUI_OPT_1_TR="1) Web Panel Kur"
TXT_GUI_OPT_1_EN="1) Install Web Panel"
TXT_GUI_OPT_2_TR="2) Web Panel Kaldir"
TXT_GUI_OPT_2_EN="2) Remove Web Panel"
TXT_GUI_OPT_3_TR="3) Web Panel Guncelle"
TXT_GUI_OPT_3_EN="3) Update Web Panel"
TXT_GUI_OPT_4_TR="4) Web Panel Durumu"
TXT_GUI_OPT_4_EN="4) Web Panel Status"
TXT_GUI_OPT_6_TR="6) Web Panel Ac/Kapat"
TXT_GUI_OPT_6_EN="6) Enable/Disable Web Panel"
TXT_GUI_OPT_0_TR="0) Geri"
TXT_GUI_OPT_0_EN="0) Back"
TXT_GUI_PORT_PROMPT_TR="Yeni port (1024-65535, bos=iptal): "
TXT_GUI_PORT_PROMPT_EN="New port (1024-65535, empty=cancel): "
TXT_GUI_PORT_INVALID_TR="Gecersiz port numarasi."
TXT_GUI_PORT_INVALID_EN="Invalid port number."
TXT_GUI_PORT_CHANGED_TR="Port degistirildi. Web panel yeniden baslatildi."
TXT_GUI_PORT_CHANGED_EN="Port changed. Web panel restarted."
TXT_GUI_INSTALLED_TR="Web Panel kuruldu."
TXT_GUI_INSTALLED_EN="Web Panel installed."
TXT_GUI_REMOVED_TR="Web Panel kaldirildi."
TXT_GUI_REMOVED_EN="Web Panel removed."
TXT_GUI_UPDATED_TR="Web Panel guncellendi."
TXT_GUI_UPDATED_EN="Web Panel updated."
TXT_GUI_NOT_INSTALLED_TR="Web Panel kurulu degil."
TXT_GUI_NOT_INSTALLED_EN="Web Panel is not installed."
TXT_GUI_STATUS_ON_TR="Web Panel : AKTIF"
TXT_GUI_STATUS_ON_EN="Web Panel : ACTIVE"
TXT_GUI_STATUS_OFF_TR="Web Panel : PASIF"
TXT_GUI_STATUS_OFF_EN="Web Panel : INACTIVE"
TXT_GUI_URL_LABEL_TR="Web Panel URL"
TXT_GUI_URL_LABEL_EN="Web Panel URL"
TXT_GUI_ENABLED_TR="Web Panel etkinlestirildi."
TXT_GUI_ENABLED_EN="Web Panel enabled."
TXT_GUI_DISABLED_TR="Web Panel durduruldu."
TXT_GUI_DISABLED_EN="Web Panel stopped."
TXT_GUI_ERR_OPT_TR="Hata: /opt dizini bulunamadi. Entware kurulu mu?"
TXT_GUI_ERR_OPT_EN="Error: /opt not found. Is Entware installed?"
TXT_GUI_ERR_LIGHTTPD_TR="Hata: lighttpd kurulamadi."
TXT_GUI_ERR_LIGHTTPD_EN="Error: lighttpd install failed."
TXT_GUI_ERR_CGI_TR="Hata: lighttpd-mod-cgi kurulamadi."
TXT_GUI_ERR_CGI_EN="Error: lighttpd-mod-cgi install failed."
TXT_GUI_HTML_OK_TR="HTML        : OK"
TXT_GUI_HTML_OK_EN="HTML        : OK"
TXT_GUI_HTML_MISS_TR="HTML        : EKSIK"
TXT_GUI_HTML_MISS_EN="HTML        : MISSING"
TXT_GUI_JSON_OK_TR="JSON        : OK"
TXT_GUI_JSON_OK_EN="JSON        : OK"
TXT_GUI_JSON_MISS_TR="JSON        : EKSIK"
TXT_GUI_JSON_MISS_EN="JSON        : MISSING"
TXT_GUI_CGI_OK_TR="CGI         : OK"
TXT_GUI_CGI_OK_EN="CGI         : OK"
TXT_GUI_CGI_MISS_TR="CGI         : EKSIK"
TXT_GUI_CGI_MISS_EN="CGI         : MISSING"
TXT_GUI_REMOVING_TR="Web Panel kaldiriliyor..."
TXT_GUI_REMOVING_EN="Removing Web Panel..."
TXT_GUI_CONFIRM_REMOVE_TR="Web Panel kaldirilsin mi? (e/h): "
TXT_GUI_CONFIRM_REMOVE_EN="Remove Web Panel? (y/n): "
TXT_GUI_LIGHTTPD_OK_TR="lighttpd    : OK"
TXT_GUI_LIGHTTPD_OK_EN="lighttpd    : OK"
TXT_GUI_LIGHTTPD_OFF_TR="lighttpd    : PASIF"
TXT_GUI_LIGHTTPD_OFF_EN="lighttpd    : INACTIVE"
TXT_GUI_OPKG_UPD_TR="opkg guncelleniyor..."
TXT_GUI_OPKG_UPD_EN="Running opkg update..."
TXT_GUI_CRON_OK_TR="Cron        : OK"
TXT_GUI_CRON_OK_EN="Cron        : OK"
TXT_GUI_SECURITY_WARN_TR="Web Panel sadece guvenilir LAN icin tasarlanmistir. WAN, Misafir veya IoT aglarina acmayin."
TXT_GUI_SECURITY_WARN_EN="Web Panel is intended for trusted LAN only. Do not expose it to WAN, Guest or IoT networks."
# ===========================================================================
# KZM GUI — Fonksiyonlar
# ===========================================================================
KZM2_GUI_DIR="/opt/www/kzm2"
KZM2_GUI_CGI_DIR="/opt/www/kzm2/cgi-bin"
KZM2_GUI_HTML="$KZM2_GUI_DIR/index.html"
KZM2_GUI_CGI="$KZM2_GUI_CGI_DIR/action.sh"
KZM2_GUI_CONF="/opt/etc/lighttpd/lighttpd.conf"
KZM2_GUI_STATUS_JSON="/opt/var/run/kzm2_status.json"
KZM2_GUI_STATUS_SCRIPT="/opt/bin/kzm2_status_gen.sh"
KZM2_GUI_CONF_CUSTOM="/opt/etc/kzm2_gui.conf"
KZM2_GUI_PORT="8088"
[ -f "$KZM2_GUI_CONF_CUSTOM" ] && {
    _p="$(grep -s '^KZM2_GUI_PORT=' "$KZM2_GUI_CONF_CUSTOM" | cut -d= -f2 | tr -d '"' | tr -d "'")"
    [ -n "$_p" ] && KZM2_GUI_PORT="$_p"
    unset _p
}
# ---------------------------------------------------------------------------
# kzm_gui_is_installed: lighttpd ve HTML dosyasi var mi?
# ---------------------------------------------------------------------------
kzm_gui_is_installed() {
    [ -f "$KZM2_GUI_HTML" ] && command -v lighttpd >/dev/null 2>&1
}
# ---------------------------------------------------------------------------
# kzm_gui_is_running: lighttpd sureci calisiyor mu?
# ---------------------------------------------------------------------------
kzm_gui_is_running() {
    pgrep -x lighttpd >/dev/null 2>&1
}
# ---------------------------------------------------------------------------
# kzm_gui_get_lan_ip: LAN IP adresini dinamik al
# ---------------------------------------------------------------------------
kzm_gui_get_lan_ip() {
    local _ip
    # Once br0 veya eth0 gibi LAN arayuzunden al
    _ip="$(ip -4 addr show br0 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)"
    [ -z "$_ip" ] && _ip="$(ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)"
    # Fallback: 192.168 ile baslayan ilk IP
    [ -z "$_ip" ] && _ip="$(ip -4 addr 2>/dev/null | awk '/inet 192\.168\./{print $2; exit}' | cut -d/ -f1)"
    [ -z "$_ip" ] && _ip="192.168.1.1"
    printf '%s' "$_ip"
}
# ---------------------------------------------------------------------------
# kzm_gui_gen_status: /opt/var/run/kzm2_status.json uret (hafif, ndmc yok)
# ---------------------------------------------------------------------------
kzm_gui_gen_status() {
    local _dir="/opt/var/run"
    mkdir -p "$_dir" 2>/dev/null
    # JSON /tmp'ye yazilir, symlink /opt/var/run altinda kalir (USB write azaltmak icin)
    ln -sf /tmp/kzm_status.json "$_dir/kzm_status.json" 2>/dev/null
    # Zapret2 calisiyor mu?
    local _zap_run=0
    if [ "$(cat /opt/zapret2/dpi_profile 2>/dev/null | tr -d '[:space:]')" = "none" ]; then
        [ -f /opt/zapret2/dpi_profile ] && _zap_run=1
    else
        pgrep -x nfqws2 >/dev/null 2>&1 && _zap_run=1
    fi
    # HealthMon calisiyor mu?
    local _hm_run=0
    local _hm_pid_file="/tmp/kzm2_healthmon.pid"
    if [ -f "$_hm_pid_file" ]; then
        local _hm_pid
        _hm_pid="$(cat "$_hm_pid_file" 2>/dev/null)"
        [ -n "$_hm_pid" ] && kill -0 "$_hm_pid" 2>/dev/null && _hm_run=1
    fi
    # HealthMon etkin mi? (config)
    local _hm_enabled=0
    [ "$(grep -s '^HM_ENABLE=' /opt/etc/healthmon.conf | cut -d= -f2 | tr -d '"')" = "1" ] && _hm_enabled=1
    # Telegram bot etkin/calisiyor mu?
    local _tg_enabled=0 _tg_run=0 _tg_configured=0
    [ "$(grep -s '^TG_BOT_ENABLE=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')" = "1" ] && _tg_enabled=1
    # Yapilandirilmis mi? Token + ChatID var mi?
    local _tg_tok _tg_chat
    _tg_tok="$(grep -s '^TG_BOT_TOKEN=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')"
    _tg_chat="$(grep -s '^TG_CHAT_ID=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')"
    [ -n "$_tg_tok" ] && [ -n "$_tg_chat" ] && _tg_configured=1
    if [ -f "/tmp/kzm2_telegram_bot.pid" ]; then
        local _tg_pid
        _tg_pid="$(cat "/tmp/kzm2_telegram_bot.pid" 2>/dev/null)"
        [ -n "$_tg_pid" ] && kill -0 "$_tg_pid" 2>/dev/null && _tg_run=1
    fi
    # CPU load
    local _load1 _load5 _load15
    _load1="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
    _load5="$(awk '{print $2}' /proc/loadavg 2>/dev/null)"
    _load15="$(awk '{print $3}' /proc/loadavg 2>/dev/null)"
    [ -z "$_load1" ] && _load1="0.00"
    # RAM (KB)
    local _ram_total=0 _ram_free=0 _ram_used_mb=0 _ram_total_mb=0
    _ram_total="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)"
    _ram_free="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null)"
    [ -z "$_ram_free" ] && _ram_free="$(awk '/^MemFree:/{print $2}' /proc/meminfo 2>/dev/null)"
    [ -z "$_ram_total" ] && _ram_total=0
    [ -z "$_ram_free"  ] && _ram_free=0
    _ram_total_mb=$(( _ram_total / 1024 ))
    _ram_used_mb=$(( (_ram_total - _ram_free) / 1024 ))
    # Disk /opt
    local _disk_used_pct=0 _disk_total_mb=0 _disk_used_mb=0
    if [ -d /opt ]; then
        local _df_line
        _df_line="$(df -P /opt 2>/dev/null | awk 'NR==2{print $2,$3,$5}')"
        _disk_total_mb="$(printf '%s' "$_df_line" | awk '{printf "%.0f", $1/1024}')"
        _disk_used_pct="$(healthmon_disk_used_pct /opt)"
        _disk_used_mb="$(printf '%s' "$_df_line" | awk '{printf "%.0f", $2/1024}')"
        # Guvenlik filtresi: bozuk df degeri kontrolu
        [ "${_disk_total_mb:-0}" -gt 0 ] 2>/dev/null && \
            [ "${_disk_used_mb:-0}" -gt "${_disk_total_mb:-0}" ] 2>/dev/null && \
            _disk_used_mb="$_disk_total_mb"
        [ "${_disk_used_pct:-0}" -gt 100 ] 2>/dev/null && _disk_used_pct=100
        [ "${_disk_used_pct:-0}" -lt 0 ] 2>/dev/null && _disk_used_pct=0
    fi
    # <1 string degerini JSON icin 0 olarak yaz ama web UI disk_used_mb ile gercek degerle gosterir
    [ "$_disk_used_pct" = "<1" ] && _disk_used_pct=0
    [ -z "$_disk_used_pct" ] && _disk_used_pct=0
    [ -z "$_disk_total_mb" ] && _disk_total_mb=0
    [ -z "$_disk_used_mb" ] && _disk_used_mb=0
    # Zapret2 version
    local _zap_ver="Unknown"
    if [ -f /opt/zapret2/ip2net/ip2net ]; then
        _zap_ver="$(strings /opt/zapret2/ip2net/ip2net 2>/dev/null | grep -E '^v[0-9]+\.' | head -n1)"
    fi
    [ -z "$_zap_ver" ] && _zap_ver="$(cat /opt/zapret2/VERSION 2>/dev/null | head -n1 | tr -d '\n')"
    [ -z "$_zap_ver" ] && _zap_ver="Unknown"
    # WAN bilgisi
    local _wan_dev _wan_ip _wan_raw
    _wan_raw="$(cat /opt/zapret2/wan_if 2>/dev/null | tr -d '\n')"
    if [ -f /opt/zapret2/wan_if ] && [ -z "$_wan_raw" ]; then
        # Kullanici tum arayuzler secmis
        _wan_dev="All Interfaces"
        local _def_iface
        _def_iface="$(ip -4 route show default 2>/dev/null | awk '/^default/{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
        _wan_ip="$(ip -4 addr show "$_def_iface" 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)"
        [ -z "$_wan_ip" ] && _wan_ip="—"
    else
        _wan_dev="$_wan_raw"
        [ -z "$_wan_dev" ] && _wan_dev="$(ip -4 route show default 2>/dev/null | awk '/^default/{print $5; exit}')"
        [ -z "$_wan_dev" ] && _wan_dev="Unknown"
        _wan_ip="$(ip -4 addr show "$_wan_dev" 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)"
        [ -z "$_wan_ip" ] && _wan_ip="Unknown"
    fi
    # Model ve firmware: statik dosyadan oku (kurulumda yazildi)
    local _model _firmware
    _model="$(cat /opt/var/run/kzm2_hw_model 2>/dev/null | tr -d '\n')"
    _firmware="$(cat /opt/var/run/kzm2_hw_firmware 2>/dev/null | tr -d '\n')"
    [ -z "$_model"    ] && _model="Keenetic"
    [ -z "$_firmware" ] && _firmware="Unknown"
    # DPI profil bilgisi
    local _dpi_profile _dpi_origin
    _dpi_profile="$(cat /opt/zapret2/dpi_profile 2>/dev/null | tr -d '\n')"
    _dpi_origin="$(cat /opt/zapret2/dpi_profile_origin 2>/dev/null | tr -d '\n')"
    [ -z "$_dpi_profile" ] && _dpi_profile="Unknown"
    [ -z "$_dpi_origin"  ] && _dpi_origin="manual"
    # Blockcheck sonucu
    local _bc_score=0 _bc_dns_ok=1 _bc_tls12_ok=0 _bc_udp_weak=2 _bc_tests_ok=0 _bc_tests_total=0 _bc_ts=0
    if [ -f /opt/zapret2/blockcheck_result.json ]; then
        _bc_score="$(grep '"score"'    /opt/zapret2/blockcheck_result.json | grep -o '[0-9]*' | head -1)"
        _bc_dns_ok="$(grep '"dns_ok"'  /opt/zapret2/blockcheck_result.json | grep -o '[0-9]' | head -1)"
        _bc_tls12_ok="$(grep '"tls12_ok"' /opt/zapret2/blockcheck_result.json | grep -o '[0-9]' | head -1)"
        _bc_udp_weak="$(grep '"udp_weak"' /opt/zapret2/blockcheck_result.json | grep -o '[0-9]' | head -1)"
        _bc_ts="$(grep '"ts"'         /opt/zapret2/blockcheck_result.json | grep -o '[0-9]*' | head -1)"
        _bc_tests_ok="$(grep '"tests_ok"'    /opt/zapret2/blockcheck_result.json | grep -o '[0-9]*' | head -1)"
        _bc_tests_total="$(grep '"tests_total"' /opt/zapret2/blockcheck_result.json | grep -o '[0-9]*' | head -1)"
        [ -z "$_bc_score"       ] && _bc_score=0
        [ -z "$_bc_dns_ok"      ] && _bc_dns_ok=0
        [ -z "$_bc_tls12_ok"    ] && _bc_tls12_ok=0
        [ -z "$_bc_udp_weak"    ] && _bc_udp_weak=2
        [ -z "$_bc_tests_ok"    ] && _bc_tests_ok=0
        [ -z "$_bc_tests_total" ] && _bc_tests_total=0
        [ -z "$_bc_ts"          ] && _bc_ts=0

    fi
    # KeenDNS bilgisi
    local _kdns_raw _kdns_access _kdns_fqdn
    _kdns_raw="$(LD_LIBRARY_PATH= ndmc -c 'show ndns' 2>/dev/null)"
    _kdns_access="$(printf '%s\n' "$_kdns_raw" | awk '/^[[:space:]]*access:/ {print $2; exit}')"
    _kdns_fqdn=""
    if [ -n "$_kdns_access" ]; then
        local _kdns_name _kdns_domain
        _kdns_name="$(printf '%s\n' "$_kdns_raw"   | awk '/^[[:space:]]*name:/   {print $2; exit}')"
        _kdns_domain="$(printf '%s\n' "$_kdns_raw" | awk '/^[[:space:]]*domain:/ {print $2; exit}')"
        _kdns_fqdn="${_kdns_name}.${_kdns_domain}"
    fi
    [ -z "$_kdns_access" ] && _kdns_access="none"
    [ -z "$_kdns_fqdn"   ] && _kdns_fqdn=""
    # ISP DNS
    local _isp_dns_json
    _isp_dns_json="$(LD_LIBRARY_PATH= ndmc -c 'show ip name-server' 2>/dev/null | awk '/address:/{print $2}' | tr '\n' ' ' | sed 's/ $//;s/ / - /g')"
    # Timestamp
    local _ts
    _ts="$(date +%s 2>/dev/null)"
    [ -z "$_ts" ] && _ts=0
    # JSON yaz (jq yok, elle compose)
    cat > /tmp/kzm_status.json << EOF
{
  "ts": $_ts,
  "lang": "$(cat /opt/zapret2/lang 2>/dev/null | tr -d '[:space:]' | head -c2)",
  "theme": "$(cat /opt/zapret2/theme 2>/dev/null | tr -d '[:space:]' | head -c5)",
  "kzm_version": "$SCRIPT_VERSION",
  "model": "$_model",
  "firmware": "$_firmware",
  "wan_dev": "$_wan_dev",
  "wan_ip": "$_wan_ip",
  "lan_ip": "$(ip -4 addr show br0 2>/dev/null | awk '/inet /{print $2;exit}' | cut -d/ -f1)",
  "keendns_fqdn": "$_kdns_fqdn",
  "keendns_access": "$_kdns_access",
  "isp_dns": "$_isp_dns_json",
  "zapret_running": $_zap_run,
  "zapret_version": "$_zap_ver",
  "healthmon_running": $_hm_run,
  "healthmon_enabled": $_hm_enabled,
  "telegram_enabled": $_tg_enabled,
  "telegram_running": $_tg_run,
  "telegram_configured": $_tg_configured,
  "load1": "$_load1",
  "load5": "$_load5",
  "load15": "$_load15",
  "ram_used_mb": $_ram_used_mb,
  "ram_total_mb": $_ram_total_mb,
  "disk_used_pct": $_disk_used_pct,
  "disk_used_mb": $_disk_used_mb,
  "disk_total_mb": $_disk_total_mb,
  "dpi_profile": "$_dpi_profile",
  "dpi_origin": "$_dpi_origin",
  "filter_mode": "$(cat /opt/zapret2/hostlist_mode 2>/dev/null | tr -d '[:space:]')",
  "scope_mode": "$(cat /opt/zapret2/scope_mode 2>/dev/null | tr -d '[:space:]')",
  "ipset_mode": "$(cat /opt/zapret2/ipset_clients_mode 2>/dev/null | tr -d '[:space:]')",
  "ipset_count": $(grep -c '[0-9]' /opt/zapret2/ipset_clients.txt 2>/dev/null | tr -d ' ' || echo 0),
  "bc_score": $_bc_score,
  "bc_dns_ok": $_bc_dns_ok,
  "bc_tls12_ok": $_bc_tls12_ok,
  "bc_udp_weak": $_bc_udp_weak,
  "bc_ts": $_bc_ts
}
EOF
}
# ---------------------------------------------------------------------------
# kzm_gui_write_status_script: /opt/bin/kzm2_status_gen.sh olustur
# ---------------------------------------------------------------------------
kzm_gui_write_status_script() {
    mkdir -p /opt/bin 2>/dev/null
    cat > "$KZM2_GUI_STATUS_SCRIPT" << 'STATEOF'
#!/bin/sh
# kzm2_status_gen.sh — KZM2 Web Panel JSON durum uretici (standalone)
# Cron: */1 * * * * /opt/bin/kzm2_status_gen.sh >/dev/null 2>&1
# NOT: Bu dosya KZM2 script tarafindan otomatik uretilmistir.
export PATH=/opt/sbin:/opt/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
mkdir -p /opt/var/run 2>/dev/null
# JSON /tmp'ye yazilir, /opt/var/run altinda symlink kalir (USB write azaltmak icin)
ln -sf /tmp/kzm_status.json /opt/var/run/kzm2_status.json 2>/dev/null
_zap=0
if [ "$(cat /opt/zapret2/dpi_profile 2>/dev/null | tr -d '[:space:]')" = "none" ]; then
    [ -f /opt/zapret2/dpi_profile ] && _zap=1
else
    pgrep nfqws2 >/dev/null 2>&1 && _zap=1
fi
_hm=0
_hmpid="$(cat /tmp/kzm2_healthmon.pid 2>/dev/null)"
[ -n "$_hmpid" ] && kill -0 "$_hmpid" 2>/dev/null && _hm=1
_hm_en=0
[ "$(grep -s '^HM_ENABLE=' /opt/etc/healthmon.conf | cut -d= -f2 | tr -d '"')" = "1" ] && _hm_en=1
_tg_en=0
[ "$(grep -s '^TG_BOT_ENABLE=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')" = "1" ] && _tg_en=1
_tg=0
_tgpid="$(cat /tmp/kzm2_telegram_bot.pid 2>/dev/null)"
[ -n "$_tgpid" ] && kill -0 "$_tgpid" 2>/dev/null && _tg=1
_tg_configured=0
_tg_tok="$(grep -s '^TG_BOT_TOKEN=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')"
_tg_chat="$(grep -s '^TG_CHAT_ID=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')"
[ -n "$_tg_tok" ] && [ -n "$_tg_chat" ] && _tg_configured=1
_load1="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"; [ -z "$_load1" ] && _load1="0.00"
_load5="$(awk '{print $2}' /proc/loadavg 2>/dev/null)"; [ -z "$_load5" ] && _load5="0.00"
_load15="$(awk '{print $3}' /proc/loadavg 2>/dev/null)"; [ -z "$_load15" ] && _load15="0.00"
_rtotal="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)"; [ -z "$_rtotal" ] && _rtotal=0
_rfree="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null)"; [ -z "$_rfree" ] && _rfree=0
_rtmb=$(( _rtotal / 1024 ))
_rumb=$(( (_rtotal - _rfree) / 1024 ))
_dpct=0; _dtmb=0; _dumb=0
if [ -d /opt ]; then
    _dpct="$(df -P /opt 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
    [ "${_dpct:-0}" -eq 0 ] 2>/dev/null && \
        [ "$(df -P /opt 2>/dev/null | awk 'NR==2{print $3}')" -gt 0 ] 2>/dev/null && _dpct=1
    [ -z "$_dpct" ] && _dpct=0
    _dtmb="$(df -P /opt 2>/dev/null | awk 'NR==2{printf "%.0f",$2/1024}')"
    _dumb="$(df -P /opt 2>/dev/null | awk 'NR==2{printf "%.0f",$3/1024}')"
    [ -z "$_dtmb" ] && _dtmb=0
    [ -z "$_dumb" ] && _dumb=0
    # Guvenlik filtresi: bozuk df degeri kontrolu
    [ "$_dtmb" -gt 0 ] 2>/dev/null && [ "$_dumb" -gt "$_dtmb" ] 2>/dev/null && _dumb="$_dtmb"
    [ "$_dpct" -gt 100 ] 2>/dev/null && _dpct=100
    [ "$_dpct" -lt 0 ] 2>/dev/null && _dpct=0
fi
# RAM detay
_rbuf="$(awk '/^Buffers:/{print $2}' /proc/meminfo 2>/dev/null)"; [ -z "$_rbuf" ] && _rbuf=0
_rcached="$(awk '/^Cached:/{print $2}' /proc/meminfo 2>/dev/null | head -1)"; [ -z "$_rcached" ] && _rcached=0
_rfree_mb=$(( _rfree / 1024 ))
_rbuf_mb=$(( (_rbuf + _rcached) / 1024 ))
# Swap
_swap_total="$(awk '/^SwapTotal:/{print $2}' /proc/meminfo 2>/dev/null)"; [ -z "$_swap_total" ] && _swap_total=0
_swap_free="$(awk '/^SwapFree:/{print $2}' /proc/meminfo 2>/dev/null)"; [ -z "$_swap_free" ] && _swap_free=0
_swap_used_mb=$(( (_swap_total - _swap_free) / 1024 ))
_swap_total_mb=$(( _swap_total / 1024 ))
# Disk /tmp
_tmp_pct="$(df /tmp 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5);print $5}')"; [ -z "$_tmp_pct" ] && _tmp_pct=0
_tmp_used_mb="$(df /tmp 2>/dev/null | awk 'NR==2{printf "%.0f",$3/1024}')"; [ -z "$_tmp_used_mb" ] && _tmp_used_mb=0
_tmp_total_mb="$(df /tmp 2>/dev/null | awk 'NR==2{printf "%.0f",$2/1024}')"; [ -z "$_tmp_total_mb" ] && _tmp_total_mb=0
# CPU sicaklik
_cpu_temp=""
for _tf in /sys/class/thermal/thermal_zone*/temp; do
    [ -f "$_tf" ] || continue
    _tv="$(cat "$_tf" 2>/dev/null)"
    if [ -n "$_tv" ]; then
        _cpu_temp="$(awk -v t="$_tv" 'BEGIN{printf "%.0f", t/1000}')"
        break
    fi
done
[ -z "$_cpu_temp" ] && _cpu_temp=0
# LAN IP
_lan_ip="$(ip -4 addr show br0 2>/dev/null | awk '/inet /{print $2;exit}' | cut -d/ -f1)"
[ -z "$_lan_ip" ] && _lan_ip="$(ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2;exit}' | cut -d/ -f1)"
[ -z "$_lan_ip" ] && _lan_ip=""
# Depolama tipi ve disk sagligi
_st_type="unknown"; _st_label="Storage (/opt)"
_dh_status="ok"; _dh_msg=""
_st_line="$(awk '$2=="/opt"{print; exit}' /proc/mounts 2>/dev/null)"
_st_dev="$(printf '%s' "$_st_line" | awk '{print $1}')"
_st_fs="$(printf '%s' "$_st_line" | awk '{print $3}')"
_st_bdev="$(printf '%s' "$_st_dev" | sed 's|/dev/||; s/[0-9]*$//')"
_st_removable="$(cat "/sys/block/${_st_bdev}/removable" 2>/dev/null)"
_st_is_usb=0
[ -n "$_st_bdev" ] && dmesg 2>/dev/null | grep -q "usb-storage.*${_st_bdev}" && _st_is_usb=1
if [ -n "$_st_dev" ]; then
    if printf '%s' "$_st_dev" | grep -q "^/dev/sd"; then
        if [ "$_st_removable" = "1" ]; then
            _st_type="usb"; _st_label="USB (/opt)"
        else
            _st_type="emmc_sd"; _st_label="eMMC/NAND (/opt)"
        fi
    elif printf '%s' "$_st_dev" | grep -q "^/dev/mmcblk"; then
        _st_type="emmc"; _st_label="eMMC/SD (/opt)"
    elif printf '%s' "$_st_dev" | grep -q "^/dev/nvme"; then
        _st_type="nvme"; _st_label="NVMe SSD (/opt)"
    elif printf '%s' "$_st_fs" | grep -qE "^tmpfs$"; then
        _st_type="tmpfs"; _st_label="tmpfs (/opt)"
    elif printf '%s' "$_st_fs" | grep -qE "^(overlay|overlayfs|ubifs)$" || printf '%s' "$_st_dev" | grep -qE "^(overlay|ubi[0-9])"; then
        _st_type="flash"; _st_label="Internal Flash (/opt)"
    else
        _st_type="generic"; _st_label="Storage (/opt)"
    fi
    # Disk sagligi: read-only
    if mount 2>/dev/null | grep -q "on /opt .*ro,"; then
        _dh_status="fail"; _dh_msg="Read-only mount"
    # Kritik I/O hatasi
    elif [ -n "$_st_bdev" ] && dmesg 2>/dev/null | grep -q "critical medium error.*dev ${_st_bdev}"; then
        _dh_status="fail"; _dh_msg="Critical I/O error"
    # EXT4 journal hatasi
    elif [ -n "$_st_bdev" ] && dmesg 2>/dev/null | grep -q "EXT4-fs (${_st_bdev}[0-9]*): error loading journal"; then
        _dh_status="warn"; _dh_msg="Journal error - e2fsck recommended"
    # USB baglantisi koptu
    elif [ "$_st_is_usb" = "1" ] && dmesg 2>/dev/null | grep -q "USB disconnect"; then
        _dh_status="warn"; _dh_msg="USB disconnect detected"
    # USB protokol hatasi
    elif [ "$_st_is_usb" = "1" ] && dmesg 2>/dev/null | grep -q "USBDEVFS_CONTROL failed"; then
        _dh_status="warn"; _dh_msg="USB protocol error"
    else
        _dh_status="ok"; _dh_msg=""
    fi
else
    _st_mp="$(df -P /opt 2>/dev/null | awk 'NR==2{print $NF}')"
    if [ "$_st_mp" = "/" ]; then
        _st_type="flash"; _st_label="Internal Flash (/opt)"
    fi
fi
# lighttpd
_lighttpd=0; pgrep lighttpd >/dev/null 2>&1 && _lighttpd=1
# curl
_curl_ok=0; if command -v curl >/dev/null 2>&1 && curl --version >/dev/null 2>&1; then _curl_ok=1; fi
_wan="$(cat /opt/zapret2/wan_if 2>/dev/null | tr -d '\n')"
if [ -f /opt/zapret2/wan_if ] && [ -z "$_wan" ]; then
    _wan_display="All Interfaces"
    _def_iface="$(ip -4 route show default 2>/dev/null | awk '/^default/{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    _wip="$(ip -4 addr show "$_def_iface" 2>/dev/null | awk '/inet /{print $2;exit}' | cut -d/ -f1)"
    [ -z "$_wip" ] && _wip=""
else
    _wan_display="$_wan"
    _wip="$(ip -4 addr show "$_wan" 2>/dev/null | awk '/inet /{print $2;exit}' | cut -d/ -f1)"
    [ -z "$_wip" ] && _wip="Unknown"
fi
_zver="$(cat /opt/zapret2/version 2>/dev/null | head -n1 | tr -d '\n')"
[ -z "$_zver" ] && _zver="Unknown"
_kzmver="$(grep '^SCRIPT_VERSION=' /opt/lib/opkg/keenetic_zapret2_manager.sh 2>/dev/null | head -n1 | cut -d= -f2 | tr -d '"')"
[ -z "$_kzmver" ] && _kzmver="Unknown"
_model="$(cat /opt/var/run/kzm2_hw_model 2>/dev/null | tr -d '\n')"
if [ -z "$_model" ] || [ "$_model" = "Keenetic" ]; then
    _model="$(LD_LIBRARY_PATH= ndmc -c 'show version' 2>/dev/null | tr -d '\r' | tr -d '\033' | awk '/description:/{gsub(/^[[:space:]]+/,"",$0); sub(/description:[[:space:]]*/,"",$0); print; exit}')"
    [ -n "$_model" ] && printf '%s' "$_model" > /opt/var/run/kzm2_hw_model 2>/dev/null
fi
[ -z "$_model" ] && _model="Keenetic"
_fw_ver="$(grep -o '<title>[^<]*</title>' /etc/components.xml 2>/dev/null | head -1 | sed 's/<title>//;s/<\/title>//')"
_fw_sandbox="$(grep -o 'sandbox="[^"]*"' /etc/components.xml 2>/dev/null | head -1 | sed 's/sandbox="//;s/"//')"
case "$_fw_sandbox" in
    stable)  _fw_ch="Kararli" ;;
    lts)     _fw_ch="LTS" ;;
    archive) _fw_ch="Arsiv" ;;
    preview) _fw_ch="Onizleme" ;;
    alpha)   _fw_ch="Gelistirici" ;;
    *)       _fw_ch="$_fw_sandbox" ;;
esac
[ -n "$_fw_ver" ] && [ -n "$_fw_ch" ] && _fw="$_fw_ver ($_fw_ch)" || _fw="$_fw_ver"
[ -n "$_fw" ] && printf '%s' "$_fw" > /opt/var/run/kzm2_hw_firmware 2>/dev/null
[ -z "$_fw" ] && _fw="$(cat /opt/var/run/kzm2_hw_firmware 2>/dev/null | tr -d '\n')"
[ -z "$_fw" ] && _fw="Unknown"
_ts="$(date +%s 2>/dev/null)"; [ -z "$_ts" ] && _ts=0
_kdns_raw="$(LD_LIBRARY_PATH= ndmc -c 'show ndns' 2>/dev/null)"
_kdns_access="$(printf '%s\n' "$_kdns_raw" | awk '/^[[:space:]]*access:/ {print $2; exit}')"
_kdns_fqdn=""
if [ -n "$_kdns_access" ]; then
    _kdns_name="$(printf '%s\n' "$_kdns_raw"   | awk '/^[[:space:]]*name:/   {print $2; exit}')"
    _kdns_domain="$(printf '%s\n' "$_kdns_raw" | awk '/^[[:space:]]*domain:/ {print $2; exit}')"
    _kdns_fqdn="${_kdns_name}.${_kdns_domain}"
fi
[ -z "$_kdns_access" ] && _kdns_access="none"
_isp_dns_json="$(LD_LIBRARY_PATH= ndmc -c 'show ip name-server' 2>/dev/null | awk '/address:/{print $2}' | tr '\n' ' ' | sed 's/ $//;s/ / - /g')"
_iss_name=""
_iss_domain="$(cat /opt/var/run/kzm2_iss.cache 2>/dev/null | tr -d '[:space:]')"
case "$_iss_domain" in
    @ttnet)      _iss_name="Turk Telekom (TT Net)" ;;
    @superonline|@fiber) _iss_name="Superonline (SOL)" ;;
    @vodafone)   _iss_name="Vodafone" ;;
    @kablofiber) _iss_name="Kablonet Fiber (Turksat)" ;;
    @kablonet)   _iss_name="Kablonet (Turksat)" ;;
    @turksat)    _iss_name="Kablonet (Turksat)" ;;
    @turk.net)   _iss_name="TurkNet (Turk Net)" ;;
    @doping)     _iss_name="Millenicom (Doping)" ;;
    @dsmart)     _iss_name="D-Smart" ;;
    @netspeed|@netspeedas) _iss_name="Netspeed" ;;
    @isnet|@is.net) _iss_name="Isnet" ;;
    @griddsl)    _iss_name="Grid Telekom" ;;
    @doruknet|@doruk) _iss_name="Doruknet" ;;
    @orisdsl.net|@vaepro.net) _iss_name="Oris Telekom" ;;
    @gnet)       _iss_name="Gibirnet" ;;
    @comnet)     _iss_name="Comnet" ;;
    @fixnet)     _iss_name="Fixnet" ;;
    @tiklanet)   _iss_name="Tiklanet" ;;
    @poyrazwifi) _iss_name="Poyraz Wifi" ;;
    @pelikan)    _iss_name="Pelikannet" ;;
    @atlantis)   _iss_name="Atlantis" ;;
    @*) _iss_name="$(printf '%s' "$_iss_domain" | sed 's/^@//')" ;;
esac
_dpi_profile="$(cat /opt/zapret2/dpi_profile 2>/dev/null | tr -d '\n')"
_dpi_origin="$(cat /opt/zapret2/dpi_profile_origin 2>/dev/null | tr -d '\n')"
[ -z "$_dpi_profile" ] && _dpi_profile="Unknown"
[ -z "$_dpi_origin"  ] && _dpi_origin="manual"
_filter_mode="$(cat /opt/zapret2/hostlist_mode 2>/dev/null | tr -d '[:space:]')"
_scope_mode="$(cat /opt/zapret2/scope_mode 2>/dev/null | tr -d '[:space:]')"
_ipset_mode="$(cat /opt/zapret2/ipset_clients_mode 2>/dev/null | tr -d '[:space:]')"
_ipset_count="$(grep -c '[0-9]' /opt/zapret2/ipset_clients.txt 2>/dev/null | tr -d ' ')"
[ -z "$_filter_mode" ] && _filter_mode="none"
[ -z "$_scope_mode"  ] && _scope_mode="global"
[ -z "$_ipset_mode"  ] && _ipset_mode="all"
[ -z "$_ipset_count" ] && _ipset_count="0"
_sha_kzm="$(cat /opt/etc/kzm2_sha256_kzm.state 2>/dev/null | tr -d '[:space:]')"
[ -z "$_sha_kzm" ] && _sha_kzm="unknown"
_sha_zapret="$(cat /opt/etc/kzm2_sha256_zapret.state 2>/dev/null | tr -d '[:space:]')"
[ -z "$_sha_zapret" ] && _sha_zapret="unknown"
_bc_score=0; _bc_dns_ok=1; _bc_tls12_ok=0; _bc_udp_weak=2; _bc_tests_ok=0; _bc_tests_total=0; _bc_ts=0
if [ -f /opt/zapret2/blockcheck_result.json ]; then
    _bc_score="$(grep '"score"'    /opt/zapret2/blockcheck_result.json | grep -o '[0-9]*' | head -1)"
    _bc_dns_ok="$(grep '"dns_ok"'  /opt/zapret2/blockcheck_result.json | grep -o '[0-9]' | head -1)"
    _bc_tls12_ok="$(grep '"tls12_ok"' /opt/zapret2/blockcheck_result.json | grep -o '[0-9]' | head -1)"
    _bc_udp_weak="$(grep '"udp_weak"' /opt/zapret2/blockcheck_result.json | grep -o '[0-9]' | head -1)"
    _bc_ts="$(grep '"ts"'         /opt/zapret2/blockcheck_result.json | grep -o '[0-9]*' | head -1)"
    _bc_tests_ok="$(grep '"tests_ok"'    /opt/zapret2/blockcheck_result.json | grep -o '[0-9]*' | head -1)"
    _bc_tests_total="$(grep '"tests_total"' /opt/zapret2/blockcheck_result.json | grep -o '[0-9]*' | head -1)"
    [ -z "$_bc_score"    ] && _bc_score=0
    [ -z "$_bc_dns_ok"   ] && _bc_dns_ok=0
    [ -z "$_bc_tls12_ok" ] && _bc_tls12_ok=0
    [ -z "$_bc_udp_weak" ] && _bc_udp_weak=2
    [ -z "$_bc_ts"       ] && _bc_ts=0
    [ -z "$_bc_tests_ok"    ] && _bc_tests_ok=0
    [ -z "$_bc_tests_total" ] && _bc_tests_total=0

fi
printf '{\n  "ts": %s,\n  "lang": "%s",\n  "theme": "%s",\n  "kzm_version": "%s",\n  "model": "%s",\n  "firmware": "%s",\n  "wan_dev": "%s",\n  "wan_ip": "%s",\n  "lan_ip": "%s",\n  "keendns_fqdn": "%s",\n  "keendns_access": "%s",\n  "iss_name": "%s",\n  "isp_dns": "%s",\n  "zapret_running": %s,\n  "zapret_version": "%s",\n  "healthmon_running": %s,\n  "healthmon_enabled": %s,\n  "telegram_enabled": %s,\n  "telegram_running": %s,\n  "telegram_configured": %s,\n  "lighttpd_running": %s,\n  "curl_ok": %s,\n  "load1": "%s",\n  "load5": "%s",\n  "load15": "%s",\n  "ram_used_mb": %s,\n  "ram_free_mb": %s,\n  "ram_total_mb": %s,\n  "ram_buffer_mb": %s,\n  "swap_used_mb": %s,\n  "swap_total_mb": %s,\n  "disk_used_pct": %s,\n  "disk_used_mb": %s,\n  "disk_total_mb": %s,\n  "disk_tmp_pct": %s,\n  "disk_tmp_used_mb": %s,\n  "disk_tmp_total_mb": %s,\n  "storage_type": "%s",\n  "storage_label": "%s",\n  "disk_health_status": "%s",\n  "disk_health_msg": "%s",\n  "cpu_temp": %s,\n  "dpi_profile": "%s",\n  "dpi_origin": "%s",\n  "filter_mode": "%s",\n  "scope_mode": "%s",\n  "ipset_mode": "%s",\n  "ipset_count": %s,\n  "bc_score": %s,\n  "bc_dns_ok": %s,\n  "bc_tls12_ok": %s,\n  "bc_udp_weak": %s,\n  "bc_tests_ok": %s,\n  "bc_tests_total": %s,\n  "bc_ts": %s,\n  "sha_kzm": "%s",\n  "sha_zapret": "%s"\n}\n' \
    "$_ts" "$(cat /opt/zapret2/lang 2>/dev/null | tr -d '[:space:]' | head -c2)" "$(cat /opt/zapret2/theme 2>/dev/null | tr -d '[:space:]' | head -c5)" "$_kzmver" "$_model" "$_fw" "$_wan_display" "$_wip" "$_lan_ip" \
    "$_kdns_fqdn" "$_kdns_access" "$_iss_name" "$_isp_dns_json" \
    "$_zap" "$_zver" "$_hm" "$_hm_en" "$_tg_en" "$_tg" "$_tg_configured" \
    "$_lighttpd" "$_curl_ok" \
    "$_load1" "$_load5" "$_load15" \
    "$_rumb" "$_rfree_mb" "$_rtmb" "$_rbuf_mb" "$_swap_used_mb" "$_swap_total_mb" \
    "$_dpct" "$_dumb" "$_dtmb" \
    "$_tmp_pct" "$_tmp_used_mb" "$_tmp_total_mb" \
    "$_st_type" "$_st_label" "$_dh_status" "$_dh_msg" \
    "$_cpu_temp" \
    "$_dpi_profile" "$_dpi_origin" "$_filter_mode" "$_scope_mode" "$_ipset_mode" "$_ipset_count" \
    "$_bc_score" "$_bc_dns_ok" "$_bc_tls12_ok" "$_bc_udp_weak" "$_bc_tests_ok" "$_bc_tests_total" "$_bc_ts" \
    "$_sha_kzm" "$_sha_zapret" \
    > /tmp/kzm_status.json.tmp && mv -f /tmp/kzm_status.json.tmp /tmp/kzm_status.json
STATEOF
    chmod +x "$KZM2_GUI_STATUS_SCRIPT"
}
# ---------------------------------------------------------------------------
# kzm_gui_write_cgi: /opt/www/kzm2/cgi-bin/action.sh olustur
# ---------------------------------------------------------------------------
kzm_gui_write_cgi() {
    mkdir -p "$KZM2_GUI_CGI_DIR" 2>/dev/null
    cat > "$KZM2_GUI_CGI" << 'CGIEOF'
#!/bin/sh
# kzm-cgi-version: __KZM_VER__
export PATH=/opt/sbin:/opt/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
printf 'Content-Type: application/json\r\n\r\n'
CONTENT_LENGTH="${CONTENT_LENGTH:-0}"
if [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
    POST_BODY=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
else
    read -r POST_BODY
fi
ACTION=$(printf '%s' "$POST_BODY" | sed 's/.*action=\([^&]*\).*/\1/' | tr -d '"'\''[:space:]')
get_param() { printf '%s' "$POST_BODY" | sed "s/.*$1=\([^&]*\).*/\1/" | sed 's/%2F/\//g;s/%2C/,/g;s/%20/ /g;s/%2E/./g;s/%2D/-/g;s/%3A/:/g;s/%40/@/g;s/+/ /g' | tr -d '\n'; }
get_param_raw() { printf '%s' "$POST_BODY" | tr '&' '\n' | sed -n "s/^$1=//p" | head -n1 | tr -d '\n'; }
ok()      { printf '{"ok":1,"msg":"%s"}' "$1"; }
ok_data() { printf '{"ok":1,"data":%s}' "$1"; }
ok_str()  { printf '{"ok":1,"data":"%s"}' "$1"; }
fail()    { printf '{"ok":0,"msg":"%s"}' "$1"; }
HL_USER="/opt/zapret2/ipset/zapret-hosts-user.txt"
HL_EXCL="/opt/zapret2/ipset/zapret-hosts-user-exclude.txt"
HL_LOCALNETS="/opt/zapret2/ipset/zapret-hosts-localnets.txt"
HL_IP_EXCL="/opt/zapret2/ipset/zapret-ip-exclude.txt"
IPSET_FILE="/opt/zapret2/ipset_clients.txt"
DPI_FILE="/opt/zapret2/dpi_profile"
SCHED_TAG="# KZM_REBOOT"
json_arr() {
    [ -f "$1" ] || { printf '[]'; return; }
    awk 'BEGIN{printf "["} NF{if(NR>1)printf ","; printf "\"%s\"",$0} END{print "]"}' "$1" 2>/dev/null || printf '[]'
}
json_arr_domains_only() {
    # Web Panel exclude listesinde Zapret2 default IP/CIDR koruma satirlarini gizle.
    # Dosyada kalmalari gerekir; sadece domain yonetimi UI'sina karistirmiyoruz.
    [ -f "$1" ] || { printf '[]'; return; }
    awk '
        BEGIN{printf "["; n=0}
        NF && $0 !~ /^[[:space:]]*#/ {
            line=$0
            # IPv4/CIDR, IPv6/localnet ve saf IP satirlarini atla
            if (line ~ /^[0-9]+(\.[0-9]+){3}(\/[0-9]+)?$/) next
            if (line ~ /:/) next
            if (n++) printf ","
            gsub(/\\/,"\\\\",line); gsub(/"/,"\\\"",line)
            printf "\"%s\"", line
        }
        END{print "]"}
    ' "$1" 2>/dev/null || printf '[]'
}
kzm_rebuild_profile_restart() {
    _kzm="/opt/lib/opkg/keenetic_zapret2_manager.sh"
    _p="$(cat /opt/zapret2/dpi_profile 2>/dev/null | tr -d '\r\n')"
    [ -z "$_p" ] && _p="tt_default"
    case "$_p" in tt_default|tt_fiber|superonline_fiber|blockcheck_auto|custom) : ;; *) _p="tt_default"; echo "tt_default" > /opt/zapret2/dpi_profile 2>/dev/null ;; esac
    if [ -f "$_kzm" ]; then
        # NFQWS2_OPT yeniden yazilsin: hostlist/autohostlist modunda <HOSTLIST> marker'i korunur.
        KZM2_SKIP_LOCK=1 sh "$_kzm" --cgi-action dpi_set "$_p" >/dev/null 2>&1 &
    else
        { /opt/zapret2/init.d/sysv/zapret2 stop-fw >/dev/null 2>&1; /opt/zapret2/init.d/sysv/zapret2 stop >/dev/null 2>&1; killall nfqws2 >/dev/null 2>&1; sleep 1; /opt/zapret2/init.d/sysv/zapret2 start-fw >/dev/null 2>&1; /opt/zapret2/init.d/sysv/zapret2 start >/dev/null 2>&1; } &
    fi
}
kzm2_json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/ /g; s/$/\\n/' | tr -d '\n' | sed 's/\\n$//'
}
kzm2_url_decode_basic() {
    # KZM2 Web Panel textarea icin gerekli temel decode. encodeURIComponent cikisini cozer.
    # Satir sonlari NFQWS2_OPT icin bosluga cevrilir.
    printf '%s' "$1" | sed \
        -e 's/+/ /g' \
        -e 's/%0D/ /g' -e 's/%0d/ /g' \
        -e 's/%0A/ /g' -e 's/%0a/ /g' \
        -e 's/%09/ /g' -e 's/%20/ /g' \
        -e 's/%22/"/g' -e "s/%27/'/g" \
        -e 's/%3C/</g' -e 's/%3c/</g' \
        -e 's/%3E/>/g' -e 's/%3e/>/g' \
        -e 's/%3D/=/g' -e 's/%3d/=/g' \
        -e 's/%3A/:/g' -e 's/%3a/:/g' \
        -e 's/%2F/\//g' -e 's/%2f/\//g' \
        -e 's/%2C/,/g' -e 's/%2c/,/g' \
        -e 's/%2D/-/g' -e 's/%2d/-/g' \
        -e 's/%2B/+/g' -e 's/%2b/+/g' \
        -e 's/%28/(/g' -e 's/%29/)/g' \
        -e 's/%3B/;/g' -e 's/%3b/;/g' \
        -e 's/%26/\&/g'
}
kzm2_manual_dpi_default() {
    printf '%s' '--filter-tcp=80 <HOSTLIST> --filter-l7=http --payload=http_req --lua-desync=fake:blob=fake_default_http:ip_ttl=2:repeats=1 --new
--filter-tcp=443 <HOSTLIST> --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:ip_ttl=2:repeats=1 --new
--filter-udp=443 <HOSTLIST> --filter-l7=quic --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:ip_ttl=2:repeats=6'
}
kzm2_manual_dpi_config() {
    if [ -f /opt/zapret2/config ]; then
        sed -n 's/^NFQWS2_OPT="\(.*\)"[[:space:]]*$/\1/p' /opt/zapret2/config | head -n1 | sed 's/[[:space:]]*$//'
    fi
}
kzm2_manual_dpi_runtime() {
    _pid="$(pidof nfqws2 2>/dev/null | awk '{print $1}')"
    [ -n "$_pid" ] || return 1
    tr '\0' ' ' < "/proc/${_pid}/cmdline" 2>/dev/null | sed \
      -e 's#--hostlist=/opt/zapret2/ipset/zapret-hosts-user.txt##g' \
      -e 's#--hostlist-exclude=/opt/zapret2/ipset/zapret-hosts-user-exclude.txt##g' \
      -e 's#--hostlist-auto=/opt/zapret2/ipset/zapret-hosts-auto.txt##g' \
      -e 's#--hostlist-auto-fail-threshold=[^ ]*##g' \
      -e 's#--hostlist-auto-fail-time=[^ ]*##g' \
      -e 's#--hostlist-auto-retrans-threshold=[^ ]*##g' \
      -e 's#--hostlist-auto-retrans-reset=[^ ]*##g' \
      -e 's#--hostlist-auto-retrans-maxseq=[^ ]*##g' \
      -e 's#--hostlist-auto-incoming-maxseq=[^ ]*##g' \
      -e 's#--hostlist-auto-udp-in=[^ ]*##g' \
      -e 's#--hostlist-auto-udp-out=[^ ]*##g' \
      -e 's#^.*--filter-tcp=80#--filter-tcp=80#' \
      -e 's/[[:space:]][[:space:]]*/ /g' \
      -e 's/--filter-tcp=80 /--filter-tcp=80 <HOSTLIST> /' \
      -e 's/--filter-tcp=443 /--filter-tcp=443 <HOSTLIST> /' \
      -e 's/--filter-udp=443 /--filter-udp=443 <HOSTLIST> /' \
      -e 's/[[:space:]]*$//'
}
kzm2_manual_dpi_export_web() {
    local _cmd="" _clean="" _cfg="" _src="runtime" _host="" _prof="" _base=""
    local _out_dir="/opt/zapret2/dpi_profiles" _ts="" _out="" _latest=""
    _host="$(hostname 2>/dev/null)"; [ -n "$_host" ] || _host="unknown"
    _prof="$(cat /opt/zapret2/dpi_profile 2>/dev/null | tr -d '\r\n')"; [ -n "$_prof" ] || _prof="tt_default"
    case "$_prof" in
        tt_default) _base="Varsayilan Zapret2 (TTL2 fake)" ;;
        tt_fiber) _base="Turk Telekom Fiber (TTL2 fake)" ;;
        superonline_fiber) _base="Superonline Fiber (TTL6 hostcase)" ;;
        blockcheck_auto) _base="Blockcheck Otomatik (Auto)" ;;
        custom) _base="Ozel NFQWS2_OPT" ;;
        *) _base="$_prof" ;;
    esac
    if pidof nfqws2 >/dev/null 2>&1; then
        _cmd="$(tr '\0' ' ' < /proc/$(pidof nfqws2 | awk '{print $1}')/cmdline 2>/dev/null)"
        _clean="$(printf '%s\n' "$_cmd" | awk '
            BEGIN{block=""; first=1}
            {
                for(i=1;i<=NF;i++){
                    t=$i
                    if(t ~ /^--filter-(tcp|udp)=/){
                        if(block != ""){
                            if(first){printf "%s", block; first=0} else {printf " --new %s", block}
                        }
                        block=t " <HOSTLIST>"
                    } else if(t ~ /^--filter-l7=/ || t ~ /^--payload=/ || t ~ /^--lua-desync=/){
                        if(block != "") block=block " " t
                    }
                }
            }
            END{
                if(block != ""){
                    if(first){printf "%s", block} else {printf " --new %s", block}
                }
            }')"
    fi
    if [ -z "$_clean" ]; then
        _src="config"
        _cfg="$(grep '^NFQWS2_OPT=' /opt/zapret2/config 2>/dev/null | sed 's/^NFQWS2_OPT="//;s/"$//')"
        _clean="$_cfg"
    fi
    [ -n "$_clean" ] || { fail "D&#305;&#351;a aktar&#305;lacak DPI profili bulunamad&#305;"; return 1; }
    mkdir -p "$_out_dir" 2>/dev/null
    _ts="$(date +%Y%m%d_%H%M%S 2>/dev/null)"; [ -n "$_ts" ] || _ts="manual"
    _out="$_out_dir/active_dpi_profile_${_ts}.txt"
    _latest="$_out_dir/active_dpi_profile_latest.txt"
    {
        echo "===== KZM2 DPI PROFILI ====="
        echo "Cihaz        : $_host"
        if [ "$_src" = "runtime" ]; then
            echo "Kaynak       : Calisan Profil"
            echo "Mod          : Aktif Runtime"
        else
            echo "Kaynak       : Config"
            echo "Mod          : Kayitli Config"
        fi
        echo "Temel Profil : $_base"
        echo
        echo "NFQWS2_OPT:"
        echo
        kzm2_manual_dpi_pretty "$_clean"
        echo
        echo "===== SON ====="
    } > "$_out" 2>/dev/null
    cp -f "$_out" "$_latest" 2>/dev/null
    [ -f "$_latest" ] || { fail "DPI profili dosyaya yaz&#305;lamad&#305;"; return 1; }
    printf '{"ok":1,"msg":"%s","path":"%s"}' "DPI profili d&#305;&#351;a aktar&#305;ld&#305;" "$_latest"
}

kzm2_manual_dpi_pretty() {
    # Web Panel manuel DPI alaninda her parametre okunabilir olsun.
    # Config/runtime tek satir gelebilir; ekranda her --parametre ayri satira bolunur.
    # <HOSTLIST> degeri ilgili --filter satirinda kalir.
    printf '%s\n' "$1" | tr '\r\n\t' '   ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//' | awk '
    {
        out=""; cur="";
        for (i=1; i<=NF; i++) {
            tok=$i;
            if (tok ~ /^--/) {
                if (cur != "") { out = out cur "\n"; }
                cur = tok;
            } else {
                if (cur == "") cur = tok; else cur = cur " " tok;
            }
        }
        if (cur != "") out = out cur;
        print out;
    }' | sed '/^[[:space:]]*$/d'
}
kzm2_manual_dpi_msg() {
    _tr="$1"
    _en="$2"
    _lng="${LANG:-tr}"
    [ -f /opt/zapret2/lang ] && _lng="$(cat /opt/zapret2/lang 2>/dev/null | tr -d '[:space:]' | head -c2)"
    [ "$_lng" = "en" ] && printf '%s' "$_en" || printf '%s' "$_tr"
}

kzm2_manual_dpi_adv_default() {
    case "$1" in
        NFQWS2_PORTS_TCP) printf '%s' '80,443' ;;
        NFQWS2_PORTS_UDP) printf '%s' '443' ;;
        NFQWS2_TCP_PKT_OUT) printf '%s' '6' ;;
        NFQWS2_TCP_PKT_IN) printf '%s' '4' ;;
        NFQWS2_UDP_PKT_OUT) printf '%s' '3' ;;
        NFQWS2_UDP_PKT_IN) printf '%s' '3' ;;
        *) printf '%s' '' ;;
    esac
}
kzm2_manual_dpi_adv_get() {
    _key="$1"
    _def="$(kzm2_manual_dpi_adv_default "$_key")"
    _val=""
    if [ -f /opt/zapret2/config ]; then
        _val="$(grep "^${_key}=" /opt/zapret2/config 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '"[:space:]')"
    fi
    [ -n "$_val" ] || _val="$_def"
    printf '%s' "$_val"
}
kzm2_manual_dpi_adv_json() {
    _src="$1"
    if [ "$_src" = "default" ]; then
        _ptcp="$(kzm2_manual_dpi_adv_default NFQWS2_PORTS_TCP)"
        _pudp="$(kzm2_manual_dpi_adv_default NFQWS2_PORTS_UDP)"
        _tout="$(kzm2_manual_dpi_adv_default NFQWS2_TCP_PKT_OUT)"
        _tin="$(kzm2_manual_dpi_adv_default NFQWS2_TCP_PKT_IN)"
        _uout="$(kzm2_manual_dpi_adv_default NFQWS2_UDP_PKT_OUT)"
        _uin="$(kzm2_manual_dpi_adv_default NFQWS2_UDP_PKT_IN)"
    else
        _ptcp="$(kzm2_manual_dpi_adv_get NFQWS2_PORTS_TCP)"
        _pudp="$(kzm2_manual_dpi_adv_get NFQWS2_PORTS_UDP)"
        _tout="$(kzm2_manual_dpi_adv_get NFQWS2_TCP_PKT_OUT)"
        _tin="$(kzm2_manual_dpi_adv_get NFQWS2_TCP_PKT_IN)"
        _uout="$(kzm2_manual_dpi_adv_get NFQWS2_UDP_PKT_OUT)"
        _uin="$(kzm2_manual_dpi_adv_get NFQWS2_UDP_PKT_IN)"
    fi
    printf '{"ok":1,"ports_tcp":"%s","ports_udp":"%s","tcp_out":"%s","tcp_in":"%s","udp_out":"%s","udp_in":"%s"}' \
        "$(kzm2_json_escape "$_ptcp")" "$(kzm2_json_escape "$_pudp")" "$_tout" "$_tin" "$_uout" "$_uin"
}
kzm2_manual_dpi_adv_validate_ports() {
    _v="$(printf '%s' "$1" | tr -d '[:space:]')"
    [ -n "$_v" ] || return 1
    printf '%s' "$_v" | grep -qE '^[0-9]+(,[0-9]+)*$' || return 1
    printf '%s' "$_v" | tr ',' '\n' | awk '{ if ($1 < 1 || $1 > 65535) bad=1 } END{ exit bad }'
}
kzm2_manual_dpi_adv_validate_num() {
    _v="$1"
    printf '%s' "$_v" | grep -qE '^[0-9]+$' || return 1
    [ "$_v" -ge 1 ] 2>/dev/null || return 1
    [ "$_v" -le 999 ] 2>/dev/null || return 1
    return 0
}
kzm2_manual_dpi_adv_validate() {
    _ptcp="$(printf '%s' "$1" | tr -d '[:space:]')"
    _pudp="$(printf '%s' "$2" | tr -d '[:space:]')"
    _tout="$3"; _tin="$4"; _uout="$5"; _uin="$6"
    kzm2_manual_dpi_adv_validate_ports "$_ptcp" || { kzm2_manual_dpi_msg "TCP port listesi gecersiz" "Invalid TCP port list"; return 1; }
    kzm2_manual_dpi_adv_validate_ports "$_pudp" || { kzm2_manual_dpi_msg "UDP port listesi gecersiz" "Invalid UDP port list"; return 1; }
    kzm2_manual_dpi_adv_validate_num "$_tout" || { kzm2_manual_dpi_msg "TCP out paket degeri gecersiz" "Invalid TCP out packet value"; return 1; }
    kzm2_manual_dpi_adv_validate_num "$_tin" || { kzm2_manual_dpi_msg "TCP in paket degeri gecersiz" "Invalid TCP in packet value"; return 1; }
    kzm2_manual_dpi_adv_validate_num "$_uout" || { kzm2_manual_dpi_msg "UDP out paket degeri gecersiz" "Invalid UDP out packet value"; return 1; }
    kzm2_manual_dpi_adv_validate_num "$_uin" || { kzm2_manual_dpi_msg "UDP in paket degeri gecersiz" "Invalid UDP in packet value"; return 1; }
    return 0
}
kzm2_manual_dpi_adv_write() {
    _ptcp="$(printf '%s' "$1" | tr -d '[:space:]')"
    _pudp="$(printf '%s' "$2" | tr -d '[:space:]')"
    _tout="$3"; _tin="$4"; _uout="$5"; _uin="$6"
    KZM2_MANUAL_DPI_ADV_BAK=""
    mkdir -p /opt/zapret2 2>/dev/null || return 1
    [ -f /opt/zapret2/config ] || : > /opt/zapret2/config || return 1
    # 3'lu rotating adv backup: .1 en yeni, .3 en eski
    rm -f /opt/zapret2/config.bak_adv.3 2>/dev/null
    [ -f /opt/zapret2/config.bak_adv.2 ] && mv /opt/zapret2/config.bak_adv.2 /opt/zapret2/config.bak_adv.3 2>/dev/null
    [ -f /opt/zapret2/config.bak_adv.1 ] && mv /opt/zapret2/config.bak_adv.1 /opt/zapret2/config.bak_adv.2 2>/dev/null
    KZM2_MANUAL_DPI_ADV_BAK="/opt/zapret2/config.bak_adv.1"
    cp -a /opt/zapret2/config "$KZM2_MANUAL_DPI_ADV_BAK" 2>/dev/null || return 1
    _tmp="/tmp/kzm2_manual_dpi_adv.$$"
    awk -v ptcp="$_ptcp" -v pudp="$_pudp" -v tout="$_tout" -v tin="$_tin" -v uout="$_uout" -v uin="$_uin" '
        BEGIN{w1=0;w2=0;w3=0;w4=0;w5=0;w6=0}
        /^NFQWS2_PORTS_TCP=/{print "NFQWS2_PORTS_TCP=" ptcp; w1=1; next}
        /^NFQWS2_PORTS_UDP=/{print "NFQWS2_PORTS_UDP=" pudp; w2=1; next}
        /^NFQWS2_TCP_PKT_OUT=/{print "NFQWS2_TCP_PKT_OUT=" tout; w3=1; next}
        /^NFQWS2_TCP_PKT_IN=/{print "NFQWS2_TCP_PKT_IN=" tin; w4=1; next}
        /^NFQWS2_UDP_PKT_OUT=/{print "NFQWS2_UDP_PKT_OUT=" uout; w5=1; next}
        /^NFQWS2_UDP_PKT_IN=/{print "NFQWS2_UDP_PKT_IN=" uin; w6=1; next}
        {print}
        END{
            if(!w1) print "NFQWS2_PORTS_TCP=" ptcp
            if(!w2) print "NFQWS2_PORTS_UDP=" pudp
            if(!w3) print "NFQWS2_TCP_PKT_OUT=" tout
            if(!w4) print "NFQWS2_TCP_PKT_IN=" tin
            if(!w5) print "NFQWS2_UDP_PKT_OUT=" uout
            if(!w6) print "NFQWS2_UDP_PKT_IN=" uin
        }' /opt/zapret2/config > "$_tmp" || { rm -f "$_tmp" 2>/dev/null; return 1; }
    # Config syntax guard: asil config'e yazmadan once shell syntax bozulmasin.
    if ! sh -n "$_tmp" >/dev/null 2>&1; then
        rm -f "$_tmp" 2>/dev/null
        return 1
    fi
    mv "$_tmp" /opt/zapret2/config 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
}

kzm2_manual_dpi_validate() {
    _v="$1"
    [ -n "$_v" ] || { kzm2_manual_dpi_msg "Manuel profil bo&#351; olamaz" "Manual profile cannot be empty"; return 1; }
    printf '%s' "$_v" | grep -q '"' && { kzm2_manual_dpi_msg "&#199;ift t&#305;rnak kullanmay&#305;n" "Do not use double quotes"; return 1; }
    printf '%s' "$_v" | grep -q "'" && { kzm2_manual_dpi_msg "Tek t&#305;rnak kullanmay&#305;n" "Do not use single quotes"; return 1; }
    printf '%s' "$_v" | grep -Eq '(^|[[:space:]])--dpi-desync' && { kzm2_manual_dpi_msg "Eski KZM/Zapret1 --dpi-desync parametreleri kullan&#305;lamaz" "Legacy KZM/Zapret1 --dpi-desync parameters are not allowed"; return 1; }
    printf '%s' "$_v" | grep -Eq '(^|[[:space:]])--(lua-init|qnum|fwmark|user|hostlist=|hostlist-auto=|hostlist-exclude=)' && { kzm2_manual_dpi_msg "Sistem ba&#351;latma/hostlist parametreleri bu alanda kullan&#305;lamaz" "Startup/hostlist parameters are not allowed in this field"; return 1; }
    printf '%s' "$_v" | grep -q -- '--filter-' || { kzm2_manual_dpi_msg "En az bir --filter-tcp veya --filter-udp blo&#287;u olmal&#305;" "At least one --filter-tcp or --filter-udp block is required"; return 1; }
    printf '%s' "$_v" | grep -q -- '--payload=' || { kzm2_manual_dpi_msg "En az bir --payload parametresi olmal&#305;" "At least one --payload parameter is required"; return 1; }
    printf '%s' "$_v" | grep -q -- '--lua-desync=' || { kzm2_manual_dpi_msg "En az bir --lua-desync parametresi olmal&#305;" "At least one --lua-desync parameter is required"; return 1; }
    _bad_repeats="$(printf '%s
' "$_v" | tr ' :' '

' | awk -F= '/^repeats=/{ if ($2 !~ /^[0-9]+$/ || $2 < 1 || $2 > 20) print $2 }' | head -n1)"
    [ -z "$_bad_repeats" ] || { kzm2_manual_dpi_msg "repeats degeri 1-20 araliginda olmal&#305;" "repeats value must be between 1 and 20"; return 1; }
    return 0
}
kzm2_manual_dpi_expand_hostlist() {
    _v="$1"
    _hl="--hostlist=/opt/zapret2/ipset/zapret-hosts-user.txt --hostlist-exclude=/opt/zapret2/ipset/zapret-hosts-user-exclude.txt --hostlist-auto=/opt/zapret2/ipset/zapret-hosts-auto.txt --hostlist-auto-fail-threshold=3 --hostlist-auto-fail-time=60 --hostlist-auto-retrans-threshold=3 --hostlist-auto-retrans-reset=1 --hostlist-auto-retrans-maxseq=32768 --hostlist-auto-incoming-maxseq=4096 --hostlist-auto-udp-in=1 --hostlist-auto-udp-out=4"
    _hl_noauto="--hostlist=/opt/zapret2/ipset/zapret-hosts-user.txt --hostlist-exclude=/opt/zapret2/ipset/zapret-hosts-user-exclude.txt"
    printf '%s' "$_v" | sed "s|<HOSTLIST_NOAUTO>|$_hl_noauto|g; s|<HOSTLIST>|$_hl|g"
}

kzm2_manual_dpi_dryrun() {
    _opt="$1"
    _bin="/opt/zapret2/nfq2/nfqws2"
    _log="/tmp/kzm2_manualdpi_dryrun.log"
    [ -x "$_bin" ] || { printf '%s
' "nfqws2 binary not found" > "$_log"; return 1; }

    _opt_one="$(printf '%s
' "$_opt" | tr '
	' '   ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$_opt_one" ] || { printf '%s
' "empty profile" > "$_log"; return 1; }

    _opt_run="$(kzm2_manual_dpi_expand_hostlist "$_opt_one")"
    _args_file="/tmp/kzm2_manualdpi_args.$$"
    {
        printf '%s
' '--fwmark=0x40000000'
        printf '%s
' '--lua-init=@/opt/zapret2/lua/zapret-lib.lua'
        printf '%s
' '--lua-init=@/opt/zapret2/lua/zapret-antidpi.lua'
        printf '%s
' '--lua-init=@/opt/zapret2/lua/zapret-auto.lua'
        printf '%s
' '--qnum=300'
        printf '%s
' "$_opt_run" | tr ' ' '
' | sed '/^[[:space:]]*$/d'
    } > "$_args_file" || { rm -f "$_args_file"; return 1; }

    # Guard kalsin: nfqws2 surume gore bazen @file, bazen direkt arg kabul ediyor.
    # Bu yuzden iki uyumlu dry-run yolu denenir; ikisi de hataliysa bloklanir.
    : > "$_log"
    set -f
    _args="$(cat "$_args_file" 2>/dev/null)"
    "$_bin" --dry-run $_args > "$_log" 2>&1
    _rc=$?
    set +f
    if [ "$_rc" -eq 0 ]; then
        rm -f "$_args_file" 2>/dev/null
        return 0
    fi
    printf '
--- retry with @file ---
' >> "$_log"
    _args_file2="/tmp/kzm2_manualdpi_args2.$$"
    { printf '%s
' '--dry-run'; cat "$_args_file" 2>/dev/null; } > "$_args_file2" || { rm -f "$_args_file" "$_args_file2" 2>/dev/null; return 1; }
    "$_bin" "@$_args_file2" >> "$_log" 2>&1
    _rc=$?
    rm -f "$_args_file" "$_args_file2" 2>/dev/null
    return "$_rc"
}

kzm2_manual_dpi_write() {
    _opt="$1"
    KZM2_MANUAL_DPI_BAK=""
    mkdir -p /opt/zapret2 2>/dev/null
    [ -f /opt/zapret2/config ] || return 1
    # 3'lu rotating manual backup: .1 en yeni, .3 en eski
    rm -f /opt/zapret2/config.bak_manual.3 2>/dev/null
    [ -f /opt/zapret2/config.bak_manual.2 ] && mv /opt/zapret2/config.bak_manual.2 /opt/zapret2/config.bak_manual.3 2>/dev/null
    [ -f /opt/zapret2/config.bak_manual.1 ] && mv /opt/zapret2/config.bak_manual.1 /opt/zapret2/config.bak_manual.2 2>/dev/null
    KZM2_MANUAL_DPI_BAK="/opt/zapret2/config.bak_manual.1"
    cp -a /opt/zapret2/config "$KZM2_MANUAL_DPI_BAK" 2>/dev/null || return 1

    _opt_one="$(printf '%s\n' "$_opt" | tr '\r\n\t' '   ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$_opt_one" ] || return 1

    _tmp="/tmp/kzm2_manual_dpi.$$"
    _written=0
    _skip=0
    : > "$_tmp" || return 1
    while IFS= read -r _line || [ -n "$_line" ]; do
        if [ "$_skip" = "1" ]; then
            case "$_line" in
                *\"*) _skip=0 ;;
            esac
            continue
        fi
        case "$_line" in
            NFQWS2_OPT=*)
                printf 'NFQWS2_OPT="%s "\n' "$_opt_one" >> "$_tmp" || { rm -f "$_tmp"; return 1; }
                _written=1
                case "$_line" in
                    *\"*) : ;;
                    *) _skip=1 ;;
                esac
                ;;
            *)
                printf '%s\n' "$_line" >> "$_tmp" || { rm -f "$_tmp"; return 1; }
                ;;
        esac
    done < /opt/zapret2/config
    [ "$_written" = "1" ] || printf 'NFQWS2_OPT="%s "\n' "$_opt_one" >> "$_tmp"
    # Config syntax guard: bozuk quote/shell formatini asil config'e yazmadan yakala.
    if ! sh -n "$_tmp" >/dev/null 2>&1; then
        rm -f "$_tmp" 2>/dev/null
        return 1
    fi
    grep -q '^NFQWS2_OPT=".*"' "$_tmp" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
    mv "$_tmp" /opt/zapret2/config 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }

    grep -q '^NFQWS2_OPT=".*"' /opt/zapret2/config 2>/dev/null || return 1
    printf '%s' "custom" > /opt/zapret2/dpi_profile 2>/dev/null
    printf '%s' "manual" > /opt/zapret2/dpi_profile_origin 2>/dev/null
    printf '%s\n' "$_opt_one" > /opt/zapret2/dpi_profile_params 2>/dev/null
    healthmon_log "$(date '+%Y-%m-%d %H:%M:%S') | dpi_profile_change | profile=custom | scope=$(get_scope_mode) | new_opt=$_opt_one | src=manualdpi"
    return 0
}

kzm2_manual_dpi_is_running() {
    pidof nfqws2 >/dev/null 2>&1
}

kzm2_manual_dpi_wait_running() {
    _i=0
    while [ "$_i" -lt 10 ]; do
        kzm2_manual_dpi_is_running && return 0
        sleep 1
        _i=$(( _i + 1 ))
    done
    return 1
}

kzm2_manual_dpi_recovery_restart() {
    rm -f /tmp/.zapret2_paused /opt/var/run/nfqws2.pid 2>/dev/null
    _script="/opt/lib/opkg/keenetic_zapret2_manager.sh"
    if [ -f "$_script" ]; then
        KZM2_SKIP_LOCK=1 sh "$_script" --cgi-action restart_zapret2 >/dev/null 2>&1
    else
        /opt/etc/init.d/S90-zapret2 restart >/dev/null 2>&1 || /opt/zapret2/init.d/sysv/zapret2 restart >/dev/null 2>&1
    fi
    kzm2_manual_dpi_wait_running && return 0
    killall nfqws2 >/dev/null 2>&1 || true
    rm -f /opt/var/run/nfqws2.pid /tmp/.zapret2_paused 2>/dev/null
    /opt/zapret2/init.d/sysv/zapret2 stop >/dev/null 2>&1 || true
    sleep 1
    /opt/zapret2/init.d/sysv/zapret2 start >/dev/null 2>&1 || /opt/etc/init.d/S90-zapret2 start >/dev/null 2>&1
    kzm2_manual_dpi_wait_running
}

kzm2_manual_dpi_restart_checked() {
    kzm2_manual_dpi_recovery_restart
}

kzm2_manual_dpi_rollback() {
    _bak="$1"
    [ -n "$_bak" ] && [ -f "$_bak" ] || return 1
    cp -a "$_bak" /opt/zapret2/config 2>/dev/null || return 1
    kzm2_manual_dpi_recovery_restart
}
refresh() { sh /opt/bin/kzm2_status_gen.sh >/dev/null 2>&1; }
wait_zapret2() {
    # $1: "up" veya "down" — beklenen durum; max 8 saniye
    local _want="$1" _i=0
    while [ "$_i" -lt 8 ]; do
        if [ "$_want" = "up" ]; then
            ps 2>/dev/null | grep -q "[n]fqws" && break
        else
            ps 2>/dev/null | grep -q "[n]fqws" || break
        fi
        sleep 1; _i=$(( _i + 1 ))
    done
}
case "$ACTION" in
    zapret_start)
        rm -f /tmp/.zapret2_paused 2>/dev/null
        _kzm="/opt/lib/opkg/keenetic_zapret2_manager.sh"
        [ -f "$_kzm" ] && KZM2_SKIP_LOCK=1 sh "$_kzm" --cgi-action fix_permissions >/dev/null 2>&1
        sh /opt/etc/init.d/S90-zapret2 start >/dev/null 2>&1
        wait_zapret2 up; refresh; ok "Zapret2 baslatildi" ;;
    zapret_stop)
        touch /tmp/.zapret2_paused 2>/dev/null
        sh /opt/etc/init.d/S90-zapret2 stop >/dev/null 2>&1
        wait_zapret2 down; refresh; ok "Zapret2 durduruldu" ;;
    zapret_restart)
        _kzm="/opt/lib/opkg/keenetic_zapret2_manager.sh"
        [ -f "$_kzm" ] || { ok "Zapret2 yeniden baslatildi"; exit 0; }
        KZM2_SKIP_LOCK=1 sh "$_kzm" --cgi-action restart_zapret2 >/dev/null 2>&1
        sleep 2; wait_zapret2 up; sleep 2; refresh; ok "Zapret2 yeniden baslatildi" ;;
    fix_permissions)
        fix_zapret2_runtime_permissions 2>/dev/null
        ok "Izinler duzeltildi" ;;
    healthmon_start)
        CONF=/opt/etc/healthmon.conf
        SCRIPT="/opt/lib/opkg/keenetic_zapret2_manager.sh"
        if [ -f "$CONF" ]; then
            sed -i 's/^HM_ENABLE=.*/HM_ENABLE="1"/' "$CONF" 2>/dev/null
            # Autorestart kapali kalmamali — "0" ise "1" yap
            sed -i 's/^HM_ZAPRET_AUTORESTART="0"/HM_ZAPRET_AUTORESTART="1"/' "$CONF" 2>/dev/null
        else
            printf 'HM_ENABLE="1"\nHM_ZAPRET_AUTORESTART="1"\n' > "$CONF"
        fi
        # Zaten calisiyor mu kontrol et
        _hmpid="$(cat /tmp/kzm2_healthmon.pid 2>/dev/null)"
        if [ -n "$_hmpid" ] && kill -0 "$_hmpid" 2>/dev/null; then
            refresh; ok "Health Monitor zaten calisiyor"
        else
            rm -f /tmp/kzm2_healthmon.pid 2>/dev/null
            rm -rf /tmp/kzm2_healthmon.lock 2>/dev/null
            # trap+double-fork: lighttpd CGI kapaninca SIGHUP/SIGTERM gonderir
            # Subshell icinde sinyalleri engelleyip arka plana alinca init'e baglanir
            (KZM2_SKIP_LOCK=1 sh "$SCRIPT" --healthmon-daemon </dev/null >>/tmp/kzm2_healthmon.log 2>&1 &)
            sleep 2; refresh; ok "Health Monitor baslatildi"
        fi ;;
    healthmon_stop)
        CONF=/opt/etc/healthmon.conf
        [ -f "$CONF" ] && sed -i 's/^HM_ENABLE=.*/HM_ENABLE="0"/' "$CONF" 2>/dev/null
        _hmpid="$(cat /tmp/kzm2_healthmon.pid 2>/dev/null)"
        [ -n "$_hmpid" ] && kill "$_hmpid" 2>/dev/null
        sleep 1; rm -f /tmp/kzm2_healthmon.pid 2>/dev/null; refresh; ok "Health Monitor durduruldu" ;;
    healthmon_restart)
        _kzm="/opt/lib/opkg/keenetic_zapret2_manager.sh"
        [ -f "$_kzm" ] || { fail "KZM2 script bulunamadi"; exit 0; }
        # Once durdur
        _hmpid="$(cat /tmp/kzm2_healthmon.pid 2>/dev/null)"
        [ -n "$_hmpid" ] && kill "$_hmpid" 2>/dev/null
        sleep 1; kill -9 "$_hmpid" 2>/dev/null; rm -f /tmp/kzm2_healthmon.pid 2>/dev/null
        rm -rf /tmp/kzm2_healthmon.lock 2>/dev/null
        # HM_ENABLE=1 yaz ve autostart kur
        CONF=/opt/etc/healthmon.conf
        [ -f "$CONF" ] && sed -i 's/^HM_ENABLE=.*/HM_ENABLE="1"/' "$CONF" 2>/dev/null
        # init.d autostart yoksa kur
        [ -f /opt/etc/init.d/S99kzm2_healthmon ] || KZM2_SKIP_LOCK=1 sh "$_kzm" --cgi-action healthmon_start >/dev/null 2>&1
        # Yeniden baslat
        (KZM2_SKIP_LOCK=1 sh "$_kzm" --healthmon-daemon </dev/null >>/tmp/kzm2_healthmon.log 2>&1 &)
        sleep 2
        refresh
        ok "Health Monitor yeniden baslatildi" ;;
    hm_get)
        CONF=/opt/etc/healthmon.conf
        [ -f "$CONF" ] || { fail "Config bulunamadi"; exit 0; }
        . "$CONF" 2>/dev/null
        HM_INTERVAL="${HM_INTERVAL:-60}"
        HM_HEARTBEAT_SEC="${HM_HEARTBEAT_SEC:-300}"
        HM_COOLDOWN_SEC="${HM_COOLDOWN_SEC:-600}"
        HM_UPDATECHECK_ENABLE="${HM_UPDATECHECK_ENABLE:-1}"
        HM_UPDATECHECK_SEC="${HM_UPDATECHECK_SEC:-21600}"
        HM_AUTOUPDATE_MODE="${HM_AUTOUPDATE_MODE:-2}"
        HM_CPU_WARN="${HM_CPU_WARN:-70}"
        HM_CPU_WARN_DUR="${HM_CPU_WARN_DUR:-180}"
        HM_CPU_CRIT="${HM_CPU_CRIT:-90}"
        HM_CPU_CRIT_DUR="${HM_CPU_CRIT_DUR:-60}"
        HM_DISK_WARN="${HM_DISK_WARN:-90}"
        HM_RAM_WARN_MB="${HM_RAM_WARN_MB:-40}"
        HM_ZAPRET_WATCHDOG="${HM_ZAPRET_WATCHDOG:-1}"
        HM_ZAPRET_COOLDOWN_SEC="${HM_ZAPRET_COOLDOWN_SEC:-120}"
        HM_ZAPRET_AUTORESTART="${HM_ZAPRET_AUTORESTART:-1}"
        HM_QLEN_WATCHDOG="${HM_QLEN_WATCHDOG:-1}"
        HM_QLEN_WARN_TH="${HM_QLEN_WARN_TH:-50}"
        HM_QLEN_CRIT_TURNS="${HM_QLEN_CRIT_TURNS:-1}"
        HM_KEENDNS_CURL_SEC="${HM_KEENDNS_CURL_SEC:-120}"
        HM_DEBUG="${HM_DEBUG:-0}"
        HM_NFQWS_ALERT="${HM_NFQWS_ALERT:-1}"
        HM_SYSLOG_WATCH="${HM_SYSLOG_WATCH:-0}"
        HM_SYSLOG_COOLDOWN_SEC="${HM_SYSLOG_COOLDOWN_SEC:-600}"
        HM_SYSLOG_IKE_COOLDOWN_SEC="${HM_SYSLOG_IKE_COOLDOWN_SEC:-3600}"
        _load=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "?")
        _ram_free=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo "?")
        _disk_raw=$(df -P /opt 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5);print $5}')
        _disk_used=$(df -P /opt 2>/dev/null | awk 'NR==2{printf "%.0f",$3/1024}')
        if [ "${_disk_raw:-0}" -eq 0 ] && [ "${_disk_used:-0}" -gt 0 ] 2>/dev/null; then
            _disk="<1"
        else
            _disk="${_disk_raw:-0}"
        fi
        pgrep -f "/opt/zapret2/nfq2/nfqws2" >/dev/null 2>&1 && _zst="AKT&#304;F" || _zst="PAS&#304;F"
        _cgi_lang="$(cat /opt/zapret2/lang 2>/dev/null | tr -d '[:space:]' | head -c2)"
        [ "$_cgi_lang" = "en" ] && _zst="$(pgrep -f '/opt/zapret2/nfq2/nfqws2' >/dev/null 2>&1 && echo 'ACTIVE' || echo 'INACTIVE')"
        case "$HM_AUTOUPDATE_MODE" in
            2) _mode="$([ "$_cgi_lang" = "en" ] && echo 'Auto Install' || echo 'Oto Kur')" ;;
            1) _mode="$([ "$_cgi_lang" = "en" ] && echo 'Notify' || echo 'Bildir')" ;;
            *) _mode="$([ "$_cgi_lang" = "en" ] && echo 'Off' || echo 'Kapal&#305;')" ;;
        esac
        if [ "$_cgi_lang" = "en" ]; then
            [ "$HM_UPDATECHECK_ENABLE" = "1" ] && _upd="On" || _upd="Off"
            [ "${HM_ZAPRET_WATCHDOG}" = "1" ] && _zwd="On" || _zwd="Off"
            [ "${HM_ZAPRET_AUTORESTART}" = "1" ] && _zar="On" || _zar="Off"
            [ "${HM_QLEN_WATCHDOG}" = "1" ] && _qwd="On" || _qwd="Off"
            [ "${HM_WANMON_ENABLE:-0}" = "1" ] && _wmen="On" || _wmen="Off"
            [ "${HM_SYSLOG_WATCH:-0}" = "1" ] && _swd="On" || _swd="Off"
            [ "${HM_DEBUG:-0}" = "1" ] && _dbg="On" || _dbg="Off"
            [ "${HM_NFQWS_ALERT:-1}" = "1" ] && _nalert="On" || _nalert="Off"
        else
            [ "$HM_UPDATECHECK_ENABLE" = "1" ] && _upd="A&#231;&#305;k" || _upd="Kapal&#305;"
            [ "${HM_ZAPRET_WATCHDOG}" = "1" ] && _zwd="A&#231;&#305;k" || _zwd="Kapal&#305;"
            [ "${HM_ZAPRET_AUTORESTART}" = "1" ] && _zar="A&#231;&#305;k" || _zar="Kapal&#305;"
            [ "${HM_QLEN_WATCHDOG}" = "1" ] && _qwd="A&#231;&#305;k" || _qwd="Kapal&#305;"
            [ "${HM_WANMON_ENABLE:-0}" = "1" ] && _wmen="A&#231;&#305;k" || _wmen="Kapal&#305;"
            [ "${HM_SYSLOG_WATCH:-0}" = "1" ] && _swd="A&#231;&#305;k" || _swd="Kapal&#305;"
            [ "${HM_DEBUG:-0}" = "1" ] && _dbg="A&#231;&#305;k" || _dbg="Kapal&#305;"
            [ "${HM_NFQWS_ALERT:-1}" = "1" ] && _nalert="A&#231;&#305;k" || _nalert="Kapal&#305;"
        fi
        _r() { printf "<div class='info-row'><div class='lbl'>%s</div><div class='val'>%s</div></div>" "$1" "$2"; }
        _s() { printf "<div class='info-sec'>%s</div>" "$1"; }
        _rows=""
        if [ "$_cgi_lang" = "en" ]; then
        _rows="${_rows}$(_s "CONFIGURATION")"
        _rows="${_rows}$(_r "Check Interval" "${HM_INTERVAL}s")"
        _rows="${_rows}$(_r "Heartbeat" "${HM_HEARTBEAT_SEC}s")"
        _rows="${_rows}$(_r "Notification Cooldown" "${HM_COOLDOWN_SEC}s")"
        _rows="${_rows}$(_r "Update Check" "${_upd} / every ${HM_UPDATECHECK_SEC}s")"
        _rows="${_rows}$(_r "Auto Update" "${_mode} (mode ${HM_AUTOUPDATE_MODE})")"
        _rows="${_rows}$(_s "THRESHOLDS")"
        _rows="${_rows}$(_r "CPU Warning" "${HM_CPU_WARN}% / ${HM_CPU_WARN_DUR}s")"
        _rows="${_rows}$(_r "CPU Critical" "${HM_CPU_CRIT}% / ${HM_CPU_CRIT_DUR}s")"
        _rows="${_rows}$(_r "Disk /opt Warning" "at ${HM_DISK_WARN}% full")"
        _rows="${_rows}$(_r "RAM Warning" "below ${HM_RAM_WARN_MB} MB")"
        _rows="${_rows}$(_s "ZAPRET2")"
        _rows="${_rows}$(_r "Zapret2 Watchdog" "${_zwd}")"
        _rows="${_rows}$(_r "Watchdog Cooldown" "${HM_ZAPRET_COOLDOWN_SEC}s")"
        _rows="${_rows}$(_r "Auto Restart" "${_zar}")"
        _rows="${_rows}$(_r "NFQUEUE Queue Watchdog" "${_qwd} | <span style='color:var(--muted)'>Threshold:</span> <b>${HM_QLEN_WARN_TH}</b> Packets | <span style='color:var(--muted)'>Consecutive:</span> <b>${HM_QLEN_CRIT_TURNS}</b> Turns")"
        _rows="${_rows}$(_r "nfqws2 Queue Alert" "${_nalert}")"
        _rows="${_rows}$(_r "WAN Monitoring" "${_wmen} | <span style='color:var(--muted)'>Failure Threshold:</span> <b>${HM_WANMON_FAIL_TH:-3}</b> Failed Pings | <span style='color:var(--muted)'>Recovery Threshold:</span> <b>${HM_WANMON_OK_TH:-2}</b> Successful Pings | <span style='color:var(--muted)'>Interface:</span> ${HM_WANMON_IFACE:-auto}")"
        _rows="${_rows}$(_r "KeenDNS Check Interval" "${HM_KEENDNS_CURL_SEC}s")"
        _rows="${_rows}$(_r "System Log Watch" "${_swd} | <span style='color:var(--muted)'>Critical Cooldown:</span> <b>${HM_SYSLOG_COOLDOWN_SEC}</b>s | <span style='color:var(--muted)'>IKE Cooldown:</span> <b>${HM_SYSLOG_IKE_COOLDOWN_SEC}</b>s")"
        _rows="${_rows}$(_r "Debug Mode" "${_dbg}")"
        _rows="${_rows}$(_s "CURRENT STATUS")"
        _rows="${_rows}$(_r "CPU Load" "${_load}")"
        _rows="${_rows}$(_r "Free RAM" "${_ram_free} MB")"
        _rows="${_rows}$(_r "Disk /opt" "${_disk}% used")"
        _rows="${_rows}$(_r "Zapret2" "${_zst}")"
        else
        _rows="${_rows}$(_s "KONFIGURASYON")"
        _rows="${_rows}$(_r "Kontrol Aral&#305;&#287;&#305;" "${HM_INTERVAL}s")"
        _rows="${_rows}$(_r "Heartbeat" "${HM_HEARTBEAT_SEC}s")"
        _rows="${_rows}$(_r "Bildirim Bekleme" "${HM_COOLDOWN_SEC}s")"
        _rows="${_rows}$(_r "G&#252;ncelleme Kontrol&#252;" "${_upd} / her ${HM_UPDATECHECK_SEC}s")"
        _rows="${_rows}$(_r "Oto G&#252;ncelleme" "${_mode} (mod ${HM_AUTOUPDATE_MODE})")"
        _rows="${_rows}$(_s "E&#350;&#304;KLER")"
        _rows="${_rows}$(_r "CPU Uyar&#305;" "${HM_CPU_WARN}% / ${HM_CPU_WARN_DUR}s")"
        _rows="${_rows}$(_r "CPU Kritik" "${HM_CPU_CRIT}% / ${HM_CPU_CRIT_DUR}s")"
        _rows="${_rows}$(_r "Disk /opt Uyar&#305;" "%${HM_DISK_WARN} dolulukta")"
        _rows="${_rows}$(_r "RAM Uyar&#305;" "${HM_RAM_WARN_MB} MB alt&#305;nda")"
        _rows="${_rows}$(_s "ZAPRET2")"
        _rows="${_rows}$(_r "Zapret2 Denetimi" "${_zwd}")"
        _rows="${_rows}$(_r "Denetim Bekleme" "${HM_ZAPRET_COOLDOWN_SEC}s")"
        _rows="${_rows}$(_r "Oto Yeniden Ba&#351;lat" "${_zar}")"
        _rows="${_rows}$(_r "NFQUEUE Kuyruk Denetimi" "${_qwd} | <span style='color:var(--muted)'>E&#351;ik:</span> <b>${HM_QLEN_WARN_TH}</b> Paket | <span style='color:var(--muted)'>Ard&#305;&#351;&#305;k:</span> <b>${HM_QLEN_CRIT_TURNS}</b> Tur")"
        _rows="${_rows}$(_r "nfqws2 Kuyruk Alarm&#305;" "${_nalert}")"
        _rows="${_rows}$(_r "WAN &#304;zleme" "${_wmen} | <span style='color:var(--muted)'>Kesinti E&#351;i&#287;i:</span> <b>${HM_WANMON_FAIL_TH:-3}</b> Ba&#351;ar&#305;s&#305;z Ping | <span style='color:var(--muted)'>Toparlanma E&#351;i&#287;i:</span> <b>${HM_WANMON_OK_TH:-2}</b> Ba&#351;ar&#305;l&#305; Ping | <span style='color:var(--muted)'>Aray&#252;z:</span> ${HM_WANMON_IFACE:-auto}")"
        _rows="${_rows}$(_r "KeenDNS Kontrol Aral&#305;&#287;&#305;" "${HM_KEENDNS_CURL_SEC}s")"
        _rows="${_rows}$(_r "Sistem Log &#304;zleme" "${_swd} | <span style='color:var(--muted)'>Kritik Bekleme:</span> <b>${HM_SYSLOG_COOLDOWN_SEC}</b>s | <span style='color:var(--muted)'>IKE Bekleme:</span> <b>${HM_SYSLOG_IKE_COOLDOWN_SEC}</b>s")"
        _rows="${_rows}$(_r "Debug Modu" "${_dbg}")"
        _rows="${_rows}$(_s "ANLIK DURUM")"
        _rows="${_rows}$(_r "CPU Y&#252;k&#252;" "${_load}")"
        _rows="${_rows}$(_r "Bo&#351; RAM" "${_ram_free} MB")"
        _rows="${_rows}$(_r "Disk /opt" "${_disk}% dolu")"
        _rows="${_rows}$(_r "Zapret2" "${_zst}")"
        fi
        printf '{"ok":1,"data":"%s"}' "$(printf '%s' "$_rows" | sed 's/"/\\"/g')" ;;
    tg_test)
        _kzm="/opt/lib/opkg/keenetic_zapret2_manager.sh"
        [ -f "$_kzm" ] || { fail "KZM2 script bulunamadi"; exit 0; }
        KZM2_SKIP_LOCK=1 sh "$_kzm" --cgi-action tg_test >/dev/null 2>&1
        ok "Test mesaji gonderildi" ;;
    tg_start)
        _kzm="/opt/lib/opkg/keenetic_zapret2_manager.sh"
        [ -f "$_kzm" ] || { fail "KZM2 script bulunamadi"; exit 0; }
        _tg_en="$(grep -s '^TG_BOT_ENABLE=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')"
        [ "$_tg_en" != "1" ] && { fail "Bot yapilandirilmamis"; exit 0; }
        _pid_f="/tmp/kzm2_telegram_bot.pid"
        if [ -f "$_pid_f" ] && kill -0 "$(cat "$_pid_f" 2>/dev/null)" 2>/dev/null; then
            ok "Bot zaten calisiyor"; exit 0
        fi
        _log="/tmp/kzm2_telegram_bot.log"
        if command -v nohup >/dev/null 2>&1; then
            nohup sh "$_kzm" --telegram-daemon </dev/null >>"$_log" 2>&1 &
        else
            sh "$_kzm" --telegram-daemon </dev/null >>"$_log" 2>&1 &
        fi
        sleep 1
        _real_pid="$(ps 2>/dev/null | awk '/--telegram-daemon/ && !/awk/{print $1}' | head -1)"
        [ -n "$_real_pid" ] && echo "$_real_pid" > "$_pid_f" || echo $! > "$_pid_f"
        ok "Bot baslatildi" ;;
    tg_stop)
        _pid_f="/tmp/kzm2_telegram_bot.pid"
        if [ -f "$_pid_f" ]; then
            _pid="$(cat "$_pid_f" 2>/dev/null)"
            if [ -n "$_pid" ]; then
                kill "$_pid" 2>/dev/null || true
                sleep 1
                kill -9 "$_pid" 2>/dev/null || true
            fi
            rm -f "$_pid_f" 2>/dev/null
        fi
        # PID dosyasi disinda kalan --telegram-daemon processleri de temizle
        ps 2>/dev/null | awk '/--telegram-daemon/ && !/awk/{print $1}' | \
            while IFS= read -r _p; do kill -9 "$_p" 2>/dev/null || true; done
        # Process gercekten olene kadar bekle (max 5 saniye)
        _w=0
        while [ "$_w" -lt 5 ]; do
            ps 2>/dev/null | grep -q '[t]elegram-daemon' || break
            sleep 1; _w=$((_w+1))
        done
        ok "Bot durduruldu" ;;
    tg_restart)
        _kzm="/opt/lib/opkg/keenetic_zapret2_manager.sh"
        _pid_f="/tmp/kzm2_telegram_bot.pid"
        # tg_stop ile ayni mantik
        if [ -f "$_pid_f" ]; then
            _pid="$(cat "$_pid_f" 2>/dev/null)"
            if [ -n "$_pid" ]; then
                kill "$_pid" 2>/dev/null || true
                sleep 2
                kill -9 "$_pid" 2>/dev/null || true
            fi
            rm -f "$_pid_f" 2>/dev/null
        fi
        for _kp in $(ps 2>/dev/null | awk '/--telegram-daemon/ && !/awk/{print $1}'); do
            kill -9 "$_kp" 2>/dev/null || true
        done
        # Process gercekten olene kadar bekle (max 5 saniye)
        _w=0
        while [ "$_w" -lt 5 ]; do
            ps 2>/dev/null | grep -q '[t]elegram-daemon' || break
            sleep 1; _w=$((_w+1))
        done
        # tg_start ile ayni kontrol
        _tg_en="$(grep -s '^TG_BOT_ENABLE=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')"
        [ "$_tg_en" != "1" ] && { ok "Bot durduruldu (yapilandirilmamis)"; exit 0; }
        # tg_start ile birebir ayni baslatma
        _log="/tmp/kzm2_telegram_bot.log"
        if command -v nohup >/dev/null 2>&1; then
            nohup sh "$_kzm" --telegram-daemon </dev/null >>"$_log" 2>&1 &
        else
            sh "$_kzm" --telegram-daemon </dev/null >>"$_log" 2>&1 &
        fi
        sleep 1
        _real_pid="$(ps 2>/dev/null | awk '/--telegram-daemon/ && !/awk/{print $1}' | head -1)"
        [ -n "$_real_pid" ] && echo "$_real_pid" > "$_pid_f" || echo $! > "$_pid_f"
        ok "Bot yeniden baslatildi" ;;
    tg_info)
        _tok="$(grep -s '^TG_BOT_TOKEN=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')"
        _chat="$(grep -s '^TG_CHAT_ID=' /opt/etc/telegram.conf | cut -d= -f2 | tr -d '"')"
        _tok_m=""; _chat_m=""
        if [ -n "$_tok" ]; then
            _tok_pfx="$(printf '%s' "$_tok" | cut -c1-6)"
            _tok_m="${_tok_pfx}...****"
        fi
        if [ -n "$_chat" ]; then
            _clen="${#_chat}"
            if [ "$_clen" -gt 4 ]; then
                _chat_sfx="$(printf '%s' "$_chat" | sed 's/.*\(....\)$/\1/')"
                _chat_m="****${_chat_sfx}"
            else
                _chat_m="****"
            fi
        fi
        printf '{"ok":1,"token":"%s","chat":"%s"}' "$_tok_m" "$_chat_m" ;;
    health_run)
        _kzm="/opt/lib/opkg/keenetic_zapret2_manager.sh"
        [ -f "$_kzm" ] || { fail "KZM2 script bulunamadi"; exit 0; }
        printf '{"running":1}\n' > /tmp/kzm_health_result.json
        KZM2_SKIP_LOCK=1 sh "$_kzm" --cgi-action health_run_bg >/dev/null 2>&1 &
        ok "Saglik kontrolu baslatildi" ;;
    health_get)
        _hf="/tmp/kzm_health_result.json"
        if [ -f "$_hf" ]; then
            cat "$_hf"
        else
            printf '{"ok":0,"msg":"Sonuc bulunamadi. Once calistirin."}'
        fi ;;
    dpi_get)
        _p=$(cat "$DPI_FILE" 2>/dev/null | tr -d '\n'); [ -z "$_p" ] && _p="tt_default"
        case "$_p" in
            tt_default)      _n="Varsayilan Zapret2 (TTL2 fake)" ;;
            tt_fiber)        _n="Turk Telekom Fiber (TTL2 fake)" ;;
            superonline_fiber) _n="Superonline Fiber (TTL6 hostcase)" ;;
            blockcheck_auto) _n="Blockcheck Otomatik (Auto)" ;;
            custom)          _n="Ozel NFQWS2_OPT" ;;
            tt_alt|sol|sol_alt|sol_fiber|turkcell_mob|vodafone_mob) _n="Eski KZM profili (devre disi)" ;;
            *)               _n="$_p" ;;
        esac
        printf '{"ok":1,"data":"%s","name":"%s"}' "$_p" "$_n" ;;
    dpi_set)
        _p=$(get_param profile)
        [ -z "$_p" ] && { fail "Profil belirtilmedi"; exit 0; }
        case "$_p" in
            tt_default|tt_fiber|superonline_fiber|blockcheck_auto|none) ;;
            *) fail "Gecersiz veya devre disi profil: $_p"; exit 0 ;;
        esac
        _kzm="/opt/lib/opkg/keenetic_zapret2_manager.sh"
        [ -f "$_kzm" ] || { fail "KZM2 script bulunamadi"; exit 0; }
        echo "$(date '+%Y-%m-%d %H:%M:%S') | dpi_profile_change | profile=$_p | scope=$(cat /opt/zapret2/scope_mode 2>/dev/null | tr -d '[:space:]') | new_opt=$(grep '^NFQWS2_OPT=' /opt/zapret2/config 2>/dev/null | cut -d'"' -f2) | src=webpanel" >> /tmp/kzm2_healthmon.log 2>/dev/null
        KZM2_SKIP_LOCK=1 sh "$_kzm" --cgi-action dpi_set "$_p" >/dev/null 2>&1 &
        sleep 3; refresh; ok "Profil ${_p} ayarlandi ve Zapret2 yeniden baslatildi" ;;
    manual_dpi_export|manualdpi_export)
        kzm2_manual_dpi_export_web ;;
    manual_dpi_get|manualdpi_get)
        _src="$(get_param source)"
        case "$_src" in
            default) _val="$(kzm2_manual_dpi_default)" ;;
            runtime) _val="$(kzm2_manual_dpi_runtime 2>/dev/null)"; [ -n "$_val" ] || _val="$(kzm2_manual_dpi_config)" ;;
            *) _val="$(kzm2_manual_dpi_config)" ;;
        esac
        [ -n "$_val" ] || _val="$(kzm2_manual_dpi_default)"
        _val="$(kzm2_manual_dpi_pretty "$_val")"
        printf '{"ok":1,"data":"%s"}' "$(kzm2_json_escape "$_val")" ;;
    manual_dpi_adv_get|manualdpi_adv_get)
        _src="$(get_param source)"
        kzm2_manual_dpi_adv_json "$_src" ;;
    manual_dpi_adv_save|manualdpi_adv_save)
        _ptcp="$(kzm2_url_decode_basic "$(get_param_raw ports_tcp)" | tr -d '[:space:]')"
        _pudp="$(kzm2_url_decode_basic "$(get_param_raw ports_udp)" | tr -d '[:space:]')"
        _tout="$(kzm2_url_decode_basic "$(get_param_raw tcp_out)" | tr -d '[:space:]')"
        _tin="$(kzm2_url_decode_basic "$(get_param_raw tcp_in)" | tr -d '[:space:]')"
        _uout="$(kzm2_url_decode_basic "$(get_param_raw udp_out)" | tr -d '[:space:]')"
        _uin="$(kzm2_url_decode_basic "$(get_param_raw udp_in)" | tr -d '[:space:]')"
        _err_adv="$(kzm2_manual_dpi_adv_validate "$_ptcp" "$_pudp" "$_tout" "$_tin" "$_uout" "$_uin" 2>/dev/null)"
        if [ -n "$_err_adv" ]; then
            fail "$_err_adv"
        elif kzm2_manual_dpi_adv_write "$_ptcp" "$_pudp" "$_tout" "$_tin" "$_uout" "$_uin"; then
            _bak="$KZM2_MANUAL_DPI_ADV_BAK"
            if kzm2_manual_dpi_restart_checked; then
                refresh
                ok "$(kzm2_manual_dpi_msg 'Config de&#287;i&#351;kenleri kaydedildi ve Zapret2 yeniden ba&#351;lat&#305;ld&#305;' 'Config variables saved and Zapret2 restarted')"
            else
                kzm2_manual_dpi_rollback "$_bak"
                refresh
                fail "$(kzm2_manual_dpi_msg 'Config de&#287;i&#351;kenleri uygulamada ba&#351;ar&#305;s&#305;z oldu. &#214;nceki config geri y&#252;klendi.' 'Config variables failed to apply. Previous config was restored.')"
            fi
        else
            fail "$(kzm2_manual_dpi_msg 'Config de&#287;i&#351;kenleri yaz&#305;lamad&#305;. &#214;nceki config korundu' 'Config variables could not be written. Previous config was kept')"
        fi ;;
    manual_dpi_save|manualdpi_save)
        _raw="$(get_param_raw opt)"
        _opt="$(kzm2_url_decode_basic "$_raw" | tr '\r\n\t' '   ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ *//; s/ *$//')"
        _err="$(kzm2_manual_dpi_validate "$_opt" 2>/dev/null)"
        if [ -n "$_err" ]; then
            fail "$_err"
        elif kzm2_manual_dpi_write "$_opt"; then
            _bak="$KZM2_MANUAL_DPI_BAK"
            if kzm2_manual_dpi_restart_checked; then
                refresh
                ok "$(kzm2_manual_dpi_msg 'Manuel DPI profili uyguland&#305;' 'Manual DPI profile applied')"
            else
                kzm2_manual_dpi_rollback "$_bak"
                refresh
                if kzm2_manual_dpi_is_running; then fail "$(kzm2_manual_dpi_msg 'Manuel profil ba&#351;ar&#305;s&#305;z oldu. &#214;nceki &#231;al&#305;&#351;an profil geri y&#252;klendi.' 'Manual profile failed. Previous working profile was restored.')"; else fail "$(kzm2_manual_dpi_msg 'Manuel profil ba&#351;ar&#305;s&#305;z oldu ve Zapret2 ba&#351;lat&#305;lamad&#305;. SSH ile kontrol edin.' 'Manual profile failed and Zapret2 could not be started. Check via SSH.')"; fi
            fi
        else
            fail "$(kzm2_manual_dpi_msg 'Manuel DPI profili yaz&#305;lamad&#305; veya do&#287;rulanamad&#305;. &#214;nceki profil korundu' 'Manual DPI profile could not be written or validated. Previous profile was kept')"
        fi ;;
    hl_get)
        ok_data "$(json_arr "$HL_USER")" ;;
    hl_add)
        _d=$(get_param domain); [ -z "$_d" ] && { fail "Domain bos"; exit 0; }
        grep -qxF "$_d" "$HL_USER" 2>/dev/null || printf '%s\n' "$_d" >> "$HL_USER"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | zapret_restart | triggered (web)" >> /tmp/kzm2_healthmon.log 2>/dev/null
        kzm_rebuild_profile_restart
        ok "Eklendi: $_d" ;;
    hl_del)
        _d=$(get_param domain); [ -z "$_d" ] && { fail "Domain bos"; exit 0; }
        sed -i "/^$(printf '%s' "$_d" | sed 's/[.[\*^$]/\\&/g')$/d" "$HL_USER" 2>/dev/null
        echo "$(date '+%Y-%m-%d %H:%M:%S') | zapret_restart | triggered (web)" >> /tmp/kzm2_healthmon.log 2>/dev/null
        kzm_rebuild_profile_restart
        ok "Silindi: $_d" ;;
    ex_get)
        ok_data "$(json_arr_domains_only "$HL_EXCL")" ;;
    ex_add)
        _d=$(get_param domain); [ -z "$_d" ] && { fail "Domain bos"; exit 0; }
        grep -qxF "$_d" "$HL_EXCL" 2>/dev/null || printf '%s\n' "$_d" >> "$HL_EXCL"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | zapret_restart | triggered (web)" >> /tmp/kzm2_healthmon.log 2>/dev/null
        kzm_rebuild_profile_restart
        ok "Eklendi: $_d" ;;
    ex_del)
        _d=$(get_param domain); [ -z "$_d" ] && { fail "Domain bos"; exit 0; }
        sed -i "/^$(printf '%s' "$_d" | sed 's/[.[\*^$]/\\&/g')$/d" "$HL_EXCL" 2>/dev/null
        echo "$(date '+%Y-%m-%d %H:%M:%S') | zapret_restart | triggered (web)" >> /tmp/kzm2_healthmon.log 2>/dev/null
        kzm_rebuild_profile_restart
        ok "Silindi: $_d" ;;
    auto_get)
        ok_data "$(json_arr "/opt/zapret2/ipset/zapret-hosts-auto.txt")" ;;
    auto_del)
        _d=$(get_param domain); [ -z "$_d" ] && { fail "Domain bos"; exit 0; }
        sed -i "/^$(printf '%s' "$_d" | sed 's/[.[\\*^$]/\\&/g')$/d" "/opt/zapret2/ipset/zapret-hosts-auto.txt" 2>/dev/null
        echo "$(date '+%Y-%m-%d %H:%M:%S') | zapret_restart | triggered (web)" >> /tmp/kzm2_healthmon.log 2>/dev/null
        kzm_rebuild_profile_restart
        ok "Silindi: $_d" ;;
    nozapret_get)
        ok_data "$(json_arr "/opt/zapret2/ipset/nozapret.txt")" ;;
    nozapret_add)
        _ip=$(get_param ip); [ -z "$_ip" ] && { fail "IP bos"; exit 0; }
        # Cakisma korumasi: ipset_clients.txt'den cikar
        sed -i "/^$(printf '%s' "$_ip" | sed 's/[.[\*^$]/\\&/g')$/d" "$IPSET_FILE" 2>/dev/null
        kzm_append_unique_line "/opt/zapret2/ipset/nozapret.txt" "$_ip"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | zapret_restart | triggered (web)" >> /tmp/kzm2_healthmon.log 2>/dev/null
        kzm_rebuild_profile_restart
        ok "Eklendi: $_ip" ;;
    nozapret_del)
        _ip=$(get_param ip); [ -z "$_ip" ] && { fail "IP bos"; exit 0; }
        sed -i "/^$(printf '%s' "$_ip" | sed 's/[.[\*^$]/\\&/g')$/d" "/opt/zapret2/ipset/nozapret.txt" 2>/dev/null
        echo "$(date '+%Y-%m-%d %H:%M:%S') | zapret_restart | triggered (web)" >> /tmp/kzm2_healthmon.log 2>/dev/null
        kzm_rebuild_profile_restart
        ok "Silindi: $_ip" ;;
    ipset_active_get)
        ok_data "$(json_arr "$IPSET_FILE")" ;;
    ip_get)
        ok_data "$(json_arr "$IPSET_FILE")" ;;
    ip_add)
        _ip=$(get_param ip); [ -z "$_ip" ] && { fail "IP bos"; exit 0; }
        kzm_append_unique_line "$IPSET_FILE" "$_ip"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | zapret_restart | triggered (web)" >> /tmp/kzm2_healthmon.log 2>/dev/null
        kzm_rebuild_profile_restart
        ok "Eklendi: $_ip" ;;
    ip_del)
        _ip=$(get_param ip); [ -z "$_ip" ] && { fail "IP bos"; exit 0; }
        sed -i "\|^$(printf '%s' "$_ip" | sed 's/[.[*^$]/\\&/g')$|d" "$IPSET_FILE" 2>/dev/null
        echo "$(date '+%Y-%m-%d %H:%M:%S') | zapret_restart | triggered (web)" >> /tmp/kzm2_healthmon.log 2>/dev/null
        kzm_rebuild_profile_restart
        ok "Silindi: $_ip" ;;
    sched_get)
        _line=$(crontab -l 2>/dev/null | grep "$SCHED_TAG" 2>/dev/null)
        [ -z "$_line" ] && { printf '{"ok":1,"data":""}'; exit 0; }
        _h=$(printf '%s' "$_line" | awk '{print $2}')
        _m=$(printf '%s' "$_line" | awk '{print $1}')
        _dow=$(printf '%s' "$_line" | awk '{print $5}')
        printf '{"ok":1,"data":"%02d:%02d","dow":"%s"}' "$_h" "$_m" "$_dow" ;;
    sched_set)
        _t=$(get_param time); [ -z "$_t" ] && { fail "Saat bos"; exit 0; }
        _dow=$(get_param dow); [ -z "$_dow" ] && _dow="*"
        case "$_dow" in [0-6]|"*") ;; *) _dow="*" ;; esac
        _h=$(printf '%s' "$_t" | cut -d: -f1 | sed 's/^0*//')
        _m=$(printf '%s' "$_t" | cut -d: -f2 | sed 's/^0*//')
        [ -z "$_h" ] && _h=0; [ -z "$_m" ] && _m=0
        _tmp="/tmp/kzm_cron_set.$$"
        crontab -l 2>/dev/null | grep -v "$SCHED_TAG" > "$_tmp"
        printf '%s %s * * %s LD_LIBRARY_PATH= ndmc -c "system reboot" %s\n' "$_m" "$_h" "$_dow" "$SCHED_TAG" >> "$_tmp"
        crontab "$_tmp"; rm -f "$_tmp"
        ok "Zamanlama ayarlandi: $_t (dow:$_dow)" ;;
    sched_del)
        _tmp="/tmp/kzm_cron_del.$$"
        crontab -l 2>/dev/null | grep -v "$SCHED_TAG" > "$_tmp"
        crontab "$_tmp"; rm -f "$_tmp"
        ok "Zamanlama kaldirildi" ;;
    opkg_sched_get)
        _line=$(crontab -l 2>/dev/null | grep '# KZM_OPKG_UPGRADE' 2>/dev/null)
        [ -z "$_line" ] && { printf '{"ok":1,"data":""}'; exit 0; }
        _h=$(printf '%s' "$_line" | awk '{print $2}')
        _m=$(printf '%s' "$_line" | awk '{print $1}')
        _dom=$(printf '%s' "$_line" | awk '{print $3}')
        case "$_dom" in
            "1,15") _period="biweekly" ;;
            "1")    _period="monthly" ;;
            *)      _period="weekly" ;;
        esac
        printf '{"ok":1,"data":"%02d:%02d","period":"%s"}' "$_h" "$_m" "$_period" ;;
    opkg_sched_set)
        _period=$(get_param period)
        _tmp="/tmp/kzm_opkg_cron_set.$$"
        crontab -l 2>/dev/null | grep -v '^#' | grep -v '# KZM_OPKG_UPGRADE' | grep -v '^[[:space:]]*$' > "$_tmp"
        case "$_period" in
            biweekly) printf '0 3 1,15 * * sh /opt/lib/opkg/keenetic_zapret2_manager.sh --opkg-upgrade # KZM_OPKG_UPGRADE\n' >> "$_tmp" ;;
            monthly)  printf '0 3 1 * * sh /opt/lib/opkg/keenetic_zapret2_manager.sh --opkg-upgrade # KZM_OPKG_UPGRADE\n' >> "$_tmp" ;;
            *)        printf '0 3 * * 0 sh /opt/lib/opkg/keenetic_zapret2_manager.sh --opkg-upgrade # KZM_OPKG_UPGRADE\n' >> "$_tmp" ;;
        esac
        crontab "$_tmp"; rm -f "$_tmp"
        ok "OPKG zamanlama ayarlandi: $_period" ;;
    opkg_sched_del)
        _tmp="/tmp/kzm_opkg_cron_del.$$"
        crontab -l 2>/dev/null | grep -v '^#' | grep -v '# KZM_OPKG_UPGRADE' | grep -v '^[[:space:]]*$' > "$_tmp"
        crontab "$_tmp"; rm -f "$_tmp"
        ok "OPKG zamanlama kaldirildi" ;;
    backup_settings)
        _dir="/opt/zapret2_backups/zapret2_settings"
        mkdir -p "$_dir" 2>/dev/null
        _ts=$(date +%Y%m%d_%H%M%S 2>/dev/null)
        _f="$_dir/zapret2_settings_${_ts}.tar.gz"
        _rels=""
        _ar() { [ -e "$1" ] && _rels="$_rels ${1#/}"; }
        _ar /opt/zapret2/config
        _ar /opt/zapret2/wan_if
        _ar /opt/zapret2/lang
        _ar /opt/zapret2/hostlist_mode
        _ar /opt/zapret2/scope_mode
        _ar /opt/zapret2/ipset_clients.txt
        _ar /opt/zapret2/ipset_clients_mode
        _ar /opt/zapret2/dpi_profile
        _ar /opt/zapret2/dpi_profile_origin
        _ar /opt/zapret2/dpi_profile_params
        _ar /opt/zapret2/blockcheck_auto_params
        _ar /opt/zapret2/dpi_profiles
        _ar /opt/etc/healthmon.conf
        _ar /opt/etc/telegram.conf
        _ar /opt/etc/kzm2_gui.conf
        _ar /opt/zapret2/init.d/sysv/zapret2.real
        _ar /opt/zapret2/init.d/sysv/custom.d/90-keenetic-client-ipset
        _ar /opt/etc/init.d/S99kzm2_healthmon
        for _xf in /opt/zapret2/ipset/*.txt; do [ -e "$_xf" ] && _rels="$_rels ${_xf#/}"; done
        [ -z "$(printf '%s' "$_rels" | tr -d ' ')" ] && { fail "Yedeklenecek dosya yok"; exit 0; }
        tar -C / -czf "$_f" $_rels 2>/dev/null
        [ -f "$_f" ] && [ -s "$_f" ] && ok "Yedeklendi: zapret2_settings_${_ts}.tar.gz" || { rm -f "$_f" 2>/dev/null; fail "Yedekleme basarisiz"; } ;;
    ipset_backup)
        _src="/opt/zapret2/ipset"
        _cur="/opt/zapret2_backups/current"
        _hist="/opt/zapret2_backups/history"
        mkdir -p "$_cur" "$_hist" 2>/dev/null
        ! ls "$_src"/*.txt >/dev/null 2>&1 && { fail "IPSET dosyasi bulunamadi"; exit 0; }
        _ts=$(date +%Y%m%d_%H%M%S 2>/dev/null)
        mkdir -p "$_hist/$_ts" 2>/dev/null
        _count=0
        for _xf in "$_src"/*.txt; do
            [ -f "$_xf" ] || continue
            cp -a "$_xf" "$_cur/$(basename "$_xf")" 2>/dev/null
            cp -a "$_xf" "$_hist/$_ts/$(basename "$_xf")" 2>/dev/null
            _count=$((_count+1))
        done
        for _xf in /opt/zapret2/ipset_clients.txt /opt/zapret2/ipset_clients_mode; do
            [ -f "$_xf" ] || continue
            cp -a "$_xf" "$_cur/$(basename "$_xf")" 2>/dev/null
            cp -a "$_xf" "$_hist/$_ts/$(basename "$_xf")" 2>/dev/null
            _count=$((_count+1))
        done
        ok "IPSET yedeklendi: $_count dosya" ;;
    ipset_list)
        _cur="/opt/zapret2_backups/current"
        _hist="/opt/zapret2_backups/history"
        _files=""
        if ls "$_cur"/*.txt >/dev/null 2>&1; then
            for _xf in "$_cur"/*.txt; do
                [ -f "$_xf" ] || continue
                _bn=$(basename "$_xf")
                _sz=$(wc -l < "$_xf" 2>/dev/null || echo "?")
                _files="${_files}${_bn}:${_sz}|"
            done
        fi
        _hlist="$(ls -1 "$_hist" 2>/dev/null | tail -n 5 | tr '\n' '|' | sed 's/|$//')"
        printf '{"ok":1,"files":"%s","history":"%s"}' "$_files" "$_hlist" ;;
    ipset_restore)
        _fn=$(get_param file); [ -z "$_fn" ] && { fail "Dosya belirtilmedi"; exit 0; }
        _cur="/opt/zapret2_backups/current"
        _dst="/opt/zapret2/ipset"
        _src="$_cur/$_fn"
        [ -f "$_src" ] || { fail "Dosya bulunamadi: $_fn"; exit 0; }
        mkdir -p "$_dst" 2>/dev/null
        case "$_fn" in
            ipset_clients.txt|ipset_clients_mode)
                cp -a "$_src" "/opt/zapret2/$_fn" 2>/dev/null || { fail "Geri yukleme basarisiz"; exit 0; }
                ;;
            *)
                cp -a "$_src" "$_dst/$_fn" 2>/dev/null || { fail "Geri yukleme basarisiz"; exit 0; }
                ;;
        esac
        apply_ipset_client_settings >/dev/null 2>&1 || true
        _kzm="/opt/lib/opkg/keenetic_zapret2_manager.sh"
        KZM2_SKIP_LOCK=1 sh "$_kzm" --cgi-action zapret_restart >/dev/null 2>&1 &
        ok "Geri yuklendi: $_fn" ;;
    settings_list)
        _dir="/opt/zapret2_backups/zapret2_settings"
        if ! ls "$_dir"/zapret2_settings_*.tar.gz >/dev/null 2>&1; then
            printf '{"ok":1,"data":[]}'
        else
            _json="$(ls -1t "$_dir"/zapret2_settings_*.tar.gz 2>/dev/null | head -10 | \
                awk 'BEGIN{printf "["} NR>1{printf ","} {f=$0; gsub(/.*\//,"",f); printf "{\"path\":\"%s\",\"name\":\"%s\"}",$0,f} END{print "]"}')"
            printf '{"ok":1,"data":%s}' "$_json"
        fi ;;
    settings_restore)
        _f=$(get_param file); [ -z "$_f" ] && { fail "Dosya belirtilmedi"; exit 0; }
        _scope=$(get_param scope); [ -z "$_scope" ] && _scope="1"
        _dir="/opt/zapret2_backups/zapret2_settings"
        _bn=$(basename "$_f")
        case "$_bn" in zapret2_settings_*.tar.gz) ;; *) fail "Gecersiz KZM2 yedegi"; exit 0 ;; esac
        _f="$_dir/$_bn"
        [ -f "$_f" ] || { fail "Arsiv bulunamadi"; exit 0; }
        _tmp="/tmp/zapret_restore_cgi.$$"
        rm -rf "$_tmp" 2>/dev/null
        mkdir -p "$_tmp" || { fail "Gecici dizin olusturulamadi"; exit 0; }
        tar -xzf "$_f" -C "$_tmp" >/dev/null 2>&1 || { rm -rf "$_tmp"; fail "Arsiv acma basarisiz"; exit 0; }
        _tsrc="$_tmp"
        [ -d "$_tmp/opt" ] || { for _td in "$_tmp"/*; do [ -d "$_td/opt" ] && _tsrc="$_td" && break; done; }
        _cpif() { _sp="$_tsrc/$1"; if [ -d "$_sp" ]; then mkdir -p "/$1" 2>/dev/null; cp -a "$_sp/." "/$1/" 2>/dev/null; elif [ -e "$_sp" ]; then mkdir -p "/$(dirname "$1")" 2>/dev/null; cp -a "$_sp" "/$1" 2>/dev/null; fi; }
        case "$_scope" in
            1) cp -a "$_tsrc/"* / 2>/dev/null ;;
            2) _cpif opt/zapret2/config; _cpif opt/zapret2/lang; _cpif opt/zapret2/wan_if
               _cpif opt/zapret2/dpi_profile; _cpif opt/zapret2/dpi_profile_origin
               _cpif opt/zapret2/dpi_profile_params; _cpif opt/zapret2/blockcheck_auto_params
               _cpif opt/zapret2/dpi_profiles ;;
            3) _cpif opt/zapret2/hostlist_mode; _cpif opt/zapret2/scope_mode; _cpif opt/zapret2/ipset ;;
            4) _cpif opt/zapret2/ipset_clients.txt; _cpif opt/zapret2/ipset_clients_mode; _cpif opt/zapret2/ipset ;;
            5) _cpif opt/zapret2/config ;;
            6) _cpif opt/etc/healthmon.conf; _cpif opt/etc/telegram.conf; _cpif opt/etc/kzm2_gui.conf
               _cpif opt/zapret2/init.d/sysv/zapret2.real
               _cpif opt/zapret2/init.d/sysv/custom.d/90-keenetic-client-ipset
               _cpif opt/etc/init.d/S99kzm2_healthmon ;;
        esac
        rm -rf "$_tmp" 2>/dev/null
        _kzm="/opt/lib/opkg/keenetic_zapret2_manager.sh"
        KZM2_SKIP_LOCK=1 sh "$_kzm" --cgi-action fix_permissions >/dev/null 2>&1
        KZM2_SKIP_LOCK=1 sh "$_kzm" --cgi-action zapret_restart >/dev/null 2>&1 &
        ok "Geri yuklendi (kapsam:$_scope)" ;;
    settings_clean)
        _dir="/opt/zapret2_backups/zapret2_settings"
        if ! ls "$_dir"/zapret2_settings_*.tar.gz >/dev/null 2>&1; then
            ok "Silinecek yedek yok"
        else
            _count=$(ls -1 "$_dir"/zapret2_settings_*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
            rm -f "$_dir"/zapret2_settings_*.tar.gz 2>/dev/null
            ok "Temizlendi: $_count yedek silindi"
        fi ;;
    ipset_history_clean)
        _hist="/opt/zapret2_backups/history"
        if [ ! -d "$_hist" ] || [ -z "$(ls -A "$_hist" 2>/dev/null)" ]; then
            ok "Silinecek gecmis yedek yok"
        else
            _count=$(ls -1 "$_hist" 2>/dev/null | wc -l | tr -d ' ')
            rm -rf "${_hist:?}"/* 2>/dev/null
            ok "Temizlendi: $_count gecmis yedek silindi"
        fi ;;
    component_check)
        _kzm="/opt/lib/opkg/keenetic_zapret2_manager.sh"
        [ -f "$_kzm" ] || { fail "KZM2 bulunamadi"; exit 0; }
        KZM2_SKIP_LOCK=1 sh "$_kzm" --cgi-action component_check 2>/dev/null ;;
    status_refresh)
        refresh; ok "Durum guncellendi" ;;
    opkg_update)
        if opkg update >/dev/null 2>&1; then
            _upgradable="$(opkg list-upgradable 2>/dev/null)"
            _count=0
            [ -n "$_upgradable" ] && _count="$(printf '%s\n' "$_upgradable" | grep -c .)"
            printf '{"ok":1,"count":%s}' "$_count"
        else
            fail "opkg update basarisiz"
        fi ;;
    opkg_upgrade)
        if opkg upgrade >/dev/null 2>&1; then
            ok "opkg upgrade tamamlandi"
        else
            fail "opkg upgrade basarisiz"
        fi ;;
    dns_list)
        _dnsraw="$(LD_LIBRARY_PATH= ndmc -c 'show dns-proxy' 2>/dev/null)"
        _dnsrc="$(LD_LIBRARY_PATH= ndmc -c 'show running-config' 2>/dev/null)"
        _rebind="off"
        if printf '%s' "$_dnsraw" | grep -q "norebind_ctl = on" && ! printf '%s' "$_dnsrc" | grep -q "no rebind-protect"; then
            _rebind="on"
        fi
        _items=""
        _comma=""
        for _dkey in \
            "8.8.8.8@dns.google|DoT|Filtresiz" \
            "8.8.4.4@dns.google|DoT|Filtresiz" \
            "dns.google/dns-query|DoH|Filtresiz" \
            "1.1.1.1@one.one.one.one|DoT|Filtresiz" \
            "1.0.0.1@one.one.one.one|DoT|Filtresiz" \
            "cloudflare-dns.com/dns-query|DoH|Filtresiz" \
            "1.1.1.1/dns-query|DoH|Filtresiz" \
            "1.0.0.1/dns-query|DoH|Filtresiz" \
            "1.1.1.2@security.cloudflare-dns.com|DoT|Aile" \
            "1.0.0.2@security.cloudflare-dns.com|DoT|Aile" \
            "9.9.9.9@dns.quad9.net|DoT|Gizlilik" \
            "149.112.112.112@dns.quad9.net|DoT|Gizlilik" \
            "94.140.14.14@dns.adguard-dns.com|DoT|Reklam" \
            "94.140.15.15@dns.adguard-dns.com|DoT|Reklam" \
            "dns.mullvad.net/dns-query|DoH|Gizlilik" \
            "185.228.168.9@family-filter-dns.cleanbrowsing.org|DoT|Aile" \
            "185.228.169.9@family-filter-dns.cleanbrowsing.org|DoT|Aile"
        do
            _dk="${_dkey%%|*}"
            _rest="${_dkey#*|}"
            _dt="${_rest%%|*}"
            _dgrp="${_rest##*|}"
            _gk="${_dk%%@*}"
            _found=0
            case "$_dt" in
                DoT)
                    printf '%s' "$_dnsraw" | grep -qF "# ${_gk}@" && _found=1
                    ;;
                DoH)
                    printf '%s' "$_dnsraw" | grep -qF "uri: https://${_gk}" && _found=1
                    ;;
            esac
            if [ "$_found" = "1" ]; then
                _items="${_items}${_comma}{\"key\":\"${_dk}\",\"type\":\"${_dt}\",\"group\":\"${_dgrp}\"}"
                _comma=","
            fi
        done
        printf '{"ok":1,"items":[%s],"rebind":"%s"}
' "$_items" "$_rebind" ;;
    dns_add_preset)
        _pkg=$(get_param pkg)
        case "$_pkg" in Google|Cloudflare|CF_Families|Quad9|AdGuard|Mullvad|Dns0eu|CleanBrowsing) ;; *) fail "Gecersiz paket"; exit 0 ;; esac
        _kzm="/opt/lib/opkg/keenetic_zapret2_manager.sh"
        [ -f "$_kzm" ] || { fail "KZM2 bulunamadi"; exit 0; }
        # Zaten mevcut mu inline kontrol et
        _dnsraw_chk="$(LD_LIBRARY_PATH= ndmc -c 'show dns-proxy' 2>/dev/null)"
        _pkg_all_exist=1
        case "$_pkg" in
            Google)        _pkg_keys="8.8.8.8 8.8.4.4 dns.google" ;;
            Cloudflare)    _pkg_keys="1.1.1.1 1.0.0.1 cloudflare-dns.com" ;;
            CF_Families)   _pkg_keys="1.1.1.2 1.0.0.2" ;;
            Quad9)         _pkg_keys="9.9.9.9 149.112.112.112" ;;
            AdGuard)       _pkg_keys="94.140.14.14 94.140.15.15" ;;
            Mullvad)       _pkg_keys="dns.mullvad.net" ;;
            CleanBrowsing) _pkg_keys="185.228.168.9 185.228.169.9" ;;
        esac
        for _pk in $_pkg_keys; do
            printf '%s' "$_dnsraw_chk" | grep -qF "$_pk" || { _pkg_all_exist=0; break; }
        done
        if [ "$_pkg_all_exist" -eq 1 ]; then
            ok "Zaten mevcut: $_pkg"
        else
            KZM2_SKIP_LOCK=1 sh "$_kzm" --cgi-action dns_add_preset "$_pkg" >/dev/null 2>&1 &
            sleep 3; ok "Paket eklendi: $_pkg"
        fi ;;
    dns_del)
        _dkey=$(get_param key)
        [ -z "$_dkey" ] && { fail "Key bos"; exit 0; }
        _kzm="/opt/lib/opkg/keenetic_zapret2_manager.sh"
        [ -f "$_kzm" ] || { fail "KZM2 bulunamadi"; exit 0; }
        KZM2_SKIP_LOCK=1 sh "$_kzm" --cgi-action dns_del "$_dkey" >/dev/null 2>&1
        ok "Silindi: $_dkey" ;;
    dns_rebind_toggle)
        _kzm="/opt/lib/opkg/keenetic_zapret2_manager.sh"
        [ -f "$_kzm" ] || { fail "KZM2 bulunamadi"; exit 0; }
        KZM2_SKIP_LOCK=1 sh "$_kzm" --cgi-action dns_rebind_toggle >/dev/null 2>&1
        ok "Rebind durumu degistirildi" ;;
    lang_set)
        _lang=$(get_param lang)
        case "$_lang" in
            tr|en) printf '%s' "$_lang" > /opt/zapret2/lang 2>/dev/null; refresh; ok "Dil degistirildi: $_lang" ;;
            *) fail "Gecersiz dil" ;;
        esac ;;
    theme_set)
        _theme=$(get_param theme)
        case "$_theme" in
            dark|light) printf '%s' "$_theme" > /opt/zapret2/theme 2>/dev/null; refresh; ok "Tema degistirildi: $_theme" ;;
            *) fail "Gecersiz tema" ;;
        esac ;;
    *)
        fail "Bilinmeyen action: $ACTION" ;;
esac
CGIEOF
    sed -i "s/__KZM_VER__/${SCRIPT_VERSION}/g" "$KZM2_GUI_CGI" 2>/dev/null
    chmod +x "$KZM2_GUI_CGI"
}
# ---------------------------------------------------------------------------
# kzm_gui_write_lighttpd_conf: lighttpd.conf olustur
# ---------------------------------------------------------------------------
kzm_gui_write_lighttpd_conf() {
    mkdir -p /opt/etc/lighttpd /opt/var/run 2>/dev/null
    cat > "$KZM2_GUI_CONF" << CONFEOF
server.document-root = "/opt/www/kzm2"
server.port          = $KZM2_GUI_PORT
server.bind          = "0.0.0.0"
server.pid-file      = "/opt/var/run/lighttpd.pid"
server.modules = (
  "mod_alias",
  "mod_cgi",
  "mod_setenv"
)
index-file.names = ( "index.html" )
mimetype.assign = (
  ".html" => "text/html; charset=utf-8",
  ".js"   => "application/javascript",
  ".json" => "application/json",
  ".css"  => "text/css",
  ".ico"  => "image/x-icon"
)
setenv.add-response-header = (
  "Cache-Control" => "no-cache, no-store, must-revalidate",
  "Pragma"        => "no-cache",
  "Expires"       => "0"
)
alias.url = ( "/run/" => "/opt/var/run/" )
\$HTTP["url"] =~ "^/cgi-bin/" {
  cgi.assign = ( ".sh" => "/bin/sh" )
}
CONFEOF
}
# ---------------------------------------------------------------------------
# kzm_gui_write_html: /opt/www/kzm2/index.html yaz
# NOT: Turkce karakterler HTML entity olarak yazilmistir (self-test uyumu)
# ---------------------------------------------------------------------------
kzm_gui_write_html() {
    mkdir -p "$KZM2_GUI_DIR" 2>/dev/null
    cat > "$KZM2_GUI_HTML" << 'HTMLEOF'
<!doctype html>
<html lang="tr">
<head>
<meta charset="utf-8"/>
<meta name="kzm-version" content="__KZM_VER__"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate"/>
<meta http-equiv="Pragma" content="no-cache"/>
<meta http-equiv="Expires" content="0"/>
 <title>KZM2 Control Panel</title>
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyMDAgMjAwIj48cGF0aCBkPSJNMCAwIEM2NiAwIDEzMiAwIDIwMCAwIEMyMDAgNjYgMjAwIDEzMiAyMDAgMjAwIEMxMzQgMjAwIDY4IDIwMCAwIDIwMCBDMCAxMzQgMCA2OCAwIDAgWiIgZmlsbD0iIzAwOTdEQyIvPjxwYXRoIGQ9Ik0wIDAgQzcuMjYgMCAxNC41MiAwIDIyIDAgQzIyIDEyLjU0IDIyIDI1LjA4IDIyIDM4IEMzOC40NTgzMjk0MSA0MC4zMzc5MjI1OCAzOC40NTgzMjk0MSA0MC4zMzc5MjI1OCA1My4wOTQyMzgyOCAzNC4xMjEwOTM3NSBDNjAuMTkzMzIzMjMgMjguMDg5NTIyMTEgNjYuNDExNDU5OTYgMjEuMTQ3MTU5MjMgNzIuNjA1NDY4NzUgMTQuMjEwOTM3NSBDNzMuNDcyNDc0MDYgMTMuMjQwNjg4ODYgNzMuNDcyNDc0MDYgMTMuMjQwNjg4ODYgNzQuMzU2OTk0NjMgMTIuMjUwODM5MjMgQzc2LjYzMDM4NzgxIDkuNjk2MzUzMiA3OC44ODA0MjE5NiA3LjE0NzEyOTk5IDgxLjAzNzU5NzY2IDQuNDkyOTE5OTIgQzg0LjYwNzg0MDkxIDAuNTkxOTUyMTEgODcuNDk0MjI2MTUgLTAuMzM1MzIyMzkgOTIuODA0MTIyOTIgLTAuNjM3MjA3MDMgQzk2LjU0MzI3MDE1IC0wLjcxNjE5NDUgMTAwLjI2NDA4NTY4IC0wLjU4NDc5MjY5IDEwNCAtMC40Mzc1IEMxMDUuNTUzMzE1MDEgLTAuNDAyMzM3MzMgMTA3LjEwNjcwNjc0IC0wLjM3MDQwNzAzIDEwOC42NjAxNTYyNSAtMC4zNDE3OTY4OCBDMTEyLjQ0MjAxODQgLTAuMjY1MTYzMjcgMTE2LjIyMDE1Mzk5IC0wLjE0NDY2OTQxIDEyMCAwIEMxMTQuNjQyNjgyNjEgNi40OTM2MDIxMSAxMTQuNjQyNjgyNjEgNi40OTM2MDIxMSAxMTEuNjI1IDguOTM3NSBDMTA3LjM1MTUyODQgMTIuNTY5MTM4NDEgMTAzLjQ0MDYxODc0IDE2LjUxNjI5MDU3IDk5LjUgMjAuNSBDOTUuMDA1NzEwNTMgMjUuMDM5MDYxMDIgOTAuNTIyNTQzNSAyOS41MDg3NzQwNCA4NS42MTMyODEyNSAzMy42MDU0Njg3NSBDODMuNjQyMDA3MiAzNS4zMDk0NTE0MSA4MS44MjU4NzA0OSAzNy4xNDIzMDYwNiA4MCAzOSBDODEuMDI3MzgyODEgMzkuMzQwMzEyNSA4Mi4wNTQ3NjU2MyAzOS42ODA2MjUgODMuMTEzMjgxMjUgNDAuMDMxMjUgQzk4LjMzMjQ3ODkgNDUuMjY2OTkyODUgMTA4LjA4MDI2OTAyIDUyLjI1ODAyMDIzIDExNi4zNzg5MDYyNSA2Ni4zMzk4NDM3NSBDMTIwLjg1OTUyMjMgNzUuOTcyMzg3NjYgMTE5LjMxMzUzMjc4IDg3LjY0NDcwOTA4IDExOSA5OCBDMTEyLjA3IDk4IDEwNS4xNCA5OCA5OCA5OCBDOTcuOTM4MTI1IDk1LjIzNjI1IDk3Ljg3NjI1IDkyLjQ3MjUgOTcuODEyNSA4OS42MjUgQzk3LjQ0NDU5NTI1IDgxLjM4MDgyNDU1IDk2LjMxNzU0MTk3IDc0LjczMDQyMTY3IDkwLjU3MDMxMjUgNjguNDMzNTkzNzUgQzc4LjYwODU0MTMgNTguNDY1NDUxMDggNjAuNjQxODYzOTggNjAuMzM3NDcyNzUgNDYuMTg3NSA2MC4yNSBDNDMuODM3ODY5MDEgNjAuMjIxNzk4NTkgNDEuNDg4MjU4MTQgNjAuMTkxODY1NDUgMzkuMTM4NjcxODggNjAuMTYwMTU2MjUgQzMzLjQyNTU4NzkzIDYwLjA4MzU3ODc2IDI3LjcxMzgzODYgNjAuMDQyNTkyOTEgMjIgNjAgQzIyIDcyLjU0IDIyIDg1LjA4IDIyIDk4IEMxNC43NCA5OCA3LjQ4IDk4IDAgOTggQzAgNjUuNjYgMCAzMy4zMiAwIDAgWiIgZmlsbD0iI0ZDRkRGRSIgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoNDIsNTEpIi8+PC9zdmc+"/>
<style>
:root,[data-theme="dark"]{
  --bg:#0b1220;--panel:#0f1b33;--card:#111f3d;--card2:#0b1730;
  --text:#e7eefc;--fg:#e7eefc;--muted:#a9b7d6;--line:rgba(231,238,252,.10);
  --accent:#4b7dff;--good:#2ecc71;--warn:#f1c40f;--bad:#e74c3c;
  --radius:14px;--mono:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;
  --sw:240px;--swc:54px;--str:.22s cubic-bezier(.4,0,.2,1);
}
[data-theme="light"]{
  --bg:#f0f4fa;--panel:#e2e8f5;--card:#ffffff;--card2:#eef3fb;
  --text:#1a2340;--fg:#1a2340;--muted:#5a6a8a;--line:rgba(26,35,64,.10);
  --accent:#1a56db;--good:#16a34a;--warn:#d97706;--bad:#dc2626;
  --radius:14px;--mono:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;
  --sw:240px;--swc:54px;--str:.22s cubic-bezier(.4,0,.2,1);
}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Arial;
  background:var(--bg);
  color:var(--text);min-height:100vh;overflow-x:hidden;}
.app{display:grid;grid-template-columns:var(--sw) 1fr;min-height:100vh;transition:grid-template-columns var(--str);}
.app.sb-off{grid-template-columns:var(--swc) 1fr;}
aside{border-right:1px solid var(--line);
  background:var(--panel);
  padding:12px 8px;position:sticky;top:0;height:100vh;overflow:visible;
  display:flex;flex-direction:column;gap:2px;
  width:var(--sw);transition:width var(--str);position:relative;}
.app.sb-off aside{width:var(--swc);}
.sb-toggle{position:absolute;top:10px;right:-18px;transform:none;width:20px;height:50px;border-radius:0 14px 14px 0;
  background:linear-gradient(180deg,#5d88ff,#3f67e8);border:1px solid rgba(75,125,255,.50);display:flex;align-items:center;justify-content:center;
  cursor:pointer;color:#fff;font-size:22px;font-weight:800;z-index:50;
  transition:background .15s,transform var(--str),box-shadow .15s;line-height:1;user-select:none;
  box-shadow:0 0 14px rgba(75,125,255,.50);padding:0;}
.sb-toggle:hover{background:linear-gradient(180deg,#6b93ff,#4d74ef);box-shadow:0 0 18px rgba(75,125,255,.65);}
.app.sb-off .sb-toggle{transform:rotate(180deg);}
.brand{display:flex;gap:10px;align-items:center;padding:6px 4px 22px;
  border-bottom:1px solid var(--line);margin-bottom:8px;overflow:hidden;}
.logo{width:32px;height:32px;border-radius:9px;flex-shrink:0;
  display:grid;place-items:center;
  cursor:pointer;transition:opacity .15s;overflow:hidden;}
.logo:hover{opacity:.75;}
.brand-text{overflow:hidden;white-space:nowrap;transition:opacity var(--str),max-width var(--str);max-width:180px;}
.app.sb-off aside .brand-text{opacity:0;max-width:0;}
.brand h1{font-size:13px;font-weight:700;white-space:nowrap;}
.brand small{display:block;color:var(--muted);font-size:10px;margin-top:1px;white-space:nowrap;}
nav{display:flex;flex-direction:column;gap:2px;padding:0 2px;}
.sec{color:var(--muted);font-size:10px;letter-spacing:.12em;
  margin:8px 4px 2px;text-transform:uppercase;font-weight:600;
  white-space:nowrap;overflow:hidden;transition:opacity var(--str);}
.app.sb-off aside .sec{opacity:0;}
.item{display:flex;align-items:center;gap:9px;
  padding:8px 9px;border-radius:9px;border:1px solid transparent;cursor:pointer;
  user-select:none;transition:.12s ease;overflow:hidden;white-space:nowrap;position:relative;}
.item:hover{border-color:rgba(75,125,255,.2);background:rgba(75,125,255,.08);}
.item.active{border-color:rgba(75,125,255,.5);background:rgba(75,125,255,.12);}
.item-icon{font-size:15px;flex-shrink:0;width:20px;text-align:center;}
.item-label{font-size:12.5px;flex:1;white-space:nowrap;overflow:hidden;
  transition:opacity var(--str),max-width var(--str);max-width:150px;}
.app.sb-off aside .item-label{opacity:0;max-width:0;}
.pill{font-size:10px;color:var(--muted);padding:1px 6px;border-radius:999px;
  border:1px solid var(--line);white-space:nowrap;flex-shrink:0;
  transition:opacity var(--str);margin-left:auto;}
.app.sb-off aside .pill{opacity:0;width:0;padding:0;border:none;margin:0;}
.tip{display:none;position:fixed;
  background:var(--panel);border:1px solid var(--line);border-radius:7px;
  padding:5px 10px;font-size:12px;white-space:nowrap;color:var(--text);
  pointer-events:none;box-shadow:0 4px 16px rgba(0,0,0,.5);z-index:9999;}
.app.sb-off .item:hover .tip{display:block;}
.fnote{padding:10px 4px 4px;color:var(--muted);font-size:11px;
  border-top:1px solid var(--line);margin-top:auto;
  white-space:nowrap;overflow:hidden;transition:opacity var(--str);}
.app.sb-off aside .fnote{opacity:0;}
main{display:flex;flex-direction:column;min-height:100vh}
header{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:8px;
  padding:14px 22px;border-bottom:1px solid var(--line);
  background:var(--panel);backdrop-filter:blur(12px);
  position:sticky;top:0;z-index:10;}
.title h2{font-size:17px;font-weight:700}
.title small{color:var(--muted);font-size:11px}
.meta{display:flex;flex-wrap:wrap;gap:14px;font-size:12px;color:var(--muted);align-items:center}
.meta b{color:var(--text)}
.good{color:var(--good)!important}.bad{color:var(--bad)!important}.warn{color:var(--warn)!important}
#view{padding:18px 22px;flex:1}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(270px,1fr));gap:14px}
.card{background:var(--card);border:1px solid var(--line);border-radius:var(--radius);
  padding:16px 16px 13px;display:flex;flex-direction:column;gap:10px;}
.card.wide{grid-column:1/-1}
.card h3{font-size:14px;color:var(--muted);font-weight:600;letter-spacing:.04em}
.big{font-size:30px;font-weight:800;letter-spacing:-.02em}
.sub{font-size:14px;color:var(--muted);line-height:1.5}
.row{display:flex;flex-wrap:wrap;gap:7px;align-items:center}
.badge{display:inline-block;font-size:11px;font-weight:700;padding:3px 10px;
  border-radius:999px;letter-spacing:.03em;min-width:110px;text-align:center;box-sizing:border-box;}
.badge.good{background:rgba(46,204,113,.15);color:var(--good);border:1px solid rgba(46,204,113,.3)}
.badge.bad{background:rgba(231,76,60,.15);color:var(--bad);border:1px solid rgba(231,76,60,.3)}
.badge.warn{background:rgba(241,196,15,.12);color:var(--warn);border:1px solid rgba(241,196,15,.25)}
.badge.off{background:rgba(169,183,214,.1);color:var(--muted);border:1px solid var(--line)}
.svc-badges .badge{width:100%;text-align:center;box-sizing:border-box;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.badge.info{background:rgba(52,152,219,.15);color:#3498db;border:1px solid rgba(52,152,219,.3)}
.btns{display:flex;flex-wrap:wrap;gap:7px;margin-top:2px}
.dash-zapret-actions{display:flex;flex-wrap:wrap;gap:7px;margin-top:2px}
.dash-zapret-actions button{width:140px;min-width:140px;text-align:center;justify-content:center;box-sizing:border-box}
.zapret-control-actions{display:flex;flex-wrap:wrap;gap:7px;margin-top:2px}
.zapret-control-actions button{width:140px;min-width:140px;max-width:140px;text-align:center;justify-content:center;box-sizing:border-box;display:inline-flex;align-items:center}
.healthmon-actions{display:flex;flex-wrap:wrap;gap:12px}
.healthmon-actions button{width:140px;min-width:140px;max-width:140px;text-align:center;justify-content:center;box-sizing:border-box;display:inline-flex;align-items:center}
@media (max-width:768px){.healthmon-actions{display:flex;flex-wrap:wrap;gap:12px}.healthmon-actions button{width:calc(50% - 6px);min-width:calc(50% - 6px);max-width:calc(50% - 6px)}}
.bk-actions{display:flex;flex-wrap:wrap;gap:7px;margin-top:2px}
button{font-size:12px;padding:6px 13px;border-radius:7px;border:none;cursor:pointer;
  font-weight:600;transition:.13s;background:var(--accent);color:#fff;}
button:hover{opacity:.85}button:disabled{opacity:.35;cursor:not-allowed}
button.ghost{background:rgba(75,125,255,.13);color:var(--accent);border:1px solid rgba(75,125,255,.3)}
button.ghost:hover{background:rgba(75,125,255,.22)}
button.danger{background:rgba(231,76,60,.18);color:var(--bad);border:1px solid rgba(231,76,60,.35)}
button.danger:hover{background:rgba(231,76,60,.3)}
button.ok{background:rgba(46,204,113,.18);color:var(--good);border:1px solid rgba(46,204,113,.35)}
button.ok:hover{background:rgba(46,204,113,.28)}
.progress{background:rgba(255,255,255,.06);border-radius:999px;height:5px;overflow:hidden}
.bar{height:100%;border-radius:999px;background:var(--accent);transition:.4s}
.bar.good{background:var(--good)}.bar.warn{background:var(--warn)}.bar.bad{background:var(--bad)}
.hint{font-size:11px;color:var(--muted)}
.info-grid{border:1px solid var(--line);border-radius:10px;overflow:hidden;background:rgba(0,0,0,.1)}
.info-sec{padding:6px 11px;font-size:11px;font-weight:700;letter-spacing:.06em;color:var(--muted);background:rgba(255,255,255,.04);border-bottom:1px solid var(--line)}
.info-row{display:grid;grid-template-columns:200px 1fr;border-bottom:1px solid var(--line)}
.info-row:last-child{border-bottom:none}
.info-row .lbl{padding:8px 11px;color:var(--muted);font-size:14px}
.info-row .val{padding:8px 11px;font-size:14px}
.dash-stack{display:flex;flex-direction:column;gap:16px}
.security-note{margin:0 0 12px;padding:10px 14px;border-radius:12px;background:rgba(245,158,11,.12);border:1px solid rgba(245,158,11,.30);color:var(--text);font-size:13px;line-height:1.45}
.security-note b{color:#f59e0b;font-weight:800}
.dash-top-grid{display:grid;grid-template-columns:1fr 1fr 1fr 1fr;gap:16px}
.dash-card-span-2{grid-column:span 2}
.dash-services-grid{display:grid;grid-template-columns:1fr 1fr;gap:6px}
.bk-grid{display:grid;grid-template-columns:1fr 1fr;gap:16px}
.dpi-grid{display:grid;grid-template-columns:1fr 1fr;gap:16px}
.dpi-grid>.card{height:100%;box-sizing:border-box}
.mdpi-adv-grid{align-items:stretch}
.mdpi-adv-grid label{display:flex;flex-direction:column;justify-content:flex-end;min-height:58px;box-sizing:border-box}
.mdpi-adv-grid input{height:34px;min-height:34px;box-sizing:border-box}
.dpi-action-row{display:flex;gap:7px;align-items:center;flex-wrap:wrap}
.dpi-action-row select{flex:1 1 220px;min-width:0;max-width:100%}
.cl-grid{display:grid;grid-template-columns:160px 1fr;gap:14px}
.mob-toggle{display:none;position:fixed;top:14px;left:14px;width:36px;height:36px;border-radius:10px;background:rgba(0,151,220,.18),.18);border:1px solid rgba(75,125,255,.35);color:#fff;cursor:pointer;z-index:90;place-items:center;font-size:18px;transform:translate(-1px,-1px);backdrop-filter:blur(10px)}
.mob-backdrop{display:none;position:fixed;inset:0;background:rgba(4,10,20,.55);z-index:55}
@media (max-width: 900px){
  .app,.app.sb-off{grid-template-columns:1fr}
  main{min-width:0}
  aside{position:fixed;left:0;top:0;bottom:0;width:min(84vw,280px);height:100vh;z-index:120;transform:translateX(-105%);transition:transform var(--str),width var(--str);box-shadow:0 12px 40px rgba(0,0,0,.45)}
  .app.sb-off aside{width:min(84vw,280px)}
  .app.mob-open aside{transform:translateX(0)}
  .sb-toggle{display:none}
  .mob-toggle{display:grid}
  .mob-backdrop{display:block;opacity:0;pointer-events:none;transition:opacity var(--str)}
  .app.mob-open + .mob-backdrop{opacity:1;pointer-events:auto}
  .brand-text,.sec,.item-label,.pill,.fnote{opacity:1;max-width:none;width:auto;padding:initial;border:initial;margin:initial}
  #view{padding:14px}
  header{padding:12px 14px 12px 60px}
  .dash-top-grid{grid-template-columns:1fr 1fr}
}
@media (max-width: 640px){
  header{padding:12px 14px 12px 60px}
  .title h2{font-size:15px}
  .meta{gap:8px;font-size:11px}
  .grid{grid-template-columns:1fr}
  .dash-top-grid{grid-template-columns:1fr}
  .dash-card-span-2{grid-column:auto}
  .dash-services-grid{grid-template-columns:1fr}
  .bk-grid{grid-template-columns:1fr}
  .bk-actions{flex-direction:column}
  .bk-actions button{width:100%}
  .dpi-grid{grid-template-columns:1fr}
  .dpi-action-row{align-items:stretch}
  .dpi-action-row button{width:100%}
  .cl-grid{grid-template-columns:120px 1fr}
  .info-row{grid-template-columns:1fr}
  .info-row .lbl{padding-bottom:4px}
  .info-row .val{padding-top:0}
}
@keyframes hcBar{0%,100%{height:4px}50%{height:36px}}.spinner{display:inline-block;width:11px;height:11px;border:2px solid rgba(255,255,255,.25);
  border-top-color:#fff;border-radius:50%;animation:spin .7s linear infinite;margin-right:5px;vertical-align:middle;}
@keyframes spin{to{transform:rotate(360deg)}}
.toast{position:fixed;bottom:20px;right:20px;z-index:999;padding:11px 16px;
  border-radius:9px;font-size:12.5px;font-weight:600;opacity:0;transition:.3s;pointer-events:none;}
.toast.show{opacity:1}
.toast.ok{background:rgba(46,204,113,.95);color:#fff}
.toast.err{background:rgba(231,76,60,.95);color:#fff}
.rbtn{font-size:11px;padding:4px 9px;background:rgba(75,125,255,.13);
  color:var(--accent);border:1px solid rgba(75,125,255,.28);border-radius:6px;cursor:pointer;}
.ts{font-size:11px;color:var(--muted)}
.irow{display:flex;gap:7px;align-items:center;flex-wrap:wrap}
.hl-ex-row{width:255px;max-width:100%}
@media (max-width:640px){.hl-ex-row{width:100%}.hl-ex-row input{flex:1;min-width:0}}
input[type=text],input[type=number],select,textarea{
  background:var(--card2);border:1px solid var(--line);border-radius:7px;
  color:var(--text);padding:6px 10px;font-size:12.5px;outline:none;transition:.12s;}
input:focus,select:focus,textarea:focus{border-color:rgba(75,125,255,.5)}
select option{background:var(--card)}
.li{display:flex;justify-content:space-between;align-items:center;
  padding:7px 10px;border-bottom:1px solid var(--line);font-size:12.5px;}
.li:last-child{border-bottom:none}
.lw{border:1px solid var(--line);border-radius:9px;overflow:hidden;
  background:rgba(0,0,0,.15);max-height:240px;overflow-y:auto;}
.empty{padding:20px;text-align:center;color:var(--muted);font-size:12px}
.tag{display:inline-block;font-size:10px;padding:2px 7px;border-radius:999px;
  background:rgba(75,125,255,.15);color:var(--accent);border:1px solid rgba(75,125,255,.25);}
</style>
</head>
<body>
<button class="mob-toggle" id="mobToggle" onclick="sbToggle()" aria-label="Menu">&#9776;</button>
<div class="app" id="kzmApp">
<aside>
  <div class="sb-toggle" onclick="sbToggle()" title="Sidebar">&#8249;</div>
  <div class="brand">
    <div class="logo" onclick="sbToggle()"><svg viewBox="0 0 200 200" width="32" height="32" xmlns="http://www.w3.org/2000/svg"><path d="M0 0 C66 0 132 0 200 0 C200 66 200 132 200 200 C134 200 68 200 0 200 C0 134 0 68 0 0 Z" fill="#0097DC"/><path d="M0 0 C7.26 0 14.52 0 22 0 C22 12.54 22 25.08 22 38 C38.45832941 40.33792258 38.45832941 40.33792258 53.09423828 34.12109375 C60.19332323 28.08952211 66.41145996 21.14715923 72.60546875 14.2109375 C73.47247406 13.24068886 73.47247406 13.24068886 74.35699463 12.25083923 C76.63038781 9.6963532 78.88042196 7.14712999 81.03759766 4.49291992 C84.60784091 0.59195211 87.49422615 -0.33532239 92.80412292 -0.63720703 C96.54327015 -0.7161945 100.26408568 -0.58479269 104 -0.4375 C105.55331501 -0.40233733 107.10670674 -0.37040703 108.66015625 -0.34179688 C112.4420184 -0.26516327 116.22015399 -0.14466941 120 0 C114.64268261 6.49360211 114.64268261 6.49360211 111.625 8.9375 C107.3515284 12.56913841 103.44061874 16.51629057 99.5 20.5 C95.00571053 25.03906102 90.5225435 29.50877404 85.61328125 33.60546875 C83.6420072 35.30945141 81.82587049 37.14230606 80 39 C81.02738281 39.3403125 82.05476563 39.680625 83.11328125 40.03125 C98.3324789 45.26699285 108.08026902 52.25802023 116.37890625 66.33984375 C120.8595223 75.97238766 119.31353278 87.64470908 119 98 C112.07 98 105.14 98 98 98 C97.938125 95.23625 97.87625 92.4725 97.8125 89.625 C97.44459525 81.38082455 96.31754197 74.73042167 90.5703125 68.43359375 C78.6085413 58.46545108 60.64186398 60.33747275 46.1875 60.25 C43.83786901 60.22179859 41.48825814 60.19186545 39.13867188 60.16015625 C33.42558793 60.08357876 27.7138386 60.04259291 22 60 C22 72.54 22 85.08 22 98 C14.74 98 7.48 98 0 98 C0 65.66 0 33.32 0 0 Z" fill="#FCFDFE" transform="translate(42,51)"/></svg></div>
    <div class="brand-text"><h1 id="brandTitle">KZM2 Kontrol Paneli</h1><small>Keenetic &bull; Entware &bull; __KZM_PORT__</small></div>
  </div>
  <div class="sec" data-tr="GENEL" data-en="GENERAL">GENEL</div>
  <nav>
    <div class="item active" data-view="dash"><span class="item-icon">&#9783;</span><span class="item-label" data-tr="Dashboard" data-en="Dashboard">Dashboard</span><span class="pill" id="dashLivePill">Canl&#305;</span><span class="tip">Dashboard</span></div>
  </nav>
  <div class="sec" data-tr="ZAPRET2 Y&#214;NET&#304;M&#304;" data-en="ZAPRET2 MANAGEMENT">ZAPRET2 Y&#214;NET&#304;M&#304;</div>
  <nav>
    <div class="item" data-view="zapret"><span class="item-icon">&#8644;</span><span class="item-label" data-tr="Zapret2 Kontrol" data-en="Zapret2 Control">Zapret2 Kontrol</span><span class="pill">3-5</span><span class="tip">Zapret2 Kontrol</span></div>
    <div class="item" data-view="dpi"><span class="item-icon">&#9889;</span><span class="item-label" data-tr="DPI Profili" data-en="DPI Profile">DPI Profili</span><span class="pill">9</span><span class="tip">DPI Profili</span></div>
    <div class="item" data-view="hostlist"><span class="item-icon">&#9776;</span><span class="item-label" data-tr="Hostlist" data-en="Hostlist">Hostlist</span><span class="pill">11</span><span class="tip">Hostlist</span></div>
    <div class="item" data-view="ipset"><span class="item-icon">&#9636;</span><span class="item-label" data-tr="IPSET" data-en="IPSET">IPSET</span><span class="pill">12</span><span class="tip">IPSET</span></div>
  </nav>
  <div class="sec" data-tr="SERV&#304;SLER" data-en="SERVICES">SERV&#304;SLER</div>
  <nav>
    <div class="item" data-view="healthmon"><span class="item-icon">&#9829;</span><span class="item-label" data-tr="Sistem Sa&#287;l&#305;&#287;&#305; ve &#304;zleme" data-en="Health &amp; Monitoring">Sistem Sa&#287;l&#305;&#287;&#305; ve &#304;zleme</span><span class="pill">16</span><span class="tip">Sistem Sa&#287;l&#305;&#287;&#305; ve &#304;zleme</span></div>
    <div class="item" data-view="healthcheck"><span class="item-icon">&#9906;</span><span class="item-label" data-tr="A&#287; Tan&#305;lama" data-en="Network Diagnostics">A&#287; Tan&#305;lama</span><span class="pill">14-1</span><span class="tip">A&#287; Tan&#305;lama</span></div>
    <div class="item" data-view="dns"><span class="item-icon">&#9670;</span><span class="item-label" data-tr="DNS Y&#246;netimi" data-en="DNS Management">DNS Y&#246;netimi</span><span class="pill">14-3</span><span class="tip">DNS Y&#246;netimi</span></div>
    <div class="item" data-view="compcheck"><span class="item-icon">&#9874;</span><span class="item-label" data-tr="Bile&#351;en Kontrol&#252;" data-en="Component Check">Bile&#351;en Kontrolu</span><span class="pill">14-4</span><span class="tip">Bile&#351;en Kontrolu</span></div>
    <div class="item" data-view="telegram"><span class="item-icon">&#9992;</span><span class="item-label" data-tr="Telegram" data-en="Telegram">Telegram</span><span class="pill">15</span><span class="tip">Telegram</span></div>
    <div class="item" data-view="manualdpi"><span class="item-icon">&#128295;</span><span class="item-label" data-tr="Manuel DPI" data-en="Manual DPI">Manuel DPI</span><span class="pill">NFQWS2</span><span class="tip">Manuel DPI</span></div>
 
  </nav>
  <div class="sec" data-tr="D&#304;&#286;ER" data-en="OTHER">D&#304;&#286;ER</div>
  <nav>
    <div class="item" data-view="sched"><span class="item-icon">&#9719;</span><span class="item-label" data-tr="Zamanlanm&#305;&#351; G&#246;revler" data-en="Scheduled Tasks">Zamanlanm&#305;&#351; G&#246;revler</span><span class="pill">R</span><span class="tip">Zamanlanm&#305;&#351; G&#246;revler</span></div>
    <div class="item" data-view="backup"><span class="item-icon">&#128190;</span><span class="item-label" data-tr="Yedekle" data-en="Backup">Yedekle</span><span class="pill">8</span><span class="tip">Yedekle</span></div>
    <div class="item" data-view="changelog"><span class="item-icon">&#128203;</span><span class="item-label" data-tr="KZM2 S&#252;r&#252;m Notlar&#305;" data-en="KZM2 Release Notes">KZM2 S&#252;r&#252;m Notlar&#305;</span><span class="tip">KZM S&#252;r&#252;m Notlar&#305;</span></div>
    <div class="item" data-view="docs"><span class="item-icon">&#128214;</span><span class="item-label" data-tr="Belgeler" data-en="Documentation">Belgeler</span><span class="tip">Belgeler</span></div>
  </nav>
  <div class="fnote">KZM2 Web Panel<br/><small id="atick"><span id="atickLabel">Otomatik yenileme</span>: 15s</small></div>
</aside>
<main>
  <header>
    <div class="title"><h2 id="pTitle">Dashboard</h2><small id="pSub">Canl&#305; sistem &#246;zeti.</small></div>
    <div class="meta">
      <span id="langBadge" style="display:inline-flex;align-items:center;gap:4px;white-space:nowrap;flex-shrink:0;opacity:.85;cursor:pointer;" title="SSH: kzm → L"></span>
      <span id="themeBadge" style="display:inline-flex;align-items:center;gap:4px;white-space:nowrap;flex-shrink:0;opacity:.85;cursor:pointer;" title="Tema"></span>
      <span>WAN: <b id="hWan">&#8212;</b></span>
      <span><span id="hLoadLabel">CPU Y&#252;k&#252;: </span><b id="hLoad">&#8212;</b></span>
      <span>KZM2: <b id="hVer">&#8212;</b></span>
      <span>Zapret2: <b id="hZap">&#8212;</b></span>
      <span>HealthMon: <b id="hHm">&#8212;</b></span>
      <button class="rbtn" onclick="act('status_refresh',null,'');setTimeout(fetchS,800);">&#8635; <span id="refreshBtnLabel">Yenile</span></button>
      <span class="ts" id="tsLbl"></span>
    </div>
  </header>

  <div id="view"><div style="padding:40px;color:var(--muted);text-align:center">Y&#252;kleniyor...</div></div>
</main>
</div>
<div class="mob-backdrop" id="mobBackdrop" onclick="closeMobMenu()"></div>
<div class="toast" id="toast"></div>
<script>
var S=null,curV='dash',aTimer=null;
function isMob(){return window.matchMedia('(max-width: 900px)').matches;}
function closeMobMenu(){
  var a=document.getElementById('kzmApp');
  a.classList.remove('mob-open');
}
function sbToggle(){
  var a=document.getElementById('kzmApp');
  if(isMob()){
    a.classList.toggle('mob-open');
    return;
  }
  var collapsed=a.classList.toggle('sb-off');
  try{localStorage.setItem('kzm_sb',collapsed?'0':'1');}catch(e){}
}
(function(){
  try{if(localStorage.getItem('kzm_sb')==='0' && !isMob())document.getElementById('kzmApp').classList.add('sb-off');}catch(e){}
})();
window.addEventListener('resize',function(){if(!isMob())closeMobMenu();});
document.addEventListener('mouseover',function(e){
  var item=e.target.closest('.item');
  if(!item)return;
  var app=document.getElementById('kzmApp');
  if(!app.classList.contains('sb-off'))return;
  var tip=item.querySelector('.tip');
  if(!tip)return;
  var r=item.getBoundingClientRect();
  tip.style.top=(r.top+r.height/2-14)+'px';
  tip.style.left=(r.right+6)+'px';
});
function toast(msg,ok){
  var t=document.getElementById('toast');
  t.innerHTML=msg;t.className='toast '+(ok?'ok':'err')+' show';
  clearTimeout(t._t);t._t=setTimeout(function(){t.className='toast';},3000);
}
function fetchS(){
  return fetch('/run/kzm_status.json?t='+Date.now())
    .then(function(r){return r.json();})
    .then(function(d){
      S=d;syncLang();syncTheme();updHdr();if(curV==='dash'||curV==='healthmon'||curV==='telegram'||curV==='zapret'||curV==='dpi')render(curV);
      var dt=new Date(d.ts*1000);
      document.getElementById('tsLbl').textContent=dt.toLocaleTimeString('tr-TR');
    })
    .catch(function(){
      if(!S)document.getElementById('view').innerHTML=
        '<div style="padding:40px;color:var(--bad);text-align:center">Status JSON okunamad&#305;. kzm2_status_gen.sh &#231;al&#305;&#351;&#305;yor mu?</div>';
    });
}
function startAuto(){clearInterval(aTimer);aTimer=setInterval(fetchS,15000);}
function quickPoll(times,interval){
  var n=0;
  var t=setInterval(function(){
    fetchS();n++;
    if(n>=times){clearInterval(t);startAuto();}
  },interval);
}
function act(action,btn,msg){
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',
    headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:'action='+action})
  .then(function(r){return r.json();})
  .then(function(res){
    toast(res.msg||msg,!!res.ok);
    if(btn){btn.disabled=false;btn.innerHTML=btn._o;}
    clearInterval(aTimer);
    // status_refresh action JSON dosyas&#305;n&#305; g&#252;nceller, bittikten sonra fetchS
    fetch('/cgi-bin/action.sh',{method:'POST',
      headers:{'Content-Type':'application/x-www-form-urlencoded'},
      body:'action=status_refresh'})
    .then(function(){return fetchS();})
    .then(function(){render(curV);quickPoll(5,2000);})
    .catch(function(){fetchS();quickPoll(5,2000);});
  })
  .catch(function(){toast('Ba&#287;lant&#305; hatas&#305;',false);if(btn){btn.disabled=false;btn.innerHTML=btn._o;}});
}
function actD(action,data,btn,msg){
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',
    headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:'action='+action+'&'+data})
  .then(function(r){return r.json();})
  .then(function(res){
    toast(res.msg||msg,!!res.ok);
    setTimeout(function(){if(btn){btn.disabled=false;btn.innerHTML=btn._o;}fetchS().then(function(){if(curV!=='manualdpi')render(curV);});},1500);
  })
  .catch(function(){toast('Ba&#287;lant&#305; hatas&#305;',false);if(btn){btn.disabled=false;btn.innerHTML=btn._o;}});
}
function getD(action,cb){
  fetch('/cgi-bin/action.sh',{method:'POST',
    headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:'action='+action})
  .then(function(r){return r.json();}).then(cb)
  .catch(function(e){cb({ok:0,msg:''+e});});
}
function updHdr(){
  if(!S)return;
  document.getElementById('hWan').textContent=S.wan_ip||'—';
  document.getElementById('hLoad').textContent=S.load1||'—';
  document.getElementById('hVer').textContent=S.kzm_version||'—';
  var z=document.getElementById('hZap');
  z.innerHTML=S.zapret_running?'<span class="good">'+(L?'ACTIVE':'AKT&#304;F')+'</span>':'<span class="bad">'+(L?'INACTIVE':'PAS&#304;F')+'</span>';
  var h=document.getElementById('hHm');
  if(h) h.innerHTML=S.healthmon_running?'<span class="good">'+(L?'ACTIVE':'AKT&#304;F')+'</span>':'<span class="bad">'+(L?'INACTIVE':'PAS&#304;F')+'</span>';
}
function bdg(on,a,b){return on?'<span class="badge good">'+(a||'AKT&#304;F')+'</span>':'<span class="badge bad">'+(b||'PAS&#304;F')+'</span>';}
function bdgO(on,a,b){return on?'<span class="badge good">'+(a||'AKT&#304;F')+'</span>':'<span class="badge off">'+(b||'KAPALI')+'</span>';}
function brr(p){var c=p>85?'bad':p>60?'warn':'good';return '<div class="progress"><div class="bar '+c+'" style="width:'+p+'%"></div></div>';}
function pct(u,t){return t?Math.round(u/t*100):0;}
function ir(l,v){return '<div class="info-row"><div class="lbl">'+l+'</div><div class="val">'+v+'</div></div>';}
function nd(){return '<div class="empty">Y&#252;kleniyor...</div>';}
function fmtKeenDns(a){var d=L?'Direct':'Do&#287;rudan';var c=L?'Cloud':'Cloud';var u=L?'Unknown':'Bilinmiyor';var m={'direct':'<span style="color:var(--good)">&#9679; '+d+'</span>','cloud':'<span style="color:var(--warn)">&#9679; '+c+'</span>'};return m[a]||'<span style="color:var(--bad)">&#9679; '+u+'</span>';}
var opkgState={status:null,count:0,upgraded:false};
var hmConfCache=null;
var dnsCache=null;
function fmtOpkgCard(){
  var statusHtml=L?'Press the button to refresh the package list.':'Paket listesini yenilemek i&#231;in butona bas&#305;n.';
  var upgradeShow='none';
  if(opkgState.status==='ok_current'){
    statusHtml='<span style="color:var(--good)">&#10003; '+(L?'List refreshed. All packages up to date.':'Liste yenilendi. T&#252;m paketler g&#252;ncel.')+'</span>';
  } else if(opkgState.status==='ok_upgradable'){
    statusHtml='<span style="color:var(--warn)">&#9888; '+(L?'List refreshed. <b>'+opkgState.count+'</b> package(s) waiting for upgrade.':'Liste yenilendi. <b>'+opkgState.count+'</b> paket y&#252;kseltilmeyi bekliyor.')+'</span>';
    upgradeShow='';
  } else if(opkgState.status==='upgraded'){
    statusHtml='<span style="color:var(--good)">&#10003; '+(L?'opkg upgrade completed.':'opkg upgrade tamamlandi.')+'</span>';
  } else if(opkgState.status==='err'){
    statusHtml='<span style="color:var(--bad)">&#10007; '+(L?'Error occurred.':'Hata olustu.')+'</span>';
  }
  return '<div class="card" id="opkgCard" style="grid-column:span 2">'+
    '<h3>'+(L?'OPKG Packages':'OPKG Paketleri')+'</h3>'+
    '<div id="opkgStatus" style="font-size:12.5px;color:var(--muted);margin:8px 0 10px">'+statusHtml+'</div>'+
    '<div class="btns">'+
      '<button id="opkgUpdateBtn" onclick="opkgUpdate(this)">&#8635; '+(L?'Refresh List':'Listeyi Yenile')+'</button>'+
      '<button id="opkgUpgradeBtn" class="danger" style="display:'+upgradeShow+'" onclick="opkgUpgrade(this)">&#8679; '+(L?'Upgrade':'Y&#252;kselt')+'</button>'+
    '</div>'+
    '<div id="opkgWarn" style="display:none;margin-top:10px;padding:8px 10px;background:rgba(231,76,60,.12);border:1px solid rgba(231,76,60,.3);border-radius:7px;font-size:11.5px;color:var(--bad)">'+
      '&#9888; '+(L?'opkg upgrade may break the system on Keenetic.<br>Are you sure you want to continue?':'opkg upgrade Keenetic\'te sistem bozulmasina yol acabilir.<br>Devam etmek istediginizden emin misiniz?')+'<br>'+
      '<div class="btns" style="margin-top:8px">'+
        '<button class="danger" onclick="opkgUpgradeConfirm(this)">'+(L?'Yes, Upgrade':'Evet, Y&#252;kselt')+'</button>'+
        '<button class="ghost" onclick="document.getElementById(\'opkgWarn\').style.display=\'none\'">'+(L?'Cancel':'Iptal')+'</button>'+
      '</div>'+
    '</div>'+
  '</div>';
}
function dnsRender(r){
  var el=document.getElementById('dnsListArea');
  var rb=document.getElementById('dnsRebindStatus');
  if(!el)return;
  if(!r||!r.ok){el.innerHTML='<span class="sub">Hata</span>';return;}
  if(r.items&&r.items.length>0){
    var grpColor={'Filtresiz':'good','Gizlilik':'info','Reklam':'warn','Aile':'off'};
    var grpLabel={'Filtresiz':L?'Unfiltered':'Filtresiz','Gizlilik':L?'Privacy':'Gizlilik','Reklam':L?'Ad Block':'Reklam','Aile':L?'Family':'Aile'};
    var groups={};
    var rows='<table style="width:100%;border-collapse:collapse;font-size:12.5px;table-layout:fixed">';
    for(var i=0;i<r.items.length;i++){
      var itm=r.items[i];
      var bg=i%2===0?'':'background:rgba(255,255,255,0.03);';
      var grpCls=grpColor[itm.group]||'off';
      groups[itm.group]=1;
      rows+='<tr style="'+bg+'border-bottom:1px solid rgba(255,255,255,0.05)">'+
        '<td style="padding:5px 0;width:46px"><span class="badge '+(itm.type==='DoT'?'good':'info')+'" style="min-width:0;width:40px;text-align:center">'+itm.type+'</span></td>'+
        '<td style="padding:5px 6px;font-family:monospace;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">'+itm.key+'</td>'+
        '<td style="padding:5px 4px;width:64px"><span class="badge '+grpCls+'" style="min-width:0;width:58px;font-size:10px;text-align:center;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">'+(grpLabel[itm.group]||itm.group)+'</span></td>'+
        '<td style="padding:5px 0;text-align:right;width:44px"><button class="danger" style="padding:2px 6px;font-size:11px" onclick="dnsDel(this.getAttribute(\'data-key\'),this)" data-key="'+itm.key+'">'+(L?'Del':'Sil')+'</button></td>'+
      '</tr>';
    }
    rows+='</table>';
    var grpKeys=Object.keys(groups);
    if(grpKeys.length>1){
      rows+='<div style="margin-top:8px;background:rgba(217,119,6,.10);border:1px solid var(--warn);border-radius:8px;padding:12px 16px;display:flex;align-items:center;gap:10px">'+
        '<span style="font-size:1.3em">&#9888;</span>'+
        '<span style="color:var(--warn);font-size:14px;font-weight:500">'+
          (L?'Multiple filter groups active! DNS conflicts may occur.':'Farkl&#305; filtre gruplar&#305; aktif! DNS kar&#305;&#351;&#305;kl&#305;&#287;&#305; ya&#351;anabilir.')+
        '</span></div>';
    }
    el.innerHTML=rows;
  } else {
    el.innerHTML='<div class="sub">'+(L?'No secure DNS servers configured.':'Guvenli DNS sunucusu yapilandirilmamis.')+'</div>';
  }
  if(rb){
    var on=r.rebind==='on';
    rb.innerHTML='<span class="badge '+(on?'good':'warn')+'">'+(on?(L?'ON':'ACIK'):(L?'OFF':'KAPALI'))+'</span>';
  }
}
function dnsLoad(){
  if(!document.getElementById('dnsListArea'))return;
  if(dnsCache){dnsRender(dnsCache);return;}
  getD('dns_list',function(r){dnsCache=r;dnsRender(r);});
}
function dnsRefresh(){dnsCache=null;setTimeout(dnsLoad,3500);}
function dnsPresetHtml(){
  var rows=[
    ['Standard','Standard (No Filter)','Standart (Filtresiz)','Google + Cloudflare DoT/DoH'],
    ['AdGuard','Ad Blocker','Reklam Engelleyici','AdGuard DoT'],
    ['Family','Family Filter','Aile Filtresi','CF Families + CleanBrowsing DoT']
  ];
  var h='<div style="margin-top:8px;display:flex;flex-direction:column;gap:8px">';
  rows.forEach(function(r){
    h+='<div style="display:flex;align-items:center;gap:12px">'+
       '<button onclick="dnsAddPreset(\''+r[0]+'\',this)" style="min-width:210px;text-align:left">'+(L?r[1]:r[2])+'</button>'+
       '<span style="font-size:13px;color:var(--muted)">'+r[3]+'</span></div>';
  });
  return h+'</div>';
}
function dnsAddPreset(pkg,btn){
  var profiles={
    'Standard':['Google','Cloudflare'],
    'Privacy':['Quad9','Mullvad','Dns0eu'],
    'AdGuard':['AdGuard'],
    'Family':['CF_Families','CleanBrowsing']
  };
  var pkgs=profiles[pkg]||[pkg];
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  var chain=Promise.resolve();
  pkgs.forEach(function(p){
    chain=chain.then(function(){
      return fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
        body:'action=dns_add_preset&pkg='+p}).then(function(r){return r.json();});
    });
  });
  chain
  .then(function(res){
    toast((res&&res.msg)?fixTR(res.msg):(L?'Done':'Tamam'),!!(res&&res.ok!==0));
    if(btn){btn.disabled=false;btn.innerHTML=btn._o;}
    dnsCache=null;dnsLoad();
  }).catch(function(){if(btn){btn.disabled=false;btn.innerHTML=btn._o;}});
}
function dnsDel(key,btn){
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:'action=dns_del&key='+encodeURIComponent(key)})
  .then(function(r){return r.json();})
  .then(function(res){
    toast(res.msg||(L?'Deleted':'Silindi'),!!res.ok);
    if(btn){btn.disabled=false;btn.innerHTML=btn._o;}
    dnsCache=null;setTimeout(dnsLoad,2500);
  }).catch(function(){if(btn){btn.disabled=false;btn.innerHTML=btn._o;}});
}
function dnsRebindToggle(btn){
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:'action=dns_rebind_toggle'})
  .then(function(r){return r.json();})
  .then(function(res){
    toast(res.msg||(L?'Done':'Tamam'),!!res.ok);
    if(btn){btn.disabled=false;btn.innerHTML=btn._o;}
    dnsCache=null;setTimeout(dnsLoad,2500);
  }).catch(function(){if(btn){btn.disabled=false;btn.innerHTML=btn._o;}});
}
function opkgUpdate(btn){
  btn.disabled=true;btn.innerHTML='<span class="spinner"></span> '+(L?'Refreshing...':'Yenileniyor...');
  document.getElementById('opkgStatus').innerHTML='<span class="spinner"></span> '+(L?'Running opkg update...':'opkg update &#231;al&#305;&#351;t&#305;r&#305;l&#305;yor...');
  document.getElementById('opkgUpgradeBtn').style.display='none';
  document.getElementById('opkgWarn').style.display='none';
  fetch('/cgi-bin/action.sh',{method:'POST',
    headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:'action=opkg_update'})
  .then(function(r){return r.json();})
  .then(function(d){
    btn.disabled=false;btn.innerHTML='&#8635; '+(L?'Refresh List':'Listeyi Yenile');
    if(d.ok){
      var cnt=parseInt(d.count)||0;
      if(cnt===0){
        opkgState={status:'ok_current',count:0,upgraded:false};
        document.getElementById('opkgStatus').innerHTML=
          '<span style="color:var(--good)">&#10003; '+(L?'List refreshed. All packages up to date.':'Liste yenilendi. T&#252;m paketler g&#252;ncel.')+'</span>';
      } else {
        opkgState={status:'ok_upgradable',count:cnt,upgraded:false};
        document.getElementById('opkgStatus').innerHTML=
          '<span style="color:var(--warn)">&#9888; '+(L?'List refreshed. <b>'+cnt+'</b> package(s) waiting for upgrade.':'Liste yenilendi. <b>'+cnt+'</b> paket y&#252;kseltilmeyi bekliyor.')+'</span>';
        document.getElementById('opkgUpgradeBtn').style.display='';
      }
    } else {
      opkgState={status:'err',count:0,upgraded:false};
      document.getElementById('opkgStatus').innerHTML=
        '<span style="color:var(--bad)">&#10007; '+(d.msg||'Hata')+'</span>';
    }
  })
  .catch(function(){
    btn.disabled=false;btn.innerHTML='&#8635; '+(L?'Refresh List':'Listeyi Yenile');
    opkgState={status:'err',count:0,upgraded:false};
    document.getElementById('opkgStatus').innerHTML='<span style="color:var(--bad)">&#10007; '+(L?'Connection error':'Ba&#287;lant&#305; hatas&#305;')+'</span>';
  });
}
function opkgUpgrade(btn){
  btn.style.display='none';
  document.getElementById('opkgWarn').style.display='';
}
function opkgUpgradeConfirm(btn){
  btn.disabled=true;btn.innerHTML='<span class="spinner"></span> Y&#252;kseltiliyor...';
  document.getElementById('opkgStatus').innerHTML='<span class="spinner"></span> opkg upgrade &#231;al&#305;&#351;t&#305;r&#305;l&#305;yor, l&#252;tfen bekleyin...';
  fetch('/cgi-bin/action.sh',{method:'POST',
    headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:'action=opkg_upgrade'})
  .then(function(r){return r.json();})
  .then(function(d){
    document.getElementById('opkgWarn').style.display='none';
    if(d.ok){
      opkgState={status:'upgraded',count:0,upgraded:true};
      document.getElementById('opkgStatus').innerHTML=
        '<span style="color:var(--good)">&#10003; opkg upgrade tamamlandi.</span>';
      document.getElementById('opkgUpgradeBtn').style.display='none';
    } else {
      opkgState={status:'err',count:0,upgraded:false};
      document.getElementById('opkgStatus').innerHTML=
        '<span style="color:var(--bad)">&#10007; '+(d.msg||'Hata')+'</span>';
    }
  })
  .catch(function(){
    document.getElementById('opkgWarn').style.display='none';
    opkgState={status:'err',count:0,upgraded:false};
    document.getElementById('opkgStatus').innerHTML='<span style="color:var(--bad)">&#10007; Ba&#287;lant&#305; hatas&#305;</span>';
  });
}
function fmtBcCard(S){
  var profileNames={
    'tt_default':(L?'Default Zapret2 (TTL2 fake)':'Varsay&#305;lan Zapret2 (TTL2 fake)'),
    'tt_fiber':(L?'Turk Telekom Fiber (TTL2 fake)':'Turk Telekom Fiber (TTL2 fake)'),
    'superonline_fiber':(L?'Superonline Fiber (TTL6 hostcase)':'Superonline Fiber (TTL6 hostcase)'),
    'blockcheck_auto':(L?'Blockcheck Auto':'Blockcheck Otomatik (Auto)'),
    'custom':(L?'Custom NFQWS2_OPT':'&#214;zel NFQWS2_OPT'),
    'none':(L?'Passthrough (No Bypass)':'Ge&#231;i&#351; Modu (Bypass Yok)')
  };
  var profLabel=profileNames[S.dpi_profile]||S.dpi_profile||'—';
  if(!S.bc_ts){
    return '<div class="card dash-card-span-2"><h3>'+(L?'DPI Health Score':'DPI Sa&#287;l&#305;k Skoru')+'</h3>'+
      '<div style="color:var(--muted);font-size:13px;margin:10px 0 6px">'+(L?'Blockcheck has not been run yet.':'Blockcheck hen&#252;z &#231;al&#305;&#351;t&#305;r&#305;lmad&#305;.')+'</div>'+
      '<div style="font-size:12px;color:var(--muted)">'+(L?'Active Profile: ':'Aktif Profil: ')+'<span style="color:var(--text)">'+profLabel+'</span></div>'+
      '<div style="margin-top:10px;font-size:11.5px;color:var(--muted)">'+(L?'Run SSH &rarr; Menu <b>B</b> (Blockcheck) to see score.':'Score g&#246;rmek i&#231;in SSH ile ba&#287;lan&#305;p<br><span style="color:var(--accent);font-family:monospace">kzm2</span> &rarr; Men&#252; <b>B</b> (Blockcheck) &#231;al&#305;&#351;t&#305;r&#305;n.')+'</div>'+
    '</div>';
  }
  var sc=S.bc_score||0;
  var clr=sc>=9?'var(--good)':sc>=7?'#4b9fff':sc>=5?'var(--warn)':'var(--bad)';
  var rat=sc>=9.5?(L?'Excellent':'M&#252;kemmel'):sc>=8.5?(L?'Very Good':'&#199;ok &#304;yi'):sc>=7?(L?'Good':'&#304;yi'):sc>=5?(L?'Fair':'Orta'):(L?'Poor':'K&#246;t&#252;');
  var pct=Math.round(sc*10);
  var dt=new Date(S.bc_ts*1000);
  var dtStr=dt.toLocaleDateString('tr-TR')+' '+dt.toLocaleTimeString('tr-TR',{hour:'2-digit',minute:'2-digit'});
  var warns='';
  if(Number(S.bc_dns_ok)===0) warns+='<span class="badge bad" style="font-size:10px">DNS: WARN</span> ';
  else if(Number(S.bc_dns_ok)===2) warns+='<span class="badge off" style="font-size:10px;background:rgba(100,120,160,0.15);color:#94a3b8;border:1px solid rgba(100,120,160,0.3)">DNS: ISP</span> ';
  if(Number(S.bc_tls12_ok)===1) warns+='<span class="badge good" style="font-size:10px">TLS: OK</span> ';
  else if(Number(S.bc_tls12_ok)===0) warns+='<span class="badge bad" style="font-size:10px">TLS: WARN</span> ';
  if(Number(S.bc_udp_weak)===0) warns+='<span class="badge good" style="font-size:10px">UDP 443: OK</span> ';
  else if(Number(S.bc_udp_weak)===1) warns+='<span class="badge warn" style="font-size:10px">UDP 443: WARN</span> ';
  if(S.bc_tests_total>0) warns+='<span class="badge off" style="font-size:10px">'+S.bc_tests_ok+'/'+S.bc_tests_total+' test</span>';
  return '<div class="card dash-card-span-2"><h3>'+(L?'DPI Health Score':'DPI Sa&#287;l&#305;k Skoru')+'</h3>'+
    '<div style="display:flex;align-items:flex-end;gap:8px;margin:8px 0 4px">'+
      '<span style="font-size:2.4em;font-weight:800;color:'+clr+'">'+sc+'</span>'+
      '<span style="color:var(--muted);font-size:13px;padding-bottom:6px">/ 10 ('+rat+')</span>'+
      (warns?'<span style="margin-left:auto">'+warns+'</span>':'')+
    '</div>'+
    '<div style="background:rgba(255,255,255,.07);border-radius:6px;height:8px;overflow:hidden;margin-bottom:8px">'+
      '<div style="height:100%;width:'+pct+'%;background:linear-gradient(90deg,'+clr+',#4b7dff);border-radius:6px"></div>'+
    '</div>'+
    '<div style="font-size:12px;color:var(--muted);margin-bottom:4px">'+(L?'Active Profile: ':'Aktif Profil: ')+'<span style="color:var(--text)">'+profLabel+'</span></div>'+
    '<div style="color:var(--muted);font-size:11px">'+(L?'Last blockcheck: ':'Son blockcheck: ')+dtStr+'</div>'+
  '</div>';
}
var V={
  dash:{title:'Dashboard',titleEn:'Dashboard',sub:'Canl&#305; sistem &#246;zeti.',subEn:'Live system overview.',html:function(){
    if(!S)return nd();
    var rp=pct(S.ram_used_mb,S.ram_total_mb);
    return '<div class="dash-stack">'+
      '<div class="dash-top-grid">'+
        '<div class="card"><h3>'+(L?'KZM2 Version':'KZM2 S&#252;r&#252;m')+'</h3><div class="big" style="color:'+(S.sha_kzm==='ok'?'var(--good)':S.sha_kzm==='fail'?'var(--warn)':'var(--text)')+'">'+  (S.kzm_version||'—')+'</div></div>'+
        '<div class="card"><h3>'+(L?'Zapret2 Version':'Zapret2 S&#252;r&#252;m')+'</h3><div class="big" style="color:'+(S.sha_zapret==='ok'?'var(--good)':S.sha_zapret==='fail'?'var(--warn)':'var(--text)')+'">'+fixTR(S.zapret_version||'—')+'</div></div>'+
        '<div class="card dash-card-span-2"><h3>'+(L?'Zapret2 Status':'Zapret2 Durumu')+'</h3>'+
          '<div class="row">'+bdg(S.zapret_running,L?'ACTIVE':'AKT&#304;F',L?'INACTIVE':'PAS&#304;F')+
            ' <span class="pill">'+(L?S.wan_dev:fixTR(S.wan_dev||'—'))+'</span>'+
            ' <span class="pill">'+(S.wan_ip||'—')+'</span></div>'+
          '<div class="dash-zapret-actions">'+
            '<button class="danger" onclick="zapretAct(\'zapret_restart\',this,\'Restart OK\')">&#8635; '+(L?'Restart':'Yeniden Ba&#351;lat')+'</button>'+
            '<button class="ghost" onclick="zapretAct(\'zapret_stop\',this,\'Stop OK\')">&#9646;&#9646; '+(L?'Stop':'Durdur')+'</button>'+
            '<button class="ok" onclick="zapretAct(\'zapret_start\',this,\'Start OK\')">&#9654; '+(L?'Start':'Ba&#351;lat')+'</button>'+
          '</div></div>'+
        '<div class="card dash-card-span-2"><h3>CPU / RAM / Disk</h3>'+
        '<table style="width:100%;border-collapse:collapse;font-size:12.5px;margin-top:6px">'+
          '<tr><td style="color:var(--muted);padding:3px 0;width:38%">'+(L?'CPU Load (1/5/15min)':'CPU Y&#252;k&#252; (1/5/15dk)')+'</td>'+
              '<td style="padding:3px 0"><b>'+S.load1+'</b> / '+S.load5+' / '+S.load15+'</td>'+
              (S.cpu_temp>0?'<td style="padding:3px 0;text-align:right;color:var(--muted)">'+(L?'SoC Temp':'SoC S&#305;cakl&#305;k')+': <b>'+S.cpu_temp+'&#176;C</b></td>':'<td></td>')+
          '</tr>'+
          '<tr><td style="color:var(--muted);padding:3px 0">RAM</td>'+
              '<td colspan="2" style="padding:3px 0">'+
                '<b>'+S.ram_used_mb+'</b> / '+S.ram_total_mb+' MB &nbsp;'+
                '<span style="color:var(--muted);font-size:11px">'+(L?'Free':'Bo&#351;')+': '+S.ram_free_mb+' MB &nbsp; Buf/Cache: '+(S.ram_buffer_mb||0)+' MB &nbsp; Swap: '+(S.swap_used_mb||0)+'/'+(S.swap_total_mb||0)+' MB</span>'+
              '</td>'+
          '</tr>'+
          '<tr><td colspan="3" style="padding:4px 0 2px">'+brr(rp)+'</td></tr>'+
          '<tr><td style="color:var(--muted);padding:3px 0">Disk /opt</td>'+
              '<td style="padding:3px 0"><b>'+(S.disk_used_pct>0?S.disk_used_pct+'%':'&lt;1%')+'</b> &nbsp;<span style="color:var(--muted);font-size:11px">'+(S.disk_used_mb||0)+' / '+Math.round((S.disk_total_mb||0)/1024)+' GB</span></td>'+
              '<td style="padding:3px 0;text-align:right;color:var(--muted);font-size:11px">/tmp: '+(S.disk_tmp_pct>0?S.disk_tmp_pct+'%':'0%')+' ('+(S.disk_tmp_used_mb||0)+'/'+(S.disk_tmp_total_mb||0)+' MB)</td>'+
          '</tr>'+
        '</table>'+
      '</div>'+
      '<div class="card dash-card-span-2"><h3>'+(L?'Services':'Servisler')+'</h3>'+
        '<div class="svc-badges dash-services-grid">'+
          '<div style="min-width:0">'+bdg(S.healthmon_running,L?'Health Mon.':'Sa&#287;l&#305;k Mon.',L?'Health Mon.':'Sa&#287;l&#305;k Mon.')+'</div>'+
          '<div style="min-width:0">'+bdgO(S.telegram_enabled&&S.telegram_running,'Telegram','Telegram')+'</div>'+
          '<div style="min-width:0">'+bdg(S.zapret_running,'Zapret2','Zapret2')+'</div>'+
          '<div style="min-width:0">'+bdg(S.lighttpd_running,'Web Panel','Web Panel')+'</div>'+
        '</div>'+
      '</div>'+
      fmtBcCard(S)+
      fmtOpkgCard()+
      '</div>'+
      '<div class="card wide"><h3>'+(L?'System Info':'Sistem Bilgisi')+'</h3><div class="info-grid">'+
        ir('Model',S.model||'—')+ir('Firmware',(L?fixTR(S.firmware||'—').replace('Kararl\u0131','Stable').replace('Kararl&#305;','Stable').replace('Kararli','Stable').replace('Ar\u015fiv','Archive').replace('Arsiv','Archive').replace('\u00d6nizleme','Preview').replace('&#214;nizleme','Preview').replace('Onizleme','Preview').replace('Geli\u015ftirici','Developer').replace('Geli&#351;tirici','Developer').replace('Gelistirici','Developer'):fixTR(S.firmware||'—')))+
        ir('WAN',(L?S.wan_dev:fixTR(S.wan_dev||'—'))+' | '+(S.wan_ip||'—'))+
        ir('LAN IP',(S.lan_ip||'—'))+
        (S.keendns_fqdn ? ir('KeenDNS',S.keendns_fqdn+' | '+fmtKeenDns(S.keendns_access)) : '')+
        (S.iss_name ? ir(L?'ISP':'ISS',S.iss_name) : '')+
        ir('ISP DNS',S.isp_dns ? '<span style="color:var(--warn)">'+S.isp_dns+' — '+(L?'Zapret2 bypass may be blocked!':'Zapret2 bypass engellenebilir!')+'</span>' : '<span style="color:var(--good)">'+(L?'None - DNS encryption active':'Yok - DNS &#351;ifreleme aktif')+'</span>')+
        ir(L?'DPI Profile':'Aktif Profil',(function(){var pn={'tt_default':'Varsay&#305;lan Zapret2 (TTL2 fake)','tt_fiber':'Turk Telekom Fiber (TTL2 fake)','blockcheck_auto':'Blockcheck Otomatik (Auto)','custom':(L?'Custom':'&#214;zel NFQWS2_OPT'),'none':(L?'Passthrough (No Bypass)':'Ge&#231;i&#351; Modu (Bypass Yok)')};var n=pn[S.dpi_profile]||S.dpi_profile||'—';var clr=S.dpi_profile==='none'?'var(--warn)':'var(--info)';return '<span style="color:'+clr+'">'+n+'</span>';})())+
        ir(L?'Filter Mode':'Filtreleme',(function(){var m=S.filter_mode||'';if(m==='autohostlist')return '<span style="color:var(--good)">'+(L?'Auto Hostlist':'Otomatik Liste')+'</span>';if(m==='hostlist')return '<span style="color:var(--info)">'+(L?'Hostlist':'Manuel Liste')+'</span>';if(m==='none')return '<span style="color:var(--warn)">'+(L?'No Filter':'Listesiz')+'</span>';return m||'—';})())+
        ir(L?'Scope':'Kapsam Modu',(function(){var m=S.scope_mode||'';if(m==='smart')return '<span style="color:var(--good)">'+(L?'Smart':'Ak&#305;ll&#305;')+'</span>';if(m==='global')return '<span style="color:var(--warn)">'+(L?'Global':'Global')+'</span>';return m||'—';})())+
        ir(L?'IPSET Mode':'IPSET Modu',(function(){var m=S.ipset_mode||'all';var c=S.ipset_count||0;if(m==='list')return '<span style="color:var(--info)">'+(L?'Selected IPs':'Se&#231;ili IP')+' ('+c+')</span>';return '<span style="color:var(--good)">'+(L?'Whole Network':'T&#252;m A&#287;')+'</span>';})())+
        ir('Zapret2',bdg(S.zapret_running,L?'ACTIVE':'AKT&#304;F',L?'INACTIVE':'PAS&#304;F'))+
        ir(L?'Health Monitor':'Sa&#287;l&#305;k Mon.',bdg(S.healthmon_running,L?'ACTIVE':'AKT&#304;F',L?'INACTIVE':'PAS&#304;F'))+
        ir('Telegram Bot',bdgO(S.telegram_enabled&&S.telegram_running,L?'ACTIVE':'AKT&#304;F',L?'OFF':'KAPALI'))+
        ir(L?'Web Panel (lighttpd)':'Web Panel (lighttpd)',bdg(S.lighttpd_running,L?'RUNNING':'&#199;ALI&#350;IYOR',L?'STOPPED':'DURDU'))+
        ir('curl',S.curl_ok?'<span class="badge good">'+(L?'INSTALLED':'KURULU')+'</span>':'<span class="badge bad">'+(L?'NOT FOUND':'BULUNAMADI')+'</span>')+
        ir(L?'KZM2 Version':'KZM2 S&#252;r&#252;m',S.kzm_version||'—')+ir(L?'Zapret2 Version':'Zapret2 S&#252;r&#252;m',fixTR(S.zapret_version||'—'))+
        ir('GitHub','<a href="https://github.com/RevolutionTR/keenetic-zapret2-manager" target="_blank" style="color:var(--accent)">github.com/RevolutionTR/keenetic-zapret2-manager</a>')+
      '</div></div></div></div>';
  }},
  zapret:{title:'Zapret2 Kontrol',titleEn:'Zapret2 Control',sub:'Zapret2 servisini y&#246;net.',subEn:'Manage Zapret2 service.',html:function(){
    if(!S)return nd();
    return '<div class="grid" style="grid-template-columns:1fr 1fr">'+
      '<div class="card"><h3>'+(L?'Status':'Durum')+'</h3>'+
        '<div class="row">'+bdg(S.zapret_running,L?'ACTIVE':'AKT&#304;F',L?'INACTIVE':'PAS&#304;F')+
          ' <span class="pill">WAN: '+(L?S.wan_dev:fixTR(S.wan_dev||'—'))+'</span>'+
          ' <span class="pill">'+fixTR(S.zapret_version||'—')+'</span></div></div>'+
      '<div class="card"><h3>'+(L?'Control':'Kontrol')+'</h3>'+
        '<div class="zapret-control-actions">'+
          '<button class="ok" onclick="zapretAct(\'zapret_start\',this,\'Baslatildi\')">&#9654; '+(L?'Start':'Ba&#351;lat')+'</button>'+
          '<button class="danger" onclick="zapretAct(\'zapret_stop\',this,\'Durduruldu\')">&#9646;&#9646; '+(L?'Stop':'Durdur')+'</button>'+
          '<button class="ghost" onclick="zapretAct(\'zapret_restart\',this,\'Yeniden ba&#351;lat&#305;ld&#305;\')">&#8635; '+(L?'Restart':'Yeniden Ba&#351;lat')+'</button>'+
        '</div>'+
        '<div class="hint" style="margin-top:8px">'+(L?'If HealthMon AUTORESTART=1, stop is not permanent.':'HealthMon AUTORESTART=1 ise durdurma kal&#305;c&#305; olmaz.')+'</div>'+
      '</div></div>';
  }},
  dpi:{title:'DPI Profili',titleEn:'DPI Profile',sub:'Mevcut DPI profilini g&#246;r&#252;nt&#252;le ve de&#287;i&#351;tir.',subEn:'View and change current DPI profile.',html:function(){
    var h='<div class="dpi-grid">'+
      '<div class="card"><h3>'+(L?'Current Profile':'Mevcut Profil')+'</h3>'+
        '<div class="big" id="dpiVal">'+(function(){
            var p=S.dpi_profile||'';
            var names={
              'tt_default':'Varsay&#305;lan Zapret2 (TTL2 fake)',
              'tt_fiber':'Turk Telekom Fiber (TTL2 fake)',
              'superonline_fiber':'Superonline Fiber (TTL6 hostcase)',
              'blockcheck_auto':'Blockcheck Otomatik (Auto)',
              'custom':(L?'Custom NFQWS2_OPT':'&#214;zel NFQWS2_OPT'),
              'none':(L?'Passthrough (No Bypass)':'Ge&#231;i&#351; Modu (Bypass Yok)')
            };
            return names[p]||p||'—';
          })()+'</div></div>'+
      '<div class="card"><h3>'+(L?'Select Profile':'Profil Se&#231;')+'</h3>'+
        '<div class="dpi-action-row">'+
          (function(){
            var cp=S.dpi_profile||'tt_default';
            var opts=[
              ['tt_default','Varsay&#305;lan Zapret2 (TTL2 fake)'],
              ['tt_fiber','Turk Telekom Fiber (TTL2 fake)'],
              ['superonline_fiber','Superonline Fiber (TTL6 hostcase)'],
              ['blockcheck_auto','Blockcheck Otomatik (Auto)'],
              ['none',L?'Passthrough (No Bypass)':'Ge&#231;i&#351; Modu (Bypass Yok)']
            ];
            var s='<select id="dpiSel" style="flex:1">';
            for(var i=0;i<opts.length;i++){
              s+='<option value="'+opts[i][0]+'"'+(opts[i][0]===cp?' selected':'')+'>'+opts[i][1]+'</option>';
            }
            return s+'</select>';
          })()+
          '<button onclick="(function(b){var v=document.getElementById(\'dpiSel\').value;var sel=document.getElementById(\'dpiSel\');var el=document.getElementById(\'dpiVal\');if(el&&sel)el.textContent=sel.options[sel.selectedIndex].text;actD(\'dpi_set\',\'profile=\'+v,b,'+(L?'\'Profile set\'':'\'Profil ayarlandi\'')+')})(this)">'+(L?'Apply':'Uygula')+'</button>'+
        '</div>'+
        '<div class="hint" style="margin-top:8px">'+(L?'Only verified Zapret2 profiles are shown. Turk Telekom Fiber uses the blockcheck-verified TTL2 fake strategy.':'Sadece dogrulanmis Zapret2 profilleri gosterilir. Turk Telekom Fiber profili blockcheck ile dogrulanmis TTL2 fake stratejisini kullanir.')+'</div>'+
      '</div></div>';
    return h;
  }},
  manualdpi:{title:'Manuel DPI Profili',titleEn:'Manual DPI Profile',sub:'Web Panel &#252;zerinden manuel NFQWS2_OPT stratejisi girin.',subEn:'Enter a custom NFQWS2_OPT strategy from the Web Panel.',html:function(){
    var h='<div class="card wide"><h3>'+(L?'Manual NFQWS2 Profile':'Manuel NFQWS2 Profili')+'</h3>'+
      '<div class="hint" style="margin-bottom:10px">'+(L?'Edit only the base strategy. Startup arguments, qnum, fwmark and hostlist paths are protected.':'Sadece temel strateji alan&#305;n&#305; d&#252;zenleyin. Ba&#351;lang&#305;&#231; arg&#252;manlar&#305;, qnum, fwmark ve hostlist yollar&#305; korunur.')+'</div>'+
      '<div style="margin:12px 0;padding:12px 14px;border:1px solid rgba(245,158,11,.45);background:rgba(245,158,11,.10);border-radius:12px;color:#fbbf24;line-height:1.45">'+
        '<b>'+(L?'Advanced user warning':'Profesyonel kullan&#305;c&#305; uyar&#305;s&#305;')+'</b><br>'+
        '<span>'+(L?'This area is intended for advanced users. Incorrect NFQWS2 parameters may stop Zapret2, break DPI bypass or interrupt internet access for selected clients. Change it only if you know what each parameter does, and export or back up the current profile before applying.':'Bu alan profesyonel kullan&#305;c&#305;lar i&#231;indir. Bilin&#231;siz girilen NFQWS2 parametreleri Zapret2&#8217;nin ba&#351;lamamas&#305;na, DPI a&#351;man&#305;n bozulmas&#305;na veya se&#231;ili cihazlarda internet eri&#351;iminin kesilmesine neden olabilir. Her parametrenin ne yapt&#305;&#287;&#305;n&#305; bilmiyorsan&#305;z de&#287;i&#351;tirmeyin; uygulamadan &#246;nce mevcut profili d&#305;&#351;a aktar&#305;n veya yedek al&#305;n.')+'</span>'+
      '</div>'+
      '<div class="hint" style="margin:8px 0 10px">'+(L?'HTTP, TLS and QUIC are edited in separate blocks. Port filters, &lt;HOSTLIST&gt; and --new separators are added automatically.':'HTTP, TLS ve QUIC ayr&#305; bloklarda d&#252;zenlenir. Port filtreleri, &lt;HOSTLIST&gt; ve --new ay&#305;ra&#231;lar&#305; otomatik eklenir.')+'</div>'+
      '<div class="grid" style="grid-template-columns:1fr;gap:10px">'+
        '<div style="border:1px solid rgba(59,130,246,.40);background:rgba(59,130,246,.07);border-radius:12px;padding:10px">'+
          '<div style="font-weight:700;color:#93c5fd;margin-bottom:6px">HTTP (TCP 80)</div>'+
          '<textarea id="mdpiHttp" spellcheck="false" style="width:100%;min-height:96px;height:clamp(96px,15vh,150px);max-height:190px;resize:vertical;background:var(--card2);border:1px solid var(--line);border-radius:10px;color:var(--fg);padding:10px;font-family:monospace;font-size:12px;line-height:1.45"></textarea>'+
        '</div>'+
        '<div style="border:1px solid rgba(34,197,94,.40);background:rgba(34,197,94,.07);border-radius:12px;padding:10px">'+
          '<div style="font-weight:700;color:#86efac;margin-bottom:6px">TLS / HTTPS (TCP 443)</div>'+
          '<textarea id="mdpiTls" spellcheck="false" style="width:100%;min-height:96px;height:clamp(96px,15vh,150px);max-height:190px;resize:vertical;background:var(--card2);border:1px solid var(--line);border-radius:10px;color:var(--fg);padding:10px;font-family:monospace;font-size:12px;line-height:1.45"></textarea>'+
        '</div>'+
        '<div style="border:1px solid rgba(168,85,247,.40);background:rgba(168,85,247,.07);border-radius:12px;padding:10px">'+
          '<div style="font-weight:700;color:#d8b4fe;margin-bottom:6px">QUIC / HTTP3 (UDP 443)</div>'+
          '<textarea id="mdpiQuic" spellcheck="false" style="width:100%;min-height:96px;height:clamp(96px,15vh,150px);max-height:190px;resize:vertical;background:var(--card2);border:1px solid var(--line);border-radius:10px;color:var(--fg);padding:10px;font-family:monospace;font-size:12px;line-height:1.45"></textarea>'+
        '</div>'+
      '</div>'+
      '<div class="btns" style="margin-top:10px;gap:8px;flex-wrap:wrap">'+
        '<button onclick="mdpiLoad(&quot;config&quot;,this)">'+(L?'Load Config':'Yap&#305;land&#305;rmadan Y&#252;kle')+'</button>'+
        '<button class="ghost" onclick="mdpiLoad(&quot;runtime&quot;,this)">'+(L?'Load Runtime':'Aktif Runtime&#8217;dan Y&#252;kle')+'</button>'+
        '<button class="ghost" onclick="mdpiLoad(&quot;default&quot;,this)">'+(L?'Load Default':'Varsay&#305;lan&#305; Y&#252;kle')+'</button>'+
        '<button class="ghost" onclick="mdpiExport(this)">'+(L?'Export Current':'Mevcut Profili D&#305;&#351;a Aktar')+'</button>'+
        '<button class="ok" onclick="mdpiSave(this)">'+(L?'Apply and Restart Zapret2':'Uygula ve Zapret2&#8217;yi Yeniden Ba&#351;lat')+'</button>'+
      '</div>'+
      '<div id="mdpiExportInfo" class="hint" style="margin-top:8px;display:none"></div>'+
      '<div class="hint" style="margin-top:10px">'+(L?'Blocked parameters: --lua-init, --qnum, --fwmark, --user, --hostlist= and legacy --dpi-desync*.':'Engellenen parametreler: --lua-init, --qnum, --fwmark, --user, --hostlist= ve eski --dpi-desync*.')+'</div>'+
      '</div>'+
      '<div class="card wide" style="margin-top:12px"><h3>'+(L?'Advanced config variables':'&#304;leri d&#252;zey config de&#287;i&#351;kenleri')+'</h3>'+ 
        '<div class="hint" style="margin-bottom:10px">'+(L?'These values are written only to /opt/zapret2/config and then Zapret2 is restarted. DPI profile/NFQWS2_OPT is not changed. Load Default uses KZM2 built-in defaults.':'Bu de&#287;erler sadece /opt/zapret2/config dosyas&#305;na yaz&#305;l&#305;r ve ard&#305;ndan Zapret2 yeniden ba&#351;lat&#305;l&#305;r. DPI profili/NFQWS2_OPT de&#287;i&#351;mez. Varsay&#305;lan Y&#252;kle, KZM2 i&#231;indeki sabit varsay&#305;lanlar&#305; al&#305;r.')+'</div>'+ 
        '<div class="grid mdpi-adv-grid" style="grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:8px">'+
          '<label style="font-size:11px;color:var(--muted)">NFQWS2_PORTS_TCP<input id="mdpiPortsTcp" type="text" value="80,443" style="width:100%;margin-top:4px"/></label>'+ 
          '<label style="font-size:11px;color:var(--muted)">NFQWS2_PORTS_UDP<input id="mdpiPortsUdp" type="text" value="443" style="width:100%;margin-top:4px"/></label>'+ 
          '<label style="font-size:11px;color:var(--muted)">NFQWS2_TCP_PKT_OUT<input id="mdpiTcpOut" type="number" min="1" max="999" value="6" style="width:100%;margin-top:4px"/></label>'+ 
          '<label style="font-size:11px;color:var(--muted)">NFQWS2_TCP_PKT_IN<input id="mdpiTcpIn" type="number" min="1" max="999" value="4" style="width:100%;margin-top:4px"/></label>'+ 
          '<label style="font-size:11px;color:var(--muted)">NFQWS2_UDP_PKT_OUT<input id="mdpiUdpOut" type="number" min="1" max="999" value="3" style="width:100%;margin-top:4px"/></label>'+ 
          '<label style="font-size:11px;color:var(--muted)">NFQWS2_UDP_PKT_IN<input id="mdpiUdpIn" type="number" min="1" max="999" value="3" style="width:100%;margin-top:4px"/></label>'+ 
        '</div>'+ 
        '<div class="btns" style="margin-top:10px;gap:8px;flex-wrap:wrap">'+
          '<button class="ghost" onclick="mdpiAdvLoad(&quot;config&quot;,this)">'+(L?'Load Config':'Config Y&#252;kle')+'</button>'+
          '<button class="ghost" onclick="mdpiAdvLoad(&quot;default&quot;,this)">'+(L?'Load Default':'Varsay&#305;lan Y&#252;kle')+'</button>'+
          '<button class="ok" onclick="mdpiAdvSave(this)">'+(L?'Apply and Restart Zapret2':'Uygula ve Zapret2&#8217;yi Yeniden Ba&#351;lat')+'</button>'+
        '</div>'+
      '</div>';
    setTimeout(function(){var t=document.getElementById('mdpiTls');if(!t||!t.value){mdpiLoad('config');mdpiAdvLoad('config');}},100);return h;
  }},
  hostlist:{title:'Hostlist Y&#246;netimi',titleEn:'Hostlist Management',sub:'Domain ekle, sil, listele.',subEn:'Add, remove, list domains.',html:function(){
    var h='<div class="grid">'+
      '<div class="card"><h3>'+(L?'Add Domain':'Domain Ekle')+'</h3>'+
        '<div class="irow">'+
          '<input type="text" id="hlIn" placeholder="example.com" style="flex:1"/>'+
          '<button onclick="hlAdd()">'+(L?'Add':'Ekle')+'</button></div></div>'+
      '<div class="card wide"><h3>User Hostlist <span id="hlCnt" class="tag">0 Domain</span></h3>'+
        '<div class="lw" id="hlL"><div class="empty">'+(L?'Loading...':'Y&#252;kleniyor...')+'</div></div></div>'+
      '<div class="card wide"><h3>Auto Hostlist <span id="autoCnt" class="tag">0 Domain</span></h3>'+
        '<div class="hint" style="margin-bottom:6px">'+(L?'Auto-generated list (read-only)':'Otomatik olu&#351;turulan liste (salt okunur)')+'</div>'+
        '<div class="lw" id="autoL"><div class="empty">'+(L?'Loading...':'Y&#252;kleniyor...')+'</div></div></div>'+
      '<div class="card wide"><h3>'+(L?'Exclude List':'Exclude Listesi')+' <span id="exCnt" class="tag">0 Domain</span></h3>'+
        '<div class="irow hl-ex-row">'+
          '<input type="text" id="exIn" placeholder="example.com" style="flex:1;min-width:0"/>'+
          '<button onclick="exAdd()">'+(L?'Add':'Ekle')+'</button></div>'+
        '<div class="lw" style="margin-top:8px" id="exL"><div class="empty">'+(L?'Loading...':'Y&#252;kleniyor...')+'</div></div>'+
      '</div></div>';
    setTimeout(hlLoad,100);return h;
  }},
  ipset:{title:'IPSET Y&#246;netimi',titleEn:'IPSET Management',sub:'Statik IP tabanl&#305; filtreleme.',subEn:'Static IP-based filtering.',html:function(){
    var h='<div class="grid">'+
      '<div class="card"><h3>'+(L?'Add IP':'IP Ekle')+'</h3>'+
        '<div class="irow">'+
          '<input type="text" id="ipIn" placeholder="192.168.1.100" style="flex:1"/>'+
          '<button onclick="ipAdd()">'+(L?'Add':'Ekle')+'</button></div>'+
        '<div class="hint" style="margin-top:6px">'+(L?'DHCP not supported, enter static IP.':'DHCP desteklenmez, statik IP girin.')+'</div></div>'+
      '<div class="card wide"><h3>'+(L?'IP List':'IP Listesi')+' <span id="ipCnt" class="tag">0 IP</span></h3>'+
        '<div class="lw" id="ipL"><div class="empty">'+(L?'Loading...':'Y&#252;kleniyor...')+'</div></div></div>'+
      '<div class="card wide"><h3>'+(L?'IPSET Members':'IPSET &#220;yeleri')+' <span id="ipaCnt" class="tag">0 IP</span></h3>'+
        '<div class="hint" style="margin-bottom:6px">'+(L?'Members from ipset_clients.txt file':'ipset_clients.txt dosyas&#305;ndaki &#252;yeler')+'</div>'+
        '<div class="lw" id="ipaL"><div class="empty">'+(L?'Loading...':'Y&#252;kleniyor...')+'</div></div></div>'+
      '<div class="card wide"><h3>No Zapret2 <span id="nzCnt" class="tag">0 IP</span></h3>'+
        '<div class="hint" style="margin-bottom:6px">'+(L?'IPs exempt from Zapret2 processing':'Zapret2 i&#351;leminden muaf IP&#39;ler')+'</div>'+
        '<div class="irow" style="margin-bottom:8px"><input id="nzIn" type="text" placeholder="192.168.1.x" style="flex:1;padding:6px 10px;background:var(--card2);border:1px solid var(--line);border-radius:6px;color:var(--fg)"/>'+
        '<button onclick="nzAdd()">'+(L?'Add':'Ekle')+'</button></div>'+
        '<div class="lw" id="nzL"><div class="empty">'+(L?'Loading...':'Y&#252;kleniyor...')+'</div></div></div>'+
      '</div>';
    setTimeout(ipLoad,100);return h;
  }},
  healthmon:{title:'Sistem Sa&#287;l&#305;&#287;&#305; ve &#304;zleme',titleEn:'System Health and Monitoring',sub:'CPU/RAM/Disk/Load/Zapret2 + HealthMon daemon (Menu 16).',subEn:'CPU/RAM/Disk/Load/Zapret2 + HealthMon daemon (Menu 16).',html:function(){
    if(!S)return nd();
    var rp=pct(S.ram_used_mb,S.ram_total_mb);
    var h='<div class="grid">'  /* uyari hmUpdate tarafindan yonetilir */+
      '<div class="card"><h3>'+(L?'CPU Load':'CPU Y&#252;k&#252;')+'</h3><div class="big" id="hmLoad1">'+S.load1+'</div>'+
        '<div class="sub" id="hmLoad515">'+(L?'5min':'5dk')+': '+S.load5+' &nbsp; '+(L?'15min':'15dk')+': '+S.load15+'</div></div>'+
      '<div class="card"><h3>RAM</h3><div class="big" id="hmRamPct">'+rp+'%</div>'+
        '<div class="sub" id="hmRamSub">'+S.ram_used_mb+' / '+S.ram_total_mb+' MB</div>'+
        '<div id="hmRamBar">'+brr(rp)+'</div></div>'+
      '<div class="card"><h3>Disk /opt</h3><div class="big" id="hmDiskPct">'+(S.disk_used_pct>0?S.disk_used_pct+'%':'<1%')+'</div>'+
        '<div class="sub" id="hmDiskSub">'+(S.disk_used_mb||0)+' MB / '+Math.round(S.disk_total_mb/1024)+' GB</div>'+
        '<div id="hmDiskBar">'+brr(S.disk_used_pct)+'</div></div>'+
      '<div class="card"><h3>HealthMon</h3>'+
        '<div class="row" id="hmHmBdg">'+bdg(S.healthmon_running,'HealthMon OK',L?'HealthMon INACTIVE':'HealthMon PAS&#304;F')+'</div>'+
        '<div class="healthmon-actions" id="hmBtn">';
    h+='<button class="danger" onclick="hmRestart(this)">'+'&#8635; '+(L?'Restart HM':'HM Yeniden Ba&#351;lat')+'</button>';
    h+=S.healthmon_running
      ?'<button class="ghost" onclick="act(\'healthmon_stop\',this,'+(L?'\'HM stopped\'':'\'HM durduruldu\'')+')">'+'&#9646;&#9646; '+(L?'Stop HM':'HM Durdur')+'</button>'
      :'<button class="ok" onclick="act(\'healthmon_start\',this,'+(L?'\'HM started\'':'\'HM ba&#351;lat&#305;ld&#305;\'')+')">'+'&#9654; '+(L?'Start HM':'HM Ba&#351;lat')+'</button>';
    h+=
      '<button class="ghost" onclick="act(\'status_refresh\',this,'+(L?'\'Updated\'':'\'G&#252;ncellendi\'')+')">'+'&#8635; '+(L?'Refresh':'Yenile')+'</button>'+
      '</div></div>'+
      '<div class="card wide" id="hmC">'+(hmConfCache||'<div class="sub">'+(L?'Loading...':'Y&#252;kleniyor...')+'</div>')+'</div>'+
    '</div>';
    if(!hmConfCache){
      getD('hm_get',function(r){
        hmConfCache=r.ok?'<div class="info-grid">'+r.data+'</div>':'<div class="sub">Okunamad&#305;</div>';
        var el=document.getElementById('hmC');
        if(el)el.innerHTML=hmConfCache;
      });
    }
    return h;
  }},
  compcheck:{title:'Bile&#351;en Kontrol&#252;',titleEn:'Component Check',sub:'OPKG, iptables, ipset, ip6tables, curl, wget-ssl, grep, gzip, cron, xtables, TC kontrol&#252;.',subEn:'OPKG, iptables, ipset, ip6tables, curl, wget-ssl, grep, gzip, cron, xtables, TC check.',html:function(){
    setTimeout(function(){ccRun();},100);
    return '<div id="ccResult"><div style="display:flex;flex-direction:column;align-items:center;justify-content:center;padding:32px;gap:16px"><div style="display:flex;align-items:center;gap:4px;height:40px"><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:.1s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:.2s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:.3s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:.4s"></div></div><div style="font-size:1.1em;color:var(--fg)">'+(L?'Checking components...':'Bile&#351;enler kontrol ediliyor...')+'</div></div></div>';
  }},
  healthcheck:{title:'A&#287; Tan&#305;lama',titleEn:'Network Diagnostics',sub:'DNS/NTP/GitHub/OPKG/Disk/Zapret2 kontrol&#252; (Menu 14).',subEn:'DNS/NTP/GitHub/OPKG/Disk/Zapret2 check (Menu 14).',html:function(){
    if(!S)return nd();
    setTimeout(function(){hcRun();},50);
    return '<div id="hcResult"><div style="display:flex;flex-direction:column;align-items:center;justify-content:center;padding:32px;gap:16px"><div style="display:flex;align-items:center;gap:4px;height:40px"><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.0s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.1s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.2s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.3s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.4s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.5s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.6s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.7s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.8s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.9s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:1.0s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:1.1s"></div></div><div style="font-size:1.1em;color:var(--fg)">'+(L?'Running diagnostics...':'Kontrol yap&#305;l&#305;yor...')+'</div><div style="font-size:0.85em;color:var(--muted)">'+(L?'Please wait':'L&#252;tfen bekleyin')+'</div></div></div>';
  }},
  telegram:{title:'Telegram',titleEn:'Telegram',sub:'Bildirim ve interaktif bot.',subEn:'Notifications and interactive bot.',html:function(){
    if(!S)return nd();
    var cfg=!!S.telegram_configured;
    var run=!!S.telegram_running;
    var en=!!S.telegram_enabled;
    var dis=cfg?'':'disabled';
    var notCfg='<div style="background:rgba(255,180,0,0.12);border:1px solid var(--warn);border-radius:6px;padding:8px 10px;margin-bottom:12px;font-size:0.88em;color:var(--warn)">&#9888; '+(L?'Not configured &mdash; SSH &gt; Menu 15':'Yap&#305;land&#305;r&#305;lmam&#305;&#351; &mdash; SSH &gt; Menu 15')+'</div>';
    var startBtn=run
      ?'<button class="danger" style="min-width:130px" onclick="tgStop(this)">&#9632; '+(L?'Stop':'Durdur')+'</button>'+
       '<button class="ghost" style="min-width:130px;margin-top:6px" onclick="tgRestart(this)">&#8635; '+(L?'Restart':'Yeniden Ba&#351;lat')+'</button>'
      :'<button '+dis+' style="min-width:130px" onclick="tgStart(this)">&#9654; '+(L?'Start':'Ba&#351;lat')+'</button>';
    var h='<div style="display:grid;grid-template-columns:1fr 1fr;gap:16px">'+
      '<div class="card">'+
        '<h3>&#128276; '+(L?'Notifications':'Bildirim')+' <span style="font-size:0.7em;font-weight:normal;color:var(--muted)">'+(L?'(One-Way)':'(Tek Yon)')+'</span></h3>'+
        (cfg?'':''+notCfg)+
        '<div style="font-size:0.85em;color:var(--muted);margin-bottom:10px">'+(L?'HealthMon alerts, Zapret2 status notifications':'HealthMon uyar&#305;lar&#305;, Zapret2 durum bildirimleri')+'</div>'+
        '<div class="row">'+bdgO(cfg,L?'Configured':'Yap&#305;land&#305;r&#305;lm&#305;&#351;',L?'Not Set Up':'Kurulmam&#305;&#351;')+'</div>'+
        '<div class="row" style="margin-top:6px">'+bdgO(en,L?'Enabled':'Etkin',L?'Disabled':'Devre D&#305;&#351;&#305;')+'</div>'+
        '<div class="btns" style="margin-top:12px">'+
          '<button '+dis+' onclick="act(\'tg_test\',this,'+(L?'\'Test sent\'':'\'Test gonderildi\'')+')">'+'&#128172; '+(L?'Send Test':'Test Gonder')+'</button>'+
        '</div>'+
      '</div>'+
      '<div class="card">'+
        '<h3>&#129302; '+(L?'Interactive Bot':'&#304;nteraktif Bot')+' <span style="font-size:0.7em;font-weight:normal;color:var(--muted)">'+(L?'(Two-Way)':'(&#199;ift Y&#246;n)')+'</span></h3>'+
        (cfg?'':''+notCfg)+
        '<div style="font-size:0.85em;color:var(--muted);margin-bottom:10px">'+(L?'Send commands from Telegram, manage router':'Telegram\'dan komut g&#246;nder, router\'&#305; y&#246;net')+'</div>'+
        '<div class="row">'+bdgO(run,L?'Running':'&#199;al&#305;&#351;&#305;yor',L?'Stopped':'Durdu')+'</div>'+
        '<div class="btns" style="margin-top:12px;display:flex;flex-direction:column;align-items:flex-start;gap:6px">'+startBtn+'</div>'+
      '</div>'+
    '</div>'+
    '<div style="margin-top:16px">'+
      '<div class="card" id="tgInfoCard"><h3>&#128272; '+(L?'Connection Info':'Ba&#287;lant&#305; Bilgileri')+'</h3>'+
        '<div style="color:var(--muted);font-size:0.9em">'+(L?'Loading...':'Y&#252;kleniyor...')+'</div>'+
      '</div>'+
    '</div>';
    setTimeout(function(){
      getD('tg_info',function(r){
        var el=document.getElementById('tgInfoCard');
        if(!el)return;
        if(r.ok&&(r.token||r.chat)){
          el.innerHTML='<h3>&#128272; '+(L?'Connection Info':'Ba&#287;lant&#305; Bilgileri')+'</h3>'+
            '<table style="width:100%;border-collapse:collapse;font-size:0.9em">'+
            '<tr><td style="color:var(--muted);padding:5px 0;width:80px">Token</td>'+
            '<td style="font-family:monospace;letter-spacing:0.03em">'+r.token+'</td></tr>'+
            '<tr><td style="color:var(--muted);padding:5px 0">Chat ID</td>'+
            '<td style="font-family:monospace">'+r.chat+'</td></tr>'+
            '</table>';
        } else {
          el.innerHTML='<h3>&#128272; '+(L?'Connection Info':'Ba&#287;lant&#305; Bilgileri')+'</h3>'+
            '<div style="color:var(--muted);font-size:0.9em">'+(L?'Not configured &mdash; use Menu 15 via SSH.':'Yap&#305;land&#305;r&#305;lmam&#305;&#351; &mdash; SSH ile Menu 15\'i kullanin.')+'</div>';
        }
      });
    },100);
    return h;
  }},
  mon:{title:'Sistem &#304;zleme',titleEn:'System Monitor',sub:'Canl&#305; kaynak kullan&#305;m&#305;.',subEn:'Live resource usage.',html:function(){
    if(!S)return nd();
    var rp=pct(S.ram_used_mb,S.ram_total_mb);
    return '<div class="grid">'+
      '<div class="card"><h3>'+(L?'CPU Load':'CPU Y&#252;k&#252;')+'</h3><div class="big">'+S.load1+'</div>'+
        '<div class="sub">'+(L?'5min':'5dk')+': '+S.load5+' &nbsp; '+(L?'15min':'15dk')+': '+S.load15+'</div></div>'+
      '<div class="card"><h3>RAM</h3><div class="big">'+rp+'%</div>'+
        '<div class="sub">'+S.ram_used_mb+' / '+S.ram_total_mb+' MB</div>'+brr(rp)+'</div>'+
      '<div class="card"><h3>Disk /opt</h3><div class="big">'+(S.disk_used_pct>0?S.disk_used_pct+'%':'<1%')+'</div>'+
        '<div class="sub">'+(S.disk_used_mb||0)+' MB / '+Math.round(S.disk_total_mb/1024)+' GB</div>'+brr(S.disk_used_pct)+'</div>'+
      '<div class="card"><h3>'+(L?'Services':'Servisler')+'</h3>'+
        '<div class="row">'+bdg(S.zapret_running,'Zapret2 OK',L?'Zapret2 INACTIVE':'Zapret2 PAS&#304;F')+'</div>'+
        '<div class="row" style="margin-top:6px">'+bdg(S.healthmon_running,'HealthMon OK',L?'HealthMon INACTIVE':'HealthMon PAS&#304;F')+'</div>'+
        '<div class="btns" style="margin-top:10px">'+
          '<button class="ghost" onclick="act(\'status_refresh\',this,'+(L?'\'Updated\'':'\'G&#252;ncellendi\'')+')">'+'&#8635; '+(L?'Refresh':'G&#252;ncelle')+'</button>'+
        '</div></div>'+
      '</div>';
  }},
  sched:{title:'Zamanlanm&#305;&#351; G&#246;revler',titleEn:'Scheduled Tasks',sub:'Cron tabanl&#305; zamanlanm&#305;&#351; g&#246;revler.',subEn:'Cron-based scheduled tasks.',html:function(){
    var h='<div class="grid">'+
      '<div class="card wide" style="grid-column:1/-1"><h3>&#9719; '+(L?'Scheduled Reboot':'Zamanl&#305; Yeniden Ba&#351;latma')+'</h3></div>'+
      '<div class="card" id="schedC"><h3>'+(L?'Current Schedule':'Mevcut Zamanlama')+'</h3><div class="sub">'+(L?'Loading...':'Y&#252;kleniyor...')+'</div></div>'+
      '<div class="card"><h3>'+(L?'Set Schedule':'Zamanlama Ayarla')+'</h3>'+
        '<div class="irow" style="margin-bottom:8px">'+
          '<select id="schedMode" style="flex:1" onchange="schedModeChange()">'+
            '<option value="daily">'+(L?'Daily':'G&#252;nl&#252;k')+'</option>'+
            '<option value="weekly">'+(L?'Weekly':'Haftal&#305;k')+'</option>'+
          '</select>'+
        '</div>'+
        '<div id="schedDowRow" style="display:none;margin-bottom:8px">'+
          '<select id="schedDow" style="width:100%">'+
            '<option value="1">'+(L?'Monday':'Pazartesi')+'</option>'+
            '<option value="2">'+(L?'Tuesday':'Sal&#305;')+'</option>'+
            '<option value="3">'+(L?'Wednesday':'&#199;ar&#351;amba')+'</option>'+
            '<option value="4">'+(L?'Thursday':'Per&#351;embe')+'</option>'+
            '<option value="5">'+(L?'Friday':'Cuma')+'</option>'+
            '<option value="6">'+(L?'Saturday':'Cumartesi')+'</option>'+
            '<option value="0">'+(L?'Sunday':'Pazar')+'</option>'+
          '</select>'+
        '</div>'+
        '<div class="irow">'+
          '<input type="text" id="schedT" placeholder="02:00" style="width:90px"/>'+
          '<button onclick="schedSet()">'+(L?'Set':'Ayarla')+'</button>'+
          '<button class="danger" onclick="schedDel(this)">'+(L?'Remove':'Kald&#305;r')+'</button>'+
        '</div>'+
        '<div class="hint" style="margin-top:6px">'+(L?'Format: HH:MM &mdash; e.g. 03:30':'Format: SS:DD &mdash; &#246;rn. 03:30')+'</div>'+
      '</div>'+
      '<div class="card wide" style="grid-column:1/-1"><h3>&#128260; '+(L?'Scheduled OPKG Upgrade':'Zamanlanm&#305;&#351; OPKG G&#252;ncelleme')+'</h3></div>'+
      '<div class="card" id="opkgSchedC"><h3>'+(L?'Current Schedule':'Mevcut Zamanlama')+'</h3><div class="sub">'+(L?'Loading...':'Y&#252;kleniyor...')+'</div></div>'+
      '<div class="card"><h3>'+(L?'Set Schedule':'Zamanlama Ayarla')+'</h3>'+
        '<div class="irow" style="margin-bottom:8px">'+
          '<select id="opkgSchedPeriod" style="flex:1">'+
            '<option value="weekly">'+(L?'Weekly (Every Sunday 03:00)':'Haftal&#305;k (Her Pazar 03:00)')+'</option>'+
            '<option value="biweekly">'+(L?'Biweekly (1st and 15th 03:00)':'2 Haftada Bir (1. ve 15. 03:00)')+'</option>'+
            '<option value="monthly">'+(L?'Monthly (1st of month 03:00)':'Ayl&#305;k (Her ay&#305;n 1\'i 03:00)')+'</option>'+
          '</select>'+
        '</div>'+
        '<div class="irow">'+
          '<button onclick="opkgSchedSet(this)">'+(L?'Set':'Ayarla')+'</button>'+
          '<button class="danger" onclick="opkgSchedDel(this)">'+(L?'Remove':'Kald&#305;r')+'</button>'+
        '</div>'+
        '<div class="hint" style="margin-top:6px">'+(L?'Runs opkg update &amp; upgrade, notifies via Telegram.':'opkg update &amp; upgrade &#231;al&#305;&#351;t&#305;r&#305;r, Telegram ile bildirir.')+'</div>'+
      '</div></div>';
    setTimeout(function(){
      getD('sched_get',function(r){
        var el=document.getElementById('schedC');
        if(!el)return;
        var dowNames=L?['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday']:['Pazar','Pazartesi','Sali','Carsamba','Persembe','Cuma','Cumartesi'];
        if(r.ok&&r.data){
          var dow=r.dow||'*';
          var sub=dow==='*'?(L?'Every day at this time':'Her g&#252;n bu saatte reboot'):(L?'Every week on <b>'+(dowNames[parseInt(dow)]||dow)+'</b> at this time':'Her hafta <b>'+(dowNames[parseInt(dow)]||dow)+'</b> g&#252;n&#252; bu saatte reboot');
          el.innerHTML='<h3>'+(L?'Current Schedule':'Mevcut Zamanlama')+'</h3><div class="big">'+r.data+'</div><div class="sub">'+sub+'</div>';
          if(dow!=='*'){
            var modeEl=document.getElementById('schedMode');
            var dowEl=document.getElementById('schedDow');
            var rowEl=document.getElementById('schedDowRow');
            if(modeEl)modeEl.value='weekly';
            if(dowEl)dowEl.value=dow;
            if(rowEl)rowEl.style.display='';
          }
          var tEl=document.getElementById('schedT');
          if(tEl)tEl.value=r.data;
        } else {
          el.innerHTML='<h3>'+(L?'Current Schedule':'Mevcut Zamanlama')+'</h3><div class="sub">'+(L?'No schedule':'Zamanlama yok')+'</div>';
        }
      });
      getD('opkg_sched_get',function(r){
        var el=document.getElementById('opkgSchedC');
        if(!el)return;
        var periodNames={weekly:(L?'Weekly (Every Sunday)':'Haftal&#305;k (Her Pazar)'),biweekly:(L?'Biweekly (1st &amp; 15th)':'2 Haftada Bir (1. ve 15.)'),monthly:(L?'Monthly (1st of month)':'Ayl&#305;k (Her ay&#305;n 1\'i)')};
        if(r.ok&&r.data){
          var pEl=document.getElementById('opkgSchedPeriod');
          if(pEl)pEl.value=r.period||'weekly';
          el.innerHTML='<h3>'+(L?'Current Schedule':'Mevcut Zamanlama')+'</h3><div class="big">'+r.data+'</div><div class="sub">'+(periodNames[r.period]||r.period)+'</div>';
        } else {
          el.innerHTML='<h3>'+(L?'Current Schedule':'Mevcut Zamanlama')+'</h3><div class="sub">'+(L?'No schedule':'Zamanlama yok')+'</div>';
        }
      });
    },100);
    return h;
  }},
  dns:{title:'DNS Y&#246;netimi',titleEn:'DNS Management',sub:'DoT/DoH sunucu y&#246;netimi.',subEn:'DoT/DoH server management.',html:function(){
    var h='<div class="grid">';
    h+='<div class="security-note" style="margin-bottom:8px;grid-column:1/-1"><b>&#9888; </b>'+(L?'If you use a VPN, assign a dedicated DNS to your VPN interface to prevent DNS leaks.':'VPN kullan&#305;yorsan&#305;z DNS s&#305;z&#305;nt&#305;s&#305;n&#305; &#246;nlemek i&#231;in VPN aray&#252;z&#252;n&#252;ze &#246;zel DNS atay&#305;n&#305;z.')+'</div>';
    // Mevcut sunucular
    h+='<div class="card wide"><h3>'+(L?'Active DNS Servers':'Aktif DNS Sunucular&#305;')+'</h3>'+
      '<div id="dnsListArea"><span class="sub">'+(L?'Loading...':'Y&#252;kleniyor...')+'</span></div>'+
      '<div style="margin-top:12px">'+
        '<b>'+(L?'Add Preset:':'Haz&#305;r Paket Ekle:')+'</b>'+dnsPresetHtml()+
    '</div>'+
    '<div class="card"><h3>Rebind '+(L?'Protection':'Koruma')+'</h3>'+
      '<div id="dnsRebindStatus" class="sub">'+(L?'Loading...':'Y&#252;kleniyor...')+'</div>'+
      '<div style="margin-top:10px">'+
        '<button id="dnsRebindBtn" onclick="dnsRebindToggle(this)">'+(L?'Toggle':'Degistir')+'</button>'+
      '</div>'+
      '<div class="hint" style="margin-top:8px">'+(L?'Blocks DNS responses returning local IPs (prevents DNS rebinding attacks).':'Yerel IP d&#246;nd&#252;ren DNS yan&#305;tlar&#305;n&#305; engeller.')+'</div>'+
    '</div>'+
    '</div>';
        setTimeout(function(){dnsLoad();},100);
    return h;
  }},
  backup:{title:'Yedekle / Geri Y&#252;kle',titleEn:'Backup / Restore',sub:'Zapret2 ayarlar&#305; yedekleme ve geri y&#252;kleme.',subEn:'Zapret2 settings backup and restore.',html:function(){
    setTimeout(function(){bkLoad();},100);
    return '<div class="bk-grid">'+
      '<div class="card"><h3>&#128190; '+(L?'Backup Zapret2 Settings':'Zapret2 Ayarlar&#305; Yedekle')+'</h3>'+
        '<div class="sub">'+(L?'Backs up config, hostlist, IPSET, DPI profile, healthmon, telegram as tar.gz.':'config, hostlist, IPSET, DPI profili, healthmon, telegram ayarlar&#305; tar.gz olarak yedekler.')+'</div>'+
        '<div class="bk-actions" style="margin-top:8px">'+
          '<button onclick="bkDoSettingsBackup(this)">'+'&#128190; '+(L?'Backup':'Yedekle')+'</button>'+
          '<button onclick="bkSettingsList(this)" style="background:#444">&#128220; '+(L?'View Backups':'Yedekleri G&#246;r')+'</button>'+
          '<button onclick="bkSettingsClean(this)" style="background:#5a1a1a">&#128465; '+(L?'Clean Backups':'Yedekleri Temizle')+'</button>'+
        '</div>'+
        '<div class="hint" style="margin-top:8px">'+(L?'Location:':'Konum:')+' /opt/zapret2_backups/zapret2_settings/</div>'+
        '<div id="bkSetList" style="margin-top:8px"></div>'+
      '</div>'+
      '<div class="card"><h3>&#9850; '+(L?'Restore Zapret2 Settings':'Zapret2 Ayarlar&#305; Geri Y&#252;kle')+'</h3>'+
        '<div class="sub">'+(L?'Restore from backup by scope. Zapret2 restarts automatically.':'Kapsam se&#231;erek yedekten geri y&#252;kle. Zapret2 otomatik yeniden ba&#351;lar.')+'</div>'+
        '<div style="margin-top:8px">'+
          '<select id="bkScope" style="width:100%;padding:6px;background:#1e1e2e;color:#cdd6f4;border:1px solid #444;border-radius:6px;margin-bottom:8px">'+
            '<option value="1">'+(L?'Full Restore':'Tam Geri Y&#252;kleme')+'</option>'+
            '<option value="2">'+(L?'DPI Settings Only':'Sadece DPI Ayarlar&#305;')+'</option>'+
            '<option value="3">'+(L?'Hostlist Only':'Sadece Hostlist')+'</option>'+
            '<option value="4">'+(L?'IPSET Only':'Sadece IPSET')+'</option>'+
          '</select>'+
          '<div id="bkSetRestore" style="margin-top:4px"><div class="sub">&#8593; '+(L?'Click View Backups first':'Once Yedekleri G&#246;r\'e t&#305;klay&#305;n')+'</div></div>'+
        '</div>'+
      '</div>'+
      '<div class="card"><h3>&#128190; '+(L?'Backup IPSET':'IPSET Yedekle')+'</h3>'+
        '<div class="sub">'+(L?'Copies current IPSET .txt files to current + history folders.':'Mevcut IPSET .txt dosyalar&#305;n&#305; current + history klas&#246;rlerine kopyalar.')+'</div>'+
        '<div class="bk-actions" style="margin-top:8px">'+
          '<button onclick="bkDoIpsetBackup(this)">'+'&#128190; '+(L?'Backup':'Yedekle')+'</button>'+
          '<button onclick="bkIpsetList(this)" style="background:#444">&#128220; '+(L?'View Backups':'Yedekleri G&#246;r')+'</button>'+
          '<button onclick="bkIpsetClean(this)" style="background:#5a1a1a">&#128465; '+(L?'Clean History':'Ge&#231;mi&#351;i Temizle')+'</button>'+
        '</div>'+
        '<div class="hint" style="margin-top:8px">'+(L?'Location:':'Konum:')+' /opt/zapret2_backups/current/</div>'+
        '<div id="bkIpList" style="margin-top:8px"></div>'+
      '</div>'+
      '<div class="card"><h3>&#9850; '+(L?'Restore IPSET':'IPSET Geri Y&#252;kle')+'</h3>'+
        '<div class="sub">'+(L?'Select and restore files from the current folder.':'Current klas&#246;r&#252;ndeki dosyalar&#305; se&#231;erek geri y&#252;kle.')+'</div>'+
        '<div id="bkIpRestore" style="margin-top:8px"><div class="sub">&#8593; '+(L?'Click View Backups first':'Once Yedekleri G&#246;r\'e t&#305;klay&#305;n')+'</div></div>'+
      '</div>'+
    '</div>';
  }},
  changelog:{title:'KZM2 — S&#252;r&#252;m Notlar&#305;',titleEn:'KZM2 — Release Notes',sub:'KZM2 g&#252;ncelleme ge&#231;mi&#351;i.',subEn:'KZM2 update history.',noPrefix:true,html:function(){
    setTimeout(function(){clLoad();},100);
    return '<div class="cl-grid">'+
      '<div class="card" id="clList" style="max-height:70vh;overflow-y:auto"><div class="sub">Y&#252;kleniyor...</div></div>'+
      '<div class="card" id="clBody" style="max-height:70vh;overflow-y:auto"><div class="sub">'+
        (L?'Select a version from the list.':'Listeden bir s&#252;r&#252;m se&#231;in.')+
      '</div></div>'+
    '</div>';
  }},
  docs:{title:'Belgeler',titleEn:'Documentation',sub:'KZM2 kullan&#305;m k&#305;lavuzlar&#305;.',subEn:'KZM2 user guides.',noPrefix:true,html:function(){
    setTimeout(function(){docsInit();},100);
    var docList=[
      {key:'guide_tr',   label:'Kullan&#305;m K&#305;lavuzu',    file:'kullanim_klavuzu.md',           lang:'tr'},
      {key:'guide_en',   label:'User Guide',               file:'user_guide_en.md',               lang:'en'},
      {key:'install_tr', label:'S&#305;f&#305;rdan Kurulum',     file:'sifirdan_kurulum_anlatimi.md',   lang:'tr'},
      {key:'install_en', label:'Installation Guide',       file:'installation_guide_en.md',        lang:'en'},
      {key:'tg_tr',      label:'Telegram Kurulum',         file:'telegram.md',                    lang:'tr'},
      {key:'tg_en',      label:'Telegram Setup',           file:'telegram_en.md',                 lang:'en'}
    ].filter(function(d){return L?(d.lang==='en'):(d.lang==='tr');});
    var nav='<div class="card" id="docsNav" style="max-height:70vh;overflow-y:auto"><h3>'+(L?'Guides':'K&#305;lavuzlar')+'</h3><div style="display:flex;flex-direction:column;gap:4px;margin-top:8px">';
    docList.forEach(function(d){
      nav+='<div onclick="docsSelect(\''+d.key+'\',\''+d.file+'\','+(d.base?'\''+d.base+'\'':'null')+')" id="docNav_'+d.key+'" style="cursor:pointer;padding:6px 10px;border-radius:7px;font-size:13px;border:1px solid transparent">'+d.label+'</div>';
    });
    nav+='</div></div>';
    return '<div class="cl-grid">'+nav+'<div class="card" id="docsBody" style="max-height:70vh;overflow-y:auto"><div class="sub">'+(L?'Select a guide from the list.':'Listeden bir k&#305;lavuz se&#231;in.')+'</div></div></div>';
  }}
};
function hlLoad(retry){
  if(!document.getElementById('hlL')){setTimeout(hlLoad,200);return;}
  getD('hl_get',function(r){
    var el=document.getElementById('hlL'),ec=document.getElementById('hlCnt');
    if(!el)return;
    if(!r.ok){el.innerHTML='<div class="empty">Liste bo&#351;</div>';if(ec)ec.textContent='0 Domain';return;}
    if(!r.data||!r.data.length){
      if(!retry){setTimeout(function(){hlLoad(true);},800);return;}
      el.innerHTML='<div class="empty">Liste bo&#351;</div>';if(ec)ec.textContent='0 Domain';return;
    }
    if(ec)ec.textContent=r.data.length+' Domain';
    el.innerHTML=r.data.map(function(d){return '<div class="li"><span>'+d+'</span>'+
      '<button class="danger" style="padding:3px 8px;font-size:11px" onclick="hlDel(\''+d+'\',this)">Sil</button></div>';}).join('');
  });
  getD('auto_get',function(r){
    var el=document.getElementById('autoL'),ec=document.getElementById('autoCnt');if(!el)return;
    if(!r.ok||!r.data||!r.data.length){
      if(!retry){setTimeout(function(){hlLoad(true);},800);return;}
      el.innerHTML='<div class="empty">Liste bo&#351;</div>';if(ec)ec.textContent='0 Domain';return;}
    if(ec)ec.textContent=r.data.length+' Domain';
    el.innerHTML=r.data.map(function(d){return '<div class="li"><span>'+d+'</span>'+
      '<button class="danger" style="padding:3px 8px;font-size:11px" onclick="autoDel(\''+d+'\',this)">Sil</button></div>';}).join('');
  });
  getD('ex_get',function(r){
    var el=document.getElementById('exL'),ec=document.getElementById('exCnt');if(!el)return;
    if(!r.ok||!r.data||!r.data.length){
      if(!retry){setTimeout(function(){hlLoad(true);},800);return;}
      el.innerHTML='<div class="empty">Liste bo&#351;</div>';if(ec)ec.textContent='0 Domain';return;}
    if(ec)ec.textContent=r.data.length+' Domain';
    el.innerHTML=r.data.map(function(d){return '<div class="li"><span>'+d+'</span>'+
      '<button class="danger" style="padding:3px 8px;font-size:11px" onclick="exDel(\''+d+'\',this)">Sil</button></div>';}).join('');
  });
}
function mdpiNormalizeLines(s){
  return (s||'').replace(/\r/g,'\n').replace(/[ \t]+(--)/g,'\n$1').split('\n').map(function(x){return x.trim();}).filter(function(x){return x&&x.charAt(0)!=='#';});
}
function mdpiSplitProfile(opt){
  var out={http:[],tls:[],quic:[]},cur='';
  mdpiNormalizeLines(opt).forEach(function(line){
    if(/^--filter-tcp=80(\s|$)/.test(line)){cur='http';return;}
    if(/^--filter-tcp=443(\s|$)/.test(line)){cur='tls';return;}
    if(/^--filter-udp=443(\s|$)/.test(line)){cur='quic';return;}
    if(/^--new(=|\s|$)/.test(line)){cur='';return;}
    if(cur&&out[cur])out[cur].push(line);
  });
  if(!out.http.length&&!out.tls.length&&!out.quic.length){out.http=mdpiNormalizeLines(opt);}
  return out;
}
function mdpiSetBlocks(opt){
  var p=mdpiSplitProfile(opt||'');
  var h=document.getElementById('mdpiHttp'),t=document.getElementById('mdpiTls'),q=document.getElementById('mdpiQuic');
  if(h)h.value=p.http.join('\n');if(t)t.value=p.tls.join('\n');if(q)q.value=p.quic.join('\n');
}
function mdpiBlockValue(id){
  var el=document.getElementById(id);
  return mdpiNormalizeLines(el?el.value:'').join('\n');
}
function mdpiJoinBlocks(){
  var parts=[];
  var http=mdpiBlockValue('mdpiHttp'),tls=mdpiBlockValue('mdpiTls'),quic=mdpiBlockValue('mdpiQuic');
  if(http)parts.push('--filter-tcp=80 <HOSTLIST>\n'+http);
  if(tls)parts.push('--filter-tcp=443 <HOSTLIST>\n'+tls);
  if(quic)parts.push('--filter-udp=443 <HOSTLIST>\n'+quic);
  return parts.join('\n--new\n');
}
function mdpiSetAdv(data){
  var d=data||{};
  var map={ports_tcp:'mdpiPortsTcp',ports_udp:'mdpiPortsUdp',tcp_out:'mdpiTcpOut',tcp_in:'mdpiTcpIn',udp_out:'mdpiUdpOut',udp_in:'mdpiUdpIn'};
  Object.keys(map).forEach(function(k){var el=document.getElementById(map[k]);if(el&&d[k]!==undefined&&d[k]!==null)el.value=d[k];});
}
function mdpiLoadAdv(src){
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=manual_dpi_adv_get&source='+encodeURIComponent(src||'config')})
  .then(function(r){return r.json();})
  .then(function(res){if(res&&res.ok)mdpiSetAdv(res.data||res||{});})
  .catch(function(){});
}
function mdpiAdvLoad(src,btn){
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=manual_dpi_adv_get&source='+encodeURIComponent(src||'config')})
  .then(function(r){return r.json();})
  .then(function(res){
    if(res&&res.ok){mdpiSetAdv(res.data||res||{});if(btn)toast(L?'Config variables loaded':'Config degiskenleri yuklendi',true);}else{if(btn)toast((res&&res.msg)||(L?'Error':'Hata'),false);}
    if(btn){btn.disabled=false;btn.innerHTML=btn._o;}
  }).catch(function(){toast(L?'Connection error':'Ba&#287;lant&#305; hatas&#305;',false);if(btn){btn.disabled=false;btn.innerHTML=btn._o;}});
}
function mdpiAdvSave(btn){
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=manual_dpi_adv_save'+mdpiAdvPayload()})
  .then(function(r){return r.json();})
  .then(function(res){toast((res&&res.msg)||(L?'Saved':'Kaydedildi'),!!(res&&res.ok));if(btn){btn.disabled=false;btn.innerHTML=btn._o;}})
  .catch(function(){toast(L?'Connection error':'Ba&#287;lant&#305; hatas&#305;',false);if(btn){btn.disabled=false;btn.innerHTML=btn._o;}});
}
function mdpiAdvPayload(){
  function v(id){var el=document.getElementById(id);return encodeURIComponent((el?el.value:'').trim());}
  return '&ports_tcp='+v('mdpiPortsTcp')+'&ports_udp='+v('mdpiPortsUdp')+'&tcp_out='+v('mdpiTcpOut')+'&tcp_in='+v('mdpiTcpIn')+'&udp_out='+v('mdpiUdpOut')+'&udp_in='+v('mdpiUdpIn');
}
function mdpiLoad(src,btn){
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=manual_dpi_get&source='+encodeURIComponent(src||'config')})
  .then(function(r){return r.json();})
  .then(function(res){
    if(res&&res.ok){mdpiSetBlocks(res.data||'');if(btn)toast(L?'Loaded':'Y&#252;klendi',true);}else{if(btn)toast((res&&res.msg)||(L?'Error':'Hata'),false);}
    if(btn){btn.disabled=false;btn.innerHTML=btn._o;}
  }).catch(function(){toast(L?'Connection error':'Ba&#287;lant&#305; hatas&#305;',false);if(btn){btn.disabled=false;btn.innerHTML=btn._o;}});
}
function mdpiExport(btn){
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=manual_dpi_export'})
  .then(function(r){return r.json();})
  .then(function(res){
    if(res&&res.ok){
      toast((res.msg||((L?'Exported':'D&#305;&#351;a aktar&#305;ld&#305;'))),true);
      var inf=document.getElementById('mdpiExportInfo');
      if(inf){inf.style.display='block';inf.innerHTML=(L?'Saved file: ':'Kaydedilen dosya: ')+'<code>'+(res.path||'/opt/zapret2/dpi_profiles/active_dpi_profile_latest.txt')+'</code>';}
    }else{toast((res&&res.msg)||(L?'Export failed':'D&#305;&#351;a aktarma ba&#351;ar&#305;s&#305;z'),false);}
    if(btn){btn.disabled=false;btn.innerHTML=btn._o;}
  }).catch(function(){toast(L?'Connection error':'Ba&#287;lant&#305; hatas&#305;',false);if(btn){btn.disabled=false;btn.innerHTML=btn._o;}});
}
function mdpiSave(btn){
  var v=mdpiJoinBlocks().trim();if(!v){toast(L?'Profile is empty':'Profil bo&#351;',false);return;}
  if(!confirm(L?'Apply manual DPI profile and restart Zapret2?':'Manuel DPI profili uygulans\u0131n ve Zapret2 yeniden ba\u015flat\u0131ls\u0131n m\u0131?'))return;
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=manual_dpi_save&opt='+encodeURIComponent(v)})
  .then(function(r){return r.json();})
  .then(function(res){toast((res&&res.msg)||(L?'Applied':'Uyguland&#305;'),!!(res&&res.ok));setTimeout(fetchS,1200);if(btn){btn.disabled=false;btn.innerHTML=btn._o;}})
  .catch(function(){toast(L?'Connection error':'Ba&#287;lant&#305; hatas&#305;',false);if(btn){btn.disabled=false;btn.innerHTML=btn._o;}});
}
function hlAdd(){var v=(document.getElementById('hlIn').value||'').trim();if(!v)return;actD('hl_add','domain='+encodeURIComponent(v),null,'Eklendi');document.getElementById('hlIn').value='';setTimeout(hlLoad,1800);}
function hlDel(d,b){actD('hl_del','domain='+encodeURIComponent(d),b,'Silindi');setTimeout(hlLoad,1800);}
function exAdd(){var v=(document.getElementById('exIn').value||'').trim();if(!v)return;actD('ex_add','domain='+encodeURIComponent(v),null,'Eklendi');document.getElementById('exIn').value='';setTimeout(hlLoad,1800);}
function exDel(d,b){actD('ex_del','domain='+encodeURIComponent(d),b,'Silindi');setTimeout(hlLoad,1800);}
function autoDel(d,b){actD('auto_del','domain='+encodeURIComponent(d),b,'Silindi');setTimeout(hlLoad,1800);}
function ipLoad(retry){
  if(!document.getElementById('ipL')){setTimeout(ipLoad,200);return;}
  getD('ip_get',function(r){
    var el=document.getElementById('ipL'),ec=document.getElementById('ipCnt');if(!el)return;
    if(!r.ok||!r.data||!r.data.length){
      if(!retry){setTimeout(function(){ipLoad(true);},800);return;}
      el.innerHTML='<div class="empty">Liste bo&#351;</div>';if(ec)ec.textContent='0 IP';return;
    }
    if(ec)ec.textContent=r.data.length+' IP';
    el.innerHTML=r.data.map(function(ip){return '<div class="li"><span>'+ip+'</span>'+
      '<button class="danger" style="padding:3px 8px;font-size:11px" onclick="ipDel(\''+ip+'\',this)">Sil</button></div>';}).join('');
  });
  getD('nozapret_get',function(r){
    var el=document.getElementById('nzL'),ec=document.getElementById('nzCnt');if(!el)return;
    if(!r.ok||!r.data||!r.data.length){
      if(!retry){setTimeout(function(){ipLoad(true);},800);return;}
      el.innerHTML='<div class="empty">Liste bo&#351;</div>';if(ec)ec.textContent='0 IP';return;}
    if(ec)ec.textContent=r.data.length+' IP';
    el.innerHTML=r.data.map(function(ip){return '<div class="li"><span>'+ip+'</span>'+
      '<button class="danger" style="padding:3px 8px;font-size:11px" onclick="nzDel(\''+ip+'\',this)">'+(L?'Delete':'Sil')+'</button></div>';}).join('');
  });
  getD('ipset_active_get',function(r){
    var el=document.getElementById('ipaL'),ec=document.getElementById('ipaCnt');if(!el)return;
    if(!r.ok||!r.data||!r.data.length){el.innerHTML='<div class="empty">Aktif &#252;ye yok</div>';if(ec)ec.textContent='0 IP';return;}
    if(ec)ec.textContent=r.data.length+' IP';
    el.innerHTML=r.data.map(function(ip){return '<div class="li"><span>'+ip+'</span></div>';}).join('');
  });
}
function ipAdd(){var v=(document.getElementById('ipIn').value||'').trim();if(!v)return;actD('ip_add','ip='+encodeURIComponent(v),null,'Eklendi');document.getElementById('ipIn').value='';setTimeout(ipLoad,1800);}
function ipDel(ip,b){actD('ip_del','ip='+encodeURIComponent(ip),b,'Silindi');setTimeout(ipLoad,1800);}
function nzAdd(){var v=(document.getElementById('nzIn').value||'').trim();if(!v)return;actD('nozapret_add','ip='+encodeURIComponent(v),null,'Eklendi');document.getElementById('nzIn').value='';setTimeout(ipLoad,1800);}
function nzDel(ip,b){actD('nozapret_del','ip='+encodeURIComponent(ip),b,'Silindi');setTimeout(ipLoad,1800);}
function schedModeChange(){var m=document.getElementById('schedMode');var r=document.getElementById('schedDowRow');if(r)r.style.display=(m&&m.value==='weekly')?'':'none';}
function schedSet(){
  var v=(document.getElementById('schedT').value||'').trim();if(!v)return;
  var mode=document.getElementById('schedMode');
  var dow='*';
  if(mode&&mode.value==='weekly'){var d=document.getElementById('schedDow');dow=d?d.value:'1';}
  actD('sched_set','time='+encodeURIComponent(v)+'&dow='+encodeURIComponent(dow),null,'Zamanlama ayarlandi');
  setTimeout(function(){render('sched');},1800);
}
function schedDel(btn){act('sched_del',btn,'Kaldirildi');setTimeout(function(){render('sched');},1500);}
function opkgSchedSet(btn){
  var p=document.getElementById('opkgSchedPeriod');
  var period=p?p.value:'weekly';
  actD('opkg_sched_set','period='+encodeURIComponent(period),btn,L?'Schedule set':'Zamanlama ayarlandi');
  setTimeout(function(){render('sched');},1500);
}
function opkgSchedDel(btn){act('opkg_sched_del',btn,L?'Removed':'Kaldirildi');setTimeout(function(){render('sched');},1500);}
var _hcTimer=null;
var _hcAttempts=0;
var _hcMaxAttempts=60;
var _hcDotTimer=null;
function hcRun(btn){
  var el=document.getElementById('hcResult');
  var _hcStart=Date.now();
  if(_hcDotTimer){clearInterval(_hcDotTimer);_hcDotTimer=null;}
  if(_hcTimer){clearInterval(_hcTimer);_hcTimer=null;}
  function updateProgress(){
    if(!document.getElementById('hcResult'))return;
    var elapsed=Math.round((Date.now()-_hcStart)/1000);
    var el2=document.getElementById('hcResult');
    if(el2)el2.innerHTML='<div style="display:flex;flex-direction:column;align-items:center;justify-content:center;padding:32px;gap:16px">'+
      '<div style="display:flex;align-items:center;gap:4px;height:40px"><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.0s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.1s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.2s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.3s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.4s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.5s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.6s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.7s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.8s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.9s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:1.0s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:1.1s"></div></div>'+
      '<div style="font-size:1.1em;color:var(--fg)">'+(L?'Running diagnostics...':'Kontrol yap&#305;l&#305;yor...')+'</div>'+
      '<div style="font-size:0.85em;color:var(--muted)">'+(L?'Please wait &mdash; ':'L&#252;tfen bekleyin &mdash; ')+elapsed+'s</div>'+
      '</div>';
  }
  if(el)el.innerHTML='<div style="display:flex;flex-direction:column;align-items:center;justify-content:center;padding:32px;gap:16px"><div style="display:flex;align-items:center;gap:4px;height:40px"><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.0s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.1s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.2s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.3s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.4s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.5s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.6s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.7s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.8s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:0.9s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:1.0s"></div><div style="width:5px;background:#4d7fff;border-radius:3px;animation:hcBar 1.1s ease-in-out infinite;animation-delay:1.1s"></div></div><div style="font-size:1.1em;color:var(--fg)">'+(L?'Running diagnostics...':'Kontrol yap&#305;l&#305;yor...')+'</div><div style="font-size:0.85em;color:var(--muted)">'+(L?'Please wait':'L&#252;tfen bekleyin')+'</div></div>';
  if(btn){btn.disabled=true;}
  _hcAttempts=0;
  _hcDotTimer=setInterval(updateProgress,1000);
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=health_run'})
  .then(function(r){return r.json();})
  .then(function(){clearInterval(_hcTimer);_hcTimer=setInterval(function(){hcPoll(btn);},2000);})
  .catch(function(){clearInterval(_hcDotTimer);_hcDotTimer=null;if(el)el.innerHTML='<div style="color:var(--bad)">Ba&#287;lant&#305; hatas&#305;</div>';if(btn)btn.disabled=false;});
}
function hcPoll(btn){
  _hcAttempts++;
  if(_hcAttempts>_hcMaxAttempts){
    clearInterval(_hcTimer);
    clearInterval(_hcDotTimer);_hcDotTimer=null;
    if(btn)btn.disabled=false;
    var el=document.getElementById('hcResult');
    if(el)el.innerHTML='<div style="color:var(--bad)">Zaman asimi (120s). Kontrol tamamlanamadi.</div><div style="margin-top:12px"><button onclick="hcRun()">&#8635; Tekrar Dene</button></div>';
    return;
  }
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=health_get'})
  .then(function(r){return r.json();})
  .then(function(d){
    if(d.running){return;}
    clearInterval(_hcTimer);
    clearInterval(_hcDotTimer);_hcDotTimer=null;
    if(btn)btn.disabled=false;
    hcRender(d);
  }).catch(function(){clearInterval(_hcTimer);clearInterval(_hcDotTimer);_hcDotTimer=null;if(btn)btn.disabled=false;});
}
// ASCII T&#252;rk&#231;e → UTF-8 d&#246;n&#252;&#351;&#252;m&#252; (JSON/shell &#231;&#305;kt&#305;s&#305; i&#231;in global helper)
// Dil yardimcisi - S.lang'a gore TR veya EN doner
var L=false; // S yuklendikten sonra guncellenir
function t(tr,en){return L?(en||tr):(tr||en);}
function syncTheme(){
  var th=(S&&S.theme==='light')?'light':'dark';
  document.body.setAttribute('data-theme',th);
  var themeBadge=document.getElementById('themeBadge');
  if(themeBadge){
    themeBadge.onclick=function(){var nt=th==='dark'?'light':'dark';fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=theme_set&theme='+nt}).then(function(){setTimeout(fetchS,300);});};
    themeBadge.innerHTML=th==='dark'?'☀️':'&#127769;';
    themeBadge.title=th==='dark'?'A\u00e7\u0131k Temaya Ge\u00e7':'Koyu Temaya Ge\u00e7';
  }
}
function syncLang(){
  L=!!(S&&S.lang==='en');
  var labels=document.querySelectorAll('.item-label[data-tr]');
  for(var i=0;i<labels.length;i++){
    labels[i].textContent=L?labels[i].getAttribute('data-en'):labels[i].getAttribute('data-tr');
  }
  var secs=document.querySelectorAll('.sec[data-tr]');
  for(var j=0;j<secs.length;j++){
    secs[j].textContent=L?secs[j].getAttribute('data-en'):secs[j].getAttribute('data-tr');
  }
  var cpuLbl=document.getElementById('hLoadLabel');
  if(cpuLbl)cpuLbl.textContent=L?'CPU Load: ':'CPU Y\xfck\xfc: ';
  var refreshLbl=document.getElementById('refreshBtnLabel');
  if(refreshLbl)refreshLbl.textContent=L?'Refresh':'Yenile';
  var atickLbl=document.getElementById('atickLabel');
  if(atickLbl)atickLbl.textContent=L?'Auto refresh':'Otomatik yenileme';
  var dashPill=document.getElementById('dashLivePill');
  if(dashPill)dashPill.textContent=L?'Live':'Canl\u0131';
  var brandTitle=document.getElementById('brandTitle');
  if(brandTitle)brandTitle.textContent=L?'KZM2 Control Panel':'KZM2 Kontrol Paneli';
  document.title=L?'KZM2 Control Panel':'KZM2 Kontrol Paneli';
  var langBadge=document.getElementById('langBadge');
  if(langBadge){langBadge.onclick=function(){var nl=L?'tr':'en';fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=lang_set&lang='+nl}).then(function(){setTimeout(function(){hmConfCache=null;fetchS().then(function(){if(curV==='manualdpi'){var vals={http:(document.getElementById('mdpiHttp')||{}).value,tls:(document.getElementById('mdpiTls')||{}).value,quic:(document.getElementById('mdpiQuic')||{}).value,ptcp:(document.getElementById('mdpiPortsTcp')||{}).value,pudp:(document.getElementById('mdpiPortsUdp')||{}).value,tout:(document.getElementById('mdpiTcpOut')||{}).value,tin:(document.getElementById('mdpiTcpIn')||{}).value,uout:(document.getElementById('mdpiUdpOut')||{}).value,uin:(document.getElementById('mdpiUdpIn')||{}).value};render(curV);setTimeout(function(){if(vals.http!==undefined&&document.getElementById('mdpiHttp'))document.getElementById('mdpiHttp').value=vals.http||'';if(vals.tls!==undefined&&document.getElementById('mdpiTls'))document.getElementById('mdpiTls').value=vals.tls||'';if(vals.quic!==undefined&&document.getElementById('mdpiQuic'))document.getElementById('mdpiQuic').value=vals.quic||'';if(vals.ptcp!==undefined&&document.getElementById('mdpiPortsTcp'))document.getElementById('mdpiPortsTcp').value=vals.ptcp||'';if(vals.pudp!==undefined&&document.getElementById('mdpiPortsUdp'))document.getElementById('mdpiPortsUdp').value=vals.pudp||'';if(vals.tout!==undefined&&document.getElementById('mdpiTcpOut'))document.getElementById('mdpiTcpOut').value=vals.tout||'';if(vals.tin!==undefined&&document.getElementById('mdpiTcpIn'))document.getElementById('mdpiTcpIn').value=vals.tin||'';if(vals.uout!==undefined&&document.getElementById('mdpiUdpOut'))document.getElementById('mdpiUdpOut').value=vals.uout||'';if(vals.uin!==undefined&&document.getElementById('mdpiUdpIn'))document.getElementById('mdpiUdpIn').value=vals.uin||'';},120);}else{render(curV);}});},300);});};}
  if(langBadge)langBadge.innerHTML=L?'<img src="data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAzNiAzNiIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48cGF0aCBmaWxsPSIjMDAyNDdEIiBkPSJNMCA5LjA1OVYxM2g1LjYyOHpNNC42NjQgMzFIMTN2LTUuODM3ek0yMyAyNS4xNjRWMzFoOC4zMzV6TTAgMjN2My45NDFMNS42MyAyM3pNMzEuMzM3IDVIMjN2NS44Mzd6TTM2IDI2Ljk0MlYyM2gtNS42MzF6TTM2IDEzVjkuMDU5TDMwLjM3MSAxM3pNMTMgNUg0LjY2NEwxMyAxMC44Mzd6Ii8+PHBhdGggZmlsbD0iI0NGMUIyQiIgZD0iTTI1LjE0IDIzbDkuNzEyIDYuODAxYTMuOTc3IDMuOTc3IDAgMCAwIC45OS0xLjc0OUwyOC42MjcgMjNIMjUuMTR6TTEzIDIzaC0yLjE0MWwtOS43MTEgNi44Yy41MjEuNTMgMS4xODkuOTA5IDEuOTM4IDEuMDg1TDEzIDIzLjk0M1YyM3ptMTAtMTBoMi4xNDFsOS43MTEtNi44YTMuOTg4IDMuOTg4IDAgMCAwLTEuOTM3LTEuMDg1TDIzIDEyLjA1N1YxM3ptLTEyLjE0MSAwTDEuMTQ4IDYuMmEzLjk5NCAzLjk5NCAwIDAgMC0uOTkxIDEuNzQ5TDcuMzcyIDEzaDMuNDg3eiIvPjxwYXRoIGZpbGw9IiNFRUUiIGQ9Ik0zNiAyMUgyMXYxMGgydi01LjgzNkwzMS4zMzUgMzFIMzJhMy45OSAzLjk5IDAgMCAwIDIuODUyLTEuMTk5TDI1LjE0IDIzaDMuNDg3bDcuMjE1IDUuMDUyYy4wOTMtLjMzNy4xNTgtLjY4Ni4xNTgtMS4wNTJ2LS4wNThMMzAuMzY5IDIzSDM2di0yek0wIDIxdjJoNS42M0wwIDI2Ljk0MVYyN2MwIDEuMDkxLjQzOSAyLjA3OCAxLjE0OCAyLjhsOS43MTEtNi44SDEzdi45NDNsLTkuOTE0IDYuOTQxYy4yOTQuMDcuNTk4LjExNi45MTQuMTE2aC42NjRMMTMgMjUuMTYzVjMxaDJWMjFIMHpNMzYgOWEzLjk4MyAzLjk4MyAwIDAgMC0xLjE0OC0yLjhMMjUuMTQxIDEzSDIzdi0uOTQzbDkuOTE1LTYuOTQyQTQuMDAxIDQuMDAxIDAgMCAwIDMyIDVoLS42NjNMMjMgMTAuODM3VjVoLTJ2MTBoMTV2LTJoLTUuNjI5TDM2IDkuMDU5Vjl6TTEzIDV2NS44MzdMNC42NjQgNUg0YTMuOTg1IDMuOTg1IDAgMCAwLTIuODUyIDEuMmw5LjcxMSA2LjhINy4zNzJMLjE1NyA3Ljk0OUEzLjk2OCAzLjk2OCAwIDAgMCAwIDl2LjA1OUw1LjYyOCAxM0gwdjJoMTVWNWgtMnoiLz48cGF0aCBmaWxsPSIjQ0YxQjJCIiBkPSJNMjEgMTVWNWgtNnYxMEgwdjZoMTV2MTBoNlYyMWgxNXYtNnoiLz48L3N2Zz4=" width="24" height="24" style="vertical-align:middle"> EN':'<img src="data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAzNiAzNiIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB4bWxuczp4bGluaz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94bGluayI+PHBhdGggZmlsbD0iI0UzMDkxNyIgZD0iTTM2IDI3YTQgNCAwIDAgMS00IDRINGE0IDQgMCAwIDEtNC00VjlhNCA0IDAgMCAxIDQtNGgyOGE0IDQgMCAwIDEgNCA0djE4eiIvPjxwYXRoIGZpbGw9IiNFRUUiIGQ9Ik0xNiAyNGE2IDYgMCAxIDEgMC0xMmMxLjMxIDAgMi41Mi40MjUgMy41MDcgMS4xMzhBNy4zMzIgNy4zMzIgMCAwIDAgMTQgMTAuNjQ3QTcuMzUzIDcuMzUzIDAgMCAwIDYuNjQ3IDE4QTcuMzUzIDcuMzUzIDAgMCAwIDE0IDI1LjM1NGMyLjE5NSAwIDQuMTYtLjk2NyA1LjUwNy0yLjQ5MkE1Ljk2MyA1Ljk2MyAwIDAgMSAxNiAyNHptMy45MTMtNS43N2wyLjQ0LjU2MmwuMjIgMi40OTNsMS4yODgtMi4xNDZsMi40NC41NjFsLTEuNjQ0LTEuODg4bDEuMjg3LTIuMTQ3bC0yLjMwMy45OGwtMS42NDQtMS44ODlsLjIyIDIuNDk0eiIvPjwvc3ZnPg==" width="24" height="24" style="vertical-align:middle"> TR';
}
function fixTR(s){if(!s)return s;
  return s.replace(/Calisiyor/g,'&#199;al&#305;&#351;&#305;yor').replace(/Calismiyor/g,'&#199;al&#305;&#351;m&#305;yor')
          .replace(/Durdurulmus/g,'Durdurulmu&#351;').replace(/durduruldu/g,'durduruldu')
          .replace(/Dogrulandi/g,'Do&#287;ruland&#305;').replace(/Farkli/g,'Farkl&#305;')
          .replace(/Varsayilan/g,'Varsay&#305;lan').replace(/butunlugu/g,'b&#252;t&#252;nl&#252;&#287;&#252;')
          .replace(/Butunlugu/g,'B&#252;t&#252;nl&#252;&#287;&#252;').replace(/Surum durumu/g,'S&#252;r&#252;m durumu')
          .replace(/surum/g,'s&#252;r&#252;m').replace(/Acik/g,'A&#231;&#305;k').replace(/Kapali/g,'Kapal&#305;')
          .replace(/Guncelleme/g,'G&#252;ncelleme').replace(/Guncel/g,'G&#252;ncel')
          .replace(/Saglikli/g,'Sa&#287;l&#305;kl&#305;').replace(/Saglik/g,'Sa&#287;l&#305;k').replace(/sagligi/g,'sa&#287;l&#305;&#287;&#305;').replace(/hatali/g,'hatal&#305;').replace(/hatasi/g,'hatas&#305;').replace(/Tanilama/g,'Tan&#305;lama')
          .replace(/Anlik/g,'Anl&#305;k').replace(/Esik/g,'E&#351;ik').replace(/esigi/g,'e&#351;i&#287;i')
          .replace(/Ardisik/g,'Ard&#305;&#351;&#305;k').replace(/Arayuz/g,'Aray&#252;z')
          .replace(/Baglanti/g,'Ba&#287;lant&#305;').replace(/baglanti/g,'ba&#287;lant&#305;')
          .replace(/Baslatildi/g,'Ba&#351;lat&#305;ld&#305;').replace(/baslatildi/g,'ba&#351;lat&#305;ld&#305;')
          .replace(/Kaldirildi/g,'Kald&#305;r&#305;ld&#305;').replace(/kaldirildi/g,'kald&#305;r&#305;ld&#305;')
          .replace(/Yeniden baslatildi/g,'Yeniden ba&#351;lat&#305;ld&#305;')
          .replace(/Zapret2 baslatildi/g,'Zapret2 ba&#351;lat&#305;ld&#305;')
          .replace(/Profil.*ayarlandi/g,function(m){return m.replace(/ayarlandi/,'ayarland&#305;');})
          .replace(/kontrolu/g,'kontrol&#252;').replace(/tutarliligi/g,'tutarl&#305;l&#305;&#287;&#305;')
          .replace(/erisimi/g,'eri&#351;imi').replace(/Yuk\b/g,'Y&#252;k').replace(/yuk\b/g,'y&#252;k')
          .replace(/Bos\b/g,'Bo&#351;').replace(/bos\b/g,'bo&#351;').replace(/MB bos/g,'MB bo&#351;')
          .replace(/Onizleme/g,'&#214;nizleme').replace(/onizleme/g,'&#246;nizleme')
          .replace(/Yerel cozucu/g,'Yerel DNS &#199;&#246;z&#252;c&#252;').replace(/resolver/g,'DNS &#199;&#246;z&#252;c&#252;')
          .replace(/unknown/g,'bilinmiyor').replace(/Unknown/g,'Bilinmiyor')
          .replace(/Dogrulandi/g,'Do&#287;ruland&#305;').replace(/Eslesmiyor/g,'E&#351;le&#351;miyor')
          .replace(/Dogrulanmamis/g,'Do&#287;rulanmam&#305;&#351;').replace(/Dogrudan Erisim/g,'Do&#287;rudan Eri&#351;im')
          .replace(/Dogrudan erisim/g,'Do&#287;rudan eri&#351;im').replace(/butunlugu/g,'b&#252;t&#252;nl&#252;&#287;&#252;')
          .replace(/Butunlugu/g,'B&#252;t&#252;nl&#252;&#287;&#252;').replace(/surum durumu/g,'s&#252;r&#252;m durumu')
          .replace(/Henuz/g,'Hen&#252;z').replace(/henuz/g,'hen&#252;z')
          .replace(/uyarilari/g,'uyar&#305;lar&#305;').replace(/bildirimleri/g,'bildirimleri')
          .replace(/gonder/g,'g&#246;nder').replace(/yonet/g,'y&#246;net')
          .replace(/Erisim/g,'Eri&#351;im').replace(/erisim/g,'eri&#351;im')
          .replace(/kullanilan/g,'kullan&#305;lan').replace(/Kullanilan/g,'Kullan&#305;lan')
          .replace(/Sicakligi/g,'S&#305;cakl&#305;&#287;&#305;').replace(/sicakligi/g,'s&#305;cakl&#305;&#287;&#305;')
          .replace(/Sistem yuk/g,'Sistem y&#252;k')
          .replace(/Dogru yerde mi/g,'Do&#287;ru yerde mi')
          .replace(/Kararli/g,'Kararl&#305;').replace(/kararli/g,'kararl&#305;')
          .replace(/Kararsiz/g,'Karars&#305;z').replace(/kararsiz/g,'karars&#305;z')
          .replace(/All Interfaces/g,'T&#252;m Aray&#252;zler')
          .replace(/Tum Arayuzler/g,'T&#252;m Aray&#252;zler')
}
function hcRender(d){
  var el=document.getElementById('hcResult');
  if(!el)return;
  if(!d||!d.ok){el.innerHTML='<div style="color:var(--bad)">'+(d&&d.msg?d.msg:(L?'Error':'Hata'))+'</div>';return;}
  var sc=parseFloat(d.score||0);
  var scClr=sc>=9.5?'var(--good)':sc>=8.5?'var(--good)':sc>=7?'var(--warn)':sc>=5?'#e8a020':'var(--bad)';
  var scLbl=sc>=9.5?(L?'EXCELLENT':'M&#220;KEMMEL'):sc>=8.5?(L?'VERY GOOD':'&#199;OK &#304;Y&#304;'):sc>=7?(L?'GOOD':'&#304;Y&#304;'):sc>=5?(L?'FAIR':'ORTA'):(L?'POOR':'ZAYIF');
  var h='<div style="background:var(--card);border:1px solid var(--border);border-radius:10px;padding:14px 16px;margin-bottom:16px">'+
    '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:8px">'+
      '<span style="font-weight:600">'+(L?'System Score':'Sistem Skoru')+'</span>'+
      '<span style="font-size:1.4em;font-weight:700;color:'+scClr+'">'+d.score+' / 10 <span style="font-size:0.65em">'+scLbl+'</span></span>'+
    '</div>'+
    '<div style="background:var(--bg);border-radius:4px;height:8px;overflow:hidden">'+
      '<div style="height:100%;width:'+(sc*10)+'%;background:'+scClr+';border-radius:4px"></div>'+
    '</div>'+
    '<div style="display:flex;flex-wrap:wrap;gap:10px 16px;margin-top:8px;font-size:0.82em;color:var(--muted)">'+
      '<span style="color:var(--good);white-space:nowrap">&#10003; PASS: '+d.pass+'</span>'+
      '<span style="color:var(--warn);white-space:nowrap">&#9888; WARN: '+d.warn+'</span>'+
      '<span style="color:var(--bad);white-space:nowrap">&#10007; FAIL: '+d.fail+'</span>'+
      '<span style="white-space:nowrap">INFO: '+d.info+'</span>'+
      (d.dns_mode?'<span style="flex:1 1 100%;min-width:0;overflow-wrap:anywhere;word-break:break-word">DNS: <b>'+d.dns_mode+'</b>'+(d.dns_providers?' • '+d.dns_providers:'')+'</span>':'')+
    '</div>'+
  '</div>';
  var secs=L?{net:'\u{1F310} Network & DNS',sys:'\u{1F4BB} System',svc:'\u2699 Services'}
             :{net:'\u{1F310} A&#287; & DNS',sys:'\u{1F4BB} Sistem',svc:'\u2699 Servisler'};
  var secOrder=['net','sys','svc'];
  var byS={net:[],sys:[],svc:[]};
  (d.items||[]).forEach(function(it){if(byS[it.sec])byS[it.sec].push(it);});
  secOrder.forEach(function(sk){
    var items=byS[sk]; if(!items||!items.length)return;
    h+='<div style="background:var(--card);border:1px solid var(--border);border-radius:10px;margin-bottom:12px;overflow:hidden">'+
      '<div style="padding:10px 16px;border-bottom:1px solid var(--border);font-weight:600;font-size:0.9em">'+secs[sk]+'</div>'+
      '<table style="width:100%;border-collapse:collapse;font-size:0.88em">';
    items.forEach(function(it,i){
      var stClr=it.st==='PASS'?'var(--good)':it.st==='FAIL'?'var(--bad)':it.st==='WARN'?'var(--warn)':'var(--muted)';
      var stIco=it.st==='PASS'?'&#10003;':it.st==='FAIL'?'&#10007;':it.st==='WARN'?'&#9888;':'&#8226;';
      h+='<tr style="border-top:'+(i?'1px solid var(--border)':'none')+'">'+
        '<td style="padding:7px 10px;color:var(--muted);white-space:nowrap">'+fixTR(it.lbl)+'</td>'+
        '<td style="padding:7px 8px;color:var(--fg);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:0;width:100%">'+fixTR(it.val)+'</td>'+
        '<td style="padding:7px 10px;text-align:right;color:'+stClr+';font-weight:600;white-space:nowrap">'+stIco+' '+it.st+'</td>'+
      '</tr>';
    });
    h+='</table></div>';
  });
  el.innerHTML=h+'<div style="margin-top:12px"><button onclick="hcRun()">&#8635; '+(L?'Refresh':'Yenile')+'</button></div>';
}
function hmRestart(btn){
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=healthmon_restart'})
  .then(function(r){return r.json();})
  .then(function(res){
    toast(res.msg||(L?'HM restarted':'HM yeniden baslatildi'),!!res.ok);
    if(btn){btn.disabled=false;btn.innerHTML=btn._o;}
    hmConfCache=null;
    fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=status_refresh'})
    .then(function(){return fetchS();})
    .then(function(){quickPoll(5,2000);});
  })
  .catch(function(){toast('Ba&#287;lant&#305; hatas&#305;',false);if(btn){btn.disabled=false;btn.innerHTML=btn._o;}});
}
function zapretAct(action,btn,msg){
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action='+action})
  .then(function(r){return r.json();})
  .then(function(res){
    toast(res.msg||msg,!!res.ok);
    if(btn){btn.disabled=false;btn.innerHTML=btn._o;}
    fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=status_refresh'})
    .then(function(){return fetchS();})
    .then(function(){render(curV);});
  }).catch(function(){toast('Ba&#287;lant&#305; hatas&#305;',false);if(btn){btn.disabled=false;btn.innerHTML=btn._o;}});
}
function tgStart(btn){
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=tg_start'})
  .then(function(r){return r.json();})
  .then(function(res){
    toast(res.msg||'Bot ba&#351;lat&#305;ld&#305;',!!res.ok);
    if(btn){btn.disabled=false;btn.innerHTML=btn._o;}
    // status_refresh -> fetchS -> render
    fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=status_refresh'})
    .then(function(){return fetchS();})
    .then(function(){render('telegram');});
  }).catch(function(){toast('Ba&#287;lant&#305; hatas&#305;',false);if(btn){btn.disabled=false;btn.innerHTML=btn._o;}});
}
function tgStop(btn){
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=tg_stop'})
  .then(function(r){return r.json();})
  .then(function(res){
    toast(res.msg||'Bot durduruldu',!!res.ok);
    if(btn){btn.disabled=false;btn.innerHTML=btn._o;}
    fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=status_refresh'})
    .then(function(){return fetchS();})
    .then(function(){render('telegram');});
  }).catch(function(){toast('Ba&#287;lant&#305; hatas&#305;',false);if(btn){btn.disabled=false;btn.innerHTML=btn._o;}});
}
function tgRestart(btn){
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=tg_restart'})
  .then(function(r){return r.json();})
  .then(function(res){
    toast(res.msg||(L?'Bot restarted':'Bot yeniden baslatildi'),!!res.ok);
    if(btn){btn.disabled=false;btn.innerHTML=btn._o;}
    fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=status_refresh'})
    .then(function(){return fetchS();})
    .then(function(){render('telegram');});
  }).catch(function(){toast('Ba&#287;lant&#305; hatas&#305;',false);if(btn){btn.disabled=false;btn.innerHTML=btn._o;}});
}
function bkDoSettingsBackup(btn){
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=backup_settings'})
  .then(function(r){return r.json();})
  .then(function(res){
    if(btn){btn.disabled=false;btn.innerHTML=btn._o||btn.innerHTML;}
    toast(res.msg||(L?'Backed up':'Yedeklendi'),!!res.ok);
    if(res.ok)bkSettingsList(null);
  }).catch(function(){if(btn){btn.disabled=false;btn.innerHTML=btn._o||btn.innerHTML;}});
}
function bkDoIpsetBackup(btn){
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=ipset_backup'})
  .then(function(r){return r.json();})
  .then(function(res){
    if(btn){btn.disabled=false;btn.innerHTML=btn._o||btn.innerHTML;}
    toast(res.msg||(L?'IPSET Backed up':'IPSET Yedeklendi'),!!res.ok);
    if(res.ok)bkIpsetList(null);
  }).catch(function(){if(btn){btn.disabled=false;btn.innerHTML=btn._o||btn.innerHTML;}});
}
function bkSettingsClean(btn){
  if(!confirm(L?'Delete all Zapret2 settings backups?':'Tum Zapret2 ayar yedekleri silinsin mi?'))return;
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=settings_clean'})
  .then(function(r){return r.json();})
  .then(function(res){
    if(btn){btn.disabled=false;btn.innerHTML=btn._o||btn.innerHTML;}
    toast(res.msg||(L?'Done':'Tamam'),!!res.ok);
    bkSettingsList(null);
  }).catch(function(){if(btn){btn.disabled=false;btn.innerHTML=btn._o||btn.innerHTML;}});
}
function bkIpsetClean(btn){
  if(!confirm(L?'Delete IPSET history backups?':'IPSET gecmis yedekleri silinsin mi?'))return;
  if(btn){btn._o=btn.innerHTML;btn.disabled=true;btn.innerHTML='<span class="spinner"></span>';}
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=ipset_history_clean'})
  .then(function(r){return r.json();})
  .then(function(res){
    if(btn){btn.disabled=false;btn.innerHTML=btn._o||btn.innerHTML;}
    toast(res.msg||(L?'Done':'Tamam'),!!res.ok);
    bkIpsetList(null);
  }).catch(function(){if(btn){btn.disabled=false;btn.innerHTML=btn._o||btn.innerHTML;}});
}
function ccRun(){
  fetch('/cgi-bin/action.sh',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'action=component_check'})
  .then(function(r){return r.json();})
  .then(function(res){
    var el=document.getElementById('ccResult');
    if(!el)return;
    var lines=(res.msg||'').split('|');
    var h='<div style="font-family:monospace;font-size:13px;line-height:1.8;text-align:left;padding:8px 0">';
    lines.forEach(function(line){
      if(!line)return;
      if(line==='SEP'){h+='<div style="border-top:1px solid var(--border);margin:10px 0"></div>';return;}
      var isResult=line.indexOf('RESULT ')===0;
      var l=isResult?line.slice(7):line;
      var pfx=l.split(' ')[0];
      var rest=l.indexOf(' ')>=0?l.slice(pfx.length+1):l;
      var pc='var(--fg)',tc='var(--fg)';
      if(pfx==='PASS'){pc='var(--good)';}
      else if(pfx==='FAIL'){pc='var(--bad)';tc='var(--bad)';}
      else if(pfx==='WARN'){pc='var(--warn)';tc='var(--warn)';}
      else if(pfx==='INFO'){pc='var(--info)';}
      else{rest=l;pfx='';}
      var pfxHtml=pfx?'<span style="color:'+pc+';font-weight:600">'+pfx+'</span> ':'';
      if(isResult){
        var bgCol=pfx==='PASS'?'rgba(39,174,96,0.12)':pfx==='FAIL'?'rgba(231,76,60,0.12)':'rgba(231,152,0,0.12)';
        var brCol=pfx==='PASS'?'rgba(39,174,96,0.35)':pfx==='FAIL'?'rgba(231,76,60,0.35)':'rgba(231,152,0,0.35)';
        var restTr=rest;
        if(!L){
          restTr=restTr
            .replace('Tum gerekli bilesenler mevcut!','T&#252;m gerekli bile&#351;enler mevcut!')
            .replace('Kritik bilesenlerde sorun var!','Kritik bile&#351;enlerde sorun var!')
            .replace('Zorunlu bilesenler tamam, opsiyonel eksikler var.','Zorunlu bile&#351;enler tamam, opsiyonel eksikler var.');
        } else {
          restTr=restTr
            .replace('Tum gerekli bilesenler mevcut!','All required components present!')
            .replace('Kritik bilesenlerde sorun var!','Critical components have issues!')
            .replace('Zorunlu bilesenler tamam, opsiyonel eksikler var.','Required components OK, optional ones missing.');
        }
        h+='<div style="margin-top:16px;background:'+bgCol+';border:1px solid '+brCol+';border-radius:8px;padding:12px 16px;display:flex;align-items:center;gap:10px">'+
          '<span style="font-size:1.3em;color:'+pc+'">&#9888;</span>'+
          '<span style="color:'+pc+';font-size:14px;font-weight:500">'+pfxHtml+restTr+'</span></div>';
      }
      else{
        var restLbl=rest;
        if(!L){
          restLbl=restLbl
            .replace('IPv6 deste&#287;i (ip6tables)','IPv6 deste&#287;i (ip6tables)')
            .replace('curl (g&#252;ncelleme i&#231;in)','curl (g&#252;ncelleme i&#231;in)')
            .replace('Netfilter Queue mod&#252;lleri','Netfilter Queue mod&#252;lleri')
            .replace('Netfilter Xtables-addons geni&#351;letme paketleri','Netfilter Xtables-addons geni&#351;letme paketleri')
            .replace('Trafik Kontrol (tc) kernel mod&#252;lleri','Trafik Kontrol (tc) kernel mod&#252;lleri')
            .replace('Trafik Kontrol (tc) bulunamad&#305;','Trafik Kontrol (tc) bulunamad&#305;')
            .replace('Harici depolama - USB (/opt bagli)','Harici depolama - USB (/opt ba&#287;l&#305;)')
            .replace('Dahili depolama - eMMC/NAND (/opt bagli)','Dahili depolama - eMMC/NAND (/opt ba&#287;l&#305;)')
            .replace('Dahili depolama - eMMC/SD (/opt bagli)','Dahili depolama - eMMC/SD (/opt ba&#287;l&#305;)')
            .replace('Dahili depolama - NVMe SSD (/opt bagli)','Dahili depolama - NVMe SSD (/opt ba&#287;l&#305;)')
            .replace('Dahili flash (/opt bagli) - USB surucusu onerilir','Dahili flash (/opt ba&#287;l&#305;) - USB s&#252;r&#252;c&#252;s&#252; &#246;nerilir')
            .replace('Dahili flash - USB surucusu onerilir','Dahili flash - USB s&#252;r&#252;c&#252;s&#252; &#246;nerilir')
            .replace('/opt tmpfs - yeniden baslatmada kayip','/opt tmpfs - yeniden ba&#351;lat&#305;lmada kay&#305;p')
            .replace('Depolama (/opt bagli)','Depolama (/opt ba&#287;l&#305;)')
            .replace('Depolama - onerilir (USB/eMMC)','Depolama - &#246;nerilir (USB/eMMC)')
            .replace('ipset bitmap:port kernel mod&#252;l&#252;','ipset bitmap:port kernel mod&#252;l&#252;')
            .replace('ipset bitmap:port mod&#252;l&#252; eksik - Zapret2 port kurallari eklenemez','ipset bitmap:port mod&#252;l&#252; eksik - Zapret2 port kurallari eklenemez');
        } else {
          restLbl=restLbl
            .replace('IPv6 deste&#287;i (ip6tables)','IPv6 support (ip6tables)')
            .replace('IPv6 deste&#287;i (ip6tables) bulunamad&#305;','IPv6 support (ip6tables) not found')
            .replace('curl (g&#252;ncelleme i&#231;in)','curl (for updates)')
            .replace('wget (g&#252;ncelleme i&#231;in)','wget (for updates)')
            .replace('curl/wget bulunamad&#305;','curl/wget not found')
            .replace('Netfilter Queue mod&#252;lleri','Netfilter Queue modules')
            .replace('Netfilter Queue mod&#252;lleri bulunamad&#305;','Netfilter Queue modules not found')
            .replace('Netfilter Xtables-addons geni&#351;letme paketleri','Netfilter Xtables-addons extension packages')
            .replace('Netfilter Xtables-addons bulunamad&#305;','Netfilter Xtables-addons not found')
            .replace('Trafik Kontrol (tc) kernel mod&#252;lleri','Traffic Control (tc) kernel modules')
            .replace('Trafik Kontrol (tc) bulunamad&#305;','Traffic Control (tc) not found')
            .replace('Harici depolama - USB (/opt bagli)','External storage - USB (/opt mounted)')
            .replace('Dahili depolama - eMMC/NAND (/opt bagli)','Internal storage - eMMC/NAND (/opt mounted)')
            .replace('Dahili depolama - eMMC/SD (/opt bagli)','Internal storage - eMMC/SD (/opt mounted)')
            .replace('Dahili depolama - NVMe SSD (/opt bagli)','Internal storage - NVMe SSD (/opt mounted)')
            .replace('Dahili flash (/opt bagli) - USB surucusu onerilir','Internal flash (/opt mounted) - USB drive recommended')
            .replace('Dahili flash - USB surucusu onerilir','Internal flash - USB drive recommended')
            .replace('/opt tmpfs - yeniden baslatmada kayip','/opt tmpfs - lost on reboot')
            .replace('Depolama (/opt bagli)','Storage (/opt mounted)')
            .replace('Depolama - onerilir (USB/eMMC)','Storage - recommended (USB/eMMC)')
            .replace('ipset bitmap:port kernel mod&#252;l&#252;','ipset bitmap:port kernel module')
            .replace('ipset bitmap:port mod&#252;l&#252; eksik - Zapret2 port kurallari eklenemez','ipset bitmap:port module missing - Zapret2 port rules may not apply');
        }
        h+='<div>'+pfxHtml+'<span style="color:'+tc+'">'+restLbl+'</span></div>';
      }
    });
    h+='</div>';
    el.innerHTML=h;
  }).catch(function(){
    var el=document.getElementById('ccResult');
    if(el)el.innerHTML='<div style="color:var(--bad)">Hata</div>';
  });
}
function bkLoad(){bkSettingsList(null);bkIpsetList(null);}
function bkSettingsList(btn){
  if(btn)btn.disabled=true;
  getD('settings_list',function(r){
    if(btn)btn.disabled=false;
    var el=document.getElementById('bkSetList'),er=document.getElementById('bkSetRestore');
    if(!el)return;
    if(!r.ok||!r.data||!r.data.length){
      el.innerHTML='<div class="sub">'+(L?'No backup found':'Yedek bulunamadi')+'</div>';
      if(er)er.innerHTML='<div class="sub">'+(L?'No backup found':'Yedek bulunamadi')+'</div>';
      return;
    }
    var html='<div style="font-size:11px;color:#888;margin-bottom:4px">'+(L?'Last 10 backups:':'Son 10 yedek:')+'</div>';
    var rhtml='';
    r.data.forEach(function(f){
      html+='<div class="li" style="font-size:11px"><span style="flex:1;word-break:break-all">'+f.name+'</span></div>';
      rhtml+='<div class="li" style="margin-bottom:4px"><span style="font-size:11px;flex:1;word-break:break-all">'+f.name+'</span>'+
        '<button style="padding:3px 8px;font-size:11px" onclick="bkSetRestore(\''+f.path.replace(/\'/g,"\\'")+'\',this)">&#9850; '+(L?'Restore':'Geri Y&#252;kle')+'</button></div>';
    });
    el.innerHTML=html;
    if(er)er.innerHTML=rhtml;
  });
}
function bkSetRestore(path,btn){
  var scope=document.getElementById('bkScope');
  var s=scope?scope.value:'1';
  if(!confirm(L?'Restore backup? (Scope:'+s+')':'Geri yuklensin mi? (Kapsam:'+s+')'))return;
  if(btn)btn.disabled=true;
  actD('settings_restore','file='+encodeURIComponent(path)+'&scope='+s,btn,'Geri yuklendi');
}
function bkIpsetList(btn){
  if(btn)btn.disabled=true;
  getD('ipset_list',function(r){
    if(btn)btn.disabled=false;
    var el=document.getElementById('bkIpList'),er=document.getElementById('bkIpRestore');
    if(!el)return;
    if(!r.ok||!r.files){
      el.innerHTML='<div class="sub">'+(L?'No backup found':'Yedek bulunamadi')+'</div>';
      if(er)er.innerHTML='<div class="sub">'+(L?'No backup found':'Yedek bulunamadi')+'</div>';
      return;
    }
    var files=r.files?r.files.split('|').filter(function(x){return x;}):[]; 
    if(!files.length){
      el.innerHTML='<div class="sub">'+(L?'No backup found':'Yedek bulunamadi')+'</div>';
      if(er)er.innerHTML='<div class="sub">'+(L?'No backup found':'Yedek bulunamadi')+'</div>';
      return;
    }
    var html='<div style="font-size:11px;color:#888;margin-bottom:4px">'+(L?'Current backups:':'Mevcut Yedekler:')+'</div>';
    var rhtml='';
    files.forEach(function(f){
      var parts=f.split(':');var name=parts[0];var cnt=parts[1]||'?';
      html+='<div class="li" style="font-size:11px"><span style="flex:1">'+name+'</span><span style="color:#888">'+cnt+' '+(L?'lines':'sat&#305;r')+'</span></div>';
      rhtml+='<div class="li" style="margin-bottom:4px"><span style="font-size:11px;flex:1">'+name+'</span>'+
        '<button style="padding:3px 8px;font-size:11px" onclick="bkIpRestore(\''+name+'\',this)">&#9850; '+(L?'Restore':'Geri Y&#252;kle')+'</button></div>';
    });
    if(r.history){
      var hist=r.history.split('|').filter(function(x){return x;});
      if(hist.length){
        html+='<div style="font-size:11px;color:#888;margin-top:8px;margin-bottom:4px">'+(L?'History (last 5):':'Ge&#231;mi&#351; (son 5):')+'</div>';
        hist.forEach(function(h){html+='<div class="li" style="font-size:11px;color:var(--fg)">'+h+'</div>';});
      }
    }
    el.innerHTML=html;
    if(er)er.innerHTML=rhtml;
  });
}
function bkIpRestore(fname,btn){
  if(!confirm(fname+' geri yuklensin mi?'))return;
  if(btn)btn.disabled=true;
  actD('ipset_restore','file='+encodeURIComponent(fname),btn,'Geri yuklendi');
}
var clCache=null;
var clCurTag=null;
function clLoad(){
  var el=document.getElementById('clList');
  if(!el)return;
  if(clCache){clBuildList();return;}
  el.innerHTML='<div class="sub">Y&#252;kleniyor...</div>';
  fetch('https://api.github.com/repos/RevolutionTR/keenetic-zapret2-manager/releases?per_page=100')
  .then(function(r){return r.json();})
  .then(function(data){
    if(!Array.isArray(data)||!data.length){
      el.innerHTML='<div class="sub">'+(L?'Could not load releases.':'S&#252;r&#252;mler y&#252;klenemedi.')+'</div>';
      return;
    }
    clCache=data;
    clBuildList();
  })
  .catch(function(){
    if(el)el.innerHTML='<div class="sub">'+(L?'Connection error.':'Ba&#287;lant&#305; hatas&#305;.')+'</div>';
  });
}
function clBuildList(){
  var el=document.getElementById('clList');
  if(!el||!clCache)return;
  var cur=S?S.kzm_version:'';
  var h='<h3>'+(L?'Versions':'S&#252;r&#252;mler')+'</h3><div style="display:flex;flex-direction:column;align-items:flex-start;gap:4px;margin-top:8px">';
  clCache.forEach(function(r){
    var tag=r.tag_name||r.name||'';
    var isCur=tag===cur;
    var isActive=tag===clCurTag;
    h+='<div onclick="clSelect(\''+tag+'\')" style="display:inline-block;max-width:100%;cursor:pointer;padding:6px 10px;border-radius:7px;font-size:12.5px;box-sizing:border-box;'+
      (isActive?'background:rgba(75,125,255,.2);border:1px solid rgba(75,125,255,.5);':'border:1px solid transparent;')+
      '">'+tag+(isCur?' <span style="color:var(--good);font-size:10px">&#9679; '+(L?'Installed':'Kurulu')+'</span>':'')+'</div>';
  });
  h+='</div>';
  el.innerHTML=h;
  // ilk acilista latest goster
  if(!clCurTag&&clCache.length){clSelect(clCache[0].tag_name||clCache[0].name);}
}
function clSelect(tag){
  clCurTag=tag;
  clBuildList();
  var rel=clCache?clCache.filter(function(r){return (r.tag_name||r.name)===tag;})[0]:null;
  var el=document.getElementById('clBody');
  if(!el)return;
  if(!rel){el.innerHTML='<div class="sub">'+(L?'Not found.':'Bulunamadi.')+'</div>';return;}
  el.innerHTML='<div style="font-size:13.5px;line-height:1.7">'+clFmt(rel.body||'')+'</div>';
  el.scrollTop=0;
}
function clFmt(md){
  if(!md)return '';
  return md
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
    .replace(/^## (.+)$/gm,'<div style="font-size:16px;font-weight:700;margin:16px 0 6px;color:var(--text)">$1</div>')
    .replace(/^### (.+)$/gm,'<div style="font-size:13px;font-weight:700;margin:12px 0 4px;color:var(--accent)">$1</div>')
    .replace(/\*\*([^*]+)\*\*/g,'<b>$1</b>')
    .replace(/^&gt; (.+)$/gm,'<div style="padding:4px 10px;margin:2px 0;border-left:3px solid var(--accent);color:var(--muted);font-size:12.5px">$1</div>')
    .replace(/^&gt;$/gm,'')
    .replace(/^---$/gm,'<hr style="border:none;border-top:1px solid var(--line);margin:12px 0"/>')
    .replace(/^- (.+)$/gm,'<div style="padding:2px 0 2px 12px;color:var(--text)">&#8226; $1</div>')
    .replace(/^(?!<div|<hr)(.+)$/gm,'<div style="color:var(--muted);font-size:12px;margin:2px 0">$1</div>')
    .replace(/\n{2,}/g,'<div style="height:6px"></div>');
}
var docsCache={};
var docsCurKey=null;
var DOCS_BASE='https://raw.githubusercontent.com/RevolutionTR/keenetic-zapret2-manager/main/docs/';
var DOCS_ROOT='https://raw.githubusercontent.com/RevolutionTR/keenetic-zapret2-manager/main/';
function docsInit(){
  if(docsCurKey){docsSelect(docsCurKey,null);}
}
function docsSelect(key,file,base){
  docsCurKey=key;
  document.querySelectorAll('[id^="docNav_"]').forEach(function(el){
    el.style.background='';el.style.border='1px solid transparent';
  });
  var navEl=document.getElementById('docNav_'+key);
  if(navEl){navEl.style.background='rgba(75,125,255,.2)';navEl.style.border='1px solid rgba(75,125,255,.5)';}
  var body=document.getElementById('docsBody');
  if(!body)return;
  if(docsCache[key]){body.innerHTML=docsFmt(docsCache[key]);body.scrollTop=0;return;}
  body.innerHTML='<div class="sub">&#8593; Y\u00fckleniyor...</div>';
  if(!file){body.innerHTML='<div class="sub">Hata.</div>';return;}
  var fetchUrl=(base||DOCS_BASE)+file;
  fetch(fetchUrl)
  .then(function(r){if(!r.ok)throw new Error(r.status);return r.text();})
  .then(function(txt){docsCache[key]=txt;body.innerHTML=docsFmt(txt);body.scrollTop=0;})
  .catch(function(){body.innerHTML='<div class="sub">'+(L?'Could not load document.':'Belge y\u00fcklenemedi.')+'</div>';});
}
function docsFmt(md){
  if(!md)return '';
  var REPO_RAW='https://raw.githubusercontent.com/RevolutionTR/keenetic-zapret2-manager/main';
  // Img taglari: relative src -> full GitHub raw URL, blocks'a al
  // Kod bloklarini once isle (inline code regex ile bozulmasin)
  // Blockquote icindeki kod bloklari: "> ```...``` " formatini normallestirelim
  md=md.replace(/((?:^> [^\n]*\n)*)(> ```[\w]*\n)((?:^> [^\n]*\n)*?)(^> ```)/gm,function(m){
    return m.replace(/^> ?/gm,'');
  });
  var blocks=[];
  // Img taglari HTML-escape'den once isle
  md=md.replace(/<img\s+src="([^"]+)"([^>]*)>/g,function(m,src,rest){
    var fullSrc=src.match(/^https?:\/\//)?src:REPO_RAW+src;
    var idx=blocks.length;
    blocks.push('<img src="'+fullSrc+'" style="max-width:100%;border-radius:7px;margin:8px 0;display:block"'+rest+'>');
    return '\x00BLOCK'+idx+'\x00';
  });
  md=md.replace(/```[\w]*\n([\s\S]*?)```/gm,function(m,code){
    var idx=blocks.length;
    var clean=code.replace(/^> ?/gm,''); // kalan > prefixleri temizle
    blocks.push('<pre style="background:rgba(0,0,0,.25);padding:10px 12px;border-radius:7px;font-size:11.5px;white-space:pre-wrap;word-break:break-all;overflow-wrap:break-word;max-width:100%;box-sizing:border-box;margin:6px 0">'+
      clean.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')+'</pre>');
    return '\x00BLOCK'+idx+'\x00';
  });
  md=md
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
    .replace(/^# (.+)$/gm,'<div style="font-size:18px;font-weight:700;margin:18px 0 8px;color:var(--text);border-bottom:1px solid var(--line);padding-bottom:6px">$1</div>')
    .replace(/^## (.+)$/gm,'<div style="font-size:15px;font-weight:700;margin:14px 0 5px;color:var(--text)">$1</div>')
    .replace(/^### (.+)$/gm,'<div style="font-size:13px;font-weight:700;margin:10px 0 4px;color:var(--accent)">$1</div>')
    .replace(/\*\*([^*]+)\*\*/g,'<b>$1</b>')
    .replace(/\[([^\]]+)\]\((https?:\/\/[^)]+)\)/g,'<a href="$2" target="_blank" style="color:var(--accent)">$1</a>')
    .replace(/`([^`\n]+)`/g,'<code style="background:rgba(255,255,255,.07);padding:1px 5px;border-radius:4px;font-size:11.5px;font-family:monospace">$1</code>')
    .replace(/^&gt; \[!WARNING\][^\n]*/gm,'')
    .replace(/^&gt; (.+)$/gm,'<div style="padding:4px 10px;margin:4px 0;border-left:3px solid var(--warn);color:var(--muted);font-size:12.5px">$1</div>')
    .replace(/^---$/gm,'<hr style="border:none;border-top:1px solid var(--line);margin:12px 0"/>')
    .replace(/^\|(.+)\|$/gm,function(m){var c=m.slice(1,-1).split('|');return '<div style="display:flex;gap:4px;margin:1px 0">'+c.map(function(x){return '<div style="flex:1;padding:4px 6px;font-size:12px;background:rgba(255,255,255,.04);border-radius:4px">'+x.trim()+'</div>';}).join('')+'</div>';})
    .replace(/^[-*] (.+)$/gm,'<div style="padding:2px 0 2px 14px;font-size:13px">&#8226; $1</div>')
    .replace(/^(?!<div|<pre|<hr|\x00)(.+)$/gm,'<div style="font-size:13px;line-height:1.7;margin:2px 0">$1</div>')
    .replace(/\n{2,}/g,'<div style="height:6px"></div>');
  // Kod bloklarini geri koy
  blocks.forEach(function(b,i){md=md.replace('\x00BLOCK'+i+'\x00',b);});
  return md;
}

function securityNote(){
  return '<div class="security-note"><b>&#128274; '+(L?'Trusted LAN only.':'Web Panel sadece g&#252;venilir LAN i&#231;indir.')+'</b> '+(L?'Do not expose this panel to WAN, Guest or IoT networks.':'WAN, Misafir veya IoT a&#287;lar&#305;na a&#231;may&#305;n.')+'</div>';
}
function render(k){
  var v=V[k]||V.dash;
  var t=(L&&v.titleEn)?v.titleEn:(v.title||k);
  var modelPfx=(S&&S.model&&!v.noPrefix)?S.model+' — ':'';
  document.getElementById('pTitle').innerHTML=modelPfx+t;
  document.getElementById('pSub').innerHTML=(L&&v.subEn)?v.subEn:(v.sub||'');
  document.getElementById('view').innerHTML=securityNote()+(v.html?v.html():'<div class="empty">Yap&#305;m a&#351;amas&#305;nda...</div>');
  window.location.hash=k;
}
document.querySelectorAll('.item').forEach(function(el){
  el.addEventListener('click',function(){
    document.querySelectorAll('.item').forEach(function(i){i.classList.remove('active');});
    el.classList.add('active');curV=el.getAttribute('data-view');render(curV);
    if(isMob())closeMobMenu();
  });
});
// Sayfa acilisinda hash'e gore goruntumu sec
(function(){
  var h=window.location.hash.slice(1);
  if(h&&V[h]){
    curV=h;
    document.querySelectorAll('.item').forEach(function(el){
      if(el.getAttribute('data-view')===h)el.classList.add('active');
      else el.classList.remove('active');
    });
  }
})();
// Sayfa acilisinda: once eski JSON'u goster, arka planda taze uret, gelince yenile
fetchS().then(function(){render(curV);});startAuto();
fetch('/cgi-bin/action.sh',{method:'POST',
  headers:{'Content-Type':'application/x-www-form-urlencoded'},
  body:'action=status_refresh'})
  .then(function(){return fetchS();})
  .catch(function(){});
</script>
</body>
</html>
HTMLEOF
    sed -i "s/__KZM_PORT__/${KZM2_GUI_PORT}/g" "$KZM2_GUI_HTML" 2>/dev/null
    sed -i "s/__KZM_VER__/${SCRIPT_VERSION}/g" "$KZM2_GUI_HTML" 2>/dev/null
}
# ---------------------------------------------------------------------------
# kzm_gui_add_cron: status_gen.sh icin cron satiri ekle
# ---------------------------------------------------------------------------
kzm_gui_add_cron() {
    local _tmp="/tmp/kzm_cron_gui.$$"
    mkdir -p /opt/var/spool/cron/crontabs 2>/dev/null
    crontab -l 2>/dev/null | grep -v 'kzm2_status_gen.sh' > "$_tmp"
    {
        cat "$_tmp"
        printf '*/1 * * * * /opt/bin/kzm2_status_gen.sh >/dev/null 2>&1\n'
    } | crontab -
    rm -f "$_tmp"
}
# ---------------------------------------------------------------------------
# kzm_gui_save_hw_info: model ve firmware bilgisini dosyaya kaydet
# ---------------------------------------------------------------------------
kzm_gui_save_hw_info() {
    mkdir -p /opt/var/run 2>/dev/null
    kzm2_banner_get_system  2>/dev/null > /opt/var/run/kzm2_hw_model  || true
    kzm2_banner_get_firmware 2>/dev/null > /opt/var/run/kzm2_hw_firmware || true
}
# ---------------------------------------------------------------------------
# kzm_gui_remove_cron: status_gen cron satirini kaldir
# ---------------------------------------------------------------------------
kzm_gui_remove_cron() {
    local _tmp="/tmp/kzm_cron_gui.$$"
    crontab -l 2>/dev/null | grep -v 'kzm2_status_gen.sh' > "$_tmp"
    crontab - < "$_tmp"
    rm -f "$_tmp"
}
# ---------------------------------------------------------------------------
# kzm_gui_install: Web Panel kurulumu
# ---------------------------------------------------------------------------
kzm_gui_install() {
    clear
    printf "\n %b%s%b\n" "${CLR_BOLD}${CLR_CYAN}" "$(T TXT_GUI_TITLE)" "${CLR_RESET}"
    print_line "="
    # /opt kontrolu
    if [ ! -d /opt ]; then
        print_status FAIL "$(T TXT_GUI_ERR_OPT)"
        press_enter_to_continue
        return 1
    fi
    print_status INFO "$(T TXT_GUI_OPKG_UPD)"
    opkg update >/dev/null 2>&1
    # lighttpd kur
    if ! command -v lighttpd >/dev/null 2>&1; then
        print_status INFO "$(T _ 'lighttpd kuruluyor...' 'Installing lighttpd...')"
        if ! opkg install lighttpd >/dev/null 2>&1; then
            print_status FAIL "$(T TXT_GUI_ERR_LIGHTTPD)"
            press_enter_to_continue
            return 1
        fi
    fi
    # lighttpd-mod-cgi kur
    if ! opkg list-installed 2>/dev/null | grep -q 'lighttpd-mod-cgi'; then
        print_status INFO "$(T _ 'lighttpd-mod-cgi kuruluyor...' 'Installing lighttpd-mod-cgi...')"
        if ! opkg install lighttpd-mod-cgi >/dev/null 2>&1; then
            print_status FAIL "$(T TXT_GUI_ERR_CGI)"
            press_enter_to_continue
            return 1
        fi
    fi
    # lighttpd-mod-setenv kur (Cache-Control header icin)
    if ! opkg list-installed 2>/dev/null | grep -q 'lighttpd-mod-setenv'; then
        print_status INFO "$(T _ 'lighttpd-mod-setenv kuruluyor...' 'Installing lighttpd-mod-setenv...')"
        opkg install lighttpd-mod-setenv >/dev/null 2>&1 || true
    fi
    print_status INFO "$(T _ 'Dosyalar olusturuluyor...' 'Creating files...')"
    # Dizinler
    mkdir -p "$KZM2_GUI_DIR" "$KZM2_GUI_CGI_DIR" /opt/var/run /opt/var/log 2>/dev/null
    # Dosyalar
    kzm_gui_write_lighttpd_conf
    kzm_gui_write_html
    kzm_gui_write_cgi
    kzm_gui_write_status_script
    # HW bilgisi kaydet
    kzm_gui_save_hw_info
    # Ilk status JSON uret
    kzm_gui_gen_status
    # Cron ekle
    kzm_gui_add_cron
    print_status PASS "$(T TXT_GUI_CRON_OK)"
    # crond calismiyorsa baslat
    if ! pgrep crond >/dev/null 2>&1; then
        crond 2>/dev/null || true
        sleep 1
        if pgrep crond >/dev/null 2>&1; then
            print_status PASS "$(T _ 'crond baslatildi' 'crond started')"
        else
            print_status WARN "$(T _ 'crond baslatilamadi - JSON her dakika yenilenmiyor olabilir' 'crond could not be started - JSON may not refresh every minute')"
        fi
    fi
    # Init.d autostart scripti olustur
    cat > /opt/etc/init.d/S80lighttpd << 'INITEOF'
#!/bin/sh
[ "$1" = "start" ] && lighttpd -f /opt/etc/lighttpd/lighttpd.conf >/dev/null 2>&1
[ "$1" = "stop"  ] && kill $(cat /opt/var/run/lighttpd.pid 2>/dev/null) 2>/dev/null; true
[ "$1" = "restart" ] && { kill $(cat /opt/var/run/lighttpd.pid 2>/dev/null) 2>/dev/null; sleep 1; lighttpd -f /opt/etc/lighttpd/lighttpd.conf >/dev/null 2>&1; }
INITEOF
    chmod +x /opt/etc/init.d/S80lighttpd
    # lighttpd baslat
    /opt/etc/init.d/S80lighttpd restart >/dev/null 2>&1 || \
        lighttpd -f "$KZM2_GUI_CONF" >/dev/null 2>&1
    sleep 1
    if kzm_gui_is_running; then
        print_status PASS "$(T TXT_GUI_LIGHTTPD_OK)"
    else
        print_status WARN "$(T TXT_GUI_LIGHTTPD_OFF)"
    fi
    print_status PASS "$(T TXT_GUI_INSTALLED)"
    echo
    kzm_gui_show_url
    press_enter_to_continue
}
# ---------------------------------------------------------------------------
# kzm_gui_uninstall: Web Panel kaldirma
# ---------------------------------------------------------------------------
kzm_gui_uninstall() {
    clear
    printf "\n %b%s%b\n" "${CLR_BOLD}${CLR_CYAN}" "$(T TXT_GUI_TITLE)" "${CLR_RESET}"
    print_line "="
    if ! kzm_gui_is_installed; then
        print_status WARN "$(T TXT_GUI_NOT_INSTALLED)"
        press_enter_to_continue
        return 0
    fi
    printf "%b%s%b" "${CLR_ORANGE}" "$(T TXT_GUI_CONFIRM_REMOVE)" "${CLR_RESET}"
    local _ans
    read -r _ans
    case "$_ans" in
        e|E|y|Y) ;;
        *) printf '%s\n' "$(T _ 'Iptal edildi.' 'Cancelled.')"; press_enter_to_continue; return 0 ;;
    esac
    print_status INFO "$(T TXT_GUI_REMOVING)"
    # lighttpd durdur ve autostart kaldir
    kill $(pgrep lighttpd) 2>/dev/null
    /opt/etc/init.d/S80lighttpd stop >/dev/null 2>&1
    rm -f /opt/etc/init.d/S80lighttpd
    # Dosyalari kaldir
    rm -rf "$KZM2_GUI_DIR"
    rm -rf /opt/etc/lighttpd
    rm -f  "$KZM2_GUI_STATUS_SCRIPT"
    rm -f  "$KZM2_GUI_STATUS_JSON"
    rm -f  /opt/var/run/kzm2_hw_model
    rm -f  /opt/var/run/kzm2_hw_firmware
    rm -f  /opt/var/log/lighttpd_error.log
    rm -f  /opt/var/log/lighttpd_access.log
    rm -f  /opt/var/run/lighttpd.pid
    # iptables kuralini kaldir
    iptables -D INPUT -p tcp --dport "$KZM2_GUI_PORT" -j ACCEPT 2>/dev/null
    # opkg ile lighttpd paketlerini kaldir
    opkg remove lighttpd lighttpd-mod-cgi 2>/dev/null | grep -v "^$" || true
    # opkg "modified conffile" nedeniyle silmedigi dosyalari manuel temizle
    rm -f /opt/etc/lighttpd/conf.d/30-cgi.conf 2>/dev/null
    # Lighttpd dizini bos kaldiysa temizle
    rmdir /opt/etc/lighttpd/conf.d 2>/dev/null
    rmdir /opt/etc/lighttpd 2>/dev/null
    # Cron kaldir
    kzm_gui_remove_cron
    rm -f "$KZM2_GUI_CONF_CUSTOM"
    print_status PASS "$(T TXT_GUI_REMOVED)"
    press_enter_to_continue
}
# ---------------------------------------------------------------------------
# kzm_gui_update: Web Panel guncelle (dosyalari yeniden yaz + restart)
# ---------------------------------------------------------------------------
kzm_gui_update() {
    clear
    printf "\n %b%s%b\n" "${CLR_BOLD}${CLR_CYAN}" "$(T TXT_GUI_TITLE)" "${CLR_RESET}"
    print_line "="
    if ! kzm_gui_is_installed; then
        print_status WARN "$(T TXT_GUI_NOT_INSTALLED)"
        print_status INFO "$(T _ 'Once kurulum yapin (Secim 1).' 'Please install first (Option 1).')"
        press_enter_to_continue
        return 1
    fi
    print_status INFO "$(T _ 'Dosyalar guncelleniyor...' 'Updating files...')"
    kzm_gui_write_lighttpd_conf
    kzm_gui_write_html
    kzm_gui_write_cgi
    kzm_gui_write_status_script
    kzm_gui_save_hw_info
    kzm_gui_gen_status
    /opt/etc/init.d/S80lighttpd restart >/dev/null 2>&1
    print_status PASS "$(T TXT_GUI_UPDATED)"
    press_enter_to_continue
}
# ---------------------------------------------------------------------------
# kzm_gui_status: Durum goster
# ---------------------------------------------------------------------------
kzm_gui_status() {
    clear
    printf "\n %b%s%b\n" "${CLR_BOLD}${CLR_CYAN}" "$(T TXT_GUI_TITLE)" "${CLR_RESET}"
    print_line "="
    if kzm_gui_is_running; then
        print_status PASS "$(T TXT_GUI_STATUS_ON)"
    else
        print_status WARN "$(T TXT_GUI_STATUS_OFF)"
    fi
    if [ -f "$KZM2_GUI_HTML" ]; then
        print_status PASS "$(T TXT_GUI_HTML_OK)"
    else
        print_status WARN "$(T TXT_GUI_HTML_MISS)"
    fi
    if [ -f "$KZM2_GUI_CGI" ]; then
        print_status PASS "$(T TXT_GUI_CGI_OK)"
    else
        print_status WARN "$(T TXT_GUI_CGI_MISS)"
    fi
    if [ -f "$KZM2_GUI_STATUS_JSON" ]; then
        print_status PASS "$(T TXT_GUI_JSON_OK)"
    else
        print_status WARN "$(T TXT_GUI_JSON_MISS)"
    fi
    echo
    if kzm_gui_is_running; then
        kzm_gui_show_url
    fi
    press_enter_to_continue
}
# ---------------------------------------------------------------------------
# kzm_gui_change_port: GUI portunu degistir
# ---------------------------------------------------------------------------
kzm_gui_change_port() {
    local _newport
    printf "%s" "$(T TXT_GUI_PORT_PROMPT)"
    read -r _newport
    [ -z "$_newport" ] && return 0
    # Sayi kontrolu ve aralik kontrolu
    case "$_newport" in
        *[!0-9]*) print_status FAIL "$(T TXT_GUI_PORT_INVALID)"; press_enter_to_continue; return 1 ;;
    esac
    if [ "$_newport" -lt 1024 ] || [ "$_newport" -gt 65535 ]; then
        print_status FAIL "$(T TXT_GUI_PORT_INVALID)"
        press_enter_to_continue
        return 1
    fi
    # Conf dosyasina yaz (default 8088 ise dosyayi sil)
    if [ "$_newport" = "8088" ]; then
        rm -f "$KZM2_GUI_CONF_CUSTOM" 2>/dev/null
    else
        printf 'KZM2_GUI_PORT=%s\n' "$_newport" > "$KZM2_GUI_CONF_CUSTOM"
    fi
    KZM2_GUI_PORT="$_newport"
    # lighttpd.conf yeniden olustur
    kzm_gui_write_lighttpd_conf
    # HTML'deki port bilgisini guncelle
    sed -i "s/Entware &bull; [0-9]*/Entware \&bull; ${KZM2_GUI_PORT}/g" "$KZM2_GUI_HTML" 2>/dev/null
    # lighttpd'yi yeniden baslat
    /opt/etc/init.d/S80lighttpd restart >/dev/null 2>&1 || {
        kill "$(cat /opt/var/run/lighttpd.pid 2>/dev/null)" 2>/dev/null
        sleep 1
        lighttpd -f "$KZM2_GUI_CONF" >/dev/null 2>&1
    }
    sleep 1
    print_status PASS "$(T TXT_GUI_PORT_CHANGED)"
    kzm_gui_show_url
    press_enter_to_continue
}
# ---------------------------------------------------------------------------
# kzm_gui_show_url: URL goster
# ---------------------------------------------------------------------------
kzm_gui_show_url() {
    local _ip
    _ip="$(kzm_gui_get_lan_ip)"
    printf " %b%s%b : %b%s%b\n" \
        "${CLR_BOLD}" "$(T TXT_GUI_URL_LABEL)" "${CLR_RESET}" \
        "${CLR_CYAN}${CLR_BOLD}" "http://${_ip}:${KZM2_GUI_PORT}/" "${CLR_RESET}"
}
# ---------------------------------------------------------------------------
# kzm_gui_toggle: lighttpd ac/kapat
# ---------------------------------------------------------------------------
kzm_gui_toggle() {
    if kzm_gui_is_running; then
        /opt/etc/init.d/S80lighttpd stop >/dev/null 2>&1 || \
            kill "$(cat /opt/var/run/lighttpd.pid 2>/dev/null)" 2>/dev/null || \
            kill "$(pgrep lighttpd | head -n1)" 2>/dev/null
        sleep 1
        print_status WARN "$(T TXT_GUI_DISABLED)"
    else
        if ! kzm_gui_is_installed; then
            print_status WARN "$(T TXT_GUI_NOT_INSTALLED)"
            press_enter_to_continue
            return 1
        fi
        /opt/etc/init.d/S80lighttpd start >/dev/null 2>&1 || \
            lighttpd -f "$KZM2_GUI_CONF" >/dev/null 2>&1
        print_status PASS "$(T TXT_GUI_ENABLED)"
    fi
    press_enter_to_continue
}
# ---------------------------------------------------------------------------
# kzm_gui_menu: Ana GUI alt menusu
# ---------------------------------------------------------------------------
kzm_gui_menu() {
    local _gchoice
    while true; do
        clear
        printf "\n %b%s%b\n" "${CLR_BOLD}${CLR_CYAN}" "$(T TXT_GUI_TITLE)" "${CLR_RESET}"
        print_line "="
        # Durum satiri
        if kzm_gui_is_running; then
            printf " %b%s%b\n" "${CLR_GREEN}" "$(T TXT_GUI_STATUS_ON)" "${CLR_RESET}"
            echo
            kzm_gui_show_url
        else
            printf " %b%s%b\n" "${CLR_RED}" "$(T TXT_GUI_STATUS_OFF)" "${CLR_RESET}"
        fi
        echo
        printf "%b%s%b\\n" "${CLR_ORANGE}" "$(T TXT_GUI_SECURITY_WARN)" "${CLR_RESET}"
        echo
        print_line "-"
        printf " %s\n" "$(T TXT_GUI_OPT_1)"
        printf " %s\n" "$(T TXT_GUI_OPT_2)"
        printf " %s\n" "$(T TXT_GUI_OPT_3)"
        printf " %s\n" "$(T TXT_GUI_OPT_4)"
        printf " %s%b%s%b\n" "$(T _ '5) Port Degistir (Mevcut: ' '5) Change Port (Current: ')" "${CLR_CYAN}${CLR_BOLD}" "${KZM2_GUI_PORT})" "${CLR_RESET}"
        printf " %s\n" "$(T TXT_GUI_OPT_6)"
        printf " %s\n" "$(T TXT_GUI_OPT_0)"
        print_line "-"
        printf "$(T _ 'Seciminiz: ' 'Your choice: ')"
        read -r _gchoice
        case "$_gchoice" in
            1) kzm_gui_install ;;
            2) kzm_gui_uninstall ;;
            3) kzm_gui_update ;;
            4) kzm_gui_status ;;
            5) kzm_gui_change_port ;;
            6) kzm_gui_toggle ;;
            0) break ;;
            *) printf '%s\n' "$(T _ 'Gecersiz secim.' 'Invalid choice.')" ;;
        esac
    done
}
# ---------------------------------------------------------------------------
# --cgi-action argumani: CGI tarafindan cagrilir, dogrudan fonksiyon calistirir
# ---------------------------------------------------------------------------
main_menu_loop() {
    while true; do
    clear  # clear_on_start_main_loop
        display_menu
        read -r choice || break
    clear  # clear_after_choice_main
        echo ""
        case "$choice" in
        c|C)
            clean_zapret_settings_backups
            restore_zapret_settings
            return 0
            ;;
            1) install_zapret2; press_enter_to_continue ;;
            2) uninstall_zapret2 ;;
            3) start_zapret2; press_enter_to_continue ;;
            4) stop_zapret2 1; press_enter_to_continue ;;
            5) restart_zapret2; press_enter_to_continue ;;
            6) check_remote_update ;;
			10) check_manager_update ;;
			7) configure_zapret_ipv6_support ;;
			8) backup_restore_menu ;;
			9)
            while true; do
                clear
                print_line "="
                printf " %b%s%b\n" "${CLR_CYAN}" "$(T _ '9. DPI Profili / WAN Arayuzu' '9. DPI Profile / WAN Interface')" "${CLR_RESET}"
                print_line "="
                printf " 1. %s\n" "$(T _ 'DPI Profilini Degistir' 'Change DPI Profile')"
                printf " 2. %s  %b[$(T _ 'Mevcut' 'Current'): $([ -z "$(get_wan_if)" ] && printf "%b%s%b" "${CLR_CYAN}" "$(T _ 'Tum Arayuzler' 'All Interfaces')" "${CLR_RESET}" || printf "%b%s%b" "${CLR_GREEN}" "$(get_wan_if)" "${CLR_RESET}")]%b\n" "$(T _ 'WAN Arayuzunu Degistir' 'Change WAN Interface')" "${CLR_RESET}"
                printf " 0. %s\n" "$(T _ 'Geri' 'Back')"
                print_line "-"
                printf "%s" "$(T _ 'Secim: ' 'Choice: ')"
                read -r _m9
                case "$_m9" in
                    1)
                        clear
                        if select_dpi_profile; then
                            apply_dpi_profile_now
                        fi
                        ;;
                    2)
                        clear
                        print_line "="
                        printf " %b%s%b\n" "${CLR_CYAN}" "$(T _ 'WAN Arayuzu Secimi' 'WAN Interface Selection')" "${CLR_RESET}"
                        print_line "-"
                        local _rec="$(detect_recommended_wan_if)"
                        [ -z "$_rec" ] && _rec="ppp0"
                        local _cur_wan_lbl
                        if [ -z "$(get_wan_if)" ]; then
                            _cur_wan_lbl="${CLR_CYAN}$(T _ 'Tum Arayuzler' 'All Interfaces')${CLR_RESET}"
                        else
                            _cur_wan_lbl="${CLR_GREEN}$(get_wan_if)${CLR_RESET}"
                        fi
                        local _lbl_cur _lbl_rec _lw
                        _lbl_cur="$(T _ 'Mevcut' 'Current')"
                        _lbl_rec="$(T _ 'Onerilen' 'Recommended')"
                        [ ${#_lbl_cur} -gt ${#_lbl_rec} ] && _lw=${#_lbl_cur} || _lw=${#_lbl_rec}
                        printf " %b%-*s:%b %s\n" "${CLR_BOLD}" "$_lw" "$_lbl_cur" "${CLR_RESET}" "$_cur_wan_lbl"
                        printf " %b%-*s:%b %b%s%b\n" "${CLR_BOLD}" "$_lw" "$_lbl_rec" "${CLR_RESET}" "${CLR_GREEN}" "${_rec}" "${CLR_RESET}"
                        echo ""
                        printf " %b%s%b\n" "${CLR_ORANGE}" "$(T _ '[!] Hatali arayuz secimi trafiginizi ve VPN erisimini durdurabilir!' '[!] Wrong interface may cut your traffic and VPN access!')" "${CLR_RESET}"
                        printf " %b%s%b\n" "${CLR_ORANGE}" "$(T _ '[!] KZM2 - Zapret2 kurulurken otomatik sectigi WAN arayuzu en duzgun calisacak arayuzdur.' '[!] KZM2 - The WAN interface auto-selected during Zapret2 installation works best.')" "${CLR_RESET}"
                        printf " %b%s%b\n" "${CLR_ORANGE}" "$(T _ '[!] Zorunlu olmadikca WAN arayuzunu DEGISTIRMEYIN!' '[!] Do NOT change the WAN interface unless absolutely necessary!')" "${CLR_RESET}"
                        echo ""
                        printf " %s %b%s%b %s %b%s%b %s %b%s%b\n" \
                            "$(T _ 'Not: Tum cikislar icin' 'Note: For all interfaces type')" \
                            "${CLR_CYAN}" "any" "${CLR_RESET}" \
                            "$(T _ ', iptal icin' ', to cancel type')" \
                            "${CLR_ORANGE}" "q" "${CLR_RESET}" \
                            "$(T _ ', onerilen:' ', recommended:')" \
                            "${CLR_GREEN}" "$_rec" "${CLR_RESET}"
                        print_line "-"
                        while true; do
                            printf "%b%s%b%b%s%b" "${CLR_BOLD}" "$(T _ 'Yeni WAN' 'New WAN')" "${CLR_RESET}" "${CLR_GREEN}" "$(T _ ' (q=iptal): ' ' (q=cancel): ')" "${CLR_RESET}"
                            read -r _wans
                            case "$_wans" in
                                q|Q) break ;;
                                "")
                                    printf " %b%s%b\n" "${CLR_ORANGE}" "$(T _ 'Gecersiz giris. Bir arayuz adi girin (ornek: ppp0) veya any / q.' 'Invalid input. Enter an interface name (e.g. ppp0) or any / q.')" "${CLR_RESET}"
                                    continue ;;
                                *)
                                    # any/ANY ozel durum, diger girislerde arayuz var mi kontrol et
                                    if [ "$_wans" != "any" ] && [ "$_wans" != "ANY" ] && [ ! -d "/sys/class/net/$_wans" ]; then
                                        printf " %b%s %b%s%b %s%b\n" "${CLR_ORANGE}" "$(T _ '[!] Arayuz bulunamadi:' '[!] Interface not found:')" "${CLR_BOLD}" "$_wans" "${CLR_ORANGE}" "$(T _ '— Gecerli bir arayuz adi girin.' '— Enter a valid interface name.')" "${CLR_RESET}"
                                        continue
                                    fi
                                    [ "$_wans" = "any" ] || [ "$_wans" = "ANY" ] || [ "$_wans" = "0" ] && _wans_display="${CLR_CYAN}$(T _ 'Tum Arayuzler' 'All Interfaces')${CLR_RESET}" || _wans_display="${CLR_GREEN}${_wans}${CLR_RESET}"
                                    printf " %b%s:%b %b%s%b — %s" "${CLR_BOLD}" "$(T _ 'Secilen' 'Selected')" "${CLR_RESET}" "" "$_wans_display" "" "$(T _ 'Onayliyor musunuz? (e/h): ' 'Confirm? (y/n): ')"
                                    read -r _wans_confirm
                                    case "$_wans_confirm" in
                                        e|E|y|Y)
                                            [ "$_wans" = "any" ] || [ "$_wans" = "ANY" ] || [ "$_wans" = "0" ] && _wans=""
                                            mkdir -p /opt/zapret2 2>/dev/null
                                            echo "$_wans" > "$WAN_IF_FILE" 2>/dev/null
                                            print_status INFO "$(T _ 'WAN degistirildi:' 'WAN changed:') $([ -z "$_wans" ] && T _ 'Tum Arayuzler' 'All Interfaces' || echo "$_wans")"
                                            sync_zapret_iface_wan_config
                                            restart_zapret2
                                            press_enter_to_continue
                                            break ;;
                                        *) continue ;;
                                    esac ;;
                            esac
                        done
                        ;;
                    0) break ;;
                    *) ;;
                esac
            done
            ;;
			11) manage_hostlist_menu ;;
            12) manage_ipset_clients ;;
			13) script_rollback_menu ;;
			14) network_diag_menu ;;
			15) telegram_notifications_menu ;;
			16) health_monitor_menu ;;
			17) kzm_gui_menu ;;
B|b) blockcheck_test_menu ;;
L|l) toggle_lang ;;
R|r) scheduled_tasks_menu ;;
        U|u) kzm2_full_uninstall ;;
            0) echo "Cikis yapiliyor..."; break ;;
            *) echo "$(T _ 'Gecersiz secim! Lutfen 0-17, B, L, R veya U girin.' 'Invalid choice! Please enter 0-17, B, L, R or U.')" ;;
        esac
        echo ""
    done
}
# Internal: run health monitor loop as a detached daemon
if [ "$1" = "--netfilter-hook" ]; then
    # Zapret2 manuel durdurulduysa hook kurallari yeniden uygulamamali
    [ -f /tmp/.zapret2_paused ] && exit 0
    # none profilde NFQUEUE kurali eklenmez, varsa temizle, nfqws2 durdur
    if [ "$(cat /opt/zapret2/dpi_profile 2>/dev/null | tr -d '[:space:]')" = "none" ]; then
        killall nfqws2 2>/dev/null
        flush_all_nfqueue_rules 2>/dev/null
        nozapret_apply_rules 2>/dev/null
        kzm2_apply_ip_exclude_rules 2>/dev/null
        exit 0
    fi
    # Zapret2 native kurallarini geri yukle (tum ag modu dahil)
    if [ -x /opt/zapret2/init.d/sysv/zapret2 ]; then
        /opt/zapret2/init.d/sysv/zapret2 start-fw >/dev/null 2>&1
    fi
    # nozapret RETURN kurali — her modda calisir
    nozapret_apply_rules 2>/dev/null
    # List modda KZM2'nin ozel IPSET kurallarini uygula
    _nfh_mode="$(cat /opt/zapret2/ipset_clients_mode 2>/dev/null | tr -d '[:space:]')"
    if [ "$_nfh_mode" = "list" ]; then
        flush_all_nfqueue_rules 2>/dev/null
        ipset_ensure_and_load_clients 2>/dev/null
        add_ipset_nfqueue_rules 2>/dev/null
    fi
    enforce_wan_if_nfqueue_rules 2>/dev/null
    kzm2_apply_ip_exclude_rules 2>/dev/null
    exit 0
fi
# Hook script guncelleme kontrolu — eski kurulumlar icin otomatik guncelle
_hook_file="/opt/etc/ndm/netfilter.d/000-zapret2.sh"
if [ -f "$_hook_file" ]; then
    if ! grep -q "netfilter-hook" "$_hook_file" 2>/dev/null || \
       grep -q "restart-fw" "$_hook_file" 2>/dev/null; then
        allow_firewall 2>/dev/null
    fi
fi
if [ "$1" = "--healthmon-daemon" ]; then
    # ignore hangup when parent shell exits
    trap '' HUP 2>/dev/null
    healthmon_loop
    exit 0
fi
if [ "$1" = "--update-gui" ]; then
    if [ -d "$KZM2_GUI_DIR" ]; then
        kzm_gui_write_html
        kzm_gui_write_cgi
        kzm_gui_write_status_script
    fi
    exit 0
fi
if [ "$1" = "--test-tls-alert" ]; then
    load_lang
    telegram_load_config 2>/dev/null
    if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
        echo "HATA: Telegram yapilandirilmamis. Menu 15'ten ayarlayin."
        exit 1
    fi
    echo "Telegram TLS uyari mesaji gonderiliyor..."
    telegram_send "$(tpl_render "$(T TXT_HM_SYSLOG_TLS_MSG)" CNT "5" MIN "30")"
    echo "Gonderildi. Telegram'i kontrol edin."
    exit 0
fi
if [ "$1" = "--telegram-daemon" ]; then
    trap '' HUP 2>/dev/null
    telegram_load_config 2>/dev/null
    telegram_bot_daemon
    exit 0
fi
if [ "$1" = "--opkg-upgrade" ]; then
    export PATH="/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    load_lang
    _log="/tmp/kzm2_healthmon.log"
    _ts="$(date '+%Y-%m-%d %H:%M:%S')"
    _title="🔄 $(T TXT_OPKG_SCHED_TITLE)"
    printf '%s | opkg_upgrade | start\n' "$_ts" >> "$_log"
    # opkg.lock varsa 30s bekle, tekrar dene
    if ! opkg update >> "$_log" 2>&1; then
        if grep -q "opkg.lock" "$_log" 2>/dev/null; then
            printf '%s | opkg_upgrade | lock busy, retrying in 30s\n' "$_ts" >> "$_log"
            sleep 30
            if ! opkg update >> "$_log" 2>&1; then
                printf '%s | opkg_upgrade | opkg update FAIL\n' "$_ts" >> "$_log"
                telegram_load_config 2>/dev/null
                [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ] && \
                    telegram_send "$(printf '%s\n%s' "$_title" "$(T TXT_OPKG_SCHED_RUN_FAIL)")" >/dev/null 2>&1
                exit 1
            fi
        else
            printf '%s | opkg_upgrade | opkg update FAIL\n' "$_ts" >> "$_log"
            telegram_load_config 2>/dev/null
            [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ] && \
                telegram_send "$(printf '%s\n%s' "$_title" "$(T TXT_OPKG_SCHED_RUN_FAIL)")" >/dev/null 2>&1
            exit 1
        fi
    fi
    _upgradable="$(opkg list-upgradable 2>/dev/null)"
    if [ -z "$_upgradable" ]; then
        _noupdate_msg="$(T TXT_OPKG_SCHED_RUN_NOUPDATE)"
        printf '%s | opkg_upgrade | %s\n' "$_ts" "$_noupdate_msg" >> "$_log"
        telegram_load_config 2>/dev/null
        if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
            telegram_send "$(printf '%s\n%s' "$_title" "$_noupdate_msg")" >/dev/null 2>&1
        fi
        exit 0
    fi
    _count="$(printf '%s\n' "$_upgradable" | grep -c .)"
    _pkglist="$(printf '%s\n' "$_upgradable" | awk '{print "📦 "$1" "$2" -> "$4}' | head -20)"
    opkg upgrade >> "$_log" 2>&1
    _rc="$?"
    if [ "$_rc" -eq 0 ] || [ "$_rc" -eq 1 ]; then
        _msg="$(tpl_render "$(T TXT_OPKG_SCHED_RUN_OK)" COUNT "$_count")"
        printf '%s | opkg_upgrade | %s\n' "$_ts" "$_msg" >> "$_log"
        telegram_load_config 2>/dev/null
        if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
            telegram_send "$(printf '%s\n%s\n%s' "$_title" "$_msg" "$_pkglist")" >/dev/null 2>&1
        fi
    else
        printf '%s | opkg_upgrade | FAIL rc=%s\n' "$_ts" "$_rc" >> "$_log"
        telegram_load_config 2>/dev/null
        [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ] && \
            telegram_send "$(printf '%s\n%s' "$_title" "$(T TXT_OPKG_SCHED_RUN_FAIL)")" >/dev/null 2>&1
        exit 1
    fi
    exit 0
fi
if [ "$1" = "--opkg-upgrade-test" ]; then
    export PATH="/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    load_lang
    _log="/tmp/kzm2_healthmon.log"
    _ts="$(date '+%Y-%m-%d %H:%M:%S')"
    _title="🔄 $(T TXT_OPKG_SCHED_TITLE)"
    _upgradable="htop 3.3.0-1 - 3.4.1-1
curl 8.5.0-1 - 8.6.0-1"
    _count="$(printf '%s\n' "$_upgradable" | grep -c .)"
    _pkglist="$(printf '%s\n' "$_upgradable" | awk '{print "📦 "$1" "$2" -> "$4}')"
    _msg="$(tpl_render "$(T TXT_OPKG_SCHED_RUN_OK)" COUNT "$_count")"
    printf '%s | opkg_upgrade_test | %s\n' "$_ts" "$_msg" >> "$_log"
    telegram_load_config 2>/dev/null
    if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
        telegram_send "$(printf '%s\n%s\n%s' "$_title" "$_msg" "$_pkglist")" >/dev/null 2>&1
    fi
    echo "Test mesaji gonderildi. Log: $_log"
    exit 0
fi
if [ "$1" = "cleanup" ]; then
    cleanup_only_leftovers
    exit 0
fi
# curl kontrolu (daemon ve cleanup modlarinda atla)
if [ "$1" != "--healthmon-daemon" ] && [ "$1" != "--telegram-daemon" ] && [ "$1" != "--opkg-upgrade" ] && [ "$1" != "cleanup" ]; then
    if ! command -v curl >/dev/null 2>&1; then
        printf '%b\n' "$(T _ 'WARN: curl bulunamadi. Yukleniyor...' 'WARN: curl not found. Installing...')"
        if command -v opkg >/dev/null 2>&1; then
            opkg update >/dev/null 2>&1
            if opkg install curl >/dev/null 2>&1; then
                printf '%b\n' "$(T _ 'PASS: curl basariyla yuklendi.' 'PASS: curl installed successfully.')"
            else
                printf '%b\n' "$(T _ 'WARN: curl yuklenemedi. Bazi ozellikler calismayabilir.' 'WARN: curl install failed. Some features may not work.')"
            fi
        else
            printf '%b\n' "$(T _ 'WARN: opkg bulunamadi, curl yuklenemiyor.' 'WARN: opkg not found, cannot install curl.')"
        fi
    fi
fi
# Web GUI versiyon kontrolu: HTML veya CGI surumu eslesmiyor ise sessizce guncelle
if [ -d "$KZM2_GUI_DIR" ]; then
    _gui_ver="$(grep -o 'kzm-version" content="[^"]*"' "$KZM2_GUI_HTML" 2>/dev/null | sed 's/.*content="//;s/"//')"
    _cgi_ver="$(grep -o 'kzm-cgi-version: [^[:space:]]*' "$KZM2_GUI_CGI" 2>/dev/null | sed 's/.*kzm-cgi-version: //')"
    if [ "$_gui_ver" != "$SCRIPT_VERSION" ] || [ "$_cgi_ver" != "$SCRIPT_VERSION" ]; then
        kzm_gui_write_html
        kzm_gui_write_cgi
    fi
    # status_gen'de theme alani yoksa veya df -P eksikse yeniden olustur
    if [ -f "$KZM2_GUI_STATUS_SCRIPT" ] && \
       { ! grep -q '"theme"' "$KZM2_GUI_STATUS_SCRIPT" 2>/dev/null || \
         grep -q 'df /opt' "$KZM2_GUI_STATUS_SCRIPT" 2>/dev/null; }; then
        kzm_gui_write_status_script 2>/dev/null
    fi
fi
# rc.unslung patch: /opt/bin/find yerine BusyBox find kullan (Entware binary bozulmasina karsi)
if grep -q '/opt/bin/find' /opt/etc/init.d/rc.unslung 2>/dev/null; then
    sed -i 's|/opt/bin/find|find|g' /opt/etc/init.d/rc.unslung 2>/dev/null
fi
# Eski backup kalintilari temizle (timestamp'li ve tekil isimli onceki formatlar)
for _f in /opt/zapret2/config.bak_adv_* /opt/zapret2/config.bak_manual_* /opt/zapret2/config.bak_adv /opt/zapret2/config.bak_manual; do
    [ -f "$_f" ] && rm -f "$_f" 2>/dev/null
done
main_menu_loop
# WAN IP detection (best-effort)
WAN_IP="$(ip -4 addr show ppp0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)"
[ -z "$WAN_IP" ] && WAN_IP="$(ip -4 addr show eth0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)"
[ -z "$WAN_IP" ] && WAN_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n1)"
[ -z "$WAN_IP" ] && WAN_IP="unknown"