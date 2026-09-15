"""Build explicit game-arrangement drafts; no onset-to-chart auto generation.

All timings below are authored gameplay prompts, NOT a transcription of the
traditional recordings. Natural phrase cuts and mixing remain listening review
items. Originals and the v1 derived media are never overwritten.
"""
from pathlib import Path
import hashlib, json, subprocess, wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
FF = ROOT / 'artifacts/media-20260909/toolchain/ffmpeg-9.0.1-essentials_build/bin/ffmpeg.exe'
RATE = 44100
OUT = ROOT / 'InheritanceTasks/Audio/rhythm-v2'
CHARTS = ROOT / 'InheritanceTasks/Charts'
MEDIA = ROOT / 'arts/非遗媒体资源/数字版/2026-09-09'
OUT.mkdir(parents=True, exist_ok=True)

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def wavefile(path, data):
    with wave.open(str(path), 'wb') as stream:
        stream.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        stream.writeframes((np.clip(data, -.98, .98)*32767).astype('<i2').tobytes())
def ogg(path, data):
    subprocess.run([str(FF), '-y', '-v', 'error', '-f', 'f32le', '-ar', str(RATE), '-ac', '1', '-i', '-', '-c:a', 'libvorbis', '-q:a', '6', str(path)], input=data.astype('<f4').tobytes(), check=True)
def decoded(path):
    return np.frombuffer(subprocess.check_output([str(FF), '-v', 'error', '-i', str(path), '-f', 'f32le', '-ar', str(RATE), '-ac', '1', '-']), np.float32).copy()
def add(dst, at, data, gain=1):
    first = round(at*RATE)
    count = min(len(data), len(dst)-first)
    if count > 0: dst[first:first+count] += data[:count]*gain
def tone(freq, duration, decay=20):
    t=np.arange(round(duration*RATE))/RATE
    return np.sin(2*np.pi*freq*t)*np.exp(-t*decay)*np.minimum(1,t/.003)

rng=np.random.default_rng(14092026)
t=np.arange(round(.23*RATE))/RATE
noise=rng.normal(0,1,len(t))
feedback={
 'pluck': sum(tone(196*(i+1),.23,14+i*8)/(i+1)**1.5 for i in range(7))*.34,
 'dance': (np.sin(2*np.pi*(95*t-90*t*t))*np.exp(-t*32)+np.convolve(noise,np.ones(13)/13,'same')*np.exp(-t*50))*.46,
 'sing': sum(np.sin(2*np.pi*180*(i+1)*t)*np.exp(-((180*(i+1)-780)/1000)**2)/(i+1) for i in range(10))*np.sin(np.pi*np.minimum(1,t/.23))**2*.20,
 'switch': (noise*np.exp(-t*130)+np.sin(2*np.pi*2100*t)*np.exp(-t*85)+np.sin(2*np.pi*380*t)*np.exp(-t*45))*.20,
 'bow': (sum(np.sin(2*np.pi*147*(i+1)*t)/(i+1) for i in range(8))*.23+noise*.08)*np.sin(np.pi*t/.23)**2*.27,
 'drum': (np.sin(2*np.pi*(130*t-130*t*t))*np.exp(-t*24)+np.sin(2*np.pi*1150*t)*np.exp(-t*70)*.35+noise*np.exp(-t*95)*.30)*.43,
 'confirm': tone(1320,.11,42)*.15+tone(1980,.11,50)*.07,
 'count': tone(880,.075,48)*.23,
}
for key,data in feedback.items(): wavefile(OUT/(key+'.wav'),data)
calibration=np.zeros(round(14.7*RATE))
for i in range(19): add(calibration,.7+i*.7,feedback['count'])
ogg(OUT/'calibration.ogg',calibration)

def event(task, number, at, kind='tap', direction=0, end=None, round_index=0):
    e={'id':f'{task}-v2-{number:02d}','time_ms':round(at*1000),'kind':kind,'direction':direction,'end_ms':round((at if end is None else end)*1000),'cue_ms':1000,'round':round_index}
    if kind=='rest': e['rest_policy']='keep_position' if task=='han_ju' else 'release_required'
    return e

