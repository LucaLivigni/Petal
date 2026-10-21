#!/usr/bin/env bash
# Publishes Petal-<version>.dmg as a GitHub Release asset, which is what the website's Download button links to.
#
# Usage: tools/publish-release.sh <path-to.dmg> <version> [--notarized]
#
# Run tools/release.sh first (it builds the DMG), then this: it stamps the website with the DMG's size and SHA-256,
# commits that, and creates the release v<version>. Requires the GitHub CLI, logged in with write access.
set -euo pipefail

dmg="${1:?usage: publish-release.sh <path-to.dmg> <version> [--notarized]}"
version="${2:?usage: publish-release.sh <path-to.dmg> <version> [--notarized]}"
shift 2
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

python3 tools/stamp-site.py "$dmg" "$version" "$@"
git add website
git commit -m "Website: release ${version}"
git push origin HEAD

notes="Requires macOS 15 or later on Apple silicon.\n\nSHA-256: $(shasum -a 256 "$dmg" | cut -d' ' -f1)"
if [[ " $* " != *" --notarized "* ]]; then
  notes+="\n\nThis build is not notarized yet. On first launch macOS says it can't verify the developer: open System Settings → Privacy & Security and choose *Open Anyway*."
fi
gh release create "v${version}" "$dmg" --title "Petal ${version}" --notes "$(printf '%b' "$notes")" --target "$(git rev-parse HEAD)"
echo "Published v${version}. The website redeploys automatically."
