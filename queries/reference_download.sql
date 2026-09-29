-- 기준 참고용 다운로드 쿼리 (사용자 제공 원문, 2026-09-28)
-- 괄호 표기 "(... CASE)", "(마스킹된 ...)" 부분은 원문에서도 생략된 상태
-- 이 쿼리의 판정 기준을 reports_v3.sql 에 반영함

-- 공통 헬퍼 (세 쿼리가 공유)
-- 상태 이력 선집계 (1 counsel_id = 1 row)
status_agg AS (
  SELECT
    counsel_id,
    MIN(CASE WHEN new_counsel_status = 'ACCUMULATE_PENDING' THEN created_at END) AS pending_at,
    MAX(CASE WHEN new_counsel_status = 'JOIN_CANCELLED'     THEN created_at END) AS cancelled_at
  FROM counsel_status_log
  GROUP BY counsel_id
)

-- 계약 인정 상태 (현재 상태 기준, §3)
-- IN ('ACCUMULATE_PENDING', 'JOIN_COMPLETED')

-- 동일 보험사 가입 판정 (§22) — 실적 불인정
(cv.exist_insurer_code IS NOT NULL AND cv.exist_insurer_code = ca.join_insurer_code)

-- 딜러 제외 조건 (계약_체결/계약_취소 공통)
(u.id IS NULL OR (
   COALESCE(u.is_deleted, FALSE) = FALSE
   AND COALESCE(u.business_card_status, '') <> 'REJECTED'
   AND COALESCE(u.is_performance_exclude, FALSE) = FALSE
 ))
AND (cm.name IS NULL OR cm.name NOT LIKE '%테스트%')

-- 1. 회원리스트 — 기간 무관, 전체 회원 (바인드 없음)
WITH status_agg AS ( ... 위와 동일 ... ),

-- 상담 단위 선집계: 동일보험사 실적 제외를 상담(counsel_id) 단위로 순계산
counsel_deal_agg AS (
  SELECT
    ca.user_id, ca.counsel_id, ca.is_self_family_contract,
    COALESCE(sa.pending_at, ca.join_completed_at) AS deal_at,
    SUM(CASE WHEN (동일보험사판정) THEN NULL ELSE cv.contract_amount END) AS recognized_premium,
    COUNT(CASE WHEN (동일보험사판정) THEN NULL ELSE 1 END) AS recognized_vehicle_count,
    COUNT(*) AS vehicle_count
  FROM counsel_application ca
  JOIN status_agg sa      ON sa.counsel_id = ca.counsel_id
  JOIN counsel_vehicle cv ON cv.counsel_id = ca.counsel_id AND COALESCE(cv.is_deleted, FALSE) = FALSE
  WHERE COALESCE(ca.is_deleted, FALSE) = FALSE
    AND ca.counsel_status IN ('ACCUMULATE_PENDING', 'JOIN_COMPLETED')
  GROUP BY ca.user_id, ca.counsel_id, ca.is_self_family_contract, COALESCE(sa.pending_at, ca.join_completed_at)
),
deal_agg AS (
  SELECT
    cd.user_id AS dealer_id,
    COUNT(DISTINCT cd.counsel_id) AS deal_count,
    COUNT(DISTINCT CASE WHEN cd.is_self_family_contract = TRUE THEN cd.counsel_id END) AS self_family_count,
    SUM(cd.recognized_premium) AS total_premium,
    MIN(cd.deal_at) AS first_deal_at,
    MAX(cd.deal_at) AS last_deal_at
  FROM counsel_deal_agg cd
  WHERE NOT (cd.vehicle_count > 0 AND cd.recognized_vehicle_count = 0)  -- 전량 동일보험사 상담 제외
  GROUP BY cd.user_id
),
-- 잔여광고비: 회원별 최신 COMPLETED 거래 1건
latest_ad_point AS (
  SELECT user_id, remaining_amount FROM (
    SELECT user_id, remaining_amount,
           ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY id DESC) AS rn
    FROM ad_point_transactions WHERE status = 'COMPLETED'
  ) WHERE rn = 1
),
-- 누적광고비: WITHDRAW 합계
ad_usage AS (
  SELECT user_id, SUM(CASE WHEN type = 'WITHDRAW' THEN amount ELSE 0 END) AS total_used
  FROM ad_point_transactions WHERE status = 'COMPLETED' GROUP BY user_id
)
SELECT
  u.created_at                                                   AS "가입일시",
  da.first_deal_at                                                AS "최초계약일",
  da.last_deal_at                                                 AS "최종계약일",
  u.user_name                                                     AS "딜러이름",
  u.user_id                                                       AS "로그인ID",
  u.phone                                                         AS "연락처",
  m.name                                                          AS "담당매니저",
  u.business_type                                                 AS "소속구분",
  (딜러등급 G1~G5 CASE)                                            AS "회원유형",
  u.primary_affiliation                                           AS "1차소속",
  u.secondary_affiliation                                         AS "2차소속",
  CASE WHEN u.is_associate = TRUE THEN '준회원' ELSE '정회원' END   AS "회원구분",
  CASE WHEN u.is_deleted = TRUE THEN 'Y' ELSE 'N' END              AS "탈퇴여부",
  COALESCE(lap.remaining_amount, 0)                               AS "잔여광고비",
  COALESCE(da.deal_count, 0)                                      AS "누적계약체결수",
  COALESCE(da.self_family_count, 0)                               AS "본인가족계약건수",
  COALESCE(da.total_premium, 0)                                   AS "누적총원수보험료",
  COALESCE(au.total_used, 0)                                      AS "누적광고비"
