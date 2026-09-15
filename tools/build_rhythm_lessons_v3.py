"""Real mix excerpts for teaching, independent actor tracks and review data.

Does NOT certify the old phrase cuts: those remain explicitly pending listening.
The archived v2 score/audio is immutable input, so reruns cannot compound edits.
"""
from pathlib import Path
import copy
import hashlib
import json
import subprocess
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'InheritanceTasks/Audio/rhythm-v3'
CHARTS = ROOT / 'InheritanceTasks/Charts'
FF = ROOT / 'artifacts/media-20260909/toolchain/ffmpeg-9.0.1-essentials_build/bin/ffmpeg.exe'
RATE = 44100
IDS = ['laohekou_si_xian', 'tujia_saye_erhe', 'jingzhou_hua_gu_xi', 'han_ju', 'ti_qin_xi', 'gu_pen_ge']

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def decode(path):
    return np.frombuffer(subprocess.check_output([str(FF), '-v', 'error', '-i', str(path), '-f', 'f32le', '-ar', str(RATE), '-ac', '1', '-']), '<f4').copy()

def encode(path, samples):
    subprocess.run([str(FF), '-v', 'error', '-y', '-f', 'f32le', '-ar', str(RATE), '-ac', '1', '-i', '-', '-c:a', 'libvorbis', '-q:a', '6', str(path)], input=samples.astype('<f4').tobytes(), check=True)

