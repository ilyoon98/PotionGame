/** Pixelbolt 0.11.0: preserve the aligned brewer while authoring a flask-shaking action. */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { renderProject, importPNG, decodePNG, encodePNG, animationGIF, framesGIF, formatJSON } from './pixelbolt/node_modules/pixelbolt/src/index.js';

const ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const OUT=path.join(ROOT,'art/mockups/f25-staff-flask-v1');
const ALIGNED=path.join(ROOT,'art/mockups/f25-staff-alignment-v1');
const CLI=path.join(ROOT,'tools/pixelbolt/node_modules/pixelbolt/bin/pixelbolt.js');
const read=p=>JSON.parse(fs.readFileSync(p,'utf8'));
const json=(p,v)=>fs.writeFileSync(p,JSON.stringify(v,null,2)+'\n');
const rel=p=>path.relative(ROOT,p).replaceAll('\\','/');
const hash=b=>createHash('sha256').update(b).digest('hex');
const quick=process.argv.includes('--quick');
for(const d of ['recipes','exports','reviews','logs','pipeline','references'])fs.mkdirSync(path.join(OUT,d),{recursive:true});
if(read(path.join(ROOT,'tools/pixelbolt/node_modules/pixelbolt/package.json')).version!=='0.11.0')throw Error('Requires Pixelbolt 0.11.0');
json(path.join(OUT,'validation.json'),{status:'building',runtime_integrated:false,approved_by_user:false});
fs.copyFileSync(path.join(ROOT,'tools/pixelbolt/node_modules/pixelbolt/LICENSE'),path.join(OUT,'PIXELBOLT-LICENSE.txt'));
const legend=read(path.join(ROOT,'art/mockups/f25-staff-motion-v1/source/generation.json')).legend;
const palette=Object.fromEntries(Object.entries(legend).map(([k,v])=>[k,v.color]));
const approved=new Set(fs.readFileSync(path.join(ROOT,'art/palette.hex'),'utf8').trim().split(/\r?\n/).map(c=>'#'+c.toUpperCase()));
const grid=p=>{const rows=fs.readFileSync(p,'utf8').trimEnd().split(/\r?\n/);if(rows.length!==48||rows.some(r=>r.length!==32))throw Error('Invalid 32x48 source: '+p);return rows;};
const baseFile=path.join(ALIGNED,'source/staff_brewing_assistant.txt');
const originalRows=grid(baseFile);
const notes=read(path.join(OUT,'source/poses.json'));
const poseNames=['rest','prepare','lift','shake_left','shake_right'];
const rows=Object.fromEntries(poseNames.map(id=>[id,grid(path.join(OUT,'source',id+'.txt'))]));
if(rows.rest.join('\n')!==originalRows.join('\n'))throw Error('Aligned resting pose changed');
const sections=[['rest',900],['prepare',220],['lift',280]];
for(let n=0;n<3;n++)sections.push(['shake_left',160],['lift',100],['shake_right',160],['lift',100]);
sections.push(['lift',340],['prepare',260],['rest',2440]);
let end=0;const timeline=sections.map(([pose,duration])=>{const entry={pose,duration,start:end};end+=duration;return entry;});
const LENGTH=end;
if(LENGTH!==6000)throw Error('Action must complete in six seconds');
const recipe={version:1,name:'staff_brewing_flask',width:32,height:48,palette,anchor:[14,46],frames:poseNames.map(name=>({name,duration:1000,ops:[{op:'grid',rows:rows[name]}]})),animations:{still:{frames:['rest'],loop:true},shake:{frames:timeline.map((_,i)=>'action_'+i),loop:false}},sheet:{columns:5,scale:1,trim:false}};
recipe.frames.push(...timeline.map((p,i)=>({name:'action_'+i,from:p.pose,duration:p.duration})));
const rendered=renderProject(recipe),base=rendered.frames[0];
const masks=read(path.join(ALIGNED,'source/alignment-notes.json')).assets.staff_brewing_assistant.semantic_masks;
const protectedParts=['neck','torso_core','waist','hip','left_leg','right_leg','left_hand'];
const color=(f,x,y)=>{const i=(y*f.width+x)*4;return f.data[i+3]?'#'+[...f.data.slice(i,i+3)].map(c=>c.toString(16).padStart(2,'0')).join('').toUpperCase():'transparent';};
const frame=f=>({...f,width:32,height:48});
const original=frame(base);
const allowed=(x,y)=>x>=17&&x<=28&&y>=27&&y<=38;
const reports=[];
for(const raw of rendered.frames){
  const f=frame(raw),colors=new Set();let changes=0,boundary=0,alpha=0;
  for(let y=0;y<48;y++)for(let x=0;x<32;x++){
    const c=color(f,x,y),a=f.data[(y*32+x)*4+3];
    if(c!==color(original,x,y)){changes++;if(!allowed(x,y))throw Error(f.name+': changed protected pixel '+x+','+y);}
    if(a!==0&&a!==255)alpha++;
    if(c==='transparent')continue;colors.add(c);
    if([[x-1,y],[x+1,y],[x,y-1],[x,y+1]].some(([xx,yy])=>xx<0||xx>=32||yy<0||yy>=48||color(f,xx,yy)==='transparent')&&c!=='#241C32')boundary++;
  }
  for(const part of protectedParts)for(const[y,x0,x1]of masks[part].runs)for(let x=x0;x<=x1;x++)if(color(f,x,y)!==color(original,x,y))throw Error(f.name+': moved '+part+' at '+x+','+y);
  if(colors.size>5||alpha||boundary||[...colors].some(c=>!approved.has(c)))throw Error(JSON.stringify({frame:f.name,colors:[...colors],alpha,boundary}));
  reports.push({frame:f.name,changed_pixels:changes,colors:colors.size,outline_errors:boundary,partial_alpha:alpha,protected_body_unchanged:true});
}
if(Buffer.compare(Buffer.from(rendered.frames.at(-1).data),Buffer.from(base.data)))throw Error('Action does not return to aligned rest');
const contactReports=[];
const expand=runs=>runs.flatMap(([y,x0,x1])=>Array.from({length:x1-x0+1},(_,i)=>[x0+i,y]));
const key=(x,y)=>x+','+y;
const neighbors=(x,y)=>[[x-1,y],[x+1,y],[x,y-1],[x,y+1]];
for(const state of notes.states){
  const f=frame(rendered.frames.find(f=>f.name===state.id));
  if(hash(fs.readFileSync(path.join(OUT,'source',state.file)))!==state.sha256)throw Error('Stale source hash: '+state.id);
  const hand=expand(state.hand_skin_runs),bottle=expand(state.flask_mask_runs),bottleSet=new Set(bottle.map(([x,y])=>key(x,y)));
  if(hand.length!==4||hand.some(([x,y])=>color(f,x,y)!==palette.s)||color(f,...state.grip)!==palette.s)throw Error(state.id+': hand material mismatch');
  if(!neighbors(...state.grip).some(([x,y])=>bottleSet.has(key(x,y))&&color(f,x,y)===palette['#']))throw Error(state.id+': hand loses the flask');
  if(bottle.some(([x,y])=>![palette['#'],palette.m,palette.R].includes(color(f,x,y))))throw Error(state.id+': flask mask material mismatch');
  if(bottle.filter(([x,y])=>color(f,x,y)===palette.R).length!==13)throw Error(state.id+': liquid amount changed');
  if(color(f,...state.flask_neck)!==palette.m)throw Error(state.id+': flask neck lost');
  for(let x=state.cap_center[0]-1;x<=state.cap_center[0]+1;x++)if(color(f,x,state.cap_center[1])!==palette['#'])throw Error(state.id+': open or broken cap');
  const reached=new Set(),queue=[bottle[0]];
  while(queue.length){const[x,y]=queue.pop(),k=key(x,y);if(reached.has(k)||!bottleSet.has(k))continue;reached.add(k);queue.push(...neighbors(x,y));}
  if(reached.size!==bottle.length)throw Error(state.id+': disconnected bottle');
  for(const[x,y]of bottle)for(let yy=y-1;yy<=y+1;yy++)for(let xx=x-1;xx<=x+1;xx++)if(yy<=26&&yy>=0&&xx>=0&&xx<32&&color(f,xx,yy)!=='transparent')throw Error(state.id+': bottle touches head');
  // Exclude the bottle to ensure it cannot hide a disconnected wrist.
  const seen=new Set(),bodyQueue=[state.grip];let sleeveConnected=false;
  while(bodyQueue.length){const[x,y]=bodyQueue.pop(),k=key(x,y);if(x<0||x>=32||y<0||y>=48||seen.has(k)||bottleSet.has(k)||color(f,x,y)==='transparent')continue;seen.add(k);if(x===16&&y>=29&&y<=36)sleeveConnected=true;bodyQueue.push(...neighbors(x,y));}
  if(!sleeveConnected)throw Error(state.id+': wrist disconnected from fixed sleeve');
  contactReports.push({pose:state.id,grip:state.grip,neck:state.flask_neck,cap:state.cap_center,hand_pixels:hand.length,liquid_pixels:13,flask_connected:true,wrist_connected_without_flask:true,head_clearance:true});
}
function run(command,args,label){const p=spawnSync(process.execPath,[CLI,command,...args,...(command==='validate'?[]:['--force'])],{cwd:ROOT,encoding:'utf8',maxBuffer:20*1024*1024});if(p.status!==0)throw Error(p.stderr||p.stdout);json(path.join(OUT,'logs',label+'.json'),JSON.parse(p.stdout.replaceAll(ROOT.replaceAll('\\','\\\\'),'.').replaceAll(ROOT.replaceAll('\\','/'),'.')));}
const recipeFile=path.join(OUT,'recipes/staff.json');fs.writeFileSync(recipeFile,formatJSON(recipe));run('validate',[recipeFile],'staff-validate');
const expectation=path.join(OUT,'recipes/staff.expect.json');json(expectation,{width:32,height:48,frames:timeline.length,colors:5,transparent:true,loop:false});
run('render',[recipeFile,'--out',path.join(OUT,'exports/staff'),'--animation','shake','--expect',expectation],'staff-render');
run('inspect',[recipeFile,'--frames',poseNames.join(','),'--out',path.join(OUT,'reviews/keyposes.png'),'--native','--scale','3'],'keyposes');
run('inspect',[recipeFile,'--animation','shake','--view','onion','--out',path.join(OUT,'reviews/onion.png'),'--scale','3'],'onion');
run('inspect',[recipeFile,'--frames',poseNames.join(','),'--view','silhouette','--out',path.join(OUT,'reviews/silhouette.png'),'--scale','3'],'silhouette');
const loopRecipe=structuredClone(recipe);loopRecipe.animations.shake.loop=true;
const solo=animationGIF(renderProject(loopRecipe),'shake',{scale:3});fs.writeFileSync(path.join(OUT,'flask-shake-3x.gif'),solo.data);

