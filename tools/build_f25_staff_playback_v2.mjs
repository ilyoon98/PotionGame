/** Reproduce the F25 motion comparison with Pixelbolt 0.11.0. */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { importPNG, renderProject, encodePNG, decodePNG, formatJSON, framesGIF } from './pixelbolt/node_modules/pixelbolt/src/index.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'art/mockups/f25-staff-playback-v2');
const OLD = path.join(ROOT, 'art/mockups/f25-staff-alignment-v1');
const REVIEW = path.join(ROOT, '.verification/f25-staff-playback-godot');
const baseline = process.argv.includes('--baseline');
const json = (p, value) => fs.writeFileSync(p, JSON.stringify(value, null, 2) + '\n');
const read = p => JSON.parse(fs.readFileSync(p, 'utf8'));
const hash = b => createHash('sha256').update(b).digest('hex');
const rel = p => path.relative(ROOT, p).replaceAll('\\', '/');
const png = (p, f) => fs.writeFileSync(p, encodePNG(f.data, f.width, f.height));
const framesByPath = new Map();
const recipes = new Map();
const evidence = [];
for (const dir of ['frames', 'recipes', 'exports', 'logs']) fs.mkdirSync(path.join(OUT, dir), { recursive: true });
if (read(path.join(ROOT, 'tools/pixelbolt/node_modules/pixelbolt/package.json')).version !== '0.11.0') throw Error('Requires Pixelbolt 0.11.0');
fs.copyFileSync(path.join(ROOT, 'tools/pixelbolt/node_modules/pixelbolt/LICENSE'), path.join(OUT, 'PIXELBOLT-LICENSE.txt'));

const ids = ['staff_sales_assistant', 'staff_cultivation_assistant', 'staff_brewing_assistant', 'staff_expedition_guide'];
const names = ['판매 보조', '재배 보조', '조제 보조', '원정 길잡이'];
const refIds = ['keeper', 'traveler', 'mage', 'elf', 'rogue'];
const refNames = ['상점 주인', '여행자', '여마법사', '엘프', '고양이 도적'];
const states = ['still', 'inhale', 'blink', 'inhale_blink'];
const LENGTH = 18000;
function intervals(points, select) {
  const sorted = [...new Set(points)].sort((a, b) => a - b);
  return sorted.slice(0, -1).map((time, i) => ({ time, duration_ms: sorted[i + 1] - time, state: select(time) }));
}
function stateAt(frames, time, loop = LENGTH) {
  time %= loop;
  let end = 0;
  for (const frame of frames) { end += frame.duration_ms; if (time < end) return frame; }
  throw Error('Missing timeline position: ' + time);
}
function saveFrame(id, name, frame) {
  const file = `frames/${id}/${name}.png`;
  fs.mkdirSync(path.join(OUT, 'frames', id), { recursive: true });
  const f = { width: frame.width || 32, height: frame.height || 48, data: frame.data };
  png(path.join(OUT, file), f); framesByPath.set(file, f);
  return file;
}

// The runtime selects fine frames with three independent clocks, not sequential atlas playback.
const refTimes = Array.from({ length: 145 }, (_, i) => i * 125);
for (let t = 3600; t < LENGTH; t += 4500) refTimes.push(t, t + 250);
const indexAt = t => Math.floor(t / 125) % 16 + (t % 3000 >= 1500 ? 16 : 0) + (t % 4500 >= 3600 && t % 4500 < 3850 ? 32 : 0);
const referenceTimeline = intervals(refTimes, indexAt);
const references = refIds.map((id, i) => {
  const source = path.join(ROOT, `assets/pixel_v1/characters/${id}/idle-fine.png`);
  const atlas = { frames: Object.fromEntries(Array.from({ length: 64 }, (_, n) => [`f${n}`, { frame: { x: n % 16 * 96, y: Math.floor(n / 16) * 144, w: 96, h: 144 }, duration: 125 }])), meta: { scale: '1' } };
  const imported = importPNG(fs.readFileSync(source), { name: 'reference_' + id, atlas });
  const recipe = imported.project || imported.recipe;
  const frames = renderProject(recipe).frames;
  frames.forEach((frame, n) => saveFrame(id, 'f' + n, { ...frame, width: 96, height: 144 }));
  evidence.push({ id, source: rel(source), sha256: hash(fs.readFileSync(source)), native_size: [96, 144], display_scale: 1, source_frames: 64, timing_segments: referenceTimeline.length, loop_ms: LENGTH });
  return { id, name: refNames[i], width: 96, height: 144, scale: 1, loop_ms: LENGTH, frames: referenceTimeline.map(p => ({ path: `frames/${id}/f${p.state}.png`, duration_ms: p.duration_ms, state: 'f' + p.state })) };
});

