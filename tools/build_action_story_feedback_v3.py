"""Small original game-feedback sounds; these are not traditional instrument samples."""
from pathlib import Path
import hashlib,json,wave
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'InheritanceTasks/Audio/action-story-v3'
RATE=24000
rng=np.random.default_rng(240914)
records=[]

def noise(t,width=5):
    return np.convolve(rng.normal(0,1,len(t)),np.ones(width)/width,mode='same')

def save(name,t,x,note):
    x=np.asarray(x)*np.minimum(1,t/.008)*np.minimum(1,(t[-1]-t)/.018)
    x=x/max(.01,np.abs(x).max())*.58
    path=DEST/(name+'.wav')
    with wave.open(str(path),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE)
        f.writeframes((np.clip(x,-1,1)*32767).astype('<i2').tobytes())
    records.append({'file':path.name,'seconds':len(t)/RATE,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'description':note,'source':'Original deterministic digital synthesis; game feedback, not heritage recording.'})

def build():
    DEST.mkdir(parents=True,exist_ok=True)
    for success in [True,False]:
        end='good' if success else 'miss'
        t=np.arange(int(RATE*(.16 if success else .24)))/RATE
        ring=np.sin(2*np.pi*(510 if success else 190)*t)+.4*np.sin(2*np.pi*830*t)
        save('puzzle-'+end,t,(ring*.25+noise(t,3)*.12)*np.exp(-23*t),'Soft wooden tile contact' if success else 'Dull tile stop')
        t=np.arange(int(RATE*.24))/RATE
        save('paper-'+end,t,(noise(t,2)-noise(t,12))*.15*np.sin(np.pi*t/t[-1])**2,'Short paper release and knife scrape')
        t=np.arange(int(RATE*.34))/RATE
        phase=2*np.pi*(160*t+210*t*t)
        save('cart-'+end,t,(np.sin(phase)*.13+np.sin(phase*2.7)*.025+noise(t,8)*.05)*np.exp(-5*t),'Wooden cart settling / brake creak')
        t=np.arange(int(RATE*.32))/RATE
        splash=noise(t,10)*(1-t/t[-1])**2
        droplets=np.sin(2*np.pi*(920*t-750*t*t))*.07*np.exp(-12*t)
        save('boat-'+end,t,splash*.3+droplets,'Gentle water settling' if success else 'Short collision splash')
    (DEST/'sources.json').write_text(json.dumps({'version':3,'assets':records},ensure_ascii=False,indent=2),encoding='utf8')

if __name__=='__main__':build()
