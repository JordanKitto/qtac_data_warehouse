-- ============================================================
-- QTAC Data Engineer Assessment
-- Script: 03_apply_applicant_updates.sql
-- Purpose:
--   Apply applicants_update.csv to dim_applicant using
--   Slowly Changing Dimension Type 2 logic.
--
-- Model context:
--   dim_applicant stores one row per applicant version.
--   When a tracked applicant attribute changes, the old row is
--   expired and a new current row is inserted.
--
-- Source:
--   source_data/applicants_update.csv
--
-- Target:
--   dim_applicant
--
-- SCD2 process:
--   Step 1: Stage and deduplicate the update file
--   Step 2: Identify changed existing applicants
--   Step 3: Expire old current rows
--   Step 4: Insert new current rows for changed and new applicants
-- ============================================================


-- ============================================================
-- Step 1: Stage and deduplicate applicant updates
-- ============================================================
-- The update extract contains one exact duplicate row for
-- applicant_id 1002.
--
-- SELECT DISTINCT removes exact duplicate rows across all columns.
-- This does not remove legitimate multiple updates for the same
-- applicant if the row values are different.
--
-- A temporary staging table is used so the raw CSV remains
-- unchanged and the transformation is reproducible.
-- ============================================================

CREATE OR REPLACE TEMP TABLE stg_applicants_update AS
SELECT DISTINCT *
FROM read_csv('source_data/applicants_update.csv');


-- Validation check:
-- Expected result is 5 rows because the source file contains
-- 6 rows, including 1 exact duplicate.
SELECT COUNT(*) AS staged_update_rows
FROM stg_applicants_update;


-- ============================================================
-- Step 2: Identify changed existing applicants
-- ============================================================
-- This step compares the deduplicated update file against the
-- current version of each applicant in dim_applicant.
--
-- Only current applicant records are compared because historical
-- rows have already been expired.
--
-- A row is considered changed when at least one tracked attribute
-- differs between the update extract and the current dimension row.
--
-- Tracked attributes:
--   - first_name
--   - last_name
--   - date_of_birth
--   - email
--   - phone
--   - state
--   - postcode
--
-- IS DISTINCT FROM is used instead of <> because it handles NULLs
-- safely. For example, NULL and a non-NULL value are treated as
-- different.
--
-- phone and postcode are cast to VARCHAR because the warehouse
-- stores them as text identifiers, while DuckDB may infer them as
-- numeric values from the CSV.
-- ============================================================

CREATE OR REPLACE TEMP TABLE stg_changed_applicants AS
SELECT
    u.*
FROM stg_applicants_update u
INNER JOIN dim_applicant d
    ON u.applicant_id = d.applicant_id
WHERE d.is_current = TRUE
  AND (
        u.first_name IS DISTINCT FROM d.first_name
     OR u.last_name IS DISTINCT FROM d.last_name
     OR u.date_of_birth IS DISTINCT FROM d.date_of_birth
     OR u.email IS DISTINCT FROM d.email
     OR CAST(u.phone AS VARCHAR) IS DISTINCT FROM d.phone
     OR u.state IS DISTINCT FROM d.state
     OR CAST(u.postcode AS VARCHAR) IS DISTINCT FROM d.postcode
  );


-- Validation check:
-- Expected changed applicants are 1002, 1005, and 1007.
-- Applicant 1010 is excluded because it has no tracked changes.
-- Applicant 1016 is excluded here because it is new, not existing.
SELECT
    applicant_id,
    first_name,
    last_name,
    state,
    postcode,
    updated_date
FROM stg_changed_applicants
ORDER BY applicant_id;


-- ============================================================
-- Step 3: Expire old current rows for changed applicants
-- ============================================================
-- For each changed applicant, the current dimension row is expired.
--
-- The old row's effective_to date is set to one day before the
-- incoming update date.
--
-- Example:
--   If the new version starts on 2025-02-15,
--   the old version ends on 2025-02-14.
--
-- The old row is also marked as not current.
--
-- This update is run before inserting the new version so there is
-- only one current row per applicant at the time the expiry logic
-- runs.
-- ============================================================

UPDATE dim_applicant AS d
SET
    effective_to = CAST(c.updated_date AS DATE) - INTERVAL 1 DAY,
    is_current = FALSE
FROM stg_changed_applicants AS c
WHERE d.applicant_id = c.applicant_id
  AND d.is_current = TRUE;