const before = [], after = [];
const tuning = [
  { breath_start: 1500, breath_hold: 1200, blink_ms: 200, blinks: [3450, 8150, 12850, 16600] },
  { breath_start: 2050, breath_hold: 1100, blink_ms: 220, blinks: [2200, 7200, 11200, 16100] },
  { breath_start: 2650, breath_hold: 1250, blink_ms: 200, blinks: [4250, 9350, 13550] },
  { breath_start: 850, breath_hold: 1150, blink_ms: 220, blinks: [1150, 6250, 11850, 17050] }
];
for (const [i, id] of ids.entries()) {
  const original = read(path.join(OLD, 'recipes', id + '.json'));
  const rendered = renderProject(original);
  const baseFrames = Object.fromEntries(rendered.frames.slice(0, 4).map(f => [f.name, f]));
  for (const name of states) saveFrame(id, name, baseFrames[name]);
  const originalFrames = original.animations.idle.frames.map(name => {
    const f = original.frames.find(f => f.name === name);
    return { path: `frames/${id}/${f.from}.png`, duration_ms: f.duration, state: f.from };
  });
  before.push({ id: 'before_' + id, name: names[i], width: 32, height: 48, scale: 3, loop_ms: 9000, frames: originalFrames });
  const tune = tuning[i];
  const cuts = [0, LENGTH, ...tune.blinks.flatMap(t => [t, t + tune.blink_ms])];
  for (let t = tune.breath_start - 3000; t <= LENGTH; t += 3000) for (const n of [t, t + tune.breath_hold]) if (n > 0 && n < LENGTH) cuts.push(n);
  const phase = intervals(cuts, t => {
    const breath = (t - tune.breath_start + 3000) % 3000 < tune.breath_hold;
    const blink = tune.blinks.some(start => t >= start && t < start + tune.blink_ms);
    return breath ? (blink ? 'inhale_blink' : 'inhale') : (blink ? 'blink' : 'still');
  });
  const recipe = { ...original, frames: original.frames.slice(0, 4), animations: { still: { frames: ['still'], loop: true }, idle: { frames: phase.map((_, j) => 'idle_' + j), loop: true } } };
  recipe.frames.push(...phase.map((p, j) => ({ name: 'idle_' + j, from: p.state, duration: p.duration_ms })));
  const newRender = renderProject(recipe);
  // This revision edits timing only; every authored body state is preserved byte-for-byte.
  for (const f of newRender.frames) {
    const spec = recipe.frames.find(p => p.name === f.name), base = baseFrames[spec.from || f.name];
    if (Buffer.compare(Buffer.from(f.data), Buffer.from(base.data))) throw Error('Unexpected pixel edit: ' + id + '/' + f.name);
  }
  recipes.set(id, recipe);
  fs.writeFileSync(path.join(OUT, 'recipes', id + '.json'), formatJSON(recipe));
  const item = { id, name: names[i], width: 32, height: 48, scale: 3, loop_ms: LENGTH, frames: phase.map(p => ({ path: `frames/${id}/${p.state}.png`, duration_ms: p.duration_ms, state: p.state })) };
  after.push(item);
  evidence.push({ id, source: rel(path.join(OLD, 'recipes', id + '.json')), source_sha256: hash(fs.readFileSync(path.join(OLD, 'recipes', id + '.json'))), tuning: tune, changed_pixels: 0, timing_segments: phase.length, loop_ms: LENGTH, loop_seam_state_unchanged: item.frames[0].state === item.frames.at(-1).state });
}
const groups = [{ label: '기존 캐릭터 · 현재 게임의 실제 재생', items: references }, { label: '직원 · 수정 전 (동일 타이밍)', items: before }];
if (!baseline) groups.push({ label: '직원 · 수정 후 (개별 호흡과 깜빡임)', items: after });
const data = { title: '직원 대기 움직임 · 실제 속도 비교', duration_ms: LENGTH, groups };
json(path.join(OUT, 'review-data.json'), data);

