# Third-party software

Petal's own code is licensed under the Apache License 2.0 (see `LICENSE`). Built copies of the app also contain the
programs below. **None of them is stored in this repository as a binary**: `tools/build-engines.sh` downloads each project's
official source archive from its own site, checks its SHA-256 (and, for FFmpeg, the release signature), and builds them.

| Component | Version | License | How Petal uses it |
|---|---|---|---|
| [FFmpeg](https://ffmpeg.org) | 9.0.2 | LGPL 2.1 or later (configured with `--disable-gpl --disable-nonfree`) | A separate program, `ffmpeg`, that Petal starts as its own process to read and write MP3, WebM, MKV, AVI, WMV, OGG, Opus, WMA and WebP |
| [LAME](https://lame.sourceforge.io) | 3.100 | LGPL 2.0 or later | MP3 encoder, linked statically inside the `ffmpeg` program |
| [libogg](https://xiph.org/ogg/) and [libvorbis](https://xiph.org/vorbis/) | 1.3.6 / 1.3.7 | BSD-3-Clause | Linked statically inside `ffmpeg` |
| [Opus](https://opus-codec.org) | 1.6.1 | BSD-3-Clause | Linked statically inside `ffmpeg` |
| [libvpx](https://www.webmproject.org) | 1.17.0 | BSD-3-Clause | VP8 / VP9 encoder, linked statically inside `ffmpeg` |
| [libwebp](https://developers.google.com/speed/webp) (`cwebp`) | 1.6.0 | BSD-3-Clause | WebP encoder, a separate program, `cwebp` |
| [libpng](http://www.libpng.org/pub/png/libpng.html) | 1.6.59 | libpng License | PNG input for `cwebp` |

H.264 and HEVC are written with Apple's VideoToolbox, not with x264 or x265, so no GPL code is involved.

## What the LGPL asks of anyone who distributes a build

* Keep the license texts with the app. They are copied into `Petal.app/Contents/Resources/Engines/licenses/` by the build.
* Make the corresponding source available. `Engines/licenses/SOURCES.txt` in every build lists the exact archives and their
  SHA-256 hashes, and `tools/build-engines.sh` rebuilds the binaries from them unmodified. Because `ffmpeg` runs as its own
  program and is not linked into Petal, a user can replace it with their own build of FFmpeg.
* Do not claim that the LGPL components are your own work.

The license texts are in `Sources/Petal/Resources/Engines/licenses/`.

## Apple software

Petal uses Apple's public system frameworks (ImageIO, AVFoundation, PDFKit, Vision, TextKit, Core Image). It can ask
Keynote, Pages and Numbers, if the user has them, to convert slides, documents and spreadsheets through AppleScript.
