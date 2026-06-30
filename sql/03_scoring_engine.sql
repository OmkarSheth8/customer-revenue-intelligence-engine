-- ============================================================
-- 03_scoring_engine.sql
-- Customer Revenue Intelligence Engine
--
-- Deterministic scoring layer: converts account features into
-- health score, churn risk score, expansion score, risk level,
-- expansion level, and customer priority tier.
--
-- No ML, no AI. Every score derives from CASE-based SQL rules.
--
-- Views (in dependency order):
--   account_scoring_engine     (v1 -- base scoring)
--   account_scoring_engine_v2  (v2 -- adjusted risk thresholds)
--   account_scoring_engine_v3  (v3 -- expanded priority tier logic)
-- ============================================================


-- ------------------------------------------------------------
-- v1: Base scoring engine
--
-- Health score formula (weights):
--   usage_activity    25%
--   active_users      20%
--   nps               20%
--   engagement_recency 15%
--   support_health    10%
--   action_discipline 10%
--
-- Churn risk formula (weights):
--   (100 - usage_activity)    20%
--   (100 - active_users)      15%
--   (100 - nps)               20%
--   (100 - support_health)    15%
--   renewal_risk              15%
--   (100 - action_discipline) 15%
--
-- Expansion score formula (weights):
--   usage_activity  25%
--   active_users    20%
--   nps             20%
--   pipeline_value  20%
--   expansion_signal 15%
--   (dampened by 35% if churn risk >= 70, 15% if churn risk >= 55)
--
-- Risk levels (v1):
--   Critical Risk  >= 75 churn risk
--   High Risk      >= 60
--   Moderate Risk  >= 40
--   Low Risk       < 40
-- ------------------------------------------------------------
CREATE VIEW core.account_scoring_engine AS
 WITH component_scores AS (
         SELECT af.account_id,
            af.company_name,
            af.industry,
            af.segment,
            af.company_size,
            af.annual_recurring_revenue,
            af.plan_type,
            af.customer_stage,
            af.account_owner,
            af.renewal_date,
            af.days_until_renewal,
            af.usage_events_last_30_days,
            af.active_users_last_30_days,
            af.support_tickets_last_30_days,
            af.nps_score,
            af.days_since_last_touch,
            af.overdue_action_count,
            af.open_pipeline_value,
            af.expansion_opportunity_count,
            af.latest_health_score,
            af.latest_churn_score,
            af.latest_expansion_score,
            af.latest_score_reason,
            af.latest_score_date,
                CASE
                    WHEN (af.usage_events_last_30_days >= 120) THEN 100
                    WHEN (af.usage_events_last_30_days >= 80) THEN 85
                    WHEN (af.usage_events_last_30_days >= 50) THEN 70
                    WHEN (af.usage_events_last_30_days >= 25) THEN 45
                    ELSE 20
                END AS usage_activity_score,
                CASE
                    WHEN (af.active_users_last_30_days >= 60) THEN 100
                    WHEN (af.active_users_last_30_days >= 35) THEN 85
                    WHEN (af.active_users_last_30_days >= 20) THEN 70
                    WHEN (af.active_users_last_30_days >= 10) THEN 45
                    ELSE 20
                END AS active_user_score,
                CASE
                    WHEN (af.nps_score >= 9) THEN 100
                    WHEN (af.nps_score >= 7) THEN 80
                    WHEN (af.nps_score >= 5) THEN 55
                    WHEN (af.nps_score >= 3) THEN 30
                    ELSE 10
                END AS nps_score_component,
                CASE
                    WHEN (af.days_since_last_touch <= 7) THEN 100
                    WHEN (af.days_since_last_touch <= 14) THEN 80
                    WHEN (af.days_since_last_touch <= 30) THEN 60
                    WHEN (af.days_since_last_touch <= 60) THEN 35
                    ELSE 10
                END AS engagement_recency_score,
                CASE
                    WHEN (af.support_tickets_last_30_days = 0) THEN 100
                    WHEN (af.support_tickets_last_30_days <= 2) THEN 85
                    WHEN (af.support_tickets_last_30_days <= 4) THEN 65
                    WHEN (af.support_tickets_last_30_days <= 7) THEN 35
                    ELSE 10
                END AS support_health_score,
                CASE
                    WHEN (af.overdue_action_count = 0) THEN 100
                    WHEN (af.overdue_action_count = 1) THEN 75
                    WHEN (af.overdue_action_count = 2) THEN 50
                    WHEN (af.overdue_action_count <= 4) THEN 25
                    ELSE 5
                END AS action_discipline_score,
                CASE
                    WHEN (af.days_until_renewal <= 30) THEN 100
                    WHEN (af.days_until_renewal <= 60) THEN 80
                    WHEN (af.days_until_renewal <= 90) THEN 60
                    WHEN (af.days_until_renewal <= 180) THEN 35
                    ELSE 15
                END AS renewal_risk_score,
                CASE
                    WHEN (af.open_pipeline_value >= (250000)::numeric) THEN 100
                    WHEN (af.open_pipeline_value >= (100000)::numeric) THEN 80
                    WHEN (af.open_pipeline_value >= (50000)::numeric) THEN 60
                    WHEN (af.open_pipeline_value > (0)::numeric) THEN 40
                    ELSE 10
                END AS pipeline_value_score,
                CASE
                    WHEN (af.expansion_opportunity_count >= 3) THEN 100
                    WHEN (af.expansion_opportunity_count = 2) THEN 80
                    WHEN (af.expansion_opportunity_count = 1) THEN 55
                    ELSE 10
                END AS expansion_signal_score
           FROM core.account_features af
        ), computed_scores AS (
         SELECT cs.account_id,
            cs.company_name,
            cs.industry,
            cs.segment,
            cs.company_size,
            cs.annual_recurring_revenue,
            cs.plan_type,
            cs.customer_stage,
            cs.account_owner,
            cs.renewal_date,
            cs.days_until_renewal,
            cs.usage_events_last_30_days,
            cs.active_users_last_30_days,
            cs.support_tickets_last_30_days,
            cs.nps_score,
            cs.days_since_last_touch,
            cs.overdue_action_count,
            cs.open_pipeline_value,
            cs.expansion_opportunity_count,
            cs.latest_health_score,
            cs.latest_churn_score,
            cs.latest_expansion_score,
            cs.latest_score_reason,
            cs.latest_score_date,
            cs.usage_activity_score,
            cs.active_user_score,
            cs.nps_score_component,
            cs.engagement_recency_score,
            cs.support_health_score,
            cs.action_discipline_score,
            cs.renewal_risk_score,
            cs.pipeline_value_score,
            cs.expansion_signal_score,
            round((((((((cs.usage_activity_score)::numeric * 0.25) + ((cs.active_user_score)::numeric * 0.20)) + ((cs.nps_score_component)::numeric * 0.20)) + ((cs.engagement_recency_score)::numeric * 0.15)) + ((cs.support_health_score)::numeric * 0.10)) + ((cs.action_discipline_score)::numeric * 0.10)), 2) AS computed_health_score,
            round(((((((((100 - cs.usage_activity_score))::numeric * 0.20) + (((100 - cs.active_user_score))::numeric * 0.15)) + (((100 - cs.nps_score_component))::numeric * 0.20)) + (((100 - cs.support_health_score))::numeric * 0.15)) + ((cs.renewal_risk_score)::numeric * 0.15)) + (((100 - cs.action_discipline_score))::numeric * 0.15)), 2) AS computed_churn_risk_score,
            round(((((((cs.usage_activity_score)::numeric * 0.25) + ((cs.active_user_score)::numeric * 0.20)) + ((cs.nps_score_component)::numeric * 0.20)) + ((cs.pipeline_value_score)::numeric * 0.20)) + ((cs.expansion_signal_score)::numeric * 0.15)), 2) AS raw_expansion_score
           FROM component_scores cs
        ), final_scores AS (
         SELECT computed_scores.account_id,
            computed_scores.company_name,
            computed_scores.industry,
            computed_scores.segment,
            computed_scores.company_size,
            computed_scores.annual_recurring_revenue,
            computed_scores.plan_type,
            computed_scores.customer_stage,
            computed_scores.account_owner,
            computed_scores.renewal_date,
            computed_scores.days_until_renewal,
            computed_scores.usage_events_last_30_days,
            computed_scores.active_users_last_30_days,
            computed_scores.support_tickets_last_30_days,
            computed_scores.nps_score,
            computed_scores.days_since_last_touch,
            computed_scores.overdue_action_count,
            computed_scores.open_pipeline_value,
            computed_scores.expansion_opportunity_count,
            computed_scores.latest_health_score,
            computed_scores.latest_churn_score,
            computed_scores.latest_expansion_score,
            computed_scores.latest_score_reason,
            computed_scores.latest_score_date,
            computed_scores.usage_activity_score,
            computed_scores.active_user_score,
            computed_scores.nps_score_component,
            computed_scores.engagement_recency_score,
            computed_scores.support_health_score,
            computed_scores.action_discipline_score,
            computed_scores.renewal_risk_score,
            computed_scores.pipeline_value_score,
            computed_scores.expansion_signal_score,
            computed_scores.computed_health_score,
            computed_scores.computed_churn_risk_score,
            computed_scores.raw_expansion_score,
                CASE
                    WHEN (computed_scores.computed_churn_risk_score >= (70)::numeric) THEN round((computed_scores.raw_expansion_score * 0.65), 2)
                    WHEN (computed_scores.computed_churn_risk_score >= (55)::numeric) THEN round((computed_scores.raw_expansion_score * 0.85), 2)
                    ELSE computed_scores.raw_expansion_score
                END AS computed_expansion_score
           FROM computed_scores
        )
 SELECT account_id,
    company_name,
    industry,
    segment,
    company_size,
    annual_recurring_revenue,
    plan_type,
    customer_stage,
    account_owner,
    renewal_date,
    days_until_renewal,
    usage_events_last_30_days,
    active_users_last_30_days,
    support_tickets_last_30_days,
    nps_score,
    days_since_last_touch,
    overdue_action_count,
    open_pipeline_value,
    expansion_opportunity_count,
    latest_health_score,
    latest_churn_score,
    latest_expansion_score,
    latest_score_reason,
    latest_score_date,
    usage_activity_score,
    active_user_score,
    nps_score_component,
    engagement_recency_score,
    support_health_score,
    action_discipline_score,
    renewal_risk_score,
    pipeline_value_score,
    expansion_signal_score,
    computed_health_score,
    computed_churn_risk_score,
    raw_expansion_score,
    computed_expansion_score,
        CASE
            WHEN (computed_churn_risk_score >= (75)::numeric) THEN 'Critical Risk'::text
            WHEN (computed_churn_risk_score >= (60)::numeric) THEN 'High Risk'::text
            WHEN (computed_churn_risk_score >= (40)::numeric) THEN 'Moderate Risk'::text
            ELSE 'Low Risk'::text
        END AS risk_level,
        CASE
            WHEN (computed_expansion_score >= (75)::numeric) THEN 'High Expansion'::text
            WHEN (computed_expansion_score >= (50)::numeric) THEN 'Medium Expansion'::text
            ELSE 'Low Expansion'::text
        END AS expansion_level,
        CASE
            WHEN ((computed_churn_risk_score >= (75)::numeric) AND (days_until_renewal <= 90)) THEN 'Tier 1 - Save Immediately'::text
            WHEN (computed_churn_risk_score >= (75)::numeric) THEN 'Tier 1 - Churn Intervention'::text
            WHEN ((computed_churn_risk_score >= (60)::numeric) AND (days_until_renewal <= 120)) THEN 'Tier 2 - Renewal Risk Watch'::text
            WHEN ((computed_expansion_score >= (75)::numeric) AND (computed_churn_risk_score < (50)::numeric)) THEN 'Tier 2 - Expansion Ready'::text
            WHEN ((computed_expansion_score >= (60)::numeric) AND (computed_churn_risk_score < (60)::numeric)) THEN 'Tier 3 - Expansion Nurture'::text
            WHEN ((computed_health_score >= (65)::numeric) AND (computed_churn_risk_score < (40)::numeric)) THEN 'Tier 3 - Maintain'::text
            ELSE 'Tier 4 - Monitor'::text
        END AS customer_priority_tier,
    'phase_12_v1_fixed_reference_2026_06_28'::text AS scoring_model_version
   FROM final_scores fs;


