## 상태 요약
- CSV 생성 확인 후 R로 분석 예정
- summary.csv 앞부분 빈 행: 초기 CSV 추출 실패 흔적
- brpl pdr이 처음부터 0으로 표시됨 제대로 구현이 안되어있거나 실행이 안되었을 가능성 높음

## 해결 완료
- find_thresholds.py Condition 해시 오류 수정 완료
- 시계 비동기 대응(옵션 A) 적용 완료: 2s sync, 전용 UDP 포트, 이동평균

## 남은 작업
- summary.csv 중복 행 정리 기준 확정
- 최신 실험 결과로 CSV/지연 값 재검증
- 실험 결과 R로 분석
- 분석 후 나온 데이터 latex문서 작성
