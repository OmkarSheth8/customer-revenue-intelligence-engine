"""
Reference validation script for checking dataset shape, row counts, missing values,
duplicate keys, and foreign-key style consistency before database import.

This file is intended for documentation and reproducibility support.
It is not part of the production backend runtime.

The production app reads from Supabase PostgreSQL via FastAPI.
Run this script against the CSV files in data/synthetic/ before importing.
"""

import os
import sys

try:
    import pandas as pd
except ImportError:
    print("pandas is required: pip install pandas")
    sys.exit(1)

# ============================================================
# Configuration
# ============================================================

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "data", "synthetic")

EXPECTED_FILES = {
    "accounts.csv":               100,
    "customer_engagement.csv":    100,
    "crm_opportunities.csv":      150,
    "product_usage_events.csv": 38374,
    "score_history.csv":         1200,
    "actions.csv":                250,
    "experiments.csv":             20,
    "system_logs.csv":            500,
}

# Primary keys for each file
PRIMARY_KEYS = {
    "accounts.csv":              "account_id",
    "customer_engagement.csv":   "engagement_id",
    "crm_opportunities.csv":     "opportunity_id",
    "product_usage_events.csv":  "event_id",
    "score_history.csv":         "score_id",
    "actions.csv":               "action_id",
    "experiments.csv":           "experiment_id",
    "system_logs.csv":           "log_id",
}

# Columns that should reference account_id
ACCOUNT_FK_FILES = [
    "customer_engagement.csv",
    "crm_opportunities.csv",
    "product_usage_events.csv",
    "score_history.csv",
    "actions.csv",
]


# ============================================================
# Validation functions
# ============================================================

def check_file_exists(filename):
    path = os.path.join(DATA_DIR, filename)
    exists = os.path.isfile(path)
    print(f"  {'OK' if exists else 'MISSING'} {filename}")
    return exists


def check_row_count(df, filename, expected):
    actual = len(df)
    status = "OK" if actual == expected else f"WARN (expected {expected}, got {actual})"
    print(f"  {status} {filename}: {actual} rows")
    return actual == expected


def check_primary_key(df, filename, pk_col):
    if pk_col not in df.columns:
        print(f"  MISSING_COL {filename}: column '{pk_col}' not found")
        return False
    null_count = df[pk_col].isna().sum()
    dup_count = df[pk_col].duplicated().sum()
    if null_count > 0:
        print(f"  NULL_PK {filename}: {null_count} null values in '{pk_col}'")
    if dup_count > 0:
        print(f"  DUP_PK {filename}: {dup_count} duplicate values in '{pk_col}'")
    if null_count == 0 and dup_count == 0:
        print(f"  OK {filename}: primary key '{pk_col}' is clean")
    return null_count == 0 and dup_count == 0


def check_foreign_key(child_df, child_file, parent_df, fk_col="account_id"):
    if fk_col not in child_df.columns:
        print(f"  MISSING_COL {child_file}: column '{fk_col}' not found")
        return False
    if fk_col not in parent_df.columns:
        print(f"  MISSING_COL accounts.csv: column '{fk_col}' not found")
        return False
    valid_ids = set(parent_df[fk_col].dropna())
    child_ids = set(child_df[fk_col].dropna())
    orphans = child_ids - valid_ids
    if orphans:
        print(f"  FK_FAIL {child_file}: {len(orphans)} account_id values not in accounts.csv")
        return False
    print(f"  OK {child_file}: all account_id values exist in accounts.csv")
    return True


def check_null_critical_fields(df, filename, critical_cols):
    issues = []
    for col in critical_cols:
        if col in df.columns:
            null_count = df[col].isna().sum()
            if null_count > 0:
                issues.append(f"'{col}' has {null_count} nulls")
    if issues:
        print(f"  NULL_FIELDS {filename}: {'; '.join(issues)}")
    else:
        print(f"  OK {filename}: no nulls in critical fields")


# ============================================================
# Main validation routine
# ============================================================

def main():
    results = {"pass": 0, "fail": 0, "warn": 0}

    print("\n=== 1. File existence check ===")
    dataframes = {}
    for filename in EXPECTED_FILES:
        if check_file_exists(filename):
            path = os.path.join(DATA_DIR, filename)
            dataframes[filename] = pd.read_csv(path)
            results["pass"] += 1
        else:
            results["fail"] += 1

    print("\n=== 2. Row count check ===")
    for filename, expected in EXPECTED_FILES.items():
        if filename in dataframes:
            ok = check_row_count(dataframes[filename], filename, expected)
            results["pass" if ok else "warn"] += 1

    print("\n=== 3. Primary key integrity ===")
    for filename, pk_col in PRIMARY_KEYS.items():
        if filename in dataframes:
            ok = check_primary_key(dataframes[filename], filename, pk_col)
            results["pass" if ok else "fail"] += 1

    print("\n=== 4. Foreign key consistency (account_id references) ===")
    if "accounts.csv" in dataframes:
        accounts_df = dataframes["accounts.csv"]
        for filename in ACCOUNT_FK_FILES:
            if filename in dataframes:
                ok = check_foreign_key(dataframes[filename], filename, accounts_df)
                results["pass" if ok else "fail"] += 1

    print("\n=== 5. Critical field null check ===")
    critical_fields = {
        "accounts.csv":            ["account_id", "company_name", "annual_recurring_revenue", "renewal_date"],
        "customer_engagement.csv": ["account_id", "nps_score", "support_tickets_last_30_days"],
        "score_history.csv":       ["account_id", "health_score", "churn_score", "expansion_score", "calculated_at"],
        "actions.csv":             ["account_id", "priority", "status"],
    }
    for filename, cols in critical_fields.items():
        if filename in dataframes:
            check_null_critical_fields(dataframes[filename], filename, cols)

    print("\n=== Summary ===")
    print(f"  PASS:  {results['pass']}")
    print(f"  WARN:  {results['warn']}")
    print(f"  FAIL:  {results['fail']}")

    if results["fail"] > 0:
        print("\nValidation FAILED -- check output above before importing.")
        sys.exit(1)
    else:
        print("\nValidation PASSED -- dataset is ready for import.")


if __name__ == "__main__":
    main()