"""Build versioned Godot presentation resources from the editable asset index."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "InheritanceTasks/Art/Pixel/v1"
AVATARS = ["travel", "life", "business", "food", "adventure", "magic"]


def q(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def build(entry: dict) -> None:
    task_id = entry["task_id"]
    target = ART / "resources" / f"{task_id}.tres"
    target.parent.mkdir(parents=True, exist_ok=True)
    lines = ['[gd_resource type="Resource" script_class="HeritageTaskPresentation" format=3]', '',
        '[ext_resource type="Script" path="res://InheritanceTasks/Data/heritage_task_presentation.gd" id="1"]',
        '[ext_resource type="Script" path="res://InheritanceTasks/Data/heritage_avatar_appearance.gd" id="2"]',
        f'[ext_resource type="Texture2D" path={q(entry["background"])} id="bg"]']
    atlas = entry.get("atlas")
    columns = entry.get("columns", 6)
    if atlas:
        lines.append(f'[ext_resource type="Texture2D" path={q(atlas)} id="atlas"]')
    if entry.get("stage_scene"):
        lines.append(f'[ext_resource type="PackedScene" path={q(entry["stage_scene"])} id="stage"]')
    if entry.get("cover"):
        lines.append(f'[ext_resource type="Texture2D" path={q(entry["cover"])} id="cover"]')
    for name in AVATARS:
        path = f"res://InheritanceTasks/Art/Pixel/v1/runtime/identities/{name}/portrait.png"
        lines.append(f'[ext_resource type="Texture2D" path={q(path)} id="portrait_{name}"]')
    for category in ("story_panels", "story_thumbnails", "story_animation"):
        for i, path in enumerate(entry.get(category, [])):
            lines.append(f'[ext_resource type="Texture2D" path={q(path)} id="{category}_{i}"]')
    lines.append("")
    for row, name in enumerate(AVATARS):
        if atlas:
            width, height = entry.get("frame_size", [128, 128])
            for column in range(columns):
                lines.extend([f'[sub_resource type="AtlasTexture" id="{name}_{column}"]', 'atlas = ExtResource("atlas")', f'region = Rect2({column * width}, {row * height}, {width}, {height})', 'filter_clip = true', ''])
            animations = []
            default_actions = {"ready": [0], "prepare": [1], "action": [1, 2, 2, 3], "hold": [2], "release": [3], "miss": [4], "recover": [5]}
            for anim, indices in entry.get("actions", default_actions).items():
                speed = entry.get("animation_speeds", {}).get(anim, 8 if len(indices) > 1 else 1)
                frames = ', '.join('{"duration": 1.0, "texture": SubResource("%s_%s")}' % (name, idx) for idx in indices)
                animations.append('{"frames": [%s], "loop": true, "name": &"%s", "speed": %s.0}' % (frames, anim, speed))
            lines.extend([f'[sub_resource type="SpriteFrames" id="frames_{name}"]', 'animations = [' + ',\n'.join(animations) + ']', ''])
        lines.extend([f'[sub_resource type="Resource" id="avatar_{name}"]', 'script = ExtResource("2")', f'avatar_id = &"{name}_blogger"', f'costume_id = &"{task_id}"', f'portrait = SubResource("{name}_0")' if atlas else f'portrait = ExtResource("portrait_{name}")'])
        if atlas:
            anchors = entry.get("anchors", {"feet": [width / 2, height - 2]})
            anchor_text = ', '.join(f'&{q(k)}: Vector2({v[0]}, {v[1]})' for k, v in anchors.items())
            lines.extend([f'sprite_frames = SubResource("frames_{name}")', 'atlas = ExtResource("atlas")', f'frame_size = Vector2i({width}, {height})', f'anchors = {{{anchor_text}}}'])
        lines.extend(['reference_note = "依原角色制作的像素衍生；传统装束与互动动作是游戏化表现。"', ''])
    properties = entry.get("properties", {})
    props = ', '.join(f'{q(k)}: {q(v) if isinstance(v, str) else json.dumps(v)}' for k, v in properties.items())
    lines.extend(['[resource]', 'script = ExtResource("1")', 'background = ExtResource("bg")', 'cover = ExtResource("cover")' if entry.get("cover") else 'cover = ExtResource("bg")', 'avatar_appearances = {' + ', '.join(f'&"{name}_blogger": SubResource("avatar_{name}")' for name in AVATARS) + '}', f'properties = {{{props}}}', 'source_manifest_path = "res://InheritanceTasks/Art/Pixel/v1/presentation-manifest.json"'])
    for category in ("story_panels", "story_thumbnails", "story_animation"):
        if entry.get(category):
            lines.append(category + ' = Array[Texture2D]([' + ', '.join(f'ExtResource("{category}_{i}")' for i in range(len(entry[category]))) + '])')
    if entry.get("stage_scene"):
        lines.append('stage_scene = ExtResource("stage")')
    target.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    definition = ROOT / 'InheritanceTasks/Definitions' / f'{task_id}.tres'
    text = definition.read_text(encoding='utf-8')
    ext = f'[ext_resource type="Resource" path="res://InheritanceTasks/Art/Pixel/v1/resources/{task_id}.tres" id="pixel_presentation"]'
    if 'id="pixel_presentation"' not in text:
        text = text.replace('[resource]', ext + '\n\n[resource]', 1)
    text = re.sub(r'^presentation = .*\n?', '', text, flags=re.MULTILINE)
    text = re.sub(r'^prototype_asset_note = .*$', 'prototype_asset_note = "独立像素场景、六博主主题装束与动作；当前美术版本见表现资源台账。"', text, flags=re.MULTILINE)
    text = text.rstrip() + '\npresentation = ExtResource("pixel_presentation")\n'
    definition.write_text(text, encoding='utf-8')


if __name__ == '__main__':
    entries = json.loads((ART / 'presentation-manifest.json').read_text(encoding='utf-8'))
    for item in entries:
        build(item)
    print(f'Built {len(entries)} presentation resources.')
