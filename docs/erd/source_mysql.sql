-- 원본 MySQL ERD DDL (사용자 제공, 2026-09-28)
-- 주의: 내용은 원문 그대로 보존(ALTER 문만 한 줄로 정리). 문법 오류 및 누락 사항은 docs/erd/ERD.md "원본 DDL 이슈" 참고

CREATE TABLE `counsel_application` (
	`counsel_id`	bigint	NOT NULL	COMMENT '상담 아이디',
	`customer_id`	bigint	NOT NULL	COMMENT '고객 아이디',
	`user_id`	bigint	NULL	COMMENT '회원 아이디',
	`channel_path`	varchar(10)	NULL	COMMENT '유입 경로',
	`counsel_status`	varchar(50)	NOT NULL	COMMENT '상담 상태',
	`product_type`	varchar(30)	NOT NULL	COMMENT '상품 종류',
	`subscription_type`	varchar(30)	NULL	COMMENT '가입 유형',
	`vehicle_type`	varchar(20)	NULL	COMMENT '차종 구분',
	`vehicle_usage_code`	varchar(20)	NULL	COMMENT '차량 용도',
	`ownership_type`	varchar(20)	NULL	COMMENT '소유 형태',
	`insurance_type`	varchar(20)	NULL	COMMENT '보험 종류',
	`join_insurer_code`	varchar(20)	NULL	COMMENT '가입 보험사',
	`insurance_end_dt`	date	NULL	COMMENT '새 보험 만기일',
	`join_completed_at`	datetime	NULL	COMMENT '보험 가입 완료 일시',
	`gift_id`	bigint	NULL	COMMENT '사은품 아이디',
	`gift_quantity`	int	NULL	COMMENT '사은품 수량',
	`counsel_manager_id`	bigint	NULL	COMMENT '상담 담당자 아이디',
	`is_renewal`	tinyint(1)	NOT NULL	DEFAULT 0	COMMENT '갱신 상담 여부',
	`renewal_origin_counsel_id`	bigint	NULL	COMMENT '갱신 원본 상담 아이디',
	`is_deleted`	tinyint(1)	NOT NULL	DEFAULT 0	COMMENT '삭제 여부',
	`updated_at`	datetime	NULL	COMMENT '수정일시',
	`created_at`	datetime	NOT NULL	DEFAULT CURRENT_TIMESTAMP	COMMENT '생성일시'
);

CREATE TABLE `common_code` (
	`code_id`	bigint	NULL	COMMENT '공통코드 아이디' primary ke',
	`group_code`	varchar(50)	NOT NULL	COMMENT '그룹 코드',
	`common_code`	varchar(50)	NULL	COMMENT '공통코드 값 (enum 등으로 참조되는 경우만 사용, 운영자 생성 건은 NULL)',
	`common_code_name`	varchar(100)	NOT NULL	COMMENT '공통코드 명',
	`parent_code_id`	bigint	NULL	COMMENT '상위 공통코드 아이디 (common_code.code_id, 최상위는 NULL)',
	`code_depth`	tinyint	NOT NULL	DEFAULT 1	COMMENT '계층 깊이',
	`sort_number`	int	NOT NULL	DEFAULT 1	COMMENT '같은 상위 내 정렬 순서 번호',
	`is_active`	tinyint(1)	NOT NULL	DEFAULT 1	COMMENT '활성 여부',
	`active_start_dt`	date	NULL	COMMENT '활성 시작일 (NULL: 제한 없음)',
	`active_end_dt`	date	NULL	COMMENT '활성 종료일 (해당일 포함, NULL: 무기한)',
	`code_description`	varchar(255)	NULL	COMMENT '코드 설명',
	`is_delete`	tinyint(1)	NOT NULL	DEFAULT 0	COMMENT '삭제 여부',
	`delete_at`	datetime	NULL	COMMENT '삭제일시',
	`updated_at`	datetime	NULL	COMMENT '수정일시',
	`created_at`	datetime	NOT NULL	DEFAULT CURRENT_TIMESTAMP	COMMENT '생성일시'
);

