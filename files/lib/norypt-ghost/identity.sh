#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Norypt Ghost — full-identity stage/apply engine.
# shellcheck source=/dev/null
. /lib/norypt-ghost/functions.sh   # also pulls profile.sh

_PENDING=/etc/norypt-ghost.identity-pending

# Reject a derived identity whose text fields did not expand cleanly: an
# unexpanded "{10lower}" token or an empty/short PSK would be a public,
# guessable Wi-Fi key.
_identity_values_ok() {
    local v
    for v in "$NG_SSID" "$NG_PSK" "$NG_GUEST_PSK" "$NG_HOSTNAME"; do
        [ -n "$v" ] || return 1
        case "$v" in *'{'*|*'}'*) return 1 ;; esac
    done
    [ ${#NG_PSK} -ge 12 ] && [ ${#NG_GUEST_PSK} -ge 12 ] && [ "$NG_PSK" != "$NG_GUEST_PSK" ]
}

# Pick a coherent identity and apply everything that can be applied before the
# reboot, in an order that never leaves a half-rotated identity on air:
#   1. derive + validate every value (nothing written yet),
#   2. RF off, write the IMEIs, read them back (abort here on any failure —
#      nothing else has changed, RF stays off),
#   3. wireless/system UCI, host keys, TLS certs,
#   4. a pending marker so the next boot verifies the IMEIs before RF returns.
# Writing the IMEIs now matters: gl_cellular_manager (S23) attaches before our
# S25 service can run, so an IMEI staged only for the next boot would let the
# OLD IMEI re-attach first and sit on the same cell right next to the new one.
# Prints the profile id on stdout; diagnostics go to stderr.
IDENTITY_STAGE() {
    local region default_region id imei1 imei2 iface
    default_region="$(uci -q get norypt-ghost.options.default_region 2>/dev/null)"
    case "$default_region" in EU|NA) ;; *) default_region=NA ;; esac
    region="$(_mcc_region "$(READ_MCC)" "$default_region")"

    id="$(_profile_pick "$region")" || { echo "no profile for region $region" >&2; return 1; }
    _profile_derive "$id" || { echo "profile derive failed for $id" >&2; return 1; }
    _identity_values_ok || { echo "profile $id produced an invalid SSID/PSK/hostname — aborting, nothing changed" >&2; return 1; }

    imei1="$(_gen_imei 1 profile "$NG_TAC")"
    imei2="$(_gen_imei 2 profile "$NG_TAC")"
    if ! IMEI_VALID "$imei1" || ! IMEI_VALID "$imei2" || [ "$imei1" = "$imei2" ]; then
        echo "IMEI generation failed — aborting, nothing changed" >&2
        return 1
    fi

    MODEM_RF_DISABLE
    if ! SET_IMEIS "$imei1" "$imei2" || ! VERIFY_IMEIS "$imei1" "$imei2"; then
        echo "IMEI write/verify failed — RF left disabled, no other identifier changed" >&2
        _recovery_hint
        return 1
    fi
    RAT_LOCK_APPLY >/dev/null 2>&1

    # Wireless BSSIDs — all AP ifaces share the profile's wifi OUI.
    # shellcheck disable=SC2154
    for iface in wifi2g wifi5g wifi6g guest2g guest5g guest6g; do
        uci -q get "wireless.${iface}" >/dev/null 2>&1 && \
            uci set "wireless.${iface}.macaddr=$(MAC_GEN routers "$NG_WIFI_OUI")"
    done
    # STA (upstream) gets the client-class OUI.
    if uci -q get wireless.sta >/dev/null 2>&1; then
        uci set "wireless.sta.macaddr=$(MAC_GEN clients "$NG_CLIENT_OUI")"
    fi
    # SSIDs.
    for iface in wifi2g wifi5g wifi6g; do
        uci -q get "wireless.${iface}" >/dev/null 2>&1 && uci set "wireless.${iface}.ssid=$NG_SSID"
    done
    for iface in guest2g guest5g guest6g; do
        uci -q get "wireless.${iface}" >/dev/null 2>&1 && uci set "wireless.${iface}.ssid=$NG_GUEST_SSID"
    done
    # PSKs.
    for iface in wifi2g wifi5g wifi6g;    do uci -q get "wireless.${iface}" >/dev/null 2>&1 && uci set "wireless.${iface}.key=$NG_PSK"; done
    for iface in guest2g guest5g guest6g; do uci -q get "wireless.${iface}" >/dev/null 2>&1 && uci set "wireless.${iface}.key=$NG_GUEST_PSK"; done
    GL_RANDOM_BSSID_OFF
    uci commit wireless

    # Wired MAC + hostname + upstream DHCP hostname.
    RANDOMIZE_WIRED_MAC "$NG_CLIENT_OUI"
    uci set "system.@system[0].hostname=$NG_HOSTNAME"; uci commit system
    printf '%s' "$NG_HOSTNAME" > /proc/sys/kernel/hostname
    uci -q set "network.wan.hostname=$NG_DHCP_HOSTNAME" 2>/dev/null; uci -q commit network

    # Host keys + TLS certs now, so the first boot already serves new ones
    # (dropbear starts at S19, before any S25 regen could run). Running daemons
    # keep their loaded keys until the reboot.
    IDENTITY_REGEN_KEYS norestart

    # Boot-time verification marker: the profile id and a 4-hex check tag —
    # never an IMEI. Removed as soon as the boot check passes.
    ( umask 077
      printf 'PROFILE_ID=%s\nIMEI_TAG=%s\n' "$id" "$(IMEI_TAG "$imei1" "$imei2")" > "$_PENDING" )
    unset imei1 imei2

    echo "$id"
}

