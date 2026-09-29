-- 현재 운영 중인 리포트 쿼리 (사용자 제공 원문, 2026-09-28)
-- 분석 내용: docs/queries_analysis.md

-- =====================================================================
-- 1. 등록된 딜러 리스트 (준회원+정회원 모두, 탈퇴회원도 포함해서 표시)
-- =====================================================================
WITH status_agg AS (
  SELECT
    csl.counsel_id,
    MIN(CASE WHEN csl.new_counsel_status = 'ACCUMULATE_PENDING'
             THEN csl.created_at END) AS pending_at
  FROM AJDCAR_PROD.PUBLIC.COUNSEL_STATUS_LOG csl
  GROUP BY csl.counsel_id
),

deal_agg AS (
  SELECT
    ca.user_id                                                    AS dealer_id,
    COUNT(*)                                                      AS deal_count,
    SUM(cv.contract_amount)                                       AS total_premium,
    MIN(COALESCE(sa.pending_at, ca.join_completed_at))            AS first_deal_at,
    MAX(COALESCE(sa.pending_at, ca.join_completed_at))            AS last_deal_at
  FROM AJDCAR_PROD.PUBLIC.COUNSEL_APPLICATION ca
  JOIN status_agg sa                        ON sa.counsel_id = ca.counsel_id
  JOIN AJDCAR_PROD.PUBLIC.COUNSEL_VEHICLE cv ON cv.counsel_id = ca.counsel_id AND cv.is_deleted = FALSE
  WHERE ca.is_deleted = FALSE
    AND ca.counsel_status IN ('ACCUMULATE_PENDING', 'JOIN_COMPLETED')
  GROUP BY ca.user_id
),

latest_ad_point AS (
  SELECT user_id, remaining_amount
  FROM (
    SELECT
      user_id,
      remaining_amount,
      ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY id DESC) AS rn
    FROM AJDCAR_PROD.PUBLIC.AD_POINT_TRANSACTIONS
    WHERE status = 'COMPLETED'
  )
  WHERE rn = 1
),

ad_usage AS (
  SELECT
    user_id,
    SUM(CASE WHEN type = 'WITHDRAW' THEN amount ELSE 0 END) AS total_used
  FROM AJDCAR_PROD.PUBLIC.AD_POINT_TRANSACTIONS
  WHERE status = 'COMPLETED'
  GROUP BY user_id
)

SELECT
  u.created_at                                                    AS "가입일시",
  da.first_deal_at                                                AS "최초계약일",
  da.last_deal_at                                                 AS "최종계약일",
  u.user_name                                                     AS "딜러이름",
  u.user_id                                                       AS "로그인ID",
  u.phone                                                         AS "연락처",
  m.name                                                          AS "담당매니저",
  u.business_type                                                 AS "소속구분",
  u.primary_affiliation                                           AS "1차소속",
  u.secondary_affiliation                                         AS "2차소속",
  CASE WHEN u.is_associate = TRUE THEN '준회원' ELSE '정회원' END     AS "회원구분",
  CASE WHEN u.is_deleted = TRUE THEN 'Y' ELSE 'N' END              AS "탈퇴여부",
  COALESCE(lap.remaining_amount, 0)                                AS "잔여광고비",
  COALESCE(da.deal_count, 0)                                      AS "누적계약체결수",
  COALESCE(da.total_premium, 0)                                   AS "누적총원수보험료",
  COALESCE(au.total_used, 0)                                      AS "누적광고비"
FROM AJDCAR_PROD.PUBLIC.USERS u
LEFT JOIN AJDCAR_PROD.PUBLIC.MANAGER m ON m.id = u.manager_id
LEFT JOIN deal_agg da                  ON da.dealer_id = u.id
LEFT JOIN latest_ad_point lap          ON lap.user_id = u.id
LEFT JOIN ad_usage au                  ON au.user_id = u.id
WHERE (u.business_card_status IS NULL OR u.business_card_status <> '반려')
  AND (m.name IS NULL OR m.name NOT LIKE '%테스트%')