CREATE TABLE `ad_point_transactions` (
	`id`	bigint	NOT NULL	COMMENT '광고비 거래 내역 아이디',
	`counsel_id`	bigint	NULL	COMMENT '상담 아이디',
	`counsel_vehicle_id`	bigint	NOT NULL	COMMENT '상담 차량 아이디',
	`user_id`	bigint	NOT NULL	COMMENT '회원 아이디',
	`type`	varchar(255)	NOT NULL	COMMENT '거래 유형 (ACCUMULATE: 적립, WITHDRAW: 출금)',
	`status`	varchar(255)	NOT NULL	COMMENT '거래 상태 (PENDING: 대기, COMPLETED: 완료, REJECTED: 거절)',
	`amount`	bigint	NOT NULL	COMMENT '거래 금액',
	`customer_id`	bigint	NULL	COMMENT '고객 아이디',
	`customer_name`	varchar(255)	NULL	COMMENT '고객명 (적립 시)',
	`customer_phone_number`	varchar(32)	NULL	COMMENT '고객 전화번호 (적립 시)',
	`remaining_amount`	bigint	NOT NULL	DEFAULT 0	COMMENT '잔여 광고 금액',
	`source`	varchar(16)	NOT NULL	DEFAULT 'SYSTEM'	COMMENT '적립 출처 (SYSTEM: 시스템 자동 적립, EVENT: 이벤트 적립)',
	`updated_at`	datetime	NULL	DEFAULT ON	COMMENT '수정 일시',
	`created_at`	datetime	NOT NULL	DEFAULT CURRENT_TIMESTAMP	COMMENT '생성 일시'
);

CREATE TABLE `permission` (
	`id`	bigint	NULL	COMMENT '권한 아이디',
	`permission_name`	varchar(100)	NOT NULL	COMMENT '권한명',
	`updated_at`	datetime	NULL	COMMENT '수정일시',
	`created_at`	datetime	NOT NULL	DEFAULT CURRENT_TIMESTAMP	COMMENT '생성일시'
);

CREATE TABLE `counsel_status_log` (
	`log_id`	bigint	NOT NULL	COMMENT '로그 아이디',
	`counsel_id`	bigint	NOT NULL	COMMENT '상담 아이디',
	`customer_id`	bigint	NOT NULL	COMMENT '고객 아이디',
	`manager_id`	bigint	NOT NULL	COMMENT '변경한 매니저 아이디',
	`previous_counsel_status`	varchar(50)	NULL	COMMENT '이전 상담 상태값',
	`new_counsel_status`	varchar(50)	NOT NULL	COMMENT '변경된 상담 상태값',
	`log_type`	varchar(20)	NOT NULL	DEFAULT STATUS_CHANGE	COMMENT '로그 타입',
	`description`	varchar(300)	NULL	COMMENT '활동 표시 텍스트',
	`created_at`	datetime	NOT NULL	DEFAULT CURRENT_TIMESTAMP	COMMENT '생성일시'
);

CREATE TABLE `comparison_estimate` (
	`estimate_id`	bigint	NOT NULL	COMMENT '견적서 아이디',
	`request_vehicle_id`	bigint	NOT NULL	COMMENT '요청 차량 아이디',
	`counsel_id`	bigint	NOT NULL	COMMENT '상담 아이디',
	`parent_estimate_id`	bigint	NULL	COMMENT '원본 견적서 아이디 (NULL: 원본, 값: 수정본)',
	`manager_id`	bigint	NOT NULL	COMMENT '생성 매니저 아이디',
	`vehicle_name`	varchar(100)	NOT NULL	COMMENT '차량명',
	`owner_name`	varchar(20)	NOT NULL	COMMENT '차주명',
	`driver_range`	varchar(100)	NOT NULL	COMMENT '운전 범위',
	`coverage_info`	varchar(255)	NOT NULL	COMMENT '가입담보',
	`insurer_amounts`	text	NOT NULL	COMMENT '보험사별 보험료',
	`created_at`	datetime	NOT NULL	DEFAULT CURRENT_TIMESTAMP	COMMENT '생성일시'
);

CREATE TABLE `manager` (
	`id`	bigint	NOT NULL	COMMENT '매니저 아이디',
	`email`	varchar(200)	NOT NULL	COMMENT '이메일',
	`name`	varchar(255)	NOT NULL	COMMENT '매니저 이름',
	`phone`	varchar(255)	NULL	COMMENT '전화번호',
	`employee_number`	varchar(20)	NOT NULL	COMMENT '사번',
	`employment_status`	varchar(15)	NOT NULL	DEFAULT EMPLOYED	COMMENT '재직 상태(EMPLOYED, ON_LEAVE, RESIGNED)',
	`manager_role`	varchar(20)	NULL	COMMENT '역할 (INSURANCE 등)',
	`is_active`	tinyint(1)	NOT NULL	DEFAULT 1	COMMENT '활성화 여부 (1: 활성, 0: 비활성)',
	`updated_at`	datetime	NULL	COMMENT '수정일시',
	`created_at`	datetime	NOT NULL	DEFAULT CURRENT_TIMESTAMP	COMMENT '생성일시'
);

