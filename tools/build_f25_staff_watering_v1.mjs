/** Pixelbolt-native staff watering study. Existing character and planter colors are preserved. */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { renderProject, importPNG, encodePNG, animationGIF, formatJSON, decodePNG } from './pixelbolt/node_modules/pixelbolt/src/index.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'art/mockups/f25-staff-watering-v1');
const OLD = path.join(ROOT, 'art/mockups/f25-staff-alignment-v1');
const CLI = path.join(ROOT, 'tools/pixelbolt/node_modules/pixelbolt/bin/pixelbolt.js');
const read = p => JSON.parse(fs.readFileSync(p, 'utf8'));
const json = (p, value) => fs.writeFileSync(p, JSON.stringify(value, null, 2) + '\n');
const rel = p => path.relative(ROOT, p).replaceAll('\\', '/');
const hash = b => createHash('sha256').update(b).digest('hex');
for (const folder of ['recipes', 'exports', 'reviews', 'logs', 'pipeline']) fs.mkdirSync(path.join(OUT, folder), { recursive: true });
if (read(path.join(ROOT, 'tools/pixelbolt/node_modules/pixelbolt/package.json')).version !== '0.11.0') throw Error('Requires Pixelbolt 0.11.0');
fs.copyFileSync(path.join(ROOT, 'tools/pixelbolt/node_modules/pixelbolt/LICENSE'), path.join(OUT, 'PIXELBOLT-LICENSE.txt'));
const legend = read(path.join(ROOT, 'art/mockups/f25-staff-motion-v1/source/generation.json')).legend;
const palette = Object.fromEntries(Object.entries(legend).map(([k, v]) => [k, v.color]));
const approved = new Set(fs.readFileSync(path.join(ROOT, 'art/palette.hex'), 'utf8').trim().split(/\r?\n/).map(c => '#' + c.toUpperCase()));
const loadGrid = p => { const rows = fs.readFileSync(p, 'utf8').trimEnd().split(/\r?\n/); if (rows.length !== 48 || rows.some(r => r.length !== 32)) throw Error('Invalid 32x48 grid: ' + p); return rows; };
const baseRows = loadGrid(path.join(OLD, 'source/staff_cultivation_assistant.txt'));
const poseNames = ['rest', 'recover', 'lift', 'tilt', 'pour'];
const grids = Object.fromEntries(poseNames.map(n => [n, loadGrid(path.join(OUT, 'source', n + '.txt'))]));
if (grids.rest.join('\n') !== baseRows.join('\n')) throw Error('Rest pose changed');
const poseNotes = read(path.join(OUT, 'source/poses.json'));
const sections = [ ['rest',1000], ['recover',180], ['lift',220], ['tilt',220], ['pour',1600], ['tilt',180], ['lift',180], ['recover',220], ['rest',1400] ];
let position = 0;
const timeline = sections.map(([pose, duration]) => { const p = { pose, start: position, duration }; position += duration; return p; });
const LENGTH = position;
const stateAt = t => timeline.find(p => t >= p.start && t < p.start + p.duration) || timeline[0];
const staffRecipe = { version:1, name:'staff_cultivation_watering', width:32, height:48, palette, anchor:[14,46], frames:poseNames.map(name=>({name,duration:1000,ops:[{op:'grid',rows:grids[name]}]})), animations:{still:{frames:['rest'],loop:true},watering:{frames:timeline.map((p,i)=>'action_'+i),loop:false}},sheet:{columns:5,scale:1,trim:false} };
staffRecipe.frames.push(...timeline.map((p,i)=>({name:'action_'+i,from:p.pose,duration:p.duration})));
const rendered = renderProject(staffRecipe);
const original = rendered.frames[0].data;
const masks = read(path.join(OLD, 'source/alignment-notes.json')).assets.staff_cultivation_assistant.semantic_masks;
const color = (data,x,y,width=32) => { const i=(y*width+x)*4; return data[i+3] ? '#'+[...data.slice(i,i+3)].map(v=>v.toString(16).padStart(2,'0')).join('').toUpperCase() : 'transparent'; };
const same = (a,b,x,y) => color(a,x,y)===color(b,x,y);
const reports=[];
for (const frame of rendered.frames) {
  const data=frame.data, colors=new Set();let boundary=0,alpha=0,changed=0;
  for(let y=0;y<48;y++)for(let x=0;x<32;x++){
    const c=color(data,x,y),a=data[(y*32+x)*4+3]; if(a!==0&&a!==255)alpha++;
    if(!same(data,original,x,y))changed++;
    if(y<=26&&!same(data,original,x,y))throw Error(frame.name+': head changed');
    if(x>=10&&!same(data,original,x,y))throw Error(frame.name+': trunk or far arm changed');
    if(c==='transparent')continue;colors.add(c);
    const outer=[[x-1,y],[x+1,y],[x,y-1],[x,y+1]].some(([xx,yy])=>xx<0||xx>=32||yy<0||yy>=48||color(data,xx,yy)==='transparent');
    if(outer&&c!=='#241C32')boundary++;
  }
  for(const part of ['left_leg','right_leg','right_hand'])for(const [y,x0,x1]of masks[part].runs)for(let x=x0;x<=x1;x++)if(!same(data,original,x,y))throw Error(frame.name+': fixed '+part+' moved');
  if(colors.size>5||alpha||boundary||[...colors].some(c=>!approved.has(c)))throw Error(JSON.stringify({frame:frame.name,colors:[...colors],alpha,boundary}));
  reports.push({frame:frame.name,changed_pixels:changed,colors:colors.size,outline_errors:boundary,head_trunk_legs_unchanged:true});
}
function run(command,args,label){const result=spawnSync(process.execPath,[CLI,command,...args,...(command==='validate'?[]:['--force'])],{cwd:ROOT,encoding:'utf8',maxBuffer:16*1024*1024});if(result.status!==0)throw Error(result.stderr||result.stdout);json(path.join(OUT,'logs',label+'.json'),JSON.parse(result.stdout.replaceAll(ROOT.replaceAll('\\','\\\\'),'.').replaceAll(ROOT.replaceAll('\\','/'),'.')));}
const recipeFile=path.join(OUT,'recipes/staff.json');fs.writeFileSync(recipeFile,formatJSON(staffRecipe));run('validate',[recipeFile],'staff-validate');run('render',[recipeFile,'--out',path.join(OUT,'exports/staff'),'--animation','watering'],'staff-render');run('inspect',[recipeFile,'--frames',poseNames.join(','),'--out',path.join(OUT,'reviews/keyposes.png'),'--native','--scale','3'],'staff-inspect');