ORDER BY "가입일시" DESC;


-- =====================================================================
-- 2. 체결리스트
-- =====================================================================
WITH status_agg AS (
  SELECT
    csl.counsel_id,
    MIN(CASE WHEN csl.new_counsel_status = 'ACCUMULATE_PENDING' THEN csl.created_at END) AS pending_at
  FROM AJDCAR_PROD.PUBLIC.COUNSEL_STATUS_LOG csl
  GROUP BY csl.counsel_id
)

SELECT
  CASE ca.channel_path
    WHEN 'DEALER_APP' THEN '딜러앱'
    WHEN 'RENEWAL'    THEN '갱신'
    WHEN 'CS'         THEN 'CS'
    ELSE '기타'
  END                                                              AS "영업채널",
  cu.customer_name                                                AS "고객명",
  cu.customer_id                                                  AS "고객번호",
  ca.counsel_id                                                   AS "상담번호",
  '="' || cu.customer_phone_number || '"'                         AS "연락처",
  cv.license_plate_number                                         AS "차량번호",
  cv.vin                                                          AS "차대번호",
  TO_CHAR(ca.insurance_end_dt, 'YYYY-MM-DD')                      AS "새보험만기일",
  cv.contract_amount                                              AS "보험료",
  TO_CHAR(COALESCE(sa.pending_at, ca.join_completed_at), 'YYYY-MM-DD') AS "체결일자",
  CASE ca.join_insurer_code
    WHEN 'AXA'      THEN 'AXA손해보험'
    WHEN 'CARROT'   THEN '캐롯손해보험'
    WHEN 'DB'       THEN 'DB손해보험'
    WHEN 'HANA'     THEN '하나손해보험'
    WHEN 'HANHWA'   THEN '한화손해보험'
    WHEN 'HEUNGKUK' THEN '흥국화재'
    WHEN 'HYUNDAI'  THEN '현대해상'
    WHEN 'KB'       THEN 'KB손해보험'
    WHEN 'LOTTE'    THEN '롯데손해보험'
    WHEN 'MERITZ'   THEN '메리츠화재'
    WHEN 'SAMSUNG'  THEN '삼성화재'
    ELSE ca.join_insurer_code
  END                                                              AS "가입보험사",
  ca.subscription_type                                            AS "가입유형",
  CASE ca.counsel_status
    WHEN 'ACCUMULATE_PENDING' THEN '지급대기'
    WHEN 'JOIN_COMPLETED'     THEN '가입완료'
    ELSE ca.counsel_status
  END                                                              AS "현재상태",
  CASE WHEN ca.is_renewal THEN '갱신' ELSE '신규' END               AS "상담구분",
  cm.name                                                         AS "상담(체결)매니저",
  u.user_name                                                     AS "유치회원명",
  u.user_id                                                       AS "유치회원ID"
FROM AJDCAR_PROD.PUBLIC.COUNSEL_APPLICATION ca
JOIN status_agg sa                          ON sa.counsel_id = ca.counsel_id
JOIN AJDCAR_PROD.PUBLIC.COUNSEL_VEHICLE cv  ON cv.counsel_id = ca.counsel_id AND cv.is_deleted = FALSE
JOIN AJDCAR_PROD.PUBLIC.CUSTOMER cu         ON cu.customer_id = ca.customer_id AND cu.is_deleted = FALSE
LEFT JOIN AJDCAR_PROD.PUBLIC.USERS u        ON u.id = ca.user_id
LEFT JOIN AJDCAR_PROD.PUBLIC.MANAGER cm     ON cm.id = ca.counsel_manager_id
WHERE ca.is_deleted = FALSE
  AND ca.counsel_status IN ('ACCUMULATE_PENDING', 'JOIN_COMPLETED')
  AND (u.id IS NULL OR (u.is_deleted = FALSE AND u.business_card_status <> '반려'))
  AND (cm.name IS NULL OR cm.name NOT LIKE '%테스트%')
