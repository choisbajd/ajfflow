-- 운영 리포트 v3 (2026-09-28)
-- 기준: queries/reference_download.sql (다운로드 쿼리) - 제외 조건 포함 전부 참고 쿼리 기준
-- 분석/근거: docs/queries_analysis.md
--
-- 참고 쿼리에서 미반영
--   - 회원유형 G1~G5 CASE (매핑 미제공) -> member_type_map 으로 대체 (확정분만 등록)
--   - 고객명/연락처 마스킹 (로직 미제공)
--   - 센터 최종 판단 (저장 위치 미정)
--
-- 기간/필터: 각 쿼리 params CTE 수정. cur_from 포함 ~ cur_to 미포함, 필터값 NULL = 전체

-- =====================================================================
-- 1. 회원(딜러) 리스트 - 기간 무관, 전체 회원 (탈퇴 포함)
-- =====================================================================
WITH status_agg AS (
  SELECT
    counsel_id,
    MIN(CASE WHEN new_counsel_status = 'ACCUMULATE_PENDING' THEN created_at END) AS pending_at
  FROM AJDCAR_PROD.PUBLIC.COUNSEL_STATUS_LOG
  GROUP BY counsel_id
),

-- 상담 단위 선집계: 동일보험사(§22) 차량은 실적 불인정
counsel_deal_agg AS (
  SELECT
    ca.user_id,
    ca.counsel_id,
    ca.is_self_family_contract,
    COALESCE(sa.pending_at, ca.join_completed_at)                              AS deal_at,
    SUM(CASE WHEN cv.exist_insurer_code = ca.join_insurer_code
             THEN NULL ELSE cv.contract_amount END)                            AS recognized_premium,
    COUNT_IF(COALESCE(cv.exist_insurer_code = ca.join_insurer_code, FALSE) = FALSE) AS recognized_vehicle_count
  FROM AJDCAR_PROD.PUBLIC.COUNSEL_APPLICATION ca
  JOIN status_agg sa                         ON sa.counsel_id = ca.counsel_id
  JOIN AJDCAR_PROD.PUBLIC.COUNSEL_VEHICLE cv ON cv.counsel_id = ca.counsel_id
                                            AND COALESCE(cv.is_deleted, FALSE) = FALSE
  WHERE COALESCE(ca.is_deleted, FALSE) = FALSE
    AND ca.counsel_status IN ('ACCUMULATE_PENDING', 'JOIN_COMPLETED')
  GROUP BY ca.user_id, ca.counsel_id, ca.is_self_family_contract, COALESCE(sa.pending_at, ca.join_completed_at)
),

deal_agg AS (
  SELECT
    user_id                                                                    AS dealer_id,
    COUNT(DISTINCT counsel_id)                                                 AS deal_count,
    COUNT(DISTINCT CASE WHEN is_self_family_contract = TRUE THEN counsel_id END) AS self_family_count,
    SUM(recognized_premium)                                                    AS total_premium,
    MIN(deal_at)                                                               AS first_deal_at,
    MAX(deal_at)                                                               AS last_deal_at
  FROM counsel_deal_agg
  WHERE recognized_vehicle_count > 0          -- 전 차량 동일보험사인 상담 제외
  GROUP BY user_id
),

latest_ad_point AS (
  SELECT user_id, remaining_amount
  FROM AJDCAR_PROD.PUBLIC.AD_POINT_TRANSACTIONS
  WHERE status = 'COMPLETED'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY id DESC) = 1
),

