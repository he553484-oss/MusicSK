#!/usr/bin/env python3
"""Make a reference sheet from captures or independently aligned recordings."""

import argparse
from hashlib import file_digest
from io import BytesIO
import json
import math
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw, ImageFont, ImageOps, UnidentifiedImageError


def snapshot(path, seconds):
    if seconds is None:
        with Image.open(path) as image:
            return ImageOps.exif_transpose(image).convert("RGB")
    process = subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", f"{seconds:.6f}",
         "-i", str(path), "-map", "0:v:0", "-frames:v", "1", "-threads", "1",
         "-f", "image2pipe", "-c:v", "png", "pipe:1"],
        check=True, capture_output=True,
    )
    with Image.open(BytesIO(process.stdout)) as image:
        return image.convert("RGB")


def timeline(anchor, count, interval):
    if anchor is None:
        return [None] * count
    middle = (count - 1) / 2
    return [anchor + (index - middle) * interval for index in range(count)]


def describe(path, images, times):
    with path.open("rb") as stream:
        digest = file_digest(stream, "sha256").hexdigest()
    return {
        "file": path.name,
        "sha256": digest,
        "sizes_px": [list(image.size) for image in images],
        "requested_times_s": times,
    }


def write_sheet(output, columns, frame_times, label):
    width, height = 320, 510
    header, gutter, footer = 72, 12, 28
    rows = len(columns[0])
    sheet = Image.new("RGB", (width * 2 + gutter * 3, header + rows * (height + footer) + gutter), "#17191f")
    draw = ImageDraw.Draw(sheet)
    title = ImageFont.load_default(size=21)
    caption = ImageFont.load_default(size=15)
    draw.text((gutter, 8), label, font=title, fill="white")
    for column, name in enumerate(("Referencia", "Musicsk")):
        x = gutter + column * (width + gutter)
        draw.text((x, 43), name, font=caption, fill="#d8ddea")
        for row, source in enumerate(columns[column]):
            y = header + row * (height + footer)
            image = source.copy()
            image.thumbnail((width, height), Image.Resampling.LANCZOS)
            sheet.paste(image, (x + (width - image.width) // 2, y + (height - image.height) // 2))
            stamp = frame_times[column][row]
            time_label = "captura" if stamp is None else f"{stamp:.3f} s"
            draw.text((x, y + height + 4), f"{source.width} x {source.height} px  -  {time_label}",
                      font=caption, fill="#d8ddea")
    sheet.save(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path)
    parser.add_argument("musicsk", type=Path)
    parser.add_argument("--reference-at", type=float, help="Time in seconds of the matching event")
    parser.add_argument("--musicsk-at", type=float, help="Time in seconds of the same event in Musicsk")
    parser.add_argument("--count", type=int, default=5, help="Odd number of frames for recordings")
    parser.add_argument("--interval", type=float, default=0.15, help="Seconds between requested frames")
    parser.add_argument("--label", required=True, help="Screen, verse or independently aligned gesture")
    parser.add_argument("--output", type=Path, required=True, help="Output PNG path")
    args = parser.parse_args()

    anchors = (args.reference_at, args.musicsk_at)
    if (anchors[0] is None) != (anchors[1] is None):
        parser.error("For videos, supply both independent times.")
    if not 1 <= args.count <= 31 or args.count % 2 == 0:
        parser.error("--count must be odd and between 1 and 31.")
    if not math.isfinite(args.interval) or args.interval <= 0:
        parser.error("--interval must be positive and finite.")
    count = 1 if anchors[0] is None else args.count
    times = [timeline(anchor, count, args.interval) for anchor in anchors]
    if any(not math.isfinite(value) or value < 0 for series in times for value in series if value is not None):
        parser.error("A requested frame is outside the start of its recording. Adjust the count or time.")
    paths = (args.reference, args.musicsk)
    manifest = args.output.with_suffix(".json")
    inputs = {path.resolve() for path in paths}
    if args.output.suffix.lower() != ".png" or {args.output.resolve(), manifest.resolve()} & inputs:
        parser.error("--output must be a PNG separate from both inputs.")
    try:
        columns = [[snapshot(path, time) for time in series] for path, series in zip(paths, times)]
        args.output.parent.mkdir(parents=True, exist_ok=True)
        write_sheet(args.output, columns, times, args.label)
        manifest.write_text(json.dumps({
            "label": args.label,
            "reference": describe(paths[0], columns[0], times[0]),
            "musicsk": describe(paths[1], columns[1], times[1]),
        }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    except subprocess.CalledProcessError as error:
        parser.exit(1, f"FFmpeg: {error.stderr.decode(errors='replace').strip()}\n")
    except (OSError, UnidentifiedImageError) as error:
        parser.exit(1, f"Capture unavailable: {error}\n")


if __name__ == "__main__":
    main()
