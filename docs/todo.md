## 상태 요약
- brpl에서 부모노드를 유지하지 못해 라우팅 형성이 안됨
- brpl에서 부모/라우팅 유지가 불안정
- queue penalty를 어느정도로 완화를 해야할지?

## 해결 완료
- find_thresholds.py Condition 해시 오류 수정 완료
- 시계 비동기 대응(옵션 A) 적용 완료: 2s sync, 전용 UDP 포트, 이동평균

## 남은 작업
- summary.csv 중복 행 정리 기준 확정
- 최신 실험 결과로 CSV/지연 값 재검증
- 실험 결과 R로 분석
- 분석 후 나온 데이터 latex문서 작성
