#!/bin/bash

LOG_FILE="${USER_LIMIT_LOG:-/etc/ErwanScript/logs/useradd-limit.log}"
STATE_DIR="${USER_LIMIT_STATE_DIR:-/etc/ErwanScript/user-lock}"
MULTILOGIN_FILE="${USER_LIMIT_MULTILOGIN_FILE:-/etc/ErwanScript/multilogin.txt}"
MULTILOGIN_DEFAULT_FILE="${USER_LIMIT_MULTILOGIN_DEFAULT_FILE:-/etc/ErwanScript/multilogin-default.txt}"
OVPN_CHAIN_NAME="${USER_LIMIT_OVPN_CHAIN:-ERWANSCRIPT_OVPN_LOCK}"
UDP_CHAIN_NAME="${USER_LIMIT_UDP_CHAIN:-ERWANSCRIPT_UDP_LOCK}"
DNSTT_CHAIN_NAME="${USER_LIMIT_DNSTT_CHAIN:-ERWANSCRIPT_DNSTT_LOCK}"
OVPN_TCP_STATUS="${USER_LIMIT_OVPN_TCP_STATUS:-/etc/openvpn/tcp_stats.log}"
OVPN_UDP_STATUS="${USER_LIMIT_OVPN_UDP_STATUS:-/etc/openvpn/udp_stats.log}"
OVPN_PORTS="${USER_LIMIT_OVPN_PORTS:-1194,443,80,110}"
HYSTERIA_PORTS="${USER_LIMIT_HYSTERIA_PORTS:-36712,36713,5666,20000:50000}"
DNSTT_PORTS="${USER_LIMIT_DNSTT_PORTS:-53,5300}"
UDP_IP_LOCK_DIR="${USER_LIMIT_UDP_IP_LOCK_DIR:-/etc/ErwanScript/udp-ip-lock}"
UDP_BLOCK_DIR="${USER_LIMIT_UDP_BLOCK_DIR:-/etc/ErwanScript/udp-ip-block}"
UDP_LOCK_TTL_SECONDS="${USER_LIMIT_UDP_LOCK_TTL_SECONDS:-300}"
DNSTT_IP_LOCK_DIR="${USER_LIMIT_DNSTT_IP_LOCK_DIR:-/etc/ErwanScript/dnstt-ip-lock}"
DNSTT_BLOCK_DIR="${USER_LIMIT_DNSTT_BLOCK_DIR:-/etc/ErwanScript/dnstt-ip-block}"
DNSTT_LOCK_TTL_SECONDS="${USER_LIMIT_DNSTT_LOCK_TTL_SECONDS:-300}"
XRAY_IP_LOCK_DIR="${USER_LIMIT_XRAY_IP_LOCK_DIR:-/etc/ErwanScript/xray-ip-lock}"
XRAY_BLOCK_DIR="${USER_LIMIT_XRAY_BLOCK_DIR:-/etc/ErwanScript/xray-ip-block}"
XRAY_DISABLED_DIR="${USER_LIMIT_XRAY_DISABLED_DIR:-/etc/ErwanScript/xray-disabled}"
XRAY_CONFIG="${USER_LIMIT_XRAY_CONFIG:-/etc/xray/config.json}"
XRAY_LOCK_TTL_SECONDS="${USER_LIMIT_XRAY_LOCK_TTL_SECONDS:-300}"
SSH_LOGIN_TTL_SECONDS="${USER_LIMIT_SSH_LOGIN_TTL_SECONDS:-900}"
FREEZE_SECONDS="${USER_LIMIT_FREEZE_SECONDS:-3600}"

mkdir -p /etc/ErwanScript/logs "$STATE_DIR" "$XRAY_DISABLED_DIR"
touch "$LOG_FILE" "$MULTILOGIN_FILE" "$MULTILOGIN_DEFAULT_FILE"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

normalize_ip() {
    echo "$1" | sed -E 's/^\[//; s/\]$//; s/^::ffff://'
}

user_limit() {
    local user="$1"
    local limit

    limit="$(awk -v key="$user" '$1 == key { print $2; exit }' "$MULTILOGIN_FILE" 2>/dev/null)"
    if ! [[ "$limit" =~ ^[0-9]+$ ]] || [ "$limit" -le 0 ]; then
        limit="$(head -n 1 "$MULTILOGIN_DEFAULT_FILE" 2>/dev/null)"
    fi
    if ! [[ "$limit" =~ ^[0-9]+$ ]] || [ "$limit" -le 0 ]; then
        limit=1
    fi
    echo "$limit"
}