// Apply the existing material-aware pipeline; no global color quantization is permitted.
const sourceManifest=read(path.join(ROOT,'art/mockups/f25-staff-motion-v1/source/original-manifest.json'));
const material=sourceManifest.assets.find(a=>a.id==='staff_brewing_assistant');
const manifest={...sourceManifest,feature:'F25 staff flask action',output:rel(path.join(OUT,'pipeline')),assets:recipe.frames.map(f=>({...material,id:f.name,source:rel(path.join(OUT,'exports/staff/frames',f.name+'.png')),position:[0,0]}))};
json(path.join(OUT,'manifest.json'),manifest);
const bundled=path.join(process.env.USERPROFILE||'','.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe');
const pipeline=spawnSync(process.env.PYTHON||(fs.existsSync(bundled)?bundled:'python'),['tools/process_pixel_art.py',rel(path.join(OUT,'manifest.json'))],{cwd:ROOT,encoding:'utf8'});
if(pipeline.status!==0)throw Error(pipeline.stdout+pipeline.stderr);
for(const f of rendered.frames){const checked=decodePNG(fs.readFileSync(path.join(OUT,'pipeline',f.name+'-native.png')));if(Buffer.compare(Buffer.from(f.data),Buffer.from(checked.data)))throw Error('Material pipeline changed '+f.name);}

