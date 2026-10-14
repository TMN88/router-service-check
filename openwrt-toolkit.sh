#!/bin/sh
# OpenWrt Toolkit — interactive installer for selected networking components.
# Only shell features available in BusyBox ash are used.
set -u

TOOLKIT_VERSION="1.0"
BASE_TMP="/tmp/openwrt-toolkit.$$"
mkdir -p "$BASE_TMP" || exit 1
trap 'rm -rf "$BASE_TMP"' EXIT HUP INT TERM

C_RESET='' C_CYAN='' C_GREEN='' C_YELLOW='' C_RED='' C_BOLD=''
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET="$(printf '\033[0m')"; C_CYAN="$(printf '\033[36m')"
  C_GREEN="$(printf '\033[32m')"; C_YELLOW="$(printf '\033[33m')"
  C_RED="$(printf '\033[31m')"; C_BOLD="$(printf '\033[1m')"
fi

info(){ printf '%s[INFO]%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
ok(){ printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn(){ printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err(){ printf '%s[ERR ]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
step(){ printf '\n%s==>%s %s\n' "$C_BOLD" "$C_RESET" "$*"; }

[ "$(id -u)" = "0" ] || { err "Запустите скрипт от root."; exit 1; }
[ -r /etc/openwrt_release ] || { err "Этот скрипт предназначен для OpenWrt."; exit 1; }
command -v uci >/dev/null 2>&1 || { err "Не найдена команда uci; система не похожа на OpenWrt."; exit 1; }

if command -v apk >/dev/null 2>&1; then PM=apk; elif command -v opkg >/dev/null 2>&1; then PM=opkg; else
  err "Не найден пакетный менеджер apk/opkg."; exit 1
fi

RELEASE="$(sed -n "s/^DISTRIB_RELEASE='\([^']*\)'.*/\1/p" /etc/openwrt_release | head -n1)"
VERSION_MAJOR="$(printf '%s' "$RELEASE" | cut -d. -f1)"
ARCH="$(ubus call system board 2>/dev/null | jsonfilter -e '@.release.target' 2>/dev/null || true)"
if [ "$PM" = opkg ]; then
  ARCH_PACKAGES="$(opkg print-architecture 2>/dev/null | awk '$1=="arch" && $2!="all" {a=$2} END{print a}' || true)"
else
  ARCH_PACKAGES="$(apk --print-arch 2>/dev/null || true)"
fi
MODEL="$(cat /tmp/sysinfo/model 2>/dev/null || printf 'неизвестна')"

fetch(){
  url="$1"; out="$2"
  if command -v curl >/dev/null 2>&1; then curl -fsSL --connect-timeout 10 --max-time 180 "$url" -o "$out"
  elif command -v uclient-fetch >/dev/null 2>&1; then uclient-fetch -q -O "$out" "$url"
  elif command -v wget >/dev/null 2>&1; then wget -q -O "$out" "$url"
  else return 127; fi
}
pkg_installed(){
  if [ "$PM" = apk ]; then apk info -e "$1" >/dev/null 2>&1
  else opkg status "$1" 2>/dev/null | grep -q '^Status: install .* installed$'; fi
}
pkg_update(){ if [ "$PM" = apk ]; then apk update; else opkg update; fi; }
pkg_install(){
  name="$1"
  if pkg_installed "$name"; then ok "Уже установлен пакет $name"; return 0; fi
  if [ "$PM" = apk ]; then apk add "$name"; else opkg install "$name"; fi
}
install_ru(){
  # Take a list of potential translation names; only installed if package is in configured feeds.
  for pkg in "$@"; do
    if pkg_installed "$pkg"; then continue; fi
    if [ "$PM" = apk ]; then
      apk add "$pkg" >/dev/null 2>&1 && { ok "Русский язык: $pkg"; return 0; }
    else
      opkg install "$pkg" >/dev/null 2>&1 && { ok "Русский язык: $pkg"; return 0; }
    fi
  done
  warn "Русский перевод недоступен в подключённых feeds для этого компонента."
  return 0
}
run_remote_installer(){
  label="$1"; url="$2"; shift 2
  file="$BASE_TMP/$(printf '%s' "$label" | tr ' /' '__').sh"
  step "$label: загружаем официальный установщик"
  if ! fetch "$url" "$file"; then err "Не удалось скачать установщик $label"; return 1; fi
  if ! head -n 1 "$file" | grep -q '^#!'; then err "Файл $label не похож на shell-скрипт"; return 1; fi
  if ! sh -n "$file"; then err "Проверка синтаксиса установщика $label не пройдена"; return 1; fi
  # shellcheck disable=SC2086
  sh "$file" "$@"
  rc=$?
  if [ "$rc" -eq 0 ]; then ok "$label: установщик завершился"; else err "$label: установщик вернул код $rc"; fi
  return "$rc"
}
wait_enter(){ printf '\nНажмите Enter для продолжения...'; read _dummy || true; }

SELECT_PODKOP=0 SELECT_AWG=0 SELECT_ZM=0 SELECT_Z2=0 SELECT_PVF=0 SELECT_SITE=0
clear 2>/dev/null || true
printf '%s\n' "$C_CYAN"
cat <<'BANNER'
╔════════════════════════════════════════════════════╗
║              OPENWRT TOOLKIT                      ║
║     Выборочная установка сетевых компонентов       ║
╚════════════════════════════════════════════════════╝
BANNER
printf '%s\n' "$C_RESET"
printf 'Роутер: %s\nOpenWrt: %s (%s)\nПакетный менеджер: %s\nАрхитектура: %s\n\n' "$MODEL" "${RELEASE:-неизвестно}" "${ARCH:-неизвестна}" "$PM" "${ARCH_PACKAGES:-$ARCH}"
printf 'Выберите компоненты. Введите номера через пробел или запятую.\n'
printf '  1) Podkop\n'
printf '  2) AmneziaWG — установка пакетов без создания туннеля\n'
printf '  3) Zapret Manager (панель LuCI/Web UI)\n'
printf '  4) Zapret2 от Routerich + готовые файлы конфигурации\n'
printf '  5) AWG Test — Podkop VPN Failover\n'
printf '  6) Site Checker (LuCI)\n'
printf '  A) Все совместимые компоненты\n'
printf '  Q) Выход\n\n'
printf 'Ваш выбор: '
read -r CHOICE || exit 0
case "$(printf '%s' "$CHOICE" | tr '[:lower:]' '[:upper:]')" in
  Q|QUIT|EXIT) exit 0 ;;
  A|ALL) SELECT_PODKOP=1 SELECT_AWG=1 SELECT_ZM=1 SELECT_Z2=1 SELECT_PVF=1 SELECT_SITE=1 ;;
  *)
    TOKENS="$(printf '%s' "$CHOICE" | tr ',' ' ')"
    for token in $TOKENS; do
      case "$token" in
        1) SELECT_PODKOP=1 ;; 2) SELECT_AWG=1 ;; 3) SELECT_ZM=1 ;;
        4) SELECT_Z2=1 ;; 5) SELECT_PVF=1 ;; 6) SELECT_SITE=1 ;;
        '') ;; *) warn "Неизвестный пункт: $token" ;;
      esac
    done
    ;;
esac

