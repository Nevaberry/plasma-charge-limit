#!/usr/bin/env python3
"""Maintain KDE gettext catalogs. Only developers need Python and gettext."""
# SPDX-FileCopyrightText: 2026 Antti Jalomäki
# SPDX-License-Identifier: MIT

import argparse
import gettext
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
TRANSLATE = ROOT / "translate"
METADATA = ROOT / "package/metadata.json"
TEMPLATE = TRANSLATE / "template.pot"
DOMAIN = "plasma_applet_com.nevaberry.chargelimit"


def run(*args):
    subprocess.run(args, check=True, cwd=ROOT)


def extract(directory, metadata):
    # Use the same catalogs for the widget picker and the widget itself.
    source = directory / "metadata.cpp"
    source.write_text("\n".join(
        "i18n(" + json.dumps(metadata["KPlugin"][key]) + ");"
        for key in ("Name", "Description")
    ), encoding="utf-8")
    output = directory / "template.pot"
    # The KDE extractor understands i18n calls and validates KDE %1 formatting.
    run("xgettext", "--language=C++", "--kde", "--from-code=UTF-8",
        "--keyword=i18n:1", "--keyword=i18nc:1c,2",
        "--add-comments=TRANSLATORS", "--no-location", "--no-wrap",
        "--omit-header", "--output=" + str(output),
        "package/contents/ui/main.qml", str(source))
    header = (
        '# Translation template for Charge Limit.\n'
        '# SPDX-License-Identifier: MIT\n'
        'msgid ""\nmsgstr ""\n'
        '"Project-Id-Version: Charge Limit\\n"\n'
        '"Report-Msgid-Bugs-To: https://github.com/Nevaberry/plasma-charge-limit/issues\\n"\n'
        '"MIME-Version: 1.0\\n"\n'
        '"Content-Type: text/plain; charset=UTF-8\\n"\n'
        '"Content-Transfer-Encoding: 8bit\\n"\n\n'
    )
    return header + output.read_text(encoding="utf-8")


def save_or_check(path, content, check):
    if check:
        if not path.is_file() or path.read_bytes() != content:
            raise SystemExit(f"Out of date: {path.relative_to(ROOT)}; run translate/translations.py build")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("update", "build", "check"))
    command = parser.parse_args().command
    metadata = json.loads(METADATA.read_text(encoding="utf-8"))
    catalogs = sorted(TRANSLATE.glob("*.po"))
    with tempfile.TemporaryDirectory(prefix="charge-limit-translations-") as temp:
        directory = Path(temp)
        template = extract(directory, metadata)
        if command == "update":
            TEMPLATE.write_text(template, encoding="utf-8")
            for catalog in catalogs:
                run("msgmerge", "--quiet", "--update", "--backup=none",
                    "--no-fuzzy-matching", "--no-wrap", str(catalog), str(TEMPLATE))
            return
        if TEMPLATE.read_text(encoding="utf-8") != template:
            raise SystemExit("Translation template is out of date; run translate/translations.py update")
        if not catalogs:
            raise SystemExit("No translation catalogs found")
        plugin = metadata["KPlugin"]
        for key in list(plugin):
            if key.startswith(("Name[", "Description[")):
                del plugin[key]
        for catalog in catalogs:
            language = catalog.stem
            compiled = directory / f"{language}.mo"
            # Reject missing/fuzzy messages and broken %1 placeholders.
            run("msgcmp", str(catalog), str(TEMPLATE))
            run("msgfmt", "--check", "--check-format", "-o", str(compiled), str(catalog))
            with compiled.open("rb") as stream:
                messages = gettext.GNUTranslations(stream)
            for key in ("Name", "Description"):
                plugin[f"{key}[{language}]"] = messages.gettext(plugin[key])
            destination = ROOT / "package/contents/locale" / language / "LC_MESSAGES" / f"{DOMAIN}.mo"
            save_or_check(destination, compiled.read_bytes(), command == "check")
        content = (json.dumps(metadata, ensure_ascii=False, indent=4) + "\n").encode("utf-8")
        save_or_check(METADATA, content, command == "check")
        print(f"{command}: {len(catalogs)} complete translation catalogs")


if __name__ == "__main__":
    main()