// Keep the approved planter intact; it is nearer to the viewer than the staff's foot plane.
const potFile=path.join(ROOT,'assets/pixel_v1/props/herb.png');
const potImport=importPNG(fs.readFileSync(potFile),{name:'approved_herb'});const pot=potImport.project||potImport.recipe;
const potImage=renderProject(pot).frames[0];
fs.copyFileSync(potFile,path.join(OUT,'approved-planter.png'));
const combinedPalette={...palette,pot_green:'#718C59',pot_purple:'#86548E',pot_cream:'#FFF0BC',pot_wood:'#916047',water_dark:'#24566A',water_light:'#9BE2CF',paper:'#F3EFE5',floor:'#E2E8DC',shadow:'#B6C7B0'};
// Re-map imported raster colors to single-character keys for a lossless grid stamp.
const potMap={'#241C32':'#','#718C59':'u','#86548E':'v','#FFF0BC':'c','#916047':'b'};
Object.assign(combinedPalette,{u:'#718C59',v:'#86548E',b:'#916047'});
const potRows=[];
for(let y=0;y<32;y++){let row='';for(let x=0;x<32;x++){const c=color(potImage.data,x,y);if(c!=='transparent'&&!potMap[c])throw Error('Unexpected planter color '+c);row+=c==='transparent'?'.':potMap[c];}potRows.push(row);}