ensure_chain() {
    iptables -nL "$OVPN_CHAIN_NAME" >/dev/null 2>&1 || iptables -N "$OVPN_CHAIN_NAME"
    iptables -C INPUT -p tcp -m multiport --dports "$OVPN_PORTS" -j "$OVPN_CHAIN_NAME" >/dev/null 2>&1 || \
        iptables -I INPUT -p tcp -m multiport --dports "$OVPN_PORTS" -j "$OVPN_CHAIN_NAME"
    iptables -C INPUT -p udp -m multiport --dports "$OVPN_PORTS" -j "$OVPN_CHAIN_NAME" >/dev/null 2>&1 || \
        iptables -I INPUT -p udp -m multiport --dports "$OVPN_PORTS" -j "$OVPN_CHAIN_NAME"
    iptables -nL "$UDP_CHAIN_NAME" >/dev/null 2>&1 || iptables -N "$UDP_CHAIN_NAME"
    iptables -C INPUT -p udp -m multiport --dports "$HYSTERIA_PORTS" -j "$UDP_CHAIN_NAME" >/dev/null 2>&1 || \
        iptables -I INPUT -p udp -m multiport --dports "$HYSTERIA_PORTS" -j "$UDP_CHAIN_NAME"
    iptables -nL "$DNSTT_CHAIN_NAME" >/dev/null 2>&1 || iptables -N "$DNSTT_CHAIN_NAME"
    iptables -C INPUT -p udp -m multiport --dports "$DNSTT_PORTS" -j "$DNSTT_CHAIN_NAME" >/dev/null 2>&1 || \
        iptables -I INPUT -p udp -m multiport --dports "$DNSTT_PORTS" -j "$DNSTT_CHAIN_NAME"
}

block_ip_in_chain() {
    local chain="$1"
    local ip="$2"

    case "$ip" in
        ""|127.*|::1|localhost) return 0 ;;
    esac
    iptables -C "$chain" -s "$ip" -j REJECT >/dev/null 2>&1 || iptables -A "$chain" -s "$ip" -j REJECT
}

block_ip() {
    local ip="$1"

    block_ip_in_chain "$OVPN_CHAIN_NAME" "$ip"
    block_ip_in_chain "$UDP_CHAIN_NAME" "$ip"
    block_ip_in_chain "$DNSTT_CHAIN_NAME" "$ip"
}

unblock_ip_in_chain() {
    local chain="$1"
    local ip="$2"

    case "$ip" in
        ""|127.*|::1|localhost) return 0 ;;
    esac
    iptables -nL "$chain" >/dev/null 2>&1 || return 0
    while iptables -C "$chain" -s "$ip" -j REJECT >/dev/null 2>&1; do
        iptables -D "$chain" -s "$ip" -j REJECT
    done
}

unblock_ip() {
    local ip="$1"

    unblock_ip_in_chain "$OVPN_CHAIN_NAME" "$ip"
    unblock_ip_in_chain "$UDP_CHAIN_NAME" "$ip"
    unblock_ip_in_chain "$DNSTT_CHAIN_NAME" "$ip"
}

is_account_locked() {
    local user="$1"
    passwd -S "$user" 2>/dev/null | awk '{print $2}' | grep -q '^L$'
}

freeze_shell_path() {
    if [ -x /usr/sbin/nologin ]; then
        printf '/usr/sbin/nologin'
    elif [ -x /sbin/nologin ]; then
        printf '/sbin/nologin'
    else
        printf '/bin/false'
    fi
}

current_user_shell() {
    local user="$1"
    getent passwd "$user" | awk -F: '{print $7}'
}

freeze_account_php_style() {
    local user="$1"
    local freeze_shell

    usermod -L "$user" >/dev/null 2>&1
    freeze_shell="$(freeze_shell_path)"
    usermod -s "$freeze_shell" "$user" >/dev/null 2>&1 || true
}

unfreeze_account_php_style() {
    local user="$1"
    local original_shell="${2:-}"

    usermod -U "$user" >/dev/null 2>&1
    if [ -n "$original_shell" ] && [ "$original_shell" != "$(freeze_shell_path)" ]; then
        usermod -s "$original_shell" "$user" >/dev/null 2>&1 || true
    fi
}