[ "$SELECT_PODKOP$SELECT_AWG$SELECT_ZM$SELECT_Z2$SELECT_PVF$SELECT_SITE" != "000000" ] || { info "Ничего не выбрано."; exit 0; }
printf '\nВыбрано:\n'
[ "$SELECT_PODKOP" = 1 ] && printf ' - Podkop\n'
[ "$SELECT_AWG" = 1 ] && printf ' - AmneziaWG (только пакеты)\n'
[ "$SELECT_ZM" = 1 ] && printf ' - Zapret Manager\n'
[ "$SELECT_Z2" = 1 ] && printf ' - Zapret2 от Routerich\n'
[ "$SELECT_PVF" = 1 ] && printf ' - AWG Test / Podkop VPN Failover\n'
[ "$SELECT_SITE" = 1 ] && printf ' - Site Checker\n'
printf '\nВнимание: установка изменяет систему и может менять сетевые службы. Продолжить? [y/N]: '
read -r CONFIRM || exit 0
case "$CONFIRM" in y|Y|yes|YES|д|Д|да|ДА) ;; *) info "Отменено."; exit 0 ;; esac

step "Обновляем список пакетов ($PM)"
if ! pkg_update; then warn "Не удалось обновить списки пакетов; отдельные установщики могут повторить попытку."; fi

FAILS=0
if [ "$SELECT_PODKOP" = 1 ]; then
  run_remote_installer "Podkop" "https://raw.githubusercontent.com/itdoginfo/podkop/main/install.sh" || FAILS=$((FAILS+1))
fi
if [ "$SELECT_AWG" = 1 ]; then
  # Flags documented by upstream: -e skips ru language, -n skips interface configuration.
  # Keep translation enabled: run with -n only, so the script can install luci-i18n-amneziawg-ru,
  # but it may still ask whether to install the translation; use -en to ensure no prompt is wrong.
  # Upstream script supports -e (skip Russian) and -n (skip tunnel configuration); therefore -n
  # leaves Russian language prompt, which is answered through a pseudo-terminal if available.
  AWG_SCRIPT="$BASE_TMP/amneziawg-install.sh"
  if fetch "https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh" "$AWG_SCRIPT" && sh -n "$AWG_SCRIPT"; then
    # Upstream installer asks whether to install the Russian language pack.
    # Answer yes, and pass -n to avoid creating/configuring a tunnel.
    printf 'y\n' | sh "$AWG_SCRIPT" -n || FAILS=$((FAILS+1))
  else
    err "Не удалось скачать/проверить официальный установщик AmneziaWG."
    FAILS=$((FAILS+1))
  fi
fi
if [ "$SELECT_ZM" = 1 ]; then
  run_remote_installer "Zapret Manager" "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/ZapretManager_LuCI.sh" || FAILS=$((FAILS+1))
fi

if [ "$SELECT_Z2" = 1 ]; then
  step "Zapret2 от Routerich"
  if [ -f /etc/init.d/zapret ] || pkg_installed zapret; then
    err "Найден обычный Zapret. Удалите его перед установкой Zapret2: эти компоненты несовместимы."
    FAILS=$((FAILS+1))
  elif [ "${ARCH_PACKAGES:-}" != "aarch64_cortex-a53" ]; then
    err "Zapret2 от Routerich поддерживает aarch64_cortex-a53. Определённая архитектура: ${ARCH_PACKAGES:-$ARCH}"
    FAILS=$((FAILS+1))
  else
    if [ "$VERSION_MAJOR" = "25" ] && [ "$PM" = apk ]; then
      Z2_BASE="https://packages.routerich.ru/25.12/mediatek/filogic/routerich"
      Z2_KIND="apk"
    elif [ "$VERSION_MAJOR" = "24" ] && [ "$PM" = opkg ]; then
      Z2_BASE="https://packages.routerich.ru/24.10/mediatek/filogic/routerich"
      Z2_KIND="ipk"
    else
      err "Для Zapret2 поддерживаются ветки OpenWrt 24.10 и 25.12 на mediatek/filogic."
      FAILS=$((FAILS+1))
      Z2_BASE=""
    fi
    if [ -n "${Z2_BASE:-}" ]; then
      INDEX="$BASE_TMP/routerich-index.html"
      if fetch "$Z2_BASE/" "$INDEX"; then
        if [ "$Z2_KIND" = "apk" ]; then
          MAIN_PKG="$(grep -oE 'zapret2-[0-9][^" ]*\.apk' "$INDEX" | head -n1)"
          LUCI_PKG="$(grep -oE 'luci-app-zapret2-[0-9][^" ]*\.apk' "$INDEX" | head -n1)"
          RUPKG="$(grep -oE 'luci-i18n-zapret2-ru-[0-9][^" ]*\.apk' "$INDEX" | head -n1)"
        else
          MAIN_PKG="$(grep -oE 'zapret2_[0-9][^" ]*_aarch64_cortex-a53\.ipk' "$INDEX" | head -n1)"
          LUCI_PKG="$(grep -oE 'luci-app-zapret2_[0-9][^" ]*_all\.ipk' "$INDEX" | head -n1)"
          RUPKG="$(grep -oE 'luci-i18n-zapret2-ru_[0-9][^" ]*_all\.ipk' "$INDEX" | head -n1)"
        fi
        [ -n "$MAIN_PKG" ] || { err "В каталоге Routerich не найден пакет zapret2."; FAILS=$((FAILS+1)); MAIN_PKG=""; }
        if [ -n "$MAIN_PKG" ]; then
          for fn in "$MAIN_PKG" "$LUCI_PKG" "$RUPKG"; do
            [ -n "$fn" ] || continue
            fetch "$Z2_BASE/$fn" "$BASE_TMP/$fn" || { err "Не удалось скачать $fn"; FAILS=$((FAILS+1)); }
          done
          # Install a local package plus LuCI UI/translation if downloaded.
          if [ "$PM" = opkg ]; then
            [ -f "$BASE_TMP/$MAIN_PKG" ] && opkg install "$BASE_TMP/$MAIN_PKG" || FAILS=$((FAILS+1))
            [ -n "$LUCI_PKG" ] && [ -f "$BASE_TMP/$LUCI_PKG" ] && opkg install "$BASE_TMP/$LUCI_PKG" || true
            [ -n "$RUPKG" ] && [ -f "$BASE_TMP/$RUPKG" ] && opkg install "$BASE_TMP/$RUPKG" || install_ru luci-i18n-zapret2-ru
          else
            [ -f "$BASE_TMP/$MAIN_PKG" ] && apk add --allow-untrusted "$BASE_TMP/$MAIN_PKG" || FAILS=$((FAILS+1))
            [ -n "$LUCI_PKG" ] && [ -f "$BASE_TMP/$LUCI_PKG" ] && apk add --allow-untrusted "$BASE_TMP/$LUCI_PKG" || true
            [ -n "$RUPKG" ] && [ -f "$BASE_TMP/$RUPKG" ] && apk add --allow-untrusted "$BASE_TMP/$RUPKG" || install_ru luci-i18n-zapret2-ru
          fi
          # Use upstream Zapret-Manager's basic strategy/host helpers.
          mkdir -p /opt/zapret2/ipset /opt/zapret2/init.d/openwrt/custom.d
          fetch "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/files/Zapret2/zapret2" "$BASE_TMP/zapret2-config" || warn "Не удалось получить базовую конфигурацию Zapret2."
          fetch "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/files/Zapret2/zapret_hosts_discord.txt" "$BASE_TMP/zapret_hosts_discord.txt" || true
          fetch "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/files/Zapret2/50-discord_media.sh" "$BASE_TMP/50-discord_media.sh" || true
          if [ -f "$BASE_TMP/zapret2-config" ]; then cp "$BASE_TMP/zapret2-config" /etc/config/zapret2; fi
          if [ -f "$BASE_TMP/zapret_hosts_discord.txt" ]; then cp "$BASE_TMP/zapret_hosts_discord.txt" /opt/zapret2/ipset/zapret_hosts_discord.txt; fi
          if [ -f "$BASE_TMP/50-discord_media.sh" ]; then cp "$BASE_TMP/50-discord_media.sh" /opt/zapret2/init.d/openwrt/custom.d/50-discord_media.sh; chmod 755 /opt/zapret2/init.d/openwrt/custom.d/50-discord_media.sh; fi
          if [ -x /etc/init.d/zapret2 ]; then /etc/init.d/zapret2 enable && /etc/init.d/zapret2 restart && ok "Zapret2 установлен и запущен." || { err "Zapret2 установлен, но запуск не удался."; FAILS=$((FAILS+1)); }
          else err "После установки не найден /etc/init.d/zapret2."; FAILS=$((FAILS+1)); fi
        fi
      else
        err "Не удалось получить каталог пакетов Routerich: $Z2_BASE"
        FAILS=$((FAILS+1))
      fi
    fi
  fi
