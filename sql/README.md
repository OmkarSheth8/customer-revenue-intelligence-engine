# SQL Layer

This folder contains the database logic behind the Customer Revenue Intelligence Engine, split into readable layers.

The production database is Supabase PostgreSQL. The full importable schema is at `deployment/schema_supabase_clean.sql`. The files here document the logic in readable, layered form.

---

## Files

| File | Contents |
|---|---|
| `01_schema.sql` | Base tables (8), primary keys, foreign key constraints (5), indexes (14) |
| `02_feature_engineering_views.sql` | 5 feature views + unified `account_features` input layer |
| `03_scoring_engine.sql` | 3-version deterministic scoring engine (health, churn risk, expansion) |
| `04_action_playbook.sql` | Recommended actions engine + structured action playbook view |
| `05_dashboard_views.sql` | 4 aggregated dashboard summary views |
| `06_validation_queries.sql` | Row count checks, NULL checks, score range checks, sample queries |

---

## Layer Descriptions

### 1. Schema (`01_schema.sql`)

Eight base tables representing the full B2B SaaS customer data model:

- `core.accounts` — master account profile
- `core.product_usage_events` — raw product event log (~38K rows)
- `core.customer_engagement` — NPS, support tickets, meetings, email metrics
- `core.crm_opportunities` — sales pipeline and expansion opportunities
- `core.score_history` — historical health, churn, and expansion scores
- `core.actions` — GTM action tracking
- `core.experiments` — A/B experiment outcomes
- `core.system_logs` — operational pipeline logs

All child tables reference `core.accounts(account_id)` with ON DELETE CASCADE.

---

### 2. Feature Engineering (`02_feature_engineering_views.sql`)

Converts raw table data into account-level business metrics:

| View | Source | Key Metrics |
|---|---|---|
| `account_usage_features` | product_usage_events | events last 30d, active users, distinct features, session duration |
| `account_engagement_features` | customer_engagement | NPS category, support pressure level, email reply rate, days since touch |
| `account_opportunity_features` | crm_opportunities | open pipeline value, weighted pipeline, expansion opportunity count |
| `account_score_features` | score_history | latest health / churn / expansion scores (window function, most recent row) |
| `account_action_features` | actions | overdue count, critical count, pending count, next due date |
| `account_features` | all 5 views + accounts | unified 50-column feature record per account |

`account_features` is the sole input to the scoring engine.

---

### 3. Scoring Engine (`03_scoring_engine.sql`)

Three-version deterministic scoring:

- **v1** (`account_scoring_engine`): Base scores + v1 risk thresholds (Critical >= 75)
- **v2** (`account_scoring_engine_v2`): Adjusted thresholds (Critical >= 60, High >= 50)
- **v3** (`account_scoring_engine_v3`): Expanded 10-tier priority classification with renewal + expansion combos

The production app uses `risk_level_v2`, `expansion_level_v2`, and `customer_priority_tier_v3` from v3.

**Score formulas (all deterministic CASE logic):**

| Score | Formula |
|---|---|
| Health | usage 25% + active_users 20% + NPS 20% + recency 15% + support 10% + actions 10% |
| Churn Risk | inverse signals + renewal proximity weighted equally |
| Expansion | usage 25% + active_users 20% + NPS 20% + pipeline 20% + expansion_signal 15% (dampened if high churn) |

---

### 4. Action Playbook (`04_action_playbook.sql`)

Two views:

- **`recommended_actions_engine`**: Maps each account's priority tier to a specific action type, priority, owner role, due date, and plain-language reason.
- **`account_action_playbook`**: Expands each action type into signal-conditional immediate steps, phase 2 follow-up, success metrics, and escalation guidance (all in SQL CASE logic).
- **`account_intelligence_view`**: Final production view joining recommended_actions_engine + account_action_playbook. This is what the API reads.

The 11 action types:

| Action Type | Priority |
|---|---|
| Executive Renewal Save Plan | Critical |
| Immediate Churn Intervention | Critical |
| Renewal Risk Review | High |
| CSM Risk Review | High |
| Renewal Readiness Review | High |
| Renewal and Expansion Review | High |
| Expansion Discovery | High |
| Renewal Monitoring | Medium |
| Expansion Nurture | Medium |
| Maintain Account Health | Medium |
| Monitor Account | Low |

---

### 5. Dashboard Views (`05_dashboard_views.sql`)

Aggregated summary views queried by the FastAPI backend:

| View | API Endpoint |
|---|---|
| `dashboard_kpis` | `GET /dashboard/kpis` |
| `dashboard_risk_summary` | `GET /dashboard/risk-summary` |
| `dashboard_action_summary` | `GET /dashboard/action-summary` |
| `dashboard_owner_workload` | `GET /dashboard/owner-workload` |

---

### 6. Validation Queries (`06_validation_queries.sql`)

Read-only checks for post-import validation:

- Row counts for all 8 base tables
- Row counts for intelligence and playbook views
- Duplicate account check
- NULL checks on required playbook fields
- Score range sanity checks (0-100)
- Dashboard KPI output
- Sample high-risk, expansion-ready, and human-review accounts
- Owner workload and motion distribution