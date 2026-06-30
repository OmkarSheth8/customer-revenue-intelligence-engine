-- ============================================================
-- 02_feature_engineering_views.sql
-- Customer Revenue Intelligence Engine
--
-- Feature engineering layer: converts raw table data into
-- account-level business metrics for the scoring engine.
--
-- Views (in dependency order):
--   account_action_features
--   account_engagement_features
--   account_opportunity_features
--   account_score_features
--   account_usage_features
--   account_features  (unified feature layer -- input to scoring)
-- ============================================================

-- ------------------------------------------------------------
-- Action features: summarizes action status and urgency per account
-- ------------------------------------------------------------
CREATE VIEW core.account_action_features AS
 SELECT account_id,
    count(*) AS total_action_count,
    count(*) FILTER (WHERE ((status)::text = ANY ((ARRAY['Pending'::character varying, 'In Progress'::character varying])::text[]))) AS active_action_count,
    count(*) FILTER (WHERE ((status)::text = 'Pending'::text)) AS pending_action_count,
    count(*) FILTER (WHERE ((status)::text = 'In Progress'::text)) AS in_progress_action_count,
    count(*) FILTER (WHERE ((status)::text = 'Completed'::text)) AS completed_action_count,
    count(*) FILTER (WHERE ((status)::text = 'Dismissed'::text)) AS dismissed_action_count,
    count(*) FILTER (WHERE ((priority)::text = ANY ((ARRAY['Critical'::character varying, 'High'::character varying])::text[]))) AS high_priority_action_count,
    count(*) FILTER (WHERE ((priority)::text = 'Critical'::text)) AS critical_action_count,
    count(*) FILTER (WHERE (((status)::text = ANY ((ARRAY['Pending'::character varying, 'In Progress'::character varying])::text[])) AND (due_date < '2026-06-28'::date))) AS overdue_action_count,
    min(due_date) FILTER (WHERE ((status)::text = ANY ((ARRAY['Pending'::character varying, 'In Progress'::character varying])::text[]))) AS next_open_action_due_date
   FROM core.actions
  GROUP BY account_id;


-- ------------------------------------------------------------
-- Engagement features: NPS, support pressure, email, meetings
-- ------------------------------------------------------------
CREATE VIEW core.account_engagement_features AS
 SELECT account_id,
    emails_opened,
    emails_replied,
    meetings_last_30_days,
    support_tickets_last_30_days,
    nps_score,
    last_touch_date,
    ('2026-06-28'::date - last_touch_date) AS days_since_last_touch,
        CASE
            WHEN (emails_opened > 0) THEN round((((emails_replied)::numeric / (emails_opened)::numeric) * (100)::numeric), 2)
            ELSE (0)::numeric
        END AS email_reply_rate_percent,
        CASE
            WHEN (meetings_last_30_days >= 2) THEN 'high'::text
            WHEN (meetings_last_30_days = 1) THEN 'medium'::text
            ELSE 'low'::text
        END AS meeting_engagement_level,
        CASE
            WHEN (support_tickets_last_30_days >= 8) THEN 'high'::text
            WHEN (support_tickets_last_30_days >= 4) THEN 'medium'::text
            ELSE 'low'::text
        END AS support_pressure_level,
        CASE
            WHEN (nps_score >= 8) THEN 'promoter'::text
            WHEN (nps_score >= 5) THEN 'neutral'::text
            ELSE 'detractor'::text
        END AS nps_category
   FROM core.customer_engagement;


-- ------------------------------------------------------------
-- Opportunity features: open pipeline, expansion signals, CRM timing
-- ------------------------------------------------------------
CREATE VIEW core.account_opportunity_features AS
 SELECT account_id,
    count(*) AS total_opportunity_count,
    count(*) FILTER (WHERE ((pipeline_stage)::text <> ALL ((ARRAY['Closed Won'::character varying, 'Closed Lost'::character varying])::text[]))) AS open_opportunity_count,
    COALESCE(sum(amount) FILTER (WHERE ((pipeline_stage)::text <> ALL ((ARRAY['Closed Won'::character varying, 'Closed Lost'::character varying])::text[]))), (0)::numeric) AS open_pipeline_value,
    COALESCE(sum(((amount * (probability)::numeric) / 100.0)) FILTER (WHERE ((pipeline_stage)::text <> ALL ((ARRAY['Closed Won'::character varying, 'Closed Lost'::character varying])::text[]))), (0)::numeric) AS weighted_pipeline_value,
    min(expected_close_date) FILTER (WHERE ((pipeline_stage)::text <> ALL ((ARRAY['Closed Won'::character varying, 'Closed Lost'::character varying])::text[]))) AS next_expected_close_date,
    ('2026-06-28'::date - max(last_activity_date)) AS days_since_last_crm_activity,
    count(*) FILTER (WHERE (((opportunity_type)::text ~~* '%expansion%'::text) OR ((opportunity_type)::text ~~* '%upsell%'::text))) AS expansion_opportunity_count
   FROM core.crm_opportunities
  GROUP BY account_id;


-- ------------------------------------------------------------
-- Score history features: latest score per account (window function)
-- ------------------------------------------------------------
CREATE VIEW core.account_score_features AS
 SELECT score_id,
    account_id,
    health_score AS latest_health_score,
    churn_score AS latest_churn_score,
    expansion_score AS latest_expansion_score,
    score_reason AS latest_score_reason,
    calculated_at AS latest_score_date
   FROM ( SELECT sh.score_id,
            sh.account_id,
            sh.health_score,
            sh.churn_score,
            sh.expansion_score,
            sh.score_reason,
            sh.calculated_at,
            row_number() OVER (PARTITION BY sh.account_id ORDER BY sh.calculated_at DESC) AS row_num
           FROM core.score_history sh) ranked_scores
  WHERE (row_num = 1);


