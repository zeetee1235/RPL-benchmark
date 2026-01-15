# 문제점 및 막힌 부분 정리

본 문서는 현재 실험 파이프라인에서 확인된 문제점과 병목을 정리한 내용이다.

## 핵심 문제

1. BRPL에서 PDR이 거의 0으로 집계됨
   - 대부분의 BRPL 실험에서 `rx_count=0`이 반복됨.
   - 원인: 송신 자체가 발생하지 않거나, 라우팅이 유지되지 못하는 상태가 지속됨.
   - 관련 로그: `results/raw/stage1/brpl/*.log`

2. 라우팅 reachable 상태가 끝까지 false
   - `node_is_reachable()`가 false로 유지되어 sender가 송신을 막는 구조.
   - routing state 로그에서 `joined=1`이어도 `reachable=0`, `routes=0`이 반복됨.
   - 관련 코드: `rpl-benchmark/sender.c`

3. BRPL 부모 선택/유지 불안정
   - 로그 상 parent switch가 빈번하게 발생.
   - 부모가 붙었다가 해제되는 패턴이 반복됨.
   - 관련 코드: `rpl-benchmark/brpl-of.c`

4. DAO/Route 기반 reachable 판단과 실험 설계 충돌
   - RPL Lite는 “downward route”가 없으면 reachable=false로 판단.
   - BRPL에서 DAO/route가 안정적으로 형성되지 않아 reachable이 올라오지 않음.
   - 결과적으로 sender가 송신 자체를 차단.

5. 결과 집계 중복 행 존재
   - `summary.csv`에 동일 조건 중복 행이 존재함.
   - 분석 시 평균 왜곡 가능.
   - 관련 파일: `rpl-benchmark/results/summary.csv`

## 확인된 개선 시도

- BRPL OF 부모 선택 조건 완화
  - `ETX <= 512` -> `ETX <= 4096`
  - `path_cost <= 32768` -> `path_cost <= 60000`
  - 파일: `rpl-benchmark/brpl-of.c`

- sender 송신 조건 변경(진단용)
  - `node_is_reachable()` 대신 `node_has_joined()` 기준으로 송신
  - 이후 BRPL에서 TX/RX 로그가 발생하고 PDR이 정상값으로 집계됨
  - 파일: `rpl-benchmark/sender.c`

## 막혀 있는 부분

1. BRPL의 reachable 조건(DAO/route)을 정상화하지 못함
   - 현재는 “joined 기반 송신”으로 우회한 상태.
   - DAO/route가 왜 안정적으로 생성되지 않는지 추가 분석 필요.

2. BRPL OF가 실제 혼잡/큐 정보를 충분히 반영하지 못함
   - 현재는 로컬 node의 queuebuf 사용량만 반영.
   - 부모 노드 혼잡 여부를 직접 측정하지 않음.

3. 분석 결과가 중복된 실험에 의해 왜곡될 가능성
   - BRPL이 정상 동작을 한 데이터가 충분하지 않음.
   - 중복행 제거 기준을 명확히 정해야 함.

4. 큐 패널티 계수 미확정
   - BRPL_QUEUE_WEIGHT의 적정 값(예: ETX_DIVISOR/16 ~ /2)이 아직 실험적으로 확정되지 않음.
   - 현재는 parent 유지 불안정/DAO 문제를 우선 해결 중이라 패널티 튜닝을 못함.
   - 안정화 후 단계적 스윕으로 PDR/지연/오버헤드 트레이드오프를 확인해야 함.

## 다음 단계 후보

1. BRPL에서 DAO/route 유지 실패 원인 로그 강화
2. sender 송신 조건을 원복하고 reachable 정상화 확인
3. BRPL OF의 parent 유지 로직 재설계(ETX/penalty 균형)
4. `summary.csv` 중복 조건 정리 후 재분석
