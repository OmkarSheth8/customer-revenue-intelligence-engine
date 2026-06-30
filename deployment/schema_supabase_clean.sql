--
-- PostgreSQL database dump
--


-- Dumped from database version 18.1
-- Dumped by pg_dump version 18.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: core; Type: SCHEMA; Schema: -; Owner: -
--

DROP SCHEMA IF EXISTS core CASCADE;
CREATE SCHEMA core;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: actions; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.actions (
    action_id character varying(50) NOT NULL,
    account_id character varying(50) NOT NULL,
    recommended_action text,
    assigned_to character varying(255),
    priority character varying(50),
    status character varying(50),
    due_date date,
    completed_at timestamp without time zone,
    outcome text,
    created_at timestamp without time zone
);


--
-- Name: account_action_features; Type: VIEW; Schema: core; Owner: -
--

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


--
-- Name: customer_engagement; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.customer_engagement (
    engagement_id character varying(50) NOT NULL,
    account_id character varying(50) NOT NULL,
    emails_opened integer,
    emails_replied integer,
    meetings_last_30_days integer,
    support_tickets_last_30_days integer,
    nps_score integer,
    last_touch_date date
);


--
-- Name: account_engagement_features; Type: VIEW; Schema: core; Owner: -
--

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


--
-- Name: crm_opportunities; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.crm_opportunities (
    opportunity_id character varying(50) NOT NULL,
    account_id character varying(50) NOT NULL,
    opportunity_type character varying(100),
    pipeline_stage character varying(100),
    amount numeric(12,2),
    probability integer,
    created_date date,
    expected_close_date date,
    last_activity_date date
);


--
-- Name: account_opportunity_features; Type: VIEW; Schema: core; Owner: -
--

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


--
-- Name: score_history; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.score_history (
    score_id character varying(50) NOT NULL,
    account_id character varying(50) NOT NULL,
    health_score numeric(5,2),
    churn_score numeric(5,2),
    expansion_score numeric(5,2),
    score_reason text,
    calculated_at date
);


--
-- Name: account_score_features; Type: VIEW; Schema: core; Owner: -
--

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


--
-- Name: product_usage_events; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_usage_events (
    event_id character varying(50) NOT NULL,
    account_id character varying(50) NOT NULL,
    user_id character varying(100),
    event_type character varying(100),
    feature_name character varying(150),
    session_duration_minutes numeric(10,2),
    event_timestamp timestamp without time zone
);


--
-- Name: account_usage_features; Type: VIEW; Schema: core; Owner: -
--

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


