# Podkop VPN Failover — OpenWrt 25.12 APK edition

Адаптация [SVTagan/podkop-vpn-failover](https://github.com/SVTagan/podkop-vpn-failover) для OpenWrt 25.12 с пакетным менеджером APK. Установщик также оставляет поддержку старых версий OpenWrt с opkg.

Это независимая адаптация, не официальный выпуск исходного автора.

## Что делает

- Автоматически ищет UCI-интерфейсы `awg*` с протоколом `amneziawg`.
- Проверяет реальный HTTPS через выбранный AWG-интерфейс.
- После нескольких ошибок проверяет резервный туннель и переключает `podkop.main.interface`.
- Выполняет штатную перезагрузку Podkop и проверяет привязку sing-box после переключения.
- Использует задержку запуска, несколько проверок, временный карантин проблемных интерфейсов и паузу после полного отказа пула.
- Добавляет сервис procd и опциональные команды в LuCI.
- После первой установки оставляет сервис выключенным: сначала требуется проверка вручную.

## Установка на OpenWrt 25.12

Запусти в SSH от root:

```sh
curl -fsSL https://raw.githubusercontent.com/TMN88/router-service-check/podkop-vpn-failover-apk/install-pvf-apk.sh -o /tmp/pvf-install.sh && sh /tmp/pvf-install.sh
```

Если на роутере ещё нет curl, скачай установщик встроенным загрузчиком:

```sh
uclient-fetch -q -O /tmp/pvf-install.sh https://raw.githubusercontent.com/TMN88/router-service-check/podkop-vpn-failover-apk/install-pvf-apk.sh && sh /tmp/pvf-install.sh
```

Чтобы не устанавливать необязательные команды LuCI:

```sh
INSTALL_LUCI_COMMANDS=0 sh /tmp/pvf-install.sh
```

Установщик выбирает `apk`, если он найден, в противном случае использует `opkg`. При необходимости устанавливает `curl`. Установка не включает автоматическое переключение без проверки.

## Проверка перед запуском

```sh
podkop-vpn-failover test
podkop-vpn-failover status
```

Проверь, что активный и резервные AWG-интерфейсы обнаружены, а проверка каждого нужного туннеля возвращает HTTP 204. Затем включай failover:

```sh
podkop-vpn-failover-control start
```

Другие команды:

```sh
podkop-vpn-failover status
podkop-vpn-failover test
podkop-vpn-failover logs
podkop-vpn-failover config
podkop-vpn-failover-control restart
podkop-vpn-failover-control stop
```

Системный журнал:

```sh
logread | grep podkop-vpn-failover
```

## Удаление

```sh
curl -fsSL https://raw.githubusercontent.com/TMN88/router-service-check/podkop-vpn-failover-apk/uninstall.sh -o /tmp/pvf-uninstall.sh && sh /tmp/pvf-uninstall.sh
```

## Ограничения и безопасность

- Требуется Podkop в VPN-режиме и AmneziaWG-интерфейсы с именами `awg*`.
- Проверка использует IPv4 HTTPS-запрос к `https://www.gstatic.com/generate_204`.
- Проверка показывает состояние конкретного туннеля, но не является полной проверкой маршрутизации всех клиентов LAN.
- Адаптация APK ещё нуждается в тестировании на конкретном устройстве OpenWrt 25.12 перед включением автоматического переключения.
- Первая установка намеренно оставляет сервис остановленным и отключённым.

## Исходный проект

Оригинальная логика и документация: https://github.com/SVTagan/podkop-vpn-failover