ad_usage AS (
  SELECT user_id, SUM(amount) AS total_used
  FROM AJDCAR_PROD.PUBLIC.AD_POINT_TRANSACTIONS
  WHERE status = 'COMPLETED'
    AND type = 'WITHDRAW'
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
  CASE WHEN u.business_type = 'NEW_CAR_DEALER' THEN
    CASE u.business_sub_type
      WHEN 'IMPORTED' THEN '수입'
      WHEN 'DOMESTIC' THEN '국산'
      ELSE '미분류'
    END
  END                                                              AS "딜러세부유형",
  u.primary_affiliation                                           AS "1차소속",
  u.secondary_affiliation                                         AS "2차소속",
  CASE WHEN u.is_associate = TRUE THEN '준회원' ELSE '정회원' END     AS "회원구분",
  CASE WHEN u.is_deleted = TRUE THEN 'Y' ELSE 'N' END              AS "탈퇴여부",
  COALESCE(lap.remaining_amount, 0)                                AS "잔여광고비",
  COALESCE(da.deal_count, 0)                                      AS "누적계약체결수",
  COALESCE(da.self_family_count, 0)                               AS "본인가족계약건수",
  COALESCE(da.total_premium, 0)                                   AS "누적총원수보험료",
  COALESCE(au.total_used, 0)                                      AS "누적광고비"
FROM AJDCAR_PROD.PUBLIC.USERS u
LEFT JOIN AJDCAR_PROD.PUBLIC.MANAGER m ON m.id = u.manager_id
LEFT JOIN deal_agg da                  ON da.dealer_id = u.id
LEFT JOIN latest_ad_point lap          ON lap.user_id = u.id
LEFT JOIN ad_usage au                  ON au.user_id = u.id
WHERE COALESCE(u.business_card_status, '') <> 'REJECTED'
  AND COALESCE(u.is_performance_exclude, FALSE) = FALSE
  AND (m.name IS NULL OR m.name NOT LIKE '%테스트%')
ORDER BY u.created_at DESC;


-- =====================================================================
-- 2. 계약(체결) 리스트 + 자동 조건 판정 - 체결일자가 기간 안 (차량 단위 행)
--
-- 조건 (각 조건 PASS / FAIL / UNKNOWN)
--   C1 활동회원: 같은 유치회원의 다른 계약이 체결일 직전 60일 이내 [체결일-60일, 체결일) 에 있음
--   C2 회원유형: member_type_map.is_eligible (TRUE 충족 / FALSE 미충족 / 미등록 확인 필요)
--   C3 영업용  : vehicle_usage_map.is_commercial (FALSE 충족 / TRUE 미충족 / 미등록·NULL 확인 필요)
--   C4 보험사  : 새가입 <> 기존 충족 / 같음 미충족 / 둘 중 NULL 확인 필요
-- 종합: FAIL 1개 이상 -> 조건 미충족 (FAIL 사유만 표시)
--       FAIL 없고 UNKNOWN 1개 이상 -> 확인 필요 (UNKNOWN 사유만 표시)
--       전부 PASS -> 조건 충족 (전 조건 표시)
-- =====================================================================
WITH params AS (
  SELECT
    '2000-01-01'::TIMESTAMP_NTZ AS cur_from,
    '2100-01-01'::TIMESTAMP_NTZ AS cur_to,
    NULL::VARCHAR               AS f_auto_judgment,     -- '조건 충족' / '조건 미충족' / '확인 필요'
    NULL::VARCHAR               AS f_member_type,       -- 예: '신차딜러(수입)'
    NULL::VARCHAR               AS f_new_insurer,       -- 예: '삼성화재'
    NULL::VARCHAR               AS f_counsel_manager,   -- 부분일치
    NULL::VARCHAR               AS f_dealer_name        -- 부분일치
),

-- 회원유형 매핑. business_sub_type 이 NULL 인 행은 해당 business_type 의 모든 세부유형에 매칭
-- (같은 business_type 에 NULL 행과 세부유형 행을 같이 넣지 말 것 - 중복 매칭)
member_type_map (business_type, business_sub_type, label, is_eligible) AS (
  SELECT * FROM VALUES
    ('NEW_CAR_DEALER', 'DOMESTIC', '신차딜러(국산)', TRUE),
    ('NEW_CAR_DEALER', 'IMPORTED', '신차딜러(수입)', TRUE)
    -- 확인 필요: 보험설계사(충족) / 중고차 딜러(미충족) / 에이전트(미충족) 의 business_type 값
    -- ,('<보험설계사 코드>', NULL, '보험설계사', TRUE)
    -- ,('<중고차 코드>',     NULL, '중고차 딜러', FALSE)
    -- ,('<에이전트 코드>',   NULL, '에이전트', FALSE)
),

-- 차량용도 매핑 (counsel_application.vehicle_usage_code). 확인 필요: 실제 코드값
vehicle_usage_map (code, is_commercial) AS (
  SELECT * FROM VALUES
    ('__PLACEHOLDER__', FALSE)   -- 코드 확인 후 교체. 예: ('<비영업용 코드>', FALSE), ('<영업용 코드>', TRUE)
),

insurer_map (code, name) AS (
  SELECT * FROM VALUES
    ('AXA', 'AXA손해보험'), ('CARROT', '캐롯손해보험'), ('DB', 'DB손해보험'),
    ('HANA', '하나손해보험'), ('HANHWA', '한화손해보험'), ('HEUNGKUK', '흥국화재'),
    ('HYUNDAI', '현대해상'), ('KB', 'KB손해보험'), ('LOTTE', '롯데손해보험'),
    ('MERITZ', '메리츠화재'), ('SAMSUNG', '삼성화재')
),

status_agg AS (
  SELECT
    counsel_id,
    MIN(CASE WHEN new_counsel_status = 'ACCUMULATE_PENDING' THEN created_at END) AS pending_at
  FROM AJDCAR_PROD.PUBLIC.COUNSEL_STATUS_LOG
  GROUP BY counsel_id
),

-- 계약 상담 (상담 단위, 체결일자 포함). 활동회원 판정의 모집단이기도 함
contracts AS (
  SELECT
    ca.counsel_id,
    ca.user_id,
    COALESCE(sa.pending_at, ca.join_completed_at) AS deal_at
  FROM AJDCAR_PROD.PUBLIC.COUNSEL_APPLICATION ca
  JOIN status_agg sa ON sa.counsel_id = ca.counsel_id
  WHERE COALESCE(ca.is_deleted, FALSE) = FALSE
    AND ca.counsel_status IN ('ACCUMULATE_PENDING', 'JOIN_COMPLETED')
),

activity AS (
  SELECT
    c.counsel_id,
    COUNT(p.counsel_id) AS prev_60d_count
  FROM contracts c
  LEFT JOIN contracts p
    ON  p.user_id     = c.user_id
    AND p.counsel_id <> c.counsel_id
    AND p.deal_at    >= DATEADD(day, -60, c.deal_at)
    AND p.deal_at    <  c.deal_at
  GROUP BY c.counsel_id
),

base AS (
  SELECT
    c.counsel_id,
    cv.counsel_vehicle_id,
    c.deal_at,
    cu.customer_name,
    cv.license_plate_number,
    cv.contract_amount,
    ca.join_insurer_code,
    cv.exist_insurer_code,
    COALESCE(ni.name, ca.join_insurer_code)       AS new_insurer_name,
    COALESCE(ei.name, cv.exist_insurer_code)      AS exist_insurer_name,
    ca.vehicle_usage_code,
    ca.is_self_family_contract,
    vu.is_commercial,
    u.id                                          AS dealer_id,
    u.user_name                                   AS dealer_name,
    u.business_type,
    u.business_sub_type,
    mt.is_eligible,
    COALESCE(mt.label, u.business_type)           AS member_type_label,
    a.prev_60d_count,
    cm.name                                       AS counsel_manager_name
  FROM contracts c
  CROSS JOIN params p
  JOIN activity a                             ON a.counsel_id = c.counsel_id
  JOIN AJDCAR_PROD.PUBLIC.COUNSEL_APPLICATION ca ON ca.counsel_id = c.counsel_id
  JOIN AJDCAR_PROD.PUBLIC.COUNSEL_VEHICLE cv  ON cv.counsel_id = c.counsel_id
                                             AND COALESCE(cv.is_deleted, FALSE) = FALSE
  JOIN AJDCAR_PROD.PUBLIC.CUSTOMER cu         ON cu.customer_id = ca.customer_id
                                             AND COALESCE(cu.is_deleted, FALSE) = FALSE
  LEFT JOIN AJDCAR_PROD.PUBLIC.USERS u        ON u.id = c.user_id
  LEFT JOIN AJDCAR_PROD.PUBLIC.MANAGER cm     ON cm.id = ca.counsel_manager_id
  LEFT JOIN member_type_map mt                ON mt.business_type = u.business_type
                                             AND (mt.business_sub_type IS NULL OR mt.business_sub_type = u.business_sub_type)
  LEFT JOIN vehicle_usage_map vu              ON vu.code = ca.vehicle_usage_code
  LEFT JOIN insurer_map ni                    ON ni.code = ca.join_insurer_code
  LEFT JOIN insurer_map ei                    ON ei.code = cv.exist_insurer_code
  WHERE c.deal_at >= p.cur_from
    AND c.deal_at <  p.cur_to
    AND (u.id IS NULL OR (
          COALESCE(u.is_deleted, FALSE) = FALSE
      AND COALESCE(u.business_card_status, '') <> 'REJECTED'
      AND COALESCE(u.is_performance_exclude, FALSE) = FALSE
    ))
    AND (cm.name IS NULL OR cm.name NOT LIKE '%테스트%')
),

cond AS (
  SELECT
    b.*,
    -- C1 활동회원
    CASE WHEN dealer_id IS NULL THEN 'UNKNOWN'
         WHEN prev_60d_count > 0 THEN 'PASS' ELSE 'FAIL' END                   AS c1_status,
    CASE WHEN dealer_id IS NULL THEN '유치회원 없음'
         WHEN prev_60d_count > 0 THEN '활동회원 Y' ELSE '활동회원 N' END         AS c1_text,
    -- C2 회원유형
    CASE WHEN dealer_id IS NULL THEN 'UNKNOWN'
         WHEN is_eligible = TRUE  THEN 'PASS'
         WHEN is_eligible = FALSE THEN 'FAIL'
         ELSE 'UNKNOWN' END                                                    AS c2_status,
    CASE WHEN dealer_id IS NULL THEN NULL                                      -- C1 에서 '유치회원 없음' 표시
         WHEN is_eligible IS NOT NULL THEN member_type_label
         ELSE '회원유형 미확인(' || COALESCE(business_type, '-') || '/' || COALESCE(business_sub_type, '-') || ')'
    END                                                                        AS c2_text,
    -- C3 영업용
    CASE WHEN is_commercial = FALSE THEN 'PASS'
         WHEN is_commercial = TRUE  THEN 'FAIL'
         ELSE 'UNKNOWN' END                                                    AS c3_status,
    CASE WHEN vehicle_usage_code IS NULL THEN '차량용도 정보 없음'
         WHEN is_commercial = FALSE THEN '영업용 아님'
         WHEN is_commercial = TRUE  THEN '영업용'
         ELSE '차량용도 미확인(' || vehicle_usage_code || ')' END              AS c3_text,
    -- C4 새가입보험사 vs 기존보험사
    CASE WHEN join_insurer_code IS NULL OR exist_insurer_code IS NULL THEN 'UNKNOWN'
         WHEN join_insurer_code = exist_insurer_code THEN 'FAIL'
         ELSE 'PASS' END                                                       AS c4_status,
    CASE WHEN join_insurer_code IS NULL  THEN '새가입보험사 정보 없음'
         WHEN exist_insurer_code IS NULL THEN '기존보험사 정보 없음'
         WHEN join_insurer_code = exist_insurer_code THEN '동일 보험사 갱신'
         ELSE '타사 갱신' END                                                  AS c4_text
  FROM base b
),

judged AS (
  SELECT
    cond.*,
    CASE WHEN 'FAIL'    IN (c1_status, c2_status, c3_status, c4_status) THEN 'FAIL'
         WHEN 'UNKNOWN' IN (c1_status, c2_status, c3_status, c4_status) THEN 'UNKNOWN'
         ELSE 'PASS' END                                                       AS overall_status
  FROM cond
)

SELECT
  TO_CHAR(j.deal_at, 'YYYY-MM-DD')                                AS "체결일자",
  j.customer_name                                                 AS "고객명",
  j.license_plate_number                                          AS "차량번호",
  j.contract_amount                                               AS "보험료",
  j.new_insurer_name                                              AS "새가입보험사",
  j.exist_insurer_name                                            AS "기존보험사",
  j.dealer_name                                                   AS "유치회원명",
  j.member_type_label                                             AS "유치회원유형",
  DECODE(j.overall_status, 'PASS', '조건 충족', 'FAIL', '조건 미충족', '확인 필요') AS "자동 조건 판정",
  ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(
    IFF(j.c1_status = j.overall_status, j.c1_text, NULL),
    IFF(j.c2_status = j.overall_status, j.c2_text, NULL),
    IFF(j.c3_status = j.overall_status, j.c3_text, NULL),
    IFF(j.c4_status = j.overall_status, j.c4_text, NULL)
  ), ' / ')                                                       AS "조건 판정 사유",
  j.counsel_manager_name                                          AS "상담(체결)매니저",
  -- 조건별 상세
  CASE WHEN j.dealer_id IS NULL THEN NULL
       WHEN j.prev_60d_count > 0 THEN 'Y' ELSE 'N' END            AS "활동회원",
  j.prev_60d_count                                                AS "직전60일체결수",
  CASE WHEN j.is_commercial = TRUE THEN 'Y'
       WHEN j.is_commercial = FALSE THEN 'N' END                  AS "영업용",
  CASE WHEN j.c4_status = 'UNKNOWN' THEN NULL
       WHEN j.c4_status = 'FAIL' THEN 'Y' ELSE 'N' END            AS "동일보험사",
  CASE WHEN j.is_self_family_contract = TRUE THEN 'Y' ELSE 'N' END AS "본인가족계약여부",
  -- 식별 키 (센터 판단 연결용)
  j.counsel_id                                                    AS "상담번호",
  j.counsel_vehicle_id                                            AS "상담차량ID"
