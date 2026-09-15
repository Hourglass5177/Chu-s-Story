"""Run real Aseprite Lua and CLI export checks, without touching game assets."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--executable", type=Path, default=Path("F:/Tools/Aseprite/chuwuzhi-v1.3.18.5/build/bin/aseprite.exe"))
    parser.add_argument("--output", type=Path, default=Path("artifacts/aseprite-toolchain"))
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    script = Path(__file__).with_suffix(".lua").resolve()
    creation = subprocess.run([str(args.executable), "--batch", "--script-param", f"output={output.as_posix()}", "--script", str(script)], check=True, capture_output=True, text=True)
    assert "ASEPRITE_TOOLCHAIN_FIXTURE_OK" in creation.stdout, creation.stdout
    subprocess.run([str(args.executable), "--batch", str(output / "fixture.aseprite"), "--sheet-type", "horizontal", "--sheet", str(output / "fixture.png"), "--data", str(output / "fixture.json"), "--format", "json-array", "--list-layers", "--list-tags", "--list-slices"], check=True)
    data = json.loads((output / "fixture.json").read_text(encoding="utf-8"))
    assert len(data["frames"]) == 2
    assert [frame["duration"] for frame in data["frames"]] == [100,150]
    assert [layer["name"] for layer in data["meta"]["layers"]] == ["body","detail"]
    assert data["meta"]["frameTags"][0]["name"] == "fixture_loop"
    assert data["meta"]["slices"][0]["keys"][0]["pivot"] == {"x":8,"y":14}
    image = Image.open(output / "fixture.png").convert("RGBA")
    assert image.size == (32,16), image.size
    assert {alpha for *_,alpha in image.get_flattened_data()} == {0,255}
    colors = {pixel[:3] for pixel in image.get_flattened_data() if pixel[3]}
    assert colors == {(44,39,47),(209,154,75),(247,230,194)}, colors
    # The only difference between frames is one intended highlight pixel.
    before = image.crop((0,0,16,16))
    after = image.crop((16,0,32,16))
    assert sum(a != b for a,b in zip(before.get_flattened_data(),after.get_flattened_data())) == 1
    hashes = {path.name:hashlib.sha256(path.read_bytes()).hexdigest() for path in output.iterdir() if path.suffix in {".aseprite",".png",".json"} and path.name != "report.json"}
    report = {"status":"passed", "method":"real Aseprite batch Lua, save/reopen, CLI spritesheet export, decoded PNG and JSON inspection", "fixture_only":True, "art_quality_validated":False, "lua_output":creation.stdout.strip(), "checks":["indexed palette preserved", "two editable layers preserved", "two frames and exact durations", "animation tag preserved", "slice and feet pivot preserved", "transparent PNG alpha is binary", "exact three visible colors", "exactly one intended pixel changes across frames"], "files":hashes}
    (output / "report.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
