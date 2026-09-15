"""Export the revised ART REVIEW and build an identity comparison page.

No task definition or gameplay resource is changed here. Aseprite performs all
production raster exports; Pillow is used only for inspection contact sheets.
"""
from pathlib import Path
import hashlib
import json
import subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
REVIEW = ROOT / 'InheritanceTasks/Art/Pixel/v2/review'
AVATARS = REVIEW / 'avatar-identity-r2'
SCENE = REVIEW / 'workshop-composition-r2'
OUT = ROOT / 'artifacts/pixel-v2/review-r2'
EXE = Path('F:/Tools/Aseprite/chuwuzhi-v1.3.18.5/build/bin/aseprite.exe')
NAMES = [('travel','旅行博主'),('life','生活博主'),('business','商业博主'),
         ('food','美食博主'),('adventure','探险博主'),('magic','魔术博主')]
OUT.mkdir(parents=True, exist_ok=True)

def cli(*args):
    subprocess.run([str(EXE), '--batch', *map(str,args)], check=True)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

items=[]
for ident, name in NAMES:
    source=AVATARS/f'{ident}-redraw.aseprite'
    if not source.exists():
        raise FileNotFoundError(f'Identity redraw is not ready: {ident}')
    png=AVATARS/f'{ident}-redraw.png'
    cli(source,'--data',OUT/f'{ident}-metadata.json','--list-layers','--list-tags','--list-slices',
        '--format','json-array','--sheet',OUT/f'{ident}-reopened.png','--sheet-type','horizontal')
    im=Image.open(png).convert('RGBA')
    again=Image.open(OUT/f'{ident}-reopened.png').convert('RGBA')
    colors={c for c in im.get_flattened_data() if c[3]}
    alpha={c[3] for c in im.get_flattened_data()}
    up=Image.open(AVATARS/f'{ident}-redraw-4x.png').convert('RGBA')
    assert im.tobytes()==again.tobytes(), f'{ident}: editable source/export mismatch'
    assert alpha <= {0,255}, f'{ident}: soft/fringed opaque edge'
    assert len(colors)<=24, f'{ident}: identity study color budget exceeded'
    assert up.tobytes()==im.resize((im.width*4,im.height*4),Image.Resampling.NEAREST).tobytes()
    original=ROOT/'arts/素材合集/sprite及立绘/Sprite/角色'/f'{name}.png'
    items.append({'id':ident,'name':name,'native_size':im.size,'colors':len(colors),
                  'source_sha256':sha(source),'png_sha256':sha(png),
                  'original_reference':str(original.relative_to(ROOT)).replace('\\','/'),
                  'original_sha256':sha(original),'status':'identity review; not accepted gameplay animation'})

cli(SCENE/'workshop-travel-review.aseprite','--scale','2','--save-as',SCENE/'workshop-travel-review-2x.gif')
cli(SCENE/'travel-work-action.aseprite','--sheet-type','horizontal','--sheet',OUT/'travel-work-atlas.png',
    '--data',OUT/'travel-work-metadata.json','--list-layers','--list-tags','--list-slices','--format','json-array')
cli(SCENE/'bellows-action.aseprite','--sheet-type','horizontal','--sheet',OUT/'bellows-atlas.png',
    '--data',OUT/'bellows-metadata.json','--list-layers','--list-tags','--format','json-array')

font_path=ROOT/'InheritanceTasks/Art/Pixel/v2/fonts/fusion-pixel-12px-proportional-zh_hans.ttf'
font=ImageFont.truetype(str(font_path),24)
sheet=Image.new('RGB',(1080,382),'#f1e4d0')
draw=ImageDraw.Draw(sheet)
for n,(ident,name) in enumerate(NAMES):
    im=Image.open(AVATARS/f'{ident}-redraw.png').convert('RGBA')
    up=im.resize((im.width*2,im.height*2),Image.Resampling.NEAREST)
    x=n*180+(180-up.width)//2
    y=326-up.height
    sheet.paste(up,(x,y),up)
    draw.text((n*180+90,347),name,font=font,fill='#443b4b',anchor='mm')
