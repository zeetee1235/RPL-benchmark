# RPL-lite vs BRPL Stress Bench (Cooja, headless)

이 저장소는 **rpl-lite vs BRPL**을 동일 베이스(OF만 변경)에서 비교하고,
**붕괴 시점(collapse point)**을 찾기 위한 3단계 스윕을 자동화합니다.
모든 시뮬레이션은 headless Cooja로 실행됩니다.

## Quick Start

```bash
# 전체 스윕 (Stage 1 -> 2 -> 3)
./scripts/run_sweep_all.sh
```

## 실행 규칙 (재현성)

* 총 시간: 360s (WARMUP=60s, MEASURE=300s)
* 지표는 MEASURE 구간만 사용
* seed 고정으로 재현 가능
* `summary.csv`는 스윕 시작 시 자동 백업됨 (`run_sweep_all.sh`)

## 출력 구조

```
results/
  raw/<stage>/<mode>/Nxx_seedY_srX_irZ_siT.{csc,log,csv}
  summary.csv
  thresholds.csv
```

## summary.csv 컬럼

```
mode,stage,n_senders,seed,success_ratio,interference_ratio,send_interval_s,
rx_count,tx_expected,pdr,avg_rtt_ms,p95_rtt_ms,avg_delay_ms,p95_delay_ms,invalid_run,
dio_count,dao_count,duration_s,warmup_s,measure_s,log_path,csc_path
```

참고:
* `avg_delay_ms`/`p95_delay_ms`는 RTT 값과 동일
* `invalid_run=1`은 RTT 로그가 부족하거나 0으로만 채워진 run
* RTT 변환 기준: `CLOCK_SECOND` 기본 1000

## 단계 정의

### Stage 1: N 스윕
* 고정: `SUCCESS_RATIO=1.0`, `INTERFERENCE_RATIO=1.0`, `SEND_INTERVAL_S=10`
* N: `{5,10,15,20,25,30,40,50}`
* Seeds: `{1,2,3}`, Modes `{rpl-lite, brpl}`

### Stage 2: 링크 품질 스윕
Stage 1의 **rpl-lite** 결과로 N 2개 자동 선택:
* Stable N: `PDR >= 0.95` 최댓값
* Marginal N: `0.90 <= PDR < 0.95` 최댓값 (없으면 Stable N 다음)

파라미터:
* `SUCCESS_RATIO ∈ {1.0,0.95,0.9,0.85,0.8,0.75}`
* `INTERFERENCE_RATIO ∈ {1.0,0.95,0.9,0.85}`
* Seeds `{1,2,3}`, Modes `{rpl-lite, brpl}`

### Stage 3: 트래픽 스윕
Stage 2의 **rpl-lite** 결과에서 knee 조건 선택:
* `0.85 <= PDR <= 0.92` 중 0.90에 가장 가까운 조건
* 없으면 PDR이 0.90에 가장 가까운 조건

파라미터:
* `SEND_INTERVAL_S ∈ {20,10,5,2}` (내림차순)
* Seeds `{1,2,3}`, Modes `{rpl-lite, brpl}`

## 붕괴 시점 탐지

`tools/R/find_thresholds.R`는 조건별 집계 후 첫 붕괴 지점을 찾습니다:
* `PDR < 0.90` 또는 `avg_delay_ms > 5000`
* 또는 제어 오버헤드 급증 (`DIO+DAO`가 이전 조건의 2배 이상)

정렬 규칙:
* Stage 1: N 증가
* Stage 2: success_ratio ↓, interference_ratio ↓
* Stage 3: send_interval_s ↓

## 단일 실험 실행

```bash
./scripts/run_experiment.sh \
  --mode rpl-lite \
  --stage stage1 \
  --n-senders 20 \
  --seed 1 \
  --success-ratio 1.0 \
  --interference-ratio 1.0 \
  --send-interval 10
```

## Troubleshooting

- `mtype*.cooja` 로드 실패
  - `motes/build/cooja -> ../../build/cooja` 심볼릭 링크 추가
- Stage2/3 스윕에서 `summary.csv` 경로 오류
  - `ROOT_DIR`를 export하고 Python 블록에서 절대 경로 사용
- RTT 로그 없음 (`CSV,RTT` 없음)
  - root_start 반환값 처리, SR 루트 노드 등록/경로 갱신, `CLOCK_SECOND=1000` 확인
- 중복/오염된 summary 행
  - `log_parser.py` 동일 키 덮어쓰기, `find_thresholds.R` 중복 제거

## 환경 변수

* `CONTIKI`: Contiki-NG 루트 경로
* `DURATION_S`, `WARMUP_S`, `MEASURE_S`
* `TX_RANGE`, `INT_RANGE`
* `CLOCK_SECOND`
* `SIM_TIMEOUT_S`
