# 파이프라인 개요 (RTT 기반, headless Cooja)

본 문서는 현재 실험 파이프라인을 실행 → 분석 → 보고서 생성까지
end-to-end로 정리한다.

## 목표

- rpl-lite vs brpl을 동일 베이스 라우팅(OF만 다름)에서 비교
- 단계적 스트레스에서 붕괴 시점 탐지
- 재현 가능한 summary/thresholds/보고서(PDF) 산출

## 디렉터리 구조

```
scripts/        # Orchestration and sweeps
motes/          # Cooja motes: receiver_root, sender
tools/python/   # Log parsing and summary writer
tools/R/        # Analysis + report asset generation
results/        # Raw logs, summary.csv, thresholds.csv
docs/report/    # Report.tex, figures, tables, PDF
```

## 실행 흐름

1. **스윕 오케스트레이션**
   - `scripts/run_sweep_all.sh`가 Stage1 → Stage2 → Stage3 실행
   - 시작 시 `results/summary.csv`를 백업해 이전 결과와 섞이지 않도록 함
   - Stage 스크립트는 `SKIP_THRESHOLDS=1`로 per-run 임계점 계산을 생략

2. **단일 실행**
   - `scripts/run_experiment.sh`가 firmware 빌드, `.csc` 생성, headless Cooja 실행,
     CSV 추출 후 `results/summary.csv`에 반영
   - 파서는 동일 키 기준으로 덮어써 중복을 제거

3. **파싱**
   - `tools/python/log_parser.py`가 `CSV,RTT`(sender)와 `CSV,RX`(receiver) 처리
   - `pdr`, `avg_rtt_ms`, `p95_rtt_ms`, `invalid_run` 계산
   - `(mode, stage, n, seed, sr, ir, si)` 당 1행만 기록

4. **붕괴 시점 탐지**
   - `tools/R/find_thresholds.R`가 조건별 집계 후 모드/스테이지별 첫 붕괴 지점 탐색
   - 기준: `PDR < 0.90` 또는 `avg_delay_ms > 5000` 또는 제어 오버헤드 급증

5. **보고서 자산**
   - `tools/R/generate_report.R`가 그림/표를 `docs/report`에 생성
   - `docs/report/report.tex` → `docs/report/report.pdf`로 컴파일

## 단계 정의

- **Stage 1 (N 스윕)**:
  - 링크 품질 고정, `n_senders` 스윕
- **Stage 2 (링크 품질 스윕)**:
  - Stage1 rpl-lite 결과에서 N 선택
  - 성공/간섭 비율 스윕
- **Stage 3 (트래픽 스윕)**:
  - Stage2 rpl-lite 결과에서 knee 조건 선택
  - `send_interval_s` 스윕 (interval이 낮을수록 부하 증가)

## CSV 포맷

**Sender RTT (primary):**
```
CSV,RTT,seq,t0,t_ack,rtt_ticks,len
```

**Receiver RX (aux):**
```
CSV,RX,src_ip,seq,t_recv,len
```

## 산출물

- `results/summary.csv`: 실행별 지표 (키 기준 중복 제거)
- `results/thresholds.csv`: 모드/스테이지별 붕괴 지점
- `docs/report/report.pdf`: 그림/표 포함 보고서

## 자주 발생한 문제/해결

- Cooja mtype 경로: `motes/build/cooja -> ../../build/cooja` 심볼릭 링크
- Stage2/3 경로: Python 블록에서 `ROOT_DIR` 절대 경로 사용
- RTT 미기록: root_start 성공 처리, SR 루트 등록/경로 갱신, `CLOCK_SECOND=1000` 확인
