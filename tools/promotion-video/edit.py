"""Editable EDL -> real-footage shots, subtitles and a 1080p60 H.264 master."""
from pathlib import Path
import json,subprocess,shutil,sys
R=Path(__file__).resolve().parents[2]; P=R/'artifacts/promotion-2026'; W=Path(__file__).resolve().parent
FF=R/'artifacts/media-20260909/toolchain/ffmpeg-9.0.1-essentials_build/bin/ffmpeg.exe'
OUT=P/'delivery'; OUT.mkdir(exist_ok=True); SH=P/'shots'; SH.mkdir(exist_ok=True)
FONT=Path('tools/promotion-video/fonts/pixel.ttf')
BGM_WINDOW=(45,89)
(R/FONT).parent.mkdir(exist_ok=True)
shutil.copyfile(R/'InheritanceTasks/Art/Pixel/v2/fonts/fusion-pixel-12px-proportional-zh_hans.ttf',R/FONT)
shots=[
 dict(take='board2',start=4.2,duration=7,caption='在武汉，开启一场非遗旅行。',city='武汉'),
 dict(take='home',start=3,duration=7,caption='楚物志',city='湖北非遗文化主题桌游'),
 dict(take='board2',start=2.7,duration=11,caption='选条路，也留一点余力。',city='武汉 · 地图探索'),
 dict(take='food',start=16.8,duration=10,caption='过早，再出发。',city='武汉 · 热干面'),
 dict(take='board2',start=15.0,duration=4,still=True,caption='收进手里的，还可以亲手体验。',city='武汉 · 汉剧'),
 dict(take='board2',start=24.48,duration=6,caption='收进手里的，还可以亲手体验。',city='武汉 · 汉剧'),
 dict(take='board2',start=30.48,duration=44,tv=True,caption='跟着唱段，把追光送到台前。',city='武汉 · 汉剧',music=True),
 dict(take='board2',start=74.48,duration=11,caption='完成传承，把“？”变成5分。',city='武汉 · 汉剧'),
 dict(take='tianmen_tang_su',start=9.0,duration=8,tv=True,caption='从武汉出发，继续走进荆楚。',city='天门 · 天门糖塑'),
 dict(take='ezhou_diaohua_jianzhi',start=13.1,duration=8,tv=True,caption='从武汉出发，继续走进荆楚。',city='鄂州 · 鄂州雕花剪纸'),
 dict(take='board2',start=85.2,duration=8,caption='下一站，怎么选？',city='收藏 · 组合 · 回合'),
 dict(take='board2',start=95.4,duration=5,caption='下一站，怎么选？',city='另一位博主的旅程'),
 dict(take='board2',start=80.8,duration=5,still=True,caption='玩过之后，再看看它的故事。',city='武汉 · 汉剧'),
 dict(take='tutorial',start=8,duration=7,caption='玩过之后，再看看它的故事。',city='入门教学'),
 dict(take='outro',start=0,duration=9,caption='楚物志 · 楚行九州',city=''),
]
def run(args):
 subprocess.run([str(FF),'-hide_banner','-loglevel','error','-y']+list(map(str,args)),check=True,cwd=R)
def fontpath(p): return str(p).replace('\\','/').replace(':','\\:')
def txtfile(i,kind,text):
 p=SH/f'{i:02}-{kind}.txt'; p.write_text(text,encoding='utf8'); return fontpath(p)
def main():
 if '--use-edited-captions' in sys.argv:
  mapping=json.loads((W/'caption-map.json').read_text(encoding='utf8'))
  for s in shots:
   path=P/'字幕文案'/mapping[s['caption']]
   s['caption']=path.read_text(encoding='utf-8-sig').strip()
 t=0
 for i,s in enumerate(shots): s.update(index=i,from_seconds=t); t+=s['duration']
 assert t==150
 (W/'timeline.json').write_text(json.dumps({'fps':60,'width':1920,'height':1080,'duration':150,'shots':shots},ensure_ascii=False,indent=2),encoding='utf8')
 for i,s in enumerate(shots):
  dst=SH/f'{i:02}.mp4'
  if dst.exists(): continue
  print('Rendering shot',i,s['take'],flush=True)
  caption=txtfile(i,'caption',s['caption']); city=txtfile(i,'city',s['city'])
  draw=f"drawtext=fontfile='{fontpath(FONT)}':textfile='{caption}':fontsize=48:fontcolor=white:borderw=3:bordercolor=black:shadowx=1:shadowy=2:shadowcolor=black:x=(w-tw)/2:y=968"
  width=min(500,max(136,len(s['city'])*32+44))
  top=f"drawbox=x=110:y=20:w={width}:h=60:color=0x21160dcc:t=fill,drawtext=fontfile='{fontpath(FONT)}':textfile='{city}':fontsize=32:fontcolor=0xf5d39a:x=132:y=31"
  if s['take']=='outro':
   logo=R/'arts/branding-v2/logo-combined.png'
   title=txtfile(i,'outro','从武汉出发')
   title2=txtfile(i,'outro2','走进荆楚非遗')
   sub=txtfile(i,'sub','湖北非遗文化主题桌游')
   sub2=txtfile(i,'sub2','小红花赛道 · 参赛作品')
   filt=f"[1:v]scale=600:600:flags=lanczos[logo];[0:v][logo]overlay=180:180,drawtext=fontfile='{fontpath(FONT)}':textfile='{title}':fontsize=72:fontcolor=0xf5d39a:x=890:y=260,drawtext=fontfile='{fontpath(FONT)}':textfile='{title2}':fontsize=72:fontcolor=0xf5d39a:x=890:y=380,drawtext=fontfile='{fontpath(FONT)}':textfile='{sub}':fontsize=36:fontcolor=0xf3e4c5:x=900:y=560,drawtext=fontfile='{fontpath(FONT)}':textfile='{sub2}':fontsize=36:fontcolor=0xf3e4c5:x=900:y=650,{draw}[v]"
   args=['-f','lavfi','-i','color=c=0x21170f:s=1920x1080:r=60','-loop','1','-i',logo,'-f','lavfi','-i','anullsrc=r=48000:cl=stereo','-filter_complex',filt,'-map','[v]','-map','2:a']
  else:
   source=P/s['take']/'take.mp4'
   crop='crop=1280:720:320:175,' if s.get('tv') else ''
   vf=crop+'scale=1920:1080:flags=lanczos,'+draw+','+top
   if s.get('still'):
    png=SH/f'{i:02}-still.png'; run(['-ss',s['start'],'-i',source,'-frames:v','1',png])
    args=['-loop','1','-framerate','60','-i',png,'-f','lavfi','-i','anullsrc=r=48000:cl=stereo','-vf',vf,'-map','0:v','-map','1:a']
   else:
    args=['-ss',s['start'],'-i',source,'-vf',vf,'-af','afade=t=in:d=0.015,afade=t=out:st='+str(s['duration']-.015)+':d=0.015']
  run(args+['-t',s['duration'],'-r','60','-fps_mode','cfr','-c:v','h264_nvenc','-preset','p5','-tune','hq','-rc','vbr','-cq','18','-b:v','0','-pix_fmt','yuv420p','-c:a','aac','-b:a','256k','-ar','48000',dst])
 concat=SH/'concat.txt'; concat.write_text(''.join("file '"+str(SH/f'{i:02}.mp4').replace('\\','/')+"'\n" for i in range(len(shots))),encoding='utf8')
 joined=P/'picture-and-production-audio.mp4'
 run(['-f','concat','-safe','0','-i',concat,'-c','copy',joined])
 final=OUT/'楚物志_楚行九州_小红花赛道_宣传视频.mp4'
 # Music remains untouched in pitch/time; it yields completely to the full Hanju take.
 a,b=BGM_WINDOW
 envelope=f"if(lt(t,{a-2}),0.22,if(lt(t,{a}),0.22*({a}-t)/2,if(lt(t,{b}),0,if(lt(t,{b+2}),0.22*(t-{b})/2,if(lt(t,147),0.22,0.22*(150-t)/3)))))"
 run(['-i',joined,'-i',R/'Audio/Music/chuwuzhi-bgm.mp3','-filter_complex',f"[1:a]atrim=0:150,volume='{envelope}':eval=frame[b];[0:a][b]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95:level=false[a]",'-map','0:v','-map','[a]','-t','150','-c:v','copy','-c:a','aac','-b:a','256k','-ar','48000','-movflags','+faststart',final])
 run(['-ss','144','-i',final,'-frames:v','1',OUT/'楚物志_宣传视频封面.png'])
 print(final,flush=True)
if __name__=='__main__': main()
