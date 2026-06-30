-- ============================================================
-- 06_validation_queries.sql
-- Customer Revenue Intelligence Engine
--
-- Validation queries for confirming dataset integrity,
-- view output, and dashboard metrics after import.
--
-- Run these after loading schema_supabase_clean.sql + data.sql
-- into Supabase or any PostgreSQL instance.
-- No secrets. No destructive operations. Read-only queries.
-- ============================================================


-- ============================================================
-- 1. Base table row counts
-- Expected: 100 / 100 / 150 / 38374 / 1200 / 250 / 20 / 500
-- ============================================================

SELECT 'accounts'              AS table_name, COUNT(*) AS row_count FROM core.accounts
UNION ALL
SELECT 'customer_engagement',                  COUNT(*) FROM core.customer_engagement
UNION ALL
SELECT 'crm_opportunities',                    COUNT(*) FROM core.crm_opportunities
UNION ALL
SELECT 'product_usage_events',                 COUNT(*) FROM core.product_usage_events
UNION ALL
SELECT 'score_history',                        COUNT(*) FROM core.score_history
UNION ALL
SELECT 'actions',                              COUNT(*) FROM core.actions
UNION ALL
SELECT 'experiments',                          COUNT(*) FROM core.experiments
UNION ALL
SELECT 'system_logs',                          COUNT(*) FROM core.system_logs
ORDER BY table_name;


-- ============================================================
-- 2. Intelligence and playbook view row counts
-- Expected: 100 rows each (one per account)
-- ============================================================

SELECT COUNT(*) AS account_intelligence_view_rows FROM core.account_intelligence_view;
SELECT COUNT(*) AS account_action_playbook_rows   FROM core.account_action_playbook;
SELECT COUNT(*) AS recommended_actions_engine_rows FROM core.recommended_actions_engine;


-- ============================================================
-- 3. Duplicate account check
-- Expected: 0 rows (each account_id should be unique)
-- ============================================================

SELECT account_id, COUNT(*) AS duplicate_count
FROM core.accounts
GROUP BY account_id
HAVING COUNT(*) > 1;


-- ============================================================
-- 4. Accounts missing from intelligence view
-- Expected: 0 rows (every account should have a playbook row)
-- ============================================================

SELECT a.account_id, a.company_name
FROM core.accounts a
LEFT JOIN core.account_intelligence_view aiv ON a.account_id = aiv.account_id
WHERE aiv.account_id IS NULL;


-- ============================================================
-- 5. Playbook completeness -- check for NULL in required fields
-- Expected: 0 rows for each check
-- ============================================================

SELECT account_id, company_name
FROM core.account_intelligence_view
WHERE recommended_action_type IS NULL
   OR recommended_action_priority IS NULL
   OR suggested_owner_role IS NULL
   OR recommended_due_date IS NULL
   OR primary_business_motion IS NULL;

SELECT account_id
FROM core.account_action_playbook
WHERE immediate_next_steps IS NULL
   OR phase_2_next_steps IS NULL
   OR success_metrics IS NULL
   OR escalation_guidance IS NULL;


-- ============================================================
-- 6. Score range sanity checks
-- All computed scores should be in 0-100 range
-- ============================================================

SELECT
    MIN(computed_health_score)     AS min_health,
    MAX(computed_health_score)     AS max_health,
    MIN(computed_churn_risk_score) AS min_churn,
    MAX(computed_churn_risk_score) AS max_churn,
    MIN(computed_expansion_score)  AS min_expansion,
    MAX(computed_expansion_score)  AS max_expansion
FROM core.account_intelligence_view;

-- Any out-of-range scores (should return 0 rows)
SELECT account_id, company_name, computed_health_score, computed_churn_risk_score, computed_expansion_score
FROM core.account_intelligence_view
WHERE computed_health_score < 0 OR computed_health_score > 100
   OR computed_churn_risk_score < 0 OR computed_churn_risk_score > 100
   OR computed_expansion_score < 0 OR computed_expansion_score > 100;


-- ============================================================
-- 7. Dashboard KPI check
-- Confirms the dashboard summary view produces one row
-- ============================================================

SELECT
    total_accounts,
    critical_risk_accounts,
    high_risk_accounts,
    high_expansion_accounts,
    accounts_needing_human_review,
    total_arr,
    arr_at_risk
FROM core.dashboard_kpis;


-- ============================================================
-- 8. Risk distribution check
-- Confirms all 4 risk levels are populated
-- ============================================================

SELECT risk_level, account_count, avg_churn_risk_score, total_arr
FROM core.dashboard_risk_summary
ORDER BY
    CASE risk_level
        WHEN 'Critical Risk' THEN 1
        WHEN 'High Risk'     THEN 2
        WHEN 'Moderate Risk' THEN 3
        WHEN 'Low Risk'      THEN 4
    END;


-- ============================================================
-- 9. Sample high-risk accounts
-- ============================================================

SELECT
    company_name,
    risk_level,
    computed_churn_risk_score,
    computed_health_score,
    recommended_action_type,
    suggested_owner_role,
    days_until_renewal
FROM core.account_intelligence_view
WHERE risk_level IN ('Critical Risk', 'High Risk')
ORDER BY computed_churn_risk_score DESC
LIMIT 10;


-- ============================================================
-- 10. Sample expansion-ready accounts
-- ============================================================

SELECT
    company_name,
    expansion_level,
    computed_expansion_score,
    computed_churn_risk_score,
    recommended_action_type,
    suggested_owner_role,
    open_pipeline_value
FROM core.account_intelligence_view
WHERE expansion_level = 'High Expansion'
ORDER BY computed_expansion_score DESC
LIMIT 10;


-- ============================================================
-- 11. Sample accounts flagged for human review
-- ============================================================

SELECT
    company_name,
    recommended_action_priority,
    risk_level,
    needs_human_review,
    human_review_reason,
    days_until_renewal
FROM core.account_intelligence_view
WHERE needs_human_review = true
ORDER BY
    CASE recommended_action_priority
        WHEN 'Critical' THEN 1
        WHEN 'High'     THEN 2
        WHEN 'Medium'   THEN 3
        ELSE 4
    END
LIMIT 10;


-- ============================================================
-- 12. Owner workload distribution
-- ============================================================

SELECT
    suggested_owner_role,
    assigned_account_count,
    critical_action_count,
    high_action_count,
    human_review_count,
    total_arr_owned
FROM core.dashboard_owner_workload;


-- ============================================================
-- 13. Account motion distribution
-- ============================================================

SELECT
    primary_business_motion,
    COUNT(*) AS account_count,
    ROUND(AVG(computed_churn_risk_score), 2) AS avg_churn,
    SUM(annual_recurring_revenue) AS total_arr
FROM core.account_intelligence_view
GROUP BY primary_business_motion
ORDER BY account_count DESC;