function prepareLive() {
  const script = path.join(ROOT, 'tools/f25_staff_live_review.gd');
  if (!fs.existsSync(script)) return;
  fs.mkdirSync(REVIEW, { recursive: true });
  fs.cpSync(path.join(OUT, 'frames'), path.join(REVIEW, 'frames'), { recursive: true });
  fs.copyFileSync(script, path.join(REVIEW, 'review.gd'));
  fs.copyFileSync(path.join(ROOT, 'assets/fonts/pretendard/Pretendard-Regular.otf'), path.join(REVIEW, 'Pretendard-Regular.otf'));
  const nativeData = structuredClone(data);
  for (const group of nativeData.groups) for (const item of group.items) for (const f of item.frames) f.path = 'res://' + f.path;
  json(path.join(REVIEW, 'review.json'), nativeData);
  fs.writeFileSync(path.join(REVIEW, 'project.godot'), 'config_version=5\n[application]\nconfig/name="F25 Motion Review"\n[display]\nwindow/size/viewport_width=1040\nwindow/size/viewport_height=800\n[rendering]\nrenderer/rendering_method="gl_compatibility"\ntextures/canvas_textures/default_texture_filter=0\n');
}
prepareLive();
if (baseline) { console.log('Prepared original live motion for review'); process.exit(0); }

const CLI = path.join(ROOT, 'tools/pixelbolt/node_modules/pixelbolt/bin/pixelbolt.js');
for (const id of ids) {
  const recipeFile = path.join(OUT, 'recipes', id + '.json');
  for (const [command, args] of [['validate', [recipeFile]], ['render', [recipeFile, '--out', path.join(OUT, 'exports', id), '--animation', 'idle', '--force']], ['gif', [recipeFile, '--animation', 'idle', '--out', path.join(OUT, id + '.gif'), '--scale', '3', '--force']]]) {
    const result = spawnSync(process.execPath, [CLI, command, ...args], { cwd: ROOT, encoding: 'utf8' });
    if (result.status !== 0) throw Error(result.stderr || result.stdout);
    json(path.join(OUT, 'logs', id + '-' + command + '.json'), JSON.parse(result.stdout.replaceAll(ROOT.replaceAll('\\', '\\\\'), '.').replaceAll(ROOT.replaceAll('\\', '/'), '.')));
  }
}

// Pixelbolt draws the comparison at display resolution. Existing fine artwork stays at exact 1x.
const boardColors = ['#F3EFE5', '#E2E8DC', '#B6C7B0', '#53695B'];
const symbols = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!$%&()*+,-/:;<=>?@[]^_{}|~';
const colors = new Set(boardColors);
for (const f of framesByPath.values()) for (let j = 0; j < f.data.length; j += 4) if (f.data[j + 3]) colors.add('#' + [...f.data.slice(j, j + 3)].map(v => v.toString(16).padStart(2, '0')).join('').toUpperCase());
if (colors.size > symbols.length) throw Error('Too many display colors');
const palette = Object.fromEntries([...colors].map((c, i) => [symbols[i], c]));
const symbolFor = Object.fromEntries(Object.entries(palette).map(([a, b]) => [b, a]));
const grids = new Map();
for (const [file, f] of framesByPath) {
  const rows = [];
  for (let y = 0; y < f.height; y++) {
    let row = '';
    for (let x = 0; x < f.width; x++) {
      const j = (y * f.width + x) * 4;
      row += f.data[j + 3] ? symbolFor['#' + [...f.data.slice(j, j + 3)].map(v => v.toString(16).padStart(2, '0')).join('').toUpperCase()] : '.';
    }
    rows.push(row);
  }
  grids.set(file, rows);
}
const BOARD_W = 600, BOARD_H = 410;
function boardAt(time, pair = false) {
  const rows = pair ? [before, after] : [references, after];
  const ops = [{ op: 'rect', w: BOARD_W, h: BOARD_H, color: '#F3EFE5' }];
  const english = pair ? [['SALES', 'GARDENER', 'BREWER', 'GUIDE'], ['SALES', 'GARDENER', 'BREWER', 'GUIDE']] : [['KEEPER', 'TRAVELER', 'MAGE', 'ELF', 'ROGUE'], ['SALES', 'GARDENER', 'BREWER', 'GUIDE']];
  for (const [r, items] of rows.entries()) {
    const top = 34 + r * 200;
    ops.push({ op: 'text', x: 18, y: top - 23, text: r === 0 ? (pair ? 'STAFF / BEFORE' : 'CURRENT GAME / 1X SPEED') : 'STAFF / REVISED', color: '#53695B' });
    for (const [i, item] of items.entries()) {
      const x = 18 + i * 116;
      ops.push({ op: 'rect', x: x - 4, y: top - 3, w: 104, h: 151, color: '#E2E8DC' });
      ops.push({ op: 'line', x: x - 4, x2: x + 100, y: top + 141, y2: top + 141, color: '#B6C7B0' });
      const f = stateAt(item.frames, time, item.loop_ms);
      ops.push({ op: 'grid', x, y: top, rows: grids.get(f.path), scale: item.scale });
      ops.push({ op: 'text', x, y: top + 155, text: english[r][i], color: '#53695B' });
    }
  }
  return renderProject({ version: 1, name: 'motion_comparison', width: BOARD_W, height: BOARD_H, palette, frames: [{ name: 'view', ops }] }).frames[0];
}
for (const [name, pair] of [['together-1x', false], ['before-after-1x', true]]) {
  function* sequence() {
    for (let t = 0; t < LENGTH; t += 50) yield { ...boardAt(t, pair), width: BOARD_W, height: BOARD_H, name: 'time_' + t };
  }
  const gif = framesGIF(sequence(), { fps: { numerator: 20, denominator: 1 }, loops: 0 });
  fs.writeFileSync(path.join(OUT, name + '.gif'), gif.data);
  png(path.join(OUT, name + '.png'), { ...boardAt(0, pair), width: BOARD_W, height: BOARD_H });
}

