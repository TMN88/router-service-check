#!/bin/sh

set -u

TAG="podkop-vpn-failover"
BASE_URL="${PVF_BASE_URL:-https://raw.githubusercontent.com/TMN88/router-service-check/podkop-vpn-failover-apk}"
WORKER_DST="/usr/bin/podkop-vpn-failover"
CONTROL_DST="/usr/bin/podkop-vpn-failover-control"
INIT_DST="/etc/init.d/podkop-vpn-failover"
INSTALL_LUCI_COMMANDS="${INSTALL_LUCI_COMMANDS:-1}"
PKG_MANAGER=""

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || fail "Run this installer as root."
[ -r /etc/openwrt_release ] || fail "This installer is intended for OpenWrt."
command -v uci >/dev/null 2>&1 || fail "uci is required."

if command -v apk >/dev/null 2>&1; then
    PKG_MANAGER="apk"
elif command -v opkg >/dev/null 2>&1; then
    PKG_MANAGER="opkg"
else
    fail "Neither apk nor opkg was found."
fi

fetch() {
    url="$1"; dst="$2"
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$url" -o "$dst"; return $?; fi
    if command -v uclient-fetch >/dev/null 2>&1; then uclient-fetch -q -O "$dst" "$url"; return $?; fi
    if command -v wget >/dev/null 2>&1; then wget -q -O "$dst" "$url"; return $?; fi
    return 127
}
pkg_installed() {
    if [ "$PKG_MANAGER" = "apk" ]; then
        apk info -e "$1" >/dev/null 2>&1
    else
        opkg status "$1" 2>/dev/null | grep -q '^Status: install .* installed$'
    fi
}
pkg_update() { if [ "$PKG_MANAGER" = "apk" ]; then apk update; else opkg update; fi; }
pkg_install() { if [ "$PKG_MANAGER" = "apk" ]; then apk add "$@"; else opkg install "$@"; fi; }

need_update=0
pkg_installed curl || need_update=1
if [ "$INSTALL_LUCI_COMMANDS" = "1" ] && ! pkg_installed luci-app-commands; then need_update=1; fi
if [ "$need_update" -eq 1 ]; then
    info "Updating $PKG_MANAGER package indexes..."
    pkg_update || warn "$PKG_MANAGER update reported errors; trying available indexes."
fi
if ! pkg_installed curl; then info "Installing curl..."; pkg_install curl || fail "curl installation failed."; fi

for cmd in logger awk sort cut sed grep; do command -v "$cmd" >/dev/null 2>&1 || fail "$cmd is required."; done
if ! command -v podkop >/dev/null 2>&1 && [ ! -x /usr/bin/podkop ]; then fail "Podkop is not installed."; fi
[ -x /etc/init.d/podkop ] || fail "Podkop init service was not found at /etc/init.d/podkop."
connection_type="$(uci -q get podkop.main.connection_type 2>/dev/null)"
[ "$connection_type" = "vpn" ] || warn "podkop.main.connection_type is '${connection_type:-unset}', not 'vpn'. Failover stays idle unless Podkop main uses VPN mode."

TMP_WORKER="/tmp/${TAG}.worker.$$"
TMP_CONTROL="/tmp/${TAG}.control.$$"
TMP_INIT="/tmp/${TAG}.init.$$"
trap 'rm -f "$TMP_WORKER" "$TMP_CONTROL" "$TMP_INIT"' EXIT INT TERM
fetch "${BASE_URL}/podkop-vpn-failover" "$TMP_WORKER" || fail "Failed to download worker."
fetch "${BASE_URL}/podkop-vpn-failover-control" "$TMP_CONTROL" || fail "Failed to download control wrapper."
fetch "${BASE_URL}/podkop-vpn-failover.init" "$TMP_INIT" || fail "Failed to download procd init script."
[ -s "$TMP_WORKER" ] || fail "Downloaded worker is empty."
[ -s "$TMP_CONTROL" ] || fail "Downloaded control wrapper is empty."
[ -s "$TMP_INIT" ] || fail "Downloaded init script is empty."
/bin/sh -n "$TMP_WORKER" || fail "Worker syntax check failed."
/bin/sh -n "$TMP_CONTROL" || fail "Control wrapper syntax check failed."
/bin/sh -n "$TMP_INIT" || fail "Init script syntax check failed."
grep -q '^# podkop-vpn-failover$' "$TMP_WORKER" || fail "Worker signature mismatch."

