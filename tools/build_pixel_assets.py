"""Normalize generated pixel assets; never invent or paint creative pixels.

Keeps originals, removes only explicit chroma/checker backgrounds, uses nearest
sampling, one scale per animation strip and stable bottom-centre anchors.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
import cv2

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "InheritanceTasks/Art/Pixel/v1"


def alpha_image(path: Path, key: str = "none") -> Image.Image:
    image = Image.open(path).convert("RGBA")
    data = np.array(image)
    rgb = data[:, :, :3].astype(np.int16)
    if key == "green":
        green = rgb[:, :, 1]
        mask = (green > 80) & (green > rgb[:, :, 0] * 1.6 + 20) & (green > rgb[:, :, 2] * 1.6 + 20)
        data[mask, 3] = 0
        # Remove chroma spill only at the transparent boundary; preserve green
        # clothing and scenery inside the silhouette. Alpha/anchors stay intact.
        opaque = (data[:, :, 3] > 0).astype(np.uint8)
        edge = (opaque - cv2.erode(opaque, np.ones((3, 3), np.uint8))) > 0
        spill = edge & (green > rgb[:, :, 0] + 10) & (green > rgb[:, :, 2] + 10)
        data[spill, 1] = ((rgb[:, :, 0][spill] + rgb[:, :, 2][spill]) // 2).astype(np.uint8)
    elif key == "checker":
        # Only border-connected neutral light pixels. Dark closed outlines
        # protect faces, white clothes and highlights inside the silhouette.
        candidates = (rgb.max(2) - rgb.min(2) < 24) & (rgb.min(2) > 165)
        _, labels = cv2.connectedComponents(candidates.astype(np.uint8), connectivity=4)
        border = np.unique(np.concatenate((labels[0], labels[-1], labels[:, 0], labels[:, -1])))
        border = border[border != 0]
        data[np.isin(labels, border), 3] = 0
    data[data[:, :, 3] == 0, :3] = 0
    return Image.fromarray(data)


def normalized_strip(image: Image.Image, boxes: list[list[int]], frame_size: tuple[int, int], padding: int = 4) -> list[Image.Image]:
    cells = [image.crop(tuple(box)) for box in boxes]
    bounds = [cell.getbbox() for cell in cells]
    if any(bound is None for bound in bounds):
        raise ValueError("An animation cell contains no opaque pixels")
    max_width = max(b[2] - b[0] for b in bounds)
    max_height = max(b[3] - b[1] for b in bounds)
    scale = min((frame_size[0] - 2 * padding) / max_width, (frame_size[1] - 2 * padding) / max_height)
    result = []
    for cell, bound in zip(cells, bounds):
        sprite = cell.crop(bound)
        sprite = sprite.resize((max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale))), Image.Resampling.NEAREST)
        target = Image.new("RGBA", frame_size)
        target.alpha_composite(sprite, ((frame_size[0] - sprite.width) // 2, frame_size[1] - padding - sprite.height))
        result.append(target)
    return result


def save_atlas(frames: list[Image.Image], output: Path, columns: int) -> None:
    width, height = frames[0].size
    atlas = Image.new("RGBA", (width * columns, height * ((len(frames) + columns - 1) // columns)))
    for i, frame in enumerate(frames):
        atlas.alpha_composite(frame, ((i % columns) * width, (i // columns) * height))
    output.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(output)


def identity(identifier: str, split: float, key: str) -> dict:
    source = ART / "source" / f"identity-{identifier}.png"
    image = alpha_image(source, key)
    width, height = image.size
    y = round(height * split)
    body_boxes = [[round(i * width / 4), 0, round((i + 1) * width / 4), y] for i in range(4)]
    face_boxes = [[round(i * width / 4), y, round((i + 1) * width / 4), height] for i in range(4)]
    bodies = normalized_strip(image, body_boxes, (112, 160))
    faces = normalized_strip(image, face_boxes, (80, 80))
    output = ART / "runtime" / "identities" / identifier
    output.mkdir(parents=True, exist_ok=True)
    save_atlas(bodies, output / "turnaround.png", 4)
    save_atlas(faces, output / "expressions.png", 4)
    faces[0].save(output / "portrait.png")
    for i, frame in enumerate(bodies):
        frame.save(output / f"body-{i}.png")
    preview = Image.new("RGB", (448, 252), "#46382e")
    for i, frame in enumerate(bodies):
        preview.paste(frame, (i * 112, 0), frame)
    for i, frame in enumerate(faces):
        preview.paste(frame, (i * 112 + 16, 168), frame)
    preview.resize((896, 504), Image.Resampling.NEAREST).save(output / "preview.png")
    return {"id": identifier, "source": str(source.relative_to(ROOT)), "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "body_frame_size": [112, 160], "face_frame_size": [80, 80], "anchor": [56, 156], "status": "normalized_pending_engine_review"}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--identities", action="store_true")
    parser.add_argument("--input", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--size", nargs=2, type=int)
    parser.add_argument("--key", choices=["none", "green", "checker"], default="none")
    parser.add_argument("--grid", nargs=2, type=int)
    parser.add_argument("--frame-size", nargs=2, type=int, default=[128, 160])
    args = parser.parse_args()
    if args.identities:
        records = [identity(name, split, key) for name, split, key in [("travel", .64, "checker"), ("life", .645, "checker"), ("business", .61, "checker"), ("food", .71, "green"), ("adventure", .65, "green"), ("magic", .685, "green")]]
        (ART / "identity-manifest.json").write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Normalized {len(records)} identities; originals preserved.")
        return
    if args.input is None or args.output is None:
        parser.error("--input and --output are required")
    image = alpha_image(args.input, args.key)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.grid:
        cols, rows = args.grid
        boxes = [[round(x * image.width / cols), round(y * image.height / rows), round((x + 1) * image.width / cols), round((y + 1) * image.height / rows)] for y in range(rows) for x in range(cols)]
        frames = normalized_strip(image, boxes, tuple(args.frame_size))
        save_atlas(frames, args.output, cols)
    else:
        if args.size:
            image = image.resize(tuple(args.size), Image.Resampling.NEAREST)
        image.save(args.output)
    print(args.output)


if __name__ == "__main__":
    main()
