# Data

All data in this project is synthetic. No real customer, company, or personal data is included.

---

## Dataset Summary

| Table | Row Count | Description |
|---|---|---|
| `accounts` | 100 | B2B SaaS customer accounts |
| `customer_engagement` | 100 | NPS, support tickets, meetings, email metrics |
| `crm_opportunities` | 150 | CRM pipeline and expansion opportunities |
| `product_usage_events` | 38,374 | Raw product event log |
| `score_history` | 1,200 | Historical health, churn, and expansion scores (12 records per account) |
| `actions` | 250 | GTM action records |
| `experiments` | 20 | A/B experiment outcomes |
| `system_logs` | 500 | Operational pipeline logs |

---

## Folders

### `data/sample/`

Small representative samples (15 rows each) extracted from the full synthetic dataset. These demonstrate the schema and data format without including the full volume.

| File | Rows |
|---|---|
| `accounts_sample.csv` | 15 |
| `customer_engagement_sample.csv` | 15 |
| `crm_opportunities_sample.csv` | 15 |
| `product_usage_events_sample.csv` | 15 |
| `score_history_sample.csv` | 15 |
| `actions_sample.csv` | 15 |
| `experiments_sample.csv` | 20 (full dataset -- small) |
| `system_logs_sample.csv` | 15 |

### `data/synthetic/`

Full synthetic dataset files. Not committed to GitHub due to size (`product_usage_events.csv` is ~6MB). Available locally and imported into Supabase via `deployment/data.sql`.

---

## Full Dataset Import

The full synthetic dataset is stored in `deployment/data.sql` as PostgreSQL INSERT statements.

To import into a PostgreSQL instance:

```bash
psql "postgresql://user:password@host:5432/database" \
  -f deployment/schema_supabase_clean.sql

psql "postgresql://user:password@host:5432/database" \
  -f deployment/data.sql
```

For Supabase: use the direct connection string (port 5432, not the 6543 pooler).

---

## Data Generation

The synthetic dataset was generated using Jupyter notebooks in `notebooks/`. Each notebook corresponds to one table:

| Notebook | Table |
|---|---|
| `01_generate_accounts.ipynb` | accounts |
| `02_generate_product_usage_events.ipynb` | product_usage_events |
| `03_generate_crm_opportunities.ipynb` | crm_opportunities |
| `04_generate_customer_engagement.ipynb` | customer_engagement |
| `05_generate_actions.ipynb` | actions |
| `06_generate_score_history.ipynb` | score_history |
| `07_generate_experiments.ipynb` | experiments |
| `08_generate_system_logs.ipynb` | system_logs |

Reference Python scripts for data generation and validation are in `scripts/python/`.