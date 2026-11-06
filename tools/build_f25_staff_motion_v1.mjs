/** F25 candidate idle motion. Pixelbolt preserves and animates the existing v2 pixels. */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { decodePNG, renderProject, formatJSON } from './pixelbolt/node_modules/pixelbolt/src/index.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const rel = p => path.relative(root, p).split(path.sep).join('/');
const output = path.join(root, 'art/mockups/f25-staff-motion-v1');
const sourceFlag = process.argv.indexOf('--source-root');
const bootstrap = sourceFlag >= 0;
if (bootstrap && !process.argv[sourceFlag+1]) throw new Error('--source-root needs the original v2 candidate directory.');
const input = bootstrap ? path.resolve(root, process.argv[sourceFlag+1]) : path.join(output, 'source');
const cli = path.join(root, 'tools/pixelbolt/node_modules/pixelbolt/bin/pixelbolt.js');
const sha = b => createHash('sha256').update(b).digest('hex');
const readJSON = p => JSON.parse(fs.readFileSync(p, 'utf8'));
const json = (p, value) => fs.writeFileSync(p, JSON.stringify(value, null, 2) + '\n');
const outline = '#241C32';
const size = [32, 48];
const meta = readJSON(path.join(input, 'generation.json'));
const previousManifest = readJSON(path.join(input, bootstrap ? 'manifest.json' : 'original-manifest.json'));
const packageInfo = readJSON(path.join(root, 'tools/pixelbolt/node_modules/pixelbolt/package.json'));
if (packageInfo.version !== '0.11.0') throw new Error('This build is pinned to Pixelbolt 0.11.0.');
const force = process.argv.includes('--force');
if (fs.existsSync(path.join(output, 'validation.json')) && !force)
  throw new Error('Existing candidate preserved. Use --force to rebuild this generated candidate from its sources.');
for (const dir of ['source', 'recipes', 'exports', 'reviews', 'logs', 'pipeline'])
  fs.mkdirSync(path.join(output, dir), { recursive: true });
fs.copyFileSync(path.join(root, 'tools/pixelbolt/node_modules/pixelbolt/LICENSE'), path.join(output, 'PIXELBOLT-LICENSE.txt'));
if (bootstrap) {
  fs.copyFileSync(path.join(input,'generation.json'),path.join(output,'source','generation.json'));
  fs.copyFileSync(path.join(input,'manifest.json'),path.join(output,'source','original-manifest.json'));
}

