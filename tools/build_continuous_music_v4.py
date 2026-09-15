"""Continuous authorized recordings; never insert player-response silence.

Score marks are explicit editable game cues. Listening review is recorded as
pending; a successful encode/hash check is not a musical-transcription claim.
Gupen's call/response audio and score are deliberately left untouched.
"""
from pathlib import Path
import copy, json, shutil, wave
import numpy as np
from build_rhythm_lessons_v3 import decode,encode,sha,save_resource,choreography,RATE

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'InheritanceTasks/Audio/rhythm-v4'
MEDIA=ROOT/'arts/非遗媒体资源/数字版/2026-09-09'
SOURCES={'laohekou_si_xian':'laohekou-ensemble-v1','tujia_saye_erhe':'sayeerhe-stage-v1',
 'jingzhou_hua_gu_xi':'jingzhou-zhanhuaqiang-v1','han_ju':'hanju-congtaibie-v1','ti_qin_xi':'tiqin-stage-v1'}
# All numbers remain explicit/source-time editable in the export. No fixed
# reply blocks, BPM quantization, or onset snapping is performed by this tool.
MARKS={
 'laohekou_si_xian':[(2.15,0),(3.54,0),(5.02,0),(6.43,0),(8.16,0),(8.69,0),(10.73,0),(12.42,0),(13.01,0),(15.25,0),(17.36,0),(17.91,0),(20.18,0),(22.54,0),(23.08,0),(25.47,0),(27.52,0),(28.14,0),(30.67,0),(32.48,0),(34.62,0),(35.18,0),(37.64,0),(38.25,0)],
 'tujia_saye_erhe':[(2.04,-1),(3.08,1),(4.12,-1),(5.19,1),(6.27,-1),(7.33,1),(9.48,-1),(10.53,1),(11.61,1),(12.67,-1),(14.78,1),(15.85,-1),(16.93,-1),(18.02,1),(20.15,-1),(21.21,1),(22.28,-1),(23.35,1),(25.47,-1),(26.54,-1),(27.61,1),(28.68,1),(30.83,-1),(31.89,1),(32.96,1),(34.02,-1),(36.16,1),(37.22,-1),(38.30,1),(39.37,-1)],
 'han_ju':[(2.14,1),(4.83,-1),(7.56,1),(10.21,-1),(13.69,1),(15.82,-1),(18.55,1),(21.14,-1),(24.48,1),(26.73,-1),(28.41,1),(30.26,-1),(33.62,1),(36.13,-1),(38.72,1),(41.04,-1)],
 'jingzhou_hua_gu_xi':[(2.20,0,3.36),(5.54,0),(7.78,0,9.22),(11.48,0),(13.72,0,15.21),(17.55,0),(19.63,0,21.36),(23.74,0),(26.18,0,27.49),(29.82,0),(32.05,0,34.12),(36.43,0),(38.12,0)],
 'ti_qin_xi':[(2.15,-1),(3.53,1),(5.04,-1,6.63),(8.23,1),(10.47,-1),(12.06,1,13.82),(15.52,-1),(17.11,1),(19.35,-1,21.13),(23.03,1),(25.48,-1),(27.21,1,29.02),(31.35,-1),(33.02,1),(35.11,-1,37.04),(38.57,1)]}

