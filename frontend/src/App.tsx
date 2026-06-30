import { useEffect, useCallback, useState, useMemo, useRef, Fragment } from 'react';
import { PieChart, Pie, Cell, ResponsiveContainer } from 'recharts';
import {
  Activity, LayoutDashboard, Building2, ShieldAlert, TrendingUp,
  ClipboardCheck, Sparkles, Database, Library, Settings, Users,
  Search, Check, X, Loader2,
  UserRound, CalendarClock, ArrowRight, AlertCircle, AlertTriangle,
  Info, RefreshCw, ClipboardList, PanelRight,
} from 'lucide-react';
import {
  getDashboardKpis, getRiskSummary, getActionSummary, getOwnerWorkload,
  getAccounts, generateAiExplanation,
} from './lib/api';
import type {
  KPIs, RiskSummaryItem, ActionSummaryItem, OwnerWorkloadItem,
  Account, AIExplanationResponse,
} from './types';
import './App.css';

// ─── Types ────────────────────────────────────────────────────────────────────

type ActiveView =
  | 'dashboard' | 'accounts' | 'risk-review' | 'expansion' | 'human-review'
  | 'ai-explanations' | 'data-sources' | 'metric-library' | 'settings' | 'users-teams';

type Tone    = 'success' | 'warning' | 'critical' | 'neutral';
type KpiTone = 'primary' | 'critical' | 'success'  | 'warning';