freeze_state_file() {
    local user="$1"
    echo "$STATE_DIR/freeze-$user"
}

kill_ssh_sessions_for_user() {
    local user="$1"

    pkill -KILL -u "$user" 2>/dev/null
    pkill -f -KILL "^sshd-session: $user$" 2>/dev/null
    pkill -f -KILL "sshd-session: $user" 2>/dev/null
    pkill -f -KILL "^sshd: ${user}@" 2>/dev/null
    pkill -f -KILL "sshd: ${user} " 2>/dev/null
}

record_ip_for_user() {
    local user="$1"
    local ip="$2"
    local state_file

    state_file=$(freeze_state_file "$user")
    [ -n "$ip" ] || return 0
    [ -f "$state_file" ] || return 0

    grep -qxF "$ip" "$state_file" 2>/dev/null || echo "$ip" >> "$state_file"
}

disable_xray_user_for_freeze() {
    local user="$1"
    local observed_slots="$2"
    local safe_user disabled_file

    [ -f "$XRAY_CONFIG" ] || return 0
    command -v python3 >/dev/null 2>&1 || return 0

    safe_user="$(printf '%s' "$user" | tr -c 'A-Za-z0-9_.-' '_')"
    disabled_file="${XRAY_DISABLED_DIR}/${safe_user}.json"
    [ -f "$disabled_file" ] && return 0

    if python3 - "$XRAY_CONFIG" "$disabled_file" "$user" "$observed_slots" <<'PY'
import json, os, sys, tempfile

config_path, disabled_path, user, observed_slots = sys.argv[1:5]
removed = {
    "user": user,
    "observed_slots": int(observed_slots),
    "disabled_by": "cross-protocol-freeze",
    "vless": [],
    "vmess": [],
    "trojan": [],
    "shadowsocks": [],
}

with open(config_path, "r", encoding="utf-8") as handle:
    config = json.load(handle)

for inbound in config.get("inbounds", []):
    protocol = inbound.get("protocol")
    settings = inbound.get("settings") or {}
    clients = settings.get("clients")
    if not isinstance(clients, list):
        continue
    kept = []
    for client in clients:
        key = client.get("email") or client.get("name") or ""
        if protocol in ("trojan", "shadowsocks"):
            key = client.get("email", "")
        if key == user and protocol in removed:
            removed[protocol].append(client)
        else:
            kept.append(client)
    settings["clients"] = kept

if not any(removed[p] for p in ("vless", "vmess", "trojan", "shadowsocks")):
    sys.exit(0)

fd_cfg, tmp_cfg = tempfile.mkstemp(prefix="xray-config.", suffix=".json", dir=os.path.dirname(config_path))
fd_dis, tmp_dis = tempfile.mkstemp(prefix="xray-disabled.", suffix=".json", dir=os.path.dirname(disabled_path))
try:
    with os.fdopen(fd_cfg, "w", encoding="utf-8") as handle:
        json.dump(config, handle, indent=2)
        handle.write("\n")
    with os.fdopen(fd_dis, "w", encoding="utf-8") as handle:
        json.dump(removed, handle, indent=2)
        handle.write("\n")
    os.replace(tmp_cfg, config_path)
    os.replace(tmp_dis, disabled_path)
    os.chmod(config_path, 0o644)
    os.chmod(disabled_path, 0o644)
finally:
    for path in (tmp_cfg, tmp_dis):
        if os.path.exists(path):
            os.unlink(path)
PY
    then
        systemctl restart xray >/dev/null 2>&1 || true
        log "Disabled Xray account '$user' because total active logins exceeded the limit"
    fi
}