def save_chart(task, mode, mix, events, sections, source_edits):
    events.sort(key=lambda e:(e['time_ms'],e['id']))
    path=OUT/(task+'-mix.ogg'); ogg(path,mix)
    tutorial=np.zeros(round(11*RATE))
    add(tutorial,.4,feedback['count']); add(tutorial,1.0,feedback['count'])
    ogg(OUT/(task+'-lesson.ogg'),tutorial)
    sample=OUT/(task+'-sample.ogg'); ogg(sample,mix[:round(10.5*RATE)])
    data={'version':2,'audio_path':'res://'+path.relative_to(ROOT).as_posix(),'audio_sha256':sha(path),'end_ms':round(len(mix)/RATE*1000),'events':events,'presentation':[dict(e) for e in events],'sections':sections,'tutorial_audio_path':f'res://InheritanceTasks/Audio/rhythm-v2/{task}-lesson.ogg','feedback_key':mode,'production_status':'game_arrangement_pending_listening','annotation_note':'游戏节奏编排v2；原调原速。短句自然边界、混音及文化动作仍待人工听审，不作为传统节型、帮腔声部或真实弓法转录。'}
    (CHARTS/(task+'.json')).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    text='[gd_resource type="Resource" script_class="HeritageMusicChart" load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://InheritanceTasks/Common/heritage_music_chart.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\n'
    for key,val in data.items():
        encoded=json.dumps(val,ensure_ascii=False)
        if isinstance(val,list): encoded='Array[Dictionary]('+encoded+')'
        text+=key+' = '+encoded+'\n'
    (CHARTS/(task+'.tres')).write_text(text,encoding='utf-8')
    return {'task':task,'status':data['production_status'],'mix':str(path.relative_to(ROOT)),'sha256':sha(path),'sample':str(sample.relative_to(ROOT)),'edits':source_edits,'events':len(events),'feedback':mode,'checks':{'decoded_samples':len(mix),'peak_dbfs':float(20*np.log10(max(1e-8,np.max(np.abs(mix))))),'listened':False}}

