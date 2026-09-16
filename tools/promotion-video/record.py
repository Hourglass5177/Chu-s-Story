"""Isolated gdigrab + Master AudioEffectCapture recording. Never records a microphone."""
from pathlib import Path
import subprocess, time, sys, json, ctypes
from ctypes import wintypes
ROOT=Path(__file__).resolve().parents[2]
GODOT=Path(r'F:\godot 4.7.2\Godot_v4.7.2-stable_win64.exe')
FF=ROOT/'artifacts/media-20260909/toolchain/ffmpeg-9.0.1-essentials_build/bin/ffmpeg.exe'
mode=sys.argv[1] if len(sys.argv)>1 else 'trial'
out=ROOT/'artifacts/promotion-2026'/mode
out.mkdir(parents=True,exist_ok=True)
for name in ['ready.json','go','done.json']:
    (out/name).unlink(missing_ok=True)
if (out/'raw.mkv').exists():
    raise SystemExit('Existing footage preserved; choose/archive take before recording again.')
log=open(out/'launch.log','w',encoding='utf-8')
game=subprocess.Popen([str(GODOT),'--path',str(ROOT),'--log-file',str(out/'godot.log'),'tools/promotion-video/capture.tscn','--','--take='+mode],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
print('Game PID',game.pid,flush=True)
t=time.monotonic()
while not (out/'ready.json').exists():
    if game.poll() is not None or time.monotonic()-t>100:
        game.terminate(); raise SystemExit((out/'godot.log').read_text(encoding='utf-8')[-5000:])
    time.sleep(.3)
flog=open(out/'ffmpeg.log','w',encoding='utf-8')
ctypes.windll.user32.SetProcessDPIAware()
u=ctypes.windll.user32
u.SetWindowPos.argtypes=[wintypes.HWND,wintypes.HWND,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_uint]
u.GetClientRect.argtypes=[wintypes.HWND,ctypes.POINTER(wintypes.RECT)]
u.ClientToScreen.argtypes=[wintypes.HWND,ctypes.POINTER(wintypes.POINT)]
u.WindowFromPoint.argtypes=[wintypes.POINT]; u.WindowFromPoint.restype=wintypes.HWND
u.GetAncestor.argtypes=[wintypes.HWND,ctypes.c_uint]; u.GetAncestor.restype=wintypes.HWND
handles=[]
@ctypes.WINFUNCTYPE(wintypes.BOOL,wintypes.HWND,wintypes.LPARAM)
def enum(h,p):
    pid=wintypes.DWORD(); u.GetWindowThreadProcessId(h,ctypes.byref(pid))
    if pid.value==game.pid and u.IsWindowVisible(h): handles.append(h)
    return True
u.EnumWindows(enum,0)
if not handles: game.terminate(); raise RuntimeError('Capture window missing for game PID')
hwnd=handles[0]
ctypes.windll.user32.SetWindowPos(hwnd,-1,20,20,1920,1080,0x0040)
ctypes.windll.user32.SetForegroundWindow(hwnd)
time.sleep(.4)
rect=wintypes.RECT(); ctypes.windll.user32.GetClientRect(hwnd,ctypes.byref(rect))
point=wintypes.POINT(0,0); ctypes.windll.user32.ClientToScreen(hwnd,ctypes.byref(point))
print('Window pixels',rect.right,rect.bottom,'at',point.x,point.y,flush=True)
if (rect.right,rect.bottom)!=(1920,1080): game.terminate(); raise RuntimeError('Incorrect capture size')
rec=subprocess.Popen([str(FF),'-y','-f','gdigrab','-framerate','60','-draw_mouse','0','-offset_x',str(point.x),'-offset_y',str(point.y),'-video_size','1920x1080','-i','desktop','-c:v','libx264','-preset','ultrafast','-crf','18','-pix_fmt','yuv420p',str(out/'raw.mkv')],stdin=subprocess.PIPE,stdout=flog,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
time.sleep(1.5)
if rec.poll() is not None: game.terminate(); raise SystemExit((out/'ffmpeg.log').read_text())
(out/'go').write_text('recording',encoding='utf-8')
print('Recording',mode,flush=True)
t=time.monotonic()
try:
    while not (out/'done.json').exists():
        if game.poll() is not None: raise RuntimeError('Game exited: '+(out/'godot.log').read_text(encoding='utf-8')[-5000:])
        if time.monotonic()-t>240: raise RuntimeError('Capture timeout: '+(out/'godot.log').read_text(encoding='utf-8')[-5000:])
        for x,y in [(100,100),(1800,100),(960,540),(100,980),(1800,980)]:
            visible=u.GetAncestor(u.WindowFromPoint(wintypes.POINT(point.x+x,point.y+y)),2)
            if visible!=hwnd:
                (out/'occlusion.json').write_text(json.dumps({'at':time.monotonic()-t,'point':[x,y]}))
                raise RuntimeError('Another window covered capture; take rejected, other project untouched.')
        time.sleep(.3)
finally:
    rec.communicate(b'q',timeout=30)
    if not (out/'done.json').exists(): game.terminate()
game.wait(timeout=15)
print('Done',mode,flush=True)