restore_xray_user_from_freeze() {
    local user="$1"
    local safe_user disabled_file

    [ -f "$XRAY_CONFIG" ] || return 0
    command -v python3 >/dev/null 2>&1 || return 0
    command -v jq >/dev/null 2>&1 || return 0

    safe_user="$(printf '%s' "$user" | tr -c 'A-Za-z0-9_.-' '_')"
    disabled_file="${XRAY_DISABLED_DIR}/${safe_user}.json"
    [ -f "$disabled_file" ] || return 0
    [ "$(jq -r '.disabled_by // empty' "$disabled_file" 2>/dev/null)" = "cross-protocol-freeze" ] || return 0

    if python3 - "$XRAY_CONFIG" "$disabled_file" <<'PY'
import json, os, sys, tempfile

config_path, disabled_path = sys.argv[1:3]
with open(config_path, "r", encoding="utf-8") as handle:
    config = json.load(handle)
with open(disabled_path, "r", encoding="utf-8") as handle:
    disabled = json.load(handle)

for inbound in config.get("inbounds", []):
    protocol = inbound.get("protocol")
    settings = inbound.get("settings") or {}
    clients = settings.get("clients")
    if not isinstance(clients, list):
        continue
    existing = set()
    for client in clients:
        key = client.get("email") or client.get("name") or ""
        if protocol in ("trojan", "shadowsocks"):
            key = client.get("email", "")
        if key:
            existing.add(key)
    for client in disabled.get(protocol, []):
        key = client.get("email") or client.get("name") or ""
        if protocol in ("trojan", "shadowsocks"):
            key = client.get("email", "")
        if key and key in existing:
            continue
        clients.append(client)
        if key:
            existing.add(key)

fd_cfg, tmp_cfg = tempfile.mkstemp(prefix="xray-config.", suffix=".json", dir=os.path.dirname(config_path))
try:
    with os.fdopen(fd_cfg, "w", encoding="utf-8") as handle:
        json.dump(config, handle, indent=2)
        handle.write("\n")
    os.replace(tmp_cfg, config_path)
    os.chmod(config_path, 0o644)
finally:
    if os.path.exists(tmp_cfg):
        os.unlink(tmp_cfg)
PY
    then
        rm -f "$disabled_file"
        systemctl restart xray >/dev/null 2>&1 || true
        log "Restored Xray account '$user' after freeze was cleared"
    fi
}

freeze_user() {
    local user="$1"
    local now="$2"
    local reason="$3"
    local state_file was_locked original_shell freeze_shell

    state_file=$(freeze_state_file "$user")
    if [ -f "$state_file" ]; then
        return 0
    fi

    original_shell="$(current_user_shell "$user")"
    freeze_shell="$(freeze_shell_path)"

    if is_account_locked "$user"; then
        was_locked=1
    else
        was_locked=0
        freeze_account_php_style "$user"
    fi

    {
        echo "FREEZE_UNTIL=$((now + FREEZE_SECONDS))"
        echo "WAS_LOCKED=$was_locked"
        echo "ORIGINAL_SHELL=$original_shell"
        echo "FREEZE_SHELL=$freeze_shell"
    } > "$state_file"

    kill_ssh_sessions_for_user "$user"
    log "Frozen account '$user' for $FREEZE_SECONDS seconds due to duplicate connection ($reason)"
}

thaw_user() {
    local user="$1"
    local state_file="$2"
    local was_locked="" ip="" original_shell="" freeze_shell=""

    [ -f "$state_file" ] || return 0

    while IFS='=' read -r key value; do
        case "$key" in
            WAS_LOCKED) was_locked="$value" ;;
            ORIGINAL_SHELL) original_shell="$value" ;;
            FREEZE_SHELL) freeze_shell="$value" ;;
        esac
    done < "$state_file"

    if [ "$was_locked" = "0" ]; then
        if [ -n "$original_shell" ] && [ "$original_shell" != "$freeze_shell" ]; then
            unfreeze_account_php_style "$user" "$original_shell"
        else
            unfreeze_account_php_style "$user"
        fi
    fi
    restore_xray_user_from_freeze "$user"

    while IFS= read -r ip; do
        case "$ip" in
            ""|FREEZE_UNTIL=*|WAS_LOCKED=*) continue ;;
        esac
        unblock_ip "$ip"
    done < "$state_file"

    rm -f "$state_file"
    log "Unfroze account '$user' because the current session count is within the configured limit"
}

ssh_session_count() {
    local user="$1"
    ps -eo pid=,user=,cmd= | awk -v user="$user" '
        $2 == user && ($0 ~ /sshd-session/ || $0 ~ /sshd: /) && $0 !~ /\[listener\]/ && $0 !~ /\[priv\]/ && $0 !~ /\[accepted\]/ {
            count++
        }
        END { print count + 0 }
    '
}