fi

if [ "$SELECT_PVF" = 1 ]; then
  if [ "$PM" != opkg ]; then
    warn "AWG Test / Podkop VPN Failover: официальный установщик сейчас требует opkg. Пропускаем на этой версии OpenWrt."
  elif [ "$VERSION_MAJOR" -ge 25 ]; then
    warn "AWG Test / Podkop VPN Failover пропущен: несовместимая версия OpenWrt."
  else
    run_remote_installer "AWG Test / Podkop VPN Failover" "https://raw.githubusercontent.com/SVTagan/podkop-vpn-failover/main/install.sh" || FAILS=$((FAILS+1))
  fi
fi

if [ "$SELECT_SITE" = 1 ]; then
  run_remote_installer "Site Checker" "https://cdn.jsdelivr.net/gh/TMN88/Site_Checker@a8a70be57225827740996d41b540b8a4b7ac20b0/install.sh" || FAILS=$((FAILS+1))
fi

printf '\n%s========================================%s\n' "$C_BOLD" "$C_RESET"
if [ "$FAILS" -eq 0 ]; then ok "Завершено. Проверьте статус компонентов в LuCI."
else warn "Завершено с ошибками: $FAILS компонент(а/ов) не установлены или пропущены."
fi
printf 'Русский язык: запрошен для доступных LuCI-компонентов; для отсутствующих переводов скрипты показывают предупреждение.\n'
printf 'Примечание: установщики сторонних проектов могут содержать собственные вопросы и логику.\n'
exit "$FAILS"
; fi
}
pkg_update(){ if [ "$PM" = apk ]; then apk update; else opkg update; fi; }
pkg_install(){
  name="$1"
  if pkg_installed "$name"; then ok "Уже установлен пакет $name"; return 0; fi
  if [ "$PM" = apk ]; then apk add "$name"; else opkg install "$name"; fi
}
install_ru(){
  # Take a list of potential translation names; only installed if package is in configured feeds.
  for pkg in "$@"; do
    if pkg_installed "$pkg"; then continue; fi
    if [ "$PM" = apk ]; then
      apk add "$pkg" >/dev/null 2>&1 && { ok "Русский язык: $pkg"; return 0; }
    else
      opkg install "$pkg" >/dev/null 2>&1 && { ok "Русский язык: $pkg"; return 0; }
    fi
  done
  warn "Русский перевод недоступен в подключённых feeds для этого компонента."
  return 0
}
run_remote_installer(){
  label="$1"; url="$2"; shift 2
  file="$BASE_TMP/$(printf '%s' "$label" | tr ' /' '__').sh"
  step "$label: загружаем официальный установщик"
  if ! fetch "$url" "$file"; then err "Не удалось скачать установщик $label"; return 1; fi
  if ! head -n 1 "$file" | grep -q '^#!'; then err "Файл $label не похож на shell-скрипт"; return 1; fi
  if ! sh -n "$file"; then err "Проверка синтаксиса установщика $label не пройдена"; return 1; fi
  # shellcheck disable=SC2086
  sh "$file" "$@"
  rc=$?
  if [ "$rc" -eq 0 ]; then ok "$label: установщик завершился"; else err "$label: установщик вернул код $rc"; fi
  return "$rc"
}
wait_enter(){ printf '\nНажмите Enter для продолжения...'; read _dummy || true; }

SELECT_PODKOP=0 SELECT_AWG=0 SELECT_ZM=0 SELECT_Z2=0 SELECT_PVF=0 SELECT_SITE=0
clear 2>/dev/null || true
printf '%s\n' "$C_CYAN"
cat <<'BANNER'
╔════════════════════════════════════════════════════╗
║              OPENWRT TOOLKIT                      ║
║     Выборочная установка сетевых компонентов       ║
╚════════════════════════════════════════════════════╝
BANNER
printf '%s\n' "$C_RESET"
printf 'Роутер: %s\nOpenWrt: %s (%s)\nПакетный менеджер: %s\nАрхитектура: %s\n\n' "$MODEL" "${RELEASE:-неизвестно}" "${ARCH:-неизвестна}" "$PM" "${ARCH_PACKAGES:-$ARCH}"
printf 'Выберите компоненты. Введите номера через пробел или запятую.\n'
printf '  1) Podkop\n'
printf '  2) AmneziaWG — установка пакетов без создания туннеля\n'
printf '  3) Zapret Manager (панель LuCI/Web UI)\n'
printf '  4) Zapret2 от Routerich + готовые файлы конфигурации\n'
printf '  5) AWG Test — Podkop VPN Failover\n'
printf '  6) Site Checker (LuCI)\n'
printf '  A) Все совместимые компоненты\n'
printf '  Q) Выход\n\n'
printf 'Ваш выбор: '
read -r CHOICE || exit 0
case "$(printf '%s' "$CHOICE" | tr '[:lower:]' '[:upper:]')" in
  Q|QUIT|EXIT) exit 0 ;;
  A|ALL) SELECT_PODKOP=1 SELECT_AWG=1 SELECT_ZM=1 SELECT_Z2=1 SELECT_PVF=1 SELECT_SITE=1 ;;
  *)
    TOKENS="$(printf '%s' "$CHOICE" | tr ',' ' ')"
    for token in $TOKENS; do
      case "$token" in
        1) SELECT_PODKOP=1 ;; 2) SELECT_AWG=1 ;; 3) SELECT_ZM=1 ;;
        4) SELECT_Z2=1 ;; 5) SELECT_PVF=1 ;; 6) SELECT_SITE=1 ;;
        '') ;; *) warn "Неизвестный пункт: $token" ;;
      esac
    done
    ;;
esac