-- ------------------------------------------------------------
-- v2: Adjusted risk classification thresholds
--   Critical Risk >= 60 (lowered from 75)
--   High Risk     >= 50 (lowered from 60)
-- ------------------------------------------------------------
CREATE VIEW core.account_scoring_engine_v2 AS
 SELECT account_id,
    company_name,
    industry,
    segment,
    company_size,
    annual_recurring_revenue,
    plan_type,
    customer_stage,
    account_owner,
    renewal_date,
    days_until_renewal,
    usage_events_last_30_days,
    active_users_last_30_days,
    support_tickets_last_30_days,
    nps_score,
    days_since_last_touch,
    overdue_action_count,
    open_pipeline_value,
    expansion_opportunity_count,
    latest_health_score,
    latest_churn_score,
    latest_expansion_score,
    latest_score_reason,
    latest_score_date,
    usage_activity_score,
    active_user_score,
    nps_score_component,
    engagement_recency_score,
    support_health_score,
    action_discipline_score,
    renewal_risk_score,
    pipeline_value_score,
    expansion_signal_score,
    computed_health_score,
    computed_churn_risk_score,
    raw_expansion_score,
    computed_expansion_score,
    risk_level,
    expansion_level,
    customer_priority_tier,
    scoring_model_version,
        CASE
            WHEN (computed_churn_risk_score >= (60)::numeric) THEN 'Critical Risk'::text
            WHEN (computed_churn_risk_score >= (50)::numeric) THEN 'High Risk'::text
            WHEN (computed_churn_risk_score >= (40)::numeric) THEN 'Moderate Risk'::text
            ELSE 'Low Risk'::text
        END AS risk_level_v2,
        CASE
            WHEN (computed_expansion_score >= (75)::numeric) THEN 'High Expansion'::text
            WHEN (computed_expansion_score >= (50)::numeric) THEN 'Medium Expansion'::text
            ELSE 'Low Expansion'::text
        END AS expansion_level_v2,
        CASE
            WHEN ((computed_churn_risk_score >= (60)::numeric) AND (days_until_renewal <= 90)) THEN 'Tier 1 - Save Immediately'::text
            WHEN (computed_churn_risk_score >= (60)::numeric) THEN 'Tier 1 - Churn Intervention'::text
            WHEN ((computed_churn_risk_score >= (50)::numeric) AND (days_until_renewal <= 120)) THEN 'Tier 2 - Renewal Risk Watch'::text
            WHEN (computed_churn_risk_score >= (50)::numeric) THEN 'Tier 2 - Churn Risk Watch'::text
            WHEN ((computed_expansion_score >= (75)::numeric) AND (computed_churn_risk_score < (45)::numeric)) THEN 'Tier 2 - Expansion Ready'::text
            WHEN ((computed_expansion_score >= (60)::numeric) AND (computed_churn_risk_score < (55)::numeric)) THEN 'Tier 3 - Expansion Nurture'::text
            WHEN ((computed_health_score >= (65)::numeric) AND (computed_churn_risk_score < (40)::numeric)) THEN 'Tier 3 - Maintain'::text
            ELSE 'Tier 4 - Monitor'::text
        END AS customer_priority_tier_v2,
    'phase_12_v2_adjusted_classification_thresholds'::text AS scoring_model_version_v2
   FROM core.account_scoring_engine ase;


