-- ============================================================
-- 04_action_playbook.sql
-- Customer Revenue Intelligence Engine
--
-- Deterministic action playbook layer.
-- Converts scoring engine output into structured action plans:
--   - recommended action type and priority
--   - suggested owner role and due date
--   - immediate next steps (signal-conditional, 5 steps per account)
--   - phase 2 follow-up actions
--   - success metrics
--   - escalation guidance
--
-- Views (in dependency order):
--   recommended_actions_engine   (action type, priority, owner, due date)
--   account_action_playbook      (immediate steps, phase 2, metrics, escalation)
--   account_intelligence_view    (production view -- used by all API endpoints)
-- ============================================================
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
                WHEN (high_support AND low_usage) THEN jsonb_build_array((('Convene emergency CSM + leadership call within 24 hours to review '::text || (support_tickets_last_30_days)::text) || ' open support tickets and align on a resolution SLA'::text), 'Assign a dedicated technical resource to diagnose and close the top blocking support issues this week', (('Map inactive user groups â€” only '::text || (active_users_last_30_days)::text) || ' active users recorded â€” identify specific adoption blockers by team or role'::text), (('Schedule executive sponsor outreach from '::text || suggested_owner_role) || ' within 48 hours to express commitment and set recovery expectations'::text), 'Initiate a formal churn save plan with defined milestones, owners, and a 30-day check-in cadence')
                WHEN high_support THEN jsonb_build_array((('Escalate '::text || (support_tickets_last_30_days)::text) || ' open support tickets to engineering leadership for prioritized triage within 24 hours'::text), 'Schedule an executive check-in with the account sponsor to address service quality concerns directly', 'Assign a dedicated CSM to conduct a weekly support ticket review until volume drops below 2', 'Audit all open issues for root cause patterns and deliver a written resolution plan to the customer', (('Initiate churn save motion â€” set an internal countdown to renewal in '::text || (days_until_renewal)::text) || ' days with named accountable owners'::text))
                WHEN low_usage THEN jsonb_build_array((((('Immediately identify which user groups have gone inactive â€” currently only '::text || (active_users_last_30_days)::text) || ' active users with '::text) || (usage_events_last_30_days)::text) || ' events in 30 days'::text), 'Schedule a product adoption recovery session with key customer stakeholders within 1 week', 'Deliver targeted enablement to inactive users â€” identify top 3 unmet use cases as adoption starting points', 'Set a weekly usage recovery checkpoint and define a minimum viable usage KPI with the account champion', 'Flag for executive escalation if usage does not recover by at least 30% within 2 weeks of intervention')
                ELSE jsonb_build_array((('Open a formal churn intervention plan â€” assign ownership to '::text || suggested_owner_role) || ' immediately'::text), ((((('Review all active support tickets ('::text || (support_tickets_last_30_days)::text) || ') and usage signals ('::text) || (usage_events_last_30_days)::text) || ' events) with '::text) || (account_owner)::text), 'Schedule an executive sponsor call to surface the top blockers and re-establish shared account goals', (('Audit the renewal risk landscape with '::text || (days_until_renewal)::text) || ' days remaining â€” define recovery milestones and ownership chain'::text), 'Document the churn risk rationale and align internally on a save vs. managed churn decision before the next checkpoint')
            END
            WHEN 'Executive Renewal Save Plan'::text THEN
            CASE
                WHEN renewal_imminent THEN jsonb_build_array((('URGENT: Initiate executive-to-executive outreach today â€” renewal is in only '::text || (days_until_renewal)::text) || ' days'::text), 'Deliver a compelling ROI summary and business value review to the economic buyer this week â€” no delay', (('Resolve all open support issues ('::text || (support_tickets_last_30_days)::text) || ' tickets) before the renewal conversation begins'::text), 'Prepare commercial terms options â€” include multi-year and step-down scenarios for negotiation flexibility', 'Loop in AE and CSM leadership to align on negotiation floor, escalation authority, and close strategy')
                WHEN renewal_near THEN jsonb_build_array((('Schedule an executive sponsor meeting within 2 weeks â€” renewal is in '::text || (days_until_renewal)::text) || ' days'::text), 'Prepare an account health narrative showing usage trends, support resolution history, and ROI delivered to date', 'Identify renewal blockers: pricing concerns, product gaps, champion turnover, or active competitive evaluation', 'Develop two contract scenarios â€” status quo renewal and expansion upsell â€” to present at the executive meeting', (('Assign '::text || suggested_owner_role) || ' as deal owner and confirm the CRM renewal opportunity is fully updated'::text))
                ELSE jsonb_build_array('Assign an executive sponsor and schedule a strategic account review this quarter', ((((('Build the renewal dossier: health score '::text || (computed_health_score)::text) || ', churn risk '::text) || (computed_churn_risk_score)::text) || ', support tickets '::text) || (support_tickets_last_30_days)::text), 'Identify the top 3 renewal risk factors and document concrete mitigation actions with named owners', 'Coordinate with AE to align commercial strategy with the account health trajectory', 'Establish a monthly executive renewal checkpoint cadence and confirm all stakeholder contacts in CRM')
            END
            WHEN 'CSM Risk Review'::text THEN
            CASE
                WHEN (high_support AND low_nps) THEN jsonb_build_array((('Schedule an urgent CSM-led support triage â€” review all '::text || (support_tickets_last_30_days)::text) || ' tickets with the account team and set resolution SLAs today'::text), ('Conduct a dedicated NPS recovery conversation â€” understand what specifically drove the score of '::text || (nps_score)::text), 'Escalate the top 3 unresolved issues to engineering leadership and commit to customer-facing SLA dates', 'Deliver a written service recovery summary to the account champion within 5 business days', 'Flag for escalation to VP of Customer Success if ticket volume or NPS does not improve within 30 days')
                WHEN low_nps THEN jsonb_build_array((('Initiate an NPS recovery review â€” current score is '::text || (nps_score)::text) || ', target is 7 or above'::text), 'Contact all detractor contacts individually within 1 week to surface specific satisfaction drivers', 'Prepare a 30-day improvement action plan tied directly to the account''s stated feedback themes', 'Schedule a follow-up CSM check-in at day 14 to validate that concerns have been acknowledged and acted upon', (('Escalate to '::text || suggested_owner_role) || ' if the NPS score does not recover above 6 within the quarter'::text))
                WHEN high_support THEN jsonb_build_array((('Assign a dedicated CSM to manage '::text || (support_tickets_last_30_days)::text) || ' open tickets with a weekly review cycle'::text), 'Categorize all tickets by severity and assign engineering leads for each critical or blocking issue', 'Schedule bi-weekly customer check-ins until support ticket volume drops to 2 or fewer per month', 'Document root causes across all open tickets and share a written resolution plan with the account champion', 'Flag account for potential churn risk escalation if ticket volume remains above 3 in the next 30-day cycle')
                ELSE jsonb_build_array(('Schedule a standard CSM risk check-in within 2 weeks â€” owner is '::text || (account_owner)::text), (((('Review current usage levels ('::text || (usage_events_last_30_days)::text) || ' events) and active user engagement ('::text) || (active_users_last_30_days)::text) || ' users)'::text), 'Identify the top 2 account risk signals and document findings in CRM with action owner assignments', 'Clarify renewal intent and surface any contract terms, product, or satisfaction concerns', (('Determine whether account risk warrants escalation to '::text || suggested_owner_role) || ' or can be resolved at the CSM level'::text))
            END
            WHEN 'Renewal Readiness Review'::text THEN
            CASE
                WHEN renewal_imminent THEN jsonb_build_array((('URGENT: Renewal is in '::text || (days_until_renewal)::text) || ' days â€” complete all renewal readiness tasks this week without exception'::text), 'Send the final renewal proposal to the economic buyer and confirm all decision-making contacts today', (('Confirm all open support issues ('::text || (support_tickets_last_30_days)::text) || ' tickets) are resolved or have a committed resolution timeline before the renewal call'::text), 'Obtain verbal or written renewal intent from the account champion before end of this business week', (('Engage '::text || suggested_owner_role) || ' immediately to handle any last-minute objections or commercial terms questions'::text))
                WHEN renewal_near THEN jsonb_build_array((('Begin a formal renewal readiness review this week â€” '::text || (days_until_renewal)::text) || ' days remain on the contract'::text), 'Validate current usage trends and adoption health metrics to support the renewal value narrative', 'Survey the economic buyer on satisfaction and renewal intent â€” target outreach within 2 weeks', 'Confirm renewal decision contacts and economic buyer authority in CRM â€” update if any roles have changed', (('Resolve all outstanding support tickets ('::text || (support_tickets_last_30_days)::text) || ') before the formal renewal discussion begins'::text))
                ELSE jsonb_build_array((('Schedule a proactive renewal readiness call with '::text || (account_owner)::text) || ' and the account champion this month'::text), ((((('Build the account health story: health score '::text || (computed_health_score)::text) || ', usage events '::text) || (usage_events_last_30_days)::text) || ', NPS '::text) || (nps_score)::text), 'Identify any adoption gaps or pending feature requests that could create renewal friction if unaddressed', 'Confirm renewal decision authority and validate that all key stakeholders are currently engaged', 'Set renewal readiness checkpoints at 90, 60, and 30 days out with assigned owners for each milestone')
            END
            WHEN 'Renewal Risk Review'::text THEN
            CASE
                WHEN (renewal_imminent AND very_high_churn) THEN jsonb_build_array((((('CRITICAL: Renewal in '::text || (days_until_renewal)::text) || ' days â€” churn risk at '::text) || (computed_churn_risk_score)::text) || ', escalate to leadership immediately'::text), 'Convene a cross-functional save team â€” CSM, AE, and Support lead â€” within 48 hours', 'Deliver an urgent value-recovery briefing to the economic buyer before the renewal deadline', 'Prepare internal walk-away and managed-churn decision scenarios to inform negotiation strategy', (('Assign '::text || suggested_owner_role) || ' as executive deal lead and confirm escalation authority'::text))
                WHEN renewal_imminent THEN jsonb_build_array((('Immediate renewal risk escalation required â€” renewal is in '::text || (days_until_renewal)::text) || ' days'::text), 'Schedule an executive sponsor call to surface all renewal risk factors this week â€” no delay', (('Resolve open support tickets ('::text || (support_tickets_last_30_days)::text) || ') before the renewal meeting'::text), 'Confirm champion and economic buyer engagement â€” verify all renewal contacts are active and responsive', (('Provide a written renewal risk summary to '::text || suggested_owner_role) || ' within 24 hours of this review'::text))
                ELSE jsonb_build_array(((('Open a renewal risk review with '::text || (account_owner)::text) || ' â€” churn risk score is '::text) || (computed_churn_risk_score)::text), (((((('Map the top 3 renewal risk factors from signals: usage events ('::text || (usage_events_last_30_days)::text) || '), support tickets ('::text) || (support_tickets_last_30_days)::text) || '), NPS ('::text) || (nps_score)::text) || ')'::text), 'Define a 30-day risk mitigation plan with named owners and scheduled check-in dates', (('Engage '::text || suggested_owner_role) || ' to provide strategic renewal guidance and executive alignment'::text), 'Schedule a renewal risk board review if churn score exceeds 55 in the next 30 days')
            END
            WHEN 'Renewal and Expansion Review'::text THEN
            CASE
                WHEN (renewal_imminent AND strong_expansion) THEN jsonb_build_array((('Prioritize renewal close first â€” expansion must not create delay for the core contract expiring in '::text || (days_until_renewal)::text) || ' days'::text), 'Present a combined renewal + expansion proposal in a single executive review meeting this week', 'Confirm champion alignment on both the base renewal terms and the upsell opportunity before the meeting', (((('Engage AE to scope expansion options tied to usage signals: '::text || (usage_events_last_30_days)::text) || ' events, '::text) || (active_users_last_30_days)::text) || ' active users'::text), (('Have '::text || suggested_owner_role) || ' lead the commercial discussion â€” close the renewal before sequencing expansion'::text))
                ELSE jsonb_build_array('Schedule a combined renewal and expansion review meeting with the account champion and AE this quarter', ((((('Prepare the account health narrative â€” health score '::text || (computed_health_score)::text) || ', expansion score '::text) || (computed_expansion_score)::text) || ', NPS '::text) || (nps_score)::text), 'Identify 2â€“3 expansion use cases grounded in current product usage and the champion''s stated business goals', 'Present expansion options alongside the renewal proposal to capture full account commercial value in one motion', (('Have '::text || suggested_owner_role) || ' lead commercial terms â€” ensure both renewal and expansion close in the same cycle'::text))
            END
            WHEN 'Expansion Discovery'::text THEN
            CASE
                WHEN (strong_expansion AND high_usage) THEN jsonb_build_array((((('Open formal expansion discovery â€” expansion score is '::text || (computed_expansion_score)::text) || ' with '::text) || (usage_events_last_30_days)::text) || ' usage events showing strong product engagement'::text), 'Map all current stakeholders and identify expansion budget holders, champions, and technical evaluators', 'Conduct use-case discovery to identify 2â€“3 new deployment, seat expansion, or product tier scenarios', 'Review open pipeline value and coordinate with AE to confirm the expansion opportunity is scoped and qualified', 'Schedule the AE handoff meeting within 2 weeks to formalize the opportunity and move to a commercial motion')
                ELSE jsonb_build_array(('Initiate an expansion discovery conversation with the account champion â€” expansion score is '::text || (computed_expansion_score)::text), 'Map all active use cases and identify teams, departments, or workflows not yet using the product', 'Conduct a needs assessment to qualify the expansion scenario: seat growth, tier upgrade, or new module', 'Verify open pipeline value and coordinate with AE for discovery call scoping and opportunity qualification', (('Engage '::text || suggested_owner_role) || ' to support stakeholder access and provide strategic expansion framing'::text))
            END
            WHEN 'Expansion Nurture'::text THEN
            CASE
                WHEN (high_usage AND strong_expansion) THEN jsonb_build_array((('Leverage strong product engagement ('::text || (usage_events_last_30_days)::text) || ' events) as the lead proof point in the expansion conversation with the account champion'::text), 'Share a tailored ROI story showing business value delivered â€” connect directly to the expansion opportunity', 'Identify peer customer success stories or case studies relevant to the account''s expansion scenario', 'Schedule a product roadmap review to demonstrate how expansion-tier features address upcoming customer needs', 'Coordinate with AE to move the expansion nurture toward a qualified discovery call within the next 30 days')
                WHEN strong_expansion THEN jsonb_build_array((('Continue expansion nurture motion â€” expansion score is '::text || (computed_expansion_score)::text) || ' with positive directional signals'::text), 'Share a relevant peer customer success story to warm the expansion conversation with the champion', 'Schedule a quarterly business review (QBR) to deepen internal champion advocacy and executive visibility', 'Deliver value content: product updates, benchmark data, or adoption guides relevant to the account''s industry and goals', 'Set a 45-day nurture checkpoint to assess expansion readiness and initiate discovery if signals continue to improve')
                ELSE jsonb_build_array((('Maintain expansion nurture with regular value-add touchpoints â€” '::text || (usage_events_last_30_days)::text) || ' events this month'::text), 'Share industry benchmarks or feature adoption tips to drive incremental engagement and platform usage', 'Assess champion strength â€” determine if a new or additional expansion sponsor is needed for the motion', (('Log all engagement touchpoints in CRM and track NPS trend (currently '::text || (nps_score)::text) || ')'::text), 'Escalate to formal Expansion Discovery motion if expansion score rises above 65 in the next 60 days')
            END
            WHEN 'Maintain Account Health'::text THEN
            CASE
                WHEN has_overdue THEN jsonb_build_array((('Clear '::text || (overdue_action_count)::text) || ' overdue action(s) â€” assign owners and set completion dates by end of this week'::text), (('Schedule a standard account health check-in with '::text || (account_owner)::text) || ' to confirm all items are on track'::text), (('Verify usage levels are stable at '::text || (usage_events_last_30_days)::text) || ' events â€” confirm no decline from the prior month'::text), (('Confirm NPS is holding at '::text || (nps_score)::text) || ' â€” send a satisfaction pulse survey if it has not been checked in the last 60 days'::text), 'Document current account status in CRM and confirm the next scheduled touchpoint is booked')
                WHEN (high_usage AND healthy) THEN jsonb_build_array((('Account is healthy â€” maintain the current engagement cadence with '::text || (account_owner)::text) || ' and keep momentum'::text), (('Send a value milestone update to the champion: highlight '::text || (usage_events_last_30_days)::text) || ' product events this month as evidence of strong adoption'::text), (('Keep NPS trend positive at '::text || (nps_score)::text) || ' â€” schedule the next satisfaction survey at the 90-day interval'::text), (('Monitor expansion score ('::text || (computed_expansion_score)::text) || ') â€” begin a formal nurture motion if it crosses 60 in the next quarter'::text), 'Log account health summary in CRM and confirm no escalation triggers are currently active')
                ELSE jsonb_build_array(((('Schedule a routine health check-in with '::text || (account_owner)::text) || ' â€” current health score is '::text) || (computed_health_score)::text), (((('Confirm usage is stable: '::text || (usage_events_last_30_days)::text) || ' events and '::text) || (active_users_last_30_days)::text) || ' active users recorded this month'::text), (('Review any pending support items ('::text || (support_tickets_last_30_days)::text) || ' tickets) and confirm each has a clear resolution path and owner'::text), (('Verify NPS is at or above target (currently '::text || (nps_score)::text) || ') â€” send a check-in message to the champion if no recent sentiment data exists'::text), 'Update CRM notes with current account status and confirm the renewal timeline is on track')
            END
            WHEN 'Monitor Account'::text THEN
            CASE
                WHEN (has_overdue AND high_support) THEN jsonb_build_array((('Clear '::text || (overdue_action_count)::text) || ' overdue action(s) before adding any new monitoring tasks to the queue'::text), (('Review '::text || (support_tickets_last_30_days)::text) || ' open support tickets and confirm each has an assigned owner and a target resolution date'::text), (('Schedule a focused monitoring review with '::text || (account_owner)::text) || ' within 2 weeks'::text), 'Set automated alerts for key risk thresholds: usage below 10 events or support tickets above 8 per month', 'Evaluate whether account monitoring should escalate to CSM Risk Review given the combined signals')
                WHEN has_overdue THEN jsonb_build_array((('Resolve '::text || (overdue_action_count)::text) || ' overdue action(s) â€” assign each to a named owner with a clear due date this week'::text), 'Conduct a brief monitoring review to confirm health signals are stable and not trending downward', 'Set a 30-day monitoring checkpoint with defined escalation criteria in CRM', 'Update CRM account notes with current risk posture, monitoring status, and next review date', 'Evaluate whether current signals warrant a handoff to CSM Risk Review or Renewal Risk Review')
                ELSE jsonb_build_array('Maintain a passive monitoring stance â€” no immediate action required at this time', (((('Check usage trend weekly: currently '::text || (usage_events_last_30_days)::text) || ' events / '::text) || (active_users_last_30_days)::text) || ' active users in the last 30 days'::text), (('Review support ticket count ('::text || (support_tickets_last_30_days)::text) || ') â€” flag and escalate if it rises above 5 in any single month'::text), (('Confirm account owner ('::text || (account_owner)::text) || ') has active contact with the customer champion'::text), 'Set a 30-day review checkpoint and escalate to active management if any risk signal deteriorates')
            END
            WHEN 'Renewal Monitoring'::text THEN
            CASE
                WHEN renewal_imminent THEN jsonb_build_array((('Renewal is in '::text || (days_until_renewal)::text) || ' days â€” confirm all renewal readiness tasks are complete and no action items are outstanding'::text), 'Validate the renewal proposal has been received by the champion and is in the economic buyer''s hands', (('Conduct a final health review: confirm usage is stable at '::text || (usage_events_last_30_days)::text) || ' events and no new support issues have emerged'::text), 'Confirm that the renewal champion and economic buyer are fully aligned on terms, pricing, and timeline', 'Escalate to Renewal Risk Review immediately if any unresolved objections or blockers surface in this final window')
                ELSE jsonb_build_array((('Monitor renewal progress â€” '::text || (days_until_renewal)::text) || ' days remaining on the current contract'::text), (('Confirm the renewal timeline is on track with account owner '::text || (account_owner)::text) || ' via a brief check-in'::text), (((((('Check for any new risk signals: support tickets ('::text || (support_tickets_last_30_days)::text) || '), NPS ('::text) || (nps_score)::text) || '), usage ('::text) || (usage_events_last_30_days)::text) || ' events)'::text), 'Verify all renewal contacts in CRM are current and that champion engagement has been active this month', 'Set a 30-day renewal monitoring checkpoint and escalate to Renewal Risk Review if any signal deteriorates')
            END
            ELSE jsonb_build_array((('Review all account signals with '::text || (account_owner)::text) || ' to determine the appropriate action plan'::text), (((('Assess current health score ('::text || (computed_health_score)::text) || ') and churn risk ('::text) || (computed_churn_risk_score)::text) || ') against segment benchmarks'::text), 'Identify the top 2 risk or opportunity signals and document findings in CRM with assigned owners', ('Confirm the right owner and timeline for the next action â€” target completion by '::text || COALESCE(to_char(recommended_due_date, 'YYYY-MM-DD'::text), 'TBD'::text)), (('Escalate to '::text || suggested_owner_role) || ' if urgency level increases or signals deteriorate before next review'::text))
        END AS immediate_next_steps,
        CASE recommended_action_type
            WHEN 'Immediate Churn Intervention'::text THEN jsonb_build_array('Conduct a structured 30-day recovery QBR â€” present progress on usage recovery, ticket resolution, and NPS improvement', 'Track usage trend week over week with a shared dashboard view accessible to the account champion', 'Convert to standard health maintenance mode once churn risk drops below 40 and health score rises above 60', 'Reassess expansion potential after 60 days of sustained health improvement â€” do not initiate upsell during active save motion')
            WHEN 'Executive Renewal Save Plan'::text THEN jsonb_build_array('Execute the renewal contract â€” multi-year or step-down scenario depending on negotiation outcome', 'Introduce the executive sponsor to the product roadmap to reinforce long-term partnership value', 'Transition account to standard renewal monitoring post-close and confirm health baseline for the new contract period', 'Evaluate expansion opportunity 90 days after renewal close once account health has been confirmed stable')
            WHEN 'CSM Risk Review'::text THEN jsonb_build_array('Transition to standard health maintenance cadence once support ticket volume drops to 2 or fewer and NPS recovers above 7', 'Schedule a 60-day follow-up NPS survey to validate improvement and confirm the account champion''s satisfaction', 'Document root cause learnings from this risk review in the account CRM and update the CSM playbook for similar segments', 'Determine if expansion conversation can resume after 30 consecutive days of stable health signals')
            WHEN 'Renewal Readiness Review'::text THEN jsonb_build_array('Complete all renewal paperwork and update the CRM opportunity to Closed-Won within 48 hours of receiving the signature', 'Initiate a post-renewal success onboarding cadence â€” schedule a 30-day value check-in for the new contract period', 'Begin a proactive expansion discovery conversation 30 days after renewal close while engagement momentum is high', 'Document the renewal readiness process outcome and note any friction points to improve future renewal cycles')
            WHEN 'Renewal Risk Review'::text THEN jsonb_build_array('If renewal is achieved, transition immediately to health maintenance mode and set a 30-day post-renewal check-in', 'If renewal remains at risk, escalate to Executive Renewal Save Plan and assign executive ownership within 48 hours', 'Document all renewal risk factors and mitigation actions in the account CRM for future reference', 'Assess whether the account is a candidate for proactive expansion discussion 60 days after risk resolution')
            WHEN 'Renewal and Expansion Review'::text THEN jsonb_build_array('Close renewal documentation within 48 hours of signature and update the CRM opportunity to Closed-Won', 'Formalize the expansion opportunity as a separate CRM pipeline item within 30 days of renewal close', 'Begin formal expansion scoping after renewal is signed â€” do not conflate the two commercial timelines', 'Schedule a 60-day post-renewal expansion check-in to maintain momentum and advance the upsell motion')
            WHEN 'Expansion Discovery'::text THEN jsonb_build_array('Create a formal expansion opportunity in CRM within 5 days of the discovery call conclusion', 'Schedule a product demo targeting the new use cases or departments identified during discovery', 'Move to an AE-led commercial discovery motion within 30 days and confirm expansion ACV estimate', (('Coordinate with '::text || suggested_owner_role) || ' to align expansion timeline with renewal cycle to avoid deal conflict'::text))
            WHEN 'Expansion Nurture'::text THEN jsonb_build_array('Graduate to formal Expansion Discovery motion when expansion score crosses 65 or champion initiates commercial conversation', 'Share quarterly business value updates with the champion to maintain expansion mindshare during the nurture period', 'Strengthen internal champion by inviting them to a product advisory session or customer council if available', 'Coordinate with AE to ensure expansion opportunity is pre-staged in CRM and ready for fast conversion to discovery')
            WHEN 'Maintain Account Health'::text THEN jsonb_build_array('Schedule a quarterly business review (QBR) to reinforce value delivered and identify new goals for the coming quarter', 'Monitor expansion score monthly â€” initiate a formal nurture motion if it rises above 60 for two consecutive months', 'Confirm renewal is on track at the 90-day checkpoint and surface any early contract or pricing questions', (('Document account health trajectory in CRM and flag any signal changes to '::text || suggested_owner_role) || ' proactively'::text))
            WHEN 'Monitor Account'::text THEN jsonb_build_array('Reassess monitoring posture monthly â€” determine if signals warrant escalation to active CSM engagement', 'Escalate to CSM Risk Review immediately if health score drops below 50 or support tickets exceed 5 in a single month', 'Confirm account owner engagement at each 30-day interval â€” ensure no champion or budget changes go undetected', 'Close all overdue actions before the next monitoring cycle to avoid compounding backlog and missed signals')
            WHEN 'Renewal Monitoring'::text THEN jsonb_build_array('Complete all renewal administrative tasks (DocuSign, Salesforce update, billing confirmation) within 5 days of signature', 'Schedule a post-renewal health check at 30 days into the new contract to establish a clean baseline', 'Begin an expansion conversation 60 days after renewal close when the account is stable and champion engagement is fresh', 'Document the renewal monitoring outcome and note any late-stage friction for future proactive renewal cycles')
            ELSE jsonb_build_array((('Complete the initial action plan review with '::text || (account_owner)::text) || ' and confirm ownership assignments'::text), 'Schedule a 30-day follow-up to assess whether action has improved risk, health, or expansion signals', 'Update CRM with action plan details and ensure the next checkpoint date is logged and assigned', (('Escalate to '::text || suggested_owner_role) || ' if account signals deteriorate before the 30-day checkpoint'::text))
        END AS phase_2_next_steps,
        CASE recommended_action_type
            WHEN 'Immediate Churn Intervention'::text THEN jsonb_build_array((('Churn risk score drops from '::text || (computed_churn_risk_score)::text) || ' to below 40 within 60 days'::text), (('Health score improves from '::text || (computed_health_score)::text) || ' to above 60 within 60 days'::text), 'Support ticket volume falls to 2 or fewer per 30-day period within the first intervention cycle', (('Monthly usage events increase by 30% or more from the current baseline of '::text || (usage_events_last_30_days)::text) || ' events'::text))
            WHEN 'Executive Renewal Save Plan'::text THEN jsonb_build_array('Renewal contract signed before the expiration date with no gap in coverage', 'Churn risk score reduces by at least 15 points within 30 days of renewal close', 'Executive sponsor engagement confirmed with at least one recorded meeting or written communication', 'CRM renewal opportunity updated to Closed-Won within 48 hours of contract execution')
            WHEN 'CSM Risk Review'::text THEN jsonb_build_array((('NPS score recovers from '::text || (nps_score)::text) || ' to 7 or above within 30 days of intervention'::text), 'Support ticket volume drops to 2 or fewer per 30-day period within the first review cycle', ('Usage events remain stable or improve month-over-month from the current baseline of '::text || (usage_events_last_30_days)::text), 'CSM check-in completed, documented in CRM, and champion confirms satisfaction improvement')
            WHEN 'Renewal Readiness Review'::text THEN jsonb_build_array('Renewal signed on time with no last-minute escalations or contract terms disputes', 'All support issues resolved before the formal renewal discussion begins', 'Economic buyer and champion both engaged and confirmed as aligned on terms and timeline', 'CRM renewal opportunity updated to Closed-Won within 48 hours of signature')
            WHEN 'Renewal Risk Review'::text THEN jsonb_build_array('Renewal achieved without extension or gap â€” contract executed on schedule', 'Churn risk score improves by 10 or more points within 30 days of the risk review completion', 'All identified renewal risk factors are documented with named owners and resolution dates', 'At-risk signals addressed within a 14-day action window with visible progress updates')
            WHEN 'Renewal and Expansion Review'::text THEN jsonb_build_array('Renewal closed before the contract end date â€” no coverage gap or last-minute delay', 'Expansion opportunity formally created in CRM within 30 days of renewal close', 'Both commercial motions aligned on timeline â€” renewal and expansion champion confirmed as the same contact', 'Combined ARR impact documented and reported to leadership within 5 days of contract execution')
            WHEN 'Expansion Discovery'::text THEN jsonb_build_array('Discovery call completed within 30 days of initiating the expansion motion', 'Qualified expansion opportunity created in CRM with AE assigned and estimated ACV documented', 'Stakeholder map completed â€” budget holder, champion, and technical evaluator all identified', 'Expansion scenario defined with at least one specific use case or product tier confirmed as in-scope')
            WHEN 'Expansion Nurture'::text THEN jsonb_build_array(('Expansion score grows by 5 or more points over the 60-day nurture period from the current '::text || (computed_expansion_score)::text), 'At least one discovery checkpoint or value conversation completed during the nurture cycle', 'Champion engagement maintained with monthly touchpoints â€” no lapse in contact longer than 35 days', (('NPS maintained at '::text || (nps_score)::text) || ' or above throughout the entire nurture period'::text))
            WHEN 'Maintain Account Health'::text THEN jsonb_build_array(('Health score maintained above 65 throughout the current quarter â€” current baseline is '::text || (computed_health_score)::text), 'No support ticket spikes above 3 per 30-day period for the duration of the maintenance cadence', 'NPS at or above 7 at the next scheduled satisfaction survey', 'No escalation to risk or intervention status during the maintenance period')
            WHEN 'Monitor Account'::text THEN jsonb_build_array('No deterioration in health score, usage events, or support volume during the 30-day monitoring cycle', ('All overdue actions cleared within the current quarter â€” current backlog is '::text || (overdue_action_count)::text), 'Clear escalation criteria documented in CRM and actively understood by the account owner', '30-day monitoring checkpoint completed on schedule with no negative flags or unplanned escalations')
            WHEN 'Renewal Monitoring'::text THEN jsonb_build_array('Renewal executed on schedule with no surprises, pricing disputes, or contract delays', 'No new risk signals introduced in the final 30 days of the contract period', 'All renewal paperwork and billing tasks completed within 5 business days of signature', 'Health score maintained at 60 or above through the close of the renewal monitoring period')
            ELSE jsonb_build_array((('Account action plan reviewed and confirmed with '::text || (account_owner)::text) || ' within 1 week'::text), 'Top risk or opportunity signal addressed with a documented owner and target date within 2 weeks', 'CRM account notes updated with current status, next steps, and escalation threshold by end of current cycle', 'No unplanned escalations during the current action period â€” all risks surface through the checkpoint cadence')
        END AS success_metrics,
        CASE recommended_action_type
            WHEN 'Immediate Churn Intervention'::text THEN 'Escalate to VP of Customer Success or executive leadership if: (1) account owner cannot confirm champion engagement within 48 hours; (2) support ticket volume exceeds 12 in any 30-day window; (3) churn risk score rises above 75; or (4) customer indicates intent to cancel in writing.'::text
            WHEN 'Executive Renewal Save Plan'::text THEN 'Escalate to C-level leadership if: (1) economic buyer disengages or becomes unresponsive for more than 5 business days; (2) the renewal timeline compresses past the current target date; (3) a competitive vendor is confirmed in active evaluation; or (4) contract value is being renegotiated downward by more than 20%.'::text
            WHEN 'CSM Risk Review'::text THEN 'Escalate to CSM Manager or VP of Customer Success if: (1) NPS score drops below 4; (2) support ticket volume exceeds 8 in any 30-day period; (3) the account champion confirms intent to evaluate alternatives; or (4) the risk score increases by more than 10 points during the review cycle.'::text
            WHEN 'Renewal Readiness Review'::text THEN 'Escalate to Account Executive and CSM Manager if: (1) the economic buyer is unreachable after two outreach attempts within 14 days; (2) renewal terms are contested or a formal redline is requested; (3) a new competitive vendor is confirmed in evaluation; or (4) internal renewal approval is delayed beyond the target date.'::text
            WHEN 'Renewal Risk Review'::text THEN 'Escalate to VP of Sales or VP of Customer Success if: (1) the renewal deadline is less than 15 days away with no confirmed intent from the economic buyer; (2) churn risk score exceeds 60; (3) confirmed champion turnover during the review period; or (4) the account submits a formal contract redline or legal request.'::text
            WHEN 'Renewal and Expansion Review'::text THEN 'Escalate to AE Manager and CSM Manager if: (1) the renewal and expansion timelines conflict and create customer confusion; (2) expansion budget is not confirmed within 30 days of the review; (3) the core renewal is at risk due to commercial disagreement during the combined review; or (4) the account champion changes during the active review period.'::text
            WHEN 'Expansion Discovery'::text THEN 'Escalate to AE Manager if: (1) the expansion budget holder is unresponsive after two outreach attempts; (2) the expansion scenario requires a custom contract, new module, or non-standard commercial terms outside AE scope; or (3) a competitive risk is flagged by the champion or economic buyer during discovery.'::text
            WHEN 'Expansion Nurture'::text THEN 'Escalate to CSM leadership if: (1) expansion score drops below 50 during the nurture period; (2) the champion disengages or there is no response after two consecutive monthly touchpoints; or (3) health score falls below 60 â€” pause the expansion nurture and shift focus to risk stabilization first.'::text
            WHEN 'Maintain Account Health'::text THEN 'Escalate to CSM or Account Manager if: (1) health score drops below 55 in any review cycle; (2) support ticket volume rises above 4 in a single month; (3) NPS drops below 6 at the next survey; or (4) overdue actions exceed 3 without a documented resolution plan.'::text
            WHEN 'Monitor Account'::text THEN 'Escalate to CSM Risk Review if: (1) health score falls below 50 in any monitoring cycle; (2) support tickets exceed 5 in a single month; (3) usage drops below 10 events in any 30-day window; or (4) the account owner reports a champion change, budget freeze, or competitive conversation.'::text
            WHEN 'Renewal Monitoring'::text THEN 'Escalate to Renewal Risk Review immediately if: (1) the champion becomes unresponsive within 30 days of the renewal date; (2) any new commercial objection or pricing concern is raised; (3) support issues spike in the final 30 days of the contract period; or (4) renewal sign-off is delayed past the target execution date.'::text
            ELSE (('Escalate to '::text || suggested_owner_role) || ' if: (1) health score drops below 50; (2) churn risk score rises above 60; (3) support ticket volume exceeds 6 in any 30-day period; or (4) the account owner confirms any champion change, budget risk, or competitive threat.'::text)
        END AS escalation_guidance,
        CASE recommended_action_type
            WHEN 'Immediate Churn Intervention'::text THEN
            CASE
                WHEN (very_high_churn AND renewal_near) THEN 'CRITICAL â€” within 24 hours'::text
                ELSE 'Immediate â€” within 48 hours'::text
            END
            WHEN 'Executive Renewal Save Plan'::text THEN
            CASE
                WHEN renewal_imminent THEN 'URGENT â€” within 24 hours'::text
                WHEN renewal_near THEN 'Urgent â€” within 1 week'::text
                ELSE 'High priority â€” within 2 weeks'::text
            END
            WHEN 'CSM Risk Review'::text THEN
            CASE
                WHEN (low_nps AND high_support) THEN 'Urgent â€” within 1 week'::text
                ELSE 'Within 1â€“2 weeks'::text
            END
            WHEN 'Renewal Readiness Review'::text THEN
            CASE
                WHEN renewal_imminent THEN 'URGENT â€” this week'::text
                WHEN renewal_near THEN 'Within 2 weeks'::text
                ELSE 'Within 30 days'::text
            END
            WHEN 'Renewal Risk Review'::text THEN
            CASE
                WHEN (renewal_imminent AND very_high_churn) THEN 'CRITICAL â€” within 24 hours'::text
                WHEN renewal_imminent THEN 'Immediate â€” within 48 hours'::text
                ELSE 'Within 1 week'::text
            END
            WHEN 'Renewal and Expansion Review'::text THEN
            CASE
                WHEN renewal_imminent THEN 'URGENT â€” this week'::text
                WHEN renewal_near THEN 'Within 2 weeks'::text
                ELSE 'This quarter'::text
            END
            WHEN 'Expansion Discovery'::text THEN 'Within 30 days'::text
            WHEN 'Expansion Nurture'::text THEN '30â€“60 day nurture cycle'::text
            WHEN 'Maintain Account Health'::text THEN 'Ongoing â€” quarterly cadence'::text
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