def source(stem): return decoded(MEDIA/(stem+'.ogg'))
def copy_clip(dst, src, at, start, length, gain=.72):
    clip=src[round(start*RATE):round((start+length)*RATE)].copy()
    # Short click-prevention fades, never time stretch or pitch shift.
    fade=min(round(.012*RATE),len(clip)//2)
    clip[:fade]*=np.linspace(0,1,fade); clip[-fade:]*=np.linspace(1,0,fade)
    add(dst,at,clip,gain)

reports=[]
# Clear listen / handoff / response blocks. Candidate cuts are deliberately
# explicit, reviewable EDL entries rather than a hidden peak-snapping algorithm.
for task,stem,mode in [('laohekou_si_xian','laohekou-ensemble-v1','pluck'),('jingzhou_hua_gu_xi','jingzhou-zhanhuaqiang-v1','sing'),('ti_qin_xi','tiqin-stage-v1','bow')]:
    src=source(stem); mix=np.zeros(round(39*RATE)); ev=[]; sections=[]; edits=[]
    for r,start in enumerate([1.0,10.0,20.0,30.0]):
        base=r*9.5
        copy_clip(mix,src,base,start,3.4)
        edits.append({'source':str((MEDIA/(stem+'.ogg')).relative_to(ROOT)),'source_sha256':sha(MEDIA/(stem+'.ogg')),'source_in_seconds':start,'source_out_seconds':start+3.4,'mix_in_seconds':base,'natural_phrase_review':'pending'})
        for at in [base+3.55,base+4.25]: add(mix,at,feedback['count'],.65)
        sections.append({'id':f'round-{r+1}','start_ms':round(base*1000),'listen_end_ms':round((base+3.4)*1000),'response_start_ms':round((base+4.95)*1000),'end_ms':round((base+9.5)*1000),'round':r,'teacher_times_ms':[round((base+3.55)*1000),round((base+4.25)*1000)]})
        if mode=='pluck':
            offsets=[[4.95,6.35,7.75],[4.95,5.48,7.75,8.28],[4.95,6.88,7.41],[4.95,5.48,6.88,8.28]][r]
            for off in offsets: ev.append(event(task,len(ev)+1,base+off,round_index=r))
        else:
            # Different two-phrase time shapes, not an identical 1050ms hold.
            direction=(-1 if r%2==0 else 1) if mode=='bow' else 0
            ev.append(event(task,len(ev)+1,base+4.95,'hold',direction,base+[6.25,6.65,6.05,6.45][r],r))
            other=-direction if mode=='bow' else 0
            ev.append(event(task,len(ev)+1,base+7.15,'hold' if r in [1,3] else 'tap',other,base+8.4 if r in [1,3] else None,r))
        if r in [0,2]:
            # Rest is before the next partner segment, clear of release windows.
            ev.append(event(task,len(ev)+1,base+8.70,'rest',0,base+9.10,r))
    reports.append(save_chart(task,mode,mix,ev,sections,edits))

# Continuous recordings for dance and spotlight. Timings are an authored game
# arrangement supported by audible handoff cues, not asserted transcription.
for task,stem,mode in [('tujia_saye_erhe','sayeerhe-stage-v1','dance'),('han_ju','hanju-congtaibie-v1','switch')]:
    src=source(stem); mix=np.zeros(round(40*RATE)); copy_clip(mix,src,0,1.0,39.8,.68)
    ev=[];sections=[]
    for r in range(4):
        base=r*9.5
        directions=([-1,1,-1,1] if r==0 else [-1,1,1,-1] if r==1 else [-1,-1,1,1] if r==2 else [-1,1,-1,-1]) if mode=='dance' else [1,-1,1,-1]
        offsets=[2.0,3.5,5.0,6.5] if mode=='dance' else [2.0,3.7,5.4,7.1]
        for n,(off,direction) in enumerate(zip(offsets,directions)):
            ev.append(event(task,len(ev)+1,base+off,'tap' if mode=='dance' else 'switch',direction,round_index=r))
            if mode=='dance': add(mix,base+off,feedback['drum'],.32)
        if r in [0,2]: ev.append(event(task,len(ev)+1,base+7.8,'rest',directions[-1],base+8.7,r))
        add(mix,base+.5,feedback['count'],.5);add(mix,base+1.25,feedback['count'],.5)
        sections.append({'id':f'group-{r+1}','start_ms':round(base*1000),'end_ms':round((base+9.5)*1000),'round':r})
    reports.append(save_chart(task,mode,mix,ev,sections,[{'source':str((MEDIA/(stem+'.ogg')).relative_to(ROOT)),'source_sha256':sha(MEDIA/(stem+'.ogg')),'source_in_seconds':1.0,'source_out_seconds':40.8,'mix_in_seconds':0,'natural_phrase_review':'pending','added_sound':'game rehearsal cue, not isolated authentic percussion'}]))

task='gu_pen_ge';mix=np.zeros(round(33*RATE));ev=[];sections=[]
patterns=[[0,.7,1.4],[0,.7,2.1,2.8],[0,.42,.84,1.68,2.52]]
for r,pattern in enumerate(patterns):
    base=r*11
    for off in pattern:add(mix,base+1.2+off,feedback['drum'])
    for off in [4.4,5.1]:add(mix,base+off,feedback['count'],.7)
    for off in pattern:ev.append(event(task,len(ev)+1,base+5.8+off,round_index=r))
    sections.append({'id':f'round-{r+1}','round':r,'start_ms':round(base*1000),'listen_end_ms':round((base+4.2)*1000),'response_start_ms':round((base+5.8)*1000),'end_ms':round((base+11)*1000),'teacher_times_ms':[round((base+1.2+o)*1000) for o in pattern],'pattern_ms':[round(o*1000) for o in pattern]})
reports.append(save_chart(task,'drum',mix,ev,sections,[]))
manifest={'version':2,'authoring':'explicit editable game phrase arrangement; no automatic onset scoring','source_permission':'user-provided authorized videos; originals preserved','source_pitch_shift':False,'source_time_stretch':False,'listening_status':'not listened by an audio-capable reviewer; all natural phrase cuts and mix balance need review','feedback_provenance':'six original synthesized game interaction sounds, not authentic instruments or traditional repertoire','tasks':reports,'feedback_files':{k:{'path':str((OUT/(k+'.wav')).relative_to(ROOT)),'sha256':sha(OUT/(k+'.wav'))} for k in feedback}}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps([{'task':r['task'],'events':r['events'],'peak':round(r['checks']['peak_dbfs'],2)} for r in reports],ensure_ascii=False))
