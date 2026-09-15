"""Reproducible v1 candidate charts: sparse envelope attacks, never a fixed BPM.
These timestamps require listening review before being called transcription.
Original media is read-only. Run with the bundled Python (numpy) and FFmpeg.
"""
from pathlib import Path
import hashlib, json, subprocess, wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / 'arts/非遗媒体资源/数字版/2026-09-09'
FFMPEG = ROOT / 'artifacts/media-20260909/toolchain/ffmpeg-9.0.1-essentials_build/bin/ffmpeg.exe'
SPECS = {
 'tujia_saye_erhe': ('sayeerhe-stage-v1', 43.35, 'dance'),
 'laohekou_si_xian': ('laohekou-ensemble-v1', 41, 'pluck'),
 'jingzhou_hua_gu_xi': ('jingzhou-zhanhuaqiang-v1', 40.85, 'sing'),
 'han_ju': ('hanju-congtaibie-v1', 43.8, 'switch'),
 'ti_qin_xi': ('tiqin-stage-v1', 41.1, 'bow'),
}

def attacks(path):
    raw = subprocess.check_output([str(FFMPEG), '-v','error','-i',str(path),'-f','f32le','-ac','1','-ar','8000','-'])
    signal = np.frombuffer(raw, np.float32)
    frames = signal[:len(signal)//80*80].reshape(-1,80)
    energy = np.sqrt(np.mean(frames**2,axis=1))
    novelty = np.maximum(0,energy-np.convolve(energy,np.ones(15)/15,'same'))
    return novelty

def main():
    output = ROOT / 'InheritanceTasks/Charts'
    output.mkdir(exist_ok=True)
    for task, (stem, duration, mode) in SPECS.items():
        path = MEDIA / (stem+'.ogg')
        envelope = attacks(path)
        events=[]
        # Sparse listening anchors; relocate each candidate to a nearby actual attack.
        anchors = np.linspace(2.8,duration-2.8,18 if mode=='dance' else 14)
        switch_count = 0
        for i, anchor in enumerate(anchors):
            low,high=int((anchor-.28)*100),int((anchor+.28)*100)
            t=(low+int(np.argmax(envelope[low:high])))*10
            kind='tap'; end=t; direction=0
            if mode in ('dance','bow'): direction=(-1 if i%2==0 else 1)
            if mode=='dance' and i in (9,10,14): direction=-1
            if mode=='switch': kind='switch'; direction=1 if i%2==0 else -1
            if mode in ('sing','bow') and i%3==2: kind='hold'; end=t+1050
            if i in (5,11): kind='rest'; end=t+800
            if mode=='switch' and kind=='switch':
                direction=1 if switch_count%2==0 else -1
                switch_count+=1
            events.append(dict(id=f'{task}-v1-{i+1:02}',time_ms=t,kind=kind,direction=direction,end_ms=end,cue_ms=850))
            if mode=='pluck' and i in (7,10):
                events.append(dict(id=f'{task}-v1-{i+1:02}b',time_ms=t+420,kind='tap',direction=0,end_ms=t+420,cue_ms=400))
        data={'version':1,'audio_path':'res://'+path.relative_to(ROOT).as_posix(),'audio_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'end_ms':round(duration*1000),'events':events,'annotation_note':'候选谱面：音频能量瞬态附近取点；长音、休止与角色动作是游戏编排，尚需逐句听审，不宣称真实帮腔或弓法。'}
        data['presentation']=[dict(event) for event in events]
        (output/(task+'.json')).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        def value(v):
            if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
            return str(v)
        text='[gd_resource type="Resource" script_class="HeritageMusicChart" load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://InheritanceTasks/Common/heritage_music_chart.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\n'
        for k in ('version','audio_path','audio_sha256','end_ms','annotation_note'): text+=f'{k} = {value(data[k])}\n'
        text+='events = Array[Dictionary](['+',\n'.join('{'+', '.join(value(k)+': '+value(v) for k,v in e.items())+'}' for e in events)+'])\n'
        text+='presentation = Array[Dictionary](['+',\n'.join('{'+', '.join(value(k)+': '+value(v) for k,v in e.items())+'}' for e in events)+'])\n'
        (output/(task+'.tres')).write_text(text,encoding='utf-8')
    audio=ROOT/'InheritanceTasks/Audio';audio.mkdir(exist_ok=True)
    t=np.arange(4410)/44100
    tone=(np.sin(2*np.pi*660*t)*np.exp(-t*45)*0.3*32767).astype('<i2')
    with wave.open(str(audio/'action-feedback.wav'),'wb') as f:
        f.setparams((1,2,44100,len(tone),'NONE','not compressed'));f.writeframes(tone.tobytes())
    noise=np.random.default_rng(90209).normal(0,1,44100)
    noise=np.convolve(noise,np.ones(5)/5,'same')
    noise=(noise*1800).astype('<i2')
    with wave.open(str(audio/'breath-feedback.wav'),'wb') as f:
        f.setparams((1,2,44100,len(noise),'NONE','not compressed'));f.writeframes(noise.tobytes())

if __name__=='__main__':main()