[ "$SELECT_PODKOP$SELECT_AWG$SELECT_ZM$SELECT_Z2$SELECT_PVF$SELECT_SITE" != "000000" ] || { info "Ничего не выбрано."; exit 0; }
printf '\nВыбрано:\n'
[ "$SELECT_PODKOP" = 1 ] && printf ' - Podkop\n'
[ "$SELECT_AWG" = 1 ] && printf ' - AmneziaWG (только пакеты)\n'
[ "$SELECT_ZM" = 1 ] && printf ' - Zapret Manager\n'
[ "$SELECT_Z2" = 1 ] && printf ' - Zapret2 от Routerich\n'
[ "$SELECT_PVF" = 1 ] && printf ' - AWG Test / Podkop VPN Failover\n'
[ "$SELECT_SITE" = 1 ] && printf ' - Site Checker\n'
printf '\nВнимание: установка изменяет систему и может менять сетевые службы. Продолжить? [y/N]: '
read -r CONFIRM || exit 0
case "$CONFIRM" in y|Y|yes|YES|д|Д|да|ДА) ;; *) info "Отменено."; exit 0 ;; esac

step "Обновляем список пакетов ($PM)"
if ! pkg_update; then warn "Не удалось обновить списки пакетов; отдельные установщики могут повторить попытку."; fi

FAILS=0
if [ "$SELECT_PODKOP" = 1 ]; then
  run_remote_installer "Podkop" "https://raw.githubusercontent.com/itdoginfo/podkop/main/install.sh" || FAILS=$((FAILS+1))
fi
if [ "$SELECT_AWG" = 1 ]; then
  # Flags documented by upstream: -e skips ru language, -n skips interface configuration.
  # Keep translation enabled: run with -n only, so the script can install luci-i18n-amneziawg-ru,
  # but it may still ask whether to install the translation; use -en to ensure no prompt is wrong.
  # Upstream script supports -e (skip Russian) and -n (skip tunnel configuration); therefore -n
  # leaves Russian language prompt, which is answered through a pseudo-terminal if available.
  run_remote_installer "AmneziaWG" "https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh" -n || FAILS=$((FAILS+1))
fi
if [ "$SELECT_ZM" = 1 ]; then
  run_remote_installer "Zapret Manager" "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/ZapretManager_LuCI.sh" || FAILS=$((FAILS+1))
fi

if [ "$SELECT_Z2" = 1 ]; then
  step "Zapret2 от Routerich"
  if [ -f /etc/init.d/zapret ] || pkg_installed zapret; then
    err "Найден обычный Zapret. Удалите его перед установкой Zapret2: эти компоненты несовместимы."
    FAILS=$((FAILS+1))
  elif [ "${ARCH_PACKAGES:-}" != "aarch64_cortex-a53" ] && ! printf '%s' "$ARCH" | grep -q 'mediatek/filogic'; then
    err "Zapret2 от Routerich поддерживает aarch64_cortex-a53. Определённая архитектура: ${ARCH_PACKAGES:-$ARCH}"
    FAILS=$((FAILS+1))
  else
    if [ "$VERSION_MAJOR" = "25" ] && [ "$PM" = apk ]; then
      Z2_BASE="https://packages.routerich.ru/25.12/mediatek/filogic/routerich"
      Z2_KIND="apk"
    elif [ "$VERSION_MAJOR" = "24" ] && [ "$PM" = opkg ]; then
      Z2_BASE="https://packages.routerich.ru/24.10/mediatek/filogic/routerich"
      Z2_KIND="ipk"
    else
      err "Для Zapret2 поддерживаются ветки OpenWrt 24.10 и 25.12 на mediatek/filogic."
      FAILS=$((FAILS+1))
      Z2_BASE=""
    fi
    if [ -n "${Z2_BASE:-}" ]; then
      INDEX="$BASE_TMP/routerich-index.html"
      if fetch "$Z2_BASE/" "$INDEX"; then
        if [ "$Z2_KIND" = "apk" ]; then
          MAIN_PKG="$(grep -oE 'zapret2-[0-9][^" ]*\.apk' "$INDEX" | head -n1)"
          LUCI_PKG="$(grep -oE 'luci-app-zapret2-[0-9][^" ]*\.apk' "$INDEX" | head -n1)"
          RUPKG="$(grep -oE 'luci-i18n-zapret2-ru-[0-9][^" ]*\.apk' "$INDEX" | head -n1)"
        else
          MAIN_PKG="$(grep -oE 'zapret2_[0-9][^" ]*_aarch64_cortex-a53\.ipk' "$INDEX" | head -n1)"
          LUCI_PKG="$(grep -oE 'luci-app-zapret2_[0-9][^" ]*_all\.ipk' "$INDEX" | head -n1)"
          RUPKG="$(grep -oE 'luci-i18n-zapret2-ru_[0-9][^" ]*_all\.ipk' "$INDEX" | head -n1)"
        fi
        [ -n "$MAIN_PKG" ] || { err "В каталоге Routerich не найден пакет zapret2."; FAILS=$((FAILS+1)); MAIN_PKG=""; }
        if [ -n "$MAIN_PKG" ]; then
          for fn in "$MAIN_PKG" "$LUCI_PKG" "$RUPKG"; do
            [ -n "$fn" ] || continue
            fetch "$Z2_BASE/$fn" "$BASE_TMP/$fn" || { err "Не удалось скачать $fn"; FAILS=$((FAILS+1)); }
          done
          # Install a local package plus LuCI UI/translation if downloaded.
          if [ "$PM" = opkg ]; then
            [ -f "$BASE_TMP/$MAIN_PKG" ] && opkg install "$BASE_TMP/$MAIN_PKG" || FAILS=$((FAILS+1))
            [ -n "$LUCI_PKG" ] && [ -f "$BASE_TMP/$LUCI_PKG" ] && opkg install "$BASE_TMP/$LUCI_PKG" || true
            [ -n "$RUPKG" ] && [ -f "$BASE_TMP/$RUPKG" ] && opkg install "$BASE_TMP/$RUPKG" || install_ru luci-i18n-zapret2-ru
          else
            [ -f "$BASE_TMP/$MAIN_PKG" ] && apk add --allow-untrusted "$BASE_TMP/$MAIN_PKG" || FAILS=$((FAILS+1))
            [ -n "$LUCI_PKG" ] && [ -f "$BASE_TMP/$LUCI_PKG" ] && apk add --allow-untrusted "$BASE_TMP/$LUCI_PKG" || true
            [ -n "$RUPKG" ] && [ -f "$BASE_TMP/$RUPKG" ] && apk add --allow-untrusted "$BASE_TMP/$RUPKG" || install_ru luci-i18n-zapret2-ru
          fi
          # Use upstream Zapret-Manager's basic strategy/host helpers.
          mkdir -p /opt/zapret2/ipset /opt/zapret2/init.d/openwrt/custom.d
          fetch "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/files/Zapret2/zapret2" /etc/config/zapret2 || warn "Не удалось получить базовую конфигурацию Zapret2."
          fetch "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/files/Zapret2/zapret_hosts_discord.txt" /opt/zapret2/ipset/zapret_hosts_discord.txt || true
          fetch "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/files/Zapret2/50-discord_media.sh" /opt/zapret2/init.d/openwrt/custom.d/50-discord_media.sh || true
          chmod 755 /opt/zapret2/init.d/openwrt/custom.d/50-discord_media.sh 2>/dev/null || true
          if [ -x /etc/init.d/zapret2 ]; then /etc/init.d/zapret2 enable && /etc/init.d/zapret2 restart && ok "Zapret2 установлен и запущен." || { err "Zapret2 установлен, но запуск не удался."; FAILS=$((FAILS+1)); }
          else err "После установки не найден /etc/init.d/zapret2."; FAILS=$((FAILS+1)); fi
        fi
      else
        err "Не удалось получить каталог пакетов Routerich: $Z2_BASE"
        FAILS=$((FAILS+1))
      fi
    fi
  fi
