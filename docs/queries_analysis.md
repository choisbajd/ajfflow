# 운영 리포트 쿼리 분석

대상: [queries/current_reports.sql](../queries/current_reports.sql) / 검증 쿼리: [queries/checks.sql](../queries/checks.sql)
Snowflake 위치: `AJDCAR_PROD.PUBLIC` (원천 테이블명 대문자)

## 1. 개념 정의 (공식)

| 개념 | 기준 |
|---|---|
| DB | 가망상담, counsel_id 단위 |
| 회원 | users 단위 |
| 계약 | **현재 상태**가 지급대기(ACCUMULATE_PENDING) 또는 가입완료(JOIN_COMPLETED)인 상담. 지급대기 도달 후 가입취소된 건은 계약이 아니라 가입취소 건 |
| 계약 건수 | COUNT(DISTINCT counsel_id) (요구사항 §14). 차량 단위 아님 |
| 체결일자(=매출인식일) | 지급대기 로그가 있으면 현재 상태와 무관하게 최초 도달 시각(pending_at), 없으면 join_completed_at (2단계로 확정, §17의 3단계 표현은 무시) |

상태 흐름: 비교견적 -> 지급대기 -> 가입완료. 갱신 건은 비교견적~지급대기 간격이 수주~수개월(사전예약). "현재상태가 지급대기일 때만 pending_at" 식으로 짜면 가입완료 전환 시 매출일이 다시 잡혀 이중집계 발생.

## 2. 컬럼 매핑 (확정)

| 출력 컬럼 | 소스 | 비고 |
|---|---|---|
| 가입일시 | users.created_at | join_at 아님 |
| 고객번호 | customer.customer_id | customer_number 아님 |
| 차량번호 | counsel_vehicle.license_plate_number | counsel_vehicle_number로 보완하지 않음 |
| 누적광고비 | AD_POINT_TRANSACTIONS type='WITHDRAW', status='COMPLETED' 합 | 적립 아님, **사용액** |
| 잔여광고비 | status='COMPLETED' 최신 거래(ORDER BY id DESC)의 remaining_amount | |
| 영업채널/유입채널 | channel_path: DEALER_APP 딜러앱 / RENEWAL 갱신 / CS / 그 외 기타 | 4분류 |
| 상담구분 | is_renewal (신규/갱신) | 갱신 여부의 진짜 기준. channel_path와 100% 일치하지 않음 |
| 딜러세부유형 | users.business_sub_type: IMPORTED 수입 / DOMESTIC 국산 | NEW_CAR_DEALER를 G1(수입)/G2(국산)로 구분 |
| 가입유형 | subscription_type 원본값 | |
| 가입보험사 | join_insurer_code CASE 한글 매핑 (11개사) | |

조인/제외 규칙: customer, counsel_vehicle은 INNER JOIN(is_deleted = FALSE). 명함 반려 회원 제외, 테스트 매니저('%테스트%') 제외. 실적 제외 플래그 `users.is_performance_exclude` 존재 (ERD에는 없는 컬럼).

## 3. 운영 쿼리 vs 공식 정의 차이

| 항목 | 운영 쿼리 | 공식 정의 | 영향 |
|---|---|---|---|
| 누적계약체결수 | 차량 단위 COUNT(*) | COUNT(DISTINCT counsel_id) | 차량 2대 상담이 운영 2건 / 공식 1건 |
| 가입취소 리스트 체결일자 | join_completed_at만 | pending_at 우선 | 취소 리스트만 체결일자 기준이 다름 |

## 4. 확정된 제외/대상 규칙 (2026-09-28)

