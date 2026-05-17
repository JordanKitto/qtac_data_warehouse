-- ============================================================
-- QTAC Data Engineer Assessment
-- Script: 01_create_tables.sql
-- Purpose:
--   Create the Kimball-style warehouse tables used for the
--   assessment.
--
-- Engine:
--   DuckDB
--
-- Model summary:
--   - dim_applicant is modelled as an SCD Type 2 dimension
--     because applicant details can change over time.
--   - dim_course and dim_qualification provide descriptive
--     context for reporting.
--   - fact_preference is the central fact table because the
--     preference / offer outcome represents the core business
--     process.
-- ============================================================


-- ============================================================
-- Reset existing warehouse tables
-- ============================================================
-- Tables are dropped in dependency order.
-- fact_preference is dropped first because it contains foreign
-- keys to dim_applicant and dim_course.
--
-- This makes the script re-runnable during development and
-- testing.
-- ============================================================

DROP TABLE IF EXISTS fact_preference;
DROP TABLE IF EXISTS dim_qualification;
DROP TABLE IF EXISTS dim_course;
DROP TABLE IF EXISTS dim_applicant;


-- ============================================================
-- Dimension: dim_applicant
-- Type:
--   Slowly Changing Dimension Type 2
--
-- Grain:
--   One row per applicant version.
--
-- Key design:
--   applicant_key is the warehouse surrogate key.
--   applicant_id is the natural/source key from the QTAC extract.
--
-- Why SCD2:
--   Applicant details can change over time, such as name, email,
--   phone, state, or postcode. Instead of overwriting the original
--   record, SCD2 preserves historical versions.
--
-- SCD2 columns:
--   effective_from = date this version became valid
--   effective_to   = date this version stopped being valid
--   is_current     = true only for the latest active version
--
-- Notes:
--   date_of_birth is nullable because profiling showed one missing
--   value in the source applicants file.
--
--   phone and postcode are stored as VARCHAR because they are
--   identifiers, not numeric measures. This avoids formatting issues
--   such as leading zero loss.
-- ============================================================

CREATE TABLE dim_applicant (
    applicant_key INTEGER PRIMARY KEY,
    applicant_id INTEGER NOT NULL,

    first_name VARCHAR(50),
    last_name VARCHAR(50),
    date_of_birth DATE,
    email VARCHAR(100),
    phone VARCHAR(30),
    state VARCHAR(10),
    postcode VARCHAR(10),

    effective_from DATE NOT NULL,
    effective_to DATE,
    is_current BOOLEAN NOT NULL
);


-- ============================================================
-- Dimension: dim_course
--
-- Grain:
--   One row per course.
--
-- Key design:
--   course_key is the warehouse surrogate key.
--   course_code is the natural/source key from the course extract.
--
-- Purpose:
--   Stores descriptive course and institution information used
--   when analysing applicant preferences and accepted offers.
--
-- Data cleaning applied during load:
--   - study_mode casing is standardised
--   - csp_available is converted from Y/N to BOOLEAN
--   - active_flag is converted from 1/0 to BOOLEAN
--
-- Notes:
--   atar_cutoff is nullable because profiling identified one
--   missing cutoff in the source data.
-- ============================================================

CREATE TABLE dim_course (
    course_key INTEGER PRIMARY KEY,
    course_code VARCHAR(20) NOT NULL,
    course_name VARCHAR(150),
    institution_code VARCHAR(20),
    institution_name VARCHAR(150),
    campus VARCHAR(100),
    study_mode VARCHAR(50),
    duration_years INTEGER,
    atar_cutoff DOUBLE,
    csp_available BOOLEAN,
    active_flag BOOLEAN
);


-- ============================================================
-- Dimension: dim_qualification
--
-- Grain:
--   One row per applicant qualification.
--
-- Key design:
--   qualification_key is the warehouse surrogate key.
--   qualification_id is the natural/source key from the
--   qualifications extract.
--
-- Relationship note:
--   This table stores applicant_id rather than applicant_key.
--   This keeps the qualification linked to the source applicant
--   identity without forcing it onto one specific SCD2 applicant
--   version.
--
-- Purpose:
--   Provides applicant qualification context for the gold layer,
--   including qualification type and ATAR score where available.
--
-- Data cleaning applied during load:
--   - verified is converted from Y/N to BOOLEAN
--   - text values such as 'NULL' are safely converted to real NULLs
--     for numeric fields such as GPA and ATAR
--
-- Notes:
--   GPA and ATAR are nullable because not every qualification type
--   uses both measures.
-- ============================================================

CREATE TABLE dim_qualification (
    qualification_key INTEGER PRIMARY KEY,
    qualification_id VARCHAR(20) NOT NULL,
    applicant_id INTEGER NOT NULL,

    qualification_type VARCHAR(50),
    institution_name VARCHAR(150),
    year_completed INTEGER,
    gpa DOUBLE,
    atar_score DOUBLE,
    verified BOOLEAN
);


-- ============================================================
-- Fact: fact_preference
--
-- Grain:
--   One row per applicant course preference.
--
-- Business process:
--   This fact table represents the core QTAC application event:
--   an applicant selects a course preference, may receive an offer,
--   and may respond to that offer.
--
-- Key design:
--   preference_key is the warehouse surrogate key.
--   preference_id is the natural/source key from preferences.csv.
--
-- Foreign keys:
--   applicant_key links the fact to the SCD2 applicant dimension.
--   course_key links the fact to the course dimension.
--
-- Source traceability:
--   applicant_id and course_code are also retained in the fact
--   table. These are not the primary warehouse relationships, but
--   they make the fact table easier to audit back to the source CSV.
--
-- Design choice:
--   This assessment links preferences to the current applicant
--   record when loading the fact table. In a production
--   point-in-time model, the fact could instead link to the
--   applicant version valid at the offer or response date.
-- ============================================================

CREATE TABLE fact_preference (
    preference_key INTEGER PRIMARY KEY,
    preference_id VARCHAR(20) NOT NULL,

    applicant_key INTEGER NOT NULL,
    course_key INTEGER NOT NULL,

    applicant_id INTEGER NOT NULL,
    course_code VARCHAR(20) NOT NULL,

    preference_order INTEGER,
    application_year INTEGER,
    offer_status VARCHAR(50),
    offer_date DATE,
    response VARCHAR(50),
    response_date DATE,

    FOREIGN KEY (applicant_key) REFERENCES dim_applicant(applicant_key),
    FOREIGN KEY (course_key) REFERENCES dim_course(course_key)
);