const CHAR=[40,8],POT=[10,32],TARGET=[31,45];
// The source author records the actual open nozzle coordinate in the pour pose.
const nozzle=poseNotes.states.find(p=>p.id==='pour')?.nozzle;
if(!Array.isArray(nozzle)||nozzle.length!==2)throw Error('Missing pour nozzle in poses.json');
const origin=[CHAR[0]+nozzle[0],CHAR[1]+nozzle[1]];
if(TARGET[1]<=origin[1])throw Error('Water would travel upwards');
const fxPalette={'#':'#241C32',d:'#24566A',t:'#9BE2CF'};
const waterFrames=[];
for(let phase=0;phase<4;phase++){
  // Include the final contact point, rather than wrapping the droplet before it reaches the planter.
  const fraction=phase/3;
  const x=Math.round(origin[0]+(TARGET[0]-origin[0])*fraction),y=Math.round(origin[1]+(TARGET[1]-origin[1])*fraction);
  const ops=[{op:'grid',x:x-1,y:y-1,rows:['.#.','#t#','.#.']}];
  waterFrames.push({name:'flow_'+phase,duration:100,ops});
}
const water={version:1,name:'watering_fx',width:88,height:72,palette:fxPalette,frames:[{name:'off',duration:100,ops:[]},...waterFrames],animations:{flow:{frames:waterFrames.map(f=>f.name),loop:true}},sheet:{columns:5,scale:1}};
const waterFile=path.join(OUT,'recipes/water.json');fs.writeFileSync(waterFile,formatJSON(water));run('validate',[waterFile],'water-validate');run('render',[waterFile,'--out',path.join(OUT,'exports/water'),'--animation','flow'],'water-render');
const fxRendered=renderProject(water);
if(color(fxRendered.frames.at(-1).data,TARGET[0],TARGET[1],88)!=='#9BE2CF')throw Error('Last water drop misses its target');
if(color(potImage.data,TARGET[0]-POT[0],TARGET[1]-POT[1])==='transparent')throw Error('Water target is outside the planter opening');
for(const frame of fxRendered.frames){
  for(let i=3;i<frame.data.length;i+=4)if(frame.data[i]!==0&&frame.data[i]!==255)throw Error('Water alpha must be binary');
}
// Split only the pouring hold for the independent water cycle. The pose itself remains planted.
const sceneParts=[];
for(const p of timeline){if(p.pose==='pour')for(let ms=0;ms<p.duration;ms+=100)sceneParts.push({...p,start:p.start+ms,duration:Math.min(100,p.duration-ms),flow:Math.floor(ms/100)%4});else sceneParts.push({...p,flow:-1});}
function sceneOps(p,xOffset=0){
  const ops=[{op:'rect',x:xOffset,y:0,w:88,h:72,color:'paper'},{op:'rect',x:xOffset,y:42,w:88,h:30,color:'floor'},{op:'ellipse',x:xOffset+CHAR[0]+7,y:CHAR[1]+46,w:21,h:3,color:'shadow'},{op:'ellipse',x:xOffset+POT[0]+4,y:POT[1]+30,w:25,h:3,color:'shadow'},{op:'grid',x:xOffset+POT[0],y:POT[1],rows:potRows},{op:'grid',x:xOffset+CHAR[0],y:CHAR[1],rows:grids[p.pose]}];
  if(p.flow>=0){for(const op of waterFrames[p.flow].ops)ops.push({...op,x:op.x+xOffset,rows:op.rows.map(row=>row.replaceAll('t','z'))});}
  return ops;
}
combinedPalette.z='#9BE2CF';
const scene={version:1,name:'watering_scene',width:88,height:72,palette:combinedPalette,frames:sceneParts.map((p,i)=>({name:'scene_'+i,duration:p.duration,ops:sceneOps(p)})),animations:{watering:{frames:sceneParts.map((_,i)=>'scene_'+i),loop:false}},sheet:{columns:6,scale:1}};
const sceneFile=path.join(OUT,'recipes/scene.json');fs.writeFileSync(sceneFile,formatJSON(scene));run('validate',[sceneFile],'scene-validate');run('render',[sceneFile,'--out',path.join(OUT,'exports/scene'),'--animation','watering'],'scene-render');
const sceneRendered=renderProject(scene);
const gifScene=structuredClone(scene);gifScene.animations.watering.loop=true;
const gif=animationGIF(renderProject(gifScene),'watering',{scale:3});fs.writeFileSync(path.join(OUT,'watering-3x.gif'),gif.data);

