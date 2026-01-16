# 문제점 및 진행 상황 정리

본 문서는 실험 파이프라인에서 확인된 문제와 해결 여부를 간단히 정리한다.

## 현황 요약

- BRPL stage1 재실행 결과는 정상 수신(PDR=1.0)으로 확인됨
- 분석 스크립트(`analyze_results.py`)는 raw CSV 컬럼 불일치로 아직 실패
- `summary.csv`에 동일 조건 중복 행이 누적되어 있음
- RTT 기반 실험 스윕 완료 (rpl-lite vs brpl) 및 정상 집계 확인

## 미해결 이슈

1. 분석 스크립트 컬럼 불일치
   - `analyze_results.R`가 `delay_ms`를 기대하지만 raw CSV는 `delay_ticks`
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

5. rpl/brpl 붕괴시점 예측 실패
   - rpl은 붕괴하지않고 brpl이 먼저 낮은 조건에서 붕괴함


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

### RTT 전환 후 단일 run 테스트 (2026-01-15)

- 실행: `scripts/run_experiment.sh --mode rpl-classic --stage stage1 --n-senders 5 --seed 1`
- Cooja 로드 실패: `motes/build/cooja/mtype*.cooja` 라이브러리 없음
  - 에러: `Cannot open library: .../motes/build/cooja/mtype*.cooja`
  - 결과: 시뮬레이션 미실행, CSV 비어 있음
- `tools/R/find_thresholds.R` 실행 중 `order()` 길이 불일치 오류 발견 후 수정 완료

### RTT 전환 후 단일 run 테스트 (rpl-lite 기준, 2026-01-15)

- 실행: `scripts/run_experiment.sh --mode rpl-lite --stage stage1 --n-senders 5 --seed 1`
- 동일 증상으로 Cooja 로드 실패 (`motes/build/cooja/mtype*.cooja`)
- `tools/R/find_thresholds.R`는 정상 종료(출력 생성)

### Cooja 라이브러리 경로 수정 및 Stage1 스윕 재시도 (2026-01-15)

- `motes/build/cooja -> ../../build/cooja` 심볼릭 링크 추가로 로드 실패 해결
- 단일 run 재시도 성공 (rpl-lite, N=5, seed=1)
- `scripts/run_sweep_stage1.sh` 실행은 120s 타임아웃으로 중단됨
  - rpl-lite N=5~25, brpl N=5~25 일부까지 진행됨(로그 기준)

### RTT Echo 경로 디버깅 (rpl-lite, 2026-01-15)

- `root_start()` 반환값(0=성공)을 잘못 해석해 루트 시작 실패 로그가 반복됨 → 성공 판정으로 수정
- SRH 오류:
  - 초기: `SRH root node not found` → 루트 SR 노드 등록 추가
  - 이후: `SRH no path found to destination` → 수신 시점에 SR 경로 업데이트 추가
- Echo 응답 주소가 root로 찍히던 문제 → 수신 주소 복사 후 send/log 처리
- `CLOCK_SECOND` 기본값 128로 RTT 윈도우가 전부 필터됨 → 1000으로 수정
- 결과: `CSV,RTT` 로그 정상 생성, 요약에 RTT/ PDR 정상 반영됨 (rpl-lite N=5 seed=1)

### 전체 RTT 스윕 결과 (rpl-lite vs brpl, 2026-01-15)

- `results/summary.csv` 총 360행, `invalid_run=0`만 존재
- brpl: stage1~3 붕괴 없음
- rpl-lite:
  - stage2 붕괴: `N=50, sr=1.0, ir=0.95, si=10` (pdr_med≈0.888, rtt_med_ms≈599, collapse_frac=2/3)
  - stage3 붕괴: `N=25, sr=0.85, ir=0.9, si=2` (pdr_med≈0.879, rtt_med_ms≈591, collapse_frac=1)
- 평균 PDR 요약:
  - rpl-lite: stage1 0.957, stage2 0.890, stage3 0.909
  - brpl: stage1 0.995, stage2 0.972, stage3 0.993

## 다음 단계

1. `analyze_results.py`를 raw CSV 포맷(`delay_ticks`)에 맞게 수정
2. `summary.csv` 중복 제거 기준 정의 후 정리
3. rpl-lite vs brpl 비교로 정렬(동일 베이스에서 OF만 비교)

## 시행착오/해결 기록

1. Cooja 로드 실패 (mtype 라이브러리 경로)
   - 증상: `motes/build/cooja/mtype*.cooja` 없음으로 시뮬레이션 실패
   - 원인: Cooja가 `motes/build/cooja` 경로를 참조하지만 실제 빌드 출력은 `build/cooja`
   - 해결: `motes/build/cooja -> ../../build/cooja` 심볼릭 링크 추가

2. Stage2/3 스윕 시작 실패 (`summary.csv` 경로)
   - 증상: `results/summary.csv`를 찾지 못함
   - 원인: `scripts/`에서 실행 시 상대 경로가 달라짐
   - 해결: `ROOT_DIR`를 export하고 Python 블록에서 절대 경로 사용

3. RTT 로그가 전혀 생성되지 않음
   - 증상: `CSV,RTT` 없음, `invalid_run=1`만 누적
   - 원인:
     - root_start 성공 판정 오류(0=성공)
     - SRH 루트 노드 미등록 및 경로 미갱신
     - echo 응답 주소 로그가 root로 찍힘
     - `CLOCK_SECOND` 불일치(128 vs 실제 1000)로 측정 구간 필터링
   - 해결:
     - root_start 반환값 처리 수정
     - SR root 노드 등록 + 수신 시 SR 경로 업데이트
     - echo 주소 복사 후 전송/로그
     - `CLOCK_SECOND` 기본값 1000으로 변경

4. 요약 CSV 중복/오염
   - 증상: 동일 조건+seed 행이 누적되어 집계 왜곡
   - 해결: `log_parser.py`에서 동일 키 덮어쓰기, `find_thresholds.R`에서 중복 제거
