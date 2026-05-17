# QTAC Data Engineer Technical Assessment

## 1. Overview

This repository contains my solution for the QTAC Data Engineer technical assessment.

The assessment provided source extracts from a tertiary admissions application system and required:

- Data profiling and identification of data quality issues
- A warehouse model design
- SQL logic to load initial and updated applicant records
- SCD Type 2 handling for applicant changes
- Loading of additional entities
- A business-ready gold layer output
- CSV exports of the final warehouse and gold layer tables

I used DuckDB as the SQL engine because it is lightweight, easy to run locally, works well with CSV files, and is suitable for demonstrating SQL-based warehouse transformations without requiring server infrastructure.

---

## 2. Approach Chosen

I chose a Kimball dimensional model with SCD Type 2 handling for applicants.

This approach fits the problem because the data naturally separates into:

- Dimensions that describe business entities, such as applicants, courses, and qualifications
- A fact table that captures the applicant course preference and offer outcome event
- A gold layer output that presents accepted offer information in a business-friendly structure

The main reason for using SCD Type 2 is that applicant details can change over time. For example, an applicant may change state, postcode, name, phone, or email. Instead of overwriting the existing applicant record, SCD Type 2 preserves the previous version and inserts a new current version.

---

## 3. Warehouse Model

The warehouse model contains the following tables:

### `dim_applicant`

Grain: one row per applicant version.

This is an SCD Type 2 dimension.

Key columns:

- `applicant_key`: warehouse surrogate key
- `applicant_id`: source system applicant identifier
- applicant attributes such as name, date of birth, email, phone, state, and postcode
- `effective_from`
- `effective_to`
- `is_current`

SCD Type 2 logic allows multiple rows for the same `applicant_id`, while each version has a unique `applicant_key`.

### `dim_course`

Grain: one row per course.

This stores descriptive course information such as:

- course code
- course name
- institution
- campus
- study mode
- duration
- ATAR cutoff
- CSP availability
- active flag

### `dim_qualification`

Grain: one row per applicant qualification.

This stores applicant qualification details such as:

- qualification type
- institution name
- year completed
- GPA
- ATAR score
- verified flag

### `fact_preference`

Grain: one row per applicant course preference.

This is the central fact table because it captures the main business process:

> An applicant applies for a course preference, may receive an offer, and may accept, decline, or leave the offer pending.

The fact table stores:

- preference ID
- applicant key
- course key
- applicant ID and course code for source traceability
- preference order
- application year
- offer status
- offer date
- response
- response date

---

## 4. Load Sequence

The SQL scripts are designed to be run in this order:

1. `01_create_tables.sql`
2. `02_load_initial_applicants.sql`
3. `03_apply_applicant_updates.sql`
4. `04_load_courses.sql`
5. `05_load_qualifications.sql`
6. `06_load_preferences.sql`
7. `07_create_gold_output.sql`
8. `08_export_tables.sql`

### Initial applicant load

The initial `applicants.csv` file is loaded into `dim_applicant`.

For the initial load:

- `applicant_key` is generated as a warehouse surrogate key
- `effective_from` is populated from the source `updated_date`
- `effective_to` is set to `NULL`
- `is_current` is set to `TRUE`

This creates one current SCD Type 2 row per applicant.

### Applicant update load

The `applicants_update.csv` file is applied using SCD Type 2 logic.

The process is:

1. Stage and deduplicate the update file using `SELECT DISTINCT`
2. Compare staged update rows against current `dim_applicant` records
3. Identify existing applicants with changed tracked attributes
4. Expire old current records for changed applicants
5. Insert new current records for changed applicants
6. Insert brand-new applicants
7. Ignore unchanged applicants

Tracked applicant attributes used for change detection:

- `first_name`
- `last_name`
- `date_of_birth`
- `email`
- `phone`
- `state`
- `postcode`

The update handling produced the following results:

