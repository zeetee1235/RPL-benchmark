# RPL vs BRPL 스트레스 실험 (Cooja, headless)

이 저장소는 **RPL 붕괴 시점(collapse point)**을 찾고 동일 조건에서 BRPL과 비교하기 위한 3단계 스트레스 테스트를 자동화합니다. 모든 시뮬레이션은 `cooja.jar -nogui=<file.csc>`로 headless 실행됩니다.

## 빠른 시작

```bash
# Stage 1: N 스윕
./scripts/run_sweep_stage1.sh

# Stage 2: 링크 품질 스윕 (stage 1에서 N 값 2개 자동 선택)
./scripts/run_sweep_stage2.sh

# Stage 3: 트래픽 스윕 (stage 2에서 knee 조건 자동 선택)
./scripts/run_sweep_stage3.sh
```

## 시뮬레이션 규칙 (재현성)

* 총 시간: **360s** (WARMUP=60s, MEASURE=300s)
* 지표는 MEASURE 구간만 사용
* 각 실행은 **seed**를 받아 동일 실행 재현 가능
* 로그는 `motes/receiver_root.c`에서 출력하는 고정 CSV 포맷을 파싱

## 출력 구조

```
results/
  raw/<stage>/<mode>/Nxx_seedY_srX_irZ_siT.{csc,log,csv}
  summary.csv
  thresholds.csv
```

* `raw/...csv`는 해당 실행의 RX CSV 라인만 포함
* `summary.csv`는 실행별 지표
* `thresholds.csv`는 `tools/R/find_thresholds.R`가 자동 생성

## 코드/스크립트 구조

```
motes/          # Cooja mote 앱 (receiver_root, sender)
scripts/        # 실행 스크립트 (run_experiment, run_sweep*)
tools/python/   # 파이프라인/파서 등 보조 스크립트
tools/R/        # 통계/시각화/검정 스크립트
```

## 실행별 요약 컬럼

`summary.csv` 컬럼:

```
mode,stage,n_senders,seed,success_ratio,interference_ratio,send_interval_s,
rx_count,tx_expected,pdr,avg_rtt_ms,p95_rtt_ms,avg_delay_ms,p95_delay_ms,invalid_run,
dio_count,dao_count,duration_s,warmup_s,measure_s,log_path,csc_path
```

참고:
* `dio_count`/`dao_count`는 전체 Cooja 로그에서 best-effort로 집계
* 지연/RTT 값은 `CLOCK_SECOND`(기본 1000)으로 변환
* `avg_delay_ms`/`p95_delay_ms`는 RTT 값과 동일하게 기록
* `invalid_run=1`은 RTT 로그 부족/0값으로 판단된 실패 run

## 단계 정의

### Stage 1: N 스윕

* 고정: `SUCCESS_RATIO=1.0`, `INTERFERENCE_RATIO=1.0`, `SEND_INTERVAL_S=10`
* N 스윕: `{5,10,15,20,25,30,40,50}`
* Seeds: `{1,2,3}`
* Modes: `{rpl-lite, brpl}`

### Stage 2: 링크 품질 스윕

Stage 1의 **rpl-lite** 결과로부터 N 값 2개를 자동 선택:

* **Stable N:** `PDR >= 0.95`를 만족하는 가장 큰 N
* **Marginal N:** `0.90 <= PDR < 0.95`를 만족하는 가장 큰 N
* Marginal N이 없으면 stable N 위의 다음 N 사용 (없으면 stable N)

스윕 파라미터:

* `SUCCESS_RATIO ∈ {1.0,0.95,0.9,0.85,0.8,0.75}`
* `INTERFERENCE_RATIO ∈ {1.0,0.95,0.9,0.85}`
* Seeds `{1,2,3}`, Modes `{rpl-lite, brpl}`

### Stage 3: 트래픽 스윕

Stage 2의 **rpl-lite** 결과에서 **knee** 조건 선택:

* `0.85 <= PDR <= 0.92`인 조건이 있으면 **0.90에 가장 가까운** 조건 선택
* 없으면 PDR이 **0.90에 가장 가까운** 조건 선택

스윕 파라미터:

* `SEND_INTERVAL_S ∈ {20,10,5,2}` (내림차순)
* Seeds `{1,2,3}`, Modes `{rpl-lite, brpl}`

## Troubleshooting / Known Pitfalls

- Cooja 로드 실패 (`mtype*.cooja` not found)
  - 해결: `motes/build/cooja -> ../../build/cooja` 심볼릭 링크 추가
- Stage2/3 스윕에서 `summary.csv` 경로 오류
  - 해결: `ROOT_DIR`를 export하고 Python 블록에서 절대 경로 사용
- RTT 로그가 안 찍힘 (`CSV,RTT` 없음)
  - 해결: root_start 반환값 처리 수정, SR 루트 노드 등록/경로 갱신, `CLOCK_SECOND=1000` 확인
- 결과 중복/오염
  - 해결: `log_parser.py` 동일 키 덮어쓰기, `find_thresholds.R` 중복 제거

## 붕괴 시점 탐지

`tools/R/find_thresholds.R`는 `summary.csv`를 조건별로 집계해 모드/스테이지별 첫 붕괴 지점을 찾습니다:

* `PDR < 0.90` **또는** `avg_delay_ms > 5000`
* **또는** 제어 오버헤드 급증 (`DIO+DAO`가 이전 조건의 2배 이상일 때)

스윕 순서:

* Stage 1: N 증가
* Stage 2: success_ratio ↓ 다음 interference_ratio ↓
* Stage 3: send_interval_s ↓

## 분석/시각화

`tools/R/analyze_results.R`는 `summary.csv`를 기반으로 단계별 요약과 Stage 1 표/그래프를 생성합니다.

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

### 선택적 환경 변수 오버라이드

* `CONTIKI`: Contiki-NG 루트 경로
* `DURATION_S`, `WARMUP_S`, `MEASURE_S`
* `TX_RANGE`, `INT_RANGE`
* `CLOCK_SECOND`
* `SIM_TIMEOUT_S`

## 참고

* 필요 시 Cooja 빌드:
  ```bash
  (cd $CONTIKI/tools/cooja && ./gradlew jar)
  ```
