import React from 'react';
import {AbsoluteFill,Audio,Composition,Img,OffthreadVideo,Sequence,staticFile} from 'remotion';
import plan from './timeline.json';
const Caption: React.FC<{text:string}> = ({text}) => <div style={{position:'absolute',left:0,right:0,top:960,textAlign:'center',fontSize:48,color:'white',WebkitTextStroke:'3px black',paintOrder:'stroke fill',textShadow:'1px 2px black'}}>{text}</div>;
const Shot:React.FC<{s:any}>=({s})=>{
 if(s.take==='outro') return <AbsoluteFill style={{background:'#21170f'}}>
  <Img src={staticFile('logo.png')} style={{position:'absolute',left:180,top:180,width:600,height:600}}/>
  <div style={{position:'absolute',left:890,top:250,color:'#f5d39a',fontSize:72}}>从武汉出发</div>
  <div style={{position:'absolute',left:890,top:370,color:'#f5d39a',fontSize:72}}>走进荆楚非遗</div>
  <div style={{position:'absolute',left:900,top:550,color:'#f3e4c5',fontSize:36}}>湖北非遗文化主题桌游</div>
  <div style={{position:'absolute',left:900,top:640,color:'#f3e4c5',fontSize:36}}>小红花赛道 · 参赛作品</div>
  <Caption text={s.caption}/>
 </AbsoluteFill>;
 const scale=s.tv?1920/1280:1;
 const mediaStyle:React.CSSProperties={position:'absolute',width:1920*scale,height:1080*scale,left:s.tv?-320*scale:0,top:s.tv?-175*scale:0};
 return <AbsoluteFill style={{background:'#17120d'}}>
  <div style={{position:'absolute',left:0,top:0,width:1920,height:1080,overflow:'hidden'}}>
   {s.still?<Img src={staticFile(s.asset)} style={mediaStyle}/>:<OffthreadVideo src={staticFile(s.asset)} startFrom={Math.round(s.start*60)} endAt={Math.round((s.start+s.duration)*60)} style={mediaStyle}/>}
  </div>
  <div style={{position:'absolute',left:110,top:20,width:Math.min(500,Math.max(136,s.city.length*32+44)),height:60,boxSizing:'border-box',background:'#21160dcc',color:'#f5d39a',fontSize:32,padding:'7px 22px'}}>{s.city}</div>
  <Caption text={s.caption}/>
 </AbsoluteFill>;
};
export const Promo:React.FC=()=> <AbsoluteFill style={{fontFamily:'PromoSans',background:'#17120d'}}>
 <style>{`@font-face{font-family:PromoSans;src:url('${staticFile('pixel.ttf')}')}`}</style>
 {plan.shots.map((s)=><Sequence key={s.index} from={Math.round(s.from_seconds*60)} durationInFrames={Math.round(s.duration*60)}><Shot s={s}/></Sequence>)}
 <Audio src={staticFile('bgm.mp3')} volume={(f)=>{const t=f/60;return t<118?.22:t<120?.22*(120-t)/2:t<130?0:t<132?.22*(t-130)/2:t<147?.22:Math.max(0,.22*(150-t)/3)}}/>
</AbsoluteFill>;
export const PromoComposition=()=> <Composition id="ChuwuzhiPromo" component={Promo} durationInFrames={9000} fps={60} width={1920} height={1080}/>;