const compare={version:1,name:'watering_comparison',width:184,height:86,palette:combinedPalette,frames:sceneParts.map((p,i)=>({name:'compare_'+i,duration:p.duration,ops:[{op:'rect',w:184,h:86,color:'paper'},...sceneOps({pose:'rest',flow:-1},0).map(op=>({...op,y:(op.y||0)+13})),...sceneOps(p,96).map(op=>({...op,y:(op.y||0)+13})),{op:'text',x:8,y:4,text:'IDLE',color:'#53695B'},{op:'text',x:103,y:4,text:'WATERING',color:'#53695B'}]})),animations:{compare:{frames:sceneParts.map((_,i)=>'compare_'+i),loop:true}},sheet:{columns:6,scale:1}};
const comparison=renderProject(compare),cgif=animationGIF(comparison,'compare',{scale:3});fs.writeFileSync(path.join(OUT,'comparison-3x.gif'),cgif.data);fs.writeFileSync(path.join(OUT,'comparison.png'),encodePNG(comparison.frames[0].data,184,86));
fs.writeFileSync(path.join(OUT,'recipes/comparison.json'),formatJSON(compare));

// Reuse the project's material-aware pipeline for the 14 staff frames.
const originalManifest=read(path.join(ROOT,'art/mockups/f25-staff-motion-v1/source/original-manifest.json'));
const material=originalManifest.assets.find(a=>a.id==='staff_cultivation_assistant');
const manifest={...originalManifest,feature:'F25 staff watering candidate',output:rel(path.join(OUT,'pipeline')),assets:staffRecipe.frames.map(f=>({...material,id:f.name,source:rel(path.join(OUT,'exports/staff/frames',f.name+'.png')),position:[0,0]}))};
json(path.join(OUT,'manifest.json'),manifest);
const bundled=path.join(process.env.USERPROFILE||'','.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe');
const proc=spawnSync(process.env.PYTHON||(fs.existsSync(bundled)?bundled:'python'),['tools/process_pixel_art.py',rel(path.join(OUT,'manifest.json'))],{cwd:ROOT,encoding:'utf8'});if(proc.status!==0)throw Error(proc.stdout+proc.stderr);
for(const f of rendered.frames){const checked=decodePNG(fs.readFileSync(path.join(OUT,'pipeline',f.name+'-native.png')));if(Buffer.compare(Buffer.from(checked.data),Buffer.from(f.data)))throw Error('Material pipeline changed '+f.name);}

