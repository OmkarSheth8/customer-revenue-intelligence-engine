# Data Dictionary

This project uses synthetic B2B SaaS customer data. No real customer or company data is included. All company names, account IDs, and behavioral signals were generated programmatically.

---

## Base Tables

### core.accounts

Master customer account profile. One row per account.

| Column | Type | Description |
|---|---|---|
| `account_id` | varchar(50) | Unique account identifier (UUID) |
| `company_name` | varchar(255) | Company name |
| `industry` | varchar(100) | Industry vertical (e.g., FinTech, MarTech, EdTech) |
| `segment` | varchar(100) | Market segment (e.g., Startup, Mid-Market, Enterprise) |
| `company_size` | integer | Number of employees |
| `annual_recurring_revenue` | numeric(12,2) | Current ARR in USD |
| `plan_type` | varchar(100) | Subscription plan (e.g., Starter, Professional, Enterprise) |
| `customer_stage` | varchar(100) | Lifecycle stage (e.g., Active, At Risk, Healthy, Churned) |
| `account_owner` | varchar(255) | Name of the assigned CSM or AE |
| `contract_start_date` | date | Contract start |
| `renewal_date` | date | Contract renewal date |
| `created_at` | timestamp | Record creation timestamp |
| `updated_at` | timestamp | Last update timestamp |

**Row count:** 100

---

### core.product_usage_events

Raw product usage event log. One row per event.

| Column | Type | Description |
|---|---|---|
| `event_id` | varchar(50) | Unique event ID (UUID) |
| `account_id` | varchar(50) | FK to core.accounts |
| `user_id` | varchar(100) | Synthetic user identifier |
| `event_type` | varchar(100) | Event category (e.g., Login, Report Created, Dashboard Viewed, API Call, Integration Connected) |
| `feature_name` | varchar(150) | Product feature used (e.g., Dashboard, Reports, Settings) |
| `session_duration_minutes` | numeric(10,2) | Session length in minutes |
| `event_timestamp` | timestamp | When the event occurred |

**Row count:** 38,374

---

### core.customer_engagement

Customer engagement and satisfaction signals. One row per account (most recent record).

| Column | Type | Description |
|---|---|---|
| `engagement_id` | varchar(50) | Unique record ID (UUID) |
| `account_id` | varchar(50) | FK to core.accounts |
| `emails_opened` | integer | Number of emails opened |
| `emails_replied` | integer | Number of emails replied to |
| `meetings_last_30_days` | integer | Meetings held in the last 30 days |
| `support_tickets_last_30_days` | integer | Support tickets opened in the last 30 days |
| `nps_score` | integer | Net Promoter Score (0-10) |
| `last_touch_date` | date | Most recent customer interaction date |

**Row count:** 100

---

### core.crm_opportunities

CRM pipeline and commercial opportunity data. Multiple opportunities per account.

| Column | Type | Description |
|---|---|---|
| `opportunity_id` | varchar(50) | Unique opportunity ID (UUID) |
| `account_id` | varchar(50) | FK to core.accounts |
| `opportunity_type` | varchar(100) | Type (Renewal, Expansion, Upsell, Cross-sell) |
| `pipeline_stage` | varchar(100) | CRM stage (Prospecting, Qualification, Proposal, Negotiation, Closed Won, Closed Lost) |
| `amount` | numeric(12,2) | Opportunity value in USD |
| `probability` | integer | Close probability as a percentage (0-100) |
| `created_date` | date | Opportunity creation date |
| `expected_close_date` | date | Expected close date |
| `last_activity_date` | date | Most recent CRM activity |

**Row count:** 150

---

### core.score_history

Historical scoring records. Multiple rows per account over time.

| Column | Type | Description |
|---|---|---|
| `score_id` | varchar(50) | Unique score record ID (UUID) |
| `account_id` | varchar(50) | FK to core.accounts |
| `health_score` | numeric(5,2) | Health score at time of calculation (0-100) |
| `churn_score` | numeric(5,2) | Churn risk score at time of calculation (0-100) |
| `expansion_score` | numeric(5,2) | Expansion score at time of calculation (0-100) |
| `score_reason` | text | Plain-language summary of scoring rationale |
| `calculated_at` | date | Date scores were calculated |

