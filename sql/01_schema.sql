-- ============================================================
-- 01_schema.sql
-- Customer Revenue Intelligence Engine
--
-- Base schema: tables, primary keys, foreign keys, indexes.
-- Source of truth: deployment/schema_supabase_clean.sql
-- Production database: Supabase PostgreSQL
-- ============================================================

CREATE SCHEMA IF NOT EXISTS core;

-- ============================================================
-- BASE TABLES
-- ============================================================

CREATE TABLE core.accounts (
    account_id          character varying(50)  NOT NULL,
    company_name        character varying(255) NOT NULL,
    industry            character varying(100),
    segment             character varying(100),
    company_size        integer,
    annual_recurring_revenue numeric(12,2),
    plan_type           character varying(100),
    customer_stage      character varying(100),
    account_owner       character varying(255),
    contract_start_date date,
    renewal_date        date,
    created_at          timestamp without time zone,
    updated_at          timestamp without time zone
);

CREATE TABLE core.product_usage_events (
    event_id                 character varying(50)  NOT NULL,
    account_id               character varying(50)  NOT NULL,
    user_id                  character varying(100),
    event_type               character varying(100),
    feature_name             character varying(150),
    session_duration_minutes numeric(10,2),
    event_timestamp          timestamp without time zone
);

CREATE TABLE core.customer_engagement (
    engagement_id                character varying(50) NOT NULL,
    account_id                   character varying(50) NOT NULL,
    emails_opened                integer,
    emails_replied               integer,
    meetings_last_30_days        integer,
    support_tickets_last_30_days integer,
    nps_score                    integer,
    last_touch_date              date
);

CREATE TABLE core.crm_opportunities (
    opportunity_id       character varying(50)  NOT NULL,
    account_id           character varying(50)  NOT NULL,
    opportunity_type     character varying(100),
    pipeline_stage       character varying(100),
    amount               numeric(12,2),
    probability          integer,
    created_date         date,
    expected_close_date  date,
    last_activity_date   date
);

CREATE TABLE core.score_history (
    score_id     character varying(50) NOT NULL,
    account_id   character varying(50) NOT NULL,
    health_score numeric(5,2),
    churn_score  numeric(5,2),
    expansion_score numeric(5,2),
    score_reason text,
    calculated_at date
);

CREATE TABLE core.actions (
    action_id          character varying(50) NOT NULL,
    account_id         character varying(50) NOT NULL,
    recommended_action text,
    assigned_to        character varying(255),
    priority           character varying(50),
    status             character varying(50),
    due_date           date,
    completed_at       timestamp without time zone,
    outcome            text,
    created_at         timestamp without time zone
);

CREATE TABLE core.experiments (
    experiment_id   character varying(50)  NOT NULL,
    experiment_name character varying(255),
    hypothesis      text,
    target_accounts integer,
    success_metric  character varying(255),
    result          text,
    decision        character varying(100),
    created_at      timestamp without time zone
);

CREATE TABLE core.system_logs (
    log_id     character varying(50)  NOT NULL,
    log_type   character varying(100),
    component  character varying(100),
    status     character varying(100),
    message    text,
    created_at timestamp without time zone
);

-- ============================================================
-- PRIMARY KEYS
-- ============================================================

ALTER TABLE ONLY core.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (account_id);

ALTER TABLE ONLY core.actions
    ADD CONSTRAINT actions_pkey PRIMARY KEY (action_id);

ALTER TABLE ONLY core.crm_opportunities
    ADD CONSTRAINT crm_opportunities_pkey PRIMARY KEY (opportunity_id);

ALTER TABLE ONLY core.customer_engagement
    ADD CONSTRAINT customer_engagement_pkey PRIMARY KEY (engagement_id);

ALTER TABLE ONLY core.experiments
    ADD CONSTRAINT experiments_pkey PRIMARY KEY (experiment_id);

ALTER TABLE ONLY core.product_usage_events
    ADD CONSTRAINT product_usage_events_pkey PRIMARY KEY (event_id);

ALTER TABLE ONLY core.score_history
    ADD CONSTRAINT score_history_pkey PRIMARY KEY (score_id);

ALTER TABLE ONLY core.system_logs
    ADD CONSTRAINT system_logs_pkey PRIMARY KEY (log_id);

-- ============================================================
-- FOREIGN KEY CONSTRAINTS
-- ============================================================

ALTER TABLE ONLY core.actions
    ADD CONSTRAINT fk_actions_account
    FOREIGN KEY (account_id) REFERENCES core.accounts(account_id) ON DELETE CASCADE;

ALTER TABLE ONLY core.crm_opportunities
    ADD CONSTRAINT fk_crm_opportunities_account
    FOREIGN KEY (account_id) REFERENCES core.accounts(account_id) ON DELETE CASCADE;

ALTER TABLE ONLY core.customer_engagement
    ADD CONSTRAINT fk_customer_engagement_account
    FOREIGN KEY (account_id) REFERENCES core.accounts(account_id) ON DELETE CASCADE;

ALTER TABLE ONLY core.product_usage_events
    ADD CONSTRAINT fk_product_usage_events_account
    FOREIGN KEY (account_id) REFERENCES core.accounts(account_id) ON DELETE CASCADE;

ALTER TABLE ONLY core.score_history
    ADD CONSTRAINT fk_score_history_account
    FOREIGN KEY (account_id) REFERENCES core.accounts(account_id) ON DELETE CASCADE;

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX idx_actions_account_id         ON core.actions USING btree (account_id);
CREATE INDEX idx_actions_priority           ON core.actions USING btree (priority);
CREATE INDEX idx_actions_status_due_date    ON core.actions USING btree (status, due_date);

CREATE INDEX idx_crm_opportunities_account_id          ON core.crm_opportunities USING btree (account_id);
CREATE INDEX idx_crm_opportunities_account_stage       ON core.crm_opportunities USING btree (account_id, pipeline_stage);
CREATE INDEX idx_crm_opportunities_expected_close_date ON core.crm_opportunities USING btree (expected_close_date);

CREATE INDEX idx_customer_engagement_account_id      ON core.customer_engagement USING btree (account_id);
CREATE INDEX idx_customer_engagement_last_touch_date ON core.customer_engagement USING btree (last_touch_date);

CREATE INDEX idx_product_usage_events_account_id        ON core.product_usage_events USING btree (account_id);
CREATE INDEX idx_product_usage_events_account_timestamp ON core.product_usage_events USING btree (account_id, event_timestamp);
CREATE INDEX idx_product_usage_events_event_type        ON core.product_usage_events USING btree (event_type);

CREATE INDEX idx_score_history_account_id           ON core.score_history USING btree (account_id);
CREATE INDEX idx_score_history_account_calculated_at ON core.score_history USING btree (account_id, calculated_at);

CREATE INDEX idx_system_logs_status_created_at ON core.system_logs USING btree (status, created_at);