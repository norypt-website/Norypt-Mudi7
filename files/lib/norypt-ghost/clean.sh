#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Norypt Ghost — ephemeral state: never persist connected-device history.
# shellcheck source=/dev/null
. /lib/norypt-ghost/functions.sh

# On-flash directories that hold per-client or per-SIM history. Each is created
# if missing and tmpfs-mounted, so the stock daemons keep working but nothing
# they write survives a reboot:
#   /etc/oui-tertf       client-MAC tracker (gl-tertf / gl_clients client.db)
#   /etc/gl_modem_traffic per-SIM cellular data counters (4.10.x also syncs
#                        them to flash on every gl_cellular_manager stop)
#   /etc/vnstat          traffic stats (when vnstat is installed)
# Anything under /var already lives in RAM (/var -> /tmp on OpenWrt).
_CLEAN_DIRS="/etc/oui-tertf /etc/gl_modem_traffic"
_CLEAN_OPTIONAL_DIRS="/etc/vnstat"

# Vendor (Qualcomm/Quectel/GL) directories that only hold logs or caches, on
# partitions a firmware upgrade does not rewrite. RAM-backed only where the
# firmware has them; the listed files are kept (on flash and in RAM) because
# the daemon needs them to start:
#   /data/data_ipa   IPA offload daemon log (client IPs/MACs, ~1 KB/s in debug)
#   /data/data_tlpd  modem diagnostics log            (keeps tlpd_mode, tlpd_ctrl)
#   /root/esim       eSIM client log + a copy of the slot IMEI (keeps ver, db)
_VENDOR_DIRS="/data/data_ipa /data/data_tlpd /root/esim"

# Wi-Fi vendor logs on /data: hostapd/wpa_supplicant debug logs (every client
# MAC and every rotated BSSID) and the driver script's command log.
_WIFI_VENDOR_DIR=/data/vendor/wifi
_QCACLD_LOG=$_WIFI_VENDOR_DIR/qcacld32_commands.txt

# GL DPI "Flow Statistics" (4.10.x): per-client MAC + application + bytes +
# timestamp database, copied from /tmp to flash on every stop.
_FLOW_DB=/etc/netifyd/traffic_data.db

# GL copies nginx's RAM error log (client IPs) to flash every 10 minutes and on
# shutdown (gl-ngx-session). The flash file's existence is also an upgrade
# marker for GL, so it is kept — empty.
_NGX_FLASH_LOG=/etc/nginx/error.log
_NGX_RAM_LOG=/var/log/nginx/error.log

# GL per-SIM settings, keyed by ICCID, for every SIM ever inserted.
_SIM_MAP=/etc/config/cellular/sim_map.json
_SIM_APN_DB=/etc/config/cellular/history_apn_database.json

_is_tmpfs() { mount | grep -q " on $1 type tmpfs "; }

# Delete everything in $1 except the names listed in $2, dotfiles and
# subdirectories included. Refuses any path that is not one of the known
# telemetry/log directories.
_empty_dir() {
    local d="$1" keep="$2" f name
    case "$d" in /?*) ;; *) return 1 ;; esac
    case " $_CLEAN_DIRS $_CLEAN_OPTIONAL_DIRS $_VENDOR_DIRS " in
        *" $d "*) ;;
        *) return 1 ;;
    esac
    [ -d "$d" ] || return 0
    for f in "${d:?}"/* "${d:?}"/.[!.]* "${d:?}"/..?*; do
        [ -e "$f" ] || [ -L "$f" ] || continue
        name="${f##*/}"
        case " $keep " in *" $name "*) continue ;; esac
        rm -rf "$f"
    done
    return 0
}

# Mount a tmpfs over $1 after unlinking whatever is on flash underneath.
# (Unlinked, not overwritten: the overlay is ext4 on eMMC, whose FTL remaps
# writes, so overwrite-in-place tools are ineffective. The mount is the real
# protection.)
_ram_back() {
    local d="$1"
    _is_tmpfs "$d" && return 0
    mkdir -p "$d" 2>/dev/null || return 1
    _empty_dir "$d"
    mount -t tmpfs -o mode=0700,size=16m tmpfs "$d"
}