FROM judged j
CROSS JOIN params p
WHERE (p.f_auto_judgment   IS NULL OR DECODE(j.overall_status, 'PASS', '조건 충족', 'FAIL', '조건 미충족', '확인 필요') = p.f_auto_judgment)
  AND (p.f_member_type     IS NULL OR j.member_type_label = p.f_member_type)
  AND (p.f_new_insurer     IS NULL OR j.new_insurer_name = p.f_new_insurer)
  AND (p.f_counsel_manager IS NULL OR j.counsel_manager_name ILIKE '%' || p.f_counsel_manager || '%')
  AND (p.f_dealer_name     IS NULL OR j.dealer_name ILIKE '%' || p.f_dealer_name || '%')
ORDER BY j.deal_at DESC, j.counsel_id;


-- =====================================================================
-- 3. 가입 취소 리스트 - 가입취소일이 기간 안 (차량 단위 행)
-- =====================================================================
WITH params AS (
  SELECT '2000-01-01'::TIMESTAMP_NTZ AS cur_from,
         '2100-01-01'::TIMESTAMP_NTZ AS cur_to
),

status_agg AS (
  SELECT
    counsel_id,
    MAX(CASE WHEN new_counsel_status = 'JOIN_CANCELLED' THEN created_at END) AS cancelled_at
  FROM AJDCAR_PROD.PUBLIC.COUNSEL_STATUS_LOG
  GROUP BY counsel_id
),

