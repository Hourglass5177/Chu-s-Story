"""Export authored .aseprite files with the real CLI; inspect, never repaint them."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import struct
import subprocess

from PIL import Image, ImageDraw

IDENTITIES = ("travel", "life", "business", "food", "adventure", "magic")


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def source_header(path: Path) -> tuple[int, int, int, int]:
    with path.open("rb") as stream:
        _, magic, frames, width, height, depth = struct.unpack("<I5H", stream.read(14))
    if magic != 0xA5E0:
        raise ValueError(f"Not an Aseprite source: {path}")
    return frames, width, height, depth


def frame_image(sheet: Image.Image, frame: dict) -> Image.Image:
    rect = frame["frame"]
    return sheet.crop((rect["x"], rect["y"], rect["x"]+rect["w"], rect["y"]+rect["h"]))


def pixels_changed(a: Image.Image, b: Image.Image) -> dict:
    pairs = list(zip(a.get_flattened_data(), b.get_flattened_data()))
    changed = sum(left != right for left,right in pairs)
    union = sum(left[3] != 0 or right[3] != 0 for left,right in pairs)
    return {"changed_pixels":changed, "visible_union_pixels":union,
            "changed_visible_fraction":round(changed/max(1,union),5)}


def export_one(source: Path, source_root: Path, runtime: Path, executable: Path,
               palette: set[tuple[int,int,int]]) -> dict:
    relative = source.relative_to(source_root)
    output = runtime / relative.with_suffix("")
    output.parent.mkdir(parents=True,exist_ok=True)
    source_hash = sha256(source)
    count,width,height,depth = source_header(source)
    command = [str(executable), "--batch", str(source), "--sheet-type", "horizontal",
               "--sheet", str(output.with_suffix(".png")), "--data", str(output.with_suffix(".json")),
               "--format", "json-array", "--list-tags", "--list-layers", "--list-slices"]
    result = subprocess.run(command,check=True,capture_output=True,text=True,encoding="utf-8",errors="replace")
    if sha256(source) != source_hash:
        raise RuntimeError(f"Source changed during export; rerun: {relative}")
    data = json.loads(output.with_suffix(".json").read_text(encoding="utf-8"))
    sheet = Image.open(output.with_suffix(".png")).convert("RGBA")
    character = source.stem in IDENTITIES
    expected_count = 14 if character else {"bellows":8,"fire":6}.get(source.stem,1)
    errors = []
    if count != expected_count: errors.append(f"expected {expected_count} source frames, found {count}")
    if depth != 8: errors.append(f"source must use indexed color, found {depth}-bit mode")
    if len(data["frames"]) != count: errors.append("CLI metadata frame count differs from source")
    if sheet.size != (width*count,height): errors.append(f"sheet size {sheet.size} differs from native horizontal layout")
    frames = [frame_image(sheet,frame) for frame in data["frames"]]
    for index,frame in enumerate(data["frames"]):
        if frame.get("sourceSize") != {"w":width,"h":height} or frames[index].size != (width,height):
            errors.append(f"frame {index+1} lost its fixed native frame size")
        if frame.get("trimmed") or frame.get("rotated"):
            errors.append(f"frame {index+1} was trimmed or rotated")
    pixels = list(sheet.get_flattened_data())
    colors = {pixel[:3] for pixel in pixels if pixel[3]}
    invalid = colors-palette
    if invalid: errors.append(f"{len(invalid)} colors outside palette.json")
    semi_alpha = sum(0<pixel[3]<255 for pixel in pixels)
    if semi_alpha: errors.append(f"{semi_alpha} pixels have non-binary alpha")
    # Budgets are project checks, not claims that these counts guarantee quality.
    budget = 16 if character or relative.parts[0] == "ui" else (48 if source.stem.startswith(("background", "cover")) else 12)
    warnings = []
    if len(colors)>budget: warnings.append(f"color budget exceeded: {len(colors)} > {budget}")
    per_frame = [len({p[:3] for p in frame.get_flattened_data() if p[3]}) for frame in frames]
    actions = {}
    for tag in data["meta"].get("frameTags",[]):
        start,end = tag["from"],tag["to"]
        pairs = [(i,i+1) for i in range(start,end)]
        if tag["name"] in {"run","pump","fire"} and end>start: pairs.append((end,start))
        transitions = [{"from_frame":a+1,"to_frame":b+1,**pixels_changed(frames[a],frames[b])} for a,b in pairs]
        actions[tag["name"]] = transitions
        for delta in transitions:
            if delta["changed_pixels"] == 0:
                warnings.append(f"{tag['name']} frames {delta['from_frame']}->{delta['to_frame']} are identical; review whether intended")
    return {"source":relative.as_posix(),"runtime_png":output.with_suffix(".png").relative_to(runtime).as_posix(),
            "source_sha256":source_hash,"png_sha256":sha256(output.with_suffix(".png")),
            "json_sha256":sha256(output.with_suffix(".json")),"frame_count":count,"native_frame_size":[width,height],
            "layers":[layer["name"] for layer in data["meta"].get("layers",[])],
            "slices":data["meta"].get("slices",[]),"visible_colors_union":len(colors),
            "visible_colors_per_frame":per_frame,"color_budget":budget,"outside_palette_rgb":[list(c) for c in sorted(invalid)],
            "semi_alpha_pixels":semi_alpha,"action_deltas":actions,"errors":errors,"warnings":warnings,
            "cli_output":(result.stdout+result.stderr).strip()}


def previews(runtime: Path, output: Path) -> None:
    # Pillow is only used to arrange exact exported pixels for inspection.
    background = (244,223,173)
    ink = (42,38,51)
    for category,scale in (("alchemy",3),("shennong",8)):
        sources = []
        for name in IDENTITIES:
            data = json.loads((runtime/category/f"{name}.json").read_text(encoding="utf-8"))
            sheet = Image.open(runtime/category/f"{name}.png").convert("RGBA")
            sources.append((name,frame_image(sheet,data["frames"][0])))
        width,height = sources[0][1].size
        cell_width = width*scale+16
        canvas = Image.new("RGB",(cell_width*6,height*scale+52),background)
        draw = ImageDraw.Draw(canvas)
        for column,(name,frame) in enumerate(sources):
            draw.text((column*cell_width+8,12),name,fill=ink)
            enlarged = frame.resize((width*scale,height*scale),Image.Resampling.NEAREST)
            canvas.paste(enlarged,(column*cell_width+8,36),enlarged)
        canvas.save(output/f"{category}-six-avatars.png")
    scale = 5
    sample = json.loads((runtime/"shennong/travel.json").read_text(encoding="utf-8"))
    width = sample["frames"][0]["sourceSize"]["w"]
    height = sample["frames"][0]["sourceSize"]["h"]
    cell_width,cell_height = width*scale+20,height*scale+28
    canvas = Image.new("RGB",(8*cell_width+90,6*cell_height+30),background)
    draw = ImageDraw.Draw(canvas)
    for row,name in enumerate(IDENTITIES):
        data = json.loads((runtime/"shennong"/f"{name}.json").read_text(encoding="utf-8"))
        sheet = Image.open(runtime/"shennong"/f"{name}.png").convert("RGBA")
        draw.text((8,row*cell_height+55),name,fill=ink)
        for column in range(8):
            frame = frame_image(sheet,data["frames"][column]).resize((width*scale,height*scale),Image.Resampling.NEAREST)
            point = (90+column*cell_width,row*cell_height+36)
            canvas.paste(frame,point,frame)
            draw.text((point[0],point[1]-18),str(column+1),fill=ink)
    canvas.save(output/"shennong-run-eight-frames.png")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--art-root",type=Path,default=Path("InheritanceTasks/Art/Pixel/v2"))
    parser.add_argument("--output",type=Path,default=Path("artifacts/pixel-v2"))
    parser.add_argument("--executable",type=Path,default=Path("F:/Tools/Aseprite/chuwuzhi-v1.3.18.5/build/bin/aseprite.exe"))
    args = parser.parse_args()
    art = args.art_root.resolve(); output=args.output.resolve();output.mkdir(parents=True,exist_ok=True)
    palette_data = json.loads((art/"palette.json").read_text(encoding="utf-8"))
    palette = {tuple(int(value[i:i+2],16) for i in (0,2,4)) for value in palette_data["colors"].values()}
    sources = sorted((art/"source").rglob("*.aseprite"))
    with ThreadPoolExecutor(max_workers=3) as workers:
        records = list(workers.map(lambda path:export_one(path,art/"source",art/"runtime",args.executable,palette),sources))
    errors = [{"source":item["source"],"errors":item["errors"]} for item in records if item["errors"]]
    warnings = [{"source":item["source"],"warnings":item["warnings"]} for item in records if item["warnings"]]
    report = {"status":"failed" if errors else "exported_with_art_review_warnings" if warnings else "passed",
              "source_count":len(records),"palette_name":palette_data["name"],"master_color_count":len(palette),
              "method":"real Aseprite CLI exports; decoded native PNG and metadata checks; Pillow only arranges inspection sheets",
              "art_quality_validated":False,"errors":errors,"warnings":warnings,"assets":records}
    (output/"asset-validation.json").write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding="utf-8")
    (output/"action-deltas.json").write_text(json.dumps({item["source"]:item["action_deltas"] for item in records if item["action_deltas"]},indent=2),encoding="utf-8")
    (output/"color-counts.json").write_text(json.dumps([{key:item[key] for key in ("source","visible_colors_union","visible_colors_per_frame","color_budget","semi_alpha_pixels")} for item in records],indent=2),encoding="utf-8")
    if not errors: previews(art/"runtime",output)
    print(json.dumps({"status":report["status"],"sources":len(records),"errors":errors,"warnings":warnings},ensure_ascii=True))
    raise SystemExit(1 if errors else 0)


if __name__ == "__main__":
    main()