FROM users u
LEFT JOIN manager         m   ON m.id = u.manager_id
LEFT JOIN deal_agg        da  ON da.dealer_id = u.id
LEFT JOIN latest_ad_point lap ON lap.user_id = u.id
LEFT JOIN ad_usage        au  ON au.user_id = u.id
WHERE COALESCE(u.business_card_status, '') <> 'REJECTED'
  AND COALESCE(u.is_performance_exclude, FALSE) = FALSE
  AND (m.name IS NULL OR m.name NOT LIKE '%테스트%')
ORDER BY u.created_at DESC

-- 2. 계약_체결 — 체결일자가 선택 기간 안 (바인드: from, to)
WITH status_agg AS ( ... ),
params AS (SELECT ?::TIMESTAMP_NTZ AS cur_from, ?::TIMESTAMP_NTZ AS cur_to)

SELECT
  (channel_path CASE)                          AS "유입채널",
  (마스킹된 고객명)                              AS "고객명",
  cu.customer_id                                AS "고객번호",
  ca.counsel_id                                 AS "상담번호",
  (마스킹된 연락처)                              AS "연락처",
  cv.license_plate_number                       AS "차량번호",
  cv.vin                                        AS "차대번호",
  ca.insurance_end_dt                           AS "새보험만기일",
  cv.contract_amount                            AS "보험료",
  COALESCE(sa.pending_at, ca.join_completed_at) AS "체결일자",
  (join_insurer_code 라벨)                       AS "새가입보험사",
  (exist_insurer_code 라벨)                      AS "기존보험사",
  CASE WHEN (동일보험사판정) THEN 'N' ELSE 'Y' END AS "실적인정여부",
  ca.subscription_type                          AS "가입유형",
  CASE WHEN ca.is_self_family_contract = TRUE THEN 'Y' ELSE 'N' END AS "본인가족계약여부",
  CASE ca.counsel_status
      WHEN 'ACCUMULATE_PENDING' THEN '지급대기'
      WHEN 'JOIN_COMPLETED'     THEN '가입완료'
      ELSE ca.counsel_status END                AS "현재상태",
  CASE WHEN ca.is_renewal THEN '갱신' ELSE '신규' END AS "상담구분",
  cm.name                                       AS "상담(체결)매니저",
  um.name                                       AS "딜러전담매니저",
  CASE WHEN cm.id IS NOT NULL AND um.id IS NOT NULL AND cm.id <> um.id
       THEN 'Y' ELSE 'N' END                    AS "담당자상이",
  u.user_name                                   AS "유치회원명",
  u.user_id                                     AS "유치회원ID",
  (딜러등급 CASE)                                AS "유치회원유형"
