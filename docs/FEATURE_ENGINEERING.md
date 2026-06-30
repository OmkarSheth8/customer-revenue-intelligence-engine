# Feature Engineering Design

Raw customer records and product events are not directly useful for revenue decisions. The feature engineering layer converts raw account, product usage, CRM, engagement, support, action, and score history data into account-level business metrics that are used by the scoring engine and action playbook.

---

## Source Data

The project uses synthetic B2B SaaS customer data generated programmatically. Eight base tables feed the feature engineering layer:

| Table | Purpose |
|---|---|
| `core.accounts` | Master account profile: ARR, plan, renewal date, owner, segment, industry |
| `core.product_usage_events` | Raw product event log: every user session, feature access, login, API call |
| `core.customer_engagement` | Aggregated engagement signals: NPS, support tickets, meetings, email metrics |
| `core.crm_opportunities` | CRM pipeline: open opportunities, expansion potential, close dates |
| `core.score_history` | Historical health, churn, and expansion scores per account |
| `core.actions` | GTM action records: status, priority, due dates, overdue counts |
| `core.experiments` | A/B experiment outcomes (not used in feature engineering, used for analysis) |
| `core.system_logs` | Operational pipeline logs (not used in feature engineering) |

---

## Pipeline

```
Raw Account / Usage / CRM / Engagement Data
                     |
                     v
        Aggregate Account-Level Signals
        (SQL GROUP BY, COUNT, FILTER)
                     |
                     v
         Engineer Business Metrics
    (NPS category, support pressure level,
     usage activity score, renewal proximity)
                     |
                     v
     Unified Account Feature Layer
         (core.account_features)
                     |
                     v
         Deterministic Scoring Engine
  (health score, churn risk, expansion score)
                     |
                     v
      Rule-Based Action Classification
   (priority tier, recommended action type,
    owner role, due date, immediate steps)
                     |
                     v
     FastAPI REST Endpoints + React Dashboard
                     |
                     v
      AI Explains the Pre-Computed Plan
```

---

## Feature Engineering Views

### account_usage_features

**Source:** `core.product_usage_events`

Aggregates all product usage events by account to produce:

| Metric | Description |
|---|---|
| `usage_events_last_30_days` | Total events in the last 30 days |
| `usage_events_last_7_days` | Total events in the last 7 days |
| `active_users_last_30_days` | Distinct users active in the last 30 days |
| `active_users_total` | All-time distinct user count |
| `distinct_features_used` | Number of distinct product features accessed |
| `avg_session_duration_minutes` | Average session length |
| `last_product_event_at` | Timestamp of most recent event |
| `days_since_last_product_event` | Days since any product activity |

**Commercial meaning:** Low usage events and declining active users are leading indicators of churn risk. Consistent or growing usage supports health and expansion signals.

---

### account_engagement_features

**Source:** `core.customer_engagement`

Converts raw engagement records into classified signals:

| Metric | Description |
|---|---|
| `days_since_last_touch` | Days since most recent customer interaction |
| `email_reply_rate_percent` | `emails_replied / emails_opened × 100` |
| `meeting_engagement_level` | `high` (>= 2 meetings), `medium` (1), `low` (0) |
| `support_pressure_level` | `high` (>= 8 tickets), `medium` (>= 4), `low` (< 4) |
| `nps_category` | `promoter` (>= 8), `neutral` (>= 5), `detractor` (< 5) |

**Commercial meaning:** High support pressure combined with low NPS and long inactivity signals elevated churn risk. Strong meeting engagement and promoter NPS support retention and expansion.

---

### account_opportunity_features

**Source:** `core.crm_opportunities`

Aggregates open CRM pipeline and expansion signals:

| Metric | Description |
|---|---|
| `open_opportunity_count` | Opportunities not Closed Won or Closed Lost |
| `open_pipeline_value` | Total value of open opportunities |
| `weighted_pipeline_value` | `amount × probability / 100` across open opportunities |
| `next_expected_close_date` | Earliest open opportunity close date |
| `days_since_last_crm_activity` | Days since any CRM activity |
| `expansion_opportunity_count` | Count of expansion or upsell opportunity types |

**Commercial meaning:** Open expansion pipeline and high weighted pipeline value indicate that an account is commercially ready for upsell or cross-sell motion. High `days_since_last_crm_activity` may signal stalled pipeline.

---

### account_score_features

**Source:** `core.score_history`

Returns the most recent score record per account using a window function:

