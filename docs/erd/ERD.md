# ERD 요약 (자동차보험 상담/비교견적 도메인)

원본 DDL: [source_mysql.sql](source_mysql.sql) (MySQL, 14개 테이블)

## 도메인 그룹

| 그룹 | 테이블 | 역할 |
|---|---|---|
| 상담(핵심 팩트) | counsel_application | 상담 신청 1건 = 1행. 상태/상품/보험사/가입완료 등 |
| 상담 하위 | counsel_vehicle, counsel_status_log | 상담별 차량(1:N), 상태 변경 이력(1:N) |
| 비교견적 | comparison_request, comparison_request_vehicle, comparison_estimate | 요청 -> 요청차량 -> 견적서(수정본 체인) |
| 광고비 | ad_point_transactions | 회원(users) 광고비 적립/출금 원장 |
| 주체 | customer, users, manager | 고객 / 제휴회원(GA, DEALER) / 내부 매니저 |
| 권한 | permission, manager_permission | 매니저-권한 N:M |
| 참조 | common_code, gift | 계층형 공통코드, 사은품 |

## 관계 (FK 제약 없음, 컬럼명 기준 추론)

```
customer 1 ── N counsel_application N ── 1 users (user_id -> users.id, NULL 가능)
                     │  ├─ counsel_manager_id -> manager.id
                     │  ├─ gift_id -> gift.gift_id
                     │  └─ renewal_origin_counsel_id -> counsel_application.counsel_id (자기참조, 갱신)
                     ├── N counsel_vehicle
                     ├── N counsel_status_log (manager_id -> manager.id, customer_id 중복 보관)
                     └── N comparison_request (manager_id -> manager.id)
                              └── N comparison_request_vehicle (counsel_vehicle_id -> counsel_vehicle)
                                       └── N comparison_estimate (counsel_id 중복 보관,
                                                parent_estimate_id 자기참조: NULL=원본)
ad_point_transactions -> users.id, counsel_application, counsel_vehicle(NOT NULL), customer
customer.customer_manager_id -> manager.id
users.manager_id -> manager.id
users.sales_channel_id -> common_code.code_id (추정)
manager N ── M permission (manager_permission)
common_code.parent_code_id -> common_code.code_id (계층)
```

주의: `users.id`(bigint PK)와 `users.user_id`(로그인 문자열)는 다르다. 다른 테이블의 `user_id`는 `users.id`를 가리킨다.

## 코드성 컬럼 (common_code.group_code 매핑 대상 추정)

- counsel_application: channel_path, counsel_status, product_type, subscription_type, vehicle_type, vehicle_usage_code, ownership_type, insurance_type, join_insurer_code
- counsel_vehicle: registration_type(NEW_CAR/USED_CAR/RENEWAL), exist_insurer_code
- enum 명시: ad_point_transactions.type(ACCUMULATE/WITHDRAW), status(PENDING/COMPLETED/REJECTED), source(SYSTEM/EVENT); comparison_request.request_status(WAITING/PROCESSING/COMPLETED/CANCEL); manager.employment_status(EMPLOYED/ON_LEAVE/RESIGNED); comparison_request_vehicle.owner_type(INDIVIDUAL/CORPORATE)

## 원본 DDL 이슈

1. `common_code.code_id` COMMENT 문법 깨짐 (`'공통코드 아이디' primary ke'`), NULL 허용
2. PK 제약 누락: common_code, permission, gift, manager_permission (id 컬럼도 NULL 허용)
3. `DEFAULT ON` 불완전 (의도: `ON UPDATE CURRENT_TIMESTAMP`) - ad_point_transactions, comparison_request, customer, gift
4. 문자열 기본값 따옴표 누락: `DEFAULT STATUS_CHANGE`, `DEFAULT EMPLOYED`
5. 네이밍 불일치: users.`update_at`(나머지는 updated_at), common_code.`is_delete`/`delete_at`(나머지는 is_deleted/deleted_at)
6. 참조 대상 테이블 미제공: counsel_vehicle.review_id(후심사 이력), users.business_card_id(명함)
7. ERD 미기재 컬럼(운영 DB에는 존재): users.is_performance_exclude (실적 제외 여부), counsel_application.is_self_family_contract (본인/가족 계약 여부)
8. 소프트 삭제 컬럼 존재 테이블: counsel_application, counsel_vehicle, customer, users, common_code

## Snowflake 전환 시 고려사항

- 타입: tinyint(1)/BOOLEAN -> BOOLEAN, datetime -> TIMESTAMP_NTZ, text -> VARCHAR (insurer_amounts가 JSON이면 VARIANT)
- PK/FK는 Snowflake에서 강제되지 않음(메타데이터용) -> 무결성은 적재/테스트 단계에서 검증
- 증분 적재 키: updated_at(없으면 created_at). counsel_status_log, comparison_estimate, comparison_request_vehicle, manager_permission은 insert-only
- 개인정보 컬럼(마스킹 정책 대상): customer_name, customer_phone_number, customer_sub_phone_number, owner_name, license_plate_number, vin, users.phone/email, manager.phone/email