fi

if [ "$SELECT_PVF" = 1 ]; then
  if [ "$PM" != opkg ]; then
    warn "AWG Test / Podkop VPN Failover: официальный установщик сейчас требует opkg. Пропускаем на этой версии OpenWrt."
  elif [ "$VERSION_MAJOR" -ge 25 ]; then
    warn "AWG Test / Podkop VPN Failover пропущен: несовместимая версия OpenWrt."
  else
    run_remote_installer "AWG Test / Podkop VPN Failover" "https://raw.githubusercontent.com/SVTagan/podkop-vpn-failover/main/install.sh" || FAILS=$((FAILS+1))
  fi
fi

if [ "$SELECT_SITE" = 1 ]; then
  run_remote_installer "Site Checker" "https://cdn.jsdelivr.net/gh/TMN88/Site_Checker@a8a70be57225827740996d41b540b8a4b7ac20b0/install.sh" || FAILS=$((FAILS+1))
fi

printf '\n%s========================================%s\n' "$C_BOLD" "$C_RESET"
if [ "$FAILS" -eq 0 ]; then ok "Завершено. Проверьте статус компонентов в LuCI."
else warn "Завершено с ошибками: $FAILS компонент(а/ов) не установлены или пропущены."
fi
printf 'Русский язык: запрошен для доступных LuCI-компонентов; для отсутствующих переводов скрипты показывают предупреждение.\n'
printf 'Примечание: установщики сторонних проектов могут содержать собственные вопросы и логику.\n'
exit "$FAILS"
; fi
}
pkg_update(){ if [ "$PM" = apk ]; then apk update; else opkg update; fi; }
pkg_install(){
  name="$1"
  if pkg_installed "$name"; then ok "Уже установлен пакет $name"; return 0; fi
  if [ "$PM" = apk ]; then apk add "$name"; else opkg install "$name"; fi
}
install_ru(){
  # Take a list of potential translation names; only installed if package is in configured feeds.
  for pkg in "$@"; do
    if pkg_installed "$pkg"; then continue; fi
    if [ "$PM" = apk ]; then
      apk add "$pkg" >/dev/null 2>&1 && { ok "Русский язык: $pkg"; return 0; }
    else
      opkg install "$pkg" >/dev/null 2>&1 && { ok "Русский язык: $pkg"; return 0; }
    fi
  done
  warn "Русский перевод недоступен в подключённых feeds для этого компонента."
  return 0
}
run_remote_installer(){
  label="$1"; url="$2"; shift 2
  file="$BASE_TMP/$(printf '%s' "$label" | tr ' /' '__').sh"
  step "$label: загружаем официальный установщик"
  if ! fetch "$url" "$file"; then err "Не удалось скачать установщик $label"; return 1; fi
  if ! head -n 1 "$file" | grep -q '^#!'; then err "Файл $label не похож на shell-скрипт"; return 1; fi
  if ! sh -n "$file"; then err "Проверка синтаксиса установщика $label не пройдена"; return 1; fi
  # shellcheck disable=SC2086
  sh "$file" "$@"
  rc=$?
  if [ "$rc" -eq 0 ]; then ok "$label: установщик завершился"; else err "$label: установщик вернул код $rc"; fi
  return "$rc"
}
wait_enter(){ printf '\nНажмите Enter для продолжения...'; read _dummy || true; }

SELECT_PODKOP=0 SELECT_AWG=0 SELECT_ZM=0 SELECT_Z2=0 SELECT_PVF=0 SELECT_SITE=0
clear 2>/dev/null || true
printf '%s\n' "$C_CYAN"
cat <<'BANNER'
╔════════════════════════════════════════════════════╗
║              OPENWRT TOOLKIT                      ║
║     Выборочная установка сетевых компонентов       ║
╚════════════════════════════════════════════════════╝
BANNER
printf '%s\n' "$C_RESET"
printf 'Роутер: %s\nOpenWrt: %s (%s)\nПакетный менеджер: %s\nАрхитектура: %s\n\n' "$MODEL" "${RELEASE:-неизвестно}" "${ARCH:-неизвестна}" "$PM" "${ARCH_PACKAGES:-$ARCH}"
printf 'Выберите компоненты. Введите номера через пробел или запятую.\n'
printf '  1) Podkop\n'
printf '  2) AmneziaWG — установка пакетов без создания туннеля\n'
printf '  3) Zapret Manager (панель LuCI/Web UI)\n'
printf '  4) Zapret2 от Routerich + готовые файлы конфигурации\n'
printf '  5) AWG Test — Podkop VPN Failover\n'
printf '  6) Site Checker (LuCI)\n'
printf '  A) Все совместимые компоненты\n'
printf '  Q) Выход\n\n'
printf 'Ваш выбор: '
read -r CHOICE || exit 0
case "$(printf '%s' "$CHOICE" | tr '[:lower:]' '[:upper:]')" in
  Q|QUIT|EXIT) exit 0 ;;
  A|ALL) SELECT_PODKOP=1 SELECT_AWG=1 SELECT_ZM=1 SELECT_Z2=1 SELECT_PVF=1 SELECT_SITE=1 ;;
  *)
    TOKENS="$(printf '%s' "$CHOICE" | tr ',' ' ')"
    for token in $TOKENS; do
      case "$token" in
        1) SELECT_PODKOP=1 ;; 2) SELECT_AWG=1 ;; 3) SELECT_ZM=1 ;;
        4) SELECT_Z2=1 ;; 5) SELECT_PVF=1 ;; 6) SELECT_SITE=1 ;;
        '') ;; *) warn "Неизвестный пункт: $token" ;;
      esac
    done
    ;;
esac

[ "$SELECT_PODKOP$SELECT_AWG$SELECT_ZM$SELECT_Z2$SELECT_PVF$SELECT_SITE" != "000000" ] || { info "Ничего не выбрано."; exit 0; }
printf '\nВыбрано:\n'
[ "$SELECT_PODKOP" = 1 ] && printf ' - Podkop\n'
[ "$SELECT_AWG" = 1 ] && printf ' - AmneziaWG (только пакеты)\n'
[ "$SELECT_ZM" = 1 ] && printf ' - Zapret Manager\n'
[ "$SELECT_Z2" = 1 ] && printf ' - Zapret2 от Routerich\n'
[ "$SELECT_PVF" = 1 ] && printf ' - AWG Test / Podkop VPN Failover\n'
[ "$SELECT_SITE" = 1 ] && printf ' - Site Checker\n'
printf '\nВнимание: установка изменяет систему и может менять сетевые службы. Продолжить? [y/N]: '
read -r CONFIRM || exit 0
case "$CONFIRM" in y|Y|yes|YES|д|Д|да|ДА) ;; *) info "Отменено."; exit 0 ;; esac

step "Обновляем список пакетов ($PM)"
if ! pkg_update; then warn "Не удалось обновить списки пакетов; отдельные установщики могут повторить попытку."; fi

FAILS=0
if [ "$SELECT_PODKOP" = 1 ]; then
  run_remote_installer "Podkop" "https://raw.githubusercontent.com/itdoginfo/podkop/main/install.sh" || FAILS=$((FAILS+1))
