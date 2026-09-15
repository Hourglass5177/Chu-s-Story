"""Build a local review index from actual Godot captures and unmodified artist mockups."""
from pathlib import Path
import json
import shutil
import hashlib
import struct

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/ui-main/final-review'
SOURCE = Path(r'E:\大学\MEMO\桌游 · 楚物志\新版素材\现有素材')
REFERENCES = {
    'hud': '03_主界面与开局/主界面（AI）/效果图.png',
    'detail': '04_局内界面/卡牌详情/效果图.png',
    'national': '04_局内界面/卡牌详情/效果图（国家级非遗-未解锁）.png',
    'profession': '04_局内界面/卡牌详情/效果图（职业）.png',
    'achievement': '04_局内界面/卡牌详情/效果图（成就）.png',
    'shop': '04_局内界面/商店背包研究所/食物商店/商店-效果图.png',
    'backpack': '04_局内界面/商店背包研究所/食物背包/背包-效果图.png',
    'market': '04_局内界面/商店背包研究所/非遗研究所/效果图-非遗研究所.png',
    'event': '04_局内界面/事件结算（未完成）/效果图 事件-单选.png',
    'guide': '05-教程与图鉴/指南（原型）/指南-效果图（附带字体规范）.png',
}
PAGES = [
    ('home', '首页', '', '保留原六位博主背景；沿用四入口布局。首页构图尚不是效果图的逐像素复刻。'),
    ('mode', '模式选择', '', '网络与教学保留未开放状态，不改变游戏模式范围。'),
    ('local_count', '人数配置', '', '小尺寸加减键使用方形控件，避免横条花纹被纵向拉伸。'),
    ('player_setup', '玩家职业与起点', '', '两位本地玩家加一位电脑的配置夹具，六城市标签与确认按钮均检查边界。'),
    ('player_setup_bot', '电脑职业与难度', '', '增加难度说明时仍保留底部操作空间；不改变三档 AI 规则。'),
    ('roster', '阵容确认', '', '三席位展示；保留现有卡片与就绪状态体系，只调整字号及共用外框。'),
    ('hud', '地图与 HUD', 'hud', '原始地图与博主立绘保留；交付效果图中的示例地图和人物不替换正式资源。'),
    ('hud_ai', '含电脑的 HUD', 'hud', '速度文字与工具按钮分为两行，保留顶部镜像对齐。'),
    ('hud_crowded', '多张收藏', 'hud', '右侧两列滚动，地区标题改用较深文字色；牌面本身不改色。'),
    ('detail', '非遗详情', 'detail', '左侧完整牌面，右侧标题、描述与效果；长文字可滚动。'),
    ('national_detail', '国家级非遗交接', 'national', '本人持有且未传承，显示问号、精力成本与任务按钮；不启动或改造小游戏。'),
    ('profession', '职业详情', 'profession', '完整原立绘与技能说明，使用次数留在正文框内。'),
    ('profession_draw', '魔术博主择牌', '', '生产择牌面板展示三张事件牌夹具；选牌和余牌排序按钮分组排列。'),
    ('achievement', '成就详情', 'achievement', '原成就牌与描述分栏；保留达成状态。'),
    ('shop', '小吃商店', 'shop', '三张原食物牌；名称、价格、效果和购买按钮按行对齐。'),
    ('backpack', '食物背包', 'backpack', '三列卡片、纵向滚动，统一底部按钮位置。'),
    ('market', '非遗研究所', 'market', '左侧当前选中牌预览，右侧交易库存；夹具含两张可交易牌。'),
    ('event_choice', '事件选择', 'event', '通过生产 EventOverlay 展示两选项夹具，用于检查排版；不是一次真实事件事务完成记录。'),
    ('score', '计分详情', '', '沿用现有计分解释，补共用外框与入口；不新增低优先级专用美术。'),
    ('pause', '局内暂停', '', '保留既有暂停所有权与继续流程，统一阅读字号和按钮反馈。'),
    ('result', '双人结算', '', '结果数据为审查夹具，关闭自动演出后检查静态排版。'),
    ('result_six', '六人结算', '', '六席位同时可见；并列与淘汰逻辑另由现有回归验证。'),
    ('guide', '指南首页', 'guide', '采用章节底板与正文底板，正文使用可读字体，更新实际 HUD 配图。'),
    ('guide_topic', '指南正文', 'guide', '检查段落、章节与滚动区域，保留原规则目录。'),
    ('compendium', '主体探索图鉴', 'guide', '只调整非小游戏图鉴；小游戏图鉴恢复原主题和壳层。'),
]

PAGES[9:9] = [
    (f'hud-portrait-{index}-phase-{index % 5}', f'完整立绘 · {name}', 'hud',
     '姓名与职业框压矮下移，完整原立绘等比显示；同时检查对应阶段的高亮与顶部排版。')
    for index, name in enumerate(['美食', '魔术', '探险', '商业', '旅行', '生活'])
]

OUT.mkdir(parents=True, exist_ok=True)
(OUT / 'references').mkdir(exist_ok=True)
for key, relative in REFERENCES.items():
    shutil.copy2(SOURCE / relative, OUT / 'references' / f'{key}.png')