| 규칙 | 조건 |
|---|---|
| 명함 반려 제외 | `(business_card_status IS NULL OR business_card_status <> 'REJECTED')`. 실제 값: APPROVED 1827 / NULL 119 / REJECTED 58 / PENDING 29 / RE_SUBMITTED 1 |
| 실적 제외 | `users.is_performance_exclude = FALSE` |
| 테스트 제외 | 유치회원 담당 매니저(users.manager_id -> manager.name) `NOT LIKE '%테스트%'`. 상담 매니저 기준 아님 |
| 탈퇴 회원 | 탈퇴 딜러의 계약도 포함 |
| 딜러 리스트 대상 | business_type = 'NEW_CAR_DEALER', business_sub_type으로 수입(IMPORTED)/국산(DOMESTIC) 구분 |

| 동일보험사(§22) | `cv.exist_insurer_code = ca.join_insurer_code` 차량은 실적 불인정. 딜러 리스트 보험료 합산 제외, 전 차량 동일보험사 상담은 계약건수 제외. 체결/취소 리스트는 행 유지 + 실적인정여부 N |
| 본인가족계약 | `counsel_application.is_self_family_contract` (ERD 미기재). 딜러 리스트 건수, 체결/취소 리스트 Y/N |
| 기간 필터 | 체결리스트 = 체결일자, 취소리스트 = 가입취소일. from 포함 ~ to 미포함 |
| 취소 리스트 체결일자 | ca.join_completed_at (참고 쿼리 기준) |

반영본: [queries/reports_v3.sql](../queries/reports_v3.sql) / 기준 원문: [queries/reference_download.sql](../queries/reference_download.sql)

체결/취소 리스트 제외 조건은 참고 쿼리 그대로: 탈퇴 딜러 계약 제외, 테스트 제외는 상담(체결) 매니저 기준 (사용자 확정, 앞선 답변 대체).

## 4-1. 계약 리스트 자동 조건 판정

| 조건 | 충족 | 미충족 | 확인 필요 |
|---|---|---|---|
| C1 활동회원 | 같은 유치회원의 다른 계약이 [체결일-60일, 체결일) 에 존재 | 없음 | 유치회원 없음 |
| C2 회원유형 | 신차딜러(국산/수입), 보험설계사 | 중고차 딜러, 에이전트 | 매핑 없는 유형 |
| C3 영업용 | 영업용 아님 | 영업용 | 차량용도 NULL/미매핑 |
| C4 보험사 | 새가입 <> 기존 (타사 갱신) | 같음 (동일 보험사 갱신) | 둘 중 NULL |

종합: 미충족 1개 이상 -> 조건 미충족(미충족 사유만), 아니면 확인 필요 1개 이상 -> 확인 필요(해당 사유만), 전부 충족 -> 조건 충족(전 조건). 사유는 ' / ' 구분.
활동회원 판정의 "다른 계약"은 계약 정의(현재 상태 지급대기/가입완료)만 적용, 제외 조건 미적용.
코드 매핑 미확정: 보험설계사/중고차/에이전트 business_type, vehicle_usage_code [C11]. 센터 최종 판단은 저장 위치 미정.

## 5. 운영 쿼리에서 확인된 버그

1. **반려 필터 미동작**: `<> '반려'`는 실제 값(REJECTED)과 달라 반려 회원 58명이 제외되지 않았음
2. **명함상태 NULL 회원 유치건 누락**: 체결/취소 리스트의 `u.business_card_status <> '반려'`는 NULL이면 거짓 처리되어 NULL 회원 119명의 유치 계약이 빠졌음
3. **탈퇴 딜러 계약 누락**: 체결/취소 리스트가 `u.is_deleted = FALSE`로 제외하고 있었음
4. **테스트 필터 기준 오류**: 체결/취소 리스트가 상담 매니저 기준으로 거르고 있었음

## 6. 남은 이슈

1. **상태 로그 없는 계약건** [C4]: v2는 LEFT JOIN으로 수정. C4 결과로 영향 규모 확인
2. **코드 매핑 CASE 중복** [C7, C8]: common_code 대체 가능 여부
3. **엑셀용 `'="' || phone || '"'`**: 엑셀 외 용도에서는 값 오염
4. **주민번호**: 보류

## 7. 미결 질문

- 없음 (C4 결과만 확인 대기)
