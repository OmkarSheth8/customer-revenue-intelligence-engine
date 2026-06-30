# Scoring Logic

The scoring layer converts engineered account features into customer health, churn risk, expansion readiness, priority tier, business motion, and recommended actions. Every classification is produced by deterministic SQL CASE logic -- no ML, no AI inference.

---

## Inputs

The scoring engine reads from `core.account_features`, the unified feature view that joins usage, engagement, CRM, score history, and action signals into one account-level record.

Key inputs used by the scoring formulas:

| Input | Source |
|---|---|
| `usage_events_last_30_days` | product_usage_events (last 30 days) |
| `active_users_last_30_days` | product_usage_events (distinct users, last 30 days) |
| `nps_score` | customer_engagement |
| `support_tickets_last_30_days` | customer_engagement |
| `days_since_last_touch` | customer_engagement |
| `overdue_action_count` | actions (status = Pending or In Progress, due_date past) |
| `days_until_renewal` | accounts.renewal_date - reference date |
| `open_pipeline_value` | crm_opportunities (open stages only) |
| `expansion_opportunity_count` | crm_opportunities (expansion or upsell types) |

---

## Component Score Mappings

Before computing final scores, each raw signal is mapped to a 0-100 integer component score:

**Usage activity (usage_events_last_30_days):**
- >= 120 events → 100
- >= 80 → 85
- >= 50 → 70
- >= 25 → 45
- < 25 → 20

**Active users (active_users_last_30_days):**
- >= 60 → 100
- >= 35 → 85
- >= 20 → 70
- >= 10 → 45
- < 10 → 20

**NPS:**
- >= 9 → 100
- >= 7 → 80
- >= 5 → 55
- >= 3 → 30
- < 3 → 10

**Engagement recency (days_since_last_touch):**
- <= 7 days → 100
- <= 14 → 80
- <= 30 → 60
- <= 60 → 35
- > 60 → 10

**Support health (support_tickets_last_30_days):**
- 0 tickets → 100
- <= 2 → 85
- <= 4 → 65
- <= 7 → 35
- > 7 → 10

**Action discipline (overdue_action_count):**
- 0 overdue → 100
- 1 → 75
- 2 → 50
- <= 4 → 25
- > 4 → 5

**Renewal risk (days_until_renewal):**
- <= 30 days → 100 (high renewal risk)
- <= 60 → 80
- <= 90 → 60
- <= 180 → 35
- > 180 → 15

**Pipeline value (open_pipeline_value):**
- >= $250K → 100
- >= $100K → 80
- >= $50K → 60
- > $0 → 40
- $0 → 10

**Expansion signal (expansion_opportunity_count):**
- >= 3 → 100
- 2 → 80
- 1 → 55
- 0 → 10

---

## Health Score

Represents overall account strength. Range: 0-100 (higher = healthier).

**Formula:**

```
health_score = (usage_activity × 0.25)
             + (active_user    × 0.20)
             + (nps            × 0.20)
             + (recency        × 0.15)
             + (support_health × 0.10)
             + (action_discipline × 0.10)
```

**Health status labels** (used in the intelligence view):

| Score | Label |
|---|---|
| >= 80 | Healthy |
| >= 60 | Stable |
| >= 40 | Weak |
| < 40 | Unhealthy |

---

## Churn Risk Score

Represents likelihood that the account needs retention attention. Range: 0-100 (higher = more at risk).

**Formula:**

```
churn_score = ((100 - usage_activity) × 0.20)
            + ((100 - active_user)    × 0.15)
            + ((100 - nps)            × 0.20)
            + ((100 - support_health) × 0.15)
            + (renewal_risk           × 0.15)
            + ((100 - action_discipline) × 0.15)
```

Renewal proximity contributes directly to churn risk -- accounts close to renewal with poor signals score higher.

**Churn status labels** (used in the intelligence view):

| Score | Label |
|---|---|
| >= 60 | Immediate Risk |
| >= 50 | Elevated Risk |
| >= 40 | Watch |
| < 40 | Normal |

---

## Expansion Score

Represents commercial readiness for upsell or cross-sell. Range: 0-100 (higher = stronger expansion signal).

