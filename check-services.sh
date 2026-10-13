#!/bin/sh
# Проверка доступности популярных сервисов с самого роутера OpenWrt.
# Запуск: sh check-services.sh

check_service() {
    name="$1"
    url="$2"

    code="$(curl -sS -L -o /dev/null -w '%{http_code}' \
        --connect-timeout 5 --max-time 15 "$url" 2>/dev/null)"
    rc=$?

    case "$code" in
        2??|3??) status="РАБОТАЕТ" ;;
        *)       status="НЕТ ДОСТУПА" ;;
    esac
    [ "$rc" -eq 0 ] || status="НЕТ ДОСТУПА"

    case "$name" in
        YouTube)   YOUTUBE="$status" ;;
        Instagram) INSTAGRAM="$status" ;;
        Telegram)  TELEGRAM="$status" ;;
        WhatsApp)  WHATSAPP="$status" ;;
    esac
}

YOUTUBE="НЕ ПРОВЕРЕН"
INSTAGRAM="НЕ ПРОВЕРЕН"
TELEGRAM="НЕ ПРОВЕРЕН"
WHATSAPP="НЕ ПРОВЕРЕН"

if ! command -v curl >/dev/null 2>&1; then
    printf 'Ошибка: curl не установлен. Установи командой: apk add curl\n' >&2
    exit 1
fi

check_service "YouTube"   "https://www.youtube.com/generate_204"
check_service "Instagram" "https://www.instagram.com/"
check_service "Telegram"  "https://web.telegram.org/"
check_service "WhatsApp"  "https://web.whatsapp.com/"

printf '\nРезультаты проверки:\nYouTube    %s\nInstagram  %s\nTelegram   %s\nWhatsApp   %s\n' \
    "$YOUTUBE" "$INSTAGRAM" "$TELEGRAM" "$WHATSAPP"

printf '\nВажно: проверка выполняется с роутера и не гарантирует, что клиентский трафик проходит по тем же правилам Podkop.\n'
