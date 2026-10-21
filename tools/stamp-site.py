#!/usr/bin/env python3
"""Copies a built DMG into website/downloads/ and writes its version, size and SHA-256 into the site.

Usage: tools/stamp-site.py <path-to.dmg> <version> [--notarized]
"""
import hashlib, pathlib, re, shutil, sys

dmg = pathlib.Path(sys.argv[1]).resolve()
version = sys.argv[2]
notarized = "--notarized" in sys.argv
site = pathlib.Path(__file__).resolve().parent.parent / "website"
name = f"Petal-{version}.dmg"

(site / "downloads").mkdir(exist_ok=True)
for old in (site / "downloads").glob("Petal-*.dmg"):
    old.unlink()
shutil.copy2(dmg, site / "downloads" / name)

sha = hashlib.sha256(dmg.read_bytes()).hexdigest()
size = f"{dmg.stat().st_size / 1_000_000:.0f} MB"

app = (site / "app.js").read_text()
app = re.sub(r'const RELEASE = \{.*?\};',
             f'const RELEASE = {{ version: "{version}", file: "downloads/{name}", size: "{size}", sha256: "{sha}", '
             f'requires: "macOS 15 or later · Apple silicon", notarized: {"true" if notarized else "false"} }};', app, count=1, flags=re.S)
(site / "app.js").write_text(app)

for page in site.glob("*.html"):
    html = page.read_text()
    html = re.sub(r'downloads/Petal-[0-9][^"]*\.dmg', f'downloads/{name}', html)
    html = re.sub(r'Petal-[0-9][0-9.]*\.dmg', name, html)
    html = re.sub(r'Version [0-9][0-9.]* ·', f'Version {version} ·', html)
    html = re.sub(r'(<dd data-release="version">)[^<]*', rf'\g<1>{version}', html)
    html = re.sub(r'(<dd data-release="size">)[^<]*', rf'\g<1>{size}', html)
    html = re.sub(r'(<code data-release="sha256">)[^<]*', rf'\g<1>{sha}', html)
    html = re.sub(r'Applies to Petal [0-9][0-9.]*\.', f'Applies to Petal {version}.', html)
    page.write_text(html)

print(f"Stamped website for Petal {version}: {size}, sha256 {sha}")