type FilterKey = 'all' | 'critical-risk' | 'high-risk' | 'expansion-ready' | 'human-review' | 'renewal-soon';
const FILTER_LABELS: Record<FilterKey, string> = {
  'all':             'All',
  'critical-risk':   'Critical Risk',
  'high-risk':       'High Risk',
  'expansion-ready': 'Expansion Ready',
  'human-review':    'Human Review',
  'renewal-soon':    'Renewal Soon',
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

function fmtMoney(n: number): string {
  if (n >= 1_000_000) return `$${(n / 1_000_000).toFixed(2)}M`;
  if (n >= 1_000)     return `$${(n / 1_000).toFixed(1)}K`;
  return `$${n.toFixed(0)}`;
}
function fmtScore(n: number): string { return Number.isFinite(n) ? n.toFixed(1) : '—'; }
function fmtTime(d: Date): string {
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}
function monogram(name: string): string {
  return name.split(/\s+/).map(w => w[0] ?? '').join('').slice(0, 2).toUpperCase();
}
function toArr(val: string[] | string | null | undefined): string[] {
  if (!val) return [];
  if (typeof val === 'string') { try { return JSON.parse(val) as string[]; } catch { return [val]; } }
  return val;
}

function healthMeta(s: number): { label: string; tone: Tone } {
  if (s >= 75) return { label: 'Healthy',        tone: 'success'  };
  if (s >= 70) return { label: 'Stable',          tone: 'success'  };
  if (s >= 55) return { label: 'Moderate',        tone: 'warning'  };
  if (s >= 45) return { label: 'Needs attention', tone: 'warning'  };
  return             { label: 'Unhealthy',        tone: 'critical' };
}
function churnMeta(s: number): { label: string; tone: Tone } {
  if (s >= 55) return { label: 'Critical', tone: 'critical' };
  if (s >= 40) return { label: 'High',     tone: 'warning'  };
  if (s >= 25) return { label: 'Moderate', tone: 'warning'  };
  return             { label: 'Low',       tone: 'success'  };
}
function expansionMeta(s: number): { label: string; tone: Tone } {
  if (s >= 70) return { label: 'Strong fit',   tone: 'success' };
  if (s >= 45) return { label: 'Moderate fit', tone: 'warning' };
  if (s >= 40) return { label: 'Emerging fit', tone: 'neutral' };
  return             { label: 'Low fit',       tone: 'neutral' };
}

function urgencyScore(a: Account): number {
  let s = 0;
  if (a.recommended_action_priority === 'Critical') s += 1000;
  else if (a.recommended_action_priority === 'High') s += 500;
  if (a.risk_level === 'Critical Risk') s += 200;
  else if (a.risk_level === 'High Risk') s += 100;
  if (a.needs_human_review) s += 50;
  s += a.computed_churn_risk_score;
  return s;
}

function riskChip(l: string): string {
  return l === 'Critical Risk' ? 'chip chip-critical'
       : l === 'High Risk'     ? 'chip chip-warning'
       : l === 'Low Risk'      ? 'chip chip-success'
       : 'chip chip-neutral';
}
function priorityChip(p: string): string {
  return p === 'Critical' ? 'chip chip-critical'
       : p === 'High'     ? 'chip chip-warning'
       : p === 'Low'      ? 'chip chip-success'
       : 'chip chip-neutral';
}
function motionChip(m: string): string {
  return m === 'Save'    ? 'chip chip-critical'
       : m === 'Recover' ? 'chip chip-warning'
       : m === 'Expand'  ? 'chip chip-success'
       : m === 'Renewal' ? 'chip chip-primary'
       : 'chip chip-neutral';
}

// ─── Nav ──────────────────────────────────────────────────────────────────────

const NAV_GROUPS = [
  { section: 'Overview',     items: [
    { label: 'Dashboard',      view: 'dashboard'      as ActiveView, Icon: LayoutDashboard },
    { label: 'Accounts',       view: 'accounts'       as ActiveView, Icon: Building2 },
  ]},
  { section: 'Intelligence', items: [
    { label: 'Risk Review',    view: 'risk-review'    as ActiveView, Icon: ShieldAlert  },
    { label: 'Expansion',      view: 'expansion'      as ActiveView, Icon: TrendingUp   },
  ]},
  { section: 'Workflow',     items: [
    { label: 'Human Review',   view: 'human-review'   as ActiveView, Icon: ClipboardCheck },
    { label: 'AI Explanations',view: 'ai-explanations'as ActiveView, Icon: Sparkles     },
  ]},
  { section: 'Data',         items: [
    { label: 'Data Sources',   view: 'data-sources'   as ActiveView, Icon: Database     },
    { label: 'Metric Library', view: 'metric-library' as ActiveView, Icon: Library      },
  ]},
  { section: 'Settings',     items: [
    { label: 'Settings',       view: 'settings'       as ActiveView, Icon: Settings     },
    { label: 'Users & Teams',  view: 'users-teams'    as ActiveView, Icon: Users        },
  ]},
];

// ─── Sidebar ──────────────────────────────────────────────────────────────────

function Sidebar({
  activeView, onNav, lastRefreshedAt,
}: {
  activeView: ActiveView;
  onNav: (v: ActiveView) => void;
  lastRefreshedAt: Date | null;
}) {
  return (
    <aside className="sidebar">
      <div className="sb-brand">
        <div className="sb-brand-icon"><Activity size={18} /></div>
        <div>
          <div className="sb-brand-name">RevenueIQ Engine</div>
          <div className="sb-brand-sub">Customer Intelligence</div>
        </div>
      </div>

      <nav className="sb-nav">
        {NAV_GROUPS.map(g => (
          <div key={g.section} className="sb-group">
            <span className="sb-group-label">{g.section}</span>
            {g.items.map(({ label, view, Icon }) => (
              <button
                key={label}
                className={`sb-nav-item${activeView === view ? ' sb-nav-active' : ''}`}
                onClick={() => onNav(view)}
              >
                <Icon size={16} />
                {label}
              </button>
            ))}
          </div>
        ))}
      </nav>

      <div className="sb-freshness">
        <div className="sb-fresh-card">
          <div className="sb-fresh-row">
            <span className="sb-fresh-label">Data freshness</span>
            <span className="sb-fresh-dot-wrap">
              <span className="sb-fresh-ping" />
              <span className="sb-fresh-dot" />
            </span>
          </div>
          <div className="sb-fresh-status">Up to date</div>
          <div className="sb-fresh-sub">
            {lastRefreshedAt ? `Refreshed at ${fmtTime(lastRefreshedAt)}` : 'Live · PostgreSQL'}
          </div>
        </div>
      </div>
    </aside>
  );
}

// ─── Top Header ───────────────────────────────────────────────────────────────

function TopHeader({
  title, subtitle, isRefreshing, lastRefreshedAt, onRefresh, onSearch, searchValue,
  drawerOpen, onToggleDrawer, searchInputRef, selectedAccountName,
}: {
  title: string;
  subtitle: string;
  isRefreshing: boolean;
  lastRefreshedAt: Date | null;
  onRefresh: () => void;
  onSearch: (v: string) => void;
  searchValue: string;
  drawerOpen: boolean;
  onToggleDrawer: () => void;
  searchInputRef: { current: HTMLInputElement | null };
  selectedAccountName: string | null;
}) {
  const toggleLabel = drawerOpen
    ? 'Close Detail'
    : selectedAccountName
      ? `View ${selectedAccountName}`
      : 'Account Detail';

  return (
    <header className="topbar">
      <div className="topbar-left">
        <div className="topbar-title">{title}</div>
        <div className="topbar-subtitle">{subtitle}</div>
      </div>
      <div className="topbar-right">
        <div className="topbar-search">
          <Search size={13} className="topbar-search-icon" />
          <input
            ref={searchInputRef}
            placeholder="Search by name, industry, motion, action… (⌘K)"
            value={searchValue}
            onChange={e => onSearch(e.target.value)}
          />
          {searchValue && (
            <button
              className="topbar-search-clear"
              onClick={() => onSearch('')}
              tabIndex={-1}
              aria-label="Clear search"
            >
              <X size={11} />
            </button>
          )}
        </div>

        <button
          className="topbar-refresh"
          onClick={onRefresh}
          disabled={isRefreshing}
          title={lastRefreshedAt ? `Last refreshed ${fmtTime(lastRefreshedAt)}` : 'Refresh data'}
        >
          <RefreshCw size={13} className={isRefreshing ? 'spin' : ''} />
          {isRefreshing ? 'Refreshing…' : lastRefreshedAt ? `Refreshed ${fmtTime(lastRefreshedAt)}` : 'Refresh'}
        </button>

        <button
          className={`topbar-inspector-toggle${drawerOpen ? ' insp-active' : ''}`}
          onClick={onToggleDrawer}
          title={drawerOpen ? 'Close account inspector' : `Open account detail${selectedAccountName ? ` — ${selectedAccountName}` : ''}`}
          style={{ maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis' }}
        >
          <PanelRight size={14} style={{ flexShrink: 0 }} />
          <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {toggleLabel}
          </span>
        </button>
      </div>
    </header>
  );
}

// ─── Selected-Account Context Strip ──────────────────────────────────────────

function SelectedAccountStrip({
  account, onOpen,
}: {
  account: Account | null;
  onOpen: () => void;
}) {
  if (!account) return null;
  const c = churnMeta(account.computed_churn_risk_score);
  const h = healthMeta(account.computed_health_score);
  return (
    <div className="acct-strip">
      <span className="acct-strip-label">Selected Account</span>
      <span className="acct-strip-divider" />
      <span className="acct-strip-name">{account.company_name}</span>
      <span className={riskChip(account.risk_level)} style={{ fontSize: 10, padding: '2px 6px' }}>
        {account.risk_level}
      </span>
      <span className="acct-strip-dot">·</span>
      <span className="acct-strip-action">{account.recommended_action_type}</span>
      <span className="acct-strip-divider" />
      <span className="acct-strip-stat">
        <span className="asm-k">Churn</span>
        <span className={`asm-v asm-v-${c.tone}`}>{fmtScore(account.computed_churn_risk_score)}</span>
      </span>
      <span className="acct-strip-stat">
        <span className="asm-k">Health</span>
        <span className={`asm-v asm-v-${h.tone}`}>{fmtScore(account.computed_health_score)}</span>
      </span>
      {account.recommended_due_date && (
        <span className="acct-strip-stat">
          <span className="asm-k">Due</span>
          <span className="asm-v">{account.recommended_due_date}</span>
        </span>
      )}
      <span className="acct-strip-stat">
        <span className="asm-k">Owner</span>
        <span className="asm-v">{account.suggested_owner_role || account.account_owner || '—'}</span>
      </span>
      <span className="acct-strip-spacer" />
      <button className="acct-strip-btn" onClick={onOpen}>
        View Details <ArrowRight size={11} />
      </button>
    </div>
  );
}

// ─── Workflow Strip ───────────────────────────────────────────────────────────

function WorkflowStrip({ hasData }: { hasData: boolean }) {
  const [open, setOpen] = useState(false);
  const steps = [
    { label: 'Data Loaded',  sub: 'from PostgreSQL',       done: hasData },
    { label: 'Scored',       sub: 'health · churn · exp',  done: hasData },
    { label: 'Recommended',  sub: 'action + priority',     done: hasData },
    { label: 'Explained',    sub: 'AI on demand',          done: false   },
  ];
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      <div className="wf-card">
        <div className="wf-steps">
          {steps.map((s, i) => (
            <Fragment key={s.label}>
              <div className={`wf-step${s.done ? ' wf-done' : ''}`}>
                <div className="wf-circle">
                  {s.done ? <Check size={12} /> : <span className="wf-num">{i + 1}</span>}
                </div>
                <div>
                  <div className="wf-label">{s.label}</div>
                  <div className="wf-sub">{s.sub}</div>
                </div>
              </div>
              {i < steps.length - 1 && <div className={`wf-line${s.done ? ' wf-line-done' : ''}`} />}
            </Fragment>
          ))}
        </div>
        <button className="wf-btn" onClick={() => setOpen(v => !v)}>
          {open ? 'Hide details' : 'View run details'}
        </button>
      </div>
      {open && (
        <div className="wf-details">
          {[
            ['Status',   'All steps completed · Success'],
            ['Source',   'PostgreSQL · core schema'],
            ['Views',    'account_intelligence_view · risk_summary_view · action_summary_view · owner_workload_view'],
            ['Scoring',  'Deterministic rules engine (no ML)'],
            ['AI Layer', 'On-demand · Anthropic Claude (backend)'],
            ['Tables',   'accounts · customer_engagement · crm_opportunities · product_usage_events · score_history'],
            ['Refreshed',new Date().toLocaleTimeString()],
          ].map(([k, v]) => (
            <div key={k} className="wf-detail-row">
              <span className="wf-dk">{k}</span>
              <span className="wf-dv">{v}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ─── KPI Grid ─────────────────────────────────────────────────────────────────

function KpiGrid({ kpis }: { kpis: KPIs }) {
  const cards: Array<{ label: string; value: string; trend: string; tone: KpiTone; Icon: React.FC<{size:number}> }> = [
    { label: 'Total Accounts',  value: String(kpis.total_accounts),                 trend: 'Active accounts in portfolio',             tone: 'primary',  Icon: Building2      },
    { label: 'ARR at Risk',     value: fmtMoney(kpis.arr_at_risk),                  trend: 'Across critical and high-risk accounts',   tone: 'critical', Icon: AlertTriangle  },
    { label: 'Critical Risk',   value: String(kpis.critical_risk_accounts),         trend: 'Require immediate leadership review',       tone: 'critical', Icon: ShieldAlert    },
    { label: 'Expansion Ready', value: String(kpis.high_expansion_accounts),        trend: `${fmtMoney(kpis.high_expansion_pipeline)} expansion pipeline`, tone: 'success', Icon: TrendingUp },
    { label: 'Human Review',    value: String(kpis.accounts_needing_human_review),  trend: 'Flagged for human judgment',               tone: 'warning',  Icon: ClipboardCheck },
  ];
  return (
    <div className="kpi-grid">
      {cards.map(({ label, value, trend, tone, Icon }) => (
        <div key={label} className="kpi-card">
          <span className={`kpi-icon kpi-icon-${tone}`}><Icon size={18} /></span>
          <p className="kpi-label">{label}</p>
          <p className="kpi-value">{value}</p>
          <p className="kpi-trend">{trend}</p>
        </div>
      ))}
    </div>
  );
}

// ─── Priority Queue ───────────────────────────────────────────────────────────

function matchesSearch(a: Account, s: string): boolean {
  const fields = [
    a.company_name, a.industry, a.segment, a.plan_type, a.account_owner,
    a.primary_business_motion, a.risk_level, a.expansion_level,
    a.recommended_action_type, a.recommended_next_action,
    a.suggested_owner_role, a.recommendation_reason,
  ];
  return fields.some(f => f?.toLowerCase().includes(s));
}

function PriorityQueue({
  accounts, selectedId, onSelect, globalSearch = '',
}: {
  accounts: Account[];
  selectedId: string | null;
  onSelect: (a: Account) => void;
  globalSearch?: string;
}) {
  const top = useMemo(() => {
    const s = globalSearch.trim().toLowerCase();
    const base = s ? accounts.filter(a => matchesSearch(a, s)) : accounts;
    return [...base].sort((a, b) => urgencyScore(b) - urgencyScore(a)).slice(0, 5);
  }, [accounts, globalSearch]);

  return (
    <div className="card" style={{ overflow: 'hidden' }}>
      <div className="card-pad" style={{ paddingBottom: 12, borderBottom: '1px solid var(--border)' }}>
        <p className="card-title">Today's Priority Queue</p>
        <p className="card-sub">Top accounts requiring immediate action</p>
      </div>
      <div className="pq-list">
        {top.map((a, i) => (
          <div
            key={a.account_id}
            className={`pq-item${a.account_id === selectedId ? ' pq-sel' : ''}`}
            onClick={() => onSelect(a)}
          >
            <span className="pq-rank">{i + 1}</span>
            <span className="pq-mono">{monogram(a.company_name)}</span>
            <span className="pq-body">
              <span className="pq-name">{a.company_name}</span>
              <span className="pq-sub">
                <span className={riskChip(a.risk_level)} style={{ marginRight: 5, fontSize: 10 }}>
                  {a.risk_level}
                </span>
                {a.recommended_action_type}
              </span>
            </span>
            <span className="pq-right">
              <span className="pq-arr">{fmtMoney(a.annual_recurring_revenue)}</span>
              <span className="pq-due">{a.recommended_due_date ?? a.suggested_owner_role ?? '—'}</span>
            </span>
          </div>
        ))}
        {top.length === 0 && (
          <div style={{ padding: '24px 16px', textAlign: 'center', color: 'var(--muted-fg)', fontSize: 12 }}>
            {globalSearch.trim() ? `No accounts match "${globalSearch.trim()}".` : 'No accounts loaded yet.'}
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Motion Summary ───────────────────────────────────────────────────────────

function MotionSummary({ accounts }: { accounts: Account[] }) {
  const MOTIONS = ['Save', 'Recover', 'Renewal', 'Expand', 'Maintain', 'Monitor'];
  const motionColors: Record<string, string> = {
    Save: 'var(--critical-soft-fg)', Recover: 'var(--warning-soft-fg)',
    Renewal: 'var(--primary)', Expand: 'var(--success-soft-fg)',
    Maintain: 'var(--muted-fg)', Monitor: 'var(--muted-fg)',
  };

  const counts = useMemo(() => {
    const m = new Map<string, { count: number; arr: number }>();
    for (const a of accounts) {
      const key = a.primary_business_motion;
      const cur = m.get(key) ?? { count: 0, arr: 0 };
      m.set(key, { count: cur.count + 1, arr: cur.arr + a.annual_recurring_revenue });
    }
    return m;
  }, [accounts]);

  const items = MOTIONS.map(label => ({
    label,
    count: counts.get(label)?.count ?? 0,
    arr:   counts.get(label)?.arr   ?? 0,
    color: motionColors[label] ?? 'var(--muted-fg)',
  })).filter(x => x.count > 0);

  return (
    <div className="card card-pad" style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <div>
        <p className="card-title">Portfolio Motion Summary</p>
        <p className="card-sub">Account distribution by GTM motion</p>
      </div>
      <div className="motion-grid">
        {items.map(({ label, count, arr, color }) => (
          <div key={label} className="motion-item">
            <div className="motion-count" style={{ color }}>{count}</div>
            <div className="motion-label">{label}</div>
            <div className="motion-arr">{fmtMoney(arr)}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── Account Table ────────────────────────────────────────────────────────────

interface AccountTableProps {
  accounts:   Account[];
  selectedId: string | null;
  onSelect:   (a: Account) => void;
  globalSearch?: string;
  title?:    string;
  subtitle?: string;
  limit?:    number;
  hideFilters?: boolean;
}

function AccountTable({
  accounts, selectedId, onSelect, globalSearch = '',
  title = 'Account Intelligence',
  subtitle = 'Prioritized account list based on health, churn risk, expansion, and recommendation logic.',
  limit, hideFilters = false,
}: AccountTableProps) {
  const [filter, setFilter] = useState<FilterKey>('all');
  const [q, setQ] = useState('');

  const searchTerm = globalSearch || q;

  const base = useMemo(() => {
    if (hideFilters) return accounts;
    switch (filter) {
      case 'critical-risk':   return accounts.filter(a => a.risk_level === 'Critical Risk');
      case 'high-risk':       return accounts.filter(a => a.risk_level === 'High Risk');
      case 'expansion-ready': return accounts.filter(a => a.computed_expansion_score >= 60);
      case 'human-review':    return accounts.filter(a => a.needs_human_review);
      case 'renewal-soon':    return accounts.filter(a => typeof a.days_until_renewal === 'number' && a.days_until_renewal <= 60);
      default:                return accounts;
    }
  }, [accounts, filter, hideFilters]);

  const filtered = useMemo(() => {
    const s = searchTerm.trim().toLowerCase();
    if (!s) return base;
    return base.filter(a => matchesSearch(a, s));
  }, [base, searchTerm]);

  const rows = limit ? filtered.slice(0, limit) : filtered;

  const cnt: Record<FilterKey, number> = useMemo(() => ({
    'all':             accounts.length,
    'critical-risk':   accounts.filter(a => a.risk_level === 'Critical Risk').length,
    'high-risk':       accounts.filter(a => a.risk_level === 'High Risk').length,
    'expansion-ready': accounts.filter(a => a.computed_expansion_score >= 60).length,
    'human-review':    accounts.filter(a => a.needs_human_review).length,
    'renewal-soon':    accounts.filter(a => typeof a.days_until_renewal === 'number' && a.days_until_renewal <= 60).length,
  }), [accounts]);

  return (
    <div className="card" style={{ overflow: 'hidden' }}>
      <div className="tbl-card-header">
        <div>
          <p className="card-title">{title}</p>
          <p className="card-sub">{subtitle}</p>
          <p className="card-sub" style={{ marginTop: 2 }}>
            Showing {rows.length}{filtered.length !== rows.length ? ` of ${filtered.length}` : ''} accounts
            {searchTerm ? ` matching "${searchTerm}"` : ''}
          </p>
        </div>
        {!globalSearch && (
          <div className="tbl-search-wrap">
            <Search size={13} />
            <input
              className="tbl-search"
              placeholder="Search accounts…"
              value={q}
              onChange={e => setQ(e.target.value)}
            />
          </div>
        )}
      </div>

      {!hideFilters && (
        <div className="filter-bar">
          {(Object.keys(FILTER_LABELS) as FilterKey[]).map(f => (
            <button
              key={f}
              className={`filter-pill${filter === f ? ' pill-active' : ''}`}
              onClick={() => setFilter(f)}
            >
              {FILTER_LABELS[f]}
              <span className="pill-count">{cnt[f]}</span>
            </button>
          ))}
        </div>
      )}

      <div className="tbl-wrap" style={{ borderRadius: 0, border: 'none' }}>
        <table className="data-tbl" style={{ minWidth: 760 }}>
          <thead>
            <tr>
              <th style={{ minWidth: 180 }}>Account</th>
              <th className="th-c">Health</th>
              <th className="th-c">Churn Risk</th>
              <th className="th-c">Expansion</th>
              <th className="th-r">ARR</th>
              <th>Motion</th>
              <th>Recommended Action</th>
            </tr>
          </thead>
          <tbody>
            {rows.map(a => {
              const sel = a.account_id === selectedId;
              const h = healthMeta(a.computed_health_score);
              const c = churnMeta(a.computed_churn_risk_score);
              const e = expansionMeta(a.computed_expansion_score);
              return (
                <tr
                  key={a.account_id}
                  className={`acct-row${sel ? ' acct-sel' : ''}`}
                  onClick={() => onSelect(a)}
                >
                  <td className="td-acct">
                    <span className={`sel-bar${sel ? ' sel-bar-on' : ''}`} />
                    <span className="acct-mono">{monogram(a.company_name)}</span>
                    <span>
                      <span className="acct-name">{a.company_name}</span>
                      <span className="acct-meta">{a.industry} · {a.segment}</span>
                    </span>
                  </td>
                  <td className="td-c"><span className={`stile stile-${h.tone}`}>{fmtScore(a.computed_health_score)}</span></td>
                  <td className="td-c"><span className={`stile stile-${c.tone}`}>{fmtScore(a.computed_churn_risk_score)}</span></td>
                  <td className="td-c"><span className={`stile stile-${e.tone}`}>{fmtScore(a.computed_expansion_score)}</span></td>
                  <td className="td-r num" style={{ fontWeight: 700 }}>{fmtMoney(a.annual_recurring_revenue)}</td>
                  <td><span className={motionChip(a.primary_business_motion)}>{a.primary_business_motion}</span></td>
                  <td>
                    <div className="td-motion">
                      <span className={priorityChip(a.recommended_action_priority)}>{a.recommended_action_priority}</span>
                      <span className="motion-action">{a.recommended_action_type}</span>
                    </div>
                  </td>
                </tr>
              );
            })}
            {rows.length === 0 && (
              <tr>
                <td colSpan={7} className="tbl-empty">
                  {searchTerm.trim()
                    ? `No accounts match "${searchTerm.trim()}".`
                    : 'No accounts match this filter.'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ─── Risk Summary Card ────────────────────────────────────────────────────────

const DONUT_CLR: Record<string, string> = {
  'Critical Risk': 'hsl(7,64%,50%)', 'High Risk': 'hsl(26,80%,52%)',
  'Medium Risk':   'hsl(40,80%,55%)', 'Low Risk': 'hsl(147,40%,42%)',
};

function RiskSummaryCard({ rows, onReview }: { rows: RiskSummaryItem[]; onReview: () => void }) {
  const order = ['Critical Risk', 'High Risk', 'Medium Risk', 'Low Risk'];
  const data = order
    .map(rl => rows.find(r => r.risk_level === rl))
    .filter(Boolean)
    .map(r => ({ name: r!.risk_level, value: r!.account_count }));
  const total  = data.reduce((s, d) => s + d.value, 0);
  const crit   = rows.find(r => r.risk_level === 'Critical Risk')?.account_count ?? 0;
  const high   = rows.find(r => r.risk_level === 'High Risk')?.account_count ?? 0;
  const insight = crit + high === 0
    ? 'No critical or high-risk accounts at this time.'
    : `${crit + high} accounts in critical or high-risk segments. Prioritize save motions.`;

  return (
    <div className="card card-pad" style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <div>
        <p className="card-title">Risk Summary</p>
        <p className="card-sub">Distribution across {total} active accounts</p>
      </div>
      <div className="risk-row">
        <div className="risk-donut-wrap">
          <ResponsiveContainer width={168} height={168}>
            <PieChart>
              <Pie data={data} dataKey="value" nameKey="name" innerRadius={56} outerRadius={80} paddingAngle={2} stroke="none" startAngle={90} endAngle={-270}>
                {data.map(d => <Cell key={d.name} fill={DONUT_CLR[d.name] ?? '#94a3b8'} />)}
              </Pie>
            </PieChart>
          </ResponsiveContainer>
          <div className="risk-center">
            <span className="risk-total">{total}</span>
            <span className="risk-lbl">Accounts</span>
          </div>
        </div>
        <div className="risk-legend">
          {data.map(d => (
            <div key={d.name} className="risk-leg-row">
              <span className="risk-dot" style={{ background: DONUT_CLR[d.name] }} />
              <span className="risk-leg-name">{d.name}</span>
              <span className="risk-leg-val">{d.value}</span>
            </div>
          ))}
        </div>
      </div>
      <div className="risk-insight"><Info size={13} /><p>{insight}</p></div>
      <button className="btn-primary" onClick={onReview}>Review critical accounts</button>
    </div>
  );
}

// ─── Action Summary Card ──────────────────────────────────────────────────────

function ActionSummaryCard({
  rows, kpis, onViewAll,
}: {
  rows: ActionSummaryItem[];
  kpis: KPIs;
  onViewAll: () => void;
}) {
  const [active, setActive] = useState(0);
  const highPri = rows.reduce(
    (s, r) => (r.recommended_action_priority === 'Critical' || r.recommended_action_priority === 'High')
      ? s + r.account_count : s, 0,
  );
  const counters = [
    { label: 'Total Actions', value: String(kpis.total_accounts) },
    { label: 'Human Review',  value: String(kpis.accounts_needing_human_review) },
    { label: 'High Priority', value: String(highPri) },
  ];
  const catMap = new Map<string, number>();
  for (const r of rows) catMap.set(r.recommended_action_type, (catMap.get(r.recommended_action_type) ?? 0) + r.account_count);
  const cats = Array.from(catMap.entries()).sort((a, b) => b[1] - a[1]).slice(0, 5).map(([label, value]) => ({
    label, value,
    tone: label.toLowerCase().includes('expand') ? 'success' as const
        : (label.toLowerCase().includes('churn') || label.toLowerCase().includes('save') || label.toLowerCase().includes('recover')) ? 'warning' as const
        : 'neutral' as const,
  }));
  const max = Math.max(...cats.map(c => c.value), 1);

  return (
    <div className="card card-pad" style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <div>
        <p className="card-title">Action Summary</p>
        <p className="card-sub">Recommended actions across the portfolio</p>
      </div>
      <div className="action-counters">
        {counters.map((c, i) => (
          <button key={c.label} className={`action-ctr${active === i ? ' action-ctr-active' : ''}`} onClick={() => setActive(i)}>
            <span className="ac-val">{c.value}</span>
            <span className="ac-lbl">{c.label}</span>
          </button>
        ))}
      </div>
      <div className="action-cats">
        <p className="action-cats-lbl">Top recommended actions</p>
        {cats.map(cat => (
          <div key={cat.label} className="action-cat">
            <div className="action-cat-row">
              <span className="ac-name">{cat.label}</span>
              <span className="ac-count">{cat.value}</span>
            </div>
            <div className="ac-track">
              <div className={`ac-bar ac-bar-${cat.tone}`} style={{ width: `${(cat.value / max) * 100}%` }} />
            </div>
          </div>
        ))}
      </div>
      <button className="btn-outline" onClick={onViewAll}>View all actions</button>
    </div>
  );
}

// ─── Owner Workload Table ─────────────────────────────────────────────────────

function OwnerWorkloadTable({ rows }: { rows: OwnerWorkloadItem[] }) {
  return (
    <div className="card" style={{ overflow: 'hidden' }}>
      <div style={{ padding: '16px 18px 12px', borderBottom: '1px solid var(--border)' }}>
        <p className="card-title">Owner Workload</p>
        <p className="card-sub">Assigned accounts and action queue by owner role</p>
      </div>
      <div className="tbl-wrap" style={{ border: 'none', borderRadius: 0 }}>
        <table className="data-tbl">
          <thead>
            <tr>
              <th>Owner Role</th>
              <th className="th-r">Accounts</th>
              <th className="th-r">Critical</th>
              <th className="th-r">High</th>
              <th className="th-r">Review</th>
              <th className="th-r">ARR Owned</th>
            </tr>
          </thead>
          <tbody>
            {rows.map(r => (
              <tr key={r.suggested_owner_role}>
                <td style={{ fontWeight: 600 }}>{r.suggested_owner_role}</td>
                <td className="td-r num">{r.assigned_account_count}</td>
                <td className="td-r"><span className={r.critical_action_count > 0 ? 'chip chip-critical' : ''}>{r.critical_action_count}</span></td>
                <td className="td-r"><span className={r.high_action_count > 0 ? 'chip chip-warning' : ''}>{r.high_action_count}</span></td>
                <td className="td-r num">{r.human_review_count}</td>
                <td className="td-r num" style={{ fontWeight: 700 }}>{fmtMoney(r.total_arr_owned)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ─── Dashboard View ───────────────────────────────────────────────────────────

function DashboardView({
  kpis, riskSummary, actionSummary, accounts, selectedId,
  onSelect, onNav, globalSearch,
}: {
  kpis: KPIs;
  riskSummary: RiskSummaryItem[];
  actionSummary: ActionSummaryItem[];
  accounts: Account[];
  selectedId: string | null;
  onSelect: (a: Account) => void;
  onNav: (v: ActiveView) => void;
  globalSearch: string;
}) {
  return (
    <>
      <WorkflowStrip hasData />
      <KpiGrid kpis={kpis} />
      <div className="dash-2col">
        <PriorityQueue accounts={accounts} selectedId={selectedId} onSelect={onSelect} globalSearch={globalSearch} />
        <MotionSummary accounts={accounts} />
      </div>
      <AccountTable
        key="dashboard-top"
        accounts={accounts}
        selectedId={selectedId}
        onSelect={onSelect}
        globalSearch={globalSearch}
        title="Top Accounts Needing Action"
        subtitle="Sorted by urgency — churn risk, priority tier, and action deadline."
        limit={10}
        hideFilters
      />
      <div className="dash-2col">
        <RiskSummaryCard rows={riskSummary} onReview={() => onNav('risk-review')} />
        <ActionSummaryCard rows={actionSummary} kpis={kpis} onViewAll={() => onNav('accounts')} />
      </div>
    </>
  );
}

// ─── Risk Review View ─────────────────────────────────────────────────────────

function RiskReviewView({
  accounts, selectedId, onSelect, globalSearch,
}: {
  accounts: Account[];
  selectedId: string | null;
  onSelect: (a: Account) => void;
  globalSearch: string;
}) {
  const risky = useMemo(
    () => accounts.filter(a => a.risk_level === 'Critical Risk' || a.risk_level === 'High Risk')
                  .sort((a, b) => urgencyScore(b) - urgencyScore(a)),
    [accounts],
  );
  const arrAtRisk = risky.reduce((s, a) => s + a.annual_recurring_revenue, 0);
  const critical  = risky.filter(a => a.risk_level === 'Critical Risk').length;
  const high      = risky.filter(a => a.risk_level === 'High Risk').length;

  return (
    <>
      <div className="view-banner vb-critical">
        <div className="vb-left">
          <div className="vb-icon vb-icon-critical"><ShieldAlert size={20} /></div>
          <div>
            <div className="vb-title">Risk Review</div>
            <div className="vb-sub">Critical and high-risk accounts requiring immediate save or recover motions. Act before renewal pressure compounds.</div>
          </div>
        </div>
        <div className="vb-stats">
          <div className="vb-stat">
            <div className="vb-stat-val">{fmtMoney(arrAtRisk)}</div>
            <div className="vb-stat-lbl">ARR at Risk</div>
          </div>
          <div className="vb-stat">
            <div className="vb-stat-val">{critical}</div>
            <div className="vb-stat-lbl">Critical</div>
          </div>
          <div className="vb-stat">
            <div className="vb-stat-val">{high}</div>
            <div className="vb-stat-lbl">High Risk</div>
          </div>
        </div>
      </div>
      <AccountTable
        key="risk-review"
        accounts={risky}
        selectedId={selectedId}
        onSelect={onSelect}
        globalSearch={globalSearch}
        title={`${risky.length} Accounts at Risk`}
        subtitle="Sorted by urgency. Click any account to view recommended save action in the inspector."
        hideFilters
      />
    </>
  );
}

// ─── Expansion View ───────────────────────────────────────────────────────────

function ExpansionView({
  accounts, selectedId, onSelect, globalSearch,
}: {
  accounts: Account[];
  selectedId: string | null;
  onSelect: (a: Account) => void;
  globalSearch: string;
}) {
  const ready = useMemo(
    () => accounts.filter(a => a.primary_business_motion === 'Expand' || a.computed_expansion_score >= 60)
                  .sort((a, b) => b.computed_expansion_score - a.computed_expansion_score),
    [accounts],
  );
  const pipeline = ready.reduce((s, a) => s + a.annual_recurring_revenue, 0);

  return (
    <>
      <div className="view-banner vb-success">
        <div className="vb-left">
          <div className="vb-icon vb-icon-success"><TrendingUp size={20} /></div>
          <div>
            <div className="vb-title">Expansion Opportunities</div>
            <div className="vb-sub">Accounts with strong upsell signals and high expansion fit. Prioritize while health and sentiment are strong.</div>
          </div>
        </div>
        <div className="vb-stats">
          <div className="vb-stat">
            <div className="vb-stat-val">{ready.length}</div>
            <div className="vb-stat-lbl">Expansion Ready</div>
          </div>
          <div className="vb-stat">
            <div className="vb-stat-val">{fmtMoney(pipeline)}</div>
            <div className="vb-stat-lbl">Current ARR</div>
          </div>
        </div>
      </div>
      <AccountTable
        key="expansion"
        accounts={ready}
        selectedId={selectedId}
        onSelect={onSelect}
        globalSearch={globalSearch}
        title={`${ready.length} Expansion-Ready Accounts`}
        subtitle="Sorted by expansion score. Click any account to view the recommended expansion action."
        hideFilters
      />
    </>
  );
}

// ─── Human Review View ────────────────────────────────────────────────────────

function HumanReviewView({
  accounts, selectedId, onSelect, globalSearch,
}: {
  accounts: Account[];
  selectedId: string | null;
  onSelect: (a: Account) => void;
  globalSearch: string;
}) {
  const review = useMemo(
    () => accounts.filter(a => a.needs_human_review)
                  .sort((a, b) => urgencyScore(b) - urgencyScore(a)),
    [accounts],
  );

  return (
    <>
      <div className="view-banner vb-warning">
        <div className="vb-left">
          <div className="vb-icon vb-icon-warning"><ClipboardCheck size={20} /></div>
          <div>
            <div className="vb-title">Human Review Queue</div>
            <div className="vb-sub">Accounts flagged because the system's confidence is low or risk is extreme. Each requires human judgment before action proceeds.</div>
          </div>
        </div>
        <div className="vb-stats">
          <div className="vb-stat">
            <div className="vb-stat-val">{review.length}</div>
            <div className="vb-stat-lbl">Flagged accounts</div>
          </div>
        </div>
      </div>
      <AccountTable
        key="human-review"
        accounts={review}
        selectedId={selectedId}
        onSelect={onSelect}
        globalSearch={globalSearch}
        title={`${review.length} Accounts Flagged for Review`}
        subtitle="The automation system needs a human decision. Click any account to read the review reason in the inspector."
        hideFilters
      />
    </>
  );
}

// ─── AI Explanations View ─────────────────────────────────────────────────────

function AiExplanationsView({
  accounts, selectedId, onSelect, globalSearch,
}: {
  accounts: Account[];
  selectedId: string | null;
  onSelect: (a: Account) => void;
  globalSearch: string;
}) {
  return (
    <>
      <div className="card card-pad" style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{ width: 40, height: 40, borderRadius: 10, background: 'var(--primary-soft)', color: 'var(--primary)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
            <Sparkles size={18} />
          </div>
          <div>
            <p className="card-title">AI Explanations</p>
            <p className="card-sub">Select an account below, then click "Generate AI Explanation" in the right inspector.</p>
          </div>
        </div>
        <div style={{ background: 'var(--warning-soft)', border: '1px solid hsl(38,64%,80%)', borderRadius: 8, padding: '10px 12px', fontSize: 12, color: 'var(--warning-soft-fg)', lineHeight: 1.55 }}>
          <strong>Important:</strong> AI explains deterministic recommendations. It does not calculate scores, churn risk, or recommended actions — those are computed by the SQL scoring engine.
        </div>
      </div>
      <AccountTable
        key="ai-explanations"
        accounts={accounts}
        selectedId={selectedId}
        onSelect={onSelect}
        globalSearch={globalSearch}
        title="Select an Account"
        subtitle="Click a row to load it in the inspector, then generate the AI explanation on demand."
        hideFilters
      />
    </>
  );
}

// ─── Data Sources View ────────────────────────────────────────────────────────

function DataSourcesView() {
  const steps = [
    {
      label: 'CSV Data Uploads',
      desc: 'Raw customer data from Salesforce, Gainsight, support systems, and product analytics are loaded as CSV files.',
      tables: ['accounts', 'customer_engagement', 'crm_opportunities', 'product_usage_events', 'score_history', 'actions', 'experiments', 'system_logs'],
    },
    {
      label: 'PostgreSQL Database',
      desc: 'Data is stored in the core schema. Normalized relational tables enable joins across accounts, usage, support, and CRM data.',
      tables: [],
    },
    {
      label: 'SQL Feature Engineering Views',
      desc: 'Materialized views compute signals: health score, churn risk, expansion score, renewal timing, support pressure, and NPS.',
      tables: ['account_intelligence_view', 'risk_summary_view', 'action_summary_view', 'owner_workload_view'],
    },
    {
      label: 'Deterministic Scoring Engine',
      desc: 'Rules-based engine assigns customer priority tier, recommended action type, suggested owner, and due date. No machine learning — logic is fully transparent and auditable.',
      tables: [],
    },
    {
      label: 'FastAPI Backend',
      desc: 'REST API serves scored data from PostgreSQL views. Endpoints: /dashboard/kpis · /dashboard/risk-summary · /accounts · /accounts/{id}/ai-explanation.',
      tables: [],
    },
    {
      label: 'React Dashboard (this app)',
      desc: 'Live data via /api proxy (Vite → FastAPI). Full interactivity: search, filter, account inspector, polling every 60 seconds.',
      tables: [],
    },
    {
      label: 'AI Explanation Layer',
      desc: 'On-demand only. Calls Anthropic Claude with the already-computed scores and recommended action to generate a plain-English explanation. AI does not recalculate anything.',
      tables: [],
    },
  ];

  return (
    <div className="info-view">
      <div className="card card-pad" style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        <div>
          <p className="card-title">Data Pipeline Architecture</p>
          <p className="card-sub">End-to-end flow from raw customer data to actionable revenue intelligence</p>
        </div>
        <div className="pipeline-steps">
          {steps.map((s, i) => (
            <Fragment key={s.label}>
              <div className="pipe-step">
                <div className="pipe-num">{i + 1}</div>
                <div style={{ flex: 1 }}>
                  <p className="pipe-label">{s.label}</p>
                  <p className="pipe-desc">{s.desc}</p>
                  {s.tables.length > 0 && (
                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 5, marginTop: 8 }}>
                      {s.tables.map(t => (
                        <span key={t} style={{ fontSize: 10.5, background: 'var(--secondary)', border: '1px solid var(--border)', borderRadius: 4, padding: '2px 7px', color: 'var(--muted-fg)', fontFamily: 'monospace' }}>{t}</span>
                      ))}
                    </div>
                  )}
                </div>
              </div>
              {i < steps.length - 1 && (
                <div className="pipe-conn">
                  <div className="pipe-line"><div className="pipe-line-inner" /></div>
                  <div style={{ paddingBottom: 2 }} />
                </div>
              )}
            </Fragment>
          ))}
        </div>
      </div>
    </div>
  );
}

// ─── Metric Library View ──────────────────────────────────────────────────────

function MetricLibraryView() {
  const metrics = [
    {
      name: 'Health Score',
      range: '0 – 100',
      tone: 'success' as const,
      desc: 'Composite score measuring overall account wellness. Combines product engagement depth, support ticket load, NPS sentiment, and usage growth trends.',
      signals: ['Product usage events', 'Support ticket volume', 'NPS score', 'Feature adoption %', 'Usage trend (30-day)'],
      use: 'High health (≥75) → Stable · Moderate (55–74) → Watch closely · Low (<45) → Immediate save motion.',
    },
    {
      name: 'Churn Risk Score',
      range: '0 – 100',
      tone: 'critical' as const,
      desc: 'Probability-weighted churn signal. Higher score means higher risk. Accounts above 55 require critical intervention.',
      signals: ['Low product usage', 'High support pressure', 'Weak NPS', 'Overdue actions', 'Renewal proximity'],
      use: '≥55 Critical · ≥40 High · ≥25 Moderate · <25 Low.',
    },
    {
      name: 'Expansion Score',
      range: '0 – 100',
      tone: 'success' as const,
      desc: 'Upsell and cross-sell potential. Accounts with high engagement, broad feature adoption, and positive sentiment score highest.',
      signals: ['Seat utilization headroom', 'Feature adoption breadth', 'NPS sentiment', 'Usage growth rate'],
      use: '≥70 Strong fit → Start expansion discovery · ≥45 Moderate → Nurture.',
    },
    {
      name: 'Risk Level',
      range: 'Critical · High · Medium · Low',
      tone: 'warning' as const,
      desc: 'Categorical risk tier derived from churn risk score and health score combination.',
      signals: ['Churn Risk Score', 'Health Score'],
      use: 'Determines which GTM motion is assigned (Save vs. Recover vs. Renewal).',
    },
    {
      name: 'Customer Priority Tier',
      range: 'Critical · High · Medium · Low',
      tone: 'warning' as const,
      desc: 'Action urgency tier. Determines how quickly the team should respond and which owner role takes point.',
      signals: ['Churn risk', 'Health score', 'ARR at stake', 'Renewal timing'],
      use: 'Routes accounts to CSM Leadership (Critical) · CSM (High) · Account Owner (Medium/Low).',
    },
    {
      name: 'Business Motion',
      range: 'Save · Recover · Renewal · Expand · Maintain · Monitor',
      tone: 'neutral' as const,
      desc: 'Primary GTM motion assigned based on account health, risk profile, and expansion potential.',
      signals: ['Risk Level', 'Expansion Score', 'Health Score'],
      use: 'Save/Recover = churn prevention · Expand = upsell · Renewal = renewal readiness · Maintain/Monitor = steady state.',
    },
    {
      name: 'Human Review Flag',
      range: 'Boolean (true / false)',
      tone: 'warning' as const,
      desc: 'Set when the scoring engine confidence is low, the risk is extreme, or signals conflict. Requires a human decision before automated action proceeds.',
      signals: ['Model confidence threshold', 'Conflicting signals', 'Extreme churn risk with no prior action'],
      use: 'Always resolve human review flags before acting. They exist because the system is uncertain.',
    },
  ];

  return (
    <div className="info-view">
      {metrics.map(m => (
        <div key={m.name} className="card metric-card">
          <div className="metric-hdr">
            <span className="metric-name">{m.name}</span>
            <span className={`stile stile-${m.tone}`}>{m.range}</span>
          </div>
          <p className="metric-desc">{m.desc}</p>
          <div className="metric-signals">
            {m.signals.map(s => <span key={s} className="metric-signal-tag">{s}</span>)}
          </div>
          <p style={{ fontSize: 11.5, color: 'var(--muted-fg)', marginTop: 8, lineHeight: 1.55, fontStyle: 'italic' }}>
            {m.use}
          </p>
        </div>
      ))}
    </div>
  );
}

// ─── Settings View ────────────────────────────────────────────────────────────

function SettingsView() {
  return (
    <div className="info-view">
      <div className="card card-pad">
        <p className="card-title">Portfolio Settings</p>
        <p className="card-sub">Runtime configuration for this Revenue Intelligence Engine deployment</p>
        <div className="settings-rows">
          {[
            ['App Name',             'Customer Revenue Intelligence Engine'],
            ['Version',              'v1.0 — Portfolio Demo'],
            ['Database',             'PostgreSQL · core schema'],
            ['API Base URL',         '/api → Vite proxy → http://127.0.0.1:8000'],
            ['Scoring Model',        'Deterministic rules engine (no ML)'],
            ['Scoring Version',      'v3 — deterministic rules'],
            ['AI Explanations',      'Anthropic Claude · on-demand only · backend-managed'],
            ['Authentication',       'None (portfolio / demo mode)'],
            ['Data Refresh',         'Auto-polling every 60 seconds'],
            ['Frontend Stack',       'Vite · React 19 · TypeScript'],
            ['Backend Stack',        'FastAPI · Python · SQLAlchemy · PostgreSQL'],
            ['AI Stack',             'Anthropic Claude API (server-side only)'],
          ].map(([k, v]) => (
            <div key={k} className="settings-row">
              <span className="settings-k">{k}</span>
              <span className="settings-v">{v}</span>
            </div>
          ))}
        </div>
      </div>
      <div className="card card-pad">
        <p className="card-title">System Status</p>
        <p className="card-sub">Current health of all connected services</p>
        <div className="settings-rows">
          {[
            ['PostgreSQL', 'Connected · core schema'],
            ['FastAPI Backend', 'Running on port 8000'],
            ['Data Pipeline', 'Scoring complete · all views current'],
            ['AI Layer', 'Ready · on-demand via backend'],
          ].map(([k, v]) => (
            <div key={k} className="settings-row">
              <span className="settings-k">{k}</span>
              <span className="settings-v"><span className="status-dot" />{v}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ─── Outreach Modal ───────────────────────────────────────────────────────────

function OutreachModal({ account, onClose }: { account: Account; onClose: () => void }) {
  useEffect(() => {
    const fn = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', fn);
    return () => document.removeEventListener('keydown', fn);
  }, [onClose]);

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-card" onClick={e => e.stopPropagation()}>
        <div className="modal-hdr">
          <span className="modal-title">Create Outreach Task</span>
          <button className="insp-close-btn" onClick={onClose}><X size={14} /></button>
        </div>
        <div className="modal-body">
          <div className="modal-acct-row">
            <span className="acct-mono">{monogram(account.company_name)}</span>
            <span>
              <p className="modal-acct-name">{account.company_name}</p>
              <p className="modal-acct-meta">{account.industry} · {account.segment}</p>
            </span>
          </div>
          <div className="modal-fields">
            {[
              ['Recommended Action', account.recommended_action_type],
              ['Priority',           account.recommended_action_priority],
              ['Owner',              account.suggested_owner_role],
              ['Due Date',           account.recommended_due_date ?? '—'],
            ].map(([k, v]) => (
              <div key={k} className="modal-field">
                <span className="modal-fk">{k}</span>
                <span className={k === 'Priority' ? priorityChip(v) : 'modal-fv'}>{v}</span>
              </div>
            ))}
          </div>
          <div className="modal-note">
            <Info size={13} />
            <p>Frontend workflow preview. No task creation endpoint exists yet — in production this would create a task in your CRM or task management system and assign it to {account.suggested_owner_role}.</p>
          </div>
        </div>
        <div className="modal-ftr">
          <button className="btn-outline btn-sm" onClick={onClose}>Cancel</button>
          <button className="btn-primary btn-sm" onClick={onClose}>Acknowledge</button>
        </div>
      </div>
    </div>
  );
}

// ─── Account Inspector ────────────────────────────────────────────────────────

function AccountInspector({
  account, onClose, onOutreach,
}: {
  account: Account | null;
  onClose: () => void;
  onOutreach: () => void;
}) {
  const [aiExplanation, setAiExplanation] = useState<AIExplanationResponse | null>(null);
  const [aiLoading,     setAiLoading]     = useState(false);
  const [aiError,       setAiError]       = useState<string | null>(null);

  useEffect(() => {
    setAiExplanation(null);
    setAiLoading(false);
    setAiError(null);
  }, [account?.account_id]);

  function handleAI() {
    if (!account || aiLoading) return;
    setAiLoading(true);
    setAiError(null);
    generateAiExplanation(account.account_id)
      .then(r => { setAiExplanation(r); setAiLoading(false); })
      .catch((e: Error) => { setAiError(e.message); setAiLoading(false); });
  }

  if (!account) {
    return (
      <aside className="inspector insp-empty-state">
        <div className="insp-empty">
          <div className="insp-empty-icon"><ClipboardList size={24} /></div>
          <p className="insp-empty-title">No account selected</p>
          <p className="insp-empty-text">Select an account from the table to view its intelligence detail and generate an AI explanation.</p>
        </div>
      </aside>
    );
  }

  const h = healthMeta(account.computed_health_score);
  const c = churnMeta(account.computed_churn_risk_score);
  const e = expansionMeta(account.computed_expansion_score);

  const immSteps  = toArr(account.immediate_next_steps);
  const p2Steps   = toArr(account.phase_2_next_steps);
  const metrics   = toArr(account.success_metrics);
  const hasPlaybook = immSteps.length > 0 || p2Steps.length > 0 || metrics.length > 0 || !!account.escalation_guidance;

  return (
    <aside className="inspector">
      {/* A. Header */}
      <div className="insp-hdr">
        <div className="insp-hdr-row">
          <div className="insp-identity">
            <span className="insp-mono">{monogram(account.company_name)}</span>
            <span style={{ minWidth: 0 }}>
              <div className="insp-name">{account.company_name}</div>
              <div className="insp-meta-line">{account.industry} · {account.segment} · {account.plan_type}</div>
            </span>
          </div>
          <button className="insp-close-btn" onClick={onClose} aria-label="Close inspector"><X size={14} /></button>
        </div>
        <div className="insp-badges">
          <span className={riskChip(account.risk_level)}>{account.risk_level}</span>
          {account.needs_human_review && <span className="chip chip-warning">Review Required</span>}
          <span className={priorityChip(account.recommended_action_priority)}>{account.recommended_action_priority} Priority</span>
        </div>
      </div>

      {/* Body */}
      <div className="insp-body">

        {/* A. Score tiles */}
        <div className="insp-tiles">
          {[
            { label: 'Health Score', value: fmtScore(account.computed_health_score),      sub: h.label, tone: h.tone },
            { label: 'Churn Risk',   value: fmtScore(account.computed_churn_risk_score),  sub: c.label, tone: c.tone },
            { label: 'Expansion',    value: fmtScore(account.computed_expansion_score),   sub: e.label, tone: e.tone },
          ].map(t => (
            <div key={t.label} className="ist">
              <p className="ist-label">{t.label}</p>
              <p className="ist-value">{t.value}</p>
              <span className={`ist-badge ist-${t.tone}`}>{t.sub}</span>
            </div>
          ))}
        </div>

        {/* B. Recommended Next Steps */}
        <div className="insp-card">
          <div className="insp-card-top">
            <p className="insp-sec-label">Recommended Next Steps</p>
            <span className={priorityChip(account.recommended_action_priority)}>{account.recommended_action_priority}</span>
          </div>
          <div className="insp-action-title">{account.recommended_action_type}</div>
          {account.timeline_label && (
            <div className="pb-timeline">
              <CalendarClock size={12} />
              {account.timeline_label}
            </div>
          )}
          <div className="insp-meta-grid">
            <div className="insp-meta-item">
              <UserRound size={13} />
              <div><p className="imk">Owner</p><p className="imv">{account.suggested_owner_role || '—'}</p></div>
            </div>
            <div className="insp-meta-item">
              <CalendarClock size={13} />
              <div><p className="imk">Due</p><p className="imv">{account.recommended_due_date || '—'}</p></div>
            </div>
          </div>
          {account.recommended_next_action && <p className="insp-desc">{account.recommended_next_action}</p>}
          <button className="btn-primary insp-outreach-btn" onClick={onOutreach}>Create outreach task</button>
        </div>

        {/* Fallback when no playbook data available */}
        {!hasPlaybook && (
          <div className="pb-empty">No deterministic playbook available for this account yet.</div>
        )}

        {/* C. Immediate Steps */}
        {immSteps.length > 0 && (
          <div className="insp-card">
            <p className="insp-sec-label">Immediate Steps</p>
            <ol className="pb-step-list">
              {immSteps.map((step, i) => (
                <li key={i} className="pb-step-item">{step}</li>
              ))}
            </ol>
          </div>
        )}

        {/* D. Phase 2 Follow-up */}
        {p2Steps.length > 0 && (
          <div className="insp-card">
            <p className="insp-sec-label">Phase 2 Follow-up</p>
            <ol className="pb-step-list pb-step-list--phase2">
              {p2Steps.map((step, i) => (
                <li key={i} className="pb-step-item">{step}</li>
              ))}
            </ol>
          </div>
        )}

        {/* E. Success Metrics */}
        {metrics.length > 0 && (
          <div className="insp-card">
            <p className="insp-sec-label">Success Metrics</p>
            <div className="pb-metrics-list">
              {metrics.map((m, i) => (
                <div key={i} className="pb-metric-item">
                  <Check size={13} className="pb-check-icon" />
                  <span>{m}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* F. Escalation Guidance */}
        {account.escalation_guidance && (
          <div className="pb-escalation-card">
            <div className="pb-esc-hdr">
              <AlertTriangle size={13} />
              <span>Escalation Guidance</span>
            </div>
            <p className="pb-esc-text">{account.escalation_guidance}</p>
          </div>
        )}

        {/* G. Human review */}
        {account.needs_human_review && (
          <div className="insp-review-banner">
            <div className="rev-hdr"><AlertCircle size={14} /><span className="rev-title">Human Review Required</span></div>
            {account.human_review_reason && <p className="rev-reason">{account.human_review_reason}</p>}
          </div>
        )}

        {/* H. Explain This Plan (AI — on-demand only) */}
        <div className="insp-card">
          <div className="ai-hdr-row">
            <span className="ai-icon-badge"><Sparkles size={14} /></span>
            <span className="ai-title">Why This Plan Makes Sense</span>
          </div>
          <p className="ai-subtitle">AI explains deterministic recommendations. It does not calculate scores or next steps.</p>

          {!aiExplanation && !aiLoading && !aiError && (
            <button className="ai-gen-btn" onClick={handleAI}>
              <Sparkles size={14} /> Explain This Plan
            </button>
          )}

          {aiLoading && (
            <div className="ai-loading">
              <div className="ai-loading-row">
                <Loader2 size={14} className="spin" style={{ color: 'var(--primary)' }} />
                Generating explanation…
              </div>
              <div className="ai-shimmer-bars">
                {[92, 78, 85, 64].map(w => (
                  <div key={w} className="ai-shimmer-bar" style={{ width: `${w}%` }}>
                    <span className="ai-shimmer-sweep" />
                  </div>
                ))}
              </div>
            </div>
          )}

          {aiError && !aiLoading && <div className="ai-error">{aiError}</div>}

          {aiExplanation && !aiLoading && (
            <div className="ai-response">
              <div className="ai-sec">
                <p className="ai-sec-label">Summary</p>
                <p className="ai-sec-text">{aiExplanation.ai_summary}</p>
              </div>
              <div className="ai-sec">
                <p className="ai-sec-label">Account Status</p>
                <div className="ai-status-chips">
                  {[
                    { k: 'Health',    v: fmtScore(account.computed_health_score) },
                    { k: 'Churn',     v: fmtScore(account.computed_churn_risk_score) },
                    { k: 'Expansion', v: fmtScore(account.computed_expansion_score) },
                  ].map(x => (
                    <div key={x.k} className="ai-status-chip">
                      <p className="ai-chip-val">{x.v}</p>
                      <p className="ai-chip-key">{x.k}</p>
                    </div>
                  ))}
                </div>
                {aiExplanation.account_status_explanation && (
                  <p className="ai-sec-text" style={{ marginTop: 6 }}>{aiExplanation.account_status_explanation}</p>
                )}
              </div>
              {aiExplanation.key_signal_drivers.length > 0 && (
                <div className="ai-sec">
                  <p className="ai-sec-label">Key Signal Drivers</p>
                  {aiExplanation.key_signal_drivers.map((s, i) => (
                    <div key={i} className="ai-signal">
                      <div className="ai-sig-top">
                        <span className="ai-sig-name">{i + 1}. {s.signal}</span>
                        <span className="ai-sig-val">{s.value}</span>
                      </div>
                      <p className="ai-sig-interp">{s.interpretation}</p>
                    </div>
                  ))}
                </div>
              )}
              {aiExplanation.recommended_next_step && (
                <div className="ai-next-step">
                  <div className="ai-ns-hdr">
                    <ArrowRight size={12} style={{ color: 'var(--success-soft-fg)' }} />
                    <span>Recommended Next Step</span>
                  </div>
                  <p className="ai-ns-text">{aiExplanation.recommended_next_step}</p>
                </div>
              )}
              {aiExplanation.why_this_action_matters && (
                <div className="ai-sec">
                  <p className="ai-sec-label">Why This Action Matters</p>
                  <p className="ai-sec-text">{aiExplanation.why_this_action_matters}</p>
                </div>
              )}
              {aiExplanation.confidence_note && (
                <div className="ai-sec">
                  <p className="ai-sec-label">Confidence</p>
                  <p className="ai-sec-text">{aiExplanation.confidence_note}</p>
                </div>
              )}
              <div className="ai-guardrail">{aiExplanation.guardrail_note}</div>
              <p className="ai-model">via {aiExplanation.model_used}</p>
            </div>
          )}
        </div>

        {/* I. Account Profile */}
        <div className="insp-card">
          <p className="insp-sec-label">Account Profile</p>
          <div className="insp-profile">
            {[
              ['Industry',        account.industry || '—'],
              ['Segment',         account.segment || '—'],
              ['Plan',            account.plan_type || '—'],
              ['Size',            `${account.company_size ?? '—'} employees`],
              ['Account Owner',   account.account_owner || '—'],
              ['ARR',             fmtMoney(account.annual_recurring_revenue)],
              ['Days to Renewal', String(account.days_until_renewal ?? '—')],
              ['Motion',          account.primary_business_motion || '—'],
            ].map(([k, v]) => (
              <div key={k} className="ipg-row">
                <span className="ipg-k">{k}</span>
                <span className="ipg-v">{v}</span>
              </div>
            ))}
          </div>
        </div>

      </div>
    </aside>
  );
}

// ─── App ──────────────────────────────────────────────────────────────────────

export default function App() {
  const [kpis,          setKpis]          = useState<KPIs | null>(null);
  const [riskSummary,   setRiskSummary]   = useState<RiskSummaryItem[]>([]);
  const [actionSummary, setActionSummary] = useState<ActionSummaryItem[]>([]);
  const [ownerWorkload, setOwnerWorkload] = useState<OwnerWorkloadItem[]>([]);
  const [accounts,      setAccounts]      = useState<Account[]>([]);
  const [loading,       setLoading]       = useState(true);
  const [error,         setError]         = useState<string | null>(null);
  const [isRefreshing,  setIsRefreshing]  = useState(false);
  const [lastRefreshed, setLastRefreshed] = useState<Date | null>(null);
  const [activeView,    setActiveView]    = useState<ActiveView>('dashboard');
  const [selected,      setSelected]      = useState<Account | null>(null);
  const [drawerOpen,    setDrawerOpen]    = useState(false);
  const [showOutreach,  setShowOutreach]  = useState(false);
  const [globalSearch,  setGlobalSearch]  = useState('');

  const isFirstLoad      = useRef(true);
  const searchInputRef   = useRef<HTMLInputElement | null>(null);
  const searchValueRef   = useRef('');

  // Keep a ref to the current search value so the keyboard handler is stable
  useEffect(() => { searchValueRef.current = globalSearch; }, [globalSearch]);

  // Open the drawer and select an account together
  const handleSelectAccount = useCallback((a: Account) => {
    setSelected(a);
    setDrawerOpen(true);
  }, []);

  // Keyboard shortcuts — stable effect, reads refs for current values
  useEffect(() => {
    const fn = (e: KeyboardEvent) => {
      // ⌘K / Ctrl+K → focus search
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        searchInputRef.current?.focus();
        searchInputRef.current?.select();
        return;
      }
      if (e.key === 'Escape') {
        const isSearchFocused = document.activeElement === searchInputRef.current;
        if (isSearchFocused && searchValueRef.current.length > 0) {
          // First Escape clears search
          setGlobalSearch('');
          return;
        }
        // Second Escape (or Escape elsewhere) closes drawer
        setDrawerOpen(false);
        searchInputRef.current?.blur();
      }
    };
    document.addEventListener('keydown', fn);
    return () => document.removeEventListener('keydown', fn);
  }, []);

  const loadData = useCallback(async (manual = false) => {
    if (manual) setIsRefreshing(true);
    try {
      const [k, r, a, o, accts] = await Promise.all([
        getDashboardKpis(), getRiskSummary(), getActionSummary(),
        getOwnerWorkload(), getAccounts(),
      ]);
      setKpis(k);
      setRiskSummary(r);
      setActionSummary(a);
      setOwnerWorkload(o);
      setAccounts(accts);
      setLastRefreshed(new Date());
      setError(null);
      if (isFirstLoad.current) {
        isFirstLoad.current = false;
        setLoading(false);
        const def = accts.find(ac => ac.company_name.toLowerCase().includes('ledger')) ?? accts[0] ?? null;
        setSelected(def);
      }
    } catch (err) {
      const msg = (err as Error).message;
      setError(msg);
      if (isFirstLoad.current) { isFirstLoad.current = false; setLoading(false); }
    } finally {
      if (manual) setIsRefreshing(false);
    }
  }, []);

  useEffect(() => {
    loadData();
    const id = setInterval(() => loadData(), 60_000);
    return () => clearInterval(id);
  }, [loadData]);

  // Clear global search on view change
  useEffect(() => { setGlobalSearch(''); }, [activeView]);

  const VIEW_TITLE: Record<ActiveView, string> = {
    dashboard:         'Customer Revenue Intelligence Engine',
    accounts:          'Account Intelligence',
    'risk-review':     'Risk Review',
    expansion:         'Expansion Opportunities',
    'human-review':    'Human Review Queue',
    'ai-explanations': 'AI Explanations',
    'data-sources':    'Data Sources',
    'metric-library':  'Metric Library',
    settings:          'Settings',
    'users-teams':     'Users & Teams',
  };
  const VIEW_SUB: Record<ActiveView, string> = {
    dashboard:         'Operational dashboard for churn prevention, expansion discovery, and account prioritization.',
    accounts:          'Search and inspect all 100 active accounts by health, churn risk, and expansion signal.',
    'risk-review':     'Critical and high-risk accounts requiring immediate save or recover motions.',
    expansion:         'Accounts with strong upsell signals ready for expansion plays.',
    'human-review':    'Accounts flagged for human judgment before automated action proceeds.',
    'ai-explanations': 'Account intelligence with AI-generated plain-English explanations on demand.',
    'data-sources':    'How customer data flows from source systems to the revenue intelligence layer.',
    'metric-library':  'Definitions and computation logic for all computed scores and signals.',
    settings:          'Configuration and runtime details for your Revenue Intelligence Engine deployment.',
    'users-teams':     'Owner workload distribution and team assignments across the portfolio.',
  };

  if (loading) {
    return (
      <div style={{ display: 'flex', height: '100vh', alignItems: 'center', justifyContent: 'center', flexDirection: 'column', gap: 14, background: 'var(--bg)' }}>
        <Loader2 size={32} style={{ color: 'var(--primary)', animation: 'spin360 1s linear infinite' }} />
        <p style={{ fontSize: 13, color: 'var(--muted-fg)' }}>Loading Revenue Intelligence Engine…</p>
      </div>
    );
  }

  return (
    <>
      <div className="app-shell">
        <Sidebar activeView={activeView} onNav={setActiveView} lastRefreshedAt={lastRefreshed} />

        <div className="main-area">
          <TopHeader
            title={VIEW_TITLE[activeView]}
            subtitle={VIEW_SUB[activeView]}
            isRefreshing={isRefreshing}
            lastRefreshedAt={lastRefreshed}
            onRefresh={() => loadData(true)}
            onSearch={setGlobalSearch}
            searchValue={globalSearch}
            drawerOpen={drawerOpen}
            onToggleDrawer={() => {
              if (!drawerOpen && !selected && accounts.length > 0) {
                setSelected(
                  accounts.find(a => a.company_name.toLowerCase().includes('ledger'))
                  ?? accounts[0],
                );
              }
              setDrawerOpen(v => !v);
            }}
            searchInputRef={searchInputRef}
            selectedAccountName={selected?.company_name ?? null}
          />

          <SelectedAccountStrip
            account={selected}
            onOpen={() => setDrawerOpen(true)}
          />

          <div className="content-shell">
          <div className="content">
            {error && (
              <div style={{ background: 'var(--critical-soft)', border: '1px solid hsl(8,60%,80%)', borderRadius: 'var(--r)', padding: '14px 18px', fontSize: 12.5, color: 'var(--critical-soft-fg)', lineHeight: 1.55 }}>
                <strong>Backend connection failed.</strong> Start FastAPI at http://127.0.0.1:8000 and refresh. Error: {error}
              </div>
            )}

            {activeView === 'dashboard' && kpis && (
              <DashboardView
                kpis={kpis}
                riskSummary={riskSummary}
                actionSummary={actionSummary}
                accounts={accounts}
                selectedId={selected?.account_id ?? null}
                onSelect={handleSelectAccount}
                onNav={setActiveView}
                globalSearch={globalSearch}
              />
            )}

            {activeView === 'accounts' && (
              <AccountTable
                key="accounts"
                accounts={accounts}
                selectedId={selected?.account_id ?? null}
                onSelect={handleSelectAccount}
                globalSearch={globalSearch}
                title="All Accounts"
                subtitle="Full portfolio. Use filters and search to find any customer."
              />
            )}

            {activeView === 'risk-review' && (
              <RiskReviewView
                accounts={accounts}
                selectedId={selected?.account_id ?? null}
                onSelect={handleSelectAccount}
                globalSearch={globalSearch}
              />
            )}

            {activeView === 'expansion' && (
              <ExpansionView
                accounts={accounts}
                selectedId={selected?.account_id ?? null}
                onSelect={handleSelectAccount}
                globalSearch={globalSearch}
              />
            )}

            {activeView === 'human-review' && (
              <HumanReviewView
                accounts={accounts}
                selectedId={selected?.account_id ?? null}
                onSelect={handleSelectAccount}
                globalSearch={globalSearch}
              />
            )}

            {activeView === 'ai-explanations' && (
              <AiExplanationsView
                accounts={accounts}
                selectedId={selected?.account_id ?? null}
                onSelect={handleSelectAccount}
                globalSearch={globalSearch}
              />
            )}

            {activeView === 'data-sources'   && <DataSourcesView />}
            {activeView === 'metric-library'  && <MetricLibraryView />}
            {activeView === 'settings'        && <SettingsView />}
            {activeView === 'users-teams'     && <OwnerWorkloadTable rows={ownerWorkload} />}
          </div>

          <div className={`inspector-panel${drawerOpen ? ' panel-open' : ''}`}>
            <AccountInspector
              account={selected}
              onClose={() => setDrawerOpen(false)}
              onOutreach={() => setShowOutreach(true)}
            />
          </div>
          </div>
        </div>
      </div>

      {showOutreach && selected && (
        <OutreachModal account={selected} onClose={() => setShowOutreach(false)} />
      )}
    </>
  );
}