CREATE TABLE `comparison_request_vehicle` (
	`request_vehicle_id`	bigint	NOT NULL	COMMENT '요청 차량 아이디',
	`request_id`	bigint	NOT NULL	COMMENT '비교 견적 요청 아이디',
	`counsel_vehicle_id`	bigint	NOT NULL	COMMENT '원본 상담 차량 아이디',
	`counsel_vehicle_number`	varchar(30)	NULL	COMMENT '상담 차량 번호',
	`owner_name`	varchar(20)	NOT NULL	COMMENT '차주명',
	`owner_gender_code`	char(1)	NULL	COMMENT '차주 성별',
	`owner_type`	varchar(20)	NOT NULL	COMMENT '차주 타입 (INDIVIDUAL: 개인, CORPORATE: 법인)',
	`license_plate_number`	varchar(10)	NULL	COMMENT '차량 번호',
	`vin`	varchar(30)	NULL	COMMENT '차대 번호',
	`vehicle_additional_info`	varchar(300)	NULL	COMMENT '추가 차량 정보',
	`created_at`	datetime	NOT NULL	DEFAULT CURRENT_TIMESTAMP	COMMENT '생성일시'
);

CREATE TABLE `comparison_request` (
	`request_id`	bigint	NOT NULL	COMMENT '비교 견적 요청 아이디',
	`counsel_id`	bigint	NOT NULL	COMMENT '상담 아이디',
	`manager_id`	bigint	NOT NULL	COMMENT '요청 매니저 아이디',
	`message_content`	varchar(300)	NULL	COMMENT '요청 메시지',
	`request_status`	varchar(20)	NOT NULL	COMMENT '요청 처리 상태 (WAITING: 대기중, PROCESSING: 처리중, COMPLETED: 완료, CANCEL:취소)',
	`updated_at`	datetime	NULL	DEFAULT ON	COMMENT '수정일시',
	`created_at`	datetime	NOT NULL	DEFAULT CURRENT_TIMESTAMP	COMMENT '생성일시'
);

CREATE TABLE `counsel_vehicle` (
	`counsel_vehicle_id`	bigint	NOT NULL	COMMENT '상담 차량 아이디',
	`counsel_id`	bigint	NOT NULL	COMMENT '상담 아이디',
	`counsel_vehicle_number`	varchar(30)	NULL	COMMENT '상담 차량 번호',
	`license_plate_number`	varchar(20)	NULL	COMMENT '차량 번호',
	`vin`	varchar(30)	NULL	COMMENT '차대 번호',
	`registration_type`	varchar(10)	NULL	COMMENT '차량 등록 유형 (NEW_CAR: 신차, USED_CAR: 중고차, RENEWAL: 갱신)',
	`vehicle_additional_info`	varchar(300)	NULL	COMMENT '추가 차량 정보',
	`contract_amount`	bigint	NULL	COMMENT '가입 금액',
	`review_id`	bigint	NULL	COMMENT '최종 후심사 이력 아이디',
	`exist_insurer_code`	varchar(20)	NULL	COMMENT '기존 보험사',
	`exist_insurance_end_dt`	date	NULL	COMMENT '기존 보험 만기일',
	`is_deleted`	tinyint(1)	NOT NULL	DEFAULT 0	COMMENT '삭제 여부',
	`updated_at`	datetime	NULL	COMMENT '수정일시',
	`created_at`	datetime	NOT NULL	DEFAULT CURRENT_TIMESTAMP	COMMENT '생성일시'
);

CREATE TABLE `customer` (
	`customer_id`	bigint	NOT NULL	COMMENT '고객 아이디',
	`customer_number`	varchar(30)	NOT NULL	COMMENT '고객 번호',
	`customer_type`	varchar(20)	NULL	COMMENT '고객 유형',
	`customer_name`	varchar(30)	NULL	COMMENT '고객 이름',
	`customer_phone_number`	varchar(100)	NULL	COMMENT '고객 연락처',
	`customer_phone_type`	varchar(20)	NULL	COMMENT '고객 연락처 타입',
	`customer_sub_phone_number`	varchar(100)	NULL	COMMENT '예비 고객 연락처',
	`customer_sub_phone_type`	varchar(20)	NULL	COMMENT '예비 고객 연락처 타입',
	`customer_gender_code`	char(1)	NULL	COMMENT '고객 성별',
	`customer_manager_id`	bigint	NULL	COMMENT '고객 담당자',
	`is_marketing_agreed`	tinyint(1)	NULL	COMMENT '마케팅 수신 동의 여부',
	`marketing_agreed_at`	datetime	NULL	COMMENT '마케팅 수신 동의 일시',
	`is_deleted`	tinyint(1)	NOT NULL	COMMENT '삭제 여부',
	`updated_at`	datetime	NULL	DEFAULT ON	COMMENT '수정일시',
	`created_at`	datetime	NOT NULL	DEFAULT CURRENT_TIMESTAMP	COMMENT '생성일시'
);

