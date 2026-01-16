### 상태
일단은 초안은 완성

### 해결 완료


### 남은 작업

# brpl 붕괴 확인
스윕 조건 강화
조건 x seed로 시간이 폭발할것같은데 병목문제 해결

# CoAP 실험 추가(먼저 brpl 붕괴를 확인하고 이후 작업)
Cooja에서:

다수 센서 노드 → CoAP 서버에 주기적 요청

RPL vs BRPL 환경에서:

RTT

PDR

오버헤드 비교

“CoAP 트래픽에서 BRPL이 붕괴를 늦추는가?”


# MQTT 구성
Contiki-NG의 MQTT 예제(브로커 + 클라이언트)로:

다수 노드 → 브로커로 publish

TCP 기반 오버헤드/지연/패킷 손실 비교

UDP(CoAP) vs TCP(MQTT)
RPL vs BRPL
            