fi
if [ "$SELECT_AWG" = 1 ]; then
  # Flags documented by upstream: -e skips ru language, -n skips interface configuration.
  # Keep translation enabled: run with -n only, so the script can install luci-i18n-amneziawg-ru,
  # but it may still ask whether to install the translation; use -en to ensure no prompt is wrong.
  # Upstream script supports -e (skip Russian) and -n (skip tunnel configuration); therefore -n
  # leaves Russian language prompt, which is answered through a pseudo-terminal if available.
  AWG_SCRIPT="$BASE_TMP/amneziawg-install.sh"
  if fetch "https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh" "$AWG_SCRIPT" && sh -n "$AWG_SCRIPT"; then
    # Upstream installer asks whether to install the Russian language pack.
    # Answer yes, and pass -n to avoid creating/configuring a tunnel.
    printf 'y\n' | sh "$AWG_SCRIPT" -n || FAILS=$((FAILS+1))
  else
    err "Не удалось скачать/проверить официальный установщик AmneziaWG."
    FAILS=$((FAILS+1))
  fi
fi
if [ "$SELECT_ZM" = 1 ]; then
  run_remote_installer "Zapret Manager" "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/ZapretManager_LuCI.sh" || FAILS=$((FAILS+1))
fi

if [ "$SELECT_Z2" = 1 ]; then
  step "Zapret2 от Routerich"
  if [ -f /etc/init.d/zapret ] || pkg_installed zapret; then
    err "Найден обычный Zapret. Удалите его перед установкой Zapret2: эти компоненты несовместимы."
    FAILS=$((FAILS+1))
  elif [ "${ARCH_PACKAGES:-}" != "aarch64_cortex-a53" ]; then
    err "Zapret2 от Routerich поддерживает aarch64_cortex-a53. Определённая архитектура: ${ARCH_PACKAGES:-$ARCH}"
    FAILS=$((FAILS+1))
  else
    if [ "$VERSION_MAJOR" = "25" ] && [ "$PM" = apk ]; then
      Z2_BASE="https://packages.routerich.ru/25.12/mediatek/filogic/routerich"
      Z2_KIND="apk"
    elif [ "$VERSION_MAJOR" = "24" ] && [ "$PM" = opkg ]; then
      Z2_BASE="https://packages.routerich.ru/24.10/mediatek/filogic/routerich"
      Z2_KIND="ipk"
    else
      err "Для Zapret2 поддерживаются ветки OpenWrt 24.10 и 25.12 на mediatek/filogic."
      FAILS=$((FAILS+1))
      Z2_BASE=""
    fi
    if [ -n "${Z2_BASE:-}" ]; then
      INDEX="$BASE_TMP/routerich-index.html"
      if fetch "$Z2_BASE/" "$INDEX"; then
        if [ "$Z2_KIND" = "apk" ]; then
          MAIN_PKG="$(grep -oE 'zapret2-[0-9][^" ]*\.apk' "$INDEX" | head -n1)"
          LUCI_PKG="$(grep -oE 'luci-app-zapret2-[0-9][^" ]*\.apk' "$INDEX" | head -n1)"
          RUPKG="$(grep -oE 'luci-i18n-zapret2-ru-[0-9][^" ]*\.apk' "$INDEX" | head -n1)"
        else
          MAIN_PKG="$(grep -oE 'zapret2_[0-9][^" ]*_aarch64_cortex-a53\.ipk' "$INDEX" | head -n1)"
          LUCI_PKG="$(grep -oE 'luci-app-zapret2_[0-9][^" ]*_all\.ipk' "$INDEX" | head -n1)"
          RUPKG="$(grep -oE 'luci-i18n-zapret2-ru_[0-9][^" ]*_all\.ipk' "$INDEX" | head -n1)"
        fi
        [ -n "$MAIN_PKG" ] || { err "В каталоге Routerich не найден пакет zapret2."; FAILS=$((FAILS+1)); MAIN_PKG=""; }
        if [ -n "$MAIN_PKG" ]; then
          for fn in "$MAIN_PKG" "$LUCI_PKG" "$RUPKG"; do
            [ -n "$fn" ] || continue
            fetch "$Z2_BASE/$fn" "$BASE_TMP/$fn" || { err "Не удалось скачать $fn"; FAILS=$((FAILS+1)); }
          done
          # Install a local package plus LuCI UI/translation if downloaded.
          if [ "$PM" = opkg ]; then
            [ -f "$BASE_TMP/$MAIN_PKG" ] && opkg install "$BASE_TMP/$MAIN_PKG" || FAILS=$((FAILS+1))
            [ -n "$LUCI_PKG" ] && [ -f "$BASE_TMP/$LUCI_PKG" ] && opkg install "$BASE_TMP/$LUCI_PKG" || true
            [ -n "$RUPKG" ] && [ -f "$BASE_TMP/$RUPKG" ] && opkg install "$BASE_TMP/$RUPKG" || install_ru luci-i18n-zapret2-ru
          else
            [ -f "$BASE_TMP/$MAIN_PKG" ] && apk add --allow-untrusted "$BASE_TMP/$MAIN_PKG" || FAILS=$((FAILS+1))
            [ -n "$LUCI_PKG" ] && [ -f "$BASE_TMP/$LUCI_PKG" ] && apk add --allow-untrusted "$BASE_TMP/$LUCI_PKG" || true
            [ -n "$RUPKG" ] && [ -f "$BASE_TMP/$RUPKG" ] && apk add --allow-untrusted "$BASE_TMP/$RUPKG" || install_ru luci-i18n-zapret2-ru
          fi
          # Use upstream Zapret-Manager's basic strategy/host helpers.
          mkdir -p /opt/zapret2/ipset /opt/zapret2/init.d/openwrt/custom.d
          fetch "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/files/Zapret2/zapret2" "$BASE_TMP/zapret2-config" || warn "Не удалось получить базовую конфигурацию Zapret2."
          fetch "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/files/Zapret2/zapret_hosts_discord.txt" "$BASE_TMP/zapret_hosts_discord.txt" || true
          fetch "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/files/Zapret2/50-discord_media.sh" "$BASE_TMP/50-discord_media.sh" || true
          if [ -f "$BASE_TMP/zapret2-config" ]; then cp "$BASE_TMP/zapret2-config" /etc/config/zapret2; fi
          if [ -f "$BASE_TMP/zapret_hosts_discord.txt" ]; then cp "$BASE_TMP/zapret_hosts_discord.txt" /opt/zapret2/ipset/zapret_hosts_discord.txt; fi
          if [ -f "$BASE_TMP/50-discord_media.sh" ]; then cp "$BASE_TMP/50-discord_media.sh" /opt/zapret2/init.d/openwrt/custom.d/50-discord_media.sh; chmod 755 /opt/zapret2/init.d/openwrt/custom.d/50-discord_media.sh; fi
          if [ -x /etc/init.d/zapret2 ]; then /etc/init.d/zapret2 enable && /etc/init.d/zapret2 restart && ok "Zapret2 установлен и запущен." || { err "Zapret2 установлен, но запуск не удался."; FAILS=$((FAILS+1)); }
          else err "После установки не найден /etc/init.d/zapret2."; FAILS=$((FAILS+1)); fi
        fi
      else
        err "Не удалось получить каталог пакетов Routerich: $Z2_BASE"
        FAILS=$((FAILS+1))
      fi
    fi
  fi
fi