insurer_map (code, name) AS (
  SELECT * FROM VALUES
    ('AXA', 'AXA손해보험'), ('CARROT', '캐롯손해보험'), ('DB', 'DB손해보험'),
    ('HANA', '하나손해보험'), ('HANHWA', '한화손해보험'), ('HEUNGKUK', '흥국화재'),
    ('HYUNDAI', '현대해상'), ('KB', 'KB손해보험'), ('LOTTE', '롯데손해보험'),
    ('MERITZ', '메리츠화재'), ('SAMSUNG', '삼성화재')
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
  TO_CHAR(ca.join_completed_at, 'YYYY-MM-DD')                     AS "체결일자",
  TO_CHAR(sa.cancelled_at, 'YYYY-MM-DD')                          AS "가입취소일자",
  COALESCE(ni.name, ca.join_insurer_code)                         AS "가입보험사",
  COALESCE(ei.name, cv.exist_insurer_code)                        AS "기존보험사",
  CASE WHEN cv.exist_insurer_code = ca.join_insurer_code THEN 'N' ELSE 'Y' END AS "실적인정여부",
  ca.subscription_type                                            AS "가입유형",
  CASE WHEN ca.is_self_family_contract = TRUE THEN 'Y' ELSE 'N' END AS "본인가족계약여부",
  cm.name                                                         AS "상담(체결)매니저",
  u.user_name                                                     AS "유치회원명",
  u.user_id                                                       AS "유치회원ID"
FROM AJDCAR_PROD.PUBLIC.COUNSEL_APPLICATION ca
CROSS JOIN params p
JOIN AJDCAR_PROD.PUBLIC.COUNSEL_VEHICLE cv ON cv.counsel_id = ca.counsel_id
                                          AND COALESCE(cv.is_deleted, FALSE) = FALSE
JOIN AJDCAR_PROD.PUBLIC.CUSTOMER cu        ON cu.customer_id = ca.customer_id
                                          AND COALESCE(cu.is_deleted, FALSE) = FALSE
LEFT JOIN status_agg sa                    ON sa.counsel_id = ca.counsel_id
LEFT JOIN AJDCAR_PROD.PUBLIC.USERS u       ON u.id = ca.user_id
LEFT JOIN AJDCAR_PROD.PUBLIC.MANAGER cm    ON cm.id = ca.counsel_manager_id
LEFT JOIN insurer_map ni                   ON ni.code = ca.join_insurer_code
LEFT JOIN insurer_map ei                   ON ei.code = cv.exist_insurer_code
WHERE COALESCE(ca.is_deleted, FALSE) = FALSE
  AND ca.counsel_status = 'JOIN_CANCELLED'
  AND sa.cancelled_at >= p.cur_from
  AND sa.cancelled_at <  p.cur_to
  AND (u.id IS NULL OR (
        COALESCE(u.is_deleted, FALSE) = FALSE
    AND COALESCE(u.business_card_status, '') <> 'REJECTED'
    AND COALESCE(u.is_performance_exclude, FALSE) = FALSE
  ))
  AND (cm.name IS NULL OR cm.name NOT LIKE '%테스트%')
ORDER BY sa.cancelled_at DESC, ca.counsel_id;
