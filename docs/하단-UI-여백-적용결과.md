# 하단 UI 여백 적용 결과

2026-10-10 · **구현 완료 / 격리 배치·입력 범위 검사 완료 / 실제 화면 조작 미실시**

하단의 지도 아이콘과 원정 수 버튼을 삭제했다. 원정은 기존 포스터 돋보기 또는 관리의 원정 탭에서 확인한다.

| 모드 | 하단 높이 | 전체 크기 | 버튼 위·아래 여백 |
| --- | --- | --- | --- |
| 본 작업실 | 40→52px | 540×300 | 각각 10px |
| 최소 | 32→44px | 256×172 | 각각 6px |
| 정보 | 40→52px | 320×124 | 각각 10px |

버튼 높이는 세 모드에서 28→32px로 통일했다. 이동·관리·축소·확대·닫기 순서와 가로 폭은 유지한다. 본 작업실 골드 영역은 82→100px로 넓히고 시간·날씨와의 간격을 각각 20px·16px로 늘렸다. 그림 높이 248/128px, 글씨 크기, 관리 내용, 제조/판매/FIFO·경제·저장·로그인/단일 실행 동작은 유지한다. 모드 전환은 오른쪽 하단 버튼 중심을 계속 기준으로 삼는다.

작업 공간 루트 `.verification/`의 최종 검사:

- `toolbar-verify_three_stage_modes.log`, `toolbar-verify_toolbar_spacing.log`, `toolbar-verify_window_mode_anchor.log`: 지도 노드/속성 부재, 큰 금액·버튼 여백·포스터/원정 탭 진입·반복 모드 전환·저장 복원과 기준점 PASS.
- `mini-readability-padding.log`, `mini-companion-padding.log`: 최소 모드의 글리프·코인·여백·큰 수 축약·정확한 툴팁·모드 복귀·경제/RNG 불변 PASS.
- `toolbar-wide.log`: 실제 모델 7상태·540×300/52px 바·배율·글씨·대표/개수·단계 복원·경제/RNG 불변 PASS.
- `bar-expedition_feedback.log`, `bar-desktop_regions.log`, `bar-management.log`: 실제 원정 UI·하단 전체 입력과 125/150/200% 경계·관리/구매/FIFO/자동 진행 PASS. 네이티브 입력 도우미는 크기 인수를 사용하므로 재빌드 없이 새 높이를 전달한다.

[하단 파일 미리보기](../.verification/wide-runtime/toolbar-2x.png) · [현재 작업실](../.verification/wide-runtime/day-crafting-2x.png)

미리보기는 실제 런타임 노드·그리기 명령으로 만든 파일 렌더이며 GPU 화면 캡처가 아니다. Computer Use·실제 창 이동/클릭/게임 실행·플레이어 저장·레지스트리 조작은 하지 않았다. 기존 게임을 닫고 다시 실행하면 새 하단이 반영된다. 이전 문서의 540×288·256×160·320×112는 이번 변경 전 크기다.
