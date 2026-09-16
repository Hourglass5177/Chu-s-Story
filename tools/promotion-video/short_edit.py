"""118-second submission cut from rendered, user-captioned footage. No speed changes."""
import edit,json
P=edit.P; S=P/'shots-board-v3'; D=P/'shots-submit-118';D.mkdir(exist_ok=True)
durations=[5,5,12,6,4,4,7,4,6,11,8,10,8,3,10,5,3,7]
offsets=[0,0,0,0,0,0,0,0,0,1,3,0,0,0,0,0,0,0]
assert sum(durations)==118
for i,(duration,offset) in enumerate(zip(durations,offsets)):
 print('Short cut',i,flush=True)
 edit.run(['-ss',offset,'-i',S/f'{i:02}.mp4','-t',duration,'-c:v','h264_nvenc','-preset','p4','-cq','18','-b:v','0','-pix_fmt','yuv420p','-c:a','aac','-b:a','256k',D/f'{i:02}.mp4'])
concat=D/'concat.txt';concat.write_text(''.join("file '"+str(D/f'{i:02}.mp4').replace('\\','/')+"'\n" for i in range(18)),encoding='utf8')
joined=D/'joined.mp4';edit.run(['-f','concat','-safe','0','-i',concat,'-c','copy',joined])
final=edit.OUT/'楚物志_楚行九州_参赛宣传视频_1分58秒.mp4'
envelope="if(lt(t,91),0.22,if(lt(t,93),0.22*(93-t)/2,if(lt(t,103),0,if(lt(t,105),0.22*(t-103)/2,if(lt(t,115),0.22,0.22*(118-t)/3)))))"
edit.run(['-i',joined,'-i',edit.R/'Audio/Music/chuwuzhi-bgm.mp3','-filter_complex',f"[1:a]atrim=0:118,volume='{envelope}':eval=frame[b];[0:a][b]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95:level=false[a]",'-map','0:v','-map','[a]','-t','118','-c:v','copy','-c:a','aac','-b:a','256k','-ar','48000','-movflags','+faststart',final])
(D/'timeline.json').write_text(json.dumps({'duration':118,'durations':durations,'offsets':offsets,'source':'shots-board-v3','speed':1},indent=2),encoding='utf8')
print(final,flush=True)
