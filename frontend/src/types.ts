export interface KPIs {
  total_accounts: number;
  critical_risk_accounts: number;
  high_risk_accounts: number;
  high_expansion_accounts: number;
  accounts_needing_human_review: number;
  avg_health_score: number;
  avg_churn_risk_score: number;
  avg_expansion_score: number;
  total_arr: number;
  arr_at_risk: number;
  total_open_pipeline: number;
  high_expansion_pipeline: number;
}

export interface RiskSummaryItem {
  risk_level: string;
  account_count: number;
  avg_health_score: number;
  avg_churn_risk_score: number;
  avg_expansion_score: number;
  total_arr: number;
  total_open_pipeline: number;
  accounts_needing_human_review: number;
}

export interface ActionSummaryItem {
  recommended_action_priority: string;
  recommended_action_type: string;
  account_count: number;
  accounts_needing_human_review: number;
  earliest_due_date: string;
  total_arr: number;
  avg_churn_risk_score: number;
}

export interface OwnerWorkloadItem {
  suggested_owner_role: string;
  assigned_account_count: number;
  critical_action_count: number;
  high_action_count: number;
  human_review_count: number;
  total_arr_owned: number;
}

export interface Account {
  account_id: string;
  company_name: string;
  industry: string;
  segment: string;
  company_size: number;
  plan_type: string;
  customer_stage: string;
  account_owner: string;
  annual_recurring_revenue: number;
  days_until_renewal: number;
  computed_health_score: number;
  computed_churn_risk_score: number;
  computed_expansion_score: number;
  risk_level: string;
  expansion_level: string;
  customer_priority_tier: string;
  health_status: string;
  churn_status: string;
  expansion_status: string;
  primary_business_motion: string;
  recommended_action_type: string;
  recommended_action_priority: string;
  suggested_owner_role: string;
  recommended_due_date: string | null;
  needs_human_review: boolean;
  human_review_reason: string | null;
  recommended_next_action?: string | null;
  recommendation_reason?: string | null;
  ai_explanation_context?: string | null;
  immediate_next_steps?: string[];
  phase_2_next_steps?: string[];
  success_metrics?: string[];
  escalation_guidance?: string;
  timeline_label?: string;
  playbook_version?: string;
}

export interface AISignalDriver {
  signal: string;
  value: string;
  interpretation: string;
}

export interface AIExplanationResponse {
  account_id: string;
  company_name: string;
  model_used: string;
  ai_summary: string;
  account_status_explanation: string;
  key_signal_drivers: AISignalDriver[];
  recommended_next_step: string;
  why_this_action_matters: string;
  confidence_note: string;
  guardrail_note: string;
}