// Read the exact current-game fine sheets. Fine is not interchangeable with native pixels enlarged 3x.
const referenceIds=['keeper','traveler','mage','elf','rogue'],referenceNames=['상점 주인','여행자','여마법사','엘프','고양이 도적'];
const references=referenceIds.map((id,i)=>{
  const file=path.join(ROOT,`assets/pixel_v1/characters/${id}/idle-fine.png`),bytes=fs.readFileSync(file);
  const atlas={frames:Object.fromEntries(Array.from({length:64},(_,j)=>['f'+j,{frame:{x:j%16*96,y:Math.floor(j/16)*144,w:96,h:144},duration:125}])),meta:{scale:'1'}};
  const imported=importPNG(bytes,{name:'reference_'+id,atlas}),p=imported.project||imported.recipe;
  const frames=renderProject(p).frames.map(f=>({...f,width:96,height:144}));
  const source=rel(file),destination=path.join(OUT,'references',id+'-idle-fine.png');fs.copyFileSync(file,destination);
  return {id,name:referenceNames[i],frames,source,copy:destination,sha256:hash(bytes)};
});
const referenceAt=t=>Math.floor(t/125)%16+(t%3000>=1500?16:0)+(t%4500>=3600&&t%4500<3850?32:0);
const idleRecipe=read(path.join(ROOT,'art/mockups/f25-staff-playback-v2/recipes/staff_brewing_assistant.json'));
const idleRendered=renderProject(idleRecipe),idleMap=new Map(idleRendered.frames.map(f=>[f.name,frame(f)]));
const idleTimeline=idleRecipe.animations.idle.frames.map(name=>{const f=idleRecipe.frames.find(f=>f.name===name);return {pose:f.from,duration:f.duration};});
const select=(items,t,loop)=>{t%=loop;let end=0;for(const item of items){end+=item.duration;if(t<end)return item;}throw Error('Timeline gap');};
const actionMap=new Map(rendered.frames.slice(0,poseNames.length).map(f=>[f.name,frame(f)]));
const idleAt=t=>idleMap.get(select(idleTimeline,t,18000).pose),actionAt=t=>actionMap.get(select(timeline,t,6000).pose);
if(process.argv.includes('--prepare-live')){
  const fixture=path.join(ROOT,'.verification/f25-flask-live');fs.mkdirSync(path.join(fixture,'frames'),{recursive:true});
  fs.copyFileSync(path.join(ROOT,'tools/f25_staff_live_review.gd'),path.join(fixture,'review.gd'));
  fs.copyFileSync(path.join(ROOT,'assets/fonts/pretendard/Pretendard-Regular.otf'),path.join(fixture,'Pretendard-Regular.otf'));
  fs.writeFileSync(path.join(fixture,'project.godot'),'config_version=5\n[application]\nconfig/name="F25 Flask Review"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\ntextures/canvas_textures/default_texture_filter=0\n');
  const save=(id,frames)=>{const folder=path.join(fixture,'frames',id);fs.mkdirSync(folder,{recursive:true});for(const f of frames)fs.writeFileSync(path.join(folder,f.name+'.png'),encodePNG(f.data,f.width,f.height));};
  const cuts=new Set(Array.from({length:145},(_,i)=>i*125));for(let t=3600;t<18000;t+=4500){cuts.add(t);cuts.add(t+250);}const times=[...cuts].sort((a,b)=>a-b);
  const items=references.map(r=>{save(r.id,r.frames);return {id:r.id,name:r.name,scale:1,loop_ms:18000,frames:times.slice(0,-1).map((t,i)=>({path:'res://frames/'+r.id+'/f'+referenceAt(t)+'.png',duration_ms:times[i+1]-t}))};});
  save('idle',[...idleMap.values()]);save('action',[...actionMap.values()]);
  json(path.join(fixture,'review.json'),{title:'조제 보조 · 플라스크 움직임 비교',groups:[{label:'기존 캐릭터 · 현재 게임 재생',items},{label:'조제 보조 · 대기 / 플라스크 흔들기',items:[{id:'brewer_idle',name:'기존 대기',scale:3,loop_ms:18000,frames:idleTimeline.map(p=>({path:'res://frames/idle/'+p.pose+'.png',duration_ms:p.duration}))},{id:'brewer_shake',name:'플라스크 흔들기',scale:3,loop_ms:6000,frames:timeline.map(p=>({path:'res://frames/action/'+p.pose+'.png',duration_ms:p.duration}))}]}]});
}
const canvasColors=['#F3EFE5','#E2E8DC','#B6C7B0','#53695B'];
const allFrames=[...references.flatMap(r=>r.frames),...idleMap.values(),...actionMap.values()];
const colors=new Set(canvasColors);
for(const f of allFrames)for(let i=0;i<f.data.length;i+=4)if(f.data[i+3])colors.add('#'+[...f.data.slice(i,i+3)].map(v=>v.toString(16).padStart(2,'0')).join('').toUpperCase());
const chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!$%&()*+,-/:;<=>?@[]^_{}|~';
if(colors.size>chars.length)throw Error('Too many comparison colors');
const boardPalette=Object.fromEntries([...colors].map((c,i)=>[chars[i],c]));const symbolFor=Object.fromEntries(Object.entries(boardPalette).map(([a,b])=>[b,a]));
const gridCache=new WeakMap();
function displayGrid(f){if(gridCache.has(f))return gridCache.get(f);const rows=[];for(let y=0;y<f.height;y++){let row='';for(let x=0;x<f.width;x++){const c=color(f,x,y);row+=c==='transparent'?'.':symbolFor[c];}rows.push(row);}gridCache.set(f,rows);return rows;}
function boardAt(t,together){
  const width=together?600:280,height=together?410:210;
  const ops=[{op:'rect',w:width,h:height,color:canvasColors[0]}];
  function place(f,x,y,label,scale){ops.push({op:'rect',x:x-4,y:y-3,w:104,h:151,color:canvasColors[1]},{op:'line',x:x-4,x2:x+100,y:y+141,y2:y+141,color:canvasColors[2]},{op:'grid',x,y,rows:displayGrid(f),scale},{op:'text',x,y:y+155,text:label,color:canvasColors[3]});}
  if(together){ops.push({op:'text',x:18,y:11,text:'CURRENT GAME / SAME DISPLAY SIZE',color:canvasColors[3]});references.forEach((r,i)=>place(r.frames[referenceAt(t)],18+116*i,34,['KEEPER','TRAVELER','MAGE','ELF','ROGUE'][i],1));ops.push({op:'text',x:18,y:211,text:'BREWER / IDLE AND FLASK ACTION',color:canvasColors[3]});place(idleAt(t),160,234,'IDLE',3);place(actionAt(t),344,234,'FLASK SHAKE',3);}
  else{ops.push({op:'text',x:18,y:11,text:'BREWER / BEFORE AND ACTION',color:canvasColors[3]});place(idleAt(t),18,34,'IDLE',3);place(actionAt(t),162,34,'FLASK SHAKE',3);}
  return {...renderProject({version:1,name:'flask_comparison',width,height,palette:boardPalette,frames:[{name:'view',ops}]}).frames[0],width,height};
}
for(const [name,together]of [['comparison-1x',false],['together-1x',true]]){
  const first=boardAt(0,together);fs.writeFileSync(path.join(OUT,name+'.png'),encodePNG(first.data,first.width,first.height));
  if(!quick){function* sequence(){for(let t=0;t<18000;t+=50)yield {...boardAt(t,together),name:'time_'+t};}const gif=framesGIF(sequence(),{fps:{numerator:20,denominator:1},loops:0});fs.writeFileSync(path.join(OUT,name+'.gif'),gif.data);json(path.join(OUT,'logs',name+'-gif.json'),{frames:gif.frames,duration:gif.duration,fps:20,notes:gif.notes});}
}

