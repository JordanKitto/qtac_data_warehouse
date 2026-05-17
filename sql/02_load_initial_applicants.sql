-- ============================================================
-- QTAC Data Engineer Assessment
-- Script: 02_load_initial_applicants.sql
-- Purpose:
--   Load the initial applicants.csv extract into dim_applicant.
--
-- Model context:
--   dim_applicant is an SCD Type 2 dimension.
--   This initial load creates the first current version for each
--   applicant.
--
-- Source:
--   source_data/applicants.csv
--
-- Target:
--   dim_applicant
-- ============================================================


-- ============================================================
-- Initial applicant load
-- ============================================================
-- Grain:
--   One row per applicant from the initial source extract.
--
-- Surrogate key:
--   applicant_key is generated using ROW_NUMBER().
--   This creates a warehouse-managed key that is separate from
--   the source applicant_id.
--
-- SCD2 setup:
--   effective_from is populated from the source updated_date.
--   effective_to is NULL because these are the current records.
--   is_current is TRUE because this is the first active version
--   for each applicant.
--
-- Notes:
--   created_date and updated_date exist in the source file, but
--   they are not stored directly in dim_applicant. updated_date is
--   used to initialise the SCD2 effective_from date.
--
--   phone and postcode are loaded into VARCHAR columns because
--   they are identifiers rather than numeric measures.
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
    ROW_NUMBER() OVER (ORDER BY applicant_id) AS applicant_key,
    applicant_id,
    first_name,
    last_name,
    date_of_birth,
    email,
    phone,
    state,
    postcode,

    -- The initial source record becomes valid from its updated_date.
    updated_date AS effective_from,

    -- Current SCD2 records have no end date.
    NULL AS effective_to,

    -- All initial applicant records are current at initial load.
    TRUE AS is_current

FROM read_csv_auto('source_data/applicants.csv');