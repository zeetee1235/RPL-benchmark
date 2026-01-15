# 문제점 및 진행 상황 정리

본 문서는 실험 파이프라인에서 확인된 문제와 해결 여부를 간단히 정리한다.

## 현황 요약

- BRPL stage1 재실행 결과는 정상 수신(PDR=1.0)으로 확인됨
- 분석 스크립트(`analyze_results.py`)는 raw CSV 컬럼 불일치로 아직 실패
- `summary.csv`에 동일 조건 중복 행이 누적되어 있음

## 미해결 이슈

1. 분석 스크립트 컬럼 불일치
   - `analyze_results.py`가 `delay_ms`를 기대하지만 raw CSV는 `delay_ticks`
   - Matplotlib 캐시 경로 권한 문제로 `MPLCONFIGDIR` 설정 필요

2. 결과 집계 중복 행 존재
   - `results/summary.csv`에 동일 조건 중복 행이 누적됨
   - 분석 시 평균 왜곡 가능

3. BRPL 혼잡/큐 반영 미흡
   - BRPL OF가 로컬 queuebuf만 반영
   - 부모 노드 혼잡 여부는 직접 반영되지 않음

4. 큐 패널티 계수 미확정
   - BRPL_QUEUE_WEIGHT 적정 값이 확정되지 않음
   - 안정화 후 단계적 스윕 필요

## 해결/완화된 이슈 (stage1 기준)

1. BRPL에서 PDR이 0으로 집계
   - stage1 재실행에서 최신 24개 조합 PDR=1.0 확인

2. reachable=false로 송신 차단
   - stage1 재실행에서 RX가 정상 발생해 차단 상태는 미재현
   - 추가로 reachable 자체를 직접 검증하는 로그 확인은 필요

3. BRPL 부모 선택/유지 불안정
   - `parent switch` 로그는 `(NULL IP addr) -> ...` 형태의 초기 선택만 확인
   - 비-NULL 부모 간 전환 로그는 확인되지 않음 (불안정 증상 미재현)

## 테스트 실행 결과

### analyze_results.py 실행 (2025-01-15)

- `delay_ms` 컬럼 없음으로 `KeyError`
- `seaborn` 누락으로 초기 실행 실패 (의존성 보완 완료)
- Matplotlib 캐시 경로 권한 문제 → `MPLCONFIGDIR=/tmp/matplotlib` 필요

### BRPL stage1 재실행 (2025-01-15)

- 범위: N=5~50, seed=1~3, sr=1.0, ir=1.0, si=10
- 최신 24개 조합 기준:
  - PDR=1.0
  - avg_delay_ms: 319.39 ~ 432.73
  - p95_delay_ms: 484.38 ~ 1296.88
  - rx_count/tx_expected: 13 ~ 18
- `summary.csv` 중복 행 누적 발생

## 다음 단계

1. `analyze_results.py`를 raw CSV 포맷(`delay_ticks`)에 맞게 수정
2. `summary.csv` 중복 제거 기준 정의 후 정리
3. BRPL OF의 혼잡 반영/패널티 계수 스윕