-- ------------------------------------------------------------
-- Usage features: product event activity per account (last 7/30 days)
-- ------------------------------------------------------------
CREATE VIEW core.account_usage_features AS
 SELECT account_id,
    count(*) AS total_usage_events,
    count(*) FILTER (WHERE (event_timestamp >= ('2026-06-28'::date - '30 days'::interval))) AS usage_events_last_30_days,
    count(*) FILTER (WHERE (event_timestamp >= ('2026-06-28'::date - '7 days'::interval))) AS usage_events_last_7_days,
    count(DISTINCT user_id) AS active_users_total,
    count(DISTINCT user_id) FILTER (WHERE (event_timestamp >= ('2026-06-28'::date - '30 days'::interval))) AS active_users_last_30_days,
    count(DISTINCT feature_name) AS distinct_features_used,
    round(avg(session_duration_minutes), 2) AS avg_session_duration_minutes,
    max(event_timestamp) AS last_product_event_at,
    ('2026-06-28'::date - (max(event_timestamp))::date) AS days_since_last_product_event
   FROM core.product_usage_events
  GROUP BY account_id;


-- ------------------------------------------------------------
-- Unified account feature layer: joins all 5 feature views + accounts
-- This is the input to the scoring engine.
-- ------------------------------------------------------------
CREATE VIEW core.account_features AS
 SELECT a.account_id,
    a.company_name,
    a.industry,
    a.segment,
    a.company_size,
    a.annual_recurring_revenue,
    a.plan_type,
    a.customer_stage,
    a.account_owner,
    a.contract_start_date,
    a.renewal_date,
    a.created_at,
    a.updated_at,
    (a.renewal_date - '2026-06-28'::date) AS days_until_renewal,
    COALESCE(uf.total_usage_events, (0)::bigint) AS total_usage_events,
    COALESCE(uf.usage_events_last_30_days, (0)::bigint) AS usage_events_last_30_days,
    COALESCE(uf.usage_events_last_7_days, (0)::bigint) AS usage_events_last_7_days,
    COALESCE(uf.active_users_total, (0)::bigint) AS active_users_total,
    COALESCE(uf.active_users_last_30_days, (0)::bigint) AS active_users_last_30_days,
    COALESCE(uf.distinct_features_used, (0)::bigint) AS distinct_features_used,
    COALESCE(uf.avg_session_duration_minutes, (0)::numeric) AS avg_session_duration_minutes,
    uf.last_product_event_at,
    uf.days_since_last_product_event,
    COALESCE(ef.emails_opened, 0) AS emails_opened,
    COALESCE(ef.emails_replied, 0) AS emails_replied,
    COALESCE(ef.meetings_last_30_days, 0) AS meetings_last_30_days,
    COALESCE(ef.support_tickets_last_30_days, 0) AS support_tickets_last_30_days,
    ef.nps_score,
    ef.last_touch_date,
    ef.days_since_last_touch,
    COALESCE(ef.email_reply_rate_percent, (0)::numeric) AS email_reply_rate_percent,
    ef.meeting_engagement_level,
    ef.support_pressure_level,
    ef.nps_category,
    COALESCE(ofe.total_opportunity_count, (0)::bigint) AS total_opportunity_count,
    COALESCE(ofe.open_opportunity_count, (0)::bigint) AS open_opportunity_count,
    COALESCE(ofe.open_pipeline_value, (0)::numeric) AS open_pipeline_value,
    COALESCE(ofe.weighted_pipeline_value, (0)::numeric) AS weighted_pipeline_value,
    ofe.next_expected_close_date,
        CASE
            WHEN (ofe.next_expected_close_date IS NOT NULL) THEN (ofe.next_expected_close_date - '2026-06-28'::date)
            ELSE NULL::integer
        END AS days_until_next_expected_close,
    ofe.days_since_last_crm_activity,
    COALESCE(ofe.expansion_opportunity_count, (0)::bigint) AS expansion_opportunity_count,
    sf.latest_health_score,
    sf.latest_churn_score,
    sf.latest_expansion_score,
    sf.latest_score_reason,
    sf.latest_score_date,
    COALESCE(af.total_action_count, (0)::bigint) AS total_action_count,
    COALESCE(af.active_action_count, (0)::bigint) AS active_action_count,
    COALESCE(af.pending_action_count, (0)::bigint) AS pending_action_count,
    COALESCE(af.in_progress_action_count, (0)::bigint) AS in_progress_action_count,
    COALESCE(af.completed_action_count, (0)::bigint) AS completed_action_count,
    COALESCE(af.dismissed_action_count, (0)::bigint) AS dismissed_action_count,
    COALESCE(af.high_priority_action_count, (0)::bigint) AS high_priority_action_count,
    COALESCE(af.critical_action_count, (0)::bigint) AS critical_action_count,
    COALESCE(af.overdue_action_count, (0)::bigint) AS overdue_action_count,
    af.next_open_action_due_date
   FROM (((((core.accounts a
     LEFT JOIN core.account_usage_features uf ON (((a.account_id)::text = (uf.account_id)::text)))
     LEFT JOIN core.account_engagement_features ef ON (((a.account_id)::text = (ef.account_id)::text)))
     LEFT JOIN core.account_opportunity_features ofe ON (((a.account_id)::text = (ofe.account_id)::text)))
     LEFT JOIN core.account_score_features sf ON (((a.account_id)::text = (sf.account_id)::text)))
     LEFT JOIN core.account_action_features af ON (((a.account_id)::text = (af.account_id)::text)));