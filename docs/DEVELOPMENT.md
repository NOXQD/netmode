# Для разработки

```
root/netmode-root          помощник с правами root, таблица режимов
root/install-root.sh       корневая часть установки
root/dev.noxqd.netmode.policy  действие polkit (запасной путь, если нет sudoers)
bin/netmode                CLI, замеры, загрузчик, демон авто-видео
plugin/                    QML-плагин панели Omarchy
tests/                     unittest
```

Плагин подхватывается оболочкой при старте, поэтому после правок QML нужен
`omarchy restart shell`.

Чтобы посмотреть карточку без запуска панели, можно отрисовать её
офскрин-окном Quickshell:

```bash
QT_QPA_PLATFORM=offscreen quickshell -p путь/к/shell.qml
```

В `shell.qml` подставляется заглушка вместо `hostWidget` с полями `mode`,
`modeList`, `snap`, `pulse` и `benchResult`; `Commons` и `Ui` берутся
символическими ссылками из `/usr/share/omarchy/shell`. Так сделаны картинки в
`docs/screenshots`.

## Добавить режим

Новая запись в `MODES` в `root/netmode-root`: имя, значок (кодпоинт Nerd Font),
подпись до 30 символов, `wifi_awake` и словарь `sysctl` с отличиями от `BASE`.
Правило sudoers собирается из этого же списка при установке, поэтому после
правки нужен `./install.sh`.
