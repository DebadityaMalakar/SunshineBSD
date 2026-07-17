#!/bin/sh
# fetch-fonts.sh — install SunshineBSD's system fonts into a target root
# directory, fetched live from Google Fonts.
#
# One job: download Open Sans (PLAN.md's `Font: Open Sans` foundation
# decision) and Noto Color Emoji (the emoji fallback almost every modern
# Linux desktop ships) into <rootdir>/usr/local/share/fonts/<family>/.
#
# Open Sans is pulled as its two variable-font files (regular + italic,
# covering the full weight/width range in one file each) straight from
# the official google/fonts GitHub mirror -- the same files "download
# family" on fonts.google.com would give you. Noto Color Emoji has no
# variable axes and ships as a single static file whose gstatic.com URL
# carries a version hash that changes over time, so its URL is resolved
# live via the Google Fonts CSS2 API rather than pinned.
#
# usage: tools/fetch-fonts.sh <rootdir>
#
# Environment:
#   SUNSHINE_FONT_CACHE  download cache (default: ~/.cache/sunshinebsd/fonts)

set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: fetch-fonts.sh <rootdir>" >&2
    exit 2
fi
tree="$1"
cache="${SUNSHINE_FONT_CACHE:-$HOME/.cache/sunshinebsd/fonts}"

command -v curl >/dev/null 2>&1 || {
    echo "fetch-fonts: missing tool: curl" >&2
    exit 1
}

mkdir -p "$cache"

# fetch_url <url> <dest-filename> -- download once (cached by filename),
# verify the download is non-empty, then copy into place.
fetch_url() {
    url="$1"
    dest="$2"
    name=$(basename "$dest")
    out="$cache/$name"
    if [ ! -f "$out" ]; then
        curl -fL -o "$out.$$" "$url"
        [ -s "$out.$$" ] || {
            echo "fetch-fonts: empty download: $url" >&2
            rm -f "$out.$$"
            exit 1
        }
        mv "$out.$$" "$out"
    fi
    cp "$out" "$dest"
}

# --- Open Sans: variable font, pinned to the official mirror path ------

opensans_dest="$tree/usr/local/share/fonts/opensans"
mkdir -p "$opensans_dest"
gfonts_raw="https://raw.githubusercontent.com/google/fonts/main/ofl/opensans"
fetch_url "$gfonts_raw/OpenSans%5Bwdth,wght%5D.ttf" "$opensans_dest/OpenSans[wdth,wght].ttf"
fetch_url "$gfonts_raw/OpenSans-Italic%5Bwdth,wght%5D.ttf" "$opensans_dest/OpenSans-Italic[wdth,wght].ttf"
echo "fetch-fonts: installed opensans (2 file(s))"

# --- Noto Color Emoji: resolve the current gstatic URL live ------------

emoji_dest="$tree/usr/local/share/fonts/noto-color-emoji"
mkdir -p "$emoji_dest"
# A real browser User-Agent is required: Google Fonts serves woff2 to
# modern UAs and only serves plain TrueType to older/unrecognized ones;
# TTF is what fontconfig on FreeBSD/Xfce wants.
ua="Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/78.0"
css=$(curl -fsL -A "$ua" "https://fonts.googleapis.com/css2?family=Noto+Color+Emoji&display=swap")
emoji_url=$(echo "$css" | grep -o 'https://fonts\.gstatic\.com/[^)]*' | head -n 1)
[ -n "$emoji_url" ] || {
    echo "fetch-fonts: could not resolve a Noto Color Emoji URL from the CSS2 API" >&2
    exit 1
}
fetch_url "$emoji_url" "$emoji_dest/NotoColorEmoji.ttf"
echo "fetch-fonts: installed noto-color-emoji (1 file(s))"