-- Validation check:
-- The old rows for 1002, 1005, and 1007 should now be historical.
SELECT
    applicant_id,
    first_name,
    last_name,
    state,
    postcode,
    effective_from,
    effective_to,
    is_current
FROM dim_applicant
WHERE applicant_id IN (1002, 1005, 1007)
ORDER BY applicant_id, effective_from;


-- ============================================================
-- Step 4A: Identify brand-new applicants
-- ============================================================
-- New applicants are records that exist in the staged update file
-- but do not exist anywhere in dim_applicant.
--
-- These applicants do not need an old row expired because they have
-- no previous dimension record.
--
-- Expected new applicant:
--   applicant_id 1016
-- ============================================================

CREATE OR REPLACE TEMP TABLE stg_new_applicants AS
SELECT
    u.*
FROM stg_applicants_update u
LEFT JOIN dim_applicant d
    ON u.applicant_id = d.applicant_id
WHERE d.applicant_id IS NULL;


-- Validation check:
-- Expected result is applicant_id 1016.
SELECT
    applicant_id,
    first_name,
    last_name,
    state,
    postcode,
    updated_date
FROM stg_new_applicants
ORDER BY applicant_id;


-- ============================================================
-- Step 4B: Combine changed and new applicants for insertion
-- ============================================================
-- The final insert step should include:
--   - changed existing applicants, which need a new SCD2 version
--   - brand-new applicants, which need their first current row
--
-- It should not include unchanged applicants.
--
-- UNION ALL is used because the changed and new applicant sets are
-- mutually exclusive by design.
-- ============================================================

CREATE OR REPLACE TEMP TABLE stg_applicants_to_insert AS
SELECT *
FROM stg_changed_applicants

UNION ALL

SELECT *
FROM stg_new_applicants;


-- Validation check:
-- Expected applicants to insert:
--   1002, 1005, 1007, 1016
SELECT
    applicant_id,
    first_name,
    last_name,
    state,
    postcode,
    updated_date
FROM stg_applicants_to_insert
ORDER BY applicant_id;


-- ============================================================
-- Step 4C: Insert new current applicant versions
-- ============================================================
-- This inserts the new current rows for changed and new applicants.
--
-- applicant_key:
--   A new warehouse surrogate key is generated by taking the
--   current maximum applicant_key and adding a row number.
--
-- effective_from:
--   The new version becomes valid from the source updated_date.
--
-- effective_to:
--   Set to NULL because these are current records.
--
-- is_current:
--   Set to TRUE because these are the latest active versions.
--
-- phone and postcode:
--   Cast to VARCHAR to match the warehouse column types.
-- ============================================================

INSERT INTO dim_applicant (
    applicant_key,
    applicant_id,
    first_name,
    last_name,
    date_of_birth,
    email,
    phone,
    state,
    postcode,
    effective_from,
    effective_to,
    is_current
)
SELECT
    ROW_NUMBER() OVER (ORDER BY applicant_id)
        + (SELECT COALESCE(MAX(applicant_key), 0) FROM dim_applicant) AS applicant_key,
    applicant_id,
    first_name,
    last_name,
    date_of_birth,
    email,
    CAST(phone AS VARCHAR) AS phone,
    state,
    CAST(postcode AS VARCHAR) AS postcode,
    CAST(updated_date AS DATE) AS effective_from,
    NULL AS effective_to,
    TRUE AS is_current
FROM stg_applicants_to_insert;


-- ============================================================
-- Final validation checks
-- ============================================================
-- Expected final dim_applicant state:
--   total rows      = 19
--   current rows    = 16
--   historical rows = 3
--
-- Expected applicant outcomes:
--   1002 = old row expired, new NSW row current
--   1005 = old row expired, new Brown-Taylor row current
--   1007 = old row expired, new version current
--   1010 = unchanged, one current row only
--   1016 = new applicant, one current row
-- ============================================================

SELECT COUNT(*) AS total_rows
FROM dim_applicant;

SELECT
    is_current,
    COUNT(*) AS row_count
FROM dim_applicant
GROUP BY is_current
ORDER BY is_current;

SELECT
    applicant_key,
    applicant_id,
    first_name,
    last_name,
    state,
    postcode,
    effective_from,
    effective_to,
    is_current
FROM dim_applicant
WHERE applicant_id IN (1002, 1005, 1007, 1010, 1016)
ORDER BY applicant_id, effective_from;