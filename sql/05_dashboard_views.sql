-- ============================================================
-- 05_dashboard_views.sql
-- Customer Revenue Intelligence Engine
--
-- Aggregated dashboard summary views.
-- These are queried directly by the FastAPI backend.
--
-- Views:
--   dashboard_kpis           -- portfolio-level KPI summary
--   dashboard_risk_summary   -- account distribution by risk level
--   dashboard_action_summary -- account distribution by action type
--   dashboard_owner_workload -- workload per owner role
-- ============================================================

-- ------------------------------------------------------------
-- Portfolio KPI summary -- single-row aggregate
-- Queried by GET /dashboard/kpis
-- ------------------------------------------------------------
CREATE VIEW core.dashboard_kpis AS
 SELECT count(*) AS total_accounts,
    count(*) FILTER (WHERE (risk_level = 'Critical Risk'::text)) AS critical_risk_accounts,
    count(*) FILTER (WHERE (risk_level = 'High Risk'::text)) AS high_risk_accounts,
    count(*) FILTER (WHERE (expansion_level = 'High Expansion'::text)) AS high_expansion_accounts,
    count(*) FILTER (WHERE (needs_human_review = true)) AS accounts_needing_human_review,
    count(*) FILTER (WHERE (primary_business_motion = 'Save'::text)) AS save_motion_accounts,
    count(*) FILTER (WHERE (primary_business_motion = 'Recover'::text)) AS recover_motion_accounts,
    count(*) FILTER (WHERE (primary_business_motion = 'Renewal'::text)) AS renewal_motion_accounts,
    count(*) FILTER (WHERE (primary_business_motion = 'Expand'::text)) AS expand_motion_accounts,
    round(avg(computed_health_score), 2) AS avg_health_score,
    round(avg(computed_churn_risk_score), 2) AS avg_churn_risk_score,
    round(avg(computed_expansion_score), 2) AS avg_expansion_score,
    sum(annual_recurring_revenue) AS total_arr,
    sum(annual_recurring_revenue) FILTER (WHERE (risk_level = ANY (ARRAY['Critical Risk'::text, 'High Risk'::text]))) AS arr_at_risk,
    sum(open_pipeline_value) AS total_open_pipeline,
    sum(open_pipeline_value) FILTER (WHERE (expansion_level = 'High Expansion'::text)) AS high_expansion_pipeline,
    'phase_15_v1_dashboard_kpis'::text AS dashboard_kpi_version
   FROM core.account_intelligence_view;


-- ------------------------------------------------------------
-- Risk distribution -- one row per risk level, ordered by severity
-- Queried by GET /dashboard/risk-summary
-- ------------------------------------------------------------
CREATE VIEW core.dashboard_risk_summary AS
 SELECT risk_level,
    count(*) AS account_count,
    round(avg(computed_health_score), 2) AS avg_health_score,
    round(avg(computed_churn_risk_score), 2) AS avg_churn_risk_score,
    round(avg(computed_expansion_score), 2) AS avg_expansion_score,
    sum(annual_recurring_revenue) AS total_arr,
    sum(open_pipeline_value) AS total_open_pipeline,
    count(*) FILTER (WHERE (needs_human_review = true)) AS accounts_needing_human_review,
    'phase_15_v1_dashboard_risk_summary'::text AS dashboard_risk_summary_version
   FROM core.account_intelligence_view
  GROUP BY risk_level
  ORDER BY
        CASE risk_level
            WHEN 'Critical Risk'::text THEN 1
            WHEN 'High Risk'::text THEN 2
            WHEN 'Moderate Risk'::text THEN 3
            WHEN 'Low Risk'::text THEN 4
            ELSE NULL::integer
        END;


-- ------------------------------------------------------------
-- Action type distribution -- one row per action priority + type
-- Queried by GET /dashboard/action-summary
-- ------------------------------------------------------------
CREATE VIEW core.dashboard_action_summary AS
 SELECT recommended_action_priority,
    recommended_action_type,
    count(*) AS account_count,
    count(*) FILTER (WHERE (needs_human_review = true)) AS accounts_needing_human_review,
    min(recommended_due_date) AS earliest_due_date,
    max(recommended_due_date) AS latest_due_date,
    round(avg(computed_churn_risk_score), 2) AS avg_churn_risk_score,
    round(avg(computed_expansion_score), 2) AS avg_expansion_score,
    sum(annual_recurring_revenue) AS total_arr,
    sum(open_pipeline_value) AS total_open_pipeline,
    'phase_15_v1_dashboard_action_summary'::text AS dashboard_action_summary_version
   FROM core.account_intelligence_view
  GROUP BY recommended_action_priority, recommended_action_type
  ORDER BY
        CASE recommended_action_priority
            WHEN 'Critical'::text THEN 1
            WHEN 'High'::text THEN 2
            WHEN 'Medium'::text THEN 3
            WHEN 'Low'::text THEN 4
            ELSE NULL::integer
        END, (count(*)) DESC;


-- ------------------------------------------------------------
-- Owner workload -- one row per suggested_owner_role
-- Queried by GET /dashboard/owner-workload
-- ------------------------------------------------------------
CREATE VIEW core.dashboard_owner_workload AS
 SELECT suggested_owner_role,
    count(*) AS assigned_account_count,
    count(*) FILTER (WHERE (recommended_action_priority = 'Critical'::text)) AS critical_action_count,
    count(*) FILTER (WHERE (recommended_action_priority = 'High'::text)) AS high_action_count,
    count(*) FILTER (WHERE (recommended_action_priority = 'Medium'::text)) AS medium_action_count,
    count(*) FILTER (WHERE (recommended_action_priority = 'Low'::text)) AS low_action_count,
    count(*) FILTER (WHERE (needs_human_review = true)) AS human_review_count,
    round(avg(computed_health_score), 2) AS avg_health_score,
    round(avg(computed_churn_risk_score), 2) AS avg_churn_risk_score,
    round(avg(computed_expansion_score), 2) AS avg_expansion_score,
    sum(annual_recurring_revenue) AS total_arr_owned,
    sum(open_pipeline_value) AS total_pipeline_owned,
    'phase_15_v1_dashboard_owner_workload'::text AS dashboard_owner_workload_version
   FROM core.account_intelligence_view
  GROUP BY suggested_owner_role
  ORDER BY
    (count(*) FILTER (WHERE (recommended_action_priority = 'Critical'::text))) DESC,
    (count(*) FILTER (WHERE (recommended_action_priority = 'High'::text))) DESC,
    (count(*) FILTER (WHERE (needs_human_review = true))) DESC,
    (count(*)) DESC;