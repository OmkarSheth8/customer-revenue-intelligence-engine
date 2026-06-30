import type { KPIs, RiskSummaryItem, ActionSummaryItem, OwnerWorkloadItem, Account, AIExplanationResponse } from '../types';

// Local dev: VITE_API_BASE_URL is unset → falls back to /api, Vite proxy handles it.
// Production (Vercel): set VITE_API_BASE_URL=https://your-render-backend.onrender.com
const BASE = (import.meta.env.VITE_API_BASE_URL ?? '').replace(/\/$/, '') || '/api';

async function get<T>(path: string): Promise<T> {
  const res = await fetch(`${BASE}${path}`);
  if (!res.ok) throw new Error(`${res.status} ${res.statusText} — ${path}`);
  return res.json();
}

async function post<T>(path: string): Promise<T> {
  const res = await fetch(`${BASE}${path}`, { method: 'POST' });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error((body as { detail?: string }).detail ?? `${res.status} ${res.statusText}`);
  }
  return res.json();
}

export const getDashboardKpis          = ()             => get<KPIs>('/dashboard/kpis');
export const getRiskSummary            = ()             => get<RiskSummaryItem[]>('/dashboard/risk-summary');
export const getActionSummary          = ()             => get<ActionSummaryItem[]>('/dashboard/action-summary');
export const getOwnerWorkload          = ()             => get<OwnerWorkloadItem[]>('/dashboard/owner-workload');
export const getAccounts               = ()             => get<Account[]>('/accounts');
export const getHighRiskAccounts       = ()             => get<Account[]>('/accounts/high-risk');
export const getExpansionReadyAccounts = ()             => get<Account[]>('/accounts/expansion-ready');
export const getReviewNeededAccounts   = ()             => get<Account[]>('/accounts/review-needed');
export const getAccountsByMotion       = (motion: string) => get<Account[]>(`/accounts/motion/${encodeURIComponent(motion)}`);
export const getAccountById            = (id: string)  => get<Account>(`/accounts/${id}`);
export const generateAiExplanation     = (id: string)  => post<AIExplanationResponse>(`/accounts/${id}/ai-explanation`);

// Legacy aliases kept for compatibility
export const fetchKPIs            = getDashboardKpis;
export const fetchRiskSummary     = getRiskSummary;
export const fetchActionSummary   = getActionSummary;
export const fetchOwnerWorkload   = getOwnerWorkload;
export const fetchAccounts        = getAccounts;
export const generateAIExplanation = generateAiExplanation;