| Metric | Description |
|---|---|
| `latest_health_score` | Most recent health score |
| `latest_churn_score` | Most recent churn risk score |
| `latest_expansion_score` | Most recent expansion score |
| `latest_score_reason` | Plain-language reason from the last scoring run |
| `latest_score_date` | Date of most recent score calculation |

**Commercial meaning:** Score history tracks account trajectory over time. An account declining from healthy to at-risk status (visible in score_history) is a stronger intervention signal than a single point-in-time reading.

---

### account_action_features

**Source:** `core.actions`

Aggregates GTM action status per account:

| Metric | Description |
|---|---|
| `total_action_count` | All actions for the account |
| `active_action_count` | Pending + In Progress actions |
| `overdue_action_count` | Active actions past their due_date |
| `critical_action_count` | Actions with Critical priority |
| `completed_action_count` | Completed actions |
| `next_open_action_due_date` | Earliest due date among open actions |

**Commercial meaning:** Overdue actions and unresolved operational work increase customer risk. High overdue counts can trigger human review flags and contribute to the action discipline component of the churn risk score.

---

### account_features (unified layer)

**Source:** All 5 feature views + `core.accounts`

`core.account_features` joins account profile data with all five feature views using LEFT JOINs (accounts without data in child tables receive safe 0/null defaults via COALESCE).

This view produces one row per account with ~50 columns covering:
- Account identity and commercial context
- Renewal timing (`days_until_renewal`)
- Usage metrics (30-day and 7-day windows)
- Engagement metrics (NPS, support, meetings, email)
- CRM pipeline metrics (pipeline value, expansion count)
- Historical score data (latest health, churn, expansion)
- Action status (overdue, critical, pending counts)

`core.account_features` is the sole input to the scoring engine.

---

## How Features Feed the Scoring Engine

The scoring engine (`core.account_scoring_engine`) maps each account feature to a 0-100 component score, then computes weighted composites:

| Score | Key Inputs | Weight Distribution |
|---|---|---|
| Health | usage, active users, NPS, recency, support, action discipline | See `docs/SCORING_LOGIC.md` |
| Churn Risk | inverse of usage, NPS, support health + renewal proximity + action discipline | See `docs/SCORING_LOGIC.md` |
| Expansion | usage, active users, NPS, pipeline value, expansion signal | See `docs/SCORING_LOGIC.md` |

---

## How Features Feed the Action Playbook

After scoring, the `recommended_actions_engine` and `account_action_playbook` views use raw feature values (not just scores) to generate signal-conditional action content. For example:

- An account with `high_support = true` AND `low_usage = true` receives a different set of immediate next steps than one with only high support.
- Renewal timing (`renewal_imminent`, `renewal_near`) conditions how urgently the playbook frames the recommended next action.
- `overdue_action_count` appears directly in generated action step text.

This conditional branching happens entirely in SQL CASE expressions -- each account's action plan is unique to its specific combination of signals.

---

## AI Guardrail

> **AI does not calculate scores, risk levels, recommended actions, owner assignments, due dates, immediate steps, phase 2 follow-up, success metrics, or escalation guidance.**
>
> **AI receives the deterministic output and explains why the plan was assigned. It cannot modify, override, or regenerate any recommendation.**

---

## Example Account Walkthrough

**Scenario:** A Mid-Market EdTech account with:
- 8 usage events in the last 30 days (very low)
- 7 active users (very low)
- NPS score of 3 (detractor)
- 9 support tickets last 30 days (high pressure)
- 75 days until renewal
- 2 overdue actions

**Feature engineering output:**
- `usage_activity_score` = 20 (< 25 events)
- `active_user_score` = 20 (< 10 users)
- `nps_score_component` = 30 (NPS 3)
- `support_health_score` = 10 (> 7 tickets)
- `action_discipline_score` = 50 (2 overdue)
- `renewal_risk_score` = 60 (75 days out)

**Scoring output:**
- Health score ≈ 25 (Unhealthy)
- Churn risk ≈ 68 (Critical Risk, >= 60)
- Expansion score dampened by 35% due to high churn

**Priority tier:** Tier 1 - Churn Intervention (churn >= 60, renewal > 90 days)

**Recommended action:** Immediate Churn Intervention

**Playbook:** Signal-conditional 5-step plan emphasizing high support pressure and very low active users, with escalation triggers and 30-day success metrics.

**AI layer:** Receives this complete deterministic context and explains in plain language why the churn intervention plan was assigned -- without recalculating any values.