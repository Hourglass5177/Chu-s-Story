"""Build the pinned, local-only Aseprite editor; never modify global PATH."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.request
import zipfile

VERSION = "1.3.18.5"
DOWNLOADS = {
    "source": (
        f"https://github.com/aseprite/aseprite/releases/download/v{VERSION}/Aseprite-v{VERSION}-Source.zip",
        "04b0a84617efb3107d380c352ebb0af9eb2633ff4c1a8bfcb671d2a437247d5d",
    ),
    "skia": (
        "https://github.com/aseprite/skia/releases/download/m124-08a5439a6b/Skia-Windows-Release-x64.zip",
        "5a371a4b2819bb4eb96e36cd75fa623585e1d5477e253a970302b6f2471b6934",
    ),
}


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def prepare_sources(base: Path) -> None:
    for name, (url, expected) in DOWNLOADS.items():
        archive = base / f"{name}.zip"
        if not archive.exists():
            print(f"Download {name}: {url}", flush=True)
            urllib.request.urlretrieve(url, archive)
        if sha256(archive) != expected:
            raise RuntimeError(f"Archive hash mismatch: {archive}")
        directory = base / name
        sentinel = directory / ("CMakeLists.txt" if name == "source" else "out/Release-x64/skia.lib")
        if sentinel.exists():
            continue
        directory.mkdir(exist_ok=True)
        with zipfile.ZipFile(archive) as bundle:
            for item in bundle.infolist():
                if not (directory / item.filename).resolve().is_relative_to(directory.resolve()):
                    raise RuntimeError(f"Unsafe archive member: {item.filename}")
            bundle.extractall(directory)


def compiler_environment(vsdevcmd: Path) -> dict[str, str]:
    command = f'cmd.exe /d /s /c ""{vsdevcmd}" -arch=x64 -host_arch=x64 >nul && set"'
    result = subprocess.run(command, check=True, capture_output=True, encoding="utf-8", errors="replace")
    environment = os.environ.copy()
    environment.update(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line and not line.startswith("="))
    return environment


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(f"F:/Tools/Aseprite/chuwuzhi-v{VERSION}"))
    parser.add_argument("--vsdevcmd", type=Path, default=Path("C:/Program Files/Microsoft Visual Studio/2022/Community/Common7/Tools/VsDevCmd.bat"))
    parser.add_argument("--cmake", default="C:/Program Files/CMake/bin/cmake.exe")
    parser.add_argument("--ninja", default="F:/Program Files/Microsoft Visual Studio/18/Community/Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja/ninja.exe")
    parser.add_argument("--jobs", type=int, default=8)
    args = parser.parse_args()
    base = args.root.resolve()
    base.mkdir(parents=True, exist_ok=True)
    prepare_sources(base)
    environment = compiler_environment(args.vsdevcmd)
    configure = [args.cmake, "-S", str(base / "source"), "-B", str(base / "build"), "-G", "Ninja",
                 f"-DCMAKE_MAKE_PROGRAM={args.ninja}", "-DCMAKE_BUILD_TYPE=RelWithDebInfo",
                 "-DCMAKE_POLICY_VERSION_MINIMUM=3.5", "-DLAF_BACKEND=skia",
                 f"-DSKIA_DIR={base / 'skia'}", f"-DSKIA_LIBRARY_DIR={base / 'skia/out/Release-x64'}",
                 f"-DSKIA_LIBRARY={base / 'skia/out/Release-x64/skia.lib'}"]
    subprocess.run(configure, env=environment, check=True)
    subprocess.run([args.cmake, "--build", str(base / "build"), "--target", "aseprite", "--parallel", str(args.jobs)], env=environment, check=True)
    executable = base / "build/bin/aseprite.exe"
    version = subprocess.check_output([str(executable), "--version"], text=True).strip()
    record = {"executable": str(executable), "version": version, "sha256": sha256(executable),
              "configure_arguments": configure, "compiler": environment.get("VCToolsInstallDir"),
              "windows_sdk": environment.get("WindowsSdkDir"), "windows_sdk_version": environment.get("WindowsSDKVersion"),
              "redistributable": False}
    (base / "build-record.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(json.dumps(record), flush=True)


if __name__ == "__main__":
    main()