const uri=p=>'data:image/png;base64,'+fs.readFileSync(p).toString('base64');
const player=sceneParts.map((p,i)=>({duration:p.duration,pose:p.pose,url:uri(path.join(OUT,'exports/scene/frames','scene_'+i+'.png'))}));
const html=`<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>재배 보조 · 물 주기</title><style>*{box-sizing:border-box}body{background:#f3efe5;color:#241c32;font:16px/1.6 system-ui,'Malgun Gothic',sans-serif;margin:0}main{max-width:920px;margin:auto;padding:32px 24px}h1{font-size:28px;margin:0}p{margin:8px 0}.pair{display:flex;gap:40px;flex-wrap:wrap;margin:24px 0}.scene{width:264px;height:216px;image-rendering:pixelated}.controls{display:flex;gap:12px;align-items:center;flex-wrap:wrap}button,select{font:inherit;padding:6px 12px;border:1px solid #a6b89c;border-radius:6px;background:white}.sheet{image-rendering:pixelated;max-width:100%}.note{background:#e5eadc;border-left:4px solid #718c59;padding:10px 16px}a{color:#24566a}</style><main><h1>재배 보조 · 첫 역할 동작</h1><p>준비 → 들어 올리기 → 기울여 물 주기 → 원래 자세. 1배 속도 5.2초입니다.</p><p class="note">신체·머리·발 정렬과 원본 5색을 유지하고, 앞손과 물뿌리개를 함께 움직였습니다. 물은 별도 레이어입니다. 화분은 승인된 그림을 보존해 캐릭터보다 앞쪽에 놓았습니다.</p><div class="controls"><button id="play">일시정지</button><button id="reset">처음부터</button><select id="speed"><option value="0.5">0.5배</option><option value="1" selected>1배</option><option value="2">2배</option></select><span id="status"></span></div><div class="pair"><section><h2>대기 기준</h2><img class="scene" src="${player[0].url}" alt="정렬된 대기와 앞쪽 화분"></section><section><h2>물 주기 후보</h2><canvas class="scene" width="88" height="72" aria-label="물 주기 움직임"></canvas></section></div><h2>주요 자세</h2><img class="sheet" src="${uri(path.join(OUT,'reviews/keyposes.png'))}" alt="정지, 복귀 중간, 들어 올림, 기울임, 물 주기"><p>실제 동작은 한 번 재생 후 대기로 돌아가는 리소스로 내보냈습니다. 이 화면과 GIF는 비교를 위해 반복합니다.</p><p><a href="comparison-3x.gif">전후 움직임 GIF</a> · <a href="validation.json">검사 결과</a></p><p>게임 연결 전 검토 후보입니다. 실제 작업실 배치와 관리 역할 아이콘은 바꾸지 않았습니다.</p></main><script>const frames=${JSON.stringify(player)},length=${LENGTH};let time=0,last=null,playing=true,speed=1;const images=[];Promise.all(frames.map((f,i)=>new Promise(resolve=>{const im=new Image();im.onload=()=>{images[i]=im;resolve()};im.src=f.url}))).then(()=>requestAnimationFrame(tick));const play=document.getElementById('play');play.onclick=()=>{playing=!playing;play.textContent=playing?'일시정지':'재생'};document.getElementById('reset').onclick=()=>time=0;document.getElementById('speed').onchange=e=>speed=Number(e.target.value);function tick(now){if(last!==null&&playing)time+=Math.min(now-last,250)*speed;last=now;let local=time%length,end=0,index=0;for(let i=0;i<frames.length;i++){end+=frames[i].duration;if(local<end){index=i;break}}const c=document.querySelector('canvas'),ctx=c.getContext('2d');ctx.imageSmoothingEnabled=false;ctx.clearRect(0,0,88,72);ctx.drawImage(images[index],0,0);document.getElementById('status').textContent=(local/1000).toFixed(2)+' / 5.20초 · '+frames[index].pose;requestAnimationFrame(tick)}document.addEventListener('visibilitychange',()=>last=null);</script></html>`;
fs.writeFileSync(path.join(OUT,'review.html'),html);
json(path.join(OUT,'validation.json'),{status:'passed',art_status:'candidate',approved_by_user:false,runtime_integrated:false,engine:'Pixelbolt 0.11.0',duration_ms:LENGTH,action_loop:false,preview_loop:true,source_poses:poseNames,source_pose_notes:poseNotes,staff_frames:reports,scene_frames:sceneParts.length,staff_origin:CHAR,planter_origin:POT,water_origin:origin,water_target:TARGET,water_flows_down:true,water_only_when_pouring:true,material_pipeline_changed_pixels:0,planter_source:rel(potFile),planter_sha256:hash(fs.readFileSync(potFile)),gif:{duration:gif.duration,notes:gif.notes}});
fs.writeFileSync(path.join(OUT,'asset.brief.md'),'# 재배 보조 물 주기\n\nPixelbolt로 기존 32×48 직원의 앞팔/물뿌리개만 수정한다. 얼굴·모자·체간·두 다리와 발 y46, 원래 피부/금색 작업복/녹색 멜빵/갈색 도구/공통 외곽선 5색을 보존한다. 실루엣 기준은 넓은 밀짚모자, 녹색 멜빵, 왼쪽 물뿌리개다. 3/4 왼쪽 방향과 기본 조명을 유지한다.\n\n주요 동작은 준비→들어 올리기→기울임→물을 줌→역순 복귀다. 물을 줄 때까지 무작정 새 자세를 늘리지 않는다. 같은 앞손과 손잡이 접점 및 아래로 향하는 노즐을 확인한다. 물줄기는 별도 3색 이하 에셋이며, 최종 화면에 캐릭터 팔레트와 합쳐 굽지 않는다. 승인된 화분+받침대는 수정하지 않고 캐릭터보다 앞쪽에 배치한다. 두 물체의 깊이가 다르므로 각각의 바닥 그림자를 사용한다. 실제 작업실 배치 승인을 뜻하지 않는다.\n\n재현: node tools/build_f25_staff_watering_v1.mjs\n');
console.log('Created watering candidate: '+LENGTH+'ms, '+sceneParts.length+' scene frames');
