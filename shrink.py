#!/usr/bin/env python3
"""
Loop over video files in a folder (recursively). Any file whose resolution
exceeds 1080p or whose frame rate exceeds 30fps gets downscaled/capped.
Files already at or below 1080p30 are left as is.

Originals are always left untouched. A "shrunk-YYYYMMDDHHMMSS" folder is
created inside the source folder, mirroring the exact same directory
structure. Video files go in shrunk (or copied, if already <=1080p30); every
other file is copied over unchanged.

Usage:
    python3 shrink.py [folder] [--ext mp4 mov mkv ...]

Requires ffmpeg / ffprobe to be installed and on PATH.
"""

import argparse
import json
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

MAX_WIDTH = 1920
MAX_HEIGHT = 1080
MAX_FPS = 30

DEFAULT_EXTENSIONS = ["mp4", "mov", "mkv", "avi", "m4v"]


def check_dependencies():
    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            sys.exit(f"{tool} not found. Install with: brew install ffmpeg")


def probe_video(path: Path):
    """Return (width, height, fps) for the first video stream, or None if none found."""
    result = subprocess.run(
        [
            "ffprobe", "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height,r_frame_rate",
            "-of", "json",
            str(path),
        ],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        return None

    data = json.loads(result.stdout)
    streams = data.get("streams", [])
    if not streams:
        return None

    stream = streams[0]
    width = stream.get("width")
    height = stream.get("height")

    num, den = stream.get("r_frame_rate", "0/1").split("/")
    fps = float(num) / float(den) if float(den) != 0 else 0.0

    return width, height, fps


def shrink_video(src: Path, dest: Path):
    """Encode src down to <=1080p30 and write the result to dest."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = dest.with_suffix(f".shrink_tmp{dest.suffix}")

    vf = (
        f"scale='min({MAX_WIDTH},iw)':'min({MAX_HEIGHT},ih)':force_original_aspect_ratio=decrease,"
        f"fps='min({MAX_FPS},source_fps)',"
        f"scale=trunc(iw/2)*2:trunc(ih/2)*2"
    )

    cmd = [
        "ffmpeg", "-y", "-i", str(src),
        "-vf", vf,
        "-c:v", "libx264", "-preset", "medium", "-crf", "20",
        "-c:a", "copy",
        str(tmp_path),
        "-loglevel", "error",
    ]

    result = subprocess.run(cmd)
    if result.returncode == 0:
        tmp_path.replace(dest)
        return True
    else:
        tmp_path.unlink(missing_ok=True)
        return False


def main():
    parser = argparse.ArgumentParser(description="Downscale videos above 1080p30.")
    parser.add_argument("folder", nargs="?", default=".", help="Folder to scan (default: current directory)")
    parser.add_argument("--ext", nargs="+", default=DEFAULT_EXTENSIONS, help="File extensions to process")
    args = parser.parse_args()

    check_dependencies()

    folder = Path(args.folder).resolve()
    extensions = {e.lower().lstrip(".") for e in args.ext}

    output_root = folder / f"shrunk-{datetime.now():%Y%m%d%H%M%S}"

    files = sorted(
        f for f in folder.rglob("*")
        if f.is_file() and output_root not in f.parents
    )

    if not files:
        print(f"No files found in {folder}")
        return

    for file in files:
        rel = file.relative_to(folder)
        dest = output_root / rel
        is_video = file.suffix.lower().lstrip(".") in extensions

        if not is_video:
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(file, dest)
            print(f"COPIED (non-video): {file} -> {dest}")
            continue

        info = probe_video(file)
        if info is None:
            print(f"SKIP (no video stream found): {file}")
            continue

        width, height, fps = info

        if width <= MAX_WIDTH and height <= MAX_HEIGHT and fps <= MAX_FPS:
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(file, dest)
            print(f"COPIED, already <=1080p30 ({width}x{height} @ {fps:.2f}fps): {file} -> {dest}")
            continue

        print(f"DOWNSCALING ({width}x{height} @ {fps:.2f}fps -> <=1080p30): {file}")
        if shrink_video(file, dest):
            print(f"  -> done: {dest}")
        else:
            print(f"  -> ffmpeg failed, leaving original untouched: {file}", file=sys.stderr)


if __name__ == "__main__":
    main()
