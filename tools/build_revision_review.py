"""Build an honest local review of production captures, separate from playtests."""
from pathlib import Path
import json

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/input-revision'
names={
 'xia_lian_dan_shu':'夏氏炼丹术','laohekou_si_xian':'老河口丝弦','xiabaoping_minjian_gushi':'下堡坪故事',
 'tujia_saye_erhe':'撒叶儿嗬','xingshan_min_ge':'兴山民歌','yandi_shennong_chuanshuo':'炎帝神农',
 'tianmen_tang_su':'天门糖塑','dong_yong_chuanshuo':'董永传说','jingzhou_hua_gu_xi':'荆州花鼓戏',
 'han_ju':'汉剧','ti_qin_xi':'提琴戏','gu_pen_ge':'鼓盆歌','ezhou_diaohua_jianzhi':'雕花剪纸',
 'xisai_shenzhou_hui':'神舟护送','huangmei_xi':'黄梅戏',
}
html='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>楚物志 · 本轮修订实拍</title>
<style>*{box-sizing:border-box}body{margin:0;background:#151d1d;color:#f6ebd2;font:18px/1.6 system-ui,sans-serif}main{max-width:1320px;margin:auto;padding:36px 24px}h1{font-size:32px;margin:0}h2{font-size:24px;margin:32px 0 12px}p{color:#c8cfca}button,select,a.link{font:inherit;background:#f1d595;color:#263a38;border:0;border-radius:8px;padding:10px 16px;cursor:pointer}select{max-width:100%}button[aria-pressed=true]{background:#a9d4c6}nav{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:14px}img,video{display:block;width:100%;background:#101615;border-radius:8px}figure{margin:0}figcaption{color:#c8cfca;font-size:16px;margin-top:8px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:20px}.note{border-left:4px solid #e1ba76;padding:12px 20px;background:#263532}audio{width:100%}a{color:#f1d595}@media(max-width:800px){.grid{grid-template-columns:1fr}main{padding:20px 12px}}</style>
<main><h1>楚物志 · 本轮修订实拍</h1><p>当前工程画面与普通输入片段。试玩仍在 Godot 的小游戏图鉴中进行。</p>
<nav id="states"></nav><figure><img id="hero" src="feedback/grade-excellent.png"><figcaption id="caption"></figcaption></figure>
<h2>十五关准备页</h2><select id="games"></select><p>目标、操作与完成条件分组显示；按键提示跟随实际设备。</p><img id="preparation" src="feedback/prepare-xia_lian_dan_shu.png">
<h2>动作与成品</h2><div class="grid"><figure><video controls muted loop preload="metadata" src="shennong-motion.mp4"></video><figcaption>神农：当前工程普通输入，原速 20 帧/秒采样。</figcaption></figure><figure><img src="paper/food_blogger-result.png"><figcaption>剪纸：四处合法切割、纸屑脱落后的稳定成品。</figcaption></figure></div>
<h2>连续原声与反馈音</h2><p class="note">五关原声不再人为断开。以下声音可直接试听；具体节拍编排和短反馈听感仍待逐句听审，程序通过不代表已完成音乐验收。</p>
<select id="songs"></select><audio id="song" controls preload="none"></audio><p><a href="../rework-chart-preview/index.html">打开逐事件试听时间线</a></p>
<div class="grid"><div>花鼓戏 · 现场短反馈<audio controls preload="none" src="../../InheritanceTasks/Audio/rhythm-v4/sing-recorded.wav"></audio></div><div>提琴戏 · 现场短反馈<audio controls preload="none" src="../../InheritanceTasks/Audio/rhythm-v4/bow-recorded.wav"></audio></div></div>
<p>神农八次完整输入路线通过；兴山含暂停与调窗通过。完整程序日志、性能采样与尚待听审项目见本轮实施记录。</p></main>
<script>const names=NAME_DATA;const states=[['优','feedback/grade-excellent.png','金色星芒；普通输入触发。'],['良','feedback/grade-good.png','青色扩散圈；普通输入晚约120毫秒。'],['失','feedback/grade-miss.png','断圈与漏击原因；原声继续。'],['教学','screens/teaching.png','青绿边框、玩法教学顶条与当前动作。'],['倒数','screens/countdown.png','正式开始前的居中大号倒数。'],['神舟','feedback/boat-approach.png','当前船型、障碍船比例与高速接近画面。']];const q=s=>document.querySelector(s);states.forEach(([name,path,caption],i)=>{const b=document.createElement('button');b.textContent=name;b.onclick=()=>{document.querySelectorAll('#states button').forEach(x=>x.setAttribute('aria-pressed','false'));b.setAttribute('aria-pressed','true');q('#hero').src=path;q('#caption').textContent=caption};q('#states').append(b);if(!i)b.click()});Object.entries(names).forEach(([id,name])=>{const o=document.createElement('option');o.value=id;o.textContent=name;q('#games').append(o)});q('#games').onchange=e=>q('#preparation').src='feedback/prepare-'+e.target.value+'.png';['laohekou_si_xian','tujia_saye_erhe','jingzhou_hua_gu_xi','han_ju','ti_qin_xi'].forEach(id=>{const o=document.createElement('option');o.value=id;o.textContent=names[id];q('#songs').append(o)});q('#songs').onchange=()=>q('#song').src='../../InheritanceTasks/Audio/rhythm-v4/'+q('#songs').value+'-continuous.ogg';q('#songs').onchange();</script></html>'''
(OUT/'index.html').write_text(html.replace('NAME_DATA',json.dumps(names,ensure_ascii=False)),encoding='utf8')
frames=sorted((OUT/'shennong-route').glob('motion-*.png'))
lines=[]
for frame in frames:
    lines.extend(["file '"+frame.as_posix()+"'","duration 0.05"])
if frames:lines.append("file '"+frames[-1].as_posix()+"'")
(OUT/'motion-input.txt').write_text('\n'.join(lines),encoding='utf8')