--
-- Name: accounts; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.accounts (
    account_id character varying(50) NOT NULL,
    company_name character varying(255) NOT NULL,
    industry character varying(100),
    segment character varying(100),
    company_size integer,
    annual_recurring_revenue numeric(12,2),
    plan_type character varying(100),
    customer_stage character varying(100),
    account_owner character varying(255),
    contract_start_date date,
    renewal_date date,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: account_features; Type: VIEW; Schema: core; Owner: -
--

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


--
-- Name: account_scoring_engine; Type: VIEW; Schema: core; Owner: -
--

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


--
-- Name: account_scoring_engine_v2; Type: VIEW; Schema: core; Owner: -
--

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


--
-- Name: account_scoring_engine_v3; Type: VIEW; Schema: core; Owner: -
--

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


--
-- Name: recommended_actions_engine; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.recommended_actions_engine AS
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
    overdue_action_count,
    open_pipeline_value,
    computed_health_score,
    computed_churn_risk_score,
    computed_expansion_score,
    risk_level_v2,
    expansion_level_v2,
    customer_priority_tier_v3,
        CASE
            WHEN (customer_priority_tier_v3 = 'Tier 1 - Save Immediately'::text) THEN 'Executive Renewal Save Plan'::text
            WHEN (customer_priority_tier_v3 = 'Tier 1 - Churn Intervention'::text) THEN 'Immediate Churn Intervention'::text
            WHEN (customer_priority_tier_v3 = 'Tier 2 - Renewal Risk Watch'::text) THEN 'Renewal Risk Review'::text
            WHEN (customer_priority_tier_v3 = 'Tier 2 - Churn Risk Watch'::text) THEN 'CSM Risk Review'::text
            WHEN (customer_priority_tier_v3 = 'Tier 2 - Renewal Review'::text) THEN 'Renewal Readiness Review'::text
            WHEN (customer_priority_tier_v3 = 'Tier 2 - Renewal Expansion Review'::text) THEN 'Renewal and Expansion Review'::text
            WHEN (customer_priority_tier_v3 = 'Tier 2 - Expansion Ready'::text) THEN 'Expansion Discovery'::text
            WHEN (customer_priority_tier_v3 = 'Tier 3 - Renewal Monitor'::text) THEN 'Renewal Monitoring'::text
            WHEN (customer_priority_tier_v3 = 'Tier 3 - Expansion Nurture'::text) THEN 'Expansion Nurture'::text
            WHEN (customer_priority_tier_v3 = 'Tier 3 - Maintain'::text) THEN 'Maintain Account Health'::text
            ELSE 'Monitor Account'::text
        END AS recommended_action_type,
        CASE
            WHEN (customer_priority_tier_v3 ~~ 'Tier 1%'::text) THEN 'Critical'::text
            WHEN (customer_priority_tier_v3 ~~ 'Tier 2%'::text) THEN 'High'::text
            WHEN (customer_priority_tier_v3 ~~ 'Tier 3%'::text) THEN 'Medium'::text
            ELSE 'Low'::text
        END AS recommended_action_priority,
        CASE
            WHEN (customer_priority_tier_v3 = 'Tier 1 - Save Immediately'::text) THEN 'Schedule an executive renewal save call, review product issues, confirm renewal blockers, and create a save plan within 24 hours.'::text
            WHEN (customer_priority_tier_v3 = 'Tier 1 - Churn Intervention'::text) THEN 'Open an urgent churn intervention plan with the account owner, identify adoption blockers, review support issues, and define recovery actions.'::text
            WHEN (customer_priority_tier_v3 = 'Tier 2 - Renewal Risk Watch'::text) THEN 'Review renewal readiness, inspect product usage, check support pressure, and prepare a renewal risk mitigation plan.'::text
            WHEN (customer_priority_tier_v3 = 'Tier 2 - Churn Risk Watch'::text) THEN 'Ask the account owner to review account health, validate customer sentiment, and decide whether escalation is needed.'::text
            WHEN (customer_priority_tier_v3 = 'Tier 2 - Renewal Review'::text) THEN 'Review renewal status immediately because the account is close to renewal and has moderate churn risk.'::text
            WHEN (customer_priority_tier_v3 = 'Tier 2 - Renewal Expansion Review'::text) THEN 'Prepare a renewal conversation and evaluate expansion only if customer sentiment and product adoption are stable.'::text
            WHEN (customer_priority_tier_v3 = 'Tier 2 - Expansion Ready'::text) THEN 'Start expansion discovery with the account owner, identify additional use cases, and validate budget or pipeline opportunity.'::text
            WHEN (customer_priority_tier_v3 = 'Tier 3 - Renewal Monitor'::text) THEN 'Monitor renewal readiness, confirm next touchpoint, and check whether usage or sentiment declines.'::text
            WHEN (customer_priority_tier_v3 = 'Tier 3 - Expansion Nurture'::text) THEN 'Nurture the account for expansion by tracking usage, identifying active teams, and preparing a future upsell conversation.'::text
            WHEN (customer_priority_tier_v3 = 'Tier 3 - Maintain'::text) THEN 'Maintain regular account engagement and continue monitoring health signals.'::text
            ELSE 'No immediate action required. Continue monitoring account health, usage, support pressure, and renewal timing.'::text
        END AS recommended_next_action,
        CASE
            WHEN (customer_priority_tier_v3 ~~ 'Tier 1%'::text) THEN 'Customer Success Leadership'::text
            WHEN (customer_priority_tier_v3 = ANY (ARRAY['Tier 2 - Expansion Ready'::text, 'Tier 2 - Renewal Expansion Review'::text])) THEN 'Account Executive'::text
            WHEN (customer_priority_tier_v3 ~~ 'Tier 2%'::text) THEN 'Customer Success Manager'::text
            WHEN (customer_priority_tier_v3 ~~ 'Tier 3%'::text) THEN 'Account Owner'::text
            ELSE 'Revenue Operations'::text
        END AS suggested_owner_role,
        CASE
            WHEN (customer_priority_tier_v3 = 'Tier 1 - Save Immediately'::text) THEN ('2026-06-28'::date + '1 day'::interval)
            WHEN (customer_priority_tier_v3 = 'Tier 1 - Churn Intervention'::text) THEN ('2026-06-28'::date + '2 days'::interval)
            WHEN (customer_priority_tier_v3 ~~ 'Tier 2%'::text) THEN ('2026-06-28'::date + '5 days'::interval)
            WHEN (customer_priority_tier_v3 ~~ 'Tier 3%'::text) THEN ('2026-06-28'::date + '14 days'::interval)
            ELSE ('2026-06-28'::date + '30 days'::interval)
        END AS recommended_due_date,
        CASE
            WHEN (customer_priority_tier_v3 ~~ 'Tier 1%'::text) THEN concat('High churn risk score of ', computed_churn_risk_score, ', health score of ', computed_health_score, ', ', days_until_renewal, ' days until renewal, ', usage_events_last_30_days, ' usage events in the last 30 days, ', support_tickets_last_30_days, ' support tickets, and ', overdue_action_count, ' overdue actions.')
            WHEN (customer_priority_tier_v3 ~~ 'Tier 2%'::text) THEN concat('Priority driven by ', risk_level_v2, ', ', expansion_level_v2, ', ', days_until_renewal, ' days until renewal, churn risk score of ', computed_churn_risk_score, ', and expansion score of ', computed_expansion_score, '.')
            WHEN (customer_priority_tier_v3 ~~ 'Tier 3%'::text) THEN concat('Account has manageable risk with health score of ', computed_health_score, ', churn risk score of ', computed_churn_risk_score, ', and expansion score of ', computed_expansion_score, '.')
            ELSE concat('Account currently has low urgency with health score of ', computed_health_score, ', churn risk score of ', computed_churn_risk_score, ', and expansion score of ', computed_expansion_score, '.')
        END AS recommendation_reason,
    'phase_13_v1_rule_based_recommended_actions'::text AS recommendation_model_version
   FROM core.account_scoring_engine_v3 ase;


--
-- Name: account_action_playbook; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.account_action_playbook AS
 WITH signals AS (
         SELECT recommended_actions_engine.account_id,
            recommended_actions_engine.company_name,
            recommended_actions_engine.industry,
            recommended_actions_engine.segment,
            recommended_actions_engine.company_size,
            recommended_actions_engine.annual_recurring_revenue,
            recommended_actions_engine.plan_type,
            recommended_actions_engine.customer_stage,
            recommended_actions_engine.account_owner,
            recommended_actions_engine.renewal_date,
            recommended_actions_engine.days_until_renewal,
            recommended_actions_engine.usage_events_last_30_days,
            recommended_actions_engine.active_users_last_30_days,
            recommended_actions_engine.support_tickets_last_30_days,
            recommended_actions_engine.nps_score,
            recommended_actions_engine.overdue_action_count,
            recommended_actions_engine.open_pipeline_value,
            recommended_actions_engine.computed_health_score,
            recommended_actions_engine.computed_churn_risk_score,
            recommended_actions_engine.computed_expansion_score,
            recommended_actions_engine.risk_level_v2,
            recommended_actions_engine.expansion_level_v2,
            recommended_actions_engine.customer_priority_tier_v3,
            recommended_actions_engine.recommended_action_type,
            recommended_actions_engine.recommended_action_priority,
            recommended_actions_engine.recommended_next_action,
            recommended_actions_engine.suggested_owner_role,
            recommended_actions_engine.recommended_due_date,
            recommended_actions_engine.recommendation_reason,
            recommended_actions_engine.recommendation_model_version,
            (recommended_actions_engine.support_tickets_last_30_days >= 5) AS high_support,
            ((recommended_actions_engine.support_tickets_last_30_days >= 3) AND (recommended_actions_engine.support_tickets_last_30_days < 5)) AS moderate_support,
            (recommended_actions_engine.usage_events_last_30_days <= 15) AS low_usage,
            (recommended_actions_engine.usage_events_last_30_days >= 50) AS high_usage,
            (recommended_actions_engine.active_users_last_30_days <= 5) AS very_low_users,
            (recommended_actions_engine.nps_score <= 5) AS low_nps,
            (recommended_actions_engine.nps_score >= 8) AS high_nps,
            (recommended_actions_engine.days_until_renewal <= 30) AS renewal_imminent,
            (recommended_actions_engine.days_until_renewal <= 90) AS renewal_near,
            (recommended_actions_engine.computed_churn_risk_score >= (60)::numeric) AS very_high_churn,
            (recommended_actions_engine.computed_health_score >= (65)::numeric) AS healthy,
            (recommended_actions_engine.computed_expansion_score >= (65)::numeric) AS strong_expansion,
            (recommended_actions_engine.overdue_action_count >= 2) AS has_overdue
           FROM core.recommended_actions_engine
        )
 SELECT account_id,
    company_name AS account_name,
    recommended_action_type,
    recommended_action_priority,
    computed_churn_risk_score,
    computed_health_score,
    computed_expansion_score,
    support_tickets_last_30_days,
    usage_events_last_30_days,
    active_users_last_30_days,
    overdue_action_count,
    nps_score,
    days_until_renewal,
    risk_level_v2,
    expansion_level_v2,
    customer_priority_tier_v3,
    suggested_owner_role,
    recommended_due_date,
    account_owner,
        CASE recommended_action_type
            WHEN 'Immediate Churn Intervention'::text THEN
            CASE
                WHEN (high_support AND low_usage) THEN jsonb_build_array((('Convene emergency CSM + leadership call within 24 hours to review '::text || (support_tickets_last_30_days)::text) || ' open support tickets and align on a resolution SLA'::text), 'Assign a dedicated technical resource to diagnose and close the top blocking support issues this week', (('Map inactive user groups — only '::text || (active_users_last_30_days)::text) || ' active users recorded — identify specific adoption blockers by team or role'::text), (('Schedule executive sponsor outreach from '::text || suggested_owner_role) || ' within 48 hours to express commitment and set recovery expectations'::text), 'Initiate a formal churn save plan with defined milestones, owners, and a 30-day check-in cadence')
                WHEN high_support THEN jsonb_build_array((('Escalate '::text || (support_tickets_last_30_days)::text) || ' open support tickets to engineering leadership for prioritized triage within 24 hours'::text), 'Schedule an executive check-in with the account sponsor to address service quality concerns directly', 'Assign a dedicated CSM to conduct a weekly support ticket review until volume drops below 2', 'Audit all open issues for root cause patterns and deliver a written resolution plan to the customer', (('Initiate churn save motion — set an internal countdown to renewal in '::text || (days_until_renewal)::text) || ' days with named accountable owners'::text))
                WHEN low_usage THEN jsonb_build_array((((('Immediately identify which user groups have gone inactive — currently only '::text || (active_users_last_30_days)::text) || ' active users with '::text) || (usage_events_last_30_days)::text) || ' events in 30 days'::text), 'Schedule a product adoption recovery session with key customer stakeholders within 1 week', 'Deliver targeted enablement to inactive users — identify top 3 unmet use cases as adoption starting points', 'Set a weekly usage recovery checkpoint and define a minimum viable usage KPI with the account champion', 'Flag for executive escalation if usage does not recover by at least 30% within 2 weeks of intervention')
                ELSE jsonb_build_array((('Open a formal churn intervention plan — assign ownership to '::text || suggested_owner_role) || ' immediately'::text), ((((('Review all active support tickets ('::text || (support_tickets_last_30_days)::text) || ') and usage signals ('::text) || (usage_events_last_30_days)::text) || ' events) with '::text) || (account_owner)::text), 'Schedule an executive sponsor call to surface the top blockers and re-establish shared account goals', (('Audit the renewal risk landscape with '::text || (days_until_renewal)::text) || ' days remaining — define recovery milestones and ownership chain'::text), 'Document the churn risk rationale and align internally on a save vs. managed churn decision before the next checkpoint')
            END
            WHEN 'Executive Renewal Save Plan'::text THEN
            CASE
                WHEN renewal_imminent THEN jsonb_build_array((('URGENT: Initiate executive-to-executive outreach today — renewal is in only '::text || (days_until_renewal)::text) || ' days'::text), 'Deliver a compelling ROI summary and business value review to the economic buyer this week — no delay', (('Resolve all open support issues ('::text || (support_tickets_last_30_days)::text) || ' tickets) before the renewal conversation begins'::text), 'Prepare commercial terms options — include multi-year and step-down scenarios for negotiation flexibility', 'Loop in AE and CSM leadership to align on negotiation floor, escalation authority, and close strategy')
                WHEN renewal_near THEN jsonb_build_array((('Schedule an executive sponsor meeting within 2 weeks — renewal is in '::text || (days_until_renewal)::text) || ' days'::text), 'Prepare an account health narrative showing usage trends, support resolution history, and ROI delivered to date', 'Identify renewal blockers: pricing concerns, product gaps, champion turnover, or active competitive evaluation', 'Develop two contract scenarios — status quo renewal and expansion upsell — to present at the executive meeting', (('Assign '::text || suggested_owner_role) || ' as deal owner and confirm the CRM renewal opportunity is fully updated'::text))
                ELSE jsonb_build_array('Assign an executive sponsor and schedule a strategic account review this quarter', ((((('Build the renewal dossier: health score '::text || (computed_health_score)::text) || ', churn risk '::text) || (computed_churn_risk_score)::text) || ', support tickets '::text) || (support_tickets_last_30_days)::text), 'Identify the top 3 renewal risk factors and document concrete mitigation actions with named owners', 'Coordinate with AE to align commercial strategy with the account health trajectory', 'Establish a monthly executive renewal checkpoint cadence and confirm all stakeholder contacts in CRM')
            END
            WHEN 'CSM Risk Review'::text THEN
            CASE
                WHEN (high_support AND low_nps) THEN jsonb_build_array((('Schedule an urgent CSM-led support triage — review all '::text || (support_tickets_last_30_days)::text) || ' tickets with the account team and set resolution SLAs today'::text), ('Conduct a dedicated NPS recovery conversation — understand what specifically drove the score of '::text || (nps_score)::text), 'Escalate the top 3 unresolved issues to engineering leadership and commit to customer-facing SLA dates', 'Deliver a written service recovery summary to the account champion within 5 business days', 'Flag for escalation to VP of Customer Success if ticket volume or NPS does not improve within 30 days')
                WHEN low_nps THEN jsonb_build_array((('Initiate an NPS recovery review — current score is '::text || (nps_score)::text) || ', target is 7 or above'::text), 'Contact all detractor contacts individually within 1 week to surface specific satisfaction drivers', 'Prepare a 30-day improvement action plan tied directly to the account''s stated feedback themes', 'Schedule a follow-up CSM check-in at day 14 to validate that concerns have been acknowledged and acted upon', (('Escalate to '::text || suggested_owner_role) || ' if the NPS score does not recover above 6 within the quarter'::text))
                WHEN high_support THEN jsonb_build_array((('Assign a dedicated CSM to manage '::text || (support_tickets_last_30_days)::text) || ' open tickets with a weekly review cycle'::text), 'Categorize all tickets by severity and assign engineering leads for each critical or blocking issue', 'Schedule bi-weekly customer check-ins until support ticket volume drops to 2 or fewer per month', 'Document root causes across all open tickets and share a written resolution plan with the account champion', 'Flag account for potential churn risk escalation if ticket volume remains above 3 in the next 30-day cycle')
                ELSE jsonb_build_array(('Schedule a standard CSM risk check-in within 2 weeks — owner is '::text || (account_owner)::text), (((('Review current usage levels ('::text || (usage_events_last_30_days)::text) || ' events) and active user engagement ('::text) || (active_users_last_30_days)::text) || ' users)'::text), 'Identify the top 2 account risk signals and document findings in CRM with action owner assignments', 'Clarify renewal intent and surface any contract terms, product, or satisfaction concerns', (('Determine whether account risk warrants escalation to '::text || suggested_owner_role) || ' or can be resolved at the CSM level'::text))
            END
            WHEN 'Renewal Readiness Review'::text THEN
            CASE
                WHEN renewal_imminent THEN jsonb_build_array((('URGENT: Renewal is in '::text || (days_until_renewal)::text) || ' days — complete all renewal readiness tasks this week without exception'::text), 'Send the final renewal proposal to the economic buyer and confirm all decision-making contacts today', (('Confirm all open support issues ('::text || (support_tickets_last_30_days)::text) || ' tickets) are resolved or have a committed resolution timeline before the renewal call'::text), 'Obtain verbal or written renewal intent from the account champion before end of this business week', (('Engage '::text || suggested_owner_role) || ' immediately to handle any last-minute objections or commercial terms questions'::text))
                WHEN renewal_near THEN jsonb_build_array((('Begin a formal renewal readiness review this week — '::text || (days_until_renewal)::text) || ' days remain on the contract'::text), 'Validate current usage trends and adoption health metrics to support the renewal value narrative', 'Survey the economic buyer on satisfaction and renewal intent — target outreach within 2 weeks', 'Confirm renewal decision contacts and economic buyer authority in CRM — update if any roles have changed', (('Resolve all outstanding support tickets ('::text || (support_tickets_last_30_days)::text) || ') before the formal renewal discussion begins'::text))
                ELSE jsonb_build_array((('Schedule a proactive renewal readiness call with '::text || (account_owner)::text) || ' and the account champion this month'::text), ((((('Build the account health story: health score '::text || (computed_health_score)::text) || ', usage events '::text) || (usage_events_last_30_days)::text) || ', NPS '::text) || (nps_score)::text), 'Identify any adoption gaps or pending feature requests that could create renewal friction if unaddressed', 'Confirm renewal decision authority and validate that all key stakeholders are currently engaged', 'Set renewal readiness checkpoints at 90, 60, and 30 days out with assigned owners for each milestone')
            END
            WHEN 'Renewal Risk Review'::text THEN
            CASE
                WHEN (renewal_imminent AND very_high_churn) THEN jsonb_build_array((((('CRITICAL: Renewal in '::text || (days_until_renewal)::text) || ' days — churn risk at '::text) || (computed_churn_risk_score)::text) || ', escalate to leadership immediately'::text), 'Convene a cross-functional save team — CSM, AE, and Support lead — within 48 hours', 'Deliver an urgent value-recovery briefing to the economic buyer before the renewal deadline', 'Prepare internal walk-away and managed-churn decision scenarios to inform negotiation strategy', (('Assign '::text || suggested_owner_role) || ' as executive deal lead and confirm escalation authority'::text))
                WHEN renewal_imminent THEN jsonb_build_array((('Immediate renewal risk escalation required — renewal is in '::text || (days_until_renewal)::text) || ' days'::text), 'Schedule an executive sponsor call to surface all renewal risk factors this week — no delay', (('Resolve open support tickets ('::text || (support_tickets_last_30_days)::text) || ') before the renewal meeting'::text), 'Confirm champion and economic buyer engagement — verify all renewal contacts are active and responsive', (('Provide a written renewal risk summary to '::text || suggested_owner_role) || ' within 24 hours of this review'::text))
                ELSE jsonb_build_array(((('Open a renewal risk review with '::text || (account_owner)::text) || ' — churn risk score is '::text) || (computed_churn_risk_score)::text), (((((('Map the top 3 renewal risk factors from signals: usage events ('::text || (usage_events_last_30_days)::text) || '), support tickets ('::text) || (support_tickets_last_30_days)::text) || '), NPS ('::text) || (nps_score)::text) || ')'::text), 'Define a 30-day risk mitigation plan with named owners and scheduled check-in dates', (('Engage '::text || suggested_owner_role) || ' to provide strategic renewal guidance and executive alignment'::text), 'Schedule a renewal risk board review if churn score exceeds 55 in the next 30 days')
            END
            WHEN 'Renewal and Expansion Review'::text THEN
            CASE
                WHEN (renewal_imminent AND strong_expansion) THEN jsonb_build_array((('Prioritize renewal close first — expansion must not create delay for the core contract expiring in '::text || (days_until_renewal)::text) || ' days'::text), 'Present a combined renewal + expansion proposal in a single executive review meeting this week', 'Confirm champion alignment on both the base renewal terms and the upsell opportunity before the meeting', (((('Engage AE to scope expansion options tied to usage signals: '::text || (usage_events_last_30_days)::text) || ' events, '::text) || (active_users_last_30_days)::text) || ' active users'::text), (('Have '::text || suggested_owner_role) || ' lead the commercial discussion — close the renewal before sequencing expansion'::text))
                ELSE jsonb_build_array('Schedule a combined renewal and expansion review meeting with the account champion and AE this quarter', ((((('Prepare the account health narrative — health score '::text || (computed_health_score)::text) || ', expansion score '::text) || (computed_expansion_score)::text) || ', NPS '::text) || (nps_score)::text), 'Identify 2–3 expansion use cases grounded in current product usage and the champion''s stated business goals', 'Present expansion options alongside the renewal proposal to capture full account commercial value in one motion', (('Have '::text || suggested_owner_role) || ' lead commercial terms — ensure both renewal and expansion close in the same cycle'::text))
            END
            WHEN 'Expansion Discovery'::text THEN
            CASE
                WHEN (strong_expansion AND high_usage) THEN jsonb_build_array((((('Open formal expansion discovery — expansion score is '::text || (computed_expansion_score)::text) || ' with '::text) || (usage_events_last_30_days)::text) || ' usage events showing strong product engagement'::text), 'Map all current stakeholders and identify expansion budget holders, champions, and technical evaluators', 'Conduct use-case discovery to identify 2–3 new deployment, seat expansion, or product tier scenarios', 'Review open pipeline value and coordinate with AE to confirm the expansion opportunity is scoped and qualified', 'Schedule the AE handoff meeting within 2 weeks to formalize the opportunity and move to a commercial motion')
                ELSE jsonb_build_array(('Initiate an expansion discovery conversation with the account champion — expansion score is '::text || (computed_expansion_score)::text), 'Map all active use cases and identify teams, departments, or workflows not yet using the product', 'Conduct a needs assessment to qualify the expansion scenario: seat growth, tier upgrade, or new module', 'Verify open pipeline value and coordinate with AE for discovery call scoping and opportunity qualification', (('Engage '::text || suggested_owner_role) || ' to support stakeholder access and provide strategic expansion framing'::text))
            END
            WHEN 'Expansion Nurture'::text THEN
            CASE
                WHEN (high_usage AND strong_expansion) THEN jsonb_build_array((('Leverage strong product engagement ('::text || (usage_events_last_30_days)::text) || ' events) as the lead proof point in the expansion conversation with the account champion'::text), 'Share a tailored ROI story showing business value delivered — connect directly to the expansion opportunity', 'Identify peer customer success stories or case studies relevant to the account''s expansion scenario', 'Schedule a product roadmap review to demonstrate how expansion-tier features address upcoming customer needs', 'Coordinate with AE to move the expansion nurture toward a qualified discovery call within the next 30 days')
                WHEN strong_expansion THEN jsonb_build_array((('Continue expansion nurture motion — expansion score is '::text || (computed_expansion_score)::text) || ' with positive directional signals'::text), 'Share a relevant peer customer success story to warm the expansion conversation with the champion', 'Schedule a quarterly business review (QBR) to deepen internal champion advocacy and executive visibility', 'Deliver value content: product updates, benchmark data, or adoption guides relevant to the account''s industry and goals', 'Set a 45-day nurture checkpoint to assess expansion readiness and initiate discovery if signals continue to improve')
                ELSE jsonb_build_array((('Maintain expansion nurture with regular value-add touchpoints — '::text || (usage_events_last_30_days)::text) || ' events this month'::text), 'Share industry benchmarks or feature adoption tips to drive incremental engagement and platform usage', 'Assess champion strength — determine if a new or additional expansion sponsor is needed for the motion', (('Log all engagement touchpoints in CRM and track NPS trend (currently '::text || (nps_score)::text) || ')'::text), 'Escalate to formal Expansion Discovery motion if expansion score rises above 65 in the next 60 days')
            END
            WHEN 'Maintain Account Health'::text THEN
            CASE
                WHEN has_overdue THEN jsonb_build_array((('Clear '::text || (overdue_action_count)::text) || ' overdue action(s) — assign owners and set completion dates by end of this week'::text), (('Schedule a standard account health check-in with '::text || (account_owner)::text) || ' to confirm all items are on track'::text), (('Verify usage levels are stable at '::text || (usage_events_last_30_days)::text) || ' events — confirm no decline from the prior month'::text), (('Confirm NPS is holding at '::text || (nps_score)::text) || ' — send a satisfaction pulse survey if it has not been checked in the last 60 days'::text), 'Document current account status in CRM and confirm the next scheduled touchpoint is booked')
                WHEN (high_usage AND healthy) THEN jsonb_build_array((('Account is healthy — maintain the current engagement cadence with '::text || (account_owner)::text) || ' and keep momentum'::text), (('Send a value milestone update to the champion: highlight '::text || (usage_events_last_30_days)::text) || ' product events this month as evidence of strong adoption'::text), (('Keep NPS trend positive at '::text || (nps_score)::text) || ' — schedule the next satisfaction survey at the 90-day interval'::text), (('Monitor expansion score ('::text || (computed_expansion_score)::text) || ') — begin a formal nurture motion if it crosses 60 in the next quarter'::text), 'Log account health summary in CRM and confirm no escalation triggers are currently active')
                ELSE jsonb_build_array(((('Schedule a routine health check-in with '::text || (account_owner)::text) || ' — current health score is '::text) || (computed_health_score)::text), (((('Confirm usage is stable: '::text || (usage_events_last_30_days)::text) || ' events and '::text) || (active_users_last_30_days)::text) || ' active users recorded this month'::text), (('Review any pending support items ('::text || (support_tickets_last_30_days)::text) || ' tickets) and confirm each has a clear resolution path and owner'::text), (('Verify NPS is at or above target (currently '::text || (nps_score)::text) || ') — send a check-in message to the champion if no recent sentiment data exists'::text), 'Update CRM notes with current account status and confirm the renewal timeline is on track')
            END
            WHEN 'Monitor Account'::text THEN
            CASE
                WHEN (has_overdue AND high_support) THEN jsonb_build_array((('Clear '::text || (overdue_action_count)::text) || ' overdue action(s) before adding any new monitoring tasks to the queue'::text), (('Review '::text || (support_tickets_last_30_days)::text) || ' open support tickets and confirm each has an assigned owner and a target resolution date'::text), (('Schedule a focused monitoring review with '::text || (account_owner)::text) || ' within 2 weeks'::text), 'Set automated alerts for key risk thresholds: usage below 10 events or support tickets above 8 per month', 'Evaluate whether account monitoring should escalate to CSM Risk Review given the combined signals')
                WHEN has_overdue THEN jsonb_build_array((('Resolve '::text || (overdue_action_count)::text) || ' overdue action(s) — assign each to a named owner with a clear due date this week'::text), 'Conduct a brief monitoring review to confirm health signals are stable and not trending downward', 'Set a 30-day monitoring checkpoint with defined escalation criteria in CRM', 'Update CRM account notes with current risk posture, monitoring status, and next review date', 'Evaluate whether current signals warrant a handoff to CSM Risk Review or Renewal Risk Review')
                ELSE jsonb_build_array('Maintain a passive monitoring stance — no immediate action required at this time', (((('Check usage trend weekly: currently '::text || (usage_events_last_30_days)::text) || ' events / '::text) || (active_users_last_30_days)::text) || ' active users in the last 30 days'::text), (('Review support ticket count ('::text || (support_tickets_last_30_days)::text) || ') — flag and escalate if it rises above 5 in any single month'::text), (('Confirm account owner ('::text || (account_owner)::text) || ') has active contact with the customer champion'::text), 'Set a 30-day review checkpoint and escalate to active management if any risk signal deteriorates')
            END
            WHEN 'Renewal Monitoring'::text THEN
            CASE
                WHEN renewal_imminent THEN jsonb_build_array((('Renewal is in '::text || (days_until_renewal)::text) || ' days — confirm all renewal readiness tasks are complete and no action items are outstanding'::text), 'Validate the renewal proposal has been received by the champion and is in the economic buyer''s hands', (('Conduct a final health review: confirm usage is stable at '::text || (usage_events_last_30_days)::text) || ' events and no new support issues have emerged'::text), 'Confirm that the renewal champion and economic buyer are fully aligned on terms, pricing, and timeline', 'Escalate to Renewal Risk Review immediately if any unresolved objections or blockers surface in this final window')
                ELSE jsonb_build_array((('Monitor renewal progress — '::text || (days_until_renewal)::text) || ' days remaining on the current contract'::text), (('Confirm the renewal timeline is on track with account owner '::text || (account_owner)::text) || ' via a brief check-in'::text), (((((('Check for any new risk signals: support tickets ('::text || (support_tickets_last_30_days)::text) || '), NPS ('::text) || (nps_score)::text) || '), usage ('::text) || (usage_events_last_30_days)::text) || ' events)'::text), 'Verify all renewal contacts in CRM are current and that champion engagement has been active this month', 'Set a 30-day renewal monitoring checkpoint and escalate to Renewal Risk Review if any signal deteriorates')
            END
            ELSE jsonb_build_array((('Review all account signals with '::text || (account_owner)::text) || ' to determine the appropriate action plan'::text), (((('Assess current health score ('::text || (computed_health_score)::text) || ') and churn risk ('::text) || (computed_churn_risk_score)::text) || ') against segment benchmarks'::text), 'Identify the top 2 risk or opportunity signals and document findings in CRM with assigned owners', ('Confirm the right owner and timeline for the next action — target completion by '::text || COALESCE(to_char(recommended_due_date, 'YYYY-MM-DD'::text), 'TBD'::text)), (('Escalate to '::text || suggested_owner_role) || ' if urgency level increases or signals deteriorate before next review'::text))
        END AS immediate_next_steps,
        CASE recommended_action_type
            WHEN 'Immediate Churn Intervention'::text THEN jsonb_build_array('Conduct a structured 30-day recovery QBR — present progress on usage recovery, ticket resolution, and NPS improvement', 'Track usage trend week over week with a shared dashboard view accessible to the account champion', 'Convert to standard health maintenance mode once churn risk drops below 40 and health score rises above 60', 'Reassess expansion potential after 60 days of sustained health improvement — do not initiate upsell during active save motion')
            WHEN 'Executive Renewal Save Plan'::text THEN jsonb_build_array('Execute the renewal contract — multi-year or step-down scenario depending on negotiation outcome', 'Introduce the executive sponsor to the product roadmap to reinforce long-term partnership value', 'Transition account to standard renewal monitoring post-close and confirm health baseline for the new contract period', 'Evaluate expansion opportunity 90 days after renewal close once account health has been confirmed stable')
            WHEN 'CSM Risk Review'::text THEN jsonb_build_array('Transition to standard health maintenance cadence once support ticket volume drops to 2 or fewer and NPS recovers above 7', 'Schedule a 60-day follow-up NPS survey to validate improvement and confirm the account champion''s satisfaction', 'Document root cause learnings from this risk review in the account CRM and update the CSM playbook for similar segments', 'Determine if expansion conversation can resume after 30 consecutive days of stable health signals')
            WHEN 'Renewal Readiness Review'::text THEN jsonb_build_array('Complete all renewal paperwork and update the CRM opportunity to Closed-Won within 48 hours of receiving the signature', 'Initiate a post-renewal success onboarding cadence — schedule a 30-day value check-in for the new contract period', 'Begin a proactive expansion discovery conversation 30 days after renewal close while engagement momentum is high', 'Document the renewal readiness process outcome and note any friction points to improve future renewal cycles')
            WHEN 'Renewal Risk Review'::text THEN jsonb_build_array('If renewal is achieved, transition immediately to health maintenance mode and set a 30-day post-renewal check-in', 'If renewal remains at risk, escalate to Executive Renewal Save Plan and assign executive ownership within 48 hours', 'Document all renewal risk factors and mitigation actions in the account CRM for future reference', 'Assess whether the account is a candidate for proactive expansion discussion 60 days after risk resolution')
            WHEN 'Renewal and Expansion Review'::text THEN jsonb_build_array('Close renewal documentation within 48 hours of signature and update the CRM opportunity to Closed-Won', 'Formalize the expansion opportunity as a separate CRM pipeline item within 30 days of renewal close', 'Begin formal expansion scoping after renewal is signed — do not conflate the two commercial timelines', 'Schedule a 60-day post-renewal expansion check-in to maintain momentum and advance the upsell motion')
            WHEN 'Expansion Discovery'::text THEN jsonb_build_array('Create a formal expansion opportunity in CRM within 5 days of the discovery call conclusion', 'Schedule a product demo targeting the new use cases or departments identified during discovery', 'Move to an AE-led commercial discovery motion within 30 days and confirm expansion ACV estimate', (('Coordinate with '::text || suggested_owner_role) || ' to align expansion timeline with renewal cycle to avoid deal conflict'::text))
            WHEN 'Expansion Nurture'::text THEN jsonb_build_array('Graduate to formal Expansion Discovery motion when expansion score crosses 65 or champion initiates commercial conversation', 'Share quarterly business value updates with the champion to maintain expansion mindshare during the nurture period', 'Strengthen internal champion by inviting them to a product advisory session or customer council if available', 'Coordinate with AE to ensure expansion opportunity is pre-staged in CRM and ready for fast conversion to discovery')
            WHEN 'Maintain Account Health'::text THEN jsonb_build_array('Schedule a quarterly business review (QBR) to reinforce value delivered and identify new goals for the coming quarter', 'Monitor expansion score monthly — initiate a formal nurture motion if it rises above 60 for two consecutive months', 'Confirm renewal is on track at the 90-day checkpoint and surface any early contract or pricing questions', (('Document account health trajectory in CRM and flag any signal changes to '::text || suggested_owner_role) || ' proactively'::text))
            WHEN 'Monitor Account'::text THEN jsonb_build_array('Reassess monitoring posture monthly — determine if signals warrant escalation to active CSM engagement', 'Escalate to CSM Risk Review immediately if health score drops below 50 or support tickets exceed 5 in a single month', 'Confirm account owner engagement at each 30-day interval — ensure no champion or budget changes go undetected', 'Close all overdue actions before the next monitoring cycle to avoid compounding backlog and missed signals')
            WHEN 'Renewal Monitoring'::text THEN jsonb_build_array('Complete all renewal administrative tasks (DocuSign, Salesforce update, billing confirmation) within 5 days of signature', 'Schedule a post-renewal health check at 30 days into the new contract to establish a clean baseline', 'Begin an expansion conversation 60 days after renewal close when the account is stable and champion engagement is fresh', 'Document the renewal monitoring outcome and note any late-stage friction for future proactive renewal cycles')
            ELSE jsonb_build_array((('Complete the initial action plan review with '::text || (account_owner)::text) || ' and confirm ownership assignments'::text), 'Schedule a 30-day follow-up to assess whether action has improved risk, health, or expansion signals', 'Update CRM with action plan details and ensure the next checkpoint date is logged and assigned', (('Escalate to '::text || suggested_owner_role) || ' if account signals deteriorate before the 30-day checkpoint'::text))
        END AS phase_2_next_steps,
        CASE recommended_action_type
            WHEN 'Immediate Churn Intervention'::text THEN jsonb_build_array((('Churn risk score drops from '::text || (computed_churn_risk_score)::text) || ' to below 40 within 60 days'::text), (('Health score improves from '::text || (computed_health_score)::text) || ' to above 60 within 60 days'::text), 'Support ticket volume falls to 2 or fewer per 30-day period within the first intervention cycle', (('Monthly usage events increase by 30% or more from the current baseline of '::text || (usage_events_last_30_days)::text) || ' events'::text))
            WHEN 'Executive Renewal Save Plan'::text THEN jsonb_build_array('Renewal contract signed before the expiration date with no gap in coverage', 'Churn risk score reduces by at least 15 points within 30 days of renewal close', 'Executive sponsor engagement confirmed with at least one recorded meeting or written communication', 'CRM renewal opportunity updated to Closed-Won within 48 hours of contract execution')
            WHEN 'CSM Risk Review'::text THEN jsonb_build_array((('NPS score recovers from '::text || (nps_score)::text) || ' to 7 or above within 30 days of intervention'::text), 'Support ticket volume drops to 2 or fewer per 30-day period within the first review cycle', ('Usage events remain stable or improve month-over-month from the current baseline of '::text || (usage_events_last_30_days)::text), 'CSM check-in completed, documented in CRM, and champion confirms satisfaction improvement')
            WHEN 'Renewal Readiness Review'::text THEN jsonb_build_array('Renewal signed on time with no last-minute escalations or contract terms disputes', 'All support issues resolved before the formal renewal discussion begins', 'Economic buyer and champion both engaged and confirmed as aligned on terms and timeline', 'CRM renewal opportunity updated to Closed-Won within 48 hours of signature')
            WHEN 'Renewal Risk Review'::text THEN jsonb_build_array('Renewal achieved without extension or gap — contract executed on schedule', 'Churn risk score improves by 10 or more points within 30 days of the risk review completion', 'All identified renewal risk factors are documented with named owners and resolution dates', 'At-risk signals addressed within a 14-day action window with visible progress updates')
            WHEN 'Renewal and Expansion Review'::text THEN jsonb_build_array('Renewal closed before the contract end date — no coverage gap or last-minute delay', 'Expansion opportunity formally created in CRM within 30 days of renewal close', 'Both commercial motions aligned on timeline — renewal and expansion champion confirmed as the same contact', 'Combined ARR impact documented and reported to leadership within 5 days of contract execution')
            WHEN 'Expansion Discovery'::text THEN jsonb_build_array('Discovery call completed within 30 days of initiating the expansion motion', 'Qualified expansion opportunity created in CRM with AE assigned and estimated ACV documented', 'Stakeholder map completed — budget holder, champion, and technical evaluator all identified', 'Expansion scenario defined with at least one specific use case or product tier confirmed as in-scope')
            WHEN 'Expansion Nurture'::text THEN jsonb_build_array(('Expansion score grows by 5 or more points over the 60-day nurture period from the current '::text || (computed_expansion_score)::text), 'At least one discovery checkpoint or value conversation completed during the nurture cycle', 'Champion engagement maintained with monthly touchpoints — no lapse in contact longer than 35 days', (('NPS maintained at '::text || (nps_score)::text) || ' or above throughout the entire nurture period'::text))
            WHEN 'Maintain Account Health'::text THEN jsonb_build_array(('Health score maintained above 65 throughout the current quarter — current baseline is '::text || (computed_health_score)::text), 'No support ticket spikes above 3 per 30-day period for the duration of the maintenance cadence', 'NPS at or above 7 at the next scheduled satisfaction survey', 'No escalation to risk or intervention status during the maintenance period')
            WHEN 'Monitor Account'::text THEN jsonb_build_array('No deterioration in health score, usage events, or support volume during the 30-day monitoring cycle', ('All overdue actions cleared within the current quarter — current backlog is '::text || (overdue_action_count)::text), 'Clear escalation criteria documented in CRM and actively understood by the account owner', '30-day monitoring checkpoint completed on schedule with no negative flags or unplanned escalations')
            WHEN 'Renewal Monitoring'::text THEN jsonb_build_array('Renewal executed on schedule with no surprises, pricing disputes, or contract delays', 'No new risk signals introduced in the final 30 days of the contract period', 'All renewal paperwork and billing tasks completed within 5 business days of signature', 'Health score maintained at 60 or above through the close of the renewal monitoring period')
            ELSE jsonb_build_array((('Account action plan reviewed and confirmed with '::text || (account_owner)::text) || ' within 1 week'::text), 'Top risk or opportunity signal addressed with a documented owner and target date within 2 weeks', 'CRM account notes updated with current status, next steps, and escalation threshold by end of current cycle', 'No unplanned escalations during the current action period — all risks surface through the checkpoint cadence')
        END AS success_metrics,
        CASE recommended_action_type
            WHEN 'Immediate Churn Intervention'::text THEN 'Escalate to VP of Customer Success or executive leadership if: (1) account owner cannot confirm champion engagement within 48 hours; (2) support ticket volume exceeds 12 in any 30-day window; (3) churn risk score rises above 75; or (4) customer indicates intent to cancel in writing.'::text
            WHEN 'Executive Renewal Save Plan'::text THEN 'Escalate to C-level leadership if: (1) economic buyer disengages or becomes unresponsive for more than 5 business days; (2) the renewal timeline compresses past the current target date; (3) a competitive vendor is confirmed in active evaluation; or (4) contract value is being renegotiated downward by more than 20%.'::text
            WHEN 'CSM Risk Review'::text THEN 'Escalate to CSM Manager or VP of Customer Success if: (1) NPS score drops below 4; (2) support ticket volume exceeds 8 in any 30-day period; (3) the account champion confirms intent to evaluate alternatives; or (4) the risk score increases by more than 10 points during the review cycle.'::text
            WHEN 'Renewal Readiness Review'::text THEN 'Escalate to Account Executive and CSM Manager if: (1) the economic buyer is unreachable after two outreach attempts within 14 days; (2) renewal terms are contested or a formal redline is requested; (3) a new competitive vendor is confirmed in evaluation; or (4) internal renewal approval is delayed beyond the target date.'::text
            WHEN 'Renewal Risk Review'::text THEN 'Escalate to VP of Sales or VP of Customer Success if: (1) the renewal deadline is less than 15 days away with no confirmed intent from the economic buyer; (2) churn risk score exceeds 60; (3) confirmed champion turnover during the review period; or (4) the account submits a formal contract redline or legal request.'::text
            WHEN 'Renewal and Expansion Review'::text THEN 'Escalate to AE Manager and CSM Manager if: (1) the renewal and expansion timelines conflict and create customer confusion; (2) expansion budget is not confirmed within 30 days of the review; (3) the core renewal is at risk due to commercial disagreement during the combined review; or (4) the account champion changes during the active review period.'::text
            WHEN 'Expansion Discovery'::text THEN 'Escalate to AE Manager if: (1) the expansion budget holder is unresponsive after two outreach attempts; (2) the expansion scenario requires a custom contract, new module, or non-standard commercial terms outside AE scope; or (3) a competitive risk is flagged by the champion or economic buyer during discovery.'::text
            WHEN 'Expansion Nurture'::text THEN 'Escalate to CSM leadership if: (1) expansion score drops below 50 during the nurture period; (2) the champion disengages or there is no response after two consecutive monthly touchpoints; or (3) health score falls below 60 — pause the expansion nurture and shift focus to risk stabilization first.'::text
            WHEN 'Maintain Account Health'::text THEN 'Escalate to CSM or Account Manager if: (1) health score drops below 55 in any review cycle; (2) support ticket volume rises above 4 in a single month; (3) NPS drops below 6 at the next survey; or (4) overdue actions exceed 3 without a documented resolution plan.'::text
            WHEN 'Monitor Account'::text THEN 'Escalate to CSM Risk Review if: (1) health score falls below 50 in any monitoring cycle; (2) support tickets exceed 5 in a single month; (3) usage drops below 10 events in any 30-day window; or (4) the account owner reports a champion change, budget freeze, or competitive conversation.'::text
            WHEN 'Renewal Monitoring'::text THEN 'Escalate to Renewal Risk Review immediately if: (1) the champion becomes unresponsive within 30 days of the renewal date; (2) any new commercial objection or pricing concern is raised; (3) support issues spike in the final 30 days of the contract period; or (4) renewal sign-off is delayed past the target execution date.'::text
            ELSE (('Escalate to '::text || suggested_owner_role) || ' if: (1) health score drops below 50; (2) churn risk score rises above 60; (3) support ticket volume exceeds 6 in any 30-day period; or (4) the account owner confirms any champion change, budget risk, or competitive threat.'::text)
        END AS escalation_guidance,
        CASE recommended_action_type
            WHEN 'Immediate Churn Intervention'::text THEN
            CASE
                WHEN (very_high_churn AND renewal_near) THEN 'CRITICAL — within 24 hours'::text
                ELSE 'Immediate — within 48 hours'::text
            END
            WHEN 'Executive Renewal Save Plan'::text THEN
            CASE
                WHEN renewal_imminent THEN 'URGENT — within 24 hours'::text
                WHEN renewal_near THEN 'Urgent — within 1 week'::text
                ELSE 'High priority — within 2 weeks'::text
            END
            WHEN 'CSM Risk Review'::text THEN
            CASE
                WHEN (low_nps AND high_support) THEN 'Urgent — within 1 week'::text
                ELSE 'Within 1–2 weeks'::text
            END
            WHEN 'Renewal Readiness Review'::text THEN
            CASE
                WHEN renewal_imminent THEN 'URGENT — this week'::text
                WHEN renewal_near THEN 'Within 2 weeks'::text
                ELSE 'Within 30 days'::text
            END
            WHEN 'Renewal Risk Review'::text THEN
            CASE
                WHEN (renewal_imminent AND very_high_churn) THEN 'CRITICAL — within 24 hours'::text
                WHEN renewal_imminent THEN 'Immediate — within 48 hours'::text
                ELSE 'Within 1 week'::text
            END
            WHEN 'Renewal and Expansion Review'::text THEN
            CASE
                WHEN renewal_imminent THEN 'URGENT — this week'::text
                WHEN renewal_near THEN 'Within 2 weeks'::text
                ELSE 'This quarter'::text
            END
            WHEN 'Expansion Discovery'::text THEN 'Within 30 days'::text
            WHEN 'Expansion Nurture'::text THEN '30–60 day nurture cycle'::text
            WHEN 'Maintain Account Health'::text THEN 'Ongoing — quarterly cadence'::text
            WHEN 'Monitor Account'::text THEN '30-day monitoring cycle'::text
            WHEN 'Renewal Monitoring'::text THEN
            CASE
                WHEN renewal_imminent THEN 'Within 48 hours of renewal date'::text
                ELSE 'Monthly checkpoint'::text
            END
            ELSE 'Review within 2 weeks'::text
        END AS timeline_label,
    'action_playbook_v1'::text AS playbook_version
   FROM signals;


--
-- Name: account_intelligence_view; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.account_intelligence_view AS
 SELECT rae.account_id,
    rae.company_name,
    rae.industry,
    rae.segment,
    rae.company_size,
    rae.annual_recurring_revenue,
    rae.plan_type,
    rae.customer_stage,
    rae.account_owner,
    rae.renewal_date,
    rae.days_until_renewal,
    rae.usage_events_last_30_days,
    rae.active_users_last_30_days,
    rae.support_tickets_last_30_days,
    rae.nps_score,
    rae.overdue_action_count,
    rae.open_pipeline_value,
    rae.computed_health_score,
    rae.computed_churn_risk_score,
    rae.computed_expansion_score,
    rae.risk_level_v2 AS risk_level,
    rae.expansion_level_v2 AS expansion_level,
    rae.customer_priority_tier_v3 AS customer_priority_tier,
    rae.recommended_action_type,
    rae.recommended_action_priority,
    rae.recommended_next_action,
    rae.suggested_owner_role,
    (rae.recommended_due_date)::date AS recommended_due_date,
    rae.recommendation_reason,
        CASE
            WHEN (rae.computed_health_score >= (80)::numeric) THEN 'Healthy'::text
            WHEN (rae.computed_health_score >= (60)::numeric) THEN 'Stable'::text
            WHEN (rae.computed_health_score >= (40)::numeric) THEN 'Weak'::text
            ELSE 'Unhealthy'::text
        END AS health_status,
        CASE
            WHEN (rae.computed_churn_risk_score >= (60)::numeric) THEN 'Immediate Risk'::text
            WHEN (rae.computed_churn_risk_score >= (50)::numeric) THEN 'Elevated Risk'::text
            WHEN (rae.computed_churn_risk_score >= (40)::numeric) THEN 'Watch'::text
            ELSE 'Normal'::text
        END AS churn_status,
        CASE
            WHEN (rae.computed_expansion_score >= (75)::numeric) THEN 'Expansion Ready'::text
            WHEN (rae.computed_expansion_score >= (50)::numeric) THEN 'Expansion Possible'::text
            ELSE 'No Clear Expansion Signal'::text
        END AS expansion_status,
        CASE
            WHEN (rae.customer_priority_tier_v3 ~~ 'Tier 1%'::text) THEN 'Save'::text
            WHEN (rae.customer_priority_tier_v3 ~~ '%Churn%'::text) THEN 'Recover'::text
            WHEN (rae.customer_priority_tier_v3 ~~ '%Renewal%'::text) THEN 'Renewal'::text
            WHEN (rae.customer_priority_tier_v3 ~~ '%Expansion%'::text) THEN 'Expand'::text
            WHEN (rae.customer_priority_tier_v3 ~~ '%Maintain%'::text) THEN 'Maintain'::text
            ELSE 'Monitor'::text
        END AS primary_business_motion,
        CASE
            WHEN (rae.recommended_action_priority = 'Critical'::text) THEN 1
            WHEN (rae.recommended_action_priority = 'High'::text) THEN 2
            WHEN (rae.recommended_action_priority = 'Medium'::text) THEN 3
            ELSE 4
        END AS dashboard_priority_rank,
        CASE
            WHEN (rae.recommended_action_priority = 'Critical'::text) THEN true
            WHEN (rae.risk_level_v2 = ANY (ARRAY['Critical Risk'::text, 'High Risk'::text])) THEN true
            WHEN (rae.days_until_renewal <= 30) THEN true
            WHEN ((rae.days_until_renewal <= 60) AND (rae.computed_churn_risk_score >= (40)::numeric)) THEN true
            WHEN (rae.overdue_action_count >= 3) THEN true
            ELSE false
        END AS needs_human_review,
        CASE
            WHEN (rae.recommended_action_priority = 'Critical'::text) THEN 'Critical recommended action requires leadership review.'::text
            WHEN (rae.risk_level_v2 = 'Critical Risk'::text) THEN 'Account has critical churn risk.'::text
            WHEN (rae.risk_level_v2 = 'High Risk'::text) THEN 'Account has high churn risk.'::text
            WHEN ((rae.days_until_renewal <= 30) AND (rae.computed_churn_risk_score >= (40)::numeric)) THEN 'Account is within 30 days of renewal and has meaningful churn risk.'::text
            WHEN (rae.days_until_renewal <= 30) THEN 'Account is within 30 days of renewal.'::text
            WHEN ((rae.days_until_renewal <= 60) AND (rae.computed_churn_risk_score >= (40)::numeric)) THEN 'Account is within 60 days of renewal and has meaningful churn risk.'::text
            WHEN (rae.overdue_action_count >= 3) THEN concat('Account has ', rae.overdue_action_count, ' overdue actions.')
            ELSE 'No manual review required based on current rules.'::text
        END AS human_review_reason,
    concat(rae.company_name, ' is a ', rae.segment, ' ', rae.industry, ' account on the ', rae.plan_type, ' plan. Health score is ', rae.computed_health_score, ', churn risk score is ', rae.computed_churn_risk_score, ', expansion score is ', rae.computed_expansion_score, '. The account is categorized as ', rae.risk_level_v2, ' with ', rae.expansion_level_v2, '. Recommended action: ', rae.recommended_action_type, '. Reason: ', rae.recommendation_reason) AS ai_explanation_context,
    'phase_14_v3_dashboard_ready_account_intelligence_with_review_reason'::text AS intelligence_view_version,
    rae.company_name AS account_name,
    pbook.immediate_next_steps,
    pbook.phase_2_next_steps,
    pbook.success_metrics,
    pbook.escalation_guidance,
    pbook.timeline_label,
    pbook.playbook_version
   FROM (core.recommended_actions_engine rae
     LEFT JOIN core.account_action_playbook pbook ON (((rae.account_id)::text = (pbook.account_id)::text)));


--
-- Name: dashboard_action_summary; Type: VIEW; Schema: core; Owner: -
--

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


--
-- Name: dashboard_kpis; Type: VIEW; Schema: core; Owner: -
--

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


--
-- Name: dashboard_owner_workload; Type: VIEW; Schema: core; Owner: -
--

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
  ORDER BY (count(*) FILTER (WHERE (recommended_action_priority = 'Critical'::text))) DESC, (count(*) FILTER (WHERE (recommended_action_priority = 'High'::text))) DESC, (count(*) FILTER (WHERE (needs_human_review = true))) DESC, (count(*)) DESC;


--
-- Name: dashboard_risk_summary; Type: VIEW; Schema: core; Owner: -
--

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


--
-- Name: experiments; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.experiments (
    experiment_id character varying(50) NOT NULL,
    experiment_name character varying(255),
    hypothesis text,
    target_accounts integer,
    success_metric character varying(255),
    result text,
    decision character varying(100),
    created_at timestamp without time zone
);


--
-- Name: system_logs; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.system_logs (
    log_id character varying(50) NOT NULL,
    log_type character varying(100),
    component character varying(100),
    status character varying(100),
    message text,
    created_at timestamp without time zone
);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (account_id);


--
-- Name: actions actions_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.actions
    ADD CONSTRAINT actions_pkey PRIMARY KEY (action_id);


--
-- Name: crm_opportunities crm_opportunities_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.crm_opportunities
    ADD CONSTRAINT crm_opportunities_pkey PRIMARY KEY (opportunity_id);


--
-- Name: customer_engagement customer_engagement_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_engagement
    ADD CONSTRAINT customer_engagement_pkey PRIMARY KEY (engagement_id);


--
-- Name: experiments experiments_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.experiments
    ADD CONSTRAINT experiments_pkey PRIMARY KEY (experiment_id);


--
-- Name: product_usage_events product_usage_events_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_usage_events
    ADD CONSTRAINT product_usage_events_pkey PRIMARY KEY (event_id);


--
-- Name: score_history score_history_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.score_history
    ADD CONSTRAINT score_history_pkey PRIMARY KEY (score_id);


--
-- Name: system_logs system_logs_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.system_logs
    ADD CONSTRAINT system_logs_pkey PRIMARY KEY (log_id);


--
-- Name: idx_actions_account_id; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX idx_actions_account_id ON core.actions USING btree (account_id);


--
-- Name: idx_actions_priority; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX idx_actions_priority ON core.actions USING btree (priority);


--
-- Name: idx_actions_status_due_date; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX idx_actions_status_due_date ON core.actions USING btree (status, due_date);


--
-- Name: idx_crm_opportunities_account_id; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX idx_crm_opportunities_account_id ON core.crm_opportunities USING btree (account_id);


--
-- Name: idx_crm_opportunities_account_stage; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX idx_crm_opportunities_account_stage ON core.crm_opportunities USING btree (account_id, pipeline_stage);


--
-- Name: idx_crm_opportunities_expected_close_date; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX idx_crm_opportunities_expected_close_date ON core.crm_opportunities USING btree (expected_close_date);


--
-- Name: idx_customer_engagement_account_id; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX idx_customer_engagement_account_id ON core.customer_engagement USING btree (account_id);


--
-- Name: idx_customer_engagement_last_touch_date; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX idx_customer_engagement_last_touch_date ON core.customer_engagement USING btree (last_touch_date);


--
-- Name: idx_product_usage_events_account_id; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX idx_product_usage_events_account_id ON core.product_usage_events USING btree (account_id);


--
-- Name: idx_product_usage_events_account_timestamp; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX idx_product_usage_events_account_timestamp ON core.product_usage_events USING btree (account_id, event_timestamp);


--
-- Name: idx_product_usage_events_event_type; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX idx_product_usage_events_event_type ON core.product_usage_events USING btree (event_type);


--
-- Name: idx_score_history_account_calculated_at; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX idx_score_history_account_calculated_at ON core.score_history USING btree (account_id, calculated_at);


--
-- Name: idx_score_history_account_id; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX idx_score_history_account_id ON core.score_history USING btree (account_id);


--
-- Name: idx_system_logs_status_created_at; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX idx_system_logs_status_created_at ON core.system_logs USING btree (status, created_at);


--
-- Name: actions fk_actions_account; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.actions
    ADD CONSTRAINT fk_actions_account FOREIGN KEY (account_id) REFERENCES core.accounts(account_id) ON DELETE CASCADE;


--
-- Name: crm_opportunities fk_crm_opportunities_account; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.crm_opportunities
    ADD CONSTRAINT fk_crm_opportunities_account FOREIGN KEY (account_id) REFERENCES core.accounts(account_id) ON DELETE CASCADE;


--
-- Name: customer_engagement fk_customer_engagement_account; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_engagement
    ADD CONSTRAINT fk_customer_engagement_account FOREIGN KEY (account_id) REFERENCES core.accounts(account_id) ON DELETE CASCADE;


--
-- Name: product_usage_events fk_product_usage_events_account; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_usage_events
    ADD CONSTRAINT fk_product_usage_events_account FOREIGN KEY (account_id) REFERENCES core.accounts(account_id) ON DELETE CASCADE;


--
-- Name: score_history fk_score_history_account; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.score_history
    ADD CONSTRAINT fk_score_history_account FOREIGN KEY (account_id) REFERENCES core.accounts(account_id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--


