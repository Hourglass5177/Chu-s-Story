"""Review the existing v8 Godot captures; no assets or poses are changed."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'artifacts/dong-v8-frame-review'
SOURCE = ROOT/'artifacts/dong-anatomy-motion-v8-final'
OUT.mkdir(parents=True, exist_ok=True)
cards = []
for avatar, name in [('travel_blogger','旅行博主'),('business_blogger','商业博主')]:
    for action, label in [('flat','推车'),('brake','下坡制动')]:
        key = f'{avatar}-{action}'
        images = sorted((SOURCE/avatar).glob(f'{action}-*.png'))
        assert len(images) == 48, (key,len(images))
        width,height = Image.open(images[0]).size
        frames = [{'file':f'../../dong-anatomy-motion-v8-final/{avatar}/{p.name}',
                   'time_ms':round(i*1000/30)} for i,p in enumerate(images)]
        folder = OUT/key
        folder.mkdir(exist_ok=True)
        (folder/'report.json').write_text(json.dumps({'frames':frames,'user_accepted':False,
          'provenance':'Existing preview_dong_motion_v8.gd: ordinary input, fixed 120 Hz simulation, sample every fourth tick. Not a new runtime capture.'},ensure_ascii=False,indent=2),encoding='utf-8')
        cards.append(f'''<section data-task="{key}"><h2>{name} · {label}</h2><canvas width="{width}" height="{height}" aria-label="{name}{label}完整画面"></canvas><div class="controls"><button class="play">播放原速画面</button><button class="previous">上一帧</button><button class="next">下一帧</button><input class="seek" type="range" min="0" max="1600" value="0" step="1" aria-label="{name}{label}画面时间"><output>准备画面</output></div></section>''')

style = '''body{margin:24px;background:#201e1b;color:#f5ead2;font:20px/1.5 system-ui,"Microsoft YaHei",sans-serif}main{max-width:1060px;margin:auto}h1{font-size:30px}h2{font-size:24px}section{padding:20px;margin:24px 0;background:#38342c;border-radius:12px}canvas{display:block;width:100%;height:auto}.controls{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin-top:12px}button{font:inherit;min-height:48px;padding:8px 14px;background:#4b5f51;color:#f5ead2;border:1px solid #99b398;border-radius:6px}input{flex:1;min-width:120px}output{min-width:130px}.note{padding:18px;background:#35463f;border-radius:10px}a{color:#b4e5d0}'''
(OUT/'index.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>楚物志 · 董永 v8 待试看</title><style>'''+style+'''</style><main><h1>董永 v8 · 完整姿势待试看</h1><p class="note">沿用此前当前工程采集的旅行、商业博主推车与制动片段。按游戏内原速回放，不补帧、不拉伸手臂。每段 48 帧，共 1.6 秒；这只是动作短循环，不是全程通关录像。<br>v8 尚未获得用户认可；其余四位完整动作与六人全流程仍需继续检查。</p>'''+''.join(cards)+'''<p><a href="../music-motion-v4/index.html">返回六音游动作</a></p></main></html>'''+ '<script>'+(ROOT/'tools/music_motion_player.js').read_text(encoding='utf-8')+'</script>',encoding='utf-8')
print(OUT/'index.html')
