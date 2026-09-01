#!/usr/bin/env bash
#
# Renders one store poster per entry in posters.json, using headless Chrome.
#
#   tool/posters/build.sh                 # every poster in posters.json
#   tool/posters/build.sh 01-log.png      # only entries whose `out` matches
#   tool/posters/build.sh --wide          # the 1920x1080 landscape poster
#
# Screenshots live in tool/posters/shots/, under the names posters.json
# expects. Capture them from a device or emulator with:
#
#   adb exec-out screencap -p > tool/posters/shots/log.png
#
# Output is written to build/posters/ at 1242x2208, the size the Play Store
# asks for. The captured screens are committed alongside the template, so the
# posters can be re-rendered without a device; the README copies live in
# design/posters/.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out_dir="$root/build/posters"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

if [[ ! -x "$chrome" ]]; then
  echo "Google Chrome was not found at: $chrome" >&2
  exit 1
fi

mkdir -p "$out_dir"
filter="${1:-}"

# The landscape poster is one fixed layout rather than an entry in posters.json,
# so it renders on its own and returns.
if [[ "$filter" == "--wide" ]]; then
  "$chrome" \
    --headless \
    --disable-gpu \
    --hide-scrollbars \
    --allow-file-access-from-files \
    --force-device-scale-factor=1 \
    --virtual-time-budget=4000 \
    --window-size=1920,1080 \
    --screenshot="$out_dir/wide.png" \
    "file://$here/wide.html" > /dev/null 2>&1
  echo "wrote build/posters/wide.png"
  exit 0
fi

urlencode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1"
}

# Python reads the JSON, because poster titles contain spaces and punctuation,
# and every shell-only way of reading them back is a quoting bug in waiting.
python3 - "$here/posters.json" "$filter" <<'PY' | while IFS=$'\t' read -r out kicker title note shot accent; do
import json, sys

entries = json.load(open(sys.argv[1]))
wanted = sys.argv[2] if len(sys.argv) > 2 else ''

for e in entries:
    if wanted and wanted not in e['out']:
        continue
    print('\t'.join([
        e['out'], e.get('kicker', ''), e['title'],
        e.get('note', ''), e['shot'], e.get('accent', '#5b8cff'),
    ]))
PY
  if [[ ! -f "$here/$shot" ]]; then
    echo "skipped $out — no screenshot at tool/posters/$shot" >&2
    continue
  fi

  url="file://$here/poster.html"
  url+="?title=$(urlencode "$title")"
  url+="&kicker=$(urlencode "$kicker")"
  url+="&note=$(urlencode "$note")"
  url+="&shot=$(urlencode "$shot")"
  url+="&accent=$(urlencode "$accent")"

  "$chrome" \
    --headless \
    --disable-gpu \
    --hide-scrollbars \
    --allow-file-access-from-files \
    --force-device-scale-factor=1 \
    --virtual-time-budget=4000 \
    --window-size=1242,2208 \
    --screenshot="$out_dir/$out" \
    "$url" > /dev/null 2>&1

  echo "wrote build/posters/$out"
done
