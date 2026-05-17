-- ============================================================
-- QTAC Data Engineer Assessment
-- Script: 08_export_tables.sql
-- Purpose:
--   Export the final warehouse and gold layer tables to CSV.
--
-- Context:
--   The assessment asks for CSV exports of:
--     - warehouse layer tables after ingestion
--     - gold layer / information mart output
--
-- Output folder:
--   exports/
--
-- Exported tables:
--   - dim_applicant
--   - dim_course
--   - dim_qualification
--   - fact_preference
--   - gold_accepted_offers
-- ============================================================


-- ============================================================
-- Warehouse layer exports
-- ============================================================
-- These files show the final state of the warehouse tables after:
--   - initial applicant load
--   - applicant update SCD2 processing
--   - course loading
--   - qualification loading
--   - preference fact loading
-- ============================================================

COPY dim_applicant TO 'exports/dim_applicant.csv' (HEADER, DELIMITER ',');
COPY dim_course TO 'exports/dim_course.csv' (HEADER, DELIMITER ',');
COPY dim_qualification TO 'exports/dim_qualification.csv' (HEADER, DELIMITER ',');
COPY fact_preference TO 'exports/fact_preference.csv' (HEADER, DELIMITER ',');


-- ============================================================
-- Gold layer export
-- ============================================================
-- This is the final business-ready accepted-offer output.
--
-- It contains one row per applicant with a selected accepted offer,
-- using the lowest preference_order as the highest preference.
-- ============================================================

COPY gold_accepted_offers TO 'exports/gold_accepted_offers.csv' (HEADER, DELIMITER ',');