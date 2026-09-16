"""Rebuild selected CC0 foley and original soft notification tones; no game RNG."""
from pathlib import Path
import array
import hashlib
import json
import math
import re
import shutil
import subprocess
import wave
import numpy as np
from functools import lru_cache

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'artifacts/board-audio/sources'
OUT = ROOT / 'Audio/SFX'
FF = ROOT / 'artifacts/media-20260909/toolchain/ffmpeg-9.0.1-essentials_build/bin/ffmpeg.exe'
SR = 44100
SELECTED = {
    'dice_roll': ('casino', 'dice-shake-1.ogg', .66),
    'dice_land': ('casino', 'die-throw-1.ogg', .30),
    'card': ('casino', 'card-slide-1.ogg', .24),
    'page': ('casino', 'card-fan-1.ogg', .26),
    'trade': ('casino', 'chips-handle-1.ogg', .34),
    'move': ('casino', 'chip-lay-1.ogg', .16),
}

def write(name, samples, gain=None):
    values = list(samples)
    peak = max(abs(x) for x in values) or 1
    # Foley retains its existing export. Musical cues use fixed gain: do not
    # normalize a softened transient right back to the previous loud peak.
    scale = .48 / peak if gain is None else gain
    pcm = array.array('h', (round(max(-1, min(1, x * scale)) * 32767) for x in values))
    with wave.open(str(OUT / (name + '.wav')), 'wb') as f:
        f.setparams((1, 2, SR, 0, 'NONE', 'not compressed'))
        f.writeframes(pcm.tobytes())

INSTRUMENTS = ROOT / 'Audio/Source/chinese-instruments'
PROFILES = [
    # Routine cues keep original-speed samples; achievement has its own phrase.
    ('confirm', '确认 / 选择 · 木鱼轻点', [1], .10, .14, .5, 0),
    ('back', '返回 / 取消 / 关闭 · 木鱼轻收', [1], .10, .16, .7, 0),
    ('invalid', '无效操作 · 木鱼短点', [1], .12, .18, 1.5, 0),
    ('turn', '回合 · 一声淡弦', [219.0], .16, .80, .15, 0),
    ('action', '行动 · 短弦', [219.0], .10, .50, .65, 0),
    ('warning', '倒计时 · 木鱼轻双点', [1, 1], .20, .40, 1.5, 0),
    ('recover', '恢复 · 舒展双弦', [130.3, 219.0], .28, .98, .15, 0),
    ('event', '事件 · 淡低弦', [130.3], .15, .72, .25, 0),
    ('response', '响应 · 木鱼轻点', [1], .10, .14, .7, 0),
    ('achievement', '成就 · 古筝华彩', [130.3, 164.17, 195.11, 219.0, 260.6], .15, 1.90, .10, 0),
    ('result', '结算 · 单弦收束', [130.3], .10, .65, .45, 0),
    ('eliminate', '淘汰 · 低弦渐收', [130.3], .19, .85, .35, 0),
    ('technical', '异常 · 木鱼单点', [1], .18, .20, 1.5, 0),
]
PERCUSSION_PITCH = {'invalid': 1.0, 'warning': 1.0, 'technical': 1.0}
# Cutoff and fixed gain differentiate clear confirmation from softer closing,
# without lowering playback pitch into the rejected rubbery back sound.
UI_PERCUSSION = {
    'confirm': (2400, .22), 'back': (1650, .18),
    'invalid': (1850, .24), 'response': (2150, .20),
    'warning': (2250, .25), 'technical': (1800, .24),
}

def soft_mokugyo(cue, notes, spacing, duration):
    cutoff, gain = UI_PERCUSSION[cue]
    raw = subprocess.run([str(FF), '-v', 'error', '-i', str(INSTRUMENTS/'mokugyo-607215-hq.mp3'), '-t', '0.30', '-ac', '1', '-ar', str(SR), '-af', f'highpass=f=180,lowpass=f={cutoff}', '-f', 'f32le', '-'], capture_output=True, check=True).stdout
    sample = np.frombuffer(raw, dtype='<f4')
    output = np.zeros(round(SR * duration))
    for i in range(len(notes)):
        offset = round(i * spacing * SR)
        count = min(len(sample), len(output)-offset, round(.20*SR))
        t = np.arange(count)/SR
        envelope = np.sin(np.minimum(t/.007, 1)*np.pi/2)**2
        tail = min(round(.06*SR), count)
        envelope[-tail:] *= np.sin(np.linspace(np.pi/2, 0, tail))**2
        output[offset:offset+count] += sample[:count]*envelope*(.60**i)
    return output, gain

