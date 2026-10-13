# Podkop VPN Failover — OpenWrt 25.12 APK edition

Адаптация [SVTagan/podkop-vpn-failover](https://github.com/SVTagan/podkop-vpn-failover) для OpenWrt 25.12 с APK, с сохранением поддержки старых OpenWrt на opkg. Это независимая адаптация, не официальный выпуск автора исходного проекта.

## Установка

Запусти по SSH от root:

```sh
curl -fsSL https://raw.githubusercontent.com/TMN88/router-service-check/podkop-vpn-failover-apk/install-pvf-apk.sh -o /tmp/pvf-install.sh && sh /tmp/pvf-install.sh
```

Если curl ещё не установлен:

```sh
uclient-fetch -q -O /tmp/pvf-install.sh https://raw.githubusercontent.com/TMN88/router-service-check/podkop-vpn-failover-apk/install-pvf-apk.sh && sh /tmp/pvf-install.sh
```

Установщик автоматически выбирает `apk` или `opkg`, устанавливает `curl` и по умолчанию пытается установить `luci-app-commands`. Чтобы пропустить необязательные команды LuCI, передай `INSTALL_LUCI_COMMANDS=0`.

## Перед включением автоматического переключения

Первая установка оставляет сервис остановленным и отключённым. Сначала проверь обнаружение интерфейсов:

```sh
podkop-vpn-failover test
podkop-vpn-failover status
```

Если активный и резервные AWG-интерфейсы определились и туннели проходят проверку, включи failover:

```sh
podkop-vpn-failover-control start
```

Состояние и журнал:

```sh
podkop-vpn-failover status
podkop-vpn-failover logs
logread | grep podkop-vpn-failover
```

Удаление:

```sh
curl -fsSL https://raw.githubusercontent.com/TMN88/router-service-check/podkop-vpn-failover-apk/uninstall.sh -o /tmp/pvf-uninstall.sh && sh /tmp/pvf-uninstall.sh
```

## Как работает failover

Проект ищет UCI-интерфейсы `awg*` с протоколом `amneziawg`, проверяет HTTPS через каждый интерфейс и при подтверждённом отказе активного туннеля переключает `podkop.main.interface`, перезагружает Podkop и проверяет результат. Встроены порог ошибок, подтверждение резерва, quarantine, startup grace и пауза после полного отказа пула.

## Ограничения

- Требуется Podkop в VPN-режиме и AmneziaWG-интерфейсы с именами `awg*`.
- Проверка — IPv4 HTTPS к `https://www.gstatic.com/generate_204`.
- Состояние туннеля не заменяет полную проверку маршрутизации устройств LAN.
- APK-ветка требует тестирования на целевом роутере OpenWrt 25.12 перед включением автоматического переключения.

Оригинальный проект и его история: https://github.com/SVTagan/podkop-vpn-failover