CREATE TABLE `users` (
	`id`	bigint	NOT NULL	COMMENT '회원 아이디',
	`user_id`	varchar(50)	NOT NULL	COMMENT '회원 로그인 아이디',
	`user_name`	varchar(20)	NOT NULL	COMMENT '사용자 이름',
	`role`	varchar(255)	NOT NULL	COMMENT '역할',
	`phone`	varchar(255)	NOT NULL	COMMENT '전화번호',
	`email`	varchar(255)	NULL	COMMENT '이메일',
	`business_type`	varchar(30)	NOT NULL	COMMENT '회원 유형 (GA, DEALER 등)',
	`business_sub_type`	varchar(20)	NULL	COMMENT '회원 세부 유형 (DOMESTIC: 국산차, IMPORTED: 수입차)',
	`referral_code`	varchar(100)	NULL	COMMENT '추천인 코드',
	`ad_point`	bigint	NOT NULL	COMMENT '광고비 포인트',
	`business_card_id`	bigint	NULL	COMMENT '명함 아이디',
	`business_card_status`	varchar(15)	NOT NULL	COMMENT '명함 인증 상태',
	`primary_affiliation`	varchar(50)	NULL	COMMENT '1차 소속 정보',
	`secondary_affiliation`	varchar(50)	NULL	COMMENT '2차 소속 정보',
	`sido_code`	varchar(15)	NULL	COMMENT '지역 정보 1depth (시, 도)',
	`sigungu_code`	varchar(15)	NULL	COMMENT '지역 정보 2depth (시, 구)',
	`manager_id`	bigint	NULL	COMMENT '매니저 아이디',
	`is_associate`	tinyint(1)	NOT NULL	DEFAULT 0	COMMENT '준회원 여부',
	`join_at`	datetime	NOT NULL	COMMENT '가입 일시',
	`is_deleted`	tinyint(1)	NOT NULL	COMMENT '탈퇴 여부',
	`deleted_at`	datetime	NULL	COMMENT '탈퇴 일시',
	`sales_channel_id`	bigint	NULL	COMMENT '영업 채널 코드 아이디',
	`update_at`	datetime(6)	NOT NULL	COMMENT '수정 일시',
	`created_at`	datetime(6)	NOT NULL	COMMENT '생성 일시'
);

CREATE TABLE `gift` (
	`gift_id`	BIGINT	NULL	COMMENT '사은품 아이디',
	`gift_name`	VARCHAR(100)	NOT NULL	COMMENT '사은품 이름',
	`is_active`	BOOLEAN	NOT NULL	COMMENT '활성화 여부',
	`updated_at`	DATETIME	NOT NULL	DEFAULT ON	COMMENT '수정일시',
	`created_at`	DATETIME	NOT NULL	DEFAULT CURRENT_TIMESTAMP	COMMENT '생성일시'
);

CREATE TABLE `manager_permission` (
	`id`	bigint	NULL	COMMENT '매핑 아이디',
	`manager_id`	bigint	NOT NULL	COMMENT '매니저 아이디',
	`permission_id`	bigint	NOT NULL	COMMENT '권한 ID',
	`created_at`	datetime	NOT NULL	DEFAULT CURRENT_TIMESTAMP	COMMENT '생성일시'
);

ALTER TABLE `counsel_application` ADD CONSTRAINT `PK_COUNSEL_APPLICATION` PRIMARY KEY (`counsel_id`);
ALTER TABLE `ad_point_transactions` ADD CONSTRAINT `PK_AD_POINT_TRANSACTIONS` PRIMARY KEY (`id`);
ALTER TABLE `counsel_status_log` ADD CONSTRAINT `PK_COUNSEL_STATUS_LOG` PRIMARY KEY (`log_id`);
ALTER TABLE `comparison_estimate` ADD CONSTRAINT `PK_COMPARISON_ESTIMATE` PRIMARY KEY (`estimate_id`);
ALTER TABLE `manager` ADD CONSTRAINT `PK_MANAGER` PRIMARY KEY (`id`);
ALTER TABLE `comparison_request_vehicle` ADD CONSTRAINT `PK_COMPARISON_REQUEST_VEHICLE` PRIMARY KEY (`request_vehicle_id`);
ALTER TABLE `comparison_request` ADD CONSTRAINT `PK_COMPARISON_REQUEST` PRIMARY KEY (`request_id`);
ALTER TABLE `counsel_vehicle` ADD CONSTRAINT `PK_COUNSEL_VEHICLE` PRIMARY KEY (`counsel_vehicle_id`);
ALTER TABLE `customer` ADD CONSTRAINT `PK_CUSTOMER` PRIMARY KEY (`customer_id`);
ALTER TABLE `users` ADD CONSTRAINT `PK_USERS` PRIMARY KEY (`id`);