const logs = [];
function portable(value) {
  if (Array.isArray(value)) return value.map(portable);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,portable(v)]));
  if (typeof value === 'string') return value.split(root).join('.').split(root.split(path.sep).join('/')).join('.');
  return value;
}
function pixel(command, args, log) {
  const argv = [cli, command, ...args, ...(force && command !== 'validate' ? ['--force'] : [])];
  const result = spawnSync(process.execPath, argv, { cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  if (result.stdout) json(path.join(output, 'logs', `${log}.json`), portable(JSON.parse(result.stdout)));
  const stderrFile = path.join(output, 'logs', `${log}.stderr.txt`);
  if (result.stderr) fs.writeFileSync(stderrFile, portable(result.stderr));
  else if (fs.existsSync(stderrFile)) fs.unlinkSync(stderrFile);
  logs.push({ tool: 'Pixelbolt', version: packageInfo.version, command, args: args.map(x => path.isAbsolute(x) ? rel(x) : x), exit: result.status });
  if (result.status !== 0) throw new Error(`${command}: ${result.stderr || result.stdout}`);
  return JSON.parse(result.stdout);
}
const configs = [
  { id: 'staff_sales_assistant', x0: 0, y0: 0, seam: 30, hands: [[10, 31, 12, 9]], skin: '#F6D1AC' },
  { id: 'staff_cultivation_assistant', x0: 0, y0: 0, seam: 32, hands: [[0, 33, 23, 8]], skin: '#DE9B88' },
  { id: 'staff_brewing_assistant', x0: 0, y0: 0, seam: 30, hands: [[4, 31, 23, 8]], skin: '#F6D1AC' },
  { id: 'staff_expedition_guide', x0: 8, y0: 7, seam: 31, hands: [[5, 32, 19, 5], [0, 0, 8, 48], [0, 0, 32, 7]], skin: '#F6D1AC' },
];
function colorAt(data, x, y) {
  const i = (y * 32 + x) * 4;
  if (!data[i + 3]) return 'transparent';
  return '#' + [...data.subarray(i, i + 3)].map(v => v.toString(16).padStart(2, '0')).join('').toUpperCase();
}
function differences(a, b) {
  const out = [];
  for (let y = 0; y < 48; y++) for (let x = 0; x < 32; x++) {
    const i = (y * 32 + x) * 4;
    if ([0, 1, 2, 3].some(k => a[i + k] !== b[i + k])) out.push([x, y]);
  }
  return out;
}
function inside(x, y, r) { return x >= r[0] && y >= r[1] && x < r[0] + r[2] && y < r[1] + r[3]; }
function facts(data) {
  const colors = new Set(), badAlpha = [], badBoundary = [], feet = [];
  let bottom = -1;
  const opaque = (x, y) => x >= 0 && x < 32 && y >= 0 && y < 48 && data[(y * 32 + x) * 4 + 3] > 0;
  for (let y = 0; y < 48; y++) for (let x = 0; x < 32; x++) {
    const a = data[(y * 32 + x) * 4 + 3];
    if (a !== 0 && a !== 255) badAlpha.push([x, y]);
    if (!a) continue;
    bottom = Math.max(bottom, y);
    colors.add(colorAt(data, x, y));
    if (y === 46) feet.push(x);
    if ([[x-1,y],[x+1,y],[x,y-1],[x,y+1]].some(([xx,yy]) => !opaque(xx,yy)) && colorAt(data,x,y) !== outline)
      badBoundary.push([x,y]);
  }
  return { colors: [...colors].sort(), color_count: colors.size, bad_alpha: badAlpha, bad_boundary: badBoundary, bottom, foot_row_x: feet };
}
function timeline() {
  const edges = new Set([0, 9000, 4280, 4400, 8780, 8900]);
  for (let start = 0; start < 9000; start += 3000) for (const phase of [750, 2250]) edges.add(start + phase);
  const sorted = [...edges].sort((a,b)=>a-b);
  return sorted.slice(0,-1).map((time,i) => ({ name: `idle-${String(i).padStart(2,'0')}`, time,
    duration: sorted[i+1]-time, breath: time%3000 >=750 && time%3000<2250,
    blink: (time>=4280&&time<4400)||(time>=8780&&time<8900) }));
}
const phaseTable = timeline();
const results = [], manifestAssets = [], provenance = [], reviewItems = [];

for (const config of configs) {
  const { id } = config, staff = meta.staff[id];
  const sourceFile = path.join(input, ...(bootstrap ? ['sprites'] : []), `${id}.png`);
  const copied = path.join(output, 'source', `${id}.png`);
  const gridFile = path.join(input, ...(bootstrap ? ['source'] : []), `${id}.txt`);
  if (bootstrap) {
    fs.copyFileSync(sourceFile, copied);
    fs.copyFileSync(gridFile, path.join(output, 'source', `${id}.txt`));
  }
  const original = decodePNG(fs.readFileSync(copied));
  if (original.width !== 32 || original.height !== 48) throw new Error(`${id}: source dimensions`);
  const importedFile = path.join(output, 'recipes', `${id}-imported.json`);
  pixel('import', [copied, '--name', id, '--out', importedFile, '--metadata', path.join(output, 'source', `${id}.import.json`)], `${id}-import`);
  json(path.join(output,'source',`${id}.import.json`),portable(readJSON(path.join(output,'source',`${id}.import.json`))));
  const imported = readJSON(importedFile);
  const sourceRendered = renderProject(imported).frames[0].data;
  if (differences(original.data, sourceRendered).length) throw new Error(`${id}: lossless import changed pixels`);
  const still = { ...imported.frames[0], name: 'still', duration: 1000 };
  const baseRecipe = { ...imported, name: id, frames: [still], animations: { still: { frames: ['still'], loop: true } }, sheet: { columns: 4, padding: 0, scale: 1 } };
  const baseFile = path.join(output, 'recipes', `${id}-base.json`);
  fs.writeFileSync(baseFile, formatJSON(baseRecipe));
  const keyFor = color => Object.keys(imported.palette).find(key => imported.palette[key].toUpperCase() === color) ?? color;
  // Copy exact original pixels one grid row up only above the shoulder seam.
  // The seam row is held; the original next row forms a one-row extension, not a rescale.
  const inhale = [];
  for (let y = config.y0; y < config.seam; y++) for (let x = config.x0; x < 32; x++) {
    const value = colorAt(original.data, x, y + 1);
    if (value !== colorAt(original.data,x,y)) inhale.push({ x, y, color: keyFor(value) });
  }
  const blink = staff.eyes.x.map(x => ({ x, y: staff.eyes.y[0], color: keyFor(config.skin) }));
  const inhaleBlink = staff.eyes.x.map(x => ({ x, y: staff.eyes.y[0]-1, color: keyFor(config.skin) }));
  const states = [
    { name: 'inhale', from: 'still', duration: 1000, pixels: inhale },
    { name: 'blink', from: 'still', duration: 120, pixels: blink },
    { name: 'inhale-blink', from: 'inhale', duration: 120, pixels: inhaleBlink },
  ];
  const animationFrames = phaseTable.map(segment => ({ name: segment.name, duration: segment.duration,
    from: segment.breath ? (segment.blink ? 'inhale-blink' : 'inhale') : (segment.blink ? 'blink' : 'still') }));
  const changes = [...states, ...animationFrames].map(value => ({ insert: 'frames[-]', value }));
  changes.push({ set: 'animations.idle', value: { frames: animationFrames.map(f=>f.name), loop: true } });
  const changesFile = path.join(output, 'recipes', `${id}-motion.patch.json`);
  json(changesFile, changes);
  const recipeFile = path.join(output, 'recipes', `${id}.json`);
  pixel('patch', [baseFile, '--changes', changesFile, '--out', recipeFile, '--image', path.join(output, 'reviews', `${id}-changes.png`)], `${id}-patch`);
  const recipe = readJSON(recipeFile), rendered = renderProject(recipe);
  const palette = new Set(Object.values(staff.materials).map(c=>c.toUpperCase()));
  const frameReports = rendered.frames.map(frame => {
    const changed = differences(original.data, frame.data), f = facts(frame.data);
    const frozenChanged = changed.filter(([x,y])=> y >= config.seam || y < config.y0 || x < config.x0 || config.hands.some(r=>inside(x,y,r)));
    const outsidePalette = f.colors.filter(c=>!palette.has(c));
    const entry = { name: frame.name, duration_ms: frame.duration, changed_pixels: changed.length,
      ...f, outside_palette: outsidePalette, fixed_region_changed: frozenChanged,
      visible_rgba_sha256: sha(frame.data) };
    if (f.color_count > 5 || f.bad_alpha.length || f.bad_boundary.length || f.bottom !== 46 || outsidePalette.length || frozenChanged.length)
      throw new Error(`${id}/${frame.name} rejected: ${JSON.stringify(entry)}`);
    return entry;
  });
  const first = rendered.frames.find(f=>f.name===phaseTable[0].name);
  const last = rendered.frames.find(f=>f.name===phaseTable.at(-1).name);
  const seamPixels = differences(first.data,last.data).length;
  if (seamPixels) throw new Error(`${id}: loop join changed ${seamPixels} pixels`);
  pixel('validate', [recipeFile], `${id}-validate`);
  const expectation = path.join(output, 'recipes', `${id}.expect.json`);
  json(expectation, { width: 32, height: 48, frames: animationFrames.length, colors: 5, transparent: true, loop: true });
  const exported = pixel('render', [recipeFile, '--out', path.join(output, 'exports', id), '--animation', 'idle', '--expect', expectation], `${id}-render`);
  if (exported.check && exported.check.ok === false) throw new Error(`${id}: export expectation failed`);
  for (const [mode, extra] of [['color',[]], ['silhouette',['--view','silhouette']], ['onion',['--view','onion','--animation','idle']]])
    pixel('inspect', [recipeFile, '--out', path.join(output,'reviews',`${id}-${mode}.png`), '--native', '--scale','3','--diagnostics', ...extra], `${id}-inspect-${mode}`);
  pixel('gif', [recipeFile, '--out', path.join(output, 'reviews', `${id}-idle-3x.gif`), '--animation', 'idle', '--scale', '3'], `${id}-gif`);
  const oldAsset = previousManifest.assets.find(a=>a.id===id);
  for (const frame of rendered.frames) manifestAssets.push({ ...oldAsset, id: `${id}-${frame.name}`, source: rel(path.join(output,'exports',id,'frames',`${frame.name}.png`)), position: [0,0] });
  provenance.push({ id, name: staff.name, source: rel(sourceFile), source_sha256: sha(fs.readFileSync(sourceFile)), copied_sha256: sha(fs.readFileSync(copied)),
    source_grid: rel(gridFile), source_grid_sha256: sha(fs.readFileSync(gridFile)),
    eye_coordinates: staff.eyes, palette_roles: staff.materials, stationary_regions: config.hands,
    fixed_rows: [config.seam,47], moving_region: [config.x0,config.y0,32-config.x0,config.seam-config.y0], max_displacement_native_px: 1 });
  results.push({ id, name: staff.name, source_exact_still: differences(original.data, rendered.frames[0].data).length===0,
    loop_duration_ms: 9000, loop_join_changed_pixels: seamPixels, frame_count: rendered.frames.length, timeline: phaseTable, frames: frameReports });
  reviewItems.push({ id, name: staff.name, concept: staff.concept, timeline: phaseTable, frames: frameReports, ...config });
  process.stdout.write(`${staff.name}: ${rendered.frames.length} frames, 5 colors, fixed hands/feet, loop join 0px\n`);
}

// Keep the project's fixed cleanup/grid/material/validation pipeline and verify that it changes no RGBA pixel.
const manifest = { ...previousManifest, feature: 'F25 Pixelbolt stationary idle candidate', output: rel(path.join(output,'pipeline')), assets: manifestAssets };
json(path.join(output,'manifest.json'), manifest);
const python = process.env.PYTHON || path.join(process.env.USERPROFILE || '', '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe');
const processed = spawnSync(fs.existsSync(python) ? python : 'python', [path.join(root,'tools/process_pixel_art.py'), rel(path.join(output,'manifest.json'))], { cwd: root, encoding: 'utf8', maxBuffer: 16*1024*1024 });
fs.writeFileSync(path.join(output,'logs','fixed-pipeline.txt'), processed.stdout + processed.stderr);
if (processed.status !== 0) throw new Error(`Fixed pipeline: ${processed.stdout}\n${processed.stderr}`);
for (const asset of manifestAssets) {
  const a=decodePNG(fs.readFileSync(path.join(root,asset.source))), b=decodePNG(fs.readFileSync(path.join(output,'pipeline',`${asset.id}-native.png`)));
  if (differences(a.data,b.data).length) throw new Error(`${asset.id}: fixed pipeline modified the exact palette frames`);
}
json(path.join(output,'source','provenance.json'), { status:'candidate', approved_by_user:false, runtime_integrated:false,
  tool:{name:'Pixelbolt',version:packageInfo.version,repository:'https://github.com/skulitom/Pixelbolt',license:'MIT'}, assets:provenance });
json(path.join(output,'validation.json'), { status:'passed', art_status:'candidate_not_approved', runtime_integrated:false,
  size, display_scale:3, global_palette_additions:0, fixed_pipeline_pixel_changes:0,
  source_stationary_exact:true, animation_description:'3s one-native-pixel upper-body breath, 4.5s 120ms blink, 9s exact loop',
  limitations:['v2 appearance has not been approved','User-reserved face, clothing and shoe designs unchanged','Idle preview only; no runtime connections','Integer pixel motion has two breath positions; not interpolated motion'], assets:results });
json(path.join(output,'commands.json'), logs);
fs.writeFileSync(path.join(output,'asset.brief.md'), `# F25 직원 대기 움직임 후보\n\n기존 v2 외형은 미승인이다. 얼굴·의상·신발은 재디자인하지 않았으며 런타임에 연결하지 않았다.\n\n- 원본 32×48 / 표시 3배 / 정수 좌표 / 원본 재질별 5색 / #241C32 외곽선\n- 3초 호흡: 지정 상체 픽셀을 1행 위로 이동하고 어깨 접합 1행을 원본으로 유지한다. 회전·리샘플링 없음.\n- 4.5초마다 120ms 깜빡임: 위쪽 눈 1픽셀만 해당 피부색으로 닫는다. 아래 눈 픽셀 유지.\n- 손·물뿌리개·플라스크·등불 지팡이·발·y46 접점 고정. 판매·조제는 y30+, 재배는 y32+, 길잡이는 y31+행 고정.\n- 기존 원본 실루엣 특징(올림머리/모자/고글/후드)과 재질·조명은 그대로 유지한다.\n- 루프 9초. 첫 프레임과 마지막 프레임은 같은 원본 정지 픽셀이다.\n- 반복 프레임과 짧은 눈 픽셀은 의도된 hold/눈이다. 자동 cleanup은 사용하지 않는다.\n- Pixelbolt import/patch/render/inspect/GIF → 기존 process_pixel_art.py → RGBA 동일성 검사.\n\n재현: node tools/build_f25_staff_motion_v1.mjs (기존 생성본 재현은 --force).\n`);
const html = `<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>직원 4명 · 작은 대기 움직임</title>
<style>*{box-sizing:border-box}body{margin:0;background:#f5f2e9;color:#241c32;font:16px/1.6 system-ui,'Malgun Gothic',sans-serif}main{max-width:1120px;margin:auto;padding:40px 28px}h1{font-size:28px;line-height:1.25;margin:8px 0 12px}h2{font-size:19px;margin:0}p{margin:8px 0}.eyebrow{font-size:12px;font-weight:700;letter-spacing:.12em;color:#53695b}.notice{background:#fff5d6;border:1px solid #d7bf8b;border-radius:12px;padding:13px 18px}.toolbar{display:flex;gap:12px;flex-wrap:wrap;align-items:center;margin:22px 0}button,select{font:inherit;background:#fff;border:1px solid #bbb4a6;border-radius:8px;padding:7px 14px;color:inherit}button{cursor:pointer}input{accent-color:#53695b}.cards{display:grid;grid-template-columns:repeat(4,1fr);gap:16px}.card{background:#fffdf7;border:1px solid #d9d9ce;border-radius:14px;padding:17px}.role{min-height:50px;color:#647263;font-size:13px}.comparison{display:grid;grid-template-columns:1fr 1fr;gap:8px}.slot{height:188px;display:flex;align-items:center;flex-direction:column;justify-content:flex-end;background:var(--stage,#dbe5d8);border-radius:9px;padding:9px 0}.slot span{font-size:12px;color:#4a5650;margin-top:5px}.sprite{width:96px;height:144px;image-rendering:pixelated;image-rendering:crisp-edges;flex:none}.tag{font-size:12px;color:#53695b;margin-top:12px}.footer{margin-top:24px;font-size:14px;color:#555}.links a{color:#24566a}table{border-collapse:collapse;width:100%;font-size:14px;margin-top:16px}td,th{text-align:left;padding:8px;border-bottom:1px solid #d8d8cc}th{font-weight:600}.status{font-variant-numeric:tabular-nums;color:#647263;font-size:13px}@media(max-width:1000px){.cards{grid-template-columns:repeat(2,1fr)}}@media(max-width:580px){.cards{grid-template-columns:1fr}main{padding:24px 16px}}@media print{.toolbar{display:none}}</style>
<main><div class="eyebrow">F25 / PIXELBOLT 0.11.0 / MOTION STUDY</div><h1>직원 4명 · 작은 대기 움직임</h1><p>왼쪽은 기존 정지 그림, 오른쪽은 같은 외형에 호흡과 눈깜빡임만 넣은 후보입니다.</p><p class="notice"><strong>외형 미승인 · 게임 미연결</strong><br>얼굴·의상·신발은 기존 v2 그대로입니다. 사용자가 직접 수정할 디자인에 대한 승인으로 취급하지 않습니다.</p>
<div class="toolbar"><button id="play">일시정지</button><button id="restart">처음부터</button><label>배경 <select id="background"><option value="#dbe5d8">세이지</option><option value="#ffffff">흰색</option><option value="#4a3c52">짙은 자주</option></select></label><label><input id="sync" type="checkbox"> 같은 위상</label><label>상태 <select id="state"><option value="motion">움직임</option><option value="still">정지</option><option value="inhale">들숨</option><option value="blink">깜빡임</option><option value="inhale-blink">들숨+깜빡임</option></select></label><span id="status" class="status"></span></div>
<section class="cards">${reviewItems.map((it,i)=>`<article class="card"><h2>${it.name}</h2><div class="role">${it.concept}</div><div class="comparison"><div class="slot"><img class="sprite" src="source/${it.id}.png" alt="${it.name} 기존 정지"><span>기존 v2</span></div><div class="slot"><canvas class="sprite" width="32" height="48" data-index="${i}" aria-label="${it.name} 대기 움직임"></canvas><span>호흡 + 깜빡임</span></div></div><div class="tag">32×48 · 표시 3배 · 5색<br>손·소품·발 고정</div><p class="links"><a href="reviews/${it.id}-color.png">프레임 보기</a> · <a href="reviews/${it.id}-idle-3x.gif">GIF</a></p></article>`).join('')}</section>
<div class="footer"><p><strong>동작:</strong> 상체가 원본 1픽셀 올라오는 3초 호흡과 4.5초 간격의 120ms 깜빡임입니다. 루프는 9초이며 처음과 끝의 그림이 같습니다. 자연스러운지 판단할 수 있도록 네 명의 시작 위상을 조금씩 달리했습니다.</p><p>검사: 정지 원본 픽셀 동일 · 새 색 0 · 반투명 0 · 경계색 위반 0 · 손/소품/발 변화 0 · 접지 y46 · 기존 고정 후처리 후 픽셀 변화 0.</p><p class="links"><a href="validation.json">검증 JSON</a> · <a href="source/provenance.json">원본 기록</a> · <a href="contact-sheet.png">전체 연락시트</a> · <a href="recipes/">수정 가능한 recipe</a></p><p>검사를 통과했다는 사실은 외형이나 움직임의 사용자 승인을 뜻하지 않습니다.</p></div></main>
<script>const items=${JSON.stringify(reviewItems.map(x=>({id:x.id,timeline:x.timeline})))};const canvases=[...document.querySelectorAll('canvas')];let elapsed=0,previous=performance.now(),playing=!matchMedia('(prefers-reduced-motion: reduce)').matches;const images={};let ready=false;Promise.all(items.flatMap(item=>['still','inhale','blink','inhale-blink'].map(name=>new Promise((resolve,reject)=>{const image=new Image();image.onload=()=>{images[item.id+'/'+name]=image;resolve()};image.onerror=reject;image.src='exports/'+item.id+'/frames/'+name+'.png'})))).then(()=>ready=true);const play=document.getElementById('play');function updateButton(){play.textContent=playing?'일시정지':'재생'}updateButton();play.onclick=()=>{playing=!playing;updateButton()};document.getElementById('restart').onclick=()=>elapsed=0;document.getElementById('background').onchange=e=>document.body.style.setProperty('--stage',e.target.value);function tick(now){if(playing)elapsed+=now-previous;previous=now;const state=document.getElementById('state').value;const synchronized=document.getElementById('sync').checked;if(ready)canvases.forEach((canvas,i)=>{const item=items[i];const t=(elapsed+(synchronized?0:i*630))%9000;const phase=item.timeline.find(p=>t>=p.time&&t<p.time+p.duration);const name=state==='motion'?(phase.breath?(phase.blink?'inhale-blink':'inhale'):(phase.blink?'blink':'still')):state;const ctx=canvas.getContext('2d');ctx.imageSmoothingEnabled=false;ctx.clearRect(0,0,32,48);ctx.drawImage(images[item.id+'/'+name],0,0);canvas.dataset.frame=name});document.getElementById('status').textContent=(elapsed%9000/1000).toFixed(1)+' / 9.0초';requestAnimationFrame(tick)}requestAnimationFrame(tick);</script></html>`;
let nativeIndex=0;
const reviewedHTML=html.replace('</style>','.native{margin-top:10px}.native .sprite{width:32px;height:48px}.native .slot{height:82px}</style>')
  .replaceAll('</div></div><div class="tag">',()=>{const i=nativeIndex++,item=reviewItems[i];return `</div></div><div class="comparison native"><div class="slot"><img class="sprite" src="source/${item.id}.png" alt="${item.name} 원본 1배"><span>원본 1배</span></div><div class="slot"><canvas class="sprite" width="32" height="48" data-index="${i}" aria-label="${item.name} 동작 1배"></canvas><span>동작 1배</span></div></div><div class="tag">`;})
  .replace('canvases.forEach((canvas,i)=>{const item=items[i];','canvases.forEach((canvas)=>{const i=Number(canvas.dataset.index);const item=items[i];');
fs.writeFileSync(path.join(output,'review.html'), reviewedHTML);

// A contact sheet is a Pixelbolt recipe too. Art is copied from exact grid sources, no separate raster drawing.
const sheetRecipe = { version:1,name:'staff-motion-contact',width:192,height:212,palette:{},frames:[{name:'comparison',pixels:[]}],sheet:{scale:3} };
const sheetOps=sheetRecipe.frames[0].pixels;
for (const [index,item] of reviewItems.entries()) {
  const r=readJSON(path.join(output,'recipes',`${item.id}.json`)), p=renderProject(r);
  const row=index*52+2;
  for(const [j,state] of ['still','inhale','blink','inhale-blink'].entries()) {
    const frame=p.frames.find(f=>f.name===state), pixels=[];
    for(let y=0;y<48;y++) for(let x=0;x<32;x++) { const c=colorAt(frame.data,x,y);if(c!=='transparent') pixels.push({x:14+j*45+x,y:row+y,color:c}); }
    sheetOps.push(...pixels);
  }
}
const sheetPath=path.join(output,'reviews','contact-sheet.json');
fs.writeFileSync(sheetPath,formatJSON(sheetRecipe));
pixel('inspect',[sheetPath,'--out',path.join(output,'contact-sheet.png'),'--scale','3','--background','#dbe5d8'], 'contact-sheet');
json(path.join(output,'commands.json'),logs);
process.stdout.write(`Created ${rel(output)}/review.html\n`);