# RAM-back an existing vendor dir, keeping its owner/mode and the named files.
# $1 = dir, $2 = tmpfs size, $3 = names to keep
_ram_back_keep() {
    local d="$1" size="$2" keep="$3" tmp k own mode
    [ -d "$d" ] || return 0
    _is_tmpfs "$d" && return 0
    own="$(stat -c %u:%g "$d" 2>/dev/null)"; mode="$(stat -c %a "$d" 2>/dev/null)"
    tmp="$(mktemp -d /tmp/.ng_keep.XXXXXX)" || return 1
    for k in $keep; do [ -e "$d/$k" ] && cp -a "$d/$k" "$tmp/"; done
    _empty_dir "$d" "$keep"
    if mount -t tmpfs -o "mode=${mode:-700},size=$size" tmpfs "$d"; then
        [ -n "$own" ] && chown "$own" "$d"
        for k in $keep; do [ -e "$tmp/$k" ] && cp -a "$tmp/$k" "$d/"; done
    fi
    rm -rf "$tmp"
}

_vendor_ram_back() {
    _ram_back_keep /data/data_ipa  16m ""
    _ram_back_keep /data/data_tlpd 16m "tlpd_mode tlpd_ctrl"
    _ram_back_keep /root/esim      4m  "ver db"
}

# Wi-Fi daemons: no debug log file on flash. Applied before wifi starts at
# boot; a running hostapd picks it up on its next restart.
_wifi_logs_off() {
    local c f
    for c in hostapd wpa_supplicant; do
        [ -f "/etc/config/$c" ] || continue
        uci -q get "$c.log" >/dev/null 2>&1 || continue
        if [ "$(uci -q get "$c.log.log_folder_mode")" != "0" ] || \
           [ "$(uci -q get "$c.log.log_level")" != "info" ]; then
            uci -q set "$c.log.log_folder_mode=0"
            uci -q set "$c.log.log_level=info"
            uci -q commit "$c"
        fi
    done
    [ -d "$_WIFI_VENDOR_DIR" ] || return 0
    for f in "$_WIFI_VENDOR_DIR"/*.log "$_WIFI_VENDOR_DIR"/*.log.back_* \
             "$_QCACLD_LOG".back_*; do
        [ -f "$f" ] && rm -f "$f"
    done
    # The driver script appends to this path unconditionally; send it nowhere.
    if [ ! -L "$_QCACLD_LOG" ]; then
        rm -f "$_QCACLD_LOG"; ln -s /dev/null "$_QCACLD_LOG"
    fi
}

# IPA daemon debug off (it logs ~1 KB/s of addresses in debug mode). The flag
# file is part of the firmware, so this is re-applied every boot.
_ipa_debug_off() {
    [ -f /etc/data/ipa/log_mode ] || return 0
    grep -q on /etc/data/ipa/log_mode && echo off > /etc/data/ipa/log_mode
    return 0
}

# nginx error log: the RAM copy goes to /dev/null, so GL's 10-minute and
# shutdown sync have nothing to write; the flash copy is emptied.
_nginx_log_off() {
    mkdir -p "${_NGX_RAM_LOG%/*}"
    if [ ! -L "$_NGX_RAM_LOG" ]; then
        rm -f "$_NGX_RAM_LOG"; ln -s /dev/null "$_NGX_RAM_LOG"
    fi
    [ -s "$_NGX_FLASH_LOG" ] && : > "$_NGX_FLASH_LOG"
    return 0
}

# GoodCloud remote management and its remote-terminal client: off and not
# started at boot (option block_cloud, default on). Turning GoodCloud on again
# from the GL admin UI works until the next boot, and `check` reports it.
CLOUD_BLOCK() {
    local s
    _opt_enabled block_cloud || return 0
    if [ -f /etc/config/gl-cloud ] && [ "$(uci -q get gl-cloud.@cloud[0].enable)" != "0" ]; then
        uci -q set gl-cloud.@cloud[0].enable=0
        uci -q commit gl-cloud
    fi
    for s in gl-cloud rtty; do
        [ -x "/etc/init.d/$s" ] || continue
        "/etc/init.d/$s" enabled 2>/dev/null && "/etc/init.d/$s" disable >/dev/null 2>&1
    done
    pgrep -f '/usr/bin/gl-cloud' >/dev/null 2>&1 && /etc/init.d/gl-cloud stop >/dev/null 2>&1
    pgrep -x rtty >/dev/null 2>&1 && /etc/init.d/rtty stop >/dev/null 2>&1
    return 0
}

# ICCIDs of the SIM(s) GL currently has configured (network.*.iccid), F-less.
_current_iccids() {
    uci -q show network 2>/dev/null | sed -n "s/^network\.[^.]*\.iccid='\(.*\)'$/\1/p" \
        | tr -d 'Ff' | sort -u | tr '\n' ' '
}

# Forget every SIM except the ones in use: drops their entries from GL's
# per-SIM settings and APN history. $1 = "all" forgets the current SIM too
# (sim-swap: the outgoing SIM must not stay linked to the device). The
# caller stops gl_cellular_manager first so it cannot rewrite the files from
# memory. Prints only counts.
SIM_HISTORY_PRUNE() {
    local keep="" s
    [ "$1" = "all" ] || keep="$(_current_iccids)"
    [ -f "$_SIM_MAP" ] || [ -f "$_SIM_APN_DB" ] || return 0
    lua - "$_SIM_MAP" "$_SIM_APN_DB" "$keep" <<'EOF'
local jsonc = require "luci.jsonc"
local map_path, db_path, keep_s = arg[1], arg[2], arg[3] or ""
local keep = {}
for id in keep_s:gmatch("%d+") do keep[id] = true end
local function norm(id) return (tostring(id):gsub("[Ff]", "")) end
local function slurp(p)
    local f = io.open(p, "r"); if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end
local function save(p, s)
    local tmp = p .. ".ng_tmp"
    local f = assert(io.open(tmp, "w")); f:write(s, "\n"); f:close()
    assert(os.rename(tmp, p))
end
local dropped = 0
local s = slurp(map_path)
local m = s and jsonc.parse(s)
if type(m) == "table" then
    local out, n, kept = {}, 0, 0
    for k, v in pairs(m) do
        n = n + 1
        if keep[norm(k)] then out[k] = v; kept = kept + 1 end
    end
    if kept < n then
        dropped = dropped + (n - kept)
        save(map_path, kept == 0 and "{}" or jsonc.stringify(out, true))
    end
end
s = slurp(db_path)
local d = s and jsonc.parse(s)
if type(d) == "table" and type(d.apns) == "table" then
    local out, n = {}, #d.apns
    for _, e in ipairs(d.apns) do
        if type(e) == "table" and e.iccid and keep[norm(e.iccid)] then out[#out + 1] = e end
    end
    if #out < n then
        dropped = dropped + (n - #out)
        d.apns = out
        save(db_path, #out == 0 and '{"apns": []}' or jsonc.stringify(d, true))
    end
end
print(dropped)
EOF
    for s in "$_SIM_MAP" "$_SIM_APN_DB"; do [ -f "$s" ] && chmod 0644 "$s"; done
    if [ "$1" = "all" ]; then
        for s in $(uci -q show network 2>/dev/null | sed -n "s/^network\.\([^.]*\)\.iccid=.*/\1/p"); do
            uci -q delete "network.$s.iccid"
        done
        uci -q commit network
    fi
}