- Applicant `1002`: changed, old row expired and new row inserted
- Applicant `1005`: changed, old row expired and new row inserted
- Applicant `1007`: changed, old row expired and new row inserted
- Applicant `1010`: unchanged, no new row inserted
- Applicant `1016`: new applicant, inserted as current

After the SCD Type 2 update, `dim_applicant` contains:

- 19 total rows
- 16 current rows
- 3 historical rows

---

## 5. Data Quality Findings

The source data contained several intentional data quality issues.

### Duplicate applicant update

`applicants_update.csv` contained one exact duplicate row for applicant `1002`.

Handling:

- The update file was deduplicated in staging before applying SCD Type 2 logic.
- This prevents the same update being processed twice.

Production approach:

- I would land the raw file unchanged with a batch ID and load timestamp.
- Exact duplicates would be identified and removed or quarantined during staging.
- Legitimate multiple updates for the same applicant would be processed in `updated_date` order.

### Missing applicant values

`applicants.csv` contained:

- 1 missing `date_of_birth`
- 1 missing `phone`

Handling:

- These records were retained in the warehouse.
- The missing values were treated as source data quality issues rather than reasons to drop the applicant.

Production approach:

- These fields could be flagged for review depending on business rules.
- If mandatory, records could be quarantined or loaded with an exception status.

### Course data issues

`courses.csv` contained:

- 1 missing `atar_cutoff`
- inconsistent `study_mode` casing, with both `Full-time` and `full-time`

Handling:

- Missing `atar_cutoff` was retained as `NULL`
- `study_mode` was standardised during loading

Production approach:

- Standardised reference data or validation rules should be used for known categorical fields.

### Source flags

Some fields used source-system flag values:

- `csp_available`: `Y` / `N`
- `verified`: `Y` / `N`
- `active_flag`: `1` / `0`

Handling:

- These were converted into boolean fields in the warehouse layer.

### Preference missing values

`preferences.csv` contained missing values in:

- `offer_status`
- `offer_date`
- `response`
- `response_date`

Handling:

- These were retained as nulls.
- Missing offer or response fields may be valid where no offer has been made, no response has been received, or the application remains pending.

### Qualification missing values

`qualifications.csv` contained missing values in:

- `gpa`
- `atar_score`

Handling:

- These were retained as nulls.
- Missing GPA or ATAR is context-dependent because different qualification types use different result measures.

### Orphan qualification record

`qualifications.csv` contained one qualification record for applicant `9999`, but applicant `9999` does not exist in the applicant data.

Handling:

- The record was retained in `dim_qualification` for source traceability.
- It was flagged as an orphan record.
- It naturally does not appear in the gold layer unless it can join to a valid applicant.

Production approach:

- I would quarantine or exception-report orphan records depending on business rules.

### Duplicate accepted business outcome

The preferences data contained two accepted records for applicant `1002` for the same accepted course outcome:

- `P004`
- `P022`

Both referred to applicant `1002`, course `QUT-BS001`, preference order `2`, and response `Accepted`.

Handling:

- Both records were retained in `fact_preference` to preserve source traceability.
- The gold layer ranks accepted offers and keeps only one accepted course per applicant.

---

## 6. Key Assumptions

The following assumptions were made:

- `applicant_id` is the natural key for applicants.
- `course_code` is the natural key for courses.
- `preference_id` is the natural key for preference records.
- `qualification_id` is the natural key for qualification records.
- The lowest `preference_order` represents the highest preference.
- Accepted offers are identified where `response = 'Accepted'`.
- If an applicant has multiple accepted offers, the accepted offer with the lowest `preference_order` is selected.
- If multiple accepted offers have the same `preference_order`, the lowest `preference_id` is used as a deterministic tie-breaker.
- The gold layer joins preferences to the current applicant dimension record.
- In a production point-in-time model, facts could instead be joined to the applicant version valid at the offer or response date.
- Year 12 qualifications are preferred for ATAR reporting where available.
- Missing GPA and ATAR values are allowed because they depend on qualification type.

---

## 7. Gold Layer Output

The gold layer table is called:

