"""Normalize authored music art with a shared crop, preserving contact anchors."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image
from build_pixel_assets import ART, alpha_image, save_atlas

TASKS = {"laohekou_si_xian": 6, "tujia_saye_erhe": 8, "jingzhou_hua_gu_xi": 6,
         "han_ju": 6, "ti_qin_xi": 12}
ROW_EDGES = {
    "laohekou_si_xian": [0, 211, 423, 624, 824, 1029, 1254],
    "tujia_saye_erhe": [0, 183, 364, 546, 723, 905, 1086],
    "jingzhou_hua_gu_xi": [0, 220, 439, 649, 847, 1053, 1254],
    "han_ju": [0, 213, 413, 621, 824, 1032, 1254],
    "ti_qin_xi": [0, 150, 299, 447, 589, 737, 887],
}


def fixed_cells(source: Path, columns: int, rows: int, target: Path, row_edges: list[int] | None = None) -> dict:
    image = alpha_image(source, "green")
    # Resize the cell grid once. Never fit individual poses to their own bounds:
    # a wider bow must not move the torso or instrument across the frame.
    cell_width = image.width / columns
    cell_height = image.height / rows
    edges = row_edges or [round(y * cell_height) for y in range(rows + 1)]
    cells = [image.crop((round(x * cell_width), edges[y],
                         round((x + 1) * cell_width), edges[y + 1]))
             for y in range(rows) for x in range(columns)]
    bounds = [cell.getbbox() for cell in cells]
    if any(bound is None for bound in bounds):
        raise ValueError(f"Empty pose in {source}")
    frames = []
    groups = [cells[y * columns:(y + 1) * columns] for y in range(rows)] if row_edges else [cells]
    crops = []
    for group in groups:
        group_bounds = [cell.getbbox() for cell in group]
        union = (min(b[0] for b in group_bounds), min(b[1] for b in group_bounds),
                 max(b[2] for b in group_bounds), max(b[3] for b in group_bounds))
        scale = min(120 / (union[2] - union[0]), 120 / (union[3] - union[1]))
        size = (round((union[2] - union[0]) * scale), round((union[3] - union[1]) * scale))
        crops.append({"box": list(union), "scale": scale})
        for cell in group:
            content = cell.crop(union).resize(size, Image.Resampling.NEAREST)
            frame = Image.new("RGBA", (128, 128))
            frame.alpha_composite(content, ((128 - size[0]) // 2, 124 - size[1]))
            frames.append(frame)
    save_atlas(frames, target, columns)
    return {"source": str(source.relative_to(ART)), "output": str(target.relative_to(ART)),
            "grid": [columns, rows], "frame_size": [128, 128], "source_crops": crops,
            "row_edges": edges, "anchor_policy": "shared crop and scale per identity; bottom center",
            "sha256": hashlib.sha256(target.read_bytes()).hexdigest()}


def main() -> None:
    records = []
    runtime = ART / "runtime"
    runtime.mkdir(parents=True, exist_ok=True)
    for task_id, columns in TASKS.items():
        source = ART / "source" / f"{task_id}-background.png"
        target = runtime / f"{task_id}-background.png"
        Image.open(source).convert("RGB").resize((500, 300), Image.Resampling.NEAREST).save(target)
        records.append(fixed_cells(ART / "source" / f"{task_id}-avatars.png", columns, 6,
                                   runtime / f"{task_id}-avatars.png", ROW_EDGES[task_id]))
    # Authored NPC strips have unequal row gutters. Measured clear green gaps,
    # not a uniform 1/7 split, keep neighboring heads/shoes out of each strip.
    records.append(fixed_cells(ART / "source/music-npcs.png", 6, 7, runtime / "music-npcs.png",
                               [0, 186, 367, 551, 756, 949, 1148, 1355]))
    (ART / "music-normalization.json").write_text(json.dumps(records, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Normalized {len(TASKS)} backgrounds and {len(records)} anchored atlases.")


if __name__ == "__main__":
    main()