ORDER BY COALESCE(sa.pending_at, ca.join_completed_at) DESC;


-- =====================================================================
-- 3. 가입 취소 리스트
-- =====================================================================
WITH cancel_agg AS (
  SELECT
    csl.counsel_id,
    MAX(CASE WHEN csl.new_counsel_status = 'JOIN_CANCELLED'
             THEN csl.created_at END) AS cancelled_at
  FROM AJDCAR_PROD.PUBLIC.COUNSEL_STATUS_LOG csl
  GROUP BY csl.counsel_id
)

SELECT
  CASE ca.channel_path
    WHEN 'DEALER_APP' THEN '딜러앱'
    WHEN 'RENEWAL'    THEN '갱신'
    WHEN 'CS'         THEN 'CS'
    ELSE '기타'
  END                                                              AS "영업채널",
  cu.customer_name                                                AS "고객명",
  cu.customer_id                                                  AS "고객번호",
  ca.counsel_id                                                   AS "상담번호",
  NULL /* 확인 필요: 주민번호 컬럼명 */                              AS "주민번호",
  '="' || cu.customer_phone_number || '"'                         AS "연락처",
  cv.license_plate_number                                         AS "차량번호",
  cv.vin                                                          AS "차대번호",
  TO_CHAR(ca.insurance_end_dt, 'YYYY-MM-DD')                      AS "새보험만기일",
  cv.contract_amount                                              AS "보험료",
  TO_CHAR(ca.join_completed_at, 'YYYY-MM-DD')                     AS "체결일자",
  TO_CHAR(cn.cancelled_at, 'YYYY-MM-DD')                          AS "가입취소일자",
  CASE ca.join_insurer_code
    WHEN 'AXA'      THEN 'AXA손해보험'
    WHEN 'CARROT'   THEN '캐롯손해보험'
    WHEN 'DB'       THEN 'DB손해보험'
    WHEN 'HANA'     THEN '하나손해보험'
    WHEN 'HANHWA'   THEN '한화손해보험'
    WHEN 'HEUNGKUK' THEN '흥국화재'
    WHEN 'HYUNDAI'  THEN '현대해상'
    WHEN 'KB'       THEN 'KB손해보험'
    WHEN 'LOTTE'    THEN '롯데손해보험'
    WHEN 'MERITZ'   THEN '메리츠화재'
    WHEN 'SAMSUNG'  THEN '삼성화재'
    ELSE ca.join_insurer_code
  END                                                              AS "가입보험사",
  ca.subscription_type                                            AS "가입유형",
  cm.name                                                         AS "상담(체결)매니저",
  u.user_name                                                     AS "유치회원명",
  u.user_id                                                       AS "유치회원ID"
FROM AJDCAR_PROD.PUBLIC.COUNSEL_APPLICATION ca
JOIN AJDCAR_PROD.PUBLIC.COUNSEL_VEHICLE cv ON cv.counsel_id = ca.counsel_id AND cv.is_deleted = FALSE
JOIN AJDCAR_PROD.PUBLIC.CUSTOMER cu        ON cu.customer_id = ca.customer_id AND cu.is_deleted = FALSE
LEFT JOIN AJDCAR_PROD.PUBLIC.USERS u       ON u.id = ca.user_id
LEFT JOIN AJDCAR_PROD.PUBLIC.MANAGER cm    ON cm.id = ca.counsel_manager_id
LEFT JOIN cancel_agg cn                    ON cn.counsel_id = ca.counsel_id
WHERE ca.is_deleted = FALSE
  AND ca.counsel_status = 'JOIN_CANCELLED'
  AND (u.id IS NULL OR (u.is_deleted = FALSE AND u.business_card_status <> '반려'))
  AND (cm.name IS NULL OR cm.name NOT LIKE '%테스트%')
ORDER BY cn.cancelled_at DESC NULLS LAST;


-- =====================================================================
-- 4. 기타 확인용
-- =====================================================================
SELECT DISTINCT is_associate FROM AJDCAR_PROD.PUBLIC.USERS;