if [ "$SELECT_PVF" = 1 ]; then
  if [ "$PM" != opkg ]; then
    warn "AWG Test / Podkop VPN Failover: официальный установщик сейчас требует opkg. Пропускаем на этой версии OpenWrt."
  elif [ "$VERSION_MAJOR" -ge 25 ]; then
    warn "AWG Test / Podkop VPN Failover пропущен: несовместимая версия OpenWrt."
  else
    run_remote_installer "AWG Test / Podkop VPN Failover" "https://raw.githubusercontent.com/SVTagan/podkop-vpn-failover/main/install.sh" || FAILS=$((FAILS+1))
  fi
fi

if [ "$SELECT_SITE" = 1 ]; then
  run_remote_installer "Site Checker" "https://cdn.jsdelivr.net/gh/TMN88/Site_Checker@a8a70be57225827740996d41b540b8a4b7ac20b0/install.sh" || FAILS=$((FAILS+1))
fi

printf '\n%s========================================%s\n' "$C_BOLD" "$C_RESET"
if [ "$FAILS" -eq 0 ]; then ok "Завершено. Проверьте статус компонентов в LuCI."
else warn "Завершено с ошибками: $FAILS компонент(а/ов) не установлены или пропущены."
fi
printf 'Русский язык: запрошен для доступных LuCI-компонентов; для отсутствующих переводов скрипты показывают предупреждение.\n'
printf 'Примечание: установщики сторонних проектов могут содержать собственные вопросы и логику.\n'
exit "$FAILS"
; fi
}
pkg_update(){ if [ "$PM" = apk ]; then apk update; else opkg update; fi; }
pkg_install(){
  name="$1"
  if pkg_installed "$name"; then ok "Уже установлен пакет $name"; return 0; fi
  if [ "$PM" = apk ]; then apk add "$name"; else opkg install "$name"; fi
}
install_ru(){
  # Take a list of potential translation names; only installed if package is in configured feeds.
  for pkg in "$@"; do
    if pkg_installed "$pkg"; then continue; fi
    if [ "$PM" = apk ]; then
      apk add "$pkg" >/dev/null 2>&1 && { ok "Русский язык: $pkg"; return 0; }
    else
      opkg install "$pkg" >/dev/null 2>&1 && { ok "Русский язык: $pkg"; return 0; }
    fi
  done
  warn "Русский перевод недоступен в подключённых feeds для этого компонента."
  return 0
}
run_remote_installer(){
  label="$1"; url="$2"; shift 2
  file="$BASE_TMP/$(printf '%s' "$label" | tr ' /' '__').sh"
  step "$label: загружаем официальный установщик"
  if ! fetch "$url" "$file"; then err "Не удалось скачать установщик $label"; return 1; fi
  if ! head -n 1 "$file" | grep -q '^#!'; then err "Файл $label не похож на shell-скрипт"; return 1; fi
  if ! sh -n "$file"; then err "Проверка синтаксиса установщика $label не пройдена"; return 1; fi
  # shellcheck disable=SC2086
  sh "$file" "$@"
  rc=$?
  if [ "$rc" -eq 0 ]; then ok "$label: установщик завершился"; else err "$label: установщик вернул код $rc"; fi
  return "$rc"
}
wait_enter(){ printf '\nНажмите Enter для продолжения...'; read _dummy || true; }

SELECT_PODKOP=0 SELECT_AWG=0 SELECT_ZM=0 SELECT_Z2=0 SELECT_PVF=0 SELECT_SITE=0
clear 2>/dev/null || true
printf '%s\n' "$C_CYAN"
cat <<'BANNER'
╔════════════════════════════════════════════════════╗
║              OPENWRT TOOLKIT                      ║
║     Выборочная установка сетевых компонентов       ║
╚════════════════════════════════════════════════════╝
BANNER
printf '%s\n' "$C_RESET"
printf 'Роутер: %s\nOpenWrt: %s (%s)\nПакетный менеджер: %s\nАрхитектура: %s\n\n' "$MODEL" "${RELEASE:-неизвестно}" "${ARCH:-неизвестна}" "$PM" "${ARCH_PACKAGES:-$ARCH}"
printf 'Выберите компоненты. Введите номера через пробел или запятую.\n'
printf '  1) Podkop\n'
printf '  2) AmneziaWG — установка пакетов без создания туннеля\n'
printf '  3) Zapret Manager (панель LuCI/Web UI)\n'
printf '  4) Zapret2 от Routerich + готовые файлы конфигурации\n'
printf '  5) AWG Test — Podkop VPN Failover\n'
printf '  6) Site Checker (LuCI)\n'
printf '  A) Все совместимые компоненты\n'
printf '  Q) Выход\n\n'
printf 'Ваш выбор: '
read -r CHOICE || exit 0
case "$(printf '%s' "$CHOICE" | tr '[:lower:]' '[:upper:]')" in
  Q|QUIT|EXIT) exit 0 ;;
  A|ALL) SELECT_PODKOP=1 SELECT_AWG=1 SELECT_ZM=1 SELECT_Z2=1 SELECT_PVF=1 SELECT_SITE=1 ;;
  *)
    TOKENS="$(printf '%s' "$CHOICE" | tr ',' ' ')"
    for token in $TOKENS; do
      case "$token" in
        1) SELECT_PODKOP=1 ;; 2) SELECT_AWG=1 ;; 3) SELECT_ZM=1 ;;
        4) SELECT_Z2=1 ;; 5) SELECT_PVF=1 ;; 6) SELECT_SITE=1 ;;
        '') ;; *) warn "Неизвестный пункт: $token" ;;
      esac
    done
    ;;
esac

[ "$SELECT_PODKOP$SELECT_AWG$SELECT_ZM$SELECT_Z2$SELECT_PVF$SELECT_SITE" != "000000" ] || { info "Ничего не выбрано."; exit 0; }
printf '\nВыбрано:\n'
[ "$SELECT_PODKOP" = 1 ] && printf ' - Podkop\n'
[ "$SELECT_AWG" = 1 ] && printf ' - AmneziaWG (только пакеты)\n'
[ "$SELECT_ZM" = 1 ] && printf ' - Zapret Manager\n'
[ "$SELECT_Z2" = 1 ] && printf ' - Zapret2 от Routerich\n'
[ "$SELECT_PVF" = 1 ] && printf ' - AWG Test / Podkop VPN Failover\n'
[ "$SELECT_SITE" = 1 ] && printf ' - Site Checker\n'
printf '\nВнимание: установка изменяет систему и может менять сетевые службы. Продолжить? [y/N]: '
read -r CONFIRM || exit 0
case "$CONFIRM" in y|Y|yes|YES|д|Д|да|ДА) ;; *) info "Отменено."; exit 0 ;; esac

step "Обновляем список пакетов ($PM)"
if ! pkg_update; then warn "Не удалось обновить списки пакетов; отдельные установщики могут повторить попытку."; fi

FAILS=0
if [ "$SELECT_PODKOP" = 1 ]; then
  run_remote_installer "Podkop" "https://raw.githubusercontent.com/itdoginfo/podkop/main/install.sh" || FAILS=$((FAILS+1))
fi
if [ "$SELECT_AWG" = 1 ]; then
  # Flags documented by upstream: -e skips ru language, -n skips interface configuration.
  # Keep translation enabled: run with -n only, so the script can install luci-i18n-amneziawg-ru,
  # but it may still ask whether to install the translation; use -en to ensure no prompt is wrong.
  # Upstream script supports -e (skip Russian) and -n (skip tunnel configuration); therefore -n
  # leaves Russian language prompt, which is answered through a pseudo-terminal if available.
  run_remote_installer "AmneziaWG" "https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh" -n || FAILS=$((FAILS+1))
