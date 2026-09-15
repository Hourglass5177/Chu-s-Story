"""Package timestamped Godot frames at original speed, without synthetic motion."""
from pathlib import Path
import html
import json
import subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/music-motion-v4'
FF = ROOT / 'artifacts/media-20260909/toolchain/ffmpeg-9.0.1-essentials_build/bin/ffmpeg.exe'
NAMES = {'laohekou_si_xian':'丝弦 · 双拨', 'tujia_saye_erhe':'撒叶儿嗬 · 左脚落步',
         'jingzhou_hua_gu_xi':'花鼓戏 · 按住与收声', 'han_ju':'汉剧 · 右台追光',
         'ti_qin_xi':'提琴戏 · 长弓收尾', 'gu_pen_ge':'鼓盆歌 · 听句复现'}
cards = []
summary = []
for task, title in NAMES.items():
    folder = OUT / task
    report = json.loads((folder/'report.json').read_text(encoding='utf-8'))
    assert report['practice_step_completed'], task
    frames = report['frames']
    # ViewportTexture.get_size can report logical units under canvas stretch;
    # record the actual exported image dimensions from the captured file.
    report['captured_image_size'] = list(Image.open(folder/frames[0]['file']).size)
    (folder/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    times = [f['time_ms'] for f in frames]
    assert len(frames) > 10 and all(b > a for a,b in zip(times,times[1:])), task
    lines = []
    for i, frame in enumerate(frames):
        end = times[i+1] if i+1 < len(times) else report['lesson']['duration_ms']
        lines += [f"file '{frame['file']}'", f'duration {max(.001,(end-times[i])/1000):.6f}']
    lines += [f"file '{frames[-1]['file']}'"]
    (folder/'frames.ffconcat').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    subprocess.run([str(FF),'-v','error','-y','-f','concat','-safe','0','-i',str(folder/'frames.ffconcat'),
                    '-an','-c:v','libx264','-crf','18','-pix_fmt','yuv420p','-r','30','-movflags','+faststart',
                    str(folder/'practice.mp4')],check=True)
    gaps = [b-a for a,b in zip(times,times[1:])]
    summary.append({'task':task, 'captured_frames':len(frames), 'max_frame_interval_ms':max(gaps),
                    'source_time_start_ms':times[0], 'video_audio':'silent',
                    'normal_inputs':report['inputs'], 'user_accepted':False})
    cards.append(f'''<section data-task="{task}"><h2>{title}</h2><canvas width="{report['captured_image_size'][0]}" height="{report['captured_image_size'][1]}" aria-label="{title}实际画面"></canvas><div class="controls"><button class="play">播放原速画面</button><button class="previous">上一帧</button><button class="next">下一帧</button><input class="seek" type="range" min="0" max="{report['lesson']['duration_ms']}" value="0" step="1" aria-label="{title}画面时间"><output>准备画面</output></div><p>{html.escape(report['lesson']['instruction'])}</p><p class="small">当前工程键盘练手过程 · 原速 · 无声画面回放<br><a href="{task}/report.json">帧时刻与输入记录</a> · <a href="{task}/practice.mp4">MP4 文件</a></p></section>''')

(OUT/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(OUT/'index.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>楚物志 · 六音游当前工程动作</title><style>body{margin:0;background:#201e1b;color:#f5ead2;font:20px/1.5 system-ui,"Microsoft YaHei",sans-serif}main{max-width:1320px;margin:auto;padding:30px}h1{font-size:32px}h2{font-size:24px}section{margin:28px 0;padding:20px;background:#38342c;border:1px solid #746449;border-radius:12px}video{display:block;width:100%;background:#111;border-radius:8px}a{color:#b4e5d0}.small{font-size:17px;color:#cfc4ac}.note{padding:18px;background:#35463f;border-radius:10px}</style><main><h1>六音游 · 当前工程动作</h1><p class="note">这些是实际 Godot 教学练手画面，按原音频时刻播放。没有补画插帧、修改得分或注入姿势。截图采样率低于游戏渲染帧率，不能用它判断稳定帧率。<br>视频仅查看动作；声音请到<a href="../../tools/rhythm_review.html">乐句与操作审查页</a>对应试听。切句听审、连续运弓及用户画面验收仍未完成。</p>'''+''.join(cards)+'''<p><a href="../dong-v8-frame-review/index.html">董永 v8 推车与制动短循环（仍待用户试看）</a></p></main></html>''',encoding='utf-8')
print(json.dumps(summary, ensure_ascii=False))

# The in-app browser's native video surface can close on H.264 playback. Use
# actual timestamped captures directly; this never interpolates or redraws poses.
page = OUT/'index.html'
markup = page.read_text(encoding='utf-8').replace('video{display:block;', 'canvas{display:block;')
markup = markup.replace('</style>', '.controls{display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin-top:12px}button{font:inherit;padding:8px 15px;min-height:46px;color:#f5ead2;background:#4b5f51;border:1px solid #9db29d;border-radius:6px}input[type=range]{flex:1;min-width:180px}output{min-width:130px}</style>')
markup += '<script>'+(ROOT/'tools/music_motion_player.js').read_text(encoding='utf-8')+'</script>'
page.write_text(markup,encoding='utf-8')