def save_resource(task, chart):
    (CHARTS / (task + '.json')).write_text(json.dumps(chart, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    text = '[gd_resource type="Resource" script_class="HeritageMusicChart" load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://InheritanceTasks/Common/heritage_music_chart.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\n'
    for key, value in chart.items():
        encoded = json.dumps(value, ensure_ascii=False)
        if isinstance(value, list): encoded = 'Array[Dictionary](' + encoded + ')'
        text += key + ' = ' + encoded + '\n'
    (CHARTS / (task + '.tres')).write_text(text, encoding='utf-8')

def choreography(task, chart):
    clips = []
    def clip(actor, action, start, end, frames, event_id='', direction=0, cycle_ms=0):
        start, end = max(0, int(start)), min(chart['end_ms'], int(end))
        if end <= start: return
        clips.append(dict(id=f'{task}-motion-{len(clips):03}', actor=actor, action=action,
                          start_ms=start, end_ms=end, frames=frames, event_id=event_id,
                          direction=direction, cycle_ms=cycle_ms))
    for section in chart['sections']:
        start, end = section['start_ms'], section['end_ms']
        listen = section.get('listen_end_ms', start)
        response = section.get('response_start_ms', start)
        if task == 'laohekou_si_xian':
            midpoint = start + (listen-start)//2
            for actor, begin, finish in [('partner_left', start, midpoint), ('partner_right', midpoint, listen)]:
                clip(actor, 'play_phrase', begin, finish, [0,1,2,1], cycle_ms=720)
                clip(actor, 'handoff', finish, response, [2,3])
        elif task in ['jingzhou_hua_gu_xi', 'ti_qin_xi']:
            clip('lead', 'prepare', start, min(start+380, listen), [0])
            clip('lead', 'sing_phrase', start+380, listen, [1,2,1], cycle_ms=1500)
            clip('lead', 'handoff', listen, response, [2,3])
        elif task == 'gu_pen_ge':
            for beat in section['teacher_times_ms']:
                clip('teacher', 'prepare', beat-350, beat, [0,1])
                clip('teacher', 'strike', beat, beat+170, [2])
                clip('teacher', 'recover', beat+170, beat+350, [3,0])
            clip('teacher', 'handoff', listen, response, [3])
    for e in chart['events']:
        start, end, direction = e['time_ms'], e['end_ms'], e['direction']
        lead = e['cue_ms']
        if task == 'tujia_saye_erhe':
            if e['kind'] == 'rest':
                clip('leader', 'rest', start, end, [0], e['id'])
            else:
                clip('leader', 'weight_shift', start-lead, start, [0,1], e['id'], direction)
                clip('leader', 'land', start, start+200, [2], e['id'], direction)
                clip('leader', 'recover', start+200, start+430, [3,0], e['id'], direction)
                clip('drummer', 'prepare', start-320, start, [0,1], e['id'])
                clip('drummer', 'strike', start, start+240, [2,3], e['id'])
        elif task == 'han_ju':
            if e['kind'] == 'switch':
                clip('actor', 'cross', start-lead, start, [0,1,2,1], e['id'], direction)
                clip('actor', 'arrive', start, start+450, [3], e['id'], direction)
            else: clip('actor', 'stay', start, end, [2,3], e['id'], direction)
    return sorted(clips, key=lambda c: (c['start_ms'], c['id']))

# Indices refer to the archived score, not inferred waveform peaks. Each lesson
# is a literal excerpt of a formal section; it asks only the current concept.
def specifications(task, chart):
    rounds = [[e for e in chart['events'] if e.get('round', 0)==r] for r in range(len(chart['sections']))]
    def spec(round_index, indices, instruction, required='hit'):
        section = chart['sections'][round_index]
        selected = [rounds[round_index][i] for i in indices]
        start = section['start_ms']
        # Continuous music lessons keep 1.2 seconds of context before the first
        # selected event; call/response lessons retain the entire partner phrase.
        if task in ['han_ju', 'tujia_saye_erhe']:
            start = max(section['start_ms'], selected[0]['time_ms']-1200)
        end = min(section['end_ms'], max(e['end_ms'] for e in selected)+700)
        return start, end, selected, instruction, required
    if task == 'laohekou_si_xian':
        return [spec(0,[0],'圈合上，拨一下'), spec(1,[0,1],'拨、松开、再拨','double'), spec(2,[1,2,3],'拨完停手，听伙伴','rest')]
    if task == 'jingzhou_hua_gu_xi':
        return [spec(0,[1],'轮到你，点一下'), spec(0,[0],'按住，青圈合上时松开','hold'), spec(2,[0,2],'收声后，停手听主唱','hold_rest')]
    if task == 'ti_qin_xi':
        return [spec(0,[1],'跟弓向，轻轻拉一下'), spec(0,[0],'向左按住，青圈合上时松开','hold'), spec(1,[0],'向右长弓，收手就松开','hold')]
    if task == 'tujia_saye_erhe':
        return [spec(0,[0],'左脚落地，按左边'), spec(0,[1],'右脚落地，按右边'), spec(1,[0,1,2],'跟着落步：左、右、右','double'), spec(0,[3,4],'站稳时，两边都松开','rest')]
    if task == 'han_ju':
        return [spec(0,[0],'走到右台，按右边'), spec(0,[3,4],'灯跟到左台，站定就留住','rest')]
    return [spec(0,[0,1,2],'听师傅，接回三下','double'), spec(1,[0,1,2,3],'中间停一拍，再接两下','double')]

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    archive = OUT/'baseline-v2'; archive.mkdir(exist_ok=True)
    manifest = json.loads((ROOT/'InheritanceTasks/Audio/rhythm-v2/manifest.json').read_text(encoding='utf-8'))
    report = []
    for task in IDS:
        baseline = archive/(task+'.json')
        if not baseline.exists():
            current = json.loads((CHARTS/(task+'.json')).read_text(encoding='utf-8'))
            if current['version'] != 2: raise ValueError('Need an explicit v2 baseline for '+task)
            baseline.write_text(json.dumps(current, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
        chart = json.loads(baseline.read_text(encoding='utf-8'))
        samples = decode(ROOT/chart['audio_path'].removeprefix('res://'))
        chart['version'] = 3
        chart['choreography'] = choreography(task, chart)
        chart['tutorial_steps'] = []
        for number, (start, end, events, instruction, required) in enumerate(specifications(task, chart)):
            id_map = {e['id']:f'{task}-lesson-v5-{number}-{i}' for i,e in enumerate(events)}
            local_events = copy.deepcopy(events)
            for e in local_events:
                e['id'] = id_map[e['id']]
                e['time_ms'] -= start; e['end_ms'] -= start
                e['cue_ms'] = min(e['cue_ms'], e['time_ms'])
            local_motion = []
            for c in chart['choreography']:
                if c['end_ms'] <= start or c['start_ms'] >= end: continue
                if c['event_id'] and c['event_id'] not in id_map: continue
                c = copy.deepcopy(c)
                c['start_ms'] = max(start,c['start_ms'])-start
                c['end_ms'] = min(end,c['end_ms'])-start
                c['event_id'] = id_map.get(c['event_id'], '')
                local_motion.append(c)
            local_sections = []
            for s in chart['sections']:
                if s['end_ms'] <= start or s['start_ms'] >= end: continue
                s = copy.deepcopy(s)
                for key in ['start_ms','end_ms','listen_end_ms','response_start_ms']:
                    if key in s: s[key] = max(0,min(end-start,s[key]-start))
                s['teacher_times_ms'] = [t-start for t in s.get('teacher_times_ms',[]) if start <= t < end]
                local_sections.append(s)
            path = OUT/f'{task}-lesson-{number+1}.ogg'
            excerpt = samples[round(start*RATE/1000):round(end*RATE/1000)]
            encode(path, excerpt)
            initial_lane = -1
            for previous in chart['events']:
                if previous['kind']=='switch' and previous['time_ms']<start: initial_lane=previous['direction']
            chart['tutorial_steps'].append(dict(instruction=instruction, retry_hint=instruction, initial_lane=initial_lane,
                required=required, duration_ms=end-start, audio_path='res://'+path.relative_to(ROOT).as_posix(),
                audio_sha256=sha(path), source_mix=chart['audio_path'], source_in_ms=start, source_out_ms=end,
                events=local_events, presentation=copy.deepcopy(local_events), choreography=local_motion, sections=local_sections))
        chart['tutorial_audio_path'] = chart['tutorial_steps'][0]['audio_path']
        chart['annotation_note'] += ' v3：教学复用正式混音片段，伙伴演出独立时间线；既有切句仍待听审。'
        save_resource(task,chart)
        source = next(t for t in manifest['tasks'] if t['task']==task)
        report.append(dict(task=task, mix=chart['audio_path'], mix_sha256=chart['audio_sha256'],
                           edits=source['edits'], natural_phrase_review='pending', listening_review=False,
                           steps=[{k:v for k,v in s.items() if k not in ['events','presentation','choreography','sections']} for s in chart['tutorial_steps']]))
    (OUT/'manifest.json').write_text(json.dumps(dict(version=3, status='teaching_and_choreography_implemented_phrase_cuts_pending', tasks=report),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps([dict(task=r['task'],lessons=len(r['steps'])) for r in report]))

if __name__=='__main__': main()