# Post-reboot check (invoked by norypt-ghost-sim-swap S25). The IMEIs were
# written before the reboot; confirm the modem still holds them (by check tag)
# and, only if it does not, write a fresh pair from the same profile with RF
# off. The marker is kept on failure so the next boot retries, and RF stays
# off — never transmit an unverified identity.
IDENTITY_APPLY_BOOT() {
    [ -f "$_PENDING" ] || return 0
    local PROFILE_ID="" IMEI_TAG="" STAGED_IMEI1="" STAGED_IMEI2="" REGEN_KEYS=0 r1 r2 n1 n2
    . "$_PENDING"
    # Marker from an older build that stored the IMEIs themselves.
    [ -z "$IMEI_TAG" ] && [ -n "$STAGED_IMEI1" ] && IMEI_TAG="$(IMEI_TAG "$STAGED_IMEI1" "$STAGED_IMEI2")"
    unset STAGED_IMEI1 STAGED_IMEI2

    r1="$(READ_IMEI)"; r2="$(READ_IMEI_SLOT2)"
    if ! IMEI_VALID "$r1" || ! IMEI_VALID "$r2" || [ -z "$IMEI_TAG" ] || \
       [ "$(IMEI_TAG "$r1" "$r2")" != "$IMEI_TAG" ]; then
        MODEM_RF_DISABLE
        _profile_derive "$PROFILE_ID" >/dev/null 2>&1 || NG_TAC=""
        n1="$(_gen_imei 1 profile "$NG_TAC")"; n2="$(_gen_imei 2 profile "$NG_TAC")"
        if ! IMEI_VALID "$n1" || ! IMEI_VALID "$n2" || [ "$n1" = "$n2" ] || \
           ! SET_IMEIS "$n1" "$n2" || ! VERIFY_IMEIS "$n1" "$n2"; then
            logger -p err -t norypt-ghost "identity: IMEI verify/rewrite failed — RF left disabled; retrying next boot (or run: norypt-ghost new-identity)"
            _screen_splash error
            return 1
        fi
        RAT_LOCK_APPLY
        _at AT+CFUN=1 >/dev/null 2>&1
    fi
    unset r1 r2 n1 n2
    rm -f "$_PENDING"
    # Marker from an older build that deferred key regeneration to boot.
    [ "$REGEN_KEYS" = "1" ] && IDENTITY_REGEN_KEYS
    date '+%Y-%m-%d %H:%M (new-identity)' > /tmp/norypt-ghost.last_imei_rotate
    logger -t norypt-ghost "identity applied: profile=$PROFILE_ID"
    _screen_splash "done"
}