const uri = file => 'data:image/png;base64,' + fs.readFileSync(path.join(OUT, file)).toString('base64');
const bank = Object.fromEntries([...framesByPath.keys()].map(file => [file, uri(file)]));
const html = `<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>직원 움직임 · 실제 속도 비교</title><style>
*{box-sizing:border-box}body{margin:0;background:#f3efe5;color:#241c32;font:15px/1.6 system-ui,'Malgun Gothic',sans-serif}main{max-width:1080px;margin:auto;padding:28px 24px}h1{margin:0;font-size:27px}h2{font-size:18px;margin:28px 0 12px}p{margin:8px 0}.toolbar{display:flex;gap:12px;align-items:center;flex-wrap:wrap;position:sticky;top:0;padding:14px 0;background:#f3efe5;z-index:2}button,select{font:inherit;border:1px solid #a9bba5;background:white;border-radius:7px;padding:6px 12px;cursor:pointer}.row{display:grid;grid-template-columns:repeat(5,1fr);gap:12px}.card{text-align:center;background:#fffdf7;border:1px solid #d1d8ca;border-radius:10px;padding:12px}.stage{width:96px;height:144px;background:#e2e8dc;margin:auto;position:relative}.stage:after{content:'';position:absolute;left:0;right:0;top:141px;border-top:1px solid #90a88a}.stage canvas{image-rendering:pixelated;width:96px;height:144px;position:relative;z-index:1}.state{font-size:12px;color:#63715c;min-height:20px}.note{padding:10px 14px;border-left:4px solid #718c59;background:#e5eadc}a{color:#24566a}@media(max-width:700px){.row{grid-template-columns:repeat(2,1fr)}}
</style><main><h1>직원 4명 · 실제 속도 움직임 비교</h1><p>기존 5명과 직원 수정 전·후를 같은 시계로 재생합니다. 기본 속도는 1배입니다.</p><p class="note">기존 캐릭터는 현재 게임의 fine 프레임 96×144를 그대로 사용합니다. 직원은 32×48을 최근접 3배로 표시합니다. 표시 크기와 발 기준은 같으며, 기존 그림은 수정하지 않았습니다.</p><div class="toolbar"><button id="play">일시정지</button><button id="reset">처음부터</button><select id="speed" aria-label="재생 속도"><option value="0.5">0.5배</option><option value="1" selected>1배 · 실제 속도</option><option value="2">2배</option></select><button id="still">정지 자세 비교</button><span id="time">로딩 중</span></div>${groups.map((g,r)=>`<h2>${g.label}</h2><section class="row">${g.items.map((item,i)=>`<article class="card"><strong>${item.name}</strong><div class="stage"><canvas width="${item.width}" height="${item.height}" data-row="${r}" data-item="${i}" aria-label="${item.name} 움직임"></canvas></div><div class="state" id="state-${r}-${i}"></div></article>`).join('')}</section>`).join('')}<p>수정: 네 명의 호흡 시점과 들숨 유지 시간을 분리하고, 깜빡임을 120ms에서 200~220ms로 조정했습니다. 눈 감는 간격도 서로 다르게 배치했습니다. 정렬된 신체와 손·발·소품 픽셀은 그대로입니다.</p><p><a href="together-1x.gif">기존+직원 GIF</a> · <a href="before-after-1x.gif">직원 전후 GIF</a> · <a href="validation.json">검사 기록</a></p><p>HTML과 Godot 비교 창은 원래 밀리초 타이밍으로 재생합니다. 공유 GIF는 20fps로 표본화한 18초 반복입니다. 아직 검토 후보이며 실제 게임 배치는 변경하지 않았습니다.</p></main><script>
const data=${JSON.stringify(data)},urls=${JSON.stringify(bank)};let playing=true,elapsed=0,last=null,speed=1,still=false;const bank={};const play=document.getElementById('play');play.onclick=()=>{playing=!playing;still=false;play.textContent=playing?'일시정지':'재생'};document.getElementById('reset').onclick=()=>{elapsed=0;still=false;last=null};document.getElementById('speed').onchange=e=>{speed=Number(e.target.value)};document.getElementById('still').onclick=()=>{still=true;playing=false;play.textContent='재생'};Promise.all(Object.entries(urls).map(([k,src])=>new Promise((resolve,reject)=>{const im=new Image();im.onload=()=>{bank[k]=im;resolve()};im.onerror=()=>reject(Error(k));im.src=src}))).then(()=>requestAnimationFrame(tick));function tick(now){if(last!==null&&playing)elapsed+=Math.min(now-last,250)*speed;last=now;document.querySelectorAll('canvas').forEach(c=>{const r=Number(c.dataset.row),i=Number(c.dataset.item),a=data.groups[r].items[i];let t=elapsed%a.loop_ms,end=0,f=a.frames[0];if(still){const key=r===0?'f0':'still';f=a.frames.find(x=>x.state===key)||f}else for(const v of a.frames){end+=v.duration_ms;if(t<end){f=v;break}}const ctx=c.getContext('2d');ctx.imageSmoothingEnabled=false;ctx.clearRect(0,0,c.width,c.height);ctx.drawImage(bank[f.path],0,0);document.getElementById('state-'+r+'-'+i).textContent=still?'정지 기준':f.state});document.getElementById('time').textContent=still?'정지 기준':(elapsed/1000).toFixed(1)+'초 · '+speed+'배';requestAnimationFrame(tick)}document.addEventListener('visibilitychange',()=>last=null);
</script></html>`;
fs.writeFileSync(path.join(OUT, 'review.html'), html);
json(path.join(OUT, 'validation.json'), { status: 'passed', engine: 'Pixelbolt 0.11.0', loop_ms: LENGTH, art_status: 'candidate', runtime_integrated: false, source_states_unchanged: true, gif_fps: 20, gif_frames: 360, references_runtime_function: 'scripts/pixel_art_catalog.gd:40', assets: evidence });
fs.writeFileSync(path.join(OUT, 'asset.brief.md'), '# 직원 대기 움직임 v2\n\n정렬된 32×48 원본과 4개 신체 상태는 유지한다. 판매의 올림머리/앞치마, 재배의 밀짚모자/물뿌리개, 조제의 고글/가운/플라스크, 길잡이의 후드/등불 지팡이를 보존한다. 기존 5색 재질·공통 외곽선·3/4 시점·발 y46을 유지한다.\n\n개선 대상은 네 명의 동시 호흡/깜빡임과 짧은 눈 감음이다. 호흡 주기는 3초로 유지하되 위상과 들숨 유지 시간을 달리한다. 눈 감음은 200~220ms, 각자의 간격으로 배치한다. 손·발·도구와 정지 자세를 바꾸지 않는다. 기존 게임 fine 그림은 승인된 내부 세부 움직임까지 포함해 1배, 직원은 원본 3배로 같은 96×144 영역에 재생한다.\n\n실제 속도 평가는 별도 Godot 창에서 수행하고 playback-review.md에 관찰 사실과 한계를 기록한다. 이 생성 도구의 검사 통과만으로 자연스러움을 단정하지 않는다.\n');
console.log('Built live comparison, individual exports, and two 18-second 20fps GIFs');
