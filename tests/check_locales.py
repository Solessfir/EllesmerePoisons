"""Checks the translations: every locale file holds the same keys, each key is text the add-on really shows,
and each translation keeps its key's placeholders. Run: python tests/check_locales.py"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALES = ["deDE", "esES", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW"]
ENTRY = re.compile(r'^L\["((?:[^"\\]|\\.)*)"\] = "((?:[^"\\]|\\.)*)"$')
PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?([sd])")


def arguments(text):
    """The format arguments `text` reads, as (position, type); None when string.format would reject it (a '%' that
    is no placeholder) or it mixes numbered and plain placeholders."""
    text = text.replace("%%", "")
    if "%" in PLACEHOLDER.sub("", text):
        return None
    found = PLACEHOLDER.findall(text)
    if any(n for n, _ in found) and not all(n for n, _ in found):
        return None
    return sorted((int(n) if n else i + 1, kind) for i, (n, kind) in enumerate(found))


def strings_in(path):
    return set(re.findall(r'"((?:[^"\\]|\\.)*)"', open(path, encoding="utf-8").read()))


code = strings_in(os.path.join(ROOT, "EllesmerePoisons.lua")) | strings_in(os.path.join(ROOT, "Restock.lua"))
errors = []
reference = None
for locale in LOCALES:
    path = os.path.join(ROOT, "Locales", locale + ".lua")
    entries = {}
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.rstrip("\n")
        if not line.startswith("L["):
            continue
        m = ENTRY.match(line)
        if not m:
            errors.append("%s:%d: unreadable entry" % (locale, n))
            continue
        key, text = m.groups()
        if key in entries:
            errors.append("%s: %r twice" % (locale, key))
        entries[key] = text
        if key not in code:
            errors.append("%s: %r is not text the add-on shows" % (locale, key))
        if arguments(text) is None or arguments(text) != arguments(key):
            errors.append("%s: %r changes the placeholders" % (locale, key))
        if not text.strip():
            errors.append("%s: %r is empty" % (locale, key))
    if reference is None:
        reference = (locale, set(entries))
    else:
        for key in sorted(reference[1] - set(entries)):
            errors.append("%s: missing %r (in %s)" % (locale, key, reference[0]))
        for key in sorted(set(entries) - reference[1]):
            errors.append("%s: extra %r (not in %s)" % (locale, key, reference[0]))

# Text the add-on passes to the translator itself must be translated here (eUI's widgets cover their own labels).
for name in ("EllesmerePoisons.lua", "Restock.lua"):
    source = open(os.path.join(ROOT, name), encoding="utf-8").read()
    for key in sorted(set(re.findall(r'\bLf?\("((?:[^"\\]|\\.)*)"', source)) - reference[1]):
        errors.append("%s: %r is never translated" % (name, key))

toc = open(os.path.join(ROOT, "EllesmerePoisons.toc"), encoding="utf-8").read()
for locale in LOCALES:
    if "Locales\\%s.lua" % locale not in toc:
        errors.append("EllesmerePoisons.toc does not load Locales\\%s.lua" % locale)

print("\n".join(errors) if errors else "Translations OK: %d keys in %d locales." % (len(reference[1]), len(LOCALES)))
sys.exit(1 if errors else 0)