@lru_cache(None)
def pluck(frequency):
    # Recording has two isolated plucks: A3 near 0.034s and C3 near 7.405s.
    # Achievement alone adds neighboring pitches (within four semitones);
    # routine state cues use the two recordings at original speed.
    start, base = min([(.029, 219.0), (7.400, 130.3)], key=lambda v: abs(math.log2(frequency / v[1])))
    ratio = frequency / base
    raw = subprocess.run([str(FF), '-v', 'error', '-ss', str(start), '-i', str(INSTRUMENTS/'guzheng-847157-hq.mp3'), '-t', '2.0', '-ac', '1', '-af', f'asetrate={round(SR*ratio)},aresample={SR},highpass=f=95,lowpass=f=3800', '-f', 'f32le', '-'], capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype='<f4').copy()
    return x / .74  # Shared reference; retain the recordings' relative dynamics.

@lru_cache(None)
def gong():
    raw = subprocess.run([str(FF), '-v', 'error', '-ss', '0.90', '-i', str(INSTRUMENTS/'gong-76886-hq.mp3'), '-t', '2.0', '-ac', '1', '-ar', str(SR), '-af', 'highpass=f=180,lowpass=f=5000,afade=t=in:d=0.012', '-f', 'f32le', '-'], capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype='<f4').copy()
    return x / max(float(np.max(np.abs(x))), .001)

@lru_cache(None)
def temple_block(pitch):
    raw = subprocess.run([str(FF), '-v', 'error', '-i', str(INSTRUMENTS/'temple-block-544881-hq.mp3'), '-t', '0.35', '-ac', '1', '-af', f'lowpass=f=1900,asetrate={round(SR*pitch)},aresample={SR},afade=t=in:d=0.015', '-f', 'f32le', '-'], capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype='<f4').copy()
    return x / .87

def phrase(notes, spacing, duration, damping, gong_gain, percussion_pitch=None):
    output = np.zeros(round(SR * duration))
    for index, frequency in enumerate(notes):
        offset = round(index * spacing * SR)
        sample = temple_block(percussion_pitch) if percussion_pitch else pluck(frequency)
        count = min(len(sample), len(output) - offset)
        t = np.arange(count) / SR
        attack = np.sin(np.minimum(t / (.025 if percussion_pitch else .12), 1) * np.pi/2)**2
        output[offset:offset+count] += sample[:count] * attack * np.exp(-damping*t) * (.68**index)
    if gong_gain:
        sample = gong(); count = min(len(output), len(sample))
        output[:count] += sample[:count] * gong_gain * np.exp(-np.arange(count)/SR*2)
    # Long enough to preserve the string's natural decay; soft release, no hard cut.
    tail = min(round(.22*SR), len(output))
    output[-tail:] *= np.sin(np.linspace(np.pi/2, 0, tail))**2
    return output