**Formula (raw expansion):**

```
raw_expansion = (usage_activity  × 0.25)
              + (active_user     × 0.20)
              + (nps             × 0.20)
              + (pipeline_value  × 0.20)
              + (expansion_signal × 0.15)
```

**High churn dampening:**

```
if churn_risk >= 70: computed_expansion = raw_expansion × 0.65
if churn_risk >= 55: computed_expansion = raw_expansion × 0.85
else:                computed_expansion = raw_expansion
```

Accounts with high churn risk have their expansion score dampened -- expansion discovery is deprioritized until the account is stabilized.

**Expansion status labels** (used in the intelligence view):

| Score | Label |
|---|---|
| >= 75 | Expansion Ready |
| >= 50 | Expansion Possible |
| < 50 | No Clear Expansion Signal |

---

## Risk Level

Derived from `computed_churn_risk_score` using v2 thresholds (the active version in production):

| Churn Score | Risk Level |
|---|---|
| >= 60 | Critical Risk |
| >= 50 | High Risk |
| >= 40 | Moderate Risk |
| < 40 | Low Risk |

---

## Expansion Level

Derived from `computed_expansion_score`:

| Expansion Score | Level |
|---|---|
| >= 75 | High Expansion |
| >= 50 | Medium Expansion |
| < 50 | Low Expansion |

---

## Customer Priority Tier

The active priority tier logic (v3) maps churn risk, renewal timing, and expansion scores into 10 named tiers:

| Tier | Condition |
|---|---|
| Tier 1 - Save Immediately | churn >= 60 AND renewal <= 90 days |
| Tier 1 - Churn Intervention | churn >= 60 |
| Tier 2 - Renewal Risk Watch | churn >= 50 AND renewal <= 120 days |
| Tier 2 - Churn Risk Watch | churn >= 50 |
| Tier 2 - Renewal Review | churn >= 40 AND renewal <= 30 days |
| Tier 2 - Renewal Expansion Review | expansion >= 75 AND renewal <= 60 days AND churn < 50 |
| Tier 2 - Expansion Ready | expansion >= 75 AND churn < 50 |
| Tier 3 - Renewal Monitor | churn >= 40 AND renewal <= 60 days |
| Tier 3 - Expansion Nurture | expansion >= 60 AND churn < 55 |
| Tier 3 - Maintain | health >= 65 AND churn < 40 |
| Tier 4 - Monitor | all others |

---

## Primary Business Motion

Derived from the priority tier in the intelligence view:

| Priority Tier Pattern | Business Motion |
|---|---|
| Tier 1% | Save |
| %Churn% | Recover |
| %Renewal% | Renewal |
| %Expansion% | Expand |
| %Maintain% | Maintain |
| All others | Monitor |

---

## Recommended Actions

Each priority tier maps to a specific action type. The 11 action types and their priorities:

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

## Human Review Logic

An account is flagged `needs_human_review = true` when any of the following conditions are met:

| Condition | Rule |
|---|---|
| Action priority is Critical | `recommended_action_priority = 'Critical'` |
| Account has Critical Risk | `risk_level = 'Critical Risk'` |
| Account has High Risk | `risk_level = 'High Risk'` |
| Renewal within 30 days + churn >= 40 | `days_until_renewal <= 30 AND churn_risk >= 40` |
| Renewal within 30 days (any risk) | `days_until_renewal <= 30` |
| Renewal within 60 days + churn >= 40 | `days_until_renewal <= 60 AND churn_risk >= 40` |
| 3+ overdue actions | `overdue_action_count >= 3` |

A plain-language `human_review_reason` is computed alongside the flag.

---

## AI Explanation Layer

> **AI does not calculate scores, risk levels, recommended actions, owner assignments, due dates, immediate steps, phase 2 follow-up, success metrics, or escalation guidance.**
>
> **AI receives the fully computed deterministic output and explains why the plan was assigned based on the signals present. It cannot modify the recommendation.**

The AI explanation endpoint (`POST /accounts/{id}/ai-explanation`) sends the account's deterministic context (scores, classification, behavioral signals, and the full playbook) to OpenAI `gpt-4o-mini` and returns a natural language explanation.