const uri=p=>'data:image/png;base64,'+fs.readFileSync(p).toString('base64');
const imageBank={};for(const pose of poseNames)imageBank['action/'+pose]=uri(path.join(OUT,'exports/staff/frames',pose+'.png'));
for(const pose of ['still','inhale','blink','inhale_blink'])imageBank['idle/'+pose]=uri(path.join(ROOT,'art/mockups/f25-staff-alignment-v1/exports/staff_brewing_assistant/frames',pose+'.png'));
for(const r of references)imageBank[r.id]=uri(r.copy);
const html=`<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>조제 보조 · 플라스크 흔들기</title><style>*{box-sizing:border-box}body{margin:0;background:#f3efe5;color:#241c32;font:15px/1.65 system-ui,'Malgun Gothic',sans-serif}main{max-width:1080px;margin:auto;padding:28px 24px}h1{font-size:28px;margin:0}h2{font-size:19px;margin:24px 0 10px}p{margin:8px 0}.note{padding:10px 16px;background:#e5eadc;border-left:4px solid #718c59}.controls{display:flex;gap:12px;align-items:center;flex-wrap:wrap;position:sticky;top:0;z-index:2;background:#f3efe5;padding:14px 0}button,select{font:inherit;padding:6px 12px;border:1px solid #a7b69f;border-radius:6px;background:white}.refs{display:grid;grid-template-columns:repeat(5,1fr);gap:12px}.pair{display:flex;justify-content:center;gap:40px;margin:16px 0}.card{background:#fffdf7;border:1px solid #d1d8ca;border-radius:9px;text-align:center;padding:14px;min-width:150px}.stage{width:96px;height:144px;position:relative;background:#e2e8dc;margin:auto}.stage canvas{width:96px;height:144px;image-rendering:pixelated}.guides{position:absolute;inset:0;pointer-events:none;opacity:.5}.guides i{position:absolute;left:0;right:0;border-top:1px solid #638174}.hide-guides .guides{display:none}.native{width:32px;height:48px;image-rendering:pixelated;margin-top:8px}.sheet{max-width:100%;image-rendering:pixelated}a{color:#24566a}.small{font-size:13px;color:#58694f}@media(max-width:780px){.refs{grid-template-columns:repeat(2,1fr)}.pair{gap:12px;flex-wrap:wrap}}</style><main><h1>조제 보조 · 플라스크 흔들기</h1><p>같은 손으로 병을 받쳐 들어 올리고, 작은 왕복 동작을 세 번 한 뒤 원래 자세로 돌아옵니다. 한 동작은 6초입니다.</p><p class="note">직원 32×48·기존 5색·머리/가슴/다리와 발 정렬을 유지했습니다. 기존 캐릭터는 현재 게임의 fine 그림을 그대로, 직원은 원본 3배로 표시합니다.</p><div class="controls"><button id="play">일시정지</button><button id="reset">처음부터</button><select id="speed" aria-label="재생 속도"><option value="0.5">0.5배</option><option value="1" selected>1배</option><option value="2">2배</option></select><label><input type="checkbox" id="guides"> 신체 기준선</label><button id="still">정지 기준</button><span id="time"></span></div><h2>기존 캐릭터 · 현재 게임 재생</h2><section class="refs">${references.map(r=>`<article class="card"><strong>${r.name}</strong><div class="stage"><canvas width="96" height="144" data-ref="${r.id}"></canvas><div class="guides">${[27,31,40,46].map(y=>`<i style="top:${y*3}px"></i>`).join('')}</div></div></article>`).join('')}</section><h2>조제 보조 · 대기와 새 동작</h2><section class="pair"><article class="card"><strong>기존 대기</strong><div class="stage"><canvas id="idle" width="32" height="48"></canvas><div class="guides">${[27,31,40,46].map(y=>`<i style="top:${y*3}px"></i>`).join('')}</div></div><canvas id="idle-native" class="native" width="32" height="48"></canvas></article><article class="card"><strong>플라스크 흔들기</strong><div class="stage"><canvas id="action" width="32" height="48"></canvas><div class="guides">${[27,31,40,46].map(y=>`<i style="top:${y*3}px"></i>`).join('')}</div></div><canvas id="action-native" class="native" width="32" height="48"></canvas><p class="small" id="phase"></p></article></section><h2>주요 자세</h2><img class="sheet" src="${uri(path.join(OUT,'reviews/keyposes.png'))}" alt="정지, 준비, 들어 올림, 왼쪽 흔들기, 오른쪽 흔들기"><p>소매와 손–병 접점은 함께 움직이고, 반대 손과 몸통은 유지합니다. 병은 닫힌 상태이며 불필요한 효과나 새 색을 더하지 않았습니다.</p><p><a href="comparison-1x.gif">대기/동작 GIF</a> · <a href="together-1x.gif">기존 캐릭터와 함께 GIF</a> · <a href="validation.json">검사 결과</a></p><p class="small">리소스는 한 번 실행 후 정지 자세로 끝나며 이 화면은 비교를 위해 반복합니다. 공유 GIF는 20fps·18초입니다. 아직 검토 후보이며 게임 배치와 직원 역할 아이콘은 변경하지 않았습니다.</p></main><script>const urls=${JSON.stringify(imageBank)},action=${JSON.stringify(timeline)},idle=${JSON.stringify(idleTimeline)};let time=0,last=null,playing=true,speed=1,still=false;const images={};document.body.classList.add('hide-guides');function select(items,t,loop){t%=loop;let end=0;for(const f of items){end+=f.duration;if(t<end)return f}}const play=document.getElementById('play');play.onclick=()=>{playing=!playing;still=false;play.textContent=playing?'일시정지':'재생'};document.getElementById('reset').onclick=()=>{time=0;still=false};document.getElementById('still').onclick=()=>{playing=false;still=true;play.textContent='재생'};document.getElementById('speed').onchange=e=>speed=Number(e.target.value);document.getElementById('guides').onchange=e=>document.body.classList.toggle('hide-guides',!e.target.checked);Promise.all(Object.entries(urls).map(([k,src])=>new Promise(resolve=>{const im=new Image();im.onload=()=>{images[k]=im;resolve()};im.src=src}))).then(()=>requestAnimationFrame(tick));function draw(id,key){const c=document.getElementById(id),ctx=c.getContext('2d');ctx.imageSmoothingEnabled=false;ctx.clearRect(0,0,32,48);ctx.drawImage(images[key],0,0)}function tick(now){if(last!==null&&playing)time+=Math.min(now-last,250)*speed;last=now;const t=still?0:time%18000,ref=still?0:Math.floor(t/125)%16+(t%3000>=1500?16:0)+(t%4500>=3600&&t%4500<3850?32:0);document.querySelectorAll('[data-ref]').forEach(c=>{const ctx=c.getContext('2d');ctx.imageSmoothingEnabled=false;ctx.clearRect(0,0,96,144);ctx.drawImage(images[c.dataset.ref],ref%16*96,Math.floor(ref/16)*144,96,144,0,0,96,144)});const a=still?'rest':select(action,time,6000).pose,b=still?'still':select(idle,time,18000).pose;draw('idle','idle/'+b);draw('idle-native','idle/'+b);draw('action','action/'+a);draw('action-native','action/'+a);document.getElementById('time').textContent=still?'정지 기준':(time/1000).toFixed(1)+'초 · '+speed+'배';document.getElementById('phase').textContent=({rest:'대기',prepare:'준비/복귀',lift:'들어 올림',shake_left:'한쪽으로 흔들기',shake_right:'반대쪽으로 흔들기'})[a];requestAnimationFrame(tick)}document.addEventListener('visibilitychange',()=>last=null);</script></html>`;
fs.writeFileSync(path.join(OUT,'review.html'),html);
json(path.join(OUT,'validation.json'),{status:quick?'frames_verified_previews_pending':'passed',engine:'Pixelbolt 0.11.0',art_status:'candidate',approved_by_user:false,runtime_integrated:false,size:[32,48],display_size:[96,144],source:rel(baseFile),source_sha256:hash(fs.readFileSync(baseFile)),duration_ms:LENGTH,action_loop:false,timeline,source_pose_notes:notes,protected_regions:protectedParts,frames:reports,contacts:contactReports,material_pipeline_changed_pixels:0,action_returns_to_rest:true,references:references.map(({id,name,source,sha256})=>({id,name,source,sha256,source_size:[96,144],display_scale:1})),comparison_runtime_function:'scripts/pixel_art_catalog.gd:40',comparison_duration_ms:18000,comparison_fps:20,gif_notes:solo.notes});
fs.writeFileSync(path.join(OUT,'asset.brief.md'),'# 조제 보조 플라스크 흔들기\n\nPixelbolt로 정렬된 32×48 기존 직원의 오른팔/손/플라스크만 움직인다. 고글·와인색 단발·회색 가운의 정체성과 기존5색, 공통외곽선,3/4방향·기존조명을 유지한다. 목·가슴·허리·골반·두 다리·발y46·반대 손은 원본 픽셀 그대로다. 화면 오른손이 둥근 병몸통을 받치는 원래 접촉 관계를 유지하며 닫힌 병을 들어 작게 왕복3회 흔들고 원래 정지로 복귀한다. 눈/모자/몸을 함께 흔드는 전신변형이나 보간 회전을 하지 않는다.\n\n같은 원본3배로 움직임과 고정 부위를 비교한다. 기존5명은 실제게임 fine96×144와 motion_index의18초주기를 보존한다. 내보내기는6초 원샷이고 비교GIF/HTML만반복한다. 프레임·접촉·타이밍·시각검토의 근거와 한계는 별도 결과 문서에 기록한다.\n\n재현: node tools/build_f25_staff_flask_v1.mjs\n');
console.log('Built flask action: '+timeline.length+' timing segments / '+LENGTH+'ms'+(quick?' (GIF comparison pending)':''));