-- ------------------------------------------------------------
-- v3: Expanded priority tier logic (renewal + expansion combos)
-- This is the active scoring version used by the production app.
-- ------------------------------------------------------------
CREATE VIEW core.account_scoring_engine_v3 AS
 SELECT account_id,
    company_name,
    industry,
    segment,
    company_size,
    annual_recurring_revenue,
    plan_type,
    customer_stage,
    account_owner,
    renewal_date,
    days_until_renewal,
    usage_events_last_30_days,
    active_users_last_30_days,
    support_tickets_last_30_days,
    nps_score,
    days_since_last_touch,
    overdue_action_count,
    open_pipeline_value,
    expansion_opportunity_count,
    latest_health_score,
    latest_churn_score,
    latest_expansion_score,
    latest_score_reason,
    latest_score_date,
    usage_activity_score,
    active_user_score,
    nps_score_component,
    engagement_recency_score,
    support_health_score,
    action_discipline_score,
    renewal_risk_score,
    pipeline_value_score,
    expansion_signal_score,
    computed_health_score,
    computed_churn_risk_score,
    raw_expansion_score,
    computed_expansion_score,
    risk_level,
    expansion_level,
    customer_priority_tier,
    scoring_model_version,
    risk_level_v2,
    expansion_level_v2,
    customer_priority_tier_v2,
    scoring_model_version_v2,
        CASE
            WHEN ((computed_churn_risk_score >= (60)::numeric) AND (days_until_renewal <= 90)) THEN 'Tier 1 - Save Immediately'::text
            WHEN (computed_churn_risk_score >= (60)::numeric) THEN 'Tier 1 - Churn Intervention'::text
            WHEN ((computed_churn_risk_score >= (50)::numeric) AND (days_until_renewal <= 120)) THEN 'Tier 2 - Renewal Risk Watch'::text
            WHEN (computed_churn_risk_score >= (50)::numeric) THEN 'Tier 2 - Churn Risk Watch'::text
            WHEN ((computed_churn_risk_score >= (40)::numeric) AND (days_until_renewal <= 30)) THEN 'Tier 2 - Renewal Review'::text
            WHEN ((computed_churn_risk_score >= (40)::numeric) AND (days_until_renewal <= 60)) THEN 'Tier 3 - Renewal Monitor'::text
            WHEN ((computed_expansion_score >= (75)::numeric) AND (days_until_renewal <= 60) AND (computed_churn_risk_score < (50)::numeric)) THEN 'Tier 2 - Renewal Expansion Review'::text
            WHEN ((computed_expansion_score >= (75)::numeric) AND (computed_churn_risk_score < (50)::numeric)) THEN 'Tier 2 - Expansion Ready'::text
            WHEN ((computed_expansion_score >= (60)::numeric) AND (computed_churn_risk_score < (55)::numeric)) THEN 'Tier 3 - Expansion Nurture'::text
            WHEN ((computed_health_score >= (65)::numeric) AND (computed_churn_risk_score < (40)::numeric)) THEN 'Tier 3 - Maintain'::text
            ELSE 'Tier 4 - Monitor'::text
        END AS customer_priority_tier_v3,
    'phase_12_v3_adjusted_priority_tier_logic'::text AS scoring_model_version_v3
   FROM core.account_scoring_engine_v2 ase;