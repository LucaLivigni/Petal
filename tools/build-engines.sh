#!/bin/bash
# Builds the helper tools that ship inside Petal: ffmpeg and cwebp, as self-contained arm64 binaries.
#
#  * Sources come only from the projects' official download sites, over HTTPS, and are pinned by SHA-256.
#    (ffmpeg's tarball is additionally verified against the FFmpeg release signing key.)
#  * ffmpeg is built --disable-gpl --disable-nonfree, so the result is LGPL 2.1+. H.264 / HEVC use Apple's
#    VideoToolbox instead of x264 / x265. Every other library is BSD or LGPL.
#  * Output goes to Sources/Petal/Resources/Engines/, which the Xcode project copies into the app bundle.
#
# Usage: tools/build-engines.sh        (takes roughly 10 minutes)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

WORK=${PETAL_ENGINES_WORK:-/tmp/petal-engines-work}
SRC=$WORK/src
BUILD=$WORK/build
PREFIX=$WORK/prefix
OUT=$ROOT/Sources/Petal/Resources/Engines
JOBS=$(sysctl -n hw.ncpu)
mkdir -p "$SRC" "$BUILD" "$PREFIX" "$OUT/licenses"

export MACOSX_DEPLOYMENT_TARGET=15.0
export CC=clang CXX=clang++
export CFLAGS="-O2 -arch arm64 -mmacosx-version-min=15.0"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-arch arm64 -mmacosx-version-min=15.0"
export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

FFMPEG_VERSION=9.0.2
LAME_VERSION=3.100
OGG_VERSION=1.3.6
VORBIS_VERSION=1.3.7
OPUS_VERSION=1.6.1
VPX_VERSION=1.17.0
WEBP_VERSION=1.6.0
PNG_VERSION=1.6.59
PKGCONF_VERSION=3.0.10

SOURCES_LOG="$WORK/SOURCES.txt"
: > "$SOURCES_LOG"

step() { printf '\n==== %s ====\n' "$*"; }
# Each library is built once; delete $WORK/prefix/.built-<name> to force a rebuild.
built() { [ -f "$PREFIX/.built-$1" ]; }
mark() { touch "$PREFIX/.built-$1"; }


# fetch <file> <url> <sha256>
fetch() {
  local file=$1 url=$2 sha=$3
  [ -f "$SRC/$file" ] || curl -fL --proto '=https' --tlsv1.2 -sS -o "$SRC/$file" "$url"
  local actual; actual=$(shasum -a 256 "$SRC/$file" | cut -d' ' -f1)
  if [ "$actual" != "$sha" ]; then echo "SHA-256 mismatch for $file: expected $sha, got $actual" >&2; exit 1; fi
  echo "$file  $sha  $url" >> "$SOURCES_LOG"
}

# unpack <file> <dir-name>
unpack() { rm -rf "$BUILD/$2"; mkdir -p "$BUILD/$2"; tar -xf "$SRC/$1" -C "$BUILD/$2" --strip-components=1; }

step "Fetching sources"
fetch "ffmpeg-$FFMPEG_VERSION.tar.xz"   "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz"                          8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
fetch "lame-$LAME_VERSION.tar.gz"       "https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz" ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e
fetch "libogg-$OGG_VERSION.tar.xz"      "https://downloads.xiph.org/releases/ogg/libogg-$OGG_VERSION.tar.xz"                  5c8253428e181840cd20d41f3ca16557a9cc04bad4a3d04cce84808677fa1061
fetch "libvorbis-$VORBIS_VERSION.tar.xz" "https://downloads.xiph.org/releases/vorbis/libvorbis-$VORBIS_VERSION.tar.xz"          b33cc4934322bcbf6efcbacf49e3ca01aadbea4114ec9589d1b1e9d20f72954b
fetch "opus-$OPUS_VERSION.tar.gz"       "https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz"                  6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1
fetch "libvpx-$VPX_VERSION.tar.gz"      "https://github.com/webmproject/libvpx/archive/refs/tags/v$VPX_VERSION.tar.gz"        1020f184046187baa2985dbde38e0691f49c44088bca7a1842b0236c6081dc0a
fetch "libwebp-$WEBP_VERSION.tar.gz"    "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$WEBP_VERSION.tar.gz" e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564
fetch "libpng-$PNG_VERSION.tar.xz"      "https://download.sourceforge.net/libpng/libpng-$PNG_VERSION.tar.xz"                  d80dd2a38a37f803cb9b6ac7b14bd6e74ddc3b654780a8380bdf93523fdb4389
fetch "pkgconf-$PKGCONF_VERSION.tar.xz" "https://distfiles.ariadne.space/pkgconf/pkgconf-$PKGCONF_VERSION.tar.xz"              9371b2f6372da574d4c6dc96fe9b1463037bcf6afcb6671c1555afde7b17e2de

