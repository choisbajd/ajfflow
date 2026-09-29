-- 리포트 쿼리 전제 검증용 (docs/queries_analysis.md 의 항목 번호와 대응)
-- 각 블록을 개별 실행

-- [C1] business_card_status 실제 값 확인 ('반려' 한글값인지, REJECTED 같은 영문값인지)
SELECT business_card_status, COUNT(*) AS cnt
FROM AJDCAR_PROD.PUBLIC.USERS
GROUP BY 1 ORDER BY 2 DESC;

-- [C2] 상담 상태 전체 분포 (ACCUMULATE_PENDING / JOIN_COMPLETED 이후 상태가 있는지)
SELECT counsel_status, COUNT(*) AS cnt
FROM AJDCAR_PROD.PUBLIC.COUNSEL_APPLICATION
WHERE is_deleted = FALSE
GROUP BY 1 ORDER BY 2 DESC;

-- [C3] 상태 전이 경로 (JOIN_COMPLETED -> ACCUMULATE_PENDING 순서인지 확인)
SELECT previous_counsel_status, new_counsel_status, COUNT(*) AS cnt
FROM AJDCAR_PROD.PUBLIC.COUNSEL_STATUS_LOG
GROUP BY 1, 2 ORDER BY 3 DESC;

-- [C4] 체결 상태인데 상태 로그가 한 건도 없는 상담 (INNER JOIN status_agg 로 누락되는 건)
SELECT ca.counsel_status, COUNT(*) AS missing_cnt
FROM AJDCAR_PROD.PUBLIC.COUNSEL_APPLICATION ca
WHERE ca.is_deleted = FALSE
  AND ca.counsel_status IN ('ACCUMULATE_PENDING', 'JOIN_COMPLETED')
  AND NOT EXISTS (
    SELECT 1 FROM AJDCAR_PROD.PUBLIC.COUNSEL_STATUS_LOG csl
    WHERE csl.counsel_id = ca.counsel_id
  )
GROUP BY 1;

-- [C5] 상담 1건에 차량이 여러 대인 경우 (누적계약체결수가 차량 수로 집계되는 영향)
SELECT vehicle_cnt, COUNT(*) AS counsel_cnt
FROM (
  SELECT ca.counsel_id, COUNT(*) AS vehicle_cnt
  FROM AJDCAR_PROD.PUBLIC.COUNSEL_APPLICATION ca
  JOIN AJDCAR_PROD.PUBLIC.COUNSEL_VEHICLE cv
    ON cv.counsel_id = ca.counsel_id AND cv.is_deleted = FALSE
  WHERE ca.is_deleted = FALSE
    AND ca.counsel_status IN ('ACCUMULATE_PENDING', 'JOIN_COMPLETED')
  GROUP BY ca.counsel_id
)
GROUP BY 1 ORDER BY 1;

-- [C6] 잔여광고비: 최신 COMPLETED 거래의 remaining_amount vs users.ad_point 불일치
WITH latest AS (
  SELECT user_id, remaining_amount
  FROM AJDCAR_PROD.PUBLIC.AD_POINT_TRANSACTIONS
  WHERE status = 'COMPLETED'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY id DESC) = 1
)
SELECT u.id, u.user_name, u.ad_point, l.remaining_amount, u.ad_point - l.remaining_amount AS diff
FROM AJDCAR_PROD.PUBLIC.USERS u
JOIN latest l ON l.user_id = u.id
WHERE u.ad_point <> l.remaining_amount
ORDER BY ABS(diff) DESC;

-- [C7] 채널/보험사 코드 중 CASE 매핑에 없는 값 ('기타' 또는 코드 그대로 노출되는 건)
SELECT 'channel_path' AS col, channel_path AS val, COUNT(*) AS cnt
FROM AJDCAR_PROD.PUBLIC.COUNSEL_APPLICATION
WHERE COALESCE(channel_path, '') NOT IN ('DEALER_APP', 'RENEWAL', 'CS')
GROUP BY 1, 2
UNION ALL
SELECT 'join_insurer_code', join_insurer_code, COUNT(*)
FROM AJDCAR_PROD.PUBLIC.COUNSEL_APPLICATION
WHERE join_insurer_code IS NOT NULL
  AND join_insurer_code NOT IN ('AXA','CARROT','DB','HANA','HANHWA','HEUNGKUK','HYUNDAI','KB','LOTTE','MERITZ','SAMSUNG')
GROUP BY 1, 2;

-- [C8] common_code 에 보험사/채널 코드명이 이미 있는지 (CASE 하드코딩 대체 가능 여부)
SELECT group_code, common_code, common_code_name
FROM AJDCAR_PROD.PUBLIC.COMMON_CODE
WHERE is_delete = FALSE
  AND common_code IN ('AXA','SAMSUNG','DEALER_APP','CS','ACCUMULATE_PENDING')
ORDER BY 1, 2;

-- [C9] 딜러 리스트 대상 회원 유형 분포 (DEALER 외 GA 등이 섞이는지)
SELECT business_type, business_sub_type, role, COUNT(*) AS cnt
FROM AJDCAR_PROD.PUBLIC.USERS
GROUP BY 1, 2, 3 ORDER BY 4 DESC;

-- [C11] 자동 조건 판정용 코드값: 회원유형 / 차량용도 / 가입유형·보험종류(공동인수 위치 확인)
SELECT 'business_type' AS col, business_type || ' / ' || COALESCE(business_sub_type, '-') AS val, COUNT(*) AS cnt
FROM AJDCAR_PROD.PUBLIC.USERS GROUP BY 1, 2
UNION ALL
SELECT 'vehicle_usage_code', vehicle_usage_code, COUNT(*)
FROM AJDCAR_PROD.PUBLIC.COUNSEL_APPLICATION GROUP BY 1, 2
UNION ALL
SELECT 'subscription_type', subscription_type, COUNT(*)
FROM AJDCAR_PROD.PUBLIC.COUNSEL_APPLICATION GROUP BY 1, 2
UNION ALL
SELECT 'insurance_type', insurance_type, COUNT(*)
FROM AJDCAR_PROD.PUBLIC.COUNSEL_APPLICATION GROUP BY 1, 2
ORDER BY 1, 3 DESC;

-- [C12] 계약건 중 기존보험사 NULL 분포 (신차 등록이라 원래 없는 건인지)
SELECT cv.registration_type, COUNT(*) AS total, COUNT_IF(cv.exist_insurer_code IS NULL) AS exist_null
FROM AJDCAR_PROD.PUBLIC.COUNSEL_APPLICATION ca
JOIN AJDCAR_PROD.PUBLIC.COUNSEL_VEHICLE cv ON cv.counsel_id = ca.counsel_id AND COALESCE(cv.is_deleted, FALSE) = FALSE
WHERE COALESCE(ca.is_deleted, FALSE) = FALSE
  AND ca.counsel_status IN ('ACCUMULATE_PENDING', 'JOIN_COMPLETED')
GROUP BY 1 ORDER BY 2 DESC;

-- [C10] 테스트 계정 식별 (매니저명 외에 회원명/로그인ID 에 테스트가 들어간 건)
SELECT id, user_id, user_name, business_type, is_deleted
FROM AJDCAR_PROD.PUBLIC.USERS
WHERE user_name ILIKE '%테스트%' OR user_id ILIKE '%test%';
