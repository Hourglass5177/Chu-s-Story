"""Preserve generated paper/hand detail without rebuilding any playable contour."""
from pathlib import Path
import hashlib
import json
import re
import sys
from PIL import Image
import numpy as np
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.build_action_story_art_v3 import key_green, components

BASE = ROOT / "InheritanceTasks/Art/Pixel/v3"
OUT = BASE / "runtime/paper"
IDS = ["travel", "life", "business", "food", "adventure", "magic"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build():
    geometry = ROOT / "InheritanceTasks/Data/paper-cut-geometry-v3.json"
    geometry_hash = sha(geometry)
    previous_path = OUT / "detail-anchors.json"
    previous = json.loads(previous_path.read_text(encoding="utf-8")) if previous_path.exists() else {}
    sizes = previous.get("hand_display_sizes", {})
    for name in IDS:
        key = name + "_blogger"
        if key not in sizes:
            sizes[key] = [v * 2 for v in Image.open(OUT / (key + "-hand.png")).size]
    records = []

    def save(image, name, source, note):
        target = OUT / name
        image.save(target)
        records.append({"source": source.relative_to(ROOT).as_posix(), "source_sha256": sha(source),
                        "runtime": target.relative_to(ROOT).as_posix(), "sha256": sha(target),
                        "size": list(image.size), "method": note})

    source = BASE / "source/paper/paper_background.png"
    save(Image.open(source).convert("RGBA").resize((1000, 600), Image.Resampling.LANCZOS),
         "background.png", source, "1000x600 display; original colors retained")
    source = BASE / "source/paper/paper_pattern.png"
    rgb = np.array(Image.open(source).convert("RGB").resize((680, 420), Image.Resampling.NEAREST))
    backing = (rgb[:, :, 0] > 190) & (rgb[:, :, 1] > 170) & (rgb[:, :, 2] > 150)
    rgb[backing] = [68, 54, 47]
    save(Image.fromarray(rgb).convert("RGBA"), "pattern.png", source,
         "Original red tones; technical backing matches wax. Existing three gameplay contours unchanged")
    source = BASE / "source/paper/paper_hands.png"
    clean = key_green(Image.open(source))
    parts = components(clean, 6)
    parts.sort(key=lambda item: (round(item[0][1] / clean.height), item[0][0]))
    for name, part in zip(IDS, parts):
        save(part[1], name + "_blogger-hand.png", source,
             "Original transparent crop with blade tip at crop origin; no quantization or reduction")
    anchors = {"version": 4, "hand_display_sizes": sizes,
               "geometry_sha256": geometry_hash, "note": "Logical blade position and displayed hand size retained"}
    previous_path.write_text(json.dumps(anchors, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    presentation = BASE / "resources/ezhou_diaohua_jianzhi.tres"
    text = presentation.read_text(encoding="utf-8")
    text = re.sub(r'pixel_canvas_size = Vector2i\([^\n]+\)\n?', '', text)
    text = re.sub(r'(\[resource\]\s*script = ExtResource\("script"\))', r'\1\n\npixel_canvas_size = Vector2i(1000, 600)', text)
    text = text.replace('"native_pixel_scale": 2', '"native_pixel_scale": 1')
    text = text.replace('v3/action-art-manifest.json', 'v3/paper-detail-manifest.json')
    presentation.write_text(text, encoding="utf-8")
    assert sha(geometry) == geometry_hash, "Export must never rebuild the playable contours"
    (BASE / "paper-detail-manifest.json").write_text(json.dumps({
        "version": 4, "assets": records, "geometry_sha256_unchanged": geometry_hash,
        "status": "original-detail export; engine and user review recorded separately"
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Paper detail: eight assets, six original hand crops; playable geometry hash unchanged.")


if __name__ == "__main__":
    build()