sheet.save(OUT/'six-bloggers-r2.png')

# Black and white contact sheet verifies opaque edges independently of scenery.
edges=Image.new('RGB',(1080,648),'black')
ImageDraw.Draw(edges).rectangle((0,324,1080,648),fill='white')
for n,(ident,_) in enumerate(NAMES):
    im=Image.open(AVATARS/f'{ident}-redraw.png').convert('RGBA')
    im=im.resize((im.width*2,im.height*2),Image.Resampling.NEAREST)
    for base in (0,324):edges.paste(im,(n*180+(180-im.width)//2,base+314-im.height),im)
edges.save(OUT/'six-bloggers-black-white.png')

scene_frames=[Image.open(SCENE/f'workshop-travel-review{k}.png').convert('RGB') for k in range(1,9)]
motion=Image.new('RGB',(1000,1200),'#2a2833')
for n,im in enumerate(scene_frames):motion.paste(im,((n%2)*500,(n//2)*300))
motion.save(OUT/'workshop-eight-frames.png')
report={'status':'review candidate; user acceptance pending','avatars':items,
        'scene':'dedicated medicinal workshop; generated art, illustrative equipment',
        'workshop_background_source':{'path':str((REVIEW/'generated-workshop/workshop-source-r2.png').relative_to(ROOT)),
                                      'sha256':sha(REVIEW/'generated-workshop/workshop-source-r2.png')},
        'checks':['editable source/export equality','binary avatar transparency','24-color avatar budgets',
                  'exact 4x nearest-neighbor previews'],
        'not_claimed':['new art integrated in fifteen games','user art acceptance','all action states complete',
                       'new artwork verified by normal gameplay']}
(OUT/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')

base='/InheritanceTasks/Art/Pixel/v2/review/'
data=json.dumps(items,ensure_ascii=False)
html='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>楚物志 · 人物与炼药作坊新稿</title><style>
:root{color-scheme:dark;--cream:#f3e4cc;--wood:#d6a66b;--bg:#211f29;--panel:#302c37}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--cream);font:18px/1.55 system-ui,"Microsoft YaHei",sans-serif}
main{max-width:1160px;margin:auto;padding:30px 30px 64px}header{display:flex;justify-content:space-between;align-items:center;margin-bottom:24px}
h1{font-size:30px;margin:0}h2{font-size:23px;margin:0 0 14px}p{margin:8px 0 22px;color:#c9bdba}.badge{border:1px solid #78634f;border-radius:20px;padding:5px 14px;color:var(--wood);white-space:nowrap}
section{background:var(--panel);border:1px solid #51454a;border-radius:14px;margin-top:24px;padding:24px}
button{font:inherit;color:inherit;background:#493f45;border:1px solid #786453;border-radius:7px;min-height:46px;padding:8px 18px;cursor:pointer}
button:hover,button:focus-visible{background:#675045;outline:2px solid var(--wood);outline-offset:2px}button[aria-selected=true]{background:#d5aa77;color:#2a2730}
.scene{display:block;width:min(100%,1000px);height:auto;image-rendering:pixelated;margin:auto;border:2px solid #665249;border-radius:2px}
.toolbar{display:flex;gap:10px;flex-wrap:wrap;margin:16px 0 0;align-items:center}.small{font-size:15px;color:#bfb2ae}
.tabs{display:flex;gap:9px;flex-wrap:wrap;margin-bottom:22px}.comparison{display:grid;grid-template-columns:1fr 1fr;gap:24px}
.portrait{height:354px;background:#e7dccb;border:1px solid #7f7168;border-radius:10px;display:grid;place-items:center;position:relative;overflow:hidden}
.portrait span{position:absolute;top:12px;left:16px;color:#554854;font-size:16px}.portrait img{height:304px;max-width:95%;object-fit:contain}.portrait .pixel{image-rendering:pixelated;max-width:none}
a{color:var(--wood)}.links{display:flex;gap:20px;margin-top:16px;flex-wrap:wrap}.foot{margin-top:24px;font-size:16px}
@media(max-width:700px){main{padding:20px 12px}section{padding:14px}.comparison{gap:10px}.portrait{height:310px}.portrait img{height:260px}header{align-items:flex-start;gap:12px}h1{font-size:24px}}
</style><main><header><div><h1>人物与炼药作坊</h1><p>重新对照原立绘，检查表情、发型与同屏比例。</p></div><span class="badge">新版美术样板</span></header>
<section><h2>专用炼药作坊</h2><img id="scene" class="scene" alt="旅行博主在炼药作坊操作风箱" src="'''+base+'''workshop-composition-r2/workshop-travel-review-2x.gif">
<div class="toolbar"><button id="play">查看静帧</button><button id="background">只看场景</button><span class="small">旅行博主 · 工作装；炉体、地面和背景保持静止。</span></div></section>
<section><h2>六位博主 · 原装身份对照</h2><div class="tabs" role="tablist" id="tabs"></div><div class="comparison">
<div class="portrait"><span>原立绘</span><img id="original" alt="原始角色参考"></div><div class="portrait"><span>像素重画</span><img id="redraw" class="pixel" alt="重新绘制的像素角色"></div></div>
<div class="toolbar"><button data-bg="#e7dccb">米色底</button><button data-bg="#17151e">深色底</button><button data-bg="#ffffff">白底</button></div>
<div class="links"><a id="source" href="#">可编辑 Aseprite</a><a id="png" href="#">原生 PNG</a><a href="/artifacts/pixel-v2/review-r2/six-bloggers-r2.png">六人同屏</a></div></section>
<p class="foot">当前是美术审稿：六位原装静态人物、旅行博主工作动作与新作坊。尚未作为十五关正式美术接入。</p></main>
<script>const people='''+data+'''; const base='''+json.dumps(base)+''';let playing=true,background=false;
function select(p){document.querySelector('#original').src='/'+p.original_reference;document.querySelector('#redraw').src=base+'avatar-identity-r2/'+p.id+'-redraw.png';document.querySelector('#source').href=base+'avatar-identity-r2/'+p.id+'-redraw.aseprite';document.querySelector('#png').href=base+'avatar-identity-r2/'+p.id+'-redraw.png';for(const b of document.querySelectorAll('[role=tab]'))b.setAttribute('aria-selected',String(b.dataset.id===p.id));}
for(const p of people){const b=document.createElement('button');b.textContent=p.name;b.dataset.id=p.id;b.setAttribute('role','tab');b.onclick=()=>select(p);document.querySelector('#tabs').append(b)}select(people[0]);
function update(){document.querySelector('#scene').src=base+(background?'generated-workshop/workshop-r2-48-2x.png':'workshop-composition-r2/'+(playing?'workshop-travel-review-2x.gif':'workshop-travel-review-2x1.png'));document.querySelector('#play').textContent=playing?'查看静帧':'播放动作';document.querySelector('#background').textContent=background?'显示人物':'只看场景';}
document.querySelector('#play').onclick=()=>{playing=!playing;background=false;update()};document.querySelector('#background').onclick=()=>{background=!background;update()};
for(const b of document.querySelectorAll('[data-bg]'))b.onclick=()=>{for(const p of document.querySelectorAll('.portrait')){p.style.background=b.dataset.bg;p.querySelector('span').style.color=b.dataset.bg==='#17151e'?'#e7dccb':'#554854'}};
</script></html>'''
(OUT/'index.html').write_text(html,encoding='utf-8')
print(f'R2 art review exported: {OUT}')