data = []
for key, title, ref, note in PAGES:
    sizes = [size for size in ['1280x720', '1920x1080', '2560x1600'] if (OUT / f'{key}-{size}.png').exists()]
    data.append(dict(key=key, title=title, ref=ref, note=note, sizes=sizes))
html = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>楚物志 · 主体 UI 修订审查</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#202124;color:#f4eee5;font:16px/1.65 system-ui,"Microsoft Yahei",sans-serif}
header{padding:22px 30px 15px;border-bottom:1px solid #53504b}h1{margin:0;font-size:26px}p{margin:8px 0;color:#c9c4bc}
main{display:grid;grid-template-columns:225px minmax(0,1fr);min-height:80vh}nav{padding:15px;max-height:85vh;overflow:auto}
button,select{font:inherit;color:inherit;background:#343638;border:1px solid #65605a;border-radius:7px;padding:8px 12px}
nav button{display:block;width:100%;text-align:left;margin-bottom:6px}button[aria-current=true]{background:#75572f;border-color:#e5b775}
button:focus-visible,select:focus-visible,a:focus-visible{outline:3px solid #65c9d6;outline-offset:2px}button{cursor:pointer}
article{padding:18px 24px;border-left:1px solid #53504b;min-width:0}.toolbar{display:flex;gap:18px;align-items:center;flex-wrap:wrap}
h2{font-size:22px;margin:10px 0}.images{display:grid;gap:16px}.images.compare{grid-template-columns:1fr 1fr}
figure{margin:0;min-width:0}figure img{display:block;width:100%;max-height:76vh;object-fit:contain;background:#141517}figcaption{margin:6px 0;color:#d0c8bb}
a{color:#f2c17d}label{cursor:pointer}.hint{font-size:14px}#refFigure[hidden]{display:none}
@media(max-width:850px){main{grid-template-columns:1fr}nav{display:flex;overflow:auto;max-height:130px;flex-wrap:wrap}nav button{width:auto}article{border:0}.images.compare{grid-template-columns:1fr}}
</style><header><h1>《楚物志》主体 UI 修订审查</h1>
<p>2026-09-15 · 当前 Godot 工程实际渲染 · __COUNT__ 种页面/状态 × 3 种窗口尺寸</p>
<p class="hint">这里用于检查排版和对照原稿，不代表体验已经验收。16:9 窗口继续采用 16:10 画面等比适配，截图不含两侧留边。测试夹具说明随页面显示。</p></header>
<main><nav id="nav" aria-label="审查页面"></nav><article><div class="toolbar">
<label>窗口尺寸 <select id="size"><option>1280x720</option><option>1920x1080</option><option>2560x1600</option></select></label>
<label><input type="checkbox" id="compare"> 并排查看美术效果图</label><a id="full" target="_blank">打开原尺寸截图</a>
</div><h2 id="title"></h2><p id="note"></p><div class="images" id="images">
<figure><figcaption>当前工程</figcaption><img id="runtime" alt=""></figure>
<figure id="refFigure" hidden><figcaption>美术交付效果图（未修改）</figcaption><img id="reference" alt=""></figure>
</div><p class="hint" id="refNote"></p></article></main><script>
const pages=__DATA__;let current=pages[0];
const $=id=>document.getElementById(id);
for(const p of pages){const b=document.createElement('button');b.textContent=p.title;b.dataset.key=p.key;b.onclick=()=>{current=p;render()};$('nav').append(b)}
function render(){const path=current.key+'-'+$('size').value+'.png';$('runtime').src=path;$('runtime').alt=current.title+'当前工程截图';$('full').href=path;
$('title').textContent=current.title;$('note').textContent=current.note;const compare=$('compare').checked&&!!current.ref;
$('refFigure').hidden=!compare;$('images').classList.toggle('compare',compare);if(compare){$('reference').src='references/'+current.ref+'.png';$('reference').alt=current.title+'交付参考';}
$('refNote').textContent=current.ref?'效果图仅作构图与风格参照；文字、资源数值及玩法以当前工程为准。':'本页沿用共用组件；本轮未制作未完成的低优先级专用美术。';
for(const b of $('nav').children)b.setAttribute('aria-current',b.dataset.key===current.key)}
$('size').onchange=render;$('compare').onchange=render;render();
</script></html>'''.replace('__DATA__', json.dumps(data, ensure_ascii=False)).replace('__COUNT__', str(len(data)))
(OUT / 'index.html').write_text(html, encoding='utf-8')
(OUT / 'pages.json').write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
captures = []
for page in data:
    for size in page['sizes']:
        content = (OUT / f'{page["key"]}-{size}.png').read_bytes()
        captures.append(dict(page=page['key'], window=size,
                             image=list(struct.unpack('>II', content[16:24])),
                             sha256=hashlib.sha256(content).hexdigest()))
(OUT / 'capture-manifest.json').write_text(json.dumps(captures, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'Review index: {len(data)} states, {sum(len(p["sizes"]) for p in data)} captures')
