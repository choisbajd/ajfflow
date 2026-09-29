# ajdfin-snowflake

Snowflake 쿼리 작성 및 데이터 분석용 저장소 (애플리케이션 코드 없음).

- 원천: `AJDCAR_PROD.PUBLIC` (자동차보험 상담/비교견적 도메인)
- ERD: [docs/erd/ERD.md](docs/erd/ERD.md), 원본 DDL [docs/erd/source_mysql.sql](docs/erd/source_mysql.sql)
- 리포트 쿼리
  - [queries/reports_v3.sql](queries/reports_v3.sql): 현행 수정본 (회원 리스트 / 계약 리스트 + 자동 조건 판정 / 가입취소 리스트)
  - [queries/reference_download.sql](queries/reference_download.sql): 판정 기준 원문 (다운로드 쿼리)
  - [queries/current_reports.sql](queries/current_reports.sql): 기존 운영 쿼리 원문
  - [queries/checks.sql](queries/checks.sql): 전제 검증 쿼리 (C1~C12)
- 규칙/미결 사항: [docs/queries_analysis.md](docs/queries_analysis.md)

작업 규칙
- 새 쿼리는 docs/queries_analysis.md 의 확정 규칙(계약 정의, 체결일자, 제외 조건, 컬럼 매핑)을 따른다
- 코드값을 모르면 추측하지 말고 checks.sql 에 확인 쿼리를 추가한다