openvpn_ip_count() {
    local user="$1"
    {
        collect_openvpn_entries "$OVPN_TCP_STATUS"
        collect_openvpn_entries "$OVPN_UDP_STATUS"
    } | awk -F'|' -v user="$user" '$1 == user { print $2 }' | awk 'NF' | sort -u | wc -l
}

openvpn_session_count() {
    local user="$1"
    awk -F',' -v user="$user" '$1=="CLIENT_LIST" && $2==user { count++ } END { print count + 0 }' "$OVPN_TCP_STATUS" "$OVPN_UDP_STATUS" 2>/dev/null
}

safe_user_name() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

slot_count_file() {
    local file="$1"
    local now="$2"
    local ttl="$3"

    [ -f "$file" ] || {
        printf '0'
        return
    }
    awk -v now="$now" -v ttl="$ttl" 'NF >= 2 && (now - $2) <= ttl { count++ } END { print count + 0 }' "$file"
}

udp_slot_count() {
    local user="$1"
    local now="$2"
    local safe_user

    safe_user="$(safe_user_name "$user")"
    echo $(( $(slot_count_file "${UDP_IP_LOCK_DIR}/${safe_user}" "$now" "$UDP_LOCK_TTL_SECONDS") + $(slot_count_file "${UDP_BLOCK_DIR}/${safe_user}" "$now" "$UDP_LOCK_TTL_SECONDS") ))
}

dnstt_slot_count() {
    local user="$1"
    local now="$2"
    local safe_user

    safe_user="$(safe_user_name "$user")"
    echo $(( $(slot_count_file "${DNSTT_IP_LOCK_DIR}/${safe_user}" "$now" "$DNSTT_LOCK_TTL_SECONDS") + $(slot_count_file "${DNSTT_BLOCK_DIR}/${safe_user}" "$now" "$DNSTT_LOCK_TTL_SECONDS") ))
}

xray_slot_count() {
    local user="$1"
    local now="$2"
    local safe_user disabled_file allowed blocked disabled

    safe_user="$(safe_user_name "$user")"
    disabled_file="${XRAY_DISABLED_DIR}/${safe_user}.json"
    allowed="$(slot_count_file "${XRAY_IP_LOCK_DIR}/${safe_user}" "$now" "$XRAY_LOCK_TTL_SECONDS")"
    blocked="$(slot_count_file "${XRAY_BLOCK_DIR}/${safe_user}" "$now" "$XRAY_LOCK_TTL_SECONDS")"
    disabled=0
    if [ -f "$disabled_file" ] && command -v jq >/dev/null 2>&1; then
        disabled="$(jq -r '.observed_slots // 0' "$disabled_file" 2>/dev/null)"
        [[ "$disabled" =~ ^[0-9]+$ ]] || disabled=0
    fi
    if [ "$disabled" -gt $((allowed + blocked)) ]; then
        echo "$disabled"
    else
        echo $((allowed + blocked))
    fi
}

recent_ssh_login_count() {
    local user="$1"

    command -v journalctl >/dev/null 2>&1 || {
        printf '0'
        return
    }
    journalctl -u ssh -u erwanssh --since "${SSH_LOGIN_TTL_SECONDS} seconds ago" --no-pager 2>/dev/null | awk -v user="$user" '
        /Accepted / && / for / && / from / {
            line = $0
            sub(/^.* for /, "", line)
            sub(/ from .*$/, "", line)
            if (line == user) {
                count++
            }
        }
        END { print count + 0 }
    '
}

active_ssh_count() {
    local user="$1"
    ssh_session_count "$user"
}

active_total_count() {
    local user="$1"
    local now="$2"
    echo $(( $(active_ssh_count "$user") + $(openvpn_session_count "$user") + $(udp_slot_count "$user" "$now") + $(dnstt_slot_count "$user" "$now") + $(xray_slot_count "$user" "$now") ))
}

record_active_ips_for_user() {
    local user="$1"
    local now="$2"
    local safe_user active_file

    safe_user="$(safe_user_name "$user")"
    collect_openvpn_entries "$OVPN_TCP_STATUS" | awk -F'|' -v user="$user" '$1 == user { print $2 }'
    collect_openvpn_entries "$OVPN_UDP_STATUS" | awk -F'|' -v user="$user" '$1 == user { print $2 }'
    for active_file in "${UDP_IP_LOCK_DIR}/${safe_user}" "${UDP_BLOCK_DIR}/${safe_user}" "${DNSTT_IP_LOCK_DIR}/${safe_user}" "${DNSTT_BLOCK_DIR}/${safe_user}" "${XRAY_IP_LOCK_DIR}/${safe_user}" "${XRAY_BLOCK_DIR}/${safe_user}"; do
        [ -f "$active_file" ] || continue
        awk -v now="$now" 'NF >= 2 && (now - $2) <= 3600 { print $1 }' "$active_file"
    done
}

