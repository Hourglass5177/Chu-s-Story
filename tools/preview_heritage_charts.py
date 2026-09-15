"""Build a local, dependency-free audio and candidate-chart listening page."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/rework-chart-preview/index.html'

def main():
    charts=[]
    for path in sorted((ROOT/'InheritanceTasks/Charts').glob('*.json')):
        chart=json.loads(path.read_text(encoding='utf-8'))
        chart['task']=path.stem
        chart['url']='../../'+chart['audio_path'].removeprefix('res://')
        charts.append(chart)
    payload=json.dumps(charts,ensure_ascii=False).replace('</','<\\/')
    html='''<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>楚物志 · 谱面听审</title>
<style>body{background:#eee5cf;color:#263e43;font:17px system-ui;margin:30px auto;max-width:1150px;padding:0 24px}h1{font-size:28px}button,select{font:inherit;padding:8px 12px;border:1px solid #738c80;border-radius:6px;background:#fff9e9;color:inherit;margin:5px}audio{width:100%;margin:20px 0}svg{width:100%;background:#253e43;border-radius:10px}table{width:100%;border-collapse:collapse;font-size:14px}td,th{padding:8px;text-align:left;border-bottom:1px solid #c9b991}tr.active{background:#e1ba6c}code{font-size:12px}small{color:#5b6962}.note{border-left:4px solid #ae5745;padding:12px;background:#fff8e7}</style>
<h1>楚物志 · 谱面听审</h1><p class="note">候选编排，尚未逐句听审。原声保持完整；长音、休止、帮腔与弓向不能据此认定为真实演出标注。</p>
<select id="choice"></select><button id="previous">上一事件</button><button id="next">下一事件</button><audio id="audio" controls preload="metadata"></audio>
<svg id="timeline" viewBox="0 0 1100 150"></svg><p id="info"></p><table><thead><tr><th>稳定编号</th><th>起点</th><th>动作</th><th>方向</th><th>收尾</th><th>预备</th><th>听片段</th></tr></thead><tbody id="rows"></tbody></table>
<script>const charts=PAYLOAD;const q=s=>document.querySelector(s);let chart=null,selected=0,stopAt=Infinity;const names={han_ju:'汉剧 · 双台接句',jingzhou_hua_gu_xi:'荆州花鼓戏 · 你来接这一声',laohekou_si_xian:'老河口丝弦 · 合奏接力',ti_qin_xi:'提琴戏 · 起弓收弓',tujia_saye_erhe:'撒叶儿嗬 · 跟鼓落步'};
charts.forEach((c,i)=>{const o=document.createElement('option');o.value=i;o.textContent=names[c.task]||c.task;q('#choice').append(o)});
function load(index){chart=charts[index];q('#audio').src=chart.url;stopAt=Infinity;selected=0;q('#rows').replaceChildren();let svg='<line x1="20" y1="75" x2="1080" y2="75" stroke="#8dac9c"/>';chart.events.forEach((e,i)=>{const x=20+e.time_ms/chart.end_ms*1060, end=20+e.end_ms/chart.end_ms*1060,y=e.direction<0?45:e.direction>0?105:75;svg+=`<line x1="${x}" y1="${y}" x2="${Math.max(x+3,end)}" y2="${y}" stroke="${e.kind==='rest'?'#a7c2aa':'#e1b45b'}" stroke-width="10"/><circle cx="${x}" cy="${y}" r="6" fill="#e7d4a8"/>`;const tr=document.createElement('tr');tr.id='row'+i;[e.id,(e.time_ms/1000).toFixed(3),e.kind,e.direction,(e.end_ms/1000).toFixed(3),e.cue_ms+' ms'].forEach(v=>{const td=document.createElement('td');td.textContent=v;tr.append(td)});const td=document.createElement('td'),b=document.createElement('button');b.textContent='试听';b.onclick=()=>listen(i);td.append(b);tr.append(td);q('#rows').append(tr)});svg+='<line id="cursor" x1="20" y1="15" x2="20" y2="135" stroke="#ef7764" stroke-width="3"/>';q('#timeline').innerHTML=svg;q('#info').textContent=`v${chart.version} · ${(chart.end_ms/1000).toFixed(2)} 秒 · SHA256 ${chart.audio_sha256}`}
function listen(i){selected=Math.max(0,Math.min(chart.events.length-1,i));const e=chart.events[selected];q('#audio').currentTime=Math.max(0,e.time_ms/1000-1.3);stopAt=Math.min(chart.end_ms/1000,e.end_ms/1000+1);q('#audio').play();document.querySelectorAll('tr.active').forEach(r=>r.classList.remove('active'));q('#row'+selected).classList.add('active')}
q('#choice').onchange=e=>load(+e.target.value);q('#previous').onclick=()=>listen(selected-1);q('#next').onclick=()=>listen(selected+1);q('#audio').ontimeupdate=()=>{const x=20+q('#audio').currentTime*1000/chart.end_ms*1060;q('#cursor').setAttribute('x1',x);q('#cursor').setAttribute('x2',x);if(q('#audio').currentTime>=stopAt){q('#audio').pause();stopAt=Infinity}};load(0);</script></html>'''
    OUT.parent.mkdir(parents=True,exist_ok=True)
    OUT.write_text(html.replace('PAYLOAD',payload),encoding='utf-8')
    print(OUT)

if __name__=='__main__':main()