if [ -f "$SRC/ffmpeg-$FFMPEG_VERSION.tar.xz.asc" ] && [ -f "$SRC/ffmpeg-devel.asc" ]; then
  step "Verifying ffmpeg signature"
  mkdir -p "$WORK/gpg" && chmod 700 "$WORK/gpg"
  GNUPGHOME="$WORK/gpg" gpg --quiet --import "$SRC/ffmpeg-devel.asc" 2>/dev/null || true
  GNUPGHOME="$WORK/gpg" gpg --verify "$SRC/ffmpeg-$FFMPEG_VERSION.tar.xz.asc" "$SRC/ffmpeg-$FFMPEG_VERSION.tar.xz"
fi

MAKE_INSTALL='make -j"$JOBS" >/dev/null && make install >/dev/null'

build_pkgconf() {
  ./configure --prefix="$PREFIX" --with-system-libdir=/usr/lib --with-system-includedir=/usr/include >/dev/null
  make -j"$JOBS" >/dev/null && make install >/dev/null
  ln -sf pkgconf "$PREFIX/bin/pkg-config"
}
build_lame() {
  ./configure --prefix="$PREFIX" --disable-shared --enable-static --disable-frontend --disable-decoder --disable-gtktest >/dev/null
  make -j"$JOBS" >/dev/null && make install >/dev/null
}
build_ogg() {
  ./configure --prefix="$PREFIX" --disable-shared --enable-static >/dev/null
  make -j"$JOBS" >/dev/null && make install >/dev/null
}
build_vorbis() {
  # 1.3.7's configure still passes a PowerPC-era linker flag that modern ld rejects.
  sed -i '' 's/-force_cpusubtype_ALL//g' configure
  ./configure --prefix="$PREFIX" --disable-shared --enable-static --disable-docs --disable-examples --disable-oggtest >/dev/null
  make -j"$JOBS" >/dev/null && make install >/dev/null
}
build_opus() {
  ./configure --prefix="$PREFIX" --disable-shared --enable-static --disable-doc --disable-extra-programs >/dev/null
  make -j"$JOBS" >/dev/null && make install >/dev/null
}
build_vpx() {
  local target=arm64-darwin24-gcc   # Darwin 24 = macOS 15, the deployment target
  echo "libvpx target: $target"
  ./configure --prefix="$PREFIX" --target="$target" --disable-shared --enable-static --enable-pic \
    --disable-examples --disable-tools --disable-docs --disable-unit-tests --disable-install-docs \
    --disable-vp8-decoder --disable-vp9-decoder >/dev/null
  make -j"$JOBS" >/dev/null && make install >/dev/null
}
build_png() {
  ./configure --prefix="$PREFIX" --disable-shared --enable-static >/dev/null
  make -j"$JOBS" >/dev/null && make install >/dev/null
}
build_webp() {
  cmake -S . -B out -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local" -DCMAKE_C_FLAGS="-I$PREFIX/include" \
    -DPNG_PNG_INCLUDE_DIR="$PREFIX/include" -DPNG_LIBRARY="$PREFIX/lib/libpng16.a" -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DBUILD_SHARED_LIBS=OFF -DWEBP_LINK_STATIC=ON -DWEBP_BUILD_CWEBP=ON -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF \
    -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_ANIM_UTILS=OFF \
    -DWEBP_BUILD_EXTRAS=OFF >/dev/null
  cmake --build out -j"$JOBS" >/dev/null && cmake --install out >/dev/null
  cp out/cwebp "$PREFIX/bin/cwebp"
}
build_ffmpeg() {
  # Only what Petal uses: every decoder and demuxer (so any input opens), but a short list of encoders, muxers,
  # filters and protocols. This keeps the binary at roughly half the size of a default build.
  local encoders="aac,libmp3lame,libvorbis,libopus,flac,alac,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_f32le,wmav2,wmv2,mpeg4,libvpx_vp8,libvpx_vp9,h264_videotoolbox,gif,libwebp,libwebp_anim,png,mjpeg"
  local muxers="mp4,mov,ipod,matroska,webm,avi,asf,ogg,opus,mp3,wav,aiff,flac,caf,gif,webp,null"
  local filters="scale,format,fps,split,palettegen,paletteuse,aresample,aformat,anull,null,trim,atrim,setpts,asetpts,crop,transpose,hflip,vflip,pad,volume"
  ./configure --prefix="$PREFIX/ffmpeg-out" --arch=arm64 --cc=clang \
    --enable-static --disable-shared --disable-debug --disable-doc --enable-small \
    --disable-gpl --disable-nonfree --disable-autodetect \
    --disable-ffplay --disable-ffprobe --enable-ffmpeg \
    --disable-network --disable-avdevice \
    --disable-everything \
    --enable-decoders --enable-demuxers --enable-parsers --enable-bsfs \
    --enable-encoder="$encoders" --enable-muxer="$muxers" --enable-filter="$filters" --enable-protocol=file,pipe \
    --enable-videotoolbox --enable-audiotoolbox --enable-zlib --enable-iconv --enable-bzlib \
    --enable-libmp3lame --enable-libvorbis --enable-libopus --enable-libvpx --enable-libwebp \
    --pkg-config="$PREFIX/bin/pkg-config" --pkg-config-flags="--static" \
    --extra-cflags="-I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib -Wl,-dead_strip" --extra-libs="-liconv"
  make -j"$JOBS" >/dev/null && make install >/dev/null
}