**Row count:** 1,200 (12 historical records per account)

---

### core.actions

GTM action tracking. Multiple actions per account.

| Column | Type | Description |
|---|---|---|
| `action_id` | varchar(50) | Unique action ID (UUID) |
| `account_id` | varchar(50) | FK to core.accounts |
| `recommended_action` | text | Description of the recommended action |
| `assigned_to` | varchar(255) | Name of person assigned |
| `priority` | varchar(50) | Priority level (Critical, High, Medium, Low) |
| `status` | varchar(50) | Status (Pending, In Progress, Completed, Dismissed) |
| `due_date` | date | Action due date |
| `completed_at` | timestamp | Completion timestamp (null if not complete) |
| `outcome` | text | Outcome description (null if not complete) |
| `created_at` | timestamp | When the action was created |

**Row count:** 250

---

### core.experiments

GTM experiment outcomes. Independent of the accounts FK graph.

| Column | Type | Description |
|---|---|---|
| `experiment_id` | varchar(50) | Unique experiment ID (UUID) |
| `experiment_name` | varchar(255) | Name of the experiment |
| `hypothesis` | text | The experiment hypothesis |
| `target_accounts` | integer | Number of accounts targeted |
| `success_metric` | varchar(255) | Metric used to evaluate success |
| `result` | text | Experiment outcome narrative |
| `decision` | varchar(100) | Decision taken (e.g., Scale, Stop, Continue) |
| `created_at` | timestamp | Experiment creation timestamp |

**Row count:** 20

---

### core.system_logs

Operational pipeline and system event log. Independent of the accounts FK graph.

| Column | Type | Description |
|---|---|---|
| `log_id` | varchar(50) | Unique log ID (UUID) |
| `log_type` | varchar(100) | Log category (e.g., Export, Validation, AI Generation) |
| `component` | varchar(100) | System component (e.g., Data Ingestion, Monitoring, API) |
| `status` | varchar(100) | Outcome (Success, Failed, Warning) |
| `message` | text | Log message |
| `created_at` | timestamp | Log timestamp |

**Row count:** 500

---

## Engineered Views

Views derived from base tables. Not importable directly -- they are created by the SQL schema and read live from base table data.

| View | Description |
|---|---|
| `account_usage_features` | Usage event aggregates per account (last 7/30 days, distinct users, features, session duration) |
| `account_engagement_features` | Engagement metrics per account (NPS category, support pressure level, email reply rate, days since last touch) |
| `account_opportunity_features` | CRM opportunity aggregates (open pipeline value, weighted pipeline, expansion opportunity count) |
| `account_score_features` | Most recent score per account (window function selecting max calculated_at) |
| `account_action_features` | Action status aggregates per account (overdue count, critical count, pending count) |
| `account_features` | Unified account feature layer joining all 5 views + accounts (input to scoring engine) |
| `account_scoring_engine` | Base scoring: health, churn risk, expansion scores + v1 risk levels and priority tiers |
| `account_scoring_engine_v2` | Adjusted risk thresholds: Critical >= 60, High >= 50 |
| `account_scoring_engine_v3` | Expanded 10-tier priority logic including renewal + expansion combinations |
| `recommended_actions_engine` | Maps each priority tier to action type, priority, owner role, due date, and reason |
| `account_action_playbook` | Signal-conditional 5-step immediate actions, phase 2 follow-up, success metrics, and escalation guidance |
| `account_intelligence_view` | Production view: joins recommended_actions_engine + account_action_playbook + adds motion, review flags, AI context |
| `dashboard_kpis` | Single-row portfolio summary (total accounts, ARR at risk, critical risk count, expansion pipeline) |
| `dashboard_risk_summary` | Risk level distribution with ARR breakdown |
| `dashboard_action_summary` | Action type distribution grouped by priority |
| `dashboard_owner_workload` | Account and action counts per owner role |