# Number of remembered SIMs that are not currently in use (no identifiers).
_sim_history_extra() {
    [ -f "$_SIM_MAP" ] || { echo 0; return; }
    lua - "$_SIM_MAP" "$(_current_iccids)" <<'EOF'
local jsonc = require "luci.jsonc"
local f = io.open(arg[1], "r"); local s = f and f:read("*a"); if f then f:close() end
local m = s and jsonc.parse(s) or {}
local keep, n = {}, 0
for id in (arg[2] or ""):gmatch("%d+") do keep[id] = true end
if type(m) == "table" then
    for k in pairs(m) do if not keep[(tostring(k):gsub("[Ff]", ""))] then n = n + 1 end end
end
print(n)
EOF
}

# Ask the eMMC to discard blocks freed while $@ runs (ext4 online discard).
# The controller is told the blocks are unused; physical erasure is up to it.
_with_discard() {
    local m rc
    for m in /overlay /data; do
        grep -q " $m ext4 " /proc/mounts && mount -o remount,discard "$m" 2>/dev/null
    done
    "$@"; rc=$?
    sync; sleep 6; sync
    for m in /overlay /data; do
        grep -q " $m ext4 " /proc/mounts && mount -o remount,nodiscard "$m" 2>/dev/null
    done
    return "$rc"
}

CLEAN_APPLY() {
    local d f
    # 1. System log to RAM only: unset any flash log_file, delete the old file.
    f="$(uci -q get system.@system[0].log_file 2>/dev/null)"
    if [ -n "$f" ]; then
        uci -q delete system.@system[0].log_file; uci -q commit system
        case "$f" in /tmp/*|/var/*) ;; *) rm -f "$f" "$f".* 2>/dev/null ;; esac
        /etc/init.d/log restart >/dev/null 2>&1
    fi
    # Flash syslog file left behind by an earlier log_file setting.
    rm -f /etc/sys_log /etc/sys_log.* 2>/dev/null
    # 2. tmpfs over each telemetry dir (before its daemon starts at boot).
    for d in $_CLEAN_DIRS; do _ram_back "$d"; done
    for d in $_CLEAN_OPTIONAL_DIRS; do [ -d "$d" ] && _ram_back "$d"; done
    _vendor_ram_back
    # 3. dnsmasq: no query log, no persistent cache.
    uci -q set dhcp.@dnsmasq[0].logqueries=0
    uci -q set dhcp.@dnsmasq[0].cachelocal=0
    uci -q commit dhcp
    # 4. DHCP leases to RAM (OpenWrt default is /tmp; enforce if GL redirected it).
    local lf; lf="$(uci -q get dhcp.@dnsmasq[0].leasefile 2>/dev/null)"
    case "$lf" in /tmp/*|"") ;; *) uci -q set dhcp.@dnsmasq[0].leasefile=/tmp/dhcp.leases; uci -q commit dhcp ;; esac
    # 5. DPI Flow Statistics off, and its on-flash per-client database gone.
    if [ -f /etc/config/gl_dpi_flow_statistics ]; then
        if [ "$(uci -q get gl_dpi_flow_statistics.global.enable 2>/dev/null)" != "0" ]; then
            uci -q set gl_dpi_flow_statistics.global.enable=0
            uci -q commit gl_dpi_flow_statistics
        fi
    fi
    rm -f "$_FLOW_DB" "$_FLOW_DB"-journal "$_FLOW_DB"-wal "$_FLOW_DB"-shm 2>/dev/null
    # 6. Kernel crash recorder (mtdoops) off: it copies the kernel log tail to
    #    a flash partition on every oops, and keeps it across reboots/upgrades.
    grep -q '^mtdoops ' /proc/modules 2>/dev/null && rmmod mtdoops 2>/dev/null
    # 7. Vendor logs: Wi-Fi debug logs, IPA debug, nginx error log.
    _wifi_logs_off
    _ipa_debug_off
    _nginx_log_off
    # 8. GoodCloud remote management off.
    CLOUD_BLOCK
    # 9. Sweep any legacy flash-persisted rotation timestamps. Older builds wrote
    #    these to /etc; the no-log model keeps them in RAM (/tmp) only, so any
    #    /etc copy is a forensic trace of when the identity last changed.
    rm -f /etc/norypt-ghost.last_imei_rotate /etc/norypt-ghost.last_wireless_rotate 2>/dev/null
    logger -t norypt-ghost "clean: telemetry persistence disabled"
}

CLEAN_WIPE() {
    local d
    # shellcheck disable=SC2086
    for d in $_CLEAN_DIRS $_CLEAN_OPTIONAL_DIRS; do _is_tmpfs "$d" && _empty_dir "$d"; done
    rm -f /tmp/dhcp.leases 2>/dev/null
}

# Stop GL's cellular manager, forget unused SIMs, restart it unless $2=norestart.
# $1 = keep|all (see SIM_HISTORY_PRUNE).
SIM_FORGET() {
    local mode="$1" n
    [ -x /etc/init.d/gl_cellular_manager ] && /etc/init.d/gl_cellular_manager stop >/dev/null 2>&1
    n="$(SIM_HISTORY_PRUNE "$mode")"
    [ "$2" = "norestart" ] || { [ -x /etc/init.d/gl_cellular_manager ] && /etc/init.d/gl_cellular_manager start >/dev/null 2>&1; }
    echo "${n:-0}"
}

# Pre-firmware-upgrade wipe. GL-iNet's "Keep Settings" upgrade copies every
# path in /lib/upgrade/keep.d from the RUNNING system — including
# /etc/oui-tertf/client.db, /etc/gl_modem_traffic/ and the DPI databases — so
# RAM-only history would otherwise be written into the new firmware's flash.
CLEAN_PREPARE_UPGRADE() {
    local s
    for s in gl_clients gl-tertf gl_dpi_flow_statistics; do
        [ -x "/etc/init.d/$s" ] && "/etc/init.d/$s" stop >/dev/null 2>&1
    done
    CLEAN_WIPE
    rm -f "$_FLOW_DB" "$_FLOW_DB"-journal "$_FLOW_DB"-wal "$_FLOW_DB"-shm \
          /etc/netifyd/qos_stats /etc/netifyd/content_protection_stats 2>/dev/null
    _nginx_log_off
    SIM_FORGET keep norestart >/dev/null
}

CLEAN_STATUS() {
    local _ng_status_fail=0 d v c
    _st_pass() { echo "  PASS  $1"; }
    _st_fail() { echo "  FAIL  $1"; _ng_status_fail=1; }
    _st_warn() { echo "  WARN  $1"; }

    if [ -z "$(uci -q get system.@system[0].log_file 2>/dev/null)" ]; then
        _st_pass "syslog not persisted to flash"
    else
        _st_fail "syslog log_file set — logs hitting flash"
    fi
    [ -e /etc/sys_log ] && _st_fail "old flash syslog file present (/etc/sys_log)"
    v="$(uci -q get system.@system[0].log_ip 2>/dev/null)"
    if [ -z "$v" ]; then
        _st_pass "no remote syslog"
    else
        _st_warn "remote syslog enabled (log_ip set) — logs leave the device"
    fi
    for d in $_CLEAN_DIRS; do
        if _is_tmpfs "$d"; then _st_pass "$d is RAM-backed"; else _st_fail "$d on flash"; fi
    done
    for d in $_CLEAN_OPTIONAL_DIRS $_VENDOR_DIRS; do
        [ -d "$d" ] || continue
        if _is_tmpfs "$d"; then _st_pass "$d is RAM-backed"; else _st_fail "$d on flash"; fi
    done
    for c in hostapd wpa_supplicant; do
        uci -q get "$c.log" >/dev/null 2>&1 || continue
        if [ "$(uci -q get "$c.log.log_folder_mode")" = "0" ]; then
            _st_pass "$c debug log not written to flash"
        else
            _st_fail "$c debug log written to flash (client MACs)"
        fi
    done
    if [ -d "$_WIFI_VENDOR_DIR" ]; then
        if ls "$_WIFI_VENDOR_DIR"/hostapd-*.log* "$_WIFI_VENDOR_DIR"/wpa_supplicant-*.log* >/dev/null 2>&1; then
            _st_fail "Wi-Fi daemon log files on flash ($_WIFI_VENDOR_DIR)"
        fi
        if [ -L "$_QCACLD_LOG" ]; then _st_pass "Wi-Fi driver command log discarded"; else _st_fail "Wi-Fi driver command log on flash"; fi
    fi
    if [ -f /etc/data/ipa/log_mode ]; then
        if grep -q on /etc/data/ipa/log_mode; then _st_fail "IPA debug logging on"; else _st_pass "IPA debug logging off"; fi
    fi
    if [ -L "$_NGX_RAM_LOG" ] && [ ! -s "$_NGX_FLASH_LOG" ]; then
        _st_pass "web server error log discarded"
    else
        _st_fail "web server error log kept (copied to flash by GL)"
    fi
    if [ "$(uci -q get dhcp.@dnsmasq[0].logqueries 2>/dev/null)" = "1" ]; then
        _st_fail "dnsmasq query logging enabled"
    else
        _st_pass "dnsmasq query logging off"
    fi
    case "$(uci -q get dhcp.@dnsmasq[0].leasefile 2>/dev/null)" in
        /tmp/*|"") _st_pass "DHCP leases in RAM" ;;
        *)         _st_fail "DHCP lease file on flash" ;;
    esac
    if [ "$(uci -q get gl_dpi_flow_statistics.global.enable 2>/dev/null)" = "1" ]; then
        _st_fail "DPI Flow Statistics enabled — per-client traffic log"
    else
        _st_pass "DPI Flow Statistics off"
    fi
    if [ -e "$_FLOW_DB" ]; then
        _st_fail "per-client DPI database on flash ($_FLOW_DB)"
    fi
    if grep -q '^mtdoops ' /proc/modules 2>/dev/null; then
        _st_warn "kernel crash recorder (mtdoops) loaded — crash logs reach flash"
    else
        _st_pass "kernel crash recorder off"
    fi
    v="$(_sim_history_extra 2>/dev/null)"
    case "$v" in
        0|'') _st_pass "no other SIMs remembered" ;;
        *)    _st_warn "$v SIM(s) not in use still remembered — run: norypt-ghost forget-sims" ;;
    esac
    if [ "$(uci -q get gl-cloud.@cloud[0].enable 2>/dev/null)" = "1" ] || \
       pgrep -f '/usr/bin/gl-cloud' >/dev/null 2>&1 || pgrep -x rtty >/dev/null 2>&1; then
        if _opt_enabled block_cloud; then
            _st_fail "GoodCloud remote management on"
        else
            _st_warn "GoodCloud remote management on (block_cloud=0)"
        fi
    else
        _st_pass "GoodCloud remote management off"
    fi
    if [ -e /etc/norypt-ghost.last_imei_rotate ] || [ -e /etc/norypt-ghost.last_wireless_rotate ]; then
        _st_fail "rotation timestamps on flash"
    fi
    return "$_ng_status_fail"
}