def event(task,n,mark):
    t,d,*tail=mark; end=tail[0] if tail else t
    kind='hold' if tail else 'switch' if task=='han_ju' else 'tap'
    return dict(id=f'{task}-continuous-v4-{n:02}',time_ms=round(t*1000),end_ms=round(end*1000),kind=kind,direction=d,cue_ms=1100,round=n//6)

def lesson(chart,indices,instruction,required,number,samples):
    selected=[chart['events'][i] for i in indices]
    start=max(0,selected[0]['time_ms']-1500);end=min(chart['end_ms'],selected[-1]['end_ms']+900)
    ev=copy.deepcopy(selected)
    for e in ev:e['time_ms']-=start;e['end_ms']-=start
    clips=[]
    for c in chart['choreography']:
        if c['end_ms']<=start or c['start_ms']>=end:continue
        if c['event_id'] and c['event_id'] not in [e['id'] for e in ev]:continue
        c=copy.deepcopy(c);c['start_ms']=max(0,c['start_ms']-start);c['end_ms']=min(end-start,c['end_ms']-start);clips.append(c)
    path=OUT/f'{chart["feedback_key"]}-lesson-{number}.ogg';encode(path,samples[round(start*RATE/1000):round(end*RATE/1000)])
    initial=-1
    for e in chart['events']:
        if e['kind']=='switch' and e['time_ms']<start:initial=e['direction']
    return dict(instruction=instruction,retry_hint=instruction,initial_lane=initial,required=required,duration_ms=end-start,
     audio_path='res://'+path.relative_to(ROOT).as_posix(),audio_sha256=sha(path),source_mix=chart['audio_path'],source_in_ms=start,source_out_ms=end,
     events=ev,presentation=copy.deepcopy(ev),choreography=clips,sections=[])

def main():
    OUT.mkdir(parents=True,exist_ok=True);archive=OUT/'previous';archive.mkdir(exist_ok=True)
    reports=[]
    specs={
     'laohekou_si_xian':[([0],'跟着音乐，圈合上拨弦','hit'),([4,5],'拨、松开、再拨','double')],
     'tujia_saye_erhe':[([0,1],'左右脚跟着落地','double'),([6,7,8],'左、右、再右','double')],
     'han_ju':[([0],'亮相时选右灯','hit'),([1,2],'左灯接亮相，再换右灯','double')],
     'jingzhou_hua_gu_xi':[([1],'跟着唱句点一下','hit'),([0],'按住，青圈合上松开','hold')],
     'ti_qin_xi':[([0,1],'左短弓，再右短弓','double'),([2],'左边按住，圈合上收弓','hold'),([5],'右边按住，圈合上收弓','hold')]}
    for task,stem in SOURCES.items():
        current=ROOT/'InheritanceTasks/Charts'/f'{task}.json'
        old=archive/current.name
        if not old.exists():shutil.copy2(current,old)
        chart=json.loads(old.read_text(encoding='utf8'))
        source=MEDIA/f'{stem}.ogg';target=OUT/f'{task}-continuous.ogg';shutil.copy2(source,target)
        samples=decode(source)
        chart.update(version=4,audio_path='res://'+target.relative_to(ROOT).as_posix(),audio_sha256=sha(target),end_ms=round(len(samples)*1000/RATE),
          events=[event(task,i,m) for i,m in enumerate(MARKS[task])],sections=[],production_status='continuous_source_integrated_timing_listening_pending',
          annotation_note='v4连续授权原声，原速原调，玩家输入不切断演出。明确游戏提示时间线；尚待逐句听审，不宣称真实帮腔、弓法或声腔转录。')
        chart['presentation']=copy.deepcopy(chart['events'])
        chart['choreography']=choreography(task,chart)
        if task in ['laohekou_si_xian','jingzhou_hua_gu_xi','ti_qin_xi']:
            actors=['partner_left','partner_right'] if task=='laohekou_si_xian' else ['lead']
            for actor in actors:chart['choreography'].append(dict(id=task+'-continuous-'+actor,actor=actor,action='play_phrase' if actor.startswith('partner') else 'sing_phrase',start_ms=0,end_ms=chart['end_ms'],frames=[0,1,2,1],event_id='',direction=0,cycle_ms=1400))
        chart['tutorial_steps']=[lesson(chart,idx,text,required,n,samples) for n,(idx,text,required) in enumerate(specs[task])]
        chart['tutorial_audio_path']=chart['tutorial_steps'][0]['audio_path'];save_resource(task,chart)
        report=dict(task=task,source=str(source.relative_to(ROOT)),source_sha256=sha(source),output=chart['audio_path'],output_sha256=sha(target),
          edits=[],byte_identical=True,authored_silence=False,listening_review=False,score_review='pending',duration_ms=chart['end_ms'])
        if task in ['jingzhou_hua_gu_xi','ti_qin_xi']:
            start,end=(5.48,5.77) if task=='jingzhou_hua_gu_xi' else (3.47,3.71)
            clip=samples[round(start*RATE):round(end*RATE)].copy()
            fade=min(220,len(clip)//2);clip[:fade]*=np.linspace(0,1,fade);clip[-fade:]*=np.linspace(1,0,fade)
            peak=max(.01,np.max(np.abs(clip)));clip*=.35/peak
            path=OUT/f'{chart["feedback_key"]}-recorded.wav'
            with wave.open(str(path),'wb') as w:w.setparams((1,2,RATE,0,'NONE','not compressed'));w.writeframes((clip*32767).astype('<i2').tobytes())
            report['feedback']=dict(path=str(path.relative_to(ROOT)),sha256=sha(path),source_in_seconds=start,source_out_seconds=end,
             note='授权现场录音短片段，非分轨；游戏触发反馈，非声部或真实弓法认证',listening_review=False)
        reports.append(report)
    (OUT/'manifest.json').write_text(json.dumps({'version':4,'tasks':reports,'gupen':'unchanged demonstration/repeat audio and chart'},ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps(reports,ensure_ascii=False))

if __name__=='__main__':main()
