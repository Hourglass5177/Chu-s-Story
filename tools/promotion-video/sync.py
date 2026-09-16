from pathlib import Path
import subprocess,json,sys,numpy as np
R=Path(__file__).resolve().parents[2]
ff=R/'artifacts/media-20260909/toolchain/ffmpeg-9.0.1-essentials_build/bin/ffmpeg.exe'
p=R/'artifacts/promotion-2026'/sys.argv[1]
d=json.loads((p/'capture.json').read_text(encoding='utf-8'))
# Decode a small corner: full white slate is deliberately absent from gameplay.
raw=subprocess.check_output([str(ff),'-v','error','-i',str(p/'raw.mkv'),'-vf','crop=32:32:1000:500,scale=1:1,format=gray','-fps_mode','passthrough','-f','rawvideo','-'])
x=np.frombuffer(raw,np.uint8); on=np.where(x>248)[0]
groups=np.split(on,np.where(np.diff(on)>2)[0]+1)
groups=[g for g in groups if len(g)>4]
if len(groups)!=2: raise RuntimeError('Expected two white sync markers, got '+str([(g[0],len(g))for g in groups]))
audio=np.fromfile(p/'audio.f32',np.float32).reshape(-1,2)
rate=int(d['mix_rate']); mono=audio.mean(axis=1)
# Detect exact 1kHz pulse using sliding short Fourier correlation.
n=240; chunks=mono[:len(mono)//n*n].reshape(-1,n)
t=np.arange(n)/rate
power=np.abs(chunks@np.exp(-2j*np.pi*1000*t))/n*2
peaks=np.where(power>.12)[0]
pg=np.split(peaks,np.where(np.diff(peaks)>2)[0]+1)
pg=[g for g in pg if len(g)>=6]
if len(pg)!=2: raise RuntimeError('Expected two audio pulses '+str([(g[0],len(g))for g in pg]))
timestamps=json.loads(subprocess.check_output([str(ff.with_name('ffprobe.exe')),'-v','error','-select_streams','v:0','-show_frames','-show_entries','frame=best_effort_timestamp_time','-of','json',str(p/'raw.mkv')]))['frames']
assert len(timestamps)==len(x), 'Decoded frame and timestamp count disagree'
video=np.array([float(timestamps[g[0]]['best_effort_timestamp_time']) for g in groups]); a=np.array([g[0]*n/rate for g in pg])
offset=float(video[0]-a[0]); drift=float((video[1]-video[0])-(a[1]-a[0]))
quality={'video_markers':video.tolist(),'audio_markers':a.tolist(),'audio_delay_seconds':offset,'drift_ms':drift*1000,'audio_peak':float(np.max(np.abs(audio))),'discarded_audio_frames':d['discarded_audio_frames'],'frame_ms_p95':float(np.percentile(d['frame_ms'],95)),'frame_ms_p99':float(np.percentile(d['frame_ms'],99))}
(p/'sync.json').write_text(json.dumps(quality,indent=2),encoding='utf-8')
print(quality,flush=True)
if abs(drift)>.04: raise RuntimeError('Audio drift exceeds 40ms')
subprocess.run([str(ff),'-y','-v','warning','-i',str(p/'raw.mkv'),'-itsoffset',str(offset),'-f','f32le','-ar',str(rate),'-ac','2','-i',str(p/'audio.f32'),'-map','0:v','-map','1:a','-c:v','copy','-c:a','aac','-b:a','256k','-ar','48000','-movflags','+faststart','-shortest',str(p/'take.mp4')],check=True)