existing_install=0; was_running=0; was_enabled=0
if [ -x "$INIT_DST" ]; then
    existing_install=1
    "$INIT_DST" running >/dev/null 2>&1 && was_running=1
    "$INIT_DST" enabled >/dev/null 2>&1 && was_enabled=1
    info "Stopping existing failover service before update..."
    "$INIT_DST" stop >/dev/null 2>&1 || true
fi
cp "$TMP_WORKER" "$WORKER_DST" || fail "Failed to install worker."
chmod 0755 "$WORKER_DST" || fail "Failed to chmod worker."
cp "$TMP_CONTROL" "$CONTROL_DST" || fail "Failed to install control wrapper."
chmod 0755 "$CONTROL_DST" || fail "Failed to chmod control wrapper."
cp "$TMP_INIT" "$INIT_DST" || fail "Failed to install init script."
chmod 0755 "$INIT_DST" || fail "Failed to chmod init script."

if [ "$INSTALL_LUCI_COMMANDS" = "1" ] && ! pkg_installed luci-app-commands; then
    info "Installing luci-app-commands..."
    if ! pkg_install luci-app-commands; then
        warn "luci-app-commands install failed; skipping LuCI buttons."
        INSTALL_LUCI_COMMANDS=0
    fi
fi
configure_luci_command() {
    section="$1"; name="$2"; command_line="$3"
    uci -q delete "luci.$section" >/dev/null 2>&1 || true
    uci set "luci.$section=command"
    uci set "luci.$section.name=$name"
    uci set "luci.$section.command=$command_line"
}
if [ "$INSTALL_LUCI_COMMANDS" = "1" ]; then
    configure_luci_command pvf_status 'VPN Failover: Status' '/usr/bin/podkop-vpn-failover status'
    configure_luci_command pvf_test 'VPN Failover: Test all VPNs' '/usr/bin/podkop-vpn-failover test'
    configure_luci_command pvf_logs 'VPN Failover: Logs' '/usr/bin/podkop-vpn-failover logs'
    configure_luci_command pvf_config 'VPN Failover: Show settings' '/usr/bin/podkop-vpn-failover config'
    configure_luci_command pvf_start 'VPN Failover: Enable + Start' '/usr/bin/podkop-vpn-failover-control start'
    configure_luci_command pvf_restart 'VPN Failover: Restart' '/usr/bin/podkop-vpn-failover-control restart'
    configure_luci_command pvf_stop 'VPN Failover: Stop + Disable' '/usr/bin/podkop-vpn-failover-control stop'
    uci commit luci
fi
if [ "$existing_install" -eq 1 ]; then
    if [ "$was_enabled" -eq 1 ]; then "$INIT_DST" enable >/dev/null 2>&1 || fail "Failed to restore autostart."
    else "$INIT_DST" disable >/dev/null 2>&1 || true; fi
    if [ "$was_running" -eq 1 ]; then "$CONTROL_DST" restart || fail "Updated files installed, but service restart failed."
    else "$INIT_DST" stop >/dev/null 2>&1 || true; fi
else
    "$INIT_DST" disable >/dev/null 2>&1 || true
    "$INIT_DST" stop >/dev/null 2>&1 || true
fi
rm -f "$TMP_WORKER" "$TMP_CONTROL" "$TMP_INIT"
trap - EXIT INT TERM
info "Installed $TAG (package manager: $PKG_MANAGER)."
if [ "$existing_install" -eq 1 ]; then
    [ "$was_running" -eq 1 ] && service_state="RUNNING" || service_state="STOPPED"
    [ "$was_enabled" -eq 1 ] && autostart_state="ENABLED" || autostart_state="DISABLED"
    printf 'Service: %s\nAutostart: %s\n' "$service_state" "$autostart_state"
else
    printf 'Service: STOPPED\nAutostart: DISABLED\n'
    printf 'Check VPNs: /usr/bin/podkop-vpn-failover test\n'
    printf 'Check status: /usr/bin/podkop-vpn-failover status\n'
    printf 'Enable failover: /usr/bin/podkop-vpn-failover-control start\n'
fi
[ "$INSTALL_LUCI_COMMANDS" = "1" ] && printf 'LuCI commands: System -> Custom Commands\n'
