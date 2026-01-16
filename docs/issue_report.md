# 문제점 및 진행 상황 정리

본 문서는 RPL/BRPL 스트레스 실험 파이프라인에서 확인된 이슈, 해결 여부, 그리고 향후 보완 계획을 요약한다.

---

## 1. 현황 요약

- **BRPL Stage1 재실행 결과 정상**
  - 최신 조합에서 PDR=1.0 확인
- **RTT 기반 스윕(rpl-lite vs brpl) 전체 완료**
  - `summary.csv` 및 `thresholds.csv` 정상 생성
- **분석 스크립트(`analyze_results.R`)는 일부 컬럼 불일치로 수정 필요**
- **결과는 현재 “초안(Preliminary)” 단계**
  - BRPL 쪽 데이터 검증 및 스윕 범위 확장이 필요

---

## 2. 핵심 미해결 이슈

### (1) 분석 스크립트 컬럼 불일치
- `analyze_results.R`는 `delay_ms`를 기대하지만 raw CSV는 `delay_ticks` 사용
- Matplotlib 캐시 경로 권한 문제 → `MPLCONFIGDIR=/tmp/matplotlib` 설정 필요

### (2) 결과 집계 중복 행
- `results/summary.csv`에 동일 조건이 누적
- 평균 및 임계값 계산 왜곡 가능
- → `log_parser.py` 및 `find_thresholds.R`에서 덮어쓰기/중복 제거 로직 추가 필요

### (3) BRPL 혼잡(Queue) 반영 한계
- BRPL OF가 **로컬 queuebuf**만 반영
- **부모 노드의 혼잡 상태**는 직접 반영되지 않음
- → 실제 Backpressure 특성이 충분히 반영되지 않았을 가능성

### (4) 큐 패널티 계수 미확정
- `BRPL_QUEUE_WEIGHT` 적정값 미결정
- 안정화 이후 **단계적 스윕(파라미터 튜닝)** 필요

### (5) 붕괴 시점 예측 불일치
- rpl-lite는 Stage2/3에서 붕괴 확인
- brpl은 동일 조건에서 붕괴가 발생하지 않음
- → BRPL 쪽 **추가 조건 확장 및 검증 실험 필요**

---

## 3. 해결/완화된 이슈 (Stage1 기준)

### (1) BRPL PDR=0 오판 문제
- 원인: summary 중복/오염
- 해결: 최신 24개 조합에서 PDR=1.0 확인

### (2) `reachable=false` 송신 차단
- Stage1 재실행에서 RX 정상 발생
- 차단 상태는 재현되지 않음

### (3) BRPL 부모 불안정
- 초기 `(NULL IP addr) -> parent` 로그만 관측
- 비정상적 부모 진동은 미재현

---

## 4. RTT 전환 및 디버깅 요약

### 주요 원인
- rpl-lite(non-storing)에서 **SRH(Source Routing Header) 생성 실패**
  → Echo가 sender로 되돌아가지 못해 RTT 미기록

### 수정 내역
- `root_start()` 반환값 처리 오류 수정
- SR 루트 노드 등록 + 수신 시 경로 갱신
- Echo 응답 주소 처리 수정
- `CLOCK_SECOND=1000`으로 동기화

### 결과
- `CSV,RTT` 로그 정상 생성
- rpl-lite N=5 seed=1에서 RTT/PDR 정상 반영

---

## 5. 전체 스윕 결과 요약 (2026-01-15)

### thresholds.csv

mode,stage,threshold_found,threshold_index,threshold_condition,pdr_med,rtt_med_ms,overhead_med,collapse_frac
brpl,stage1,FALSE,NA,NA,NA,NA,NA,NA
brpl,stage2,FALSE,NA,NA,NA,NA,NA,NA
brpl,stage3,FALSE,NA,NA,NA,NA,NA,NA
rpl-lite,stage1,FALSE,NA,NA,NA,NA,NA,NA
rpl-lite,stage2,TRUE,4,N=50, sr=1, ir=0.95, si=10,0.887841,599,7602,0.666666666666667
rpl-lite,stage3,TRUE,4,N=25, sr=0.85, ir=0.9, si=2,0.879384,591,5516,1


### 평균 성능 요약
- **rpl-lite**
  - stage1: 0.957
  - stage2: 0.890
  - stage3: 0.909
- **brpl**
  - stage1: 0.995
  - stage2: 0.972
  - stage3: 0.993

---

## 6. 현재 해석 (중요)

- 본 결과는 **초안(Preliminary Results)** 이며,
- **BRPL 쪽 붕괴가 아직 관측되지 않음**
- 이는 다음 가능성을 시사:
  1. BRPL이 실제로 더 안정적일 가능성
  2. **스윕 조건이 아직 충분히 가혹하지 않음**
  3. BRPL OF에서 혼잡 반영이 불충분할 가능성

- 따라서 **BRPL 데이터 검증 및 스윕 조건 확장**이 반드시 필요함.

---

## 7. 다음 단계

1. `analyze_results.R`를 raw CSV 포맷(`delay_ticks`)에 맞게 수정
2. `summary.csv` 중복 제거 기준 확정 및 정리
3. **BRPL 검증 실험 강화**
   - 큐 패널티 계수(`BRPL_QUEUE_WEIGHT`) 스윕
   - 더 높은 노드 수 / 더 나쁜 링크 품질 / 더 높은 트래픽
4. 스윕 조건 확대에 따른 **실행 시간 문제 해결**
   - 프리플라이트 테스트
   - 조기 중단(Early Stop)
   - 병렬 실행
   - seed 단계적 적용

---

## 8. 결론

- 현재 결과는 **RPL 붕괴 지점은 관측되었으나, BRPL은 아직 붕괴가 나타나지 않은 “초안 결과”**
- BRPL 성능을 단정하기에는 **조건이 충분히 강하지 않으며**,  
  **추가 스윕과 파라미터 튜닝이 필요**
- 다만, 실험 파이프라인(RTT, 자동 스윕, 임계점 탐지)은 정상 동작함이 검증됨
