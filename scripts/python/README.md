# Scripts

Reference Python scripts for synthetic data generation and validation.

These scripts are documentation artifacts, not production backend code. The production app reads from Supabase PostgreSQL via FastAPI and does not execute these scripts at runtime.

---

## Files

| File | Purpose |
|---|---|
| `generate_synthetic_data_reference.py` | Documents the synthetic data generation approach used to create the dataset |
| `validate_data_quality_reference.py` | Validates CSV files before database import (row counts, duplicates, nulls, FK consistency) |

---

## generate_synthetic_data_reference.py

Documents how the 8 synthetic tables were generated:

- Random seed fixed at 42 for reproducibility
- 100 accounts across FinTech, MarTech, EdTech, HealthTech, LegalTech, SalesTech, HRTech
- Usage volume correlated with customer stage (at-risk accounts have lower usage)
- Score history generated as 12 monthly records per account with directional trend
- Experiments and system logs are independent of the account FK graph

This script documents the logic and design decisions for reproducibility.

---

## validate_data_quality_reference.py

Runs pre-import validation against `data/synthetic/*.csv`:

1. File existence check -- confirms all 8 CSV files are present
2. Row count check -- validates expected counts (100 / 100 / 150 / 38374 / 1200 / 250 / 20 / 500)
3. Primary key integrity -- no nulls or duplicates in ID columns
4. Foreign key consistency -- all account_id values in child tables exist in accounts.csv
5. Critical field null check -- required columns have no missing values

To run:

```bash
cd customer-revenue-intelligence-engine
pip install pandas
python scripts/python/validate_data_quality_reference.py
```

Outputs PASS / WARN / FAIL per check. Exits with code 1 if any check fails.

---

## Source Notes

The original data generation work was developed during the project build process. This folder now contains clean reference scripts that document the synthetic data generation and validation approach used for the project.

The committed sample CSVs in `data/sample/` provide small representative datasets, while the production demo uses the larger synthetic dataset loaded into Supabase PostgreSQL.