# Self-signed cert generator: px5g if present, else openssl (GL-iNet 4.x ships
# openssl, not px5g). $1 = key out, $2 = cert out, $3 = openssl -config file
# (subject + extensions), $4 = px5g -subj fallback. Writes to *.new and renames,
# so a failed generation never leaves the service without a cert.
_ng_gen_selfsigned() {
    local key="$1" crt="$2" cfg="$3" subj="$4" rc=1
    rm -f "${key}.new" "${crt}.new"
    ( umask 077
      if [ -x /usr/sbin/px5g ]; then
          /usr/sbin/px5g selfsigned -days 730 -newkey rsa:2048 \
              -keyout "${key}.new" -out "${crt}.new" -subj "$subj"
      elif [ -x /usr/bin/openssl ]; then
          /usr/bin/openssl req -x509 -nodes -days 730 -newkey rsa:2048 \
              -keyout "${key}.new" -out "${crt}.new" -config "$cfg"
      else
          exit 1
      fi ) >/dev/null 2>&1 && [ -s "${key}.new" ] && [ -s "${crt}.new" ] && rc=0
    if [ "$rc" = "0" ]; then
        mv -f "${key}.new" "$key" && mv -f "${crt}.new" "$crt"
    else
        rm -f "${key}.new" "${crt}.new"
    fi
    return "$rc"
}

# Regenerate SSH host keys and the web-admin TLS certs — permanent device IDs:
# the key fingerprint identifies the unit to anyone who can reach the admin
# port, across every other rotation.
# $1 = "norestart" to only rewrite the files (a reboot follows and every
# daemon loads the new keys at start); otherwise restart the services now.
IDENTITY_REGEN_KEYS() {
    local cfg restart=1
    [ "$1" = "norestart" ] && restart=0
    # dropbear regenerates any missing host key when it starts.
    rm -f /etc/dropbear/dropbear_*_host_key 2>/dev/null
    [ "$restart" = "1" ] && /etc/init.d/dropbear restart >/dev/null 2>&1

    # The subject/SAN below is byte-for-byte GL-iNet's stock one
    # (uci-defaults 80_nginx-oui), shared by every GL unit — so the new cert
    # differs from stock only in its fresh key and validity dates.
    cfg="$(mktemp /tmp/norypt-ghost-cert.XXXXXX)" || return 0
    cat > "$cfg" <<'EOF'
[req]
distinguished_name  = req_distinguished_name
x509_extensions     = v3_req
prompt              = no
string_mask         = utf8only

[req_distinguished_name]
C                   = HK
ST                  = Hong Kong
L                   = Hong Kong
O                   = GLiNet
CN                  = console.gl-inet.com

[v3_req]
keyUsage            = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage    = serverAuth
subjectAltName      = @alt_names

[alt_names]
DNS.1               = console.gl-inet.com
IP.1                = 192.168.8.1
EOF

    # GL-iNet admin UI (nginx, ports 80/443) — the cert clients actually see.
    if [ -f /etc/nginx/nginx.key ] || [ -f /etc/nginx/nginx.cer ]; then
        if _ng_gen_selfsigned /etc/nginx/nginx.key /etc/nginx/nginx.cer "$cfg" \
                "/C=HK/ST=Hong Kong/L=Hong Kong/O=GLiNet/CN=console.gl-inet.com"; then
            [ "$restart" = "1" ] && /etc/init.d/nginx restart >/dev/null 2>&1
        else
            logger -p warning -t norypt-ghost "identity: admin TLS cert regeneration failed (no px5g/openssl?)"
        fi
    fi
    # LuCI (uhttpd), when installed and serving HTTPS.
    if [ -x /etc/init.d/uhttpd ] && { [ -f /etc/uhttpd.key ] || [ -f /etc/uhttpd.crt ]; }; then
        _ng_gen_selfsigned /etc/uhttpd.key /etc/uhttpd.crt "$cfg" \
            "/C=HK/ST=Hong Kong/L=Hong Kong/O=GLiNet/CN=console.gl-inet.com" || \
            logger -p warning -t norypt-ghost "identity: LuCI TLS cert regeneration failed"
        [ "$restart" = "1" ] && /etc/init.d/uhttpd restart >/dev/null 2>&1
    fi
    rm -f "$cfg"
}
