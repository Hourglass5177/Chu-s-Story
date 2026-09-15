"""Probe, sparsely sample, and export the user-supplied 2026-09-09 media batch.

Original files are read only. Derived assets are defined by explicit cut points.
"""
import argparse
import concurrent.futures
import hashlib
import html
import json
import math
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path('F:/Videos/resource')
WORK = ROOT / 'artifacts/media-20260909'
DEST = ROOT / 'arts/非遗媒体资源/数字版/2026-09-09'
FFMPEG = WORK / 'toolchain/ffmpeg-9.0.1-essentials_build/bin/ffmpeg.exe'
FFPROBE = FFMPEG.with_name('ffprobe.exe')
ITEMS = [
    ('laohekou', 'Laohekou', '老河口丝弦'),
    ('sayeerhe', '中国民歌大会', '土家族撒叶儿嗬'),
    ('xingshan', '兴山民歌', '兴山民歌'),
    ('jingzhou', '荆州花鼓戏', '荆州花鼓戏'),
    ('hanju', '汉剧陈派', '汉剧'),
    ('tiqin', 'Tiqin', '提琴戏'),
]
CANDIDATES = [
    ('laohekou', 'laohekou-ensemble-v1', 72, 114, False),
    ('sayeerhe', 'sayeerhe-stage-v1', 22, 64, True),
    ('xingshan', 'xingshan-xiatianhaozi-v1', 1, 44, False),
    ('jingzhou', 'jingzhou-zhanhuaqiang-v1', 291, 333, True),
    ('hanju', 'hanju-congtaibie-v1', 1800, 1842, False),
    ('hanju', 'hanju-yuzhoufeng-v1', 2330, 2372, False),
    ('tiqin', 'tiqin-stage-v1', 244, 286, True),
]
NOTES = {
    'laohekou': '合奏及乐器配置参考；未分离声部，接力提示与节拍仍需编谱。',
    'sayeerhe': '电视舞台版本，有鼓手、全身舞蹈和近景切换；不等于连续脚步教学或田野仪式记录。',
    'xingshan': '曲名取自原文件《下田号子》；保留原调原速，完整歌词与旋律提示点待核对。',
    'jingzhou': '《站花墙》舞台对唱参考；不能仅凭两位演员认定为主唱与帮腔，帮腔段落待听审。',
    'hanju': '曲目由画面题签确认；未将片段擅自标为西皮或二黄，声腔、板式和谱面待听审。',
    'tiqin': '提供唱腔及舞台表演参考；所选片段没有乐队或运弓近景，不能用于确定真实运弓动作。',
}

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def measure(path, start=None, duration=None):
    import numpy as np
    cmd = [FFMPEG, '-v', 'error']
    if start is not None:
        cmd += ['-ss', start]
    cmd += ['-i', path]
    if duration is not None:
        cmd += ['-t', duration]
    cmd += ['-vn', '-ar', 44100, '-ac', 2, '-f', 'f32le', 'pipe:1']
    samples = np.frombuffer(run(cmd).stdout, dtype='<f4')
    peak = float(np.max(np.abs(samples)))
    rms = float(np.sqrt(np.mean(samples.astype('float64')**2)))
    return dict(peak_dbfs=round(20*math.log10(max(peak, 1e-12)), 3),
                rms_dbfs=round(20*math.log10(max(rms, 1e-12)), 3),
                clipped_sample_count=int(np.sum(np.abs(samples) >= 1.0)),
                decoded_duration=len(samples)/88200)

