"""Register engine-rendered covers; original cover files remain archived in place."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
V3 = ROOT / "InheritanceTasks/Art/Pixel/v3"
IDS = ["travel", "life", "business", "food", "adventure", "magic"]
records = []
for task in ["xisai_shenzhou_hui", "xingshan_min_ge"]:
    path = V3 / "resources" / f"{task}.tres"
    text = path.read_text(encoding="utf8")
    text = re.sub(r'^\[ext_resource[^\n]+id="revision_cover_[^"]+"\]\n*', '', text, flags=re.M)
    text = re.sub(r'^avatar_covers = .*\n', '', text, flags=re.M)
    entries = []
    refs = []
    for avatar in IDS:
        name = avatar + "_blogger"
        image = V3 / "runtime/revision-covers" / f"{task}-{name}.png"
        assert image.is_file(), image
        source = "res://" + image.relative_to(ROOT).as_posix()
        entries.append(f'[ext_resource type="Texture2D" path="{source}" id="revision_cover_{avatar}"]')
        refs.append(f'&"{name}": ExtResource("revision_cover_{avatar}")')
        records.append({"task": task, "avatar": name, "file": source})
    # Godot requires all external declarations before any subresources.
    insertion = text.find('[sub_resource')
    if insertion < 0:
        insertion = text.index('[resource]')
    text = text[:insertion] + '\n'.join(entries) + '\n\n' + text[insertion:]
    text = text.replace('cover = ExtResource("cover")', 'cover = ExtResource("revision_cover_travel")\navatar_covers = {' + ', '.join(refs) + '}', 1)
    # Idempotent registration after a prior run.
    if 'avatar_covers = ' not in text:
        text = text.replace('cover = ExtResource("revision_cover_travel")', 'cover = ExtResource("revision_cover_travel")\navatar_covers = {' + ', '.join(refs) + '}', 1)
    path.write_text(text, encoding="utf8")
(V3 / "runtime/revision-covers/manifest.json").write_text(json.dumps({
    "method": "Production-stage static composition using corrected original character crops and current boat assets.",
    "script": "tools/capture_revision_covers.gd",
    "is_playthrough_evidence": False,
    "records": records,
}, ensure_ascii=False, indent=2), encoding="utf8")
