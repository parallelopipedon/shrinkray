#!/usr/bin/env bash
#
# Bash equivalent of shrink.py. Recursively scans a folder for videos and
# downscales anything above 1080p/30fps, using ffmpeg. Videos already at or
# below 1080p30 are left as is.
#
# Originals are always left untouched. A "shrunk-<timestamp>" folder is
# created inside the source folder, mirroring the exact same directory
# structure. Video files go in shrunk (or copied, if already <=1080p30);
# every other file is copied over unchanged.
#
# Usage:
#   ./shrink.sh [folder] [--ext mp4 mov mkv ...]

set -euo pipefail

MAX_WIDTH=1920
MAX_HEIGHT=1080
MAX_FPS=30
DEFAULT_EXTENSIONS=(mp4 mov mkv avi m4v)

FOLDER="."
EXTENSIONS=()

if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
    FOLDER="$1"
    shift
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --ext)
            shift
            while [ $# -gt 0 ] && [[ "$1" != --* ]]; do
                EXTENSIONS+=("$1")
                shift
            done
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [folder] [--ext ext1 ext2 ...]" >&2
            exit 1
            ;;
    esac
done

if [ ${#EXTENSIONS[@]} -eq 0 ]; then
    EXTENSIONS=("${DEFAULT_EXTENSIONS[@]}")
fi

command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg not found. Install with: brew install ffmpeg" >&2; exit 1; }
command -v ffprobe >/dev/null 2>&1 || { echo "ffprobe not found. Install with: brew install ffmpeg" >&2; exit 1; }

FOLDER="$(cd "$FOLDER" && pwd)"

OUTPUT_ROOT="$FOLDER/shrunk-$(date +%Y%m%d%H%M%S)"

is_video() {
    local ext="${1##*.}"
    ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
    local e
    for e in "${EXTENSIONS[@]}"; do
        [ "$ext" = "$e" ] && return 0
    done
    return 1
}

shrink_video() {
    local src="$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    local tmp="${dest%.*}.shrink_tmp.${dest##*.}"
    local vf="scale='min(${MAX_WIDTH},iw)':'min(${MAX_HEIGHT},ih)':force_original_aspect_ratio=decrease,fps='min(${MAX_FPS},source_fps)',scale=trunc(iw/2)*2:trunc(ih/2)*2"

    if ffmpeg -y -i "$src" -vf "$vf" -c:v libx264 -preset medium -crf 20 -c:a copy "$tmp" -loglevel error; then
        mv -f "$tmp" "$dest"
        return 0
    else
        rm -f "$tmp"
        return 1
    fi
}

mapfile -d '' -t files < <(find "$FOLDER" -path "$OUTPUT_ROOT" -prune -o -type f -print0 | sort -z)

if [ ${#files[@]} -eq 0 ]; then
    echo "No files found in $FOLDER"
    exit 0
fi

for file in "${files[@]}"; do
    rel="${file#"$FOLDER"/}"
    dest="$OUTPUT_ROOT/$rel"

    if ! is_video "$file"; then
        mkdir -p "$(dirname "$dest")"
        cp -p "$file" "$dest"
        echo "COPIED (non-video): $file -> $dest"
        continue
    fi

    unset width height fps_raw
    read -r width height fps_raw < <(ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height,r_frame_rate \
        -of csv=p=0 "$file" 2>/dev/null | tr ',' ' ') || true

    if [ -z "${width:-}" ] || [ -z "${height:-}" ]; then
        echo "SKIP (no video stream found): $file"
        continue
    fi

    fps=$(awk -F'/' '{ if ($2 == 0) print 0; else printf "%d", ($1/$2)+0.5 }' <<< "$fps_raw")

    if [ "$width" -le "$MAX_WIDTH" ] && [ "$height" -le "$MAX_HEIGHT" ] && [ "$fps" -le "$MAX_FPS" ]; then
        mkdir -p "$(dirname "$dest")"
        cp -p "$file" "$dest"
        echo "COPIED, already <=1080p30 (${width}x${height} @ ${fps}fps): $file -> $dest"
        continue
    fi

    echo "DOWNSCALING (${width}x${height} @ ${fps}fps -> <=1080p30): $file"
    if shrink_video "$file" "$dest"; then
        echo "  -> done: $dest"
    else
        echo "  -> ffmpeg failed, leaving original untouched: $file" >&2
    fi
done
