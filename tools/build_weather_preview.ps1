$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$outputRoot = Join-Path $projectRoot 'assets/weather/v1'
$manifest = Get-Content -LiteralPath (Join-Path $outputRoot 'manifest.json') -Raw | ConvertFrom-Json
$data = @{}
foreach ($property in $manifest.assets.PSObject.Properties) {
    $path = Join-Path $outputRoot $property.Value.file
    $data[$property.Name] = @{ src = 'data:image/png;base64,' + [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)); file = $property.Value.file; size = $property.Value.size }
}
for ($frameIndex = 0; $frameIndex -lt 4; $frameIndex++) {
    $filename = 'rain_frame_' + $frameIndex + '_96x96.png'
    $data['rain_frame_' + $frameIndex] = @{ src = 'data:image/png;base64,' + [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $outputRoot $filename))); file = $filename; size = @(96,96) }
}
foreach ($name in @('keeper', 'traveler')) {
    $path = Join-Path $projectRoot ('assets/characters/animations_v1/' + $name + '_idle_48x64.png')
    $data[$name] = @{ src = 'data:image/png;base64,' + [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) }
}
$html = @'
<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>달그늘 물약상점 · 투명 날씨 오브젝트</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#1d1924;color:#eee6d9;font:15px/1.6 system-ui,'Malgun Gothic',sans-serif}main{max-width:1000px;padding:28px 24px;margin:auto}h1{font-size:26px;margin:0 0 5px}p{color:#c6b7cb;margin:0 0 20px}.controls{display:flex;align-items:center;gap:15px;flex-wrap:wrap;margin-bottom:18px}label{display:flex;gap:7px;align-items:center}button,select{font:inherit;background:#34293f;border:1px solid #6f5978;border-radius:7px;padding:7px 10px;color:#eee6d9;cursor:pointer}input{accent-color:#cfaa72}#desktop{max-width:816px;aspect-ratio:408/248;position:relative;overflow:hidden;background:#17242e;border-radius:12px;border:1px solid #54445f}.doc{position:absolute;inset:8% 15% 20% 6%;background:#253543;border:1px solid #3b4c5d;border-radius:8px;padding:18px;color:#91b1cb;font-size:13px}.doc i{display:block;background:#718496;opacity:.27;height:7px;border-radius:2px;width:70%;margin-top:19px}.doc i:nth-child(2n){width:88%}#desktop.light{background:#e8e3da}#desktop.light .doc{background:#fffdf7;color:#736b76;border-color:#c7c0bb}#desktop.light .doc i{background:#7b7482}canvas{position:absolute;inset:0;width:100%;height:100%;image-rendering:pixelated}.legend{margin:12px 0 28px;color:#bfaec8;font-size:13px}.assets{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px}.asset{padding:14px;border:1px solid #493a55;border-radius:9px;background:#28212f}.asset h2{font-size:16px;margin:0}.swatches{display:flex;align-items:center;justify-content:center;height:130px;margin:10px 0;background:repeating-conic-gradient(#39303f 0% 25%,#302837 0% 50%) 50%/16px 16px;border-radius:6px;overflow:hidden}.swatches img{image-rendering:pixelated;max-width:100%;max-height:125px;object-fit:contain}.asset a{color:#e3c194;font-size:12px;word-break:break-all}.asset small{display:block;color:#bbacc5}footer{font-size:12px;color:#b7a8c0;margin-top:22px}
</style><main><h1>투명 날씨 오브젝트</h1><p>하늘 배경 없이 해·달·구름·비를 독립적으로 배치하는 시안입니다.</p>
<div class="controls"><label>시간 <select id="time"><option value="day">낮</option><option value="night">밤</option></select></label><label>날씨 <select id="weather"><option value="clear">맑음</option><option value="rain" selected>비</option></select></label><label><input type="checkbox" id="cloud" checked>구름</label><label><input type="checkbox" id="rain" checked>빗줄기</label><label>재생 <select id="playback"><option value="frames">4프레임 반복 · 8fps</option><option value="scroll">부드러운 스크롤</option></select></label><label>비 속도 <input id="speed" type="range" min="0" max="2" step="0.1" value="1"></label><output id="frame-status">프레임 1 / 4</output><button id="background">밝은 문서에서 보기</button></div>
<div id="desktop"><div class="doc">작업 중인 문서<i></i><i></i><i></i><i></i><i></i></div><canvas id="preview" width="408" height="248" aria-label="배경이 투명한 날씨 합성 미리보기"></canvas></div>
<div class="legend">구름은 독립 레이어이며, 빗줄기만 1 → 2 → 3 → 4 → 1 순서로 반복합니다. 4프레임 방식과 스크롤 방식을 비교할 수 있습니다. 문서·캐릭터는 배치 확인용입니다.</div>
<section id="assets" class="assets"></section><footer>날씨 오브젝트 7개 + 비 애니메이션 4프레임 · 투명 RGBA · 정수 배율 / nearest 필터 권장 · 게임 적용 전 에셋 미리보기</footer></main>
<script>
const data=__WEATHER_DATA__;
const labels={sun:'해 · 낮 / 맑음',moon:'초승달 · 밤',star:'별 · 밤',cloud_clear:'밝은 구름',cloud_rain:'비구름 · 구름만',rain:'빗줄기 · 비만',raindrop:'빗방울 1개 · 파티클용'};
const images={};const ready=Promise.all(Object.entries(data).map(([key,value])=>new Promise((resolve,reject)=>{const image=new Image;image.onload=()=>resolve();image.onerror=()=>reject(Error(key));image.src=value.src;images[key]=image})));
for(const [key,label] of Object.entries(labels)){const value=data[key];const article=document.createElement('article');article.className='asset';const title=document.createElement('h2');title.textContent=label;const swatch=document.createElement('div');swatch.className='swatches';const image=document.createElement('img');image.src=value.src;image.alt=label;const size=value.size;image.style.width=size[0]*(size[0]<25?4:2)+'px';image.style.height=size[1]*(size[0]<25?4:2)+'px';swatch.append(image);const small=document.createElement('small');small.textContent=size.join(' × ')+' px · 투명 배경';const link=document.createElement('a');link.href=value.src;link.download=value.file;link.textContent=value.file;article.append(title,swatch,small,link);document.querySelector('#assets').append(article)}
const canvas=document.querySelector('#preview'),ctx=canvas.getContext('2d');ctx.imageSmoothingEnabled=false;
document.querySelector('#background').onclick=e=>{const light=document.querySelector('#desktop').classList.toggle('light');e.target.textContent=light?'어두운 문서에서 보기':'밝은 문서에서 보기'};
let offset=0,animationTime=0,last=performance.now();
function draw(key,x,y,scale=2,alpha=1){ctx.globalAlpha=alpha;const image=images[key];ctx.drawImage(image,Math.round(x),Math.round(y),image.width*scale,image.height*scale);ctx.globalAlpha=1}
function render(now){const delta=Math.min((now-last)/1000,.1);last=now;const speed=Number(document.querySelector('#speed').value);animationTime=(animationTime+delta*speed)%.5;offset=(offset+delta*384*speed)%192;const frameIndex=Math.floor(animationTime*8)%4;const frameMode=document.querySelector('#playback').value==='frames';document.querySelector('#frame-status').textContent=frameMode?'프레임 '+(frameIndex+1)+' / 4':'연속 이동';ctx.clearRect(0,0,408,248);const night=document.querySelector('#time').value==='night',rain=document.querySelector('#weather').value==='rain';const cloudOn=document.querySelector('#cloud').checked,rainOn=document.querySelector('#rain').checked;
if(night){draw('moon',74,12,2,rain?.6:1);[[153,18],[310,24],[332,67],[126,72]].forEach(([x,y],i)=>draw('star',x,y,1,i%2?.6:1))}else if(!rain){draw('sun',70,18)}
if(rain&&rainOn){ctx.save();ctx.beginPath();ctx.rect(136,56,192,157);ctx.clip();if(frameMode){draw('rain_frame_'+frameIndex,136,56,2,.75)}else{for(let row=-1;row<2;row++)draw('rain',136,56+row*192+offset,2,.75)}ctx.restore()}
if(cloudOn){if(rain)draw('cloud_rain',136,14);else draw('cloud_clear',185,37)}
draw('keeper',147,108);draw('traveler',294,108);requestAnimationFrame(render)}ready.then(()=>requestAnimationFrame(render)).catch(error=>{document.querySelector('.legend').textContent='이미지 로드 실패: '+error.message});
</script></html>
'@
$html = $html.Replace('__WEATHER_DATA__', (ConvertTo-Json -InputObject $data -Depth 6 -Compress))
[IO.File]::WriteAllText((Join-Path $outputRoot 'weather-preview.html'), $html, (New-Object Text.UTF8Encoding($false)))
Write-Output 'Created weather-preview.html: 4-frame rain playback and continuous-scroll comparison.'
