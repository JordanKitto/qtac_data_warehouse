-- ============================================================
-- QTAC Data Engineer Assessment
-- Script: 07_create_gold_output.sql
-- Purpose:
--   Create the final business-ready gold layer output.
--
-- Model context:
--   The warehouse layer stores cleaned dimensions and facts.
--   The gold layer joins those tables into a reporting-ready
--   output that a business user could consume directly.
--
-- Source tables:
--   fact_preference
--   dim_applicant
--   dim_course
--   dim_qualification
--
-- Target:
--   gold_accepted_offers
--
-- Business requirement:
--   Produce a summary showing:
--     - applicant name and state
--     - accepted course
--     - institution name
--     - qualification type
--     - ATAR score where available
--
--   If an applicant has multiple accepted offers, select the
--   highest preference. The lowest preference_order represents
--   the highest preference.
-- ============================================================


-- ============================================================
-- Recreate gold layer table
-- ============================================================
-- The table is dropped and recreated so the script can be rerun
-- during development and testing.
-- ============================================================

DROP TABLE IF EXISTS gold_accepted_offers;

CREATE TABLE gold_accepted_offers AS

WITH ranked_accepted_offers AS (
    -- ========================================================
    -- Step 1: Start from accepted preference rows
    -- ========================================================
    -- Only accepted responses are relevant for the final output.
    --
    -- ROW_NUMBER ranks accepted offers per applicant.
    --
    -- Ranking logic:
    --   1. Lowest preference_order first
    --      This means highest applicant preference.
    --
    --   2. Lowest preference_id second
    --      This is a deterministic tie-breaker for cases where
    --      two accepted rows have the same applicant, course, and
    --      preference order.
    --
    -- Example:
    --   Applicant 1002 has two accepted preference rows in the
    --   fact table. The gold layer keeps one row only.
    -- ========================================================

    SELECT
        fp.*,

        ROW_NUMBER() OVER (
            PARTITION BY fp.applicant_id
            ORDER BY fp.preference_order ASC, fp.preference_id ASC
        ) AS accepted_offer_rank

    FROM fact_preference fp
    WHERE fp.response = 'Accepted'
),

selected_accepted_offers AS (
    -- ========================================================
    -- Step 2: Keep the highest-ranked accepted offer
    -- ========================================================
    -- This produces one accepted offer record per applicant.
    -- ========================================================

    SELECT *
    FROM ranked_accepted_offers
    WHERE accepted_offer_rank = 1
),

ranked_qualifications AS (
    -- ========================================================
    -- Step 3: Rank qualifications per applicant
    -- ========================================================
    -- The gold layer only needs one qualification row per
    -- applicant.
    --
    -- Ranking logic:
    --   1. Prefer Year 12 qualification first because ATAR is
    --      most relevant to Year 12 results.
    --
    --   2. If there are multiple qualifications, prefer the most
    --      recent year_completed.
    --
    --   3. Use qualification_id as a final deterministic
    --      tie-breaker.
    --
    -- This keeps the gold layer simple and avoids duplicating
    -- accepted-offer rows where an applicant has multiple
    -- qualifications.
    -- ========================================================

    SELECT
        q.*,

        ROW_NUMBER() OVER (
            PARTITION BY q.applicant_id
            ORDER BY
                CASE
                    WHEN q.qualification_type = 'Year 12' THEN 1
                    ELSE 2
                END,
                q.year_completed DESC,
                q.qualification_id ASC
        ) AS qualification_rank

    FROM dim_qualification q
)

-- ============================================================
-- Step 4: Build final accepted-offer output
-- ============================================================
-- Join the selected accepted offer to:
--   - current applicant details
--   - course and institution details
--   - best-ranked qualification details
--
-- The qualification join is a LEFT JOIN so applicants are not
-- dropped from the gold layer if qualification data is missing.
-- ============================================================

SELECT
    a.applicant_id,
    a.first_name || ' ' || a.last_name AS applicant_name,
    a.state,

    c.course_code AS accepted_course_code,
    c.course_name AS accepted_course_name,
    c.institution_name,

    q.qualification_type,
    q.atar_score,

    sao.preference_order,
    sao.offer_status,
    sao.response,
    sao.response_date

FROM selected_accepted_offers sao

-- Join to current applicant details.
-- fact_preference was loaded against the current applicant_key,
-- and this condition reinforces that the gold layer reports the
-- current applicant version.
INNER JOIN dim_applicant a
    ON sao.applicant_key = a.applicant_key
   AND a.is_current = TRUE

-- Join to course details for course name and institution name.
INNER JOIN dim_course c
    ON sao.course_key = c.course_key

-- Join to one ranked qualification per applicant.
LEFT JOIN ranked_qualifications q
    ON sao.applicant_id = q.applicant_id
   AND q.qualification_rank = 1

ORDER BY
    a.applicant_id;


-- ============================================================
-- Validation checks
-- ============================================================
-- Expected results:
--   gold_accepted_offers row count = 11
--
-- Reason:
--   fact_preference contains 12 accepted rows, but applicant 1002
--   has two accepted rows. The gold layer keeps one accepted offer
--   per applicant.
--
-- Applicant 1002 should appear once only.
-- ============================================================

SELECT COUNT(*) AS gold_row_count
FROM gold_accepted_offers;

SELECT *
FROM gold_accepted_offers
ORDER BY applicant_id;

SELECT *
FROM gold_accepted_offers
WHERE applicant_id = 1002;