reconcile_frozen_users() {
    local state_file user limit total_count now

    now=$(date +%s)

    for state_file in "$STATE_DIR"/freeze-*; do
        [ -f "$state_file" ] || continue
        user=${state_file##*/freeze-}
        limit=$(user_limit "$user")
        total_count=$(active_total_count "$user" "$now")
        if [ "$total_count" -le "$limit" ]; then
            thaw_user "$user" "$state_file"
        fi
    done
}

unfreeze_expired_users() {
    local now state_file user freeze_until was_locked ip original_shell freeze_shell

    now=$(date +%s)

    for state_file in "$STATE_DIR"/freeze-*; do
        [ -f "$state_file" ] || continue

        user=${state_file##*/freeze-}
        freeze_until=""
        was_locked=""
        original_shell=""
        freeze_shell=""

        while IFS='=' read -r key value; do
            case "$key" in
                FREEZE_UNTIL) freeze_until="$value" ;;
                WAS_LOCKED) was_locked="$value" ;;
                ORIGINAL_SHELL) original_shell="$value" ;;
                FREEZE_SHELL) freeze_shell="$value" ;;
            esac
        done < "$state_file"

        [ -n "$freeze_until" ] || continue
        [ "$now" -lt "$freeze_until" ] && continue

        if [ "$was_locked" = "0" ]; then
            if [ -n "$original_shell" ] && [ "$original_shell" != "$freeze_shell" ]; then
                unfreeze_account_php_style "$user" "$original_shell"
            else
                unfreeze_account_php_style "$user"
            fi
        fi
        restore_xray_user_from_freeze "$user"

        while IFS= read -r ip; do
            case "$ip" in
                ""|FREEZE_UNTIL=*|WAS_LOCKED=*) continue ;;
            esac
            unblock_ip "$ip"
        done < "$state_file"

        rm -f "$state_file"
        log "Unfroze account '$user' after freeze expiry"
    done
}

handle_frozen_users() {
    local now state_file user freeze_until ip

    now=$(date +%s)

    for state_file in "$STATE_DIR"/freeze-*; do
        [ -f "$state_file" ] || continue

        user=${state_file##*/freeze-}
        freeze_until=""

        while IFS='=' read -r key value; do
            case "$key" in
                FREEZE_UNTIL) freeze_until="$value" ;;
            esac
        done < "$state_file"

        [ -n "$freeze_until" ] || continue
        [ "$now" -ge "$freeze_until" ] && continue

        kill_ssh_sessions_for_user "$user"

        while IFS= read -r ip; do
            case "$ip" in
                ""|FREEZE_UNTIL=*|WAS_LOCKED=*) continue ;;
            esac
            block_ip "$ip"
        done < "$state_file"
    done
}

