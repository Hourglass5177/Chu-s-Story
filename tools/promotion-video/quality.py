from pathlib import Path
import subprocess,json,hashlib
from PIL import Image,ImageDraw,ImageFont
import numpy as np
R=Path(__file__).resolve().parents[2]; P=R/'artifacts/promotion-2026'; O=P/'delivery'
B=R/'artifacts/media-20260909/toolchain/ffmpeg-9.0.1-essentials_build/bin'
video=O/'楚物志_楚行九州_小红花赛道_宣传视频.mp4'; Q=P/'quality';Q.mkdir(exist_ok=True)
probe=json.loads(subprocess.check_output([str(B/'ffprobe.exe'),'-v','error','-show_streams','-show_format','-of','json',str(video)]))
report={'file':video.name,'sha256':hashlib.sha256(video.read_bytes()).hexdigest(),'probe':probe}
decoded=subprocess.run([str(B/'ffmpeg.exe'),'-v','error','-i',str(video),'-f','null','-'],capture_output=True,text=True)
report['complete_decode_exit']=decoded.returncode;report['decode_errors']=decoded.stderr
audio=subprocess.check_output([str(B/'ffmpeg.exe'),'-v','error','-i',str(video),'-vn','-f','f32le','-ar','48000','-ac','2','-'])
a=np.frombuffer(audio,np.float32); report['audio_peak']=float(np.max(np.abs(a)));report['audio_clipping_samples']=int(np.sum(np.abs(a)>=1))
mono=a.reshape(-1,2).mean(axis=1); rms=np.sqrt(np.mean(mono[:len(mono)//48000*48000].reshape(-1,48000)**2,axis=1));report['rms_per_second']=rms.tolist();report['silent_seconds']=np.where(rms<.0001)[0].tolist()
times=[2,9,20,27,33,37,42,47,58,70,86,91,95,103,111,119,126,132,138,145,149]
sheet=Image.new('RGB',(1600,((len(times)+3)//4)*250),'#20170f'); draw=ImageDraw.Draw(sheet)
font=ImageFont.truetype(str(R/'arts/ui-main-v1/fonts/SourceHanSansSC-Regular.otf'),20)
for i,t in enumerate(times):
 path=Q/f'{t:03}.png'
 subprocess.run([str(B/'ffmpeg.exe'),'-v','error','-y','-ss',str(t),'-i',str(video),'-frames:v','1',str(path)],check=True)
 im=Image.open(path).resize((400,225));x=i%4*400;y=i//4*250;sheet.paste(im,(x,y));draw.text((x+10,y+227),f'{t:03}s',font=font,fill='white')
sheet.save(Q/'contact-sheet.jpg',quality=94)
(Q/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print({k:report[k] for k in ['complete_decode_exit','audio_peak','audio_clipping_samples','silent_seconds']})
print([(s.get('codec_name'),s.get('width'),s.get('height'),s.get('r_frame_rate'),s.get('duration')) for s in probe['streams']])