def export_one(cut, sources):
    source = sources[cut['source_id']]
    path = source['source']
    duration = cut['duration']
    before = measure(path, cut['start'], duration)
    gain = min(0, -3-before['peak_dbfs'])
    af = f'volume={gain:.4f}dB,afade=t=in:d=0.01,afade=t=out:st={duration-.025:.6f}:d=0.025'
    common = [FFMPEG, '-v', 'error', '-y', '-ss', cut['start'], '-i', path, '-t', duration, '-map_metadata', '-1']
    audio_args = ['-af', af, '-ar', 44100, '-ac', 2, '-c:a', 'libvorbis', '-q:a', 6]
    ogg = DEST / (cut['name']+'.ogg')
    run(common + ['-map', '0:a:0', '-vn'] + audio_args + [ogg])
    outputs = [ogg]
    if cut['video']:
        ogv = DEST / (cut['name']+'.ogv')
        run(common + ['-map', '0:v:0', '-map', '0:a:0', '-c:v', 'libtheora', '-q:v', 7,
                      '-g:v', 64, '-pix_fmt', 'yuv420p', '-threads', 2] + audio_args + [ogv])
        outputs.append(ogv)
        # Browser review copies stay outside the game's asset directory.
        run(common + ['-map', '0:v:0', '-map', '0:a:0', '-c:v', 'libx264', '-crf', 21,
                      '-preset', 'fast', '-pix_fmt', 'yuv420p', '-threads', 2,
                      '-af', af, '-ar', 44100, '-ac', 2, '-c:a', 'aac', '-b:a', '192k',
                      '-movflags', '+faststart', WORK / (cut['name']+'.mp4')])
    verified = []
    for output in outputs:
        info = probe(output)
        run([FFMPEG, '-v', 'error', '-xerror', '-i', output, '-f', 'null', '-'])
        after = measure(output)
        if abs(after['decoded_duration']-duration) > .15 or after['clipped_sample_count']:
            raise ValueError(f'Duration/clipping validation failed: {output}: {after}')
        verified.append(dict(path=output.relative_to(ROOT).as_posix(), sha256=digest(output),
                             size=output.stat().st_size, probe=info, audio_metrics=after,
                             complete_decode_passed=True))
    result = dict(**cut, title=source['title'], notes=NOTES[cut['source_id']],
                  status='prepared_candidate_not_integrated_or_phrase_audited',
                  source_audio_metrics=before, gain_db=round(gain, 4), outputs=verified)
    print(json.dumps(dict(name=cut['name'], duration=duration, gain_db=gain,
                          total_bytes=sum(o['size'] for o in verified), verified=True)), flush=True)
    return result