limit_ssh_sessions() {
    local now users user pids pid_count limit

    now=$(date +%s)
    users=$(ps -eo user=,cmd= | awk '
        (/sshd-session/ || /sshd: /) && $1 != "root" && $1 != "sshd" && $0 !~ /\[listener\]/ && $0 !~ /\[priv\]/ && $0 !~ /\[accepted\]/ {
            print $1
        }
    ' | sort -u)

    for user in $users; do
        pids=$(ps -eo pid=,user=,cmd= | awk -v user="$user" '
            $2 == user && ($0 ~ /sshd-session/ || $0 ~ /sshd: /) && $0 !~ /\[listener\]/ && $0 !~ /\[priv\]/ && $0 !~ /\[accepted\]/ {
                print $1
            }
        ')

        pid_count=$(printf '%s\n' "$pids" | sed '/^$/d' | wc -l)
        limit=$(user_limit "$user")
        if [ "$pid_count" -gt "$limit" ]; then
            freeze_user "$user" "$now" "SSH multi-login limit $limit"
        fi
    done
}

collect_openvpn_entries() {
    local file="$1"

    [ -f "$file" ] || return 0
    awk -F',' '
        $1 == "CLIENT_LIST" && $2 != "" && $3 != "" {
            print $2 "|" $3
        }
    ' "$file" | while IFS='|' read -r user real_address; do
        printf '%s|%s\n' "$user" "$(normalize_ip "${real_address%%:*}")"
    done
}

limit_openvpn_sessions() {
    local now tmpfile user limit freeze_file ip_count ip

    ensure_chain
    now=$(date +%s)
    tmpfile="$(mktemp)"

    collect_openvpn_entries "$OVPN_TCP_STATUS" >> "$tmpfile"
    collect_openvpn_entries "$OVPN_UDP_STATUS" >> "$tmpfile"

    while IFS= read -r user; do
        [ -n "$user" ] || continue
        limit=$(user_limit "$user")
        freeze_file=$(freeze_state_file "$user")
        ip_count=$(awk -F'|' -v user="$user" '$1 == user { print $2 }' "$tmpfile" | awk 'NF' | sort -u | wc -l)

        if [ -f "$freeze_file" ]; then
            while IFS= read -r ip; do
                [ -n "$ip" ] || continue
                record_ip_for_user "$user" "$ip"
                block_ip "$ip"
            done < <(awk -F'|' -v user="$user" '$1 == user { print $2 }' "$tmpfile" | awk 'NF' | sort -u)
            continue
        fi

        if [ "$ip_count" -gt "$limit" ]; then
            freeze_user "$user" "$now" "OpenVPN multi-IP limit $limit"
            while IFS= read -r ip; do
                [ -n "$ip" ] || continue
                record_ip_for_user "$user" "$ip"
                block_ip "$ip"
            done < <(awk -F'|' -v user="$user" '$1 == user { print $2 }' "$tmpfile" | awk 'NF' | sort -u)
        else
            while IFS= read -r ip; do
                [ -n "$ip" ] || continue
                unblock_ip "$ip"
            done < <(awk -F'|' -v user="$user" '$1 == user { print $2 }' "$tmpfile" | awk 'NF' | sort -u)
        fi
    done < <(awk -F'|' '{ print $1 }' "$tmpfile" | awk 'NF' | sort -u)

    rm -f "$tmpfile"
}

limit_total_sessions() {
    local now user limit total_count xray_count ip state_file

    ensure_chain
    now=$(date +%s)

    {
        ps -eo user=,cmd= | awk '(/sshd-session/ || /sshd: .*@/) && $1 != "root" { print $1 }'
        if command -v journalctl >/dev/null 2>&1; then
            journalctl -u erwanssh --since "${SSH_LOGIN_TTL_SECONDS} seconds ago" --no-pager 2>/dev/null | awk '
                /Accepted / && / for / && / from / {
                    line = $0
                    sub(/^.* for /, "", line)
                    sub(/ from .*$/, "", line)
                    print line
                }
            '
        fi
        awk -F',' '$1=="CLIENT_LIST" && $2 != "" { print $2 }' "$OVPN_TCP_STATUS" "$OVPN_UDP_STATUS" 2>/dev/null
        find "$UDP_IP_LOCK_DIR" "$UDP_BLOCK_DIR" "$DNSTT_IP_LOCK_DIR" "$DNSTT_BLOCK_DIR" "$XRAY_IP_LOCK_DIR" "$XRAY_BLOCK_DIR" -maxdepth 1 -type f 2>/dev/null | while IFS= read -r state_file; do
            basename "$state_file"
        done
    } | awk 'NF' | sort -u | while IFS= read -r user; do
        [ -n "$user" ] || continue
        limit=$(user_limit "$user")
        total_count=$(active_total_count "$user" "$now")
        if [ "$total_count" -gt "$limit" ]; then
            xray_count=$(xray_slot_count "$user" "$now")
            freeze_user "$user" "$now" "total active logins $total_count/$limit across SSH/OVPN/UDP/DNSTT/Xray"
            while IFS= read -r ip; do
                [ -n "$ip" ] || continue
                record_ip_for_user "$user" "$ip"
                block_ip "$ip"
            done < <(record_active_ips_for_user "$user" "$now" | awk 'NF' | sort -u)
            disable_xray_user_for_freeze "$user" "$xray_count"
        fi
    done
}

reconcile_frozen_users
unfreeze_expired_users
handle_frozen_users
limit_ssh_sessions
limit_openvpn_sessions
limit_total_sessions
