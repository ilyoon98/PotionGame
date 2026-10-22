# 생성 원본과 중간 검사

`generated-v1.png`와 `generated-v2.png`는 모자 포함 전신의 머리·몸통 비율이 기준과 달라 최종 에셋으로 사용하지 않은 원본이다. `body-v3.png`는 선택한 모자 없는 전신 시트, `hat-v1.png`는 별도 모자 생성 원본이다. 전체 프롬프트는 상위 `generation.json`에 있다.

등록 결과 및 진단 그림은 처리 중간 결과다. `*-registered.png`, `native-diagnostic.png`, `*inspection-8x.png`를 최종 확인표로 사용하지 않는다. 최종 원본은 상위 `frames/` 및 `body-frames/`, 확인표는 상위 `review.html`과 `keyframes-review.png`다.
