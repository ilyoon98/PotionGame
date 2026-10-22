# 게시된 픽셀 런타임 아트 v1

2026-10-15 요청으로 v9 마법 전달 흐름과 새 캐릭터를 실제 게임에 연결했다. 기존 정체성·팔레트·32×48 원본을 유지하며 새 그림을 생성하지 않았다.

`catalog.json`은 캐릭터5명의 포즈·움직임·손 앵커·물약별 잡는 점,36종 병·솥·색과 날씨·불꽃·가구·공통 바닥을 연결한다. fine 뱅크는 표시1픽셀 움직임을 포함한96×144프레임64개다. native 뱅크는32×48격자64개이며 축소 모드의 공통2배에 쓴다.

- 재게시: `tools/prepare_pixel_runtime_v1.py`. 기존 에셋 복사, native 뱅크 추출, 연속 바닥과 무손실·밉맵 없음·알파 경계 RGB 채우기 없음 설정을 만든다.
- 엔진 가져오기: Godot `--headless --editor --path . --quit`.
- 데이터 조회: `scripts/pixel_art_catalog.gd`. 장면·포즈 합성: `scripts/pixel_shop_scene.gd`.
- 실제 제조·판매는 기존 Shop/ShopState/PotionDisplay를 통해 결정한다. 렌더러가 경제를 진행시키거나 임의 재고를 추가하지 않는다.
- 편집·검토 소스는art/에 보존한다. 게임은 게시된assets/pixel_v1을 사용하고 검토 소스를 중복 가져오지 않는다.

검사와 실제 화면 기록: `art/runtime-reviews/pixel-v1/README.md`.
