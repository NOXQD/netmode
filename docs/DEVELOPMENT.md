# Для разработки

```
root/netmode-root          помощник с правами root, таблица режимов
root/install-root.sh       корневая часть установки
root/dev.noxqd.netmode.policy  действие polkit (запасной путь, если нет sudoers)
bin/netmode                CLI, замеры, загрузчик, демон авто-видео
plugin/                    QML-плагин панели Omarchy
extension/                 расширение Chromium: перенаправляет видеозапросы на прокси
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

## Проверка ускорителя без своего браузера

Прокси можно запустить командой `netmode proxy -v` и забрать кусок напрямую:

```bash
curl -r 5000000-5999999 http://127.0.0.1:18765/$(netmode token)/video2.cdnlibs.org//uploads/…/1983_2160.mp4
```

Для сквозной проверки нужен отдельный Chromium с чистым профилем
(`--headless=new --user-data-dir=… --load-extension=extension`), страница по
HTTPS и самоподписанный сертификат с `--ignore-certificate-errors`. Правило
перенаправления ставится после старта сервис-воркера, поэтому `<video>`
лучше создавать с задержкой в несколько секунд. Расширению нужны хост-права
не только на видеосервер, но и на страницу-инициатор, поэтому в манифесте
`https://*/*`. `token.js` для тестовой копии расширения нужно создать самому
(`const PORT = …`, `const TOKEN = "…"`).

## Добавить режим

Новая запись в `MODES` в `root/netmode-root`: имя, значок (кодпоинт Nerd Font),
подпись до 30 символов, `wifi_awake` и словарь `sysctl` с отличиями от `BASE`.
Правило sudoers собирается из этого же списка при установке, поэтому после
правки нужен `./install.sh`.
