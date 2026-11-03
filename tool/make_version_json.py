"""Writes version.json for the in-app update alert.
Usage: python3 make_version_json.py <source dir> <installers dir>  (prints JSON)"""
import datetime, json, os, re, sys

src, dist = sys.argv[1], sys.argv[2]
pubspec = open(os.path.join(src, 'pubspec.yaml'), encoding='utf-8').read()
version = re.search(r'^version:\s*([0-9.]+)', pubspec, re.M).group(1)

notes = []
path = os.path.join(src, 'WHATS-NEW.md')
if os.path.exists(path):
    section = None
    for line in open(path, encoding='utf-8'):
        m = re.match(r'^##\s+([0-9.]+)', line)
        if m:
            section = m.group(1)
            continue
        if section == version and line.startswith('- '):
            notes.append(line[2:].strip())

files = os.listdir(dist)
def pick(pattern):
    for f in sorted(files):
        if re.fullmatch(pattern, f):
            return f
    return None

print(json.dumps({
    'version': version,
    'notes': notes,
    'windows': pick(r'ChristmanCoordination-Setup-.*\.exe'),
    'android': pick(r'ChristmanCoordination-.*-android\.apk'),
    'android_older': pick(r'ChristmanCoordination-.*-older-phones\.apk'),
    'published': datetime.datetime.now(datetime.timezone.utc).isoformat(),
}, indent=2))