FROM counsel_application ca
CROSS JOIN params p
JOIN status_agg sa      ON sa.counsel_id = ca.counsel_id
JOIN counsel_vehicle cv ON cv.counsel_id = ca.counsel_id AND COALESCE(cv.is_deleted, FALSE) = FALSE
JOIN customer cu        ON cu.customer_id = ca.customer_id AND COALESCE(cu.is_deleted, FALSE) = FALSE
LEFT JOIN users   u  ON u.id = ca.user_id
LEFT JOIN manager cm ON cm.id = ca.counsel_manager_id
LEFT JOIN manager um ON um.id = u.manager_id
WHERE COALESCE(ca.is_deleted, FALSE) = FALSE
  AND ca.counsel_status IN ('ACCUMULATE_PENDING', 'JOIN_COMPLETED')
  AND COALESCE(sa.pending_at, ca.join_completed_at) >= p.cur_from
  AND COALESCE(sa.pending_at, ca.join_completed_at) <  p.cur_to
  AND (딜러 제외 조건 — 위 공통 헬퍼)
ORDER BY COALESCE(sa.pending_at, ca.join_completed_at) DESC, ca.counsel_id

-- 3. 계약_취소 — 가입취소일이 선택 기간 안 (바인드: from, to)
WITH status_agg AS ( ... ),
params AS (SELECT ?::TIMESTAMP_NTZ AS cur_from, ?::TIMESTAMP_NTZ AS cur_to)

SELECT
  (channel_path CASE)                          AS "유입채널",
  (마스킹된 고객명)                              AS "고객명",
  cu.customer_id                                AS "고객번호",
  ca.counsel_id                                 AS "상담번호",
  NULL                                          AS "주민번호",   -- 원본 컬럼 미확인, 자리만 유지
  (마스킹된 연락처)                              AS "연락처",
  cv.license_plate_number                       AS "차량번호",
  cv.vin                                        AS "차대번호",
  ca.insurance_end_dt                           AS "새보험만기일",
  cv.contract_amount                            AS "보험료",
  ca.join_completed_at                          AS "체결일자",
  sa.cancelled_at                               AS "가입취소일자",
  (join_insurer_code 라벨)                       AS "새가입보험사",
  (exist_insurer_code 라벨)                      AS "기존보험사",
  CASE WHEN (동일보험사판정) THEN 'N' ELSE 'Y' END AS "실적인정여부",
  ca.subscription_type                          AS "가입유형",
  CASE WHEN ca.is_self_family_contract = TRUE THEN 'Y' ELSE 'N' END AS "본인가족계약여부",
  cm.name                                       AS "상담(체결)매니저",
  u.user_name                                   AS "유치회원명",
  u.user_id                                     AS "유치회원ID",
  (딜러등급 CASE)                                AS "유치회원유형"
FROM counsel_application ca
CROSS JOIN params p
JOIN counsel_vehicle cv ON cv.counsel_id = ca.counsel_id AND COALESCE(cv.is_deleted, FALSE) = FALSE
JOIN customer cu        ON cu.customer_id = ca.customer_id AND COALESCE(cu.is_deleted, FALSE) = FALSE
LEFT JOIN users      u  ON u.id = ca.user_id
LEFT JOIN manager    cm ON cm.id = ca.counsel_manager_id
LEFT JOIN status_agg sa ON sa.counsel_id = ca.counsel_id
WHERE COALESCE(ca.is_deleted, FALSE) = FALSE
  AND ca.counsel_status = 'JOIN_CANCELLED'   -- 현재 상태 기준, 이력 기반 아님
  AND sa.cancelled_at >= p.cur_from
  AND sa.cancelled_at <  p.cur_to
  AND (딜러 제외 조건)
ORDER BY sa.cancelled_at DESC, ca.counsel_id
