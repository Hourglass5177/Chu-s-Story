"""Compose recognizable covers solely from existing, reviewed runtime layers.

No new artwork is generated and no gameplay or Godot import is performed.
The delivery builder prefers runtime/cover-source/<task-id>.png.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "InheritanceTasks/Art/Pixel/v1"
SOURCE = ART / "runtime/cover-source"
COVERS = ART / "runtime/covers"


def local(path: str) -> Path:
    return ROOT / path.removeprefix("res://")


def layer(image: Image.Image, atlas_path: Path, column: int, row: int,
          frame_size: tuple[int, int], position: tuple[int, int], size: int) -> dict:
    atlas = Image.open(atlas_path).convert("RGBA")
    width, height = frame_size
    frame = atlas.crop((column * width, row * height, (column + 1) * width, (row + 1) * height))
    frame = frame.resize((size, size), Image.Resampling.NEAREST)
    image.alpha_composite(frame, position)
    return {"source": atlas_path.relative_to(ROOT).as_posix(), "column": column, "row": row,
            "frame_size": list(frame_size), "rect": [*position, size, size]}


def build() -> None:
    SOURCE.mkdir(parents=True, exist_ok=True)
    COVERS.mkdir(parents=True, exist_ok=True)
    entries = {item["task_id"]: item for item in json.loads((ART / "presentation-manifest.json").read_text(encoding="utf-8"))}
    anchors = json.loads((ART / "runtime/craft/anchors.json").read_text(encoding="utf-8"))
    records = []
    for task_id in ["huangmei_xi", "tianmen_tang_su", "han_ju", "ti_qin_xi"]:
        entry = entries[task_id]
        background = local(entry["background"])
        image = Image.open(background).convert("RGBA").resize((500, 300), Image.Resampling.NEAREST)
        atlas = local(entry["atlas"])
        layers = []
        if task_id == "huangmei_xi":
            # An actual singing key pose from the existing actress costume atlas.
            layers.append(layer(image, atlas, 2, 0, (128, 128), (134, 14), 232))
            reason = "Open-stage background plus complete singing pose; the old opening capture showed an empty stage."
        elif task_id == "tianmen_tang_su":
            position, size = (20, 52), 232
            layers.append(layer(image, atlas, 2, 0, (128, 128), position, size))
            # Align the authored bubble neck with the measured tube tip. Do not
            # redraw a tube, a membrane, a hand, or change the gameplay radius.
            tip = anchors["tube_tip"]["travel_blogger"][2]
            tip_position = (position[0] + tip[0] * size / 128, position[1] + tip[1] * size / 128)
            bubble_position = (round(tip_position[0] - 8), round(tip_position[1] - 92))
            bubbles = ART / "runtime/craft/tianmen_tang_su-bubbles.png"
            layers.append(layer(image, bubbles, 2, 0, (160, 160), bubble_position, 160))
            reason = "Inflated amber membrane visibly meets the existing blowing tube; cover composition only, no radius rule change."
        elif task_id == "han_ju":
            # The right-facing device exposes its barrel. The left-facing pose
            # in the opening capture puts much of the lamp behind the hairstyle.
            layers.append(layer(image, ART / "runtime/music-npcs.png", 4, 5, (128, 128), (286, 79), 132))
            layers.append(layer(image, atlas, 2, 0, (128, 128), (10, 158), 142))
            reason = "Right-facing lamp barrel and tripod fully visible, pointing toward an actor on the right stage."
        else:
            layers.append(layer(image, ART / "runtime/music-npcs.png", 2, 6, (128, 128), (65, 16), 89))
            layers.append(layer(image, atlas, 7, 0, (128, 128), (156, 54), 243))
            reason = "The right long-bow pose makes the full bow, gripping hands, upright neck and cylinder at waist legible."
        source_path = SOURCE / f"{task_id}.png"
        cover_path = COVERS / f"{task_id}.png"
        image.convert("RGB").save(source_path)
        image.convert("RGB").save(cover_path)
        records.append({"task_id": task_id, "reviewed_source": source_path.relative_to(ROOT).as_posix(),
                        "cover": cover_path.relative_to(ROOT).as_posix(), "background": background.relative_to(ROOT).as_posix(),
                        "layers": layers, "reason": reason, "sha256": hashlib.sha256(source_path.read_bytes()).hexdigest()})
    report = {"date": "2026-09-13", "method": "existing runtime layer composition; not an engine capture or gameplay proof",
              "size": [500, 300], "new_art_generated": False, "covers": records,
              "retained_music_covers": {
                  "laohekou_si_xian": "Three musicians, full long-neck sanxian, resonator and hands already visible.",
                  "tujia_saye_erhe": "Leader/player feet, same-facing formation and drum already visible without clipping.",
                  "jingzhou_hua_gu_xi": "Lead actress on flower-wall stage and participant are both complete and visually distinct."}}
    (ART / "reviewed-performance-covers.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Composed {len(records)} reviewed covers from existing layers; no new artwork or engine run.")


if __name__ == "__main__":
    build()