def export():
    sources_list = json.loads((WORK / 'sources.json').read_text(encoding='utf-8'))
    sources = {s['id']: s for s in sources_list}
    for source in sources_list:
        if digest(Path(source['source'])) != source['sha256']:
            raise ValueError(f'Source changed since inspection: {source["source"]}')
    cuts = json.loads((WORK / 'cuts.json').read_text(encoding='utf-8'))
    DEST.mkdir(parents=True, exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda c: export_one(c, sources), cuts))
    manifest = dict(batch_date='2026-09-09', authorization={
        'source': '用户在当前 Codex 任务中的明确说明',
        'statement': '这些视频全部获得了授权；全部都是视频，只需音频的请你自己提取为音频；只截取需要的段落。',
        'originals_preserved': True},
        selection_review='稀疏抽帧与短区间音频能量分析；未进行完整人工听审，不保证乐句边界、声腔分类或鼓点谱面已确定。',
        processing=dict(tool=run([FFMPEG, '-version']).stdout.decode().splitlines()[0],
                        sample_rate=44100, channels=2, audio_codec='Vorbis q6',
                        video_codec='Theora q7, GOP64, source 1280x720 and source frame rate',
                        gain_policy='Only attenuate to leave 3 dB source sample-peak headroom; do not boost quiet passages',
                        fade_in_seconds=.01, fade_out_seconds=.025,
                        pitch_shift=False, time_stretch=False, denoise=False, stems=False),
        sources=sources_list, clips=results)
    dump(DEST / 'manifest.json', manifest)
    sections = []
    from urllib.parse import quote
    for c in results:
        src = '../../'+c['outputs'][0]['path']
        media = (f'<video controls preload="none" src="{c["name"]}.mp4"></video>' if c['video'] else
                 f'<audio controls preload="none" src="{quote(src)}"></audio>')
        sections.append(f'<article><h2>{html.escape(c["title"])}</h2><p>{c["name"]}<br>'
                        f'原片 {c["start"]:.3f}–{c["end"]:.3f} 秒 · {c["duration"]:.2f} 秒</p>'
                        f'{media}<p>{html.escape(c["notes"])}</p>'
                        f'<details><summary>抽样画面</summary><img src="{c["name"]}-detail.jpg"></details></article>')
    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>楚物志 · 传承素材试听</title><style>body{background:#171c1a;color:#efe9da;font:16px/1.7 system-ui;margin:32px auto;max-width:1100px;padding:0 20px}h1{font-size:28px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));gap:20px}article{background:#26312d;border:1px solid #566657;border-radius:12px;padding:20px}h2{margin:0;color:#eac888}p{color:#d2d7ce}audio,video,img{width:100%}summary{cursor:pointer}</style>
<h1>楚物志 · 传承素材试听</h1><p>2026-09-09 · 6 个来源，7 段候选。保留原调原速，原文件未改动。<br>用于下一步编谱与动作参考；乐句切点、帮腔和声腔分类尚待听审。</p><main>'''+''.join(sections)+'</main></html>'
    (WORK / 'review.html').write_text(page, encoding='utf-8')
    print('MANIFEST '+str(DEST / 'manifest.json'))

def plan():
    import numpy as np
    from PIL import Image, ImageDraw
    sources = {s['id']: s for s in json.loads((WORK / 'sources.json').read_text(encoding='utf-8'))}
    result = []
    for key, name, nominal_start, nominal_end, video in CANDIDATES:
        source = sources[key]
        path = source['source']
        # Seek only around the selected passage; never decode the full long program.
        offset = max(0, nominal_start-3)
        length = min(source['duration'], nominal_end+3)-offset
        raw = run([FFMPEG, '-v', 'error', '-ss', offset, '-i', path, '-t', length,
                   '-vn', '-ar', 8000, '-ac', 1, '-f', 'f32le', 'pipe:1']).stdout
        samples = np.frombuffer(raw, dtype='<f4')
        block = 400
        rms = np.sqrt(np.mean(samples[:len(samples)//block*block].reshape(-1, block)**2, axis=1))
        ts = offset + (np.arange(len(rms))+.5)*.05
        cuts = []
        for nominal in [nominal_start, nominal_end]:
            region = np.flatnonzero((ts >= max(.05, nominal-1.5)) & (ts <= min(source['duration']-.1, nominal+1.5)))
            selected = region[np.argmin(rms[region])]
            cuts.append(round(float(ts[selected]), 3))
        start, end = cuts
        times = [round(float(t), 3) for t in np.linspace(start, end-.1, 8)]
        sheet = Image.new('RGB', (1280, 408), '#202020')
        draw = ImageDraw.Draw(sheet)
        for i, sec in enumerate(times):
            jpg = WORK / f'{name}-detail-{i}.jpg'
            run([FFMPEG, '-v', 'error', '-y', '-ss', sec, '-i', path, '-frames:v', 1, '-vf', 'scale=320:180', jpg])
            with Image.open(jpg) as frame:
                x, y = i%4*320, i//4*204
                sheet.paste(frame, (x, y))
                draw.text((x+5, y+184), f'{sec:.3f}s', fill='white')
        sheet.save(WORK / f'{name}-detail.jpg')
        record = dict(source_id=key, name=name, start=start, end=end, duration=round(end-start, 3),
                      video=video, reviewed_frame_seconds=times,
                      cut_method='Local 50 ms RMS minimum within 1.5 seconds of each nominal boundary; not a semantic phrase detector')
        result.append(record)
    dump(WORK / 'cuts.json', result)
    print(json.dumps(result, ensure_ascii=False, indent=2))

def run(args):
    result = subprocess.run([str(a) for a in args], capture_output=True)
    if result.returncode:
        raise RuntimeError(f'Command failed ({result.returncode}): {args}\n{result.stderr.decode("utf-8", errors="replace")}')
    return result

def probe(path):
    return json.loads(run([FFPROBE, '-v', 'error', '-show_format', '-show_streams', '-of', 'json', path]).stdout)

def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def inspect_one(item):
    from PIL import Image, ImageDraw
    key, pattern, title = item
    matches = [p for p in SOURCE.glob('*.mp4') if pattern in p.name]
    if len(matches) != 1:
        raise ValueError(f'{pattern}: expected one source, found {matches}')
    path = matches[0]
    info = probe(path)
    duration = float(info['format']['duration'])
    times = [round(duration * f, 2) for f in (.35, .45, .55, .65)]
    sheet = Image.new('RGB', (960, 588), '#202020')
    draw = ImageDraw.Draw(sheet)
    for i, sec in enumerate(times):
        jpg = WORK / f'{key}-{i}.jpg'
        run([FFMPEG, '-hide_banner', '-loglevel', 'error', '-y', '-ss', sec, '-i', path,
             '-frames:v', 1, '-vf', 'scale=480:270:force_original_aspect_ratio=decrease', jpg])
        with Image.open(jpg) as frame:
            x, y = (i % 2)*480, (i // 2)*294
            sheet.paste(frame, (x, y))
            draw.text((x+8, y+272), f'{key}  {sec:.2f}s / {duration:.2f}s', fill='white')
    sheet.save(WORK / f'{key}-samples.jpg')
    sha = digest(path)
    result = dict(id=key, title=title, source=str(path), size=path.stat().st_size,
                  sha256=sha, duration=duration, sampled_seconds=times, probe=info)
    print(json.dumps({k:v for k,v in result.items() if k != 'probe'}, ensure_ascii=False), flush=True)
    return result

def main():
    global FFMPEG, FFPROBE
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['inspect', 'plan', 'export'])
    parser.add_argument('--ffmpeg', type=Path, help='Override FFmpeg; sibling ffprobe.exe must be present')
    args = parser.parse_args()
    if args.ffmpeg:
        FFMPEG = args.ffmpeg.resolve()
        FFPROBE = FFMPEG.with_name('ffprobe.exe')
    WORK.mkdir(parents=True, exist_ok=True)
    if args.mode == 'export':
        export()
        return
    if args.mode == 'plan':
        plan()
        return
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(inspect_one, ITEMS))
    dump(WORK / 'sources.json', results)

if __name__ == '__main__':
    main()