fi
if [ "$SELECT_ZM" = 1 ]; then
  run_remote_installer "Zapret Manager" "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/ZapretManager_LuCI.sh" || FAILS=$((FAILS+1))
fi

if [ "$SELECT_Z2" = 1 ]; then
  step "Zapret2 от Routerich"
  if [ -f /etc/init.d/zapret ] || pkg_installed zapret; then
    err "Найден обычный Zapret. Удалите его перед установкой Zapret2: эти компоненты несовместимы."
    FAILS=$((FAILS+1))
  elif [ "${ARCH_PACKAGES:-}" != "aarch64_cortex-a53" ] && ! printf '%s' "$ARCH" | grep -q 'mediatek/filogic'; then
    err "Zapret2 от Routerich поддерживает aarch64_cortex-a53. Определённая архитектура: ${ARCH_PACKAGES:-$ARCH}"
    FAILS=$((FAILS+1))
  else
    if [ "$VERSION_MAJOR" = "25" ] && [ "$PM" = apk ]; then
      Z2_BASE="https://packages.routerich.ru/25.12/mediatek/filogic/routerich"
      Z2_KIND="apk"
    elif [ "$VERSION_MAJOR" = "24" ] && [ "$PM" = opkg ]; then
      Z2_BASE="https://packages.routerich.ru/24.10/mediatek/filogic/routerich"
      Z2_KIND="ipk"
    else
      err "Для Zapret2 поддерживаются ветки OpenWrt 24.10 и 25.12 на mediatek/filogic."
      FAILS=$((FAILS+1))
      Z2_BASE=""
    fi
    if [ -n "${Z2_BASE:-}" ]; then
      INDEX="$BASE_TMP/routerich-index.html"
      if fetch "$Z2_BASE/" "$INDEX"; then
        if [ "$Z2_KIND" = "apk" ]; then
          MAIN_PKG="$(grep -oE 'zapret2-[0-9][^" ]*\.apk' "$INDEX" | head -n1)"
          LUCI_PKG="$(grep -oE 'luci-app-zapret2-[0-9][^" ]*\.apk' "$INDEX" | head -n1)"
          RUPKG="$(grep -oE 'luci-i18n-zapret2-ru-[0-9][^" ]*\.apk' "$INDEX" | head -n1)"
        else
          MAIN_PKG="$(grep -oE 'zapret2_[0-9][^" ]*_aarch64_cortex-a53\.ipk' "$INDEX" | head -n1)"
          LUCI_PKG="$(grep -oE 'luci-app-zapret2_[0-9][^" ]*_all\.ipk' "$INDEX" | head -n1)"
          RUPKG="$(grep -oE 'luci-i18n-zapret2-ru_[0-9][^" ]*_all\.ipk' "$INDEX" | head -n1)"
        fi
        [ -n "$MAIN_PKG" ] || { err "В каталоге Routerich не найден пакет zapret2."; FAILS=$((FAILS+1)); MAIN_PKG=""; }
        if [ -n "$MAIN_PKG" ]; then
          for fn in "$MAIN_PKG" "$LUCI_PKG" "$RUPKG"; do
            [ -n "$fn" ] || continue
            fetch "$Z2_BASE/$fn" "$BASE_TMP/$fn" || { err "Не удалось скачать $fn"; FAILS=$((FAILS+1)); }
          done
          # Install a local package plus LuCI UI/translation if downloaded.
          if [ "$PM" = opkg ]; then
            [ -f "$BASE_TMP/$MAIN_PKG" ] && opkg install "$BASE_TMP/$MAIN_PKG" || FAILS=$((FAILS+1))
            [ -n "$LUCI_PKG" ] && [ -f "$BASE_TMP/$LUCI_PKG" ] && opkg install "$BASE_TMP/$LUCI_PKG" || true
            [ -n "$RUPKG" ] && [ -f "$BASE_TMP/$RUPKG" ] && opkg install "$BASE_TMP/$RUPKG" || install_ru luci-i18n-zapret2-ru
          else
            [ -f "$BASE_TMP/$MAIN_PKG" ] && apk add --allow-untrusted "$BASE_TMP/$MAIN_PKG" || FAILS=$((FAILS+1))
            [ -n "$LUCI_PKG" ] && [ -f "$BASE_TMP/$LUCI_PKG" ] && apk add --allow-untrusted "$BASE_TMP/$LUCI_PKG" || true
            [ -n "$RUPKG" ] && [ -f "$BASE_TMP/$RUPKG" ] && apk add --allow-untrusted "$BASE_TMP/$RUPKG" || install_ru luci-i18n-zapret2-ru
          fi
          # Use upstream Zapret-Manager's basic strategy/host helpers.
          mkdir -p /opt/zapret2/ipset /opt/zapret2/init.d/openwrt/custom.d
          fetch "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/files/Zapret2/zapret2" /etc/config/zapret2 || warn "Не удалось получить базовую конфигурацию Zapret2."
          fetch "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/files/Zapret2/zapret_hosts_discord.txt" /opt/zapret2/ipset/zapret_hosts_discord.txt || true
          fetch "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/files/Zapret2/50-discord_media.sh" /opt/zapret2/init.d/openwrt/custom.d/50-discord_media.sh || true
          chmod 755 /opt/zapret2/init.d/openwrt/custom.d/50-discord_media.sh 2>/dev/null || true
          if [ -x /etc/init.d/zapret2 ]; then /etc/init.d/zapret2 enable && /etc/init.d/zapret2 restart && ok "Zapret2 установлен и запущен." || { err "Zapret2 установлен, но запуск не удался."; FAILS=$((FAILS+1)); }
          else err "После установки не найден /etc/init.d/zapret2."; FAILS=$((FAILS+1)); fi
        fi
      else
        err "Не удалось получить каталог пакетов Routerich: $Z2_BASE"
        FAILS=$((FAILS+1))
      fi
    fi
  fi
fi

if [ "$SELECT_PVF" = 1 ]; then
  if [ "$PM" != opkg ]; then
    warn "AWG Test / Podkop VPN Failover: официальный установщик сейчас требует opkg. Пропускаем на этой версии OpenWrt."
  elif [ "$VERSION_MAJOR" -ge 25 ]; then
    warn "AWG Test / Podkop VPN Failover пропущен: несовместимая версия OpenWrt."
  else
    run_remote_installer "AWG Test / Podkop VPN Failover" "https://raw.githubusercontent.com/SVTagan/podkop-vpn-failover/main/install.sh" || FAILS=$((FAILS+1))
  fi
fi

if [ "$SELECT_SITE" = 1 ]; then
  run_remote_installer "Site Checker" "https://cdn.jsdelivr.net/gh/TMN88/Site_Checker@a8a70be57225827740996d41b540b8a4b7ac20b0/install.sh" || FAILS=$((FAILS+1))
fi

printf '\n%s========================================%s\n' "$C_BOLD" "$C_RESET"
if [ "$FAILS" -eq 0 ]; then ok "Завершено. Проверьте статус компонентов в LuCI."
else warn "Завершено с ошибками: $FAILS компонент(а/ов) не установлены или пропущены."
fi
printf 'Русский язык: запрошен для доступных LuCI-компонентов; для отсутствующих переводов скрипты показывают предупреждение.\n'
printf 'Примечание: установщики сторонних проектов могут содержать собственные вопросы и логику.\n'
exit "$FAILS"