`gold_accepted_offers`

It is designed as a business-ready information mart output.

It includes:

- applicant ID
- applicant name
- state
- accepted course code
- accepted course name
- institution name
- qualification type
- ATAR score
- preference order
- offer status
- response
- response date

The logic is:

1. Filter `fact_preference` to accepted responses
2. Rank accepted offers per applicant by:
   - lowest `preference_order`
   - then lowest `preference_id`
3. Keep only the top-ranked accepted offer per applicant
4. Join to the current applicant record
5. Join to course details
6. Join to the best-ranked qualification record

The final gold layer contains:

- 11 rows
- one row per applicant with a selected accepted offer

Applicant `1002` appears once in the gold layer, despite having two accepted preference records in the fact table.

---

## 8. Final Table Outputs

The following final CSV exports are included in the `exports` folder:

### Warehouse layer exports

- `dim_applicant.csv`
- `dim_course.csv`
- `dim_qualification.csv`
- `fact_preference.csv`

### Gold layer export

- `gold_accepted_offers.csv`

Final row counts:

| Table | Row Count |
|---|---:|
| `dim_applicant` | 19 |
| `dim_course` | 14 |
| `dim_qualification` | 17 |
| `fact_preference` | 22 |
| `gold_accepted_offers` | 11 |

---

## 9. Production Considerations

If this were implemented as a production pipeline, I would add:

### Raw landing layer

Raw files would be loaded unchanged into a raw/bronze layer with:

- batch ID
- source file name
- load timestamp
- row hash
- source system metadata

### Data quality framework

I would add validation checks for:

- duplicate business keys
- missing mandatory fields
- invalid dates
- invalid categorical values
- orphan records
- multiple current SCD2 records per applicant
- unexpected nulls
- failed type conversions

### Exception handling

Invalid or suspicious records would be sent to an exception table rather than silently dropped.

### Idempotent loading

The load process would be designed so rerunning the same batch does not create duplicate records.

This could include:

- batch tracking
- merge logic
- row hashes
- natural key constraints
- audit columns

### Point-in-time fact joins

For this assessment, `fact_preference` joins to the current applicant record.

In production, I would consider linking preference facts to the applicant version valid at the time of the event using application, offer, or response dates.

### SCD2 safeguards

I would add checks to ensure:

- only one current row exists per `applicant_id`
- effective date ranges do not overlap
- historical rows have an `effective_to`
- current rows have `effective_to = NULL`

---

## 10. Files Included

```text
source_data/
    applicants.csv
    applicants_update.csv
    courses.csv
    qualifications.csv
    preferences.csv

sql/
    01_create_tables.sql
    02_load_initial_applicants.sql
    03_apply_applicant_updates.sql
    04_load_courses.sql
    05_load_qualifications.sql
    06_load_preferences.sql
    07_create_gold_output.sql
    08_export_tables.sql

notebooks/
    01_data_profiling.ipynb

diagrams/
    source_data_overview.png
    kimball_warehouse_model.png

exports/
    dim_applicant.csv
    dim_course.csv
    dim_qualification.csv
    fact_preference.csv
    gold_accepted_offers.csv

README.md
```

## 11. How to Run

This project was built using DuckDB.

The SQL scripts are stored in the `sql` folder and are intended to be run in the following order:

1. `01_create_tables.sql`
2. `02_load_initial_applicants.sql`
3. `03_apply_applicant_updates.sql`
4. `04_load_courses.sql`
5. `05_load_qualifications.sql`
6. `06_load_preferences.sql`
7. `07_create_gold_output.sql`
8. `08_export_tables.sql`

A simple Python runner, `run_sql.py`, is included to execute the scripts in order:

```bash
python run_sql.py
```

## 12. Summary
This solution demonstrates a Kimball-style warehouse model with SCD Type 2 handling for applicant changes.

The final warehouse tables preserve source traceability while applying appropriate cleaning and transformation logic. The gold layer provides a clean accepted-offer output that a business user could consume directly for reporting or analysis.