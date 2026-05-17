# File: run_sql.py

import duckdb
from pathlib import Path

DB_PATH = Path("qtac.duckdb")

SQL_FILES = [
    "01_create_tables.sql",
    "02_load_initial_applicants.sql",
    "03_apply_applicant_updates.sql",
    "04_load_courses.sql",
    "05_load_qualifications.sql",
    "06_load_preferences.sql",
    "07_create_gold_output.sql",
    "08_export_tables.sql",
]

with duckdb.connect(DB_PATH) as conn:
    for sql_file in SQL_FILES:
        sql_path = Path("sql") / sql_file
        print(f"Running {sql_path}...")

        sql = sql_path.read_text(encoding="utf-8")
        conn.execute(sql)

        print(f"Completed {sql_path}")

print("All SQL scripts completed successfully.")