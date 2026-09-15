"""Generate and export the P1 candidate. Wait for GUI-subsystem Aseprite correctly."""
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
EXE=Path('F:/Tools/Aseprite/chuwuzhi-v1.3.18.5/build/bin/aseprite.exe')
for name in ['draw_p1_assets.lua','compose_p1_cover.lua']:
    result=subprocess.run([str(EXE),'--batch','--script-param',f'root={ROOT.as_posix()}',
        '--script',str(ROOT/'tools/aseprite'/name)],check=True,capture_output=True,text=True,encoding='utf-8')
    print(result.stdout.strip())
for name in ['export_p1_assets.py','build_p1_resources.py']:
    subprocess.run([sys.executable,str(ROOT/'tools/aseprite'/name)],check=True,cwd=ROOT)
