"""Check an already exported Windows Release; never exports or accesses a mic.

Run with Python 3: verify_release_pixel.py --exe PATH --output DIRECTORY
The game is launched from its own directory with isolated APPDATA and an external
GDScript probe. Every res:// resource therefore comes from the exported PCK.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run_game(exe: Path, output: Path, name: str, extra: list[str]) -> dict:
    console = output / f"{name}-console.log"
    engine_log = output / f"{name}-engine.log"
    env = os.environ.copy()
    env["APPDATA"] = str(output / "isolated-user-data" / name)
    Path(env["APPDATA"]).mkdir(parents=True, exist_ok=True)
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = subprocess.SW_HIDE
    args = [str(exe), "--rendering-driver", "d3d12", "--windowed", "--resolution",
            "1280x720", "--max-fps", "60", "--log-file", str(engine_log), *extra]
    started = time.monotonic()
    with console.open("w", encoding="utf-8") as log:
        process = subprocess.Popen(args, cwd=exe.parent, env=env, stdout=log,
                                   stderr=subprocess.STDOUT, startupinfo=startup,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        print(f"{name}: PID {process.pid}; log {console}", flush=True)
        try:
            code = process.wait(timeout=180)
        except subprocess.TimeoutExpired:
            process.kill()  # Only the exact child created above, never other Godot processes.
            process.wait()
            raise RuntimeError(f"{name} did not close within 180 seconds")
    text = console.read_text(encoding="utf-8", errors="replace")
    if engine_log.exists():
        text += "\n" + engine_log.read_text(encoding="utf-8", errors="replace")
    errors = [line for line in text.splitlines()
              if re.match(r"^(SCRIPT ERROR|ERROR):", line.strip())
              or re.search(r"ObjectDB instances leaked|\d+ RIDs? of type .* leaked", line)]
    record = {"exit_code": code, "seconds": round(time.monotonic() - started, 3),
              "console": str(console), "engine_log": str(engine_log), "errors": errors,
              "d3d12_logged": "D3D12" in text}
    print(f"{name}: exit {code}; {record['seconds']} seconds; {len(errors)} errors", flush=True)
    if code or errors or not record["d3d12_logged"]:
        print(text[-12000:], flush=True)
        raise RuntimeError(f"{name} failed; inspect {console}")
    return record


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    options = parser.parse_args()
    exe = options.exe.resolve(strict=True)
    output = options.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    pck = exe.with_suffix(".pck")
    if not pck.is_file():
        raise RuntimeError(f"Matching exported PCK missing: {pck}")
    native = list(exe.parent.rglob("chuwuzhi_audio.windows.release.x86_64.dll"))
    if len(native) != 1:
        raise RuntimeError("Exactly one packaged Release audio extension is required")
    redistributables = ["msvcp140.dll", "msvcp140_1.dll", "vcruntime140.dll", "vcruntime140_1.dll"]
    for name in redistributables:
        if not (exe.parent / name).is_file():
            raise RuntimeError(f"Packaged Visual C++ runtime missing: {name}")
    summary = {"executable": str(exe), "exe_sha256": sha256(exe), "pck_sha256": sha256(pck),
               "native_release_dll": str(native[0]), "native_sha256": sha256(native[0]),
               "microphone_opened": False}
    summary["startup_and_close"] = run_game(exe, output, "startup", ["--quit-after", "120"])
    probe = Path(__file__).with_suffix(".gd").resolve(strict=True)
    report_path = output / "resource-model-report.json"
    summary["resource_model_and_close"] = run_game(exe, output, "resource-model", [
        "--script", str(probe), "--", f"--report={report_path}",
        f"--capture={output / 'release-presentations.png'}"])
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if report.get("status") != "PASS" or not report.get("model_initialized") or not report.get("model_released"):
        raise RuntimeError("Packed resource/model report did not pass")
    summary["report"] = str(report_path)
    summary["status"] = "PASS"
    (output / "release-check-summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    main()
