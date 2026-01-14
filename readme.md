[A] 시뮬레이션 목표 요약
- RPL 기반 네트워크에서 receiver(root)가 UDP 수신을 담당하고 CSV 로그를 남긴다.
- 노드 수 증가 및 링크 품질 저하로 RPL 한계 조건을 유도한다.
- BRPL 모드와 RPL 모드를 동일 조건에서 비교 가능한 데이터셋으로 정리한다.

[B] 네트워크 구성 초안
- 노드 종류와 역할: Root+Receiver 1, Sensor Sender N.
- 토폴로지: UDGM, 고정 좌표 그리드(재현성), Tx/Interference/Success ratio 파라미터화.
- 프로토콜 스택: IPv6 + UDP + RPL/BRPL (BRPL 모드는 OF 교체).

[C] 코드 구조 (파일 단위)
- receiver_root.c: RPL root 설정 + UDP 수신 + CSV 로그 출력.
- sender.c: 10초 주기 UDP 송신(컴파일 매크로 SEND_INTERVAL_SECONDS로 변경 가능).
- brpl-of.c: BRPL 모드에서 사용되는 objective function(큐 점유율 기반 penalty).
- project-conf.h: BRPL 모드 매크로와 로그 레벨 설정.

[D] Cooja/CLI 실행 구성
- make 명령어: make -C rpl-benchmark TARGET=cooja receiver_root.cooja sender.cooja MAKE_ROUTING=...
- .csc 구성 개요: tools/gen_csc.py가 노드 수/전파 파라미터를 반영해 brpl_stress.csc 생성.
- nogui 실행: run_experiment.sh 또는 run_sweep.sh가 java -jar cooja.jar -nogui=... 호출.

[E] 실험 자동화 설계
- run_experiment.sh: MODE(rpl-lite/rpl-classic/brpl)와 SENDERS 인자를 받아 1회 실행.
- run_sweep.sh: 노드 수를 늘리며 반복 실행, summary.csv 자동 누적.
- tools/python/log_parser.py: CSV 로그를 읽어 summary.csv로 집계.

[F] 수집 지표 & 로그 포맷
- CSV 로그 포맷: CSV,RX,src_ip,src_port,seq,t_send,t_recv,delay_ticks,len,gap
- PDR: gap 기반 결손 + 수신 수로 계산.
- end-to-end delay: delay_ticks → 실시간 변환.
- RPL 제어 트래픽: LOG_CONF_LEVEL_RPL 조정 후 DIO/DAO 카운트 가능.