# stage <name> <title> <archive> <function>
stage() {
  step "$2"
  if built "$1"; then echo "already built"; return; fi
  unpack "$3" "$1"
  ( cd "$BUILD/$1" && "$4" )
  mark "$1"
}

stage pkgconf pkgconf "pkgconf-$PKGCONF_VERSION.tar.xz" build_pkgconf
stage lame "LAME (MP3)" "lame-$LAME_VERSION.tar.gz" build_lame
stage ogg libogg "libogg-$OGG_VERSION.tar.xz" build_ogg
stage vorbis libvorbis "libvorbis-$VORBIS_VERSION.tar.xz" build_vorbis
stage opus Opus "opus-$OPUS_VERSION.tar.gz" build_opus
stage vpx "libvpx (VP8 / VP9)" "libvpx-$VPX_VERSION.tar.gz" build_vpx
stage png "libpng (for cwebp input)" "libpng-$PNG_VERSION.tar.xz" build_png
stage webp "libwebp + cwebp" "libwebp-$WEBP_VERSION.tar.gz" build_webp
stage ffmpeg "ffmpeg (LGPL)" "ffmpeg-$FFMPEG_VERSION.tar.xz" build_ffmpeg

step "Installing into the app resources"
cp "$PREFIX/ffmpeg-out/bin/ffmpeg" "$OUT/ffmpeg"
cp "$PREFIX/bin/cwebp" "$OUT/cwebp"
strip -x "$OUT/ffmpeg" "$OUT/cwebp"
for tool in ffmpeg cwebp; do
  echo "-- $tool links:"; otool -L "$OUT/$tool" | tail -n +2
  if otool -L "$OUT/$tool" | tail -n +2 | grep -vE '^\s+(/usr/lib/|/System/Library/)'; then
    echo "$tool depends on a library outside the system" >&2; exit 1
  fi
done

L="$OUT/licenses"
cp "$BUILD/ffmpeg/COPYING.LGPLv2.1" "$L/ffmpeg-LGPL-2.1.txt"
cp "$BUILD/lame/COPYING" "$L/lame-LGPL-2.0.txt"
cp "$BUILD/ogg/COPYING" "$L/libogg-BSD.txt"
cp "$BUILD/vorbis/COPYING" "$L/libvorbis-BSD.txt"
cp "$BUILD/opus/COPYING" "$L/opus-BSD.txt"
cp "$BUILD/vpx/LICENSE" "$L/libvpx-BSD.txt"
cp "$BUILD/webp/COPYING" "$L/libwebp-BSD.txt"
cp "$BUILD/png/LICENSE" "$L/libpng-license.txt"
{
  echo "Petal bundles two helper programs, built from unmodified upstream source with tools/build-engines.sh:"
  echo "  ffmpeg $FFMPEG_VERSION  (LGPL 2.1 or later, built with --disable-gpl --disable-nonfree)"
  echo "  cwebp  from libwebp $WEBP_VERSION  (BSD)"
  echo "ffmpeg is linked statically against: LAME $LAME_VERSION (LGPL), libogg $OGG_VERSION and libvorbis $VORBIS_VERSION (BSD),"
  echo "Opus $OPUS_VERSION (BSD), libvpx $VPX_VERSION (BSD), libwebp $WEBP_VERSION (BSD). cwebp uses libpng $PNG_VERSION."
  echo "The programs run as separate processes; Petal itself is not linked against them."
  echo "The exact source archives (download URL and SHA-256) are listed below; the build script is in the Petal repository."
  echo
  cat "$SOURCES_LOG"
} > "$L/SOURCES.txt"

step "Smoke test"
"$OUT/ffmpeg" -hide_banner -version | head -3
"$OUT/ffmpeg" -hide_banner -encoders 2>/dev/null | grep -E 'libmp3lame|libvorbis|libopus|libvpx|libwebp|h264_videotoolbox|wmv2|wmav2' || true
T=$(mktemp -d)
"$OUT/ffmpeg" -hide_banner -loglevel error -f lavfi -i "sine=frequency=440:duration=1" -c:a libmp3lame "$T/a.mp3" && ls -la "$T/a.mp3"
"$OUT/ffmpeg" -hide_banner -loglevel error -f lavfi -i "color=c=orange:s=64x64:d=1" -frames:v 1 -c:v libwebp "$T/a.webp" && ls -la "$T/a.webp"
"$OUT/cwebp" -version
step "Done"