def achievement_flourish(notes, duration):
    """A rising five-note figure, then a lightly voiced tonic landing."""
    output = np.zeros(round(SR*duration))
    # Unequal spacing gives a lifted ending instead of a metronomic scale.
    events = [(0.0, notes[0], .48), (.14, notes[1], .54),
              (.29, notes[2], .61), (.47, notes[3], .70),
              (.75, notes[4], .85), (.77, notes[0], .23),
              (.80, notes[2], .18)]
    for onset, frequency, gain in events:
        sample = pluck(frequency)
        offset = round(onset*SR)
        count = min(len(sample), len(output)-offset)
        t = np.arange(count)/SR
        attack = np.sin(np.minimum(t/.045, 1)*np.pi/2)**2
        output[offset:offset+count] += sample[:count]*attack*np.exp(-.48*t)*gain
    # A little depth, without restoring the old gong or a long reverb wash.
    dry = output.copy()
    for seconds, gain in [(.033, .08), (.059, .04)]:
        shift = round(seconds*SR)
        output[shift:] += dry[:-shift]*gain
    tail = round(.36*SR)
    output[-tail:] *= np.sin(np.linspace(np.pi/2, 0, tail))**2
    return output, events

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = []
    for name, (pack, filename, duration) in SELECTED.items():
        source = SOURCE / pack / 'Audio' / filename
        result = subprocess.run([str(FF), '-v', 'error', '-i', str(source), '-t', str(duration), '-ac', '1', '-ar', str(SR), '-af', f'afade=t=in:d=0.003,afade=t=out:st={duration-.025}:d=0.025', '-f', 's16le', '-'], capture_output=True, check=True)
        samples = array.array('h'); samples.frombytes(result.stdout)
        write(name, (x / 32768 for x in samples))
        manifest.append({'cue': name, 'source': filename, 'pack': pack, 'license': 'CC0-1.0', 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest()})
    for name, label, notes, spacing, duration, damping, gong_gain in PROFILES:
        if name in ['achievement', 'result']:
            if name == 'achievement':
                samples, events = achievement_flourish(notes, duration)
                gain = .22
                processing = 'five-note rising guzheng figure, soft tonic landing, subtle early reflections; nearby sample transposition within four semitones; no gong'
            else:
                samples = phrase(notes, spacing, duration, damping, 0)
                events = [(0.0, notes[0], 1.0)]
                gain = .20
                processing = 'one original-speed low guzheng pluck; soft attack and release; no arpeggio, chord, gong or added reflections'
            write(name, samples, gain=gain)
            source_name = 'guzheng-847157-hq.mp3'
            manifest.append({'cue':name, 'label':label, 'revision':'achievement-result-v5', 'source':[source_name], 'license':'CC0-1.0', 'processing':processing, 'notes_hz':notes, 'events':events, 'export_gain':gain, 'source_sha256':{source_name:hashlib.sha256((INSTRUMENTS/source_name).read_bytes()).hexdigest()}})
            continue
        if name in UI_PERCUSSION:
            samples, gain = soft_mokugyo(name, notes, spacing, duration)
            write(name, samples, gain=gain)
            source_name = 'mokugyo-607215-hq.mp3'
            manifest.append({'cue':name, 'label':label, 'revision':'soft-percussion-v4', 'source':[source_name], 'license':'CC0-1.0', 'processing':'original-speed cloth-beater wooden fish recording; 7ms softened attack, 60ms release; no pitch shift, strings, gong, or added reverb', 'lowpass_hz':UI_PERCUSSION[name][0], 'export_gain':gain, 'source_sha256':{source_name:hashlib.sha256((INSTRUMENTS/source_name).read_bytes()).hexdigest()}})
            continue
        percussion_pitch = PERCUSSION_PITCH.get(name)
        gain = .28 if percussion_pitch else (.26 if name in ['turn','achievement','result'] else .24)
        write(name, phrase(notes, spacing, duration, damping, gong_gain, percussion_pitch), gain=gain)
        sources = (['temple-block-544881-hq.mp3'] if percussion_pitch else ['guzheng-847157-hq.mp3']) + (['gong-76886-hq.mp3'] if gong_gain else [])
        manifest.append({'cue': name, 'label': label, 'revision': 'soft-natural-v3', 'source': sources, 'license': 'CC0-1.0', 'processing': 'original-speed samples, soft attack, natural decay, fixed gain without peak normalization', 'notes_hz': notes if not percussion_pitch else [], 'export_gain': gain, 'percussion_pitch': percussion_pitch, 'source_sha256': {n:hashlib.sha256((INSTRUMENTS/n).read_bytes()).hexdigest() for n in sources}})
    for entry in manifest:
        path = OUT / (entry['cue'] + '.wav')
        entry['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        with wave.open(str(path)) as f:
            entry['duration'] = f.getnframes() / f.getframerate()
    for pack in ['casino', 'interface']:
        shutil.copyfile(SOURCE / pack / 'License.txt', OUT / (pack + '-LICENSE.txt'))
    (OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf8')
    # Changed instruments first, with old sounds available for a direct comparison.
    order = ['achievement', 'result'] + [p[0] for p in PROFILES if p[0] not in ['achievement','result']] + list(SELECTED)
    ordered = [next(e for e in manifest if e['cue']==name) for name in order]
    runtime = (ROOT / 'Audio/board_sfx.gd').read_text(encoding='utf8')
    cue_gains = {name: float(gain) for name, gain in re.findall(r'&"(\w+)": \[\d+, ([-\d.]+),', runtime)}
    bus_gain = float(re.search(r'set_bus_volume_db\(bus, ([-\d.]+)\)', runtime)[1])
    music = (ROOT / 'Audio/board_music.gd').read_text(encoding='utf8')
    music_gain = float(re.search(r'DEFAULT_VOLUME_DB := ([-\d.]+)', music)[1])
    rows = ''
    for e in ordered:
        volume = 10**((cue_gains[e['cue']] + bus_gain)/20)
        if e['cue'] in ['achievement', 'result']:
            previous = f'<audio controls preload="none" data-volume="{volume:.6f}" src="pre-fanfare-v4/{e["cue"]}.wav"></audio>'
        elif e['cue'] in UI_PERCUSSION:
            previous = f'<audio controls preload="none" data-volume="{volume:.6f}" src="pre-percussion-v3/{e["cue"]}.wav"></audio><small>第三版对照</small>'
        else:
            previous = '沿用原版'
        rows += f'<tr><td>{e.get("label",e["cue"])}<small>{e["cue"]} · {e["duration"]:.2f}s</small></td><td><audio controls preload="none" data-cue="{e["cue"]}" data-volume="{volume:.6f}" src="../../Audio/SFX/{e["cue"]}.wav?v={e["sha256"][:12]}"></audio></td><td>{previous}</td></tr>'
    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>楚物志 · 木鱼轻点音效试听</title>
<style>body{background:#eee3cd;color:#4f4138;font:18px/1.6 sans-serif;margin:32px auto;padding:0 20px;max-width:1100px}td,th{padding:12px;text-align:left;border-bottom:1px solid #b7a58a}audio{height:36px;width:260px;max-width:100%}small{display:block;font-size:13px;margin-top:8px;opacity:.7}.scroll{overflow-x:auto}select{font:inherit;padding:5px;background:#fff8e9;color:inherit}h1{font-size:30px}</style>
<h1>中国乐器音效 · 第五版「成就与结算」</h1><p>成就：1.90秒古筝华彩，五音上行、轻叠收束和弦。结算：0.65秒低弦单音，简短平稳。确认、返回等木鱼轻点及其余提示沿用。</p>
<p><button id="repeat">连续试听确认 / 返回（8次）</button> <button id="stop">停止连续试听</button><small>可先播放 BGM，再试听连续操作。</small></p>
<p><label>试听响度 <select id="level"><option value="game">游戏默认响度</option><option value="raw">素材原始响度</option></select></label><br><small>默认应用游戏内各音效与总线增益，电脑操作还有额外衰减；浏览器和系统设备音量仍可能影响实际响度。新旧版本使用相同试听增益。</small></p>
<p>BGM <audio id="bgm" controls loop data-volume="MUSIC_VOLUME" src="../../Audio/Music/chuwuzhi-bgm.mp3"></audio></p>
<div class="scroll"><table><tr><th>事件与音色</th><th>当前版本</th><th>旧版对照</th></tr>ROWS</table></div>
<p><small>木鱼采样：<a href="https://freesound.org/people/jonopodmore/sounds/607215/">jonopodmore · Mokugyo.wav（CC0）</a>，原作者以布头槌敲击日本木鱼；用于木鱼音色设计，不标为湖北器物实录。</small></p>
<script>const sounds=[...document.querySelectorAll('audio')], level=document.getElementById('level');
function setLevels(){sounds.forEach(a=>a.volume=level.value==='raw'?1:Number(a.dataset.volume));}
level.addEventListener('change',setLevels);setLevels();
sounds.forEach(a=>a.addEventListener('play',()=>{if(a.id==='bgm')return;sounds.forEach(b=>{if(b!==a&&b.id!=='bgm'){b.pause();b.currentTime=0;}});}));
let pending=[];const repeat=document.getElementById('repeat');
function stopSequence(){pending.forEach(clearTimeout);pending=[];repeat.disabled=false;sounds.filter(a=>a.id!=='bgm').forEach(a=>{a.pause();a.currentTime=0;});}
document.getElementById('stop').addEventListener('click',stopSequence);
repeat.addEventListener('click',()=>{stopSequence();repeat.disabled=true;for(let i=0;i<8;i++){const play=()=>{const a=document.querySelector('audio[data-cue="'+(i%2?'back':'confirm')+'"]');a.currentTime=0;a.play().catch(stopSequence);};if(i===0)play();else pending.push(setTimeout(play,i*450));}pending.push(setTimeout(()=>{repeat.disabled=false;pending=[];},3600));});
window.addEventListener('pagehide',stopSequence);</script></html>'''
    page = page.replace('MUSIC_VOLUME', str(10**(music_gain/20))).replace('ROWS', rows)
    (ROOT / 'artifacts/board-audio/sfx-review.html').write_text(page, encoding='utf8')
    print('Built', len(manifest), 'cues')

if __name__ == '__main__': main()
