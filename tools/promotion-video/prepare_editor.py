from pathlib import Path
import json,shutil,os
R=Path(__file__).resolve().parents[2]; W=Path(__file__).resolve().parent
P=W/'remotion/public'; P.mkdir(exist_ok=True)
d=json.loads((W/'timeline.json').read_text(encoding='utf8'))
def copy(src,dst):
 dst.parent.mkdir(exist_ok=True,parents=True)
 if not dst.exists():
  try: os.link(src,dst)
  except OSError: shutil.copy2(src,dst)
for s in d['shots']:
 if s['take']=='outro': continue
 if s.get('still'):
  s['asset']=f"stills-v2/{s['take']}-{s['start']}.png"
  copy(R/f"artifacts/promotion-2026/shots/{s['index']:02}-still.png",P/s['asset'])
 else:
  s['asset']='takes/'+s['take']+'.mp4'
  copy(R/'artifacts/promotion-2026'/s['take']/'take.mp4',P/s['asset'])
copy(R/'arts/branding-v2/logo-combined.png',P/'logo.png')
copy(R/'InheritanceTasks/Art/Pixel/v2/fonts/fusion-pixel-12px-proportional-zh_hans.ttf',P/'pixel.ttf')
copy(R/'Audio/Music/chuwuzhi-bgm.mp3',P/'bgm.mp3')
(W/'remotion/src/timeline.json').write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf8')
