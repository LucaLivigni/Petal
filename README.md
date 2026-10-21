# Petal

**Drag a file. Tap a key. Drop it on what you need.**

Petal is a menu-bar app for macOS that converts, compresses and sends files from a wheel that opens right under your
cursor. No window to open, no account, nothing uploaded: everything runs on your Mac.

It is an original app, written from scratch in Swift (SwiftUI + AppKit) on Apple's public frameworks. It is inspired by the
*idea* of radial drag-and-drop converters; no code or assets were taken from other apps.

## How it works

Start dragging a file anywhere (Finder, the Desktop, any app), then tap a key without letting go. The wheel opens under the
cursor; drop the file on a wedge. The result is saved next to the original and never overwrites anything.

| Tap while dragging | Wheel | Examples |
|---|---|---|
| ⇧ Shift | **Convert** | JPG ⇄ PNG ⇄ HEIC ⇄ AVIF ⇄ WebP, SVG → PNG, MOV → MP4 / GIF, WAV → M4A / MP3, PDF → DOCX / PPTX / XLSX / EPUB / MD, DOCX → PDF / EPUB, XLSX ⇄ CSV ⇄ ODS ⇄ JSON, EPUB → PDF, SRT → VTT, ZIP ⇄ TAR.GZ |
| ⌘ Command | **Tools** | Edit and Background (photo editor), Trim (audio and video), compress, resize, remove background, copy text (OCR), split / merge PDFs, strip metadata |
| ⌃ Control | **Actions** | AirDrop, copy, copy path, move / copy to…, open in Terminal, float on screen |

* The wheel **learns** which formats you use and puts them first. *Settings → Wheels* lets you pin favourites, hide formats
  and reorder them.
* A card under the wheel shows what you are holding (size, dimensions, pages or duration) and the name the result will get.
* After a job, a card lets you drag the result straight out of it.
* Nine accent colours, two wheel sizes, a welcome guide with a hands-on practice step.
* No special permissions: Petal watches mouse drags and polls modifier keys, which macOS allows freely. It never records
  typing and makes no network connections.

## Formats

Built in (system frameworks only): images (JPG, PNG, HEIC, AVIF, TIFF, GIF, BMP, JPEG 2000, ICO, ICNS, TGA, PSD; RAW and SVG as
input), MP4 / MOV, M4A / WAV / FLAC / AIFF / CAF, video → GIF, PDF ⇄ DOCX / PPTX / XLSX / EPUB / Markdown / TXT / images,
documents (DOCX, ODT, RTF, HTML, Markdown, EPUB, TXT), spreadsheets (XLSX, ODS, CSV, TSV, JSON), subtitles (SRT, VTT),
ZIP / TAR / TAR.GZ / GZIP.

Added by the bundled `ffmpeg` and `cwebp` (see [Building the engines](#building-the-engines)): MP3, WebM, MKV, AVI, WMV, OGG,
Opus, WMA and WebP, and reading MKV / WebM / AVI / WMV video and OGG / Opus / WMA audio.

Optional, if the free Apple apps are installed (Petal drives them through AppleScript; macOS asks once for permission):
Keynote (PPT / PPTX / KEY → PDF, JPG, PNG), Pages (PAGES in and out), Numbers (XLS and Numbers input).

## Requirements

An Apple silicon Mac running macOS 15 (Sequoia) or later. To build: Xcode 26 or later and
[xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Build from source

```bash
xcodegen generate                # Petal.xcodeproj is generated from project.yml
xcodebuild -project Petal.xcodeproj -scheme Petal -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Petal.app
```

Petal builds ad hoc out of the box. To sign with your own certificate (which also keeps macOS's per-app permissions across
rebuilds), copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and put your identity in it.

### Tests

```bash
xcodebuild -project Petal.xcodeproj -scheme Petal -derivedDataPath build test
```

The suites that exercise the bundled `ffmpeg` and `cwebp` are skipped until you have built them.

### Building the engines

`ffmpeg` and `cwebp` are not stored in this repository. Without them Petal still builds and runs; the formats that need
them simply don't appear on the wheel. To build them (about ten minutes, arm64):

```bash
tools/build-engines.sh
```

The script downloads each project's official source archive, checks its SHA-256 (and FFmpeg's release signature), and builds
static binaries into `Sources/Petal/Resources/Engines/`, where the Xcode project picks them up. FFmpeg is configured with
`--disable-gpl --disable-nonfree`, so the result is LGPL. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Project layout

```
Sources/Petal
  App/        entry point, menu bar, settings, wheel preferences, guided practice
  Core/       file kinds, wheel catalog, output naming, wheel arranger
  Engines/    image, PDF, media (AVFoundation + ffmpeg), text, spreadsheet, EPUB, PPTX, archive, Keynote / Pages / Numbers bridge
  Wheel/      drag monitor, drop surface, controller, SwiftUI wheel
  Editors/    photo editor (crop, adjust, background) and audio / video trim windows
  UI/         settings, welcome guide, result card, floating shelf
Tests/PetalTests
tools/        build-engines.sh, release.sh, stamp-site.py, icon generator
website/      the landing page with an interactive demo (static, no build step)
Config/       shared build settings
```

Adding a format: write an engine function, then add one entry to `Core/Catalog.swift`.

Debug builds also accept `--demo [--tools|--actions]` (an animated wheel), `--onboarding [--step=N]`, `--settings [--page=NAME]`,
`--edit <image> [--tab=crop|adjust|background]`, `--trim <file>` and `--run <operation-id> <file…>` (simulates a drop on a wedge).

## Releasing

```bash
tools/release.sh
```

builds a Release app, signs the bundled programs and the app with the hardened runtime, and makes `Petal-<version>.dmg`
(and stamps its size and SHA-256 into the website). With a *Developer ID Application* certificate and a
notarytool profile (`PETAL_NOTARY_PROFILE=…`) it also notarizes and staples the DMG; without them the DMG works, but macOS
shows "can't verify the developer" on the first launch (System Settings → Privacy & Security → Open Anyway).

To publish the DMG, which the website's Download button links to:

```bash
tools/publish-release.sh build-release/Petal-0.1.0.dmg 0.1.0   # add --notarized for a notarized build
```

It commits the stamped website and creates the GitHub Release `v0.1.0` with the DMG attached (needs the `gh` CLI).

## Website

`website/` is a static site: `index.html`, `privacy.html`, `licenses.html`. Preview it with
`cd website && python3 -m http.server 8766`. Release metadata lives in the `RELEASE` object at the top of `website/app.js`,
which `tools/stamp-site.py` rewrites. It is deployed to GitHub Pages by `.github/workflows/pages.yml` on every push to `main` that touches `website/`
(<https://lucalivigni.github.io/Petal/>); the DMG is not in the site, the Download button points at the GitHub Release asset.

## License

Petal's code is licensed under the [Apache License 2.0](LICENSE). The name Petal and the app icon are not covered by it
(see [NOTICE](NOTICE)). Built copies of the app include FFmpeg and other open-source components under their own licenses,
listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
