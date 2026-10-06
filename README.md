# Charge Limit

A KDE Plasma 6 widget that sets your laptop's battery charge limit with one click: **50%, 80%, 90% or 100%**.

A battery lasts longer when it isn't kept full, the same advice given for electric cars. Use about 50% if the laptop is always plugged in, about 80% for daily use, and 100% only when you need the range, for example before a trip.

Plasma already has this setting in System Settings under Power Management, but it's buried in the menus, you type the numbers in by hand, and it asks for your password every time. This widget puts it one click away in your panel or system tray.

## Install

Find **Charge Limit** in Plasma's **Get New Widgets**, or download it from the [KDE Store](https://store.kde.org/p/2376310) or [GitHub releases](https://github.com/Nevaberry/plasma-charge-limit/releases/latest).

To install from source:

```sh
git clone https://github.com/Nevaberry/plasma-charge-limit
kpackagetool6 --type Plasma/Applet --install plasma-charge-limit/package
```

Charge Limit then appears in the system tray, behind the arrow. To keep it always visible, right-click the arrow, choose **Configure System Tray...**, and set **Charge Limit** to **Always show**.

The first time you pick a limit, Plasma asks for your password once. The widget then installs two small files so later changes need no password:

- `/usr/local/libexec/plasma-charge-limit-helper` is a copy of [the script](package/contents/scripts/chargelimit-helper) that writes the limit.
- `/etc/polkit-1/rules.d/50-plasma-charge-limit.rules` lets whoever is sitting at the computer run that script without a password. Remote (SSH) users still need one. This is the same default UPower uses for its own charge limit switch.

To update, run `git pull`, then the same `kpackagetool6` command with `--upgrade` instead of `--install`, and log out and back in: Plasma keeps running the old version until then. If you also added the widget to a panel, add it there again after upgrading.

An update that changes the helper asks for your password once more to install the new helper.

## Languages

The widget follows Plasma's language preference automatically, with English as the fallback. There is no separate language setting.

Translations are included for Arabic, Dutch, Finnish, French, German, Hindi, Italian, Japanese, Korean, Polish, Portuguese (Portugal and Brazil), Russian, Spanish, Swedish, Turkish, Ukrainian, and Chinese (Simplified and Traditional). This covers the widget, battery status, tips, and its name and description in the widget picker. System error details are shown as returned by the helper.

## How it works

The widget writes the same kernel settings as Plasma's own charge limit setting, for every battery that has them:

- `charge_control_end_threshold` is set to the limit.
- `charge_control_start_threshold` is set to 5% below the limit, on laptops that have it. Charging restarts only when the battery drops below that.

If `ls /sys/class/power_supply/BAT*/charge_control_end_threshold` finds a file, the widget works on your laptop. If not, the widget says "No battery with a charge limit found".

Good to know:

- On some laptops a new limit takes effect only after you unplug and replug the charger.
- Some laptops only accept certain values, such as 80% or 100%. The widget shows the error if your laptop rejects a value.
- ThinkPads remember the limit across reboots. Some other laptops reset it to 100% when they start, the same as with Plasma's own setting.

## Uninstall

```sh
kpackagetool6 --type Plasma/Applet --remove com.nevaberry.chargelimit
sudo rm /usr/local/libexec/plasma-charge-limit-helper /etc/polkit-1/rules.d/50-plasma-charge-limit.rules
```

## Development

`tests/helper-test.sh` tests the helper script against a fake `/sys/class/power_supply`.

Translations use KDE's standard gettext catalogs. Edit `translate/<language>.po`, then run:

```sh
python3 translate/translations.py build
python3 translate/translations.py check
```

These developer commands require Python 3 and GNU gettext (`xgettext`, `msgmerge`, `msgcmp`, and `msgfmt`). The compiled catalogs in `package/contents/locale` are committed, so installing or using the widget requires no translation tools. The build also translates the widget metadata from the same catalogs.

After changing English UI text, run `python3 translate/translations.py update` and translate the new messages. To add a language, create its catalog with `msginit --no-translator --locale=nl --input=translate/template.pot --output-file=translate/nl.po` (replace `nl` with the new language code), translate it, then build. Keep `%1` placeholders and HTML tags intact. `check` rejects missing translations, invalid placeholders, and stale compiled catalogs or metadata.

To package a release after running the checks:

```sh
cd package
zip -r ../charge-limit-1.3.0.plasmoid metadata.json contents
```

## License

[MIT](LICENSE)
