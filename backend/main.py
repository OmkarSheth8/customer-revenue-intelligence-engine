import json
import os
from pathlib import Path

from dotenv import load_dotenv

# Load .env from the backend directory regardless of where uvicorn is launched from.
# override=True ensures stale Windows process env vars don't shadow .env values.
_BASE_DIR = Path(__file__).resolve().parent
load_dotenv(_BASE_DIR / ".env", override=True)

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from openai import OpenAI
from pydantic import BaseModel

from database import fetch_all, fetch_one

app = FastAPI(
    title="Customer Revenue Intelligence API",
    description="Backend API for customer health, churn risk, expansion, and recommended actions.",
    version="1.0.0"
)

# Local dev origins always allowed.
_LOCAL_ORIGINS = [
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "http://localhost:5173",
    "http://127.0.0.1:5173",
    "http://localhost:5174",
    "http://127.0.0.1:5174",
]

# Production origins from env — set FRONTEND_URL or ALLOWED_ORIGINS (comma-separated) on Render.
_frontend_url   = os.getenv("FRONTEND_URL", "").strip()
_extra_origins  = [o.strip() for o in os.getenv("ALLOWED_ORIGINS", "").split(",") if o.strip()]
if _frontend_url and _frontend_url not in _extra_origins:
    _extra_origins.append(_frontend_url)

app.add_middleware(
    CORSMiddleware,
    allow_origins=_LOCAL_ORIGINS + _extra_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
def root():
    return {
        "message": "Customer Revenue Intelligence API is running"
    }


@app.get("/health")
def health_check():
    return {
        "status": "ok"
    }


@app.get("/dashboard/kpis")
def get_dashboard_kpis():
    query = """
        SELECT *
        FROM core.dashboard_kpis;
    """
    return fetch_one(query)


@app.get("/dashboard/risk-summary")
def get_risk_summary():
    query = """
        SELECT *
        FROM core.dashboard_risk_summary;
    """
    return fetch_all(query)


@app.get("/dashboard/action-summary")
def get_action_summary():
    query = """
        SELECT *
        FROM core.dashboard_action_summary;
    """
    return fetch_all(query)


@app.get("/dashboard/owner-workload")
def get_owner_workload():
    query = """
        SELECT *
        FROM core.dashboard_owner_workload;
    """
    return fetch_all(query)


@app.get("/accounts")
def get_accounts():
    query = """
        SELECT
            account_id,
            company_name,
            industry,
            segment,
            company_size,
            annual_recurring_revenue,
            plan_type,
            customer_stage,
            account_owner,
            days_until_renewal,
            computed_health_score,
            computed_churn_risk_score,
            computed_expansion_score,
            risk_level,
            expansion_level,
            customer_priority_tier,
            health_status,
            churn_status,
            expansion_status,
            primary_business_motion,
            recommended_action_type,
            recommended_action_priority,
            suggested_owner_role,
            recommended_due_date,
            needs_human_review,
            human_review_reason,
            recommended_next_action,
            recommendation_reason,
            ai_explanation_context,
            immediate_next_steps,
            phase_2_next_steps,
            success_metrics,
            escalation_guidance,
            timeline_label,
            playbook_version
        FROM core.account_intelligence_view
        ORDER BY
            dashboard_priority_rank ASC,
            computed_churn_risk_score DESC,
            days_until_renewal ASC;
    """
    return fetch_all(query)


@app.get("/accounts/high-risk")
def get_high_risk_accounts():
    query = """
        SELECT *
        FROM core.account_intelligence_view
        WHERE risk_level IN ('Critical Risk', 'High Risk')
        ORDER BY
            computed_churn_risk_score DESC,
            days_until_renewal ASC;
    """
    return fetch_all(query)


@app.get("/accounts/expansion-ready")
def get_expansion_ready_accounts():
    query = """
        SELECT *
        FROM core.account_intelligence_view
        WHERE expansion_level = 'High Expansion'
        ORDER BY
            computed_expansion_score DESC,
            open_pipeline_value DESC;
    """
    return fetch_all(query)


@app.get("/accounts/review-needed")
def get_review_needed_accounts():
    query = """
        SELECT *
        FROM core.account_intelligence_view
        WHERE needs_human_review = TRUE
        ORDER BY
            dashboard_priority_rank ASC,
            computed_churn_risk_score DESC,
            days_until_renewal ASC;
    """
    return fetch_all(query)


@app.get("/accounts/motion/{motion}")
def get_accounts_by_motion(motion: str):
    allowed_motions = {"Save", "Recover", "Renewal", "Expand", "Maintain", "Monitor"}

    if motion not in allowed_motions:
        raise HTTPException(
            status_code=400,
            detail="Invalid motion. Use Save, Recover, Renewal, Expand, Maintain, or Monitor."
        )

    query = """
        SELECT *
        FROM core.account_intelligence_view
        WHERE primary_business_motion = :motion
        ORDER BY
            dashboard_priority_rank ASC,
            computed_churn_risk_score DESC,
            days_until_renewal ASC;
    """

    return fetch_all(query, {"motion": motion})


@app.get("/accounts/{account_id}")
def get_account_by_id(account_id: str):
    query = """
        SELECT *
        FROM core.account_intelligence_view
        WHERE account_id = :account_id;
    """

    account = fetch_one(query, {"account_id": account_id})

    if not account:
        raise HTTPException(status_code=404, detail="Account not found")

    return account


# ── Phase 18A: AI Explanation ─────────────────────────────────────────────────

class SignalDriver(BaseModel):
    signal: str
    value: str
    interpretation: str


class AIExplanationResponse(BaseModel):
    account_id: str
    company_name: str
    model_used: str
    ai_summary: str
    account_status_explanation: str
    key_signal_drivers: list[SignalDriver]
    recommended_next_step: str
    why_this_action_matters: str
    confidence_note: str
    guardrail_note: str


_SYSTEM_PROMPT = """
You are a customer success analyst embedded in a B2B SaaS revenue intelligence platform.

You will receive structured account data that includes:
1. Pre-computed scores (health, churn risk, expansion) produced by a deterministic PostgreSQL scoring engine.
2. A deterministic action plan with: recommended action type, immediate steps, phase 2 steps, success metrics, and escalation guidance.

Your ONLY job is to explain why the provided plan makes sense given the account's signals.

Hard rules — no exceptions:
1. Do NOT create new recommended actions or next steps. The plan is already determined.
2. Do NOT change or challenge the recommended_action_type.
3. Do NOT recalculate, adjust, or override any score. All scores are ground truth.
4. Do NOT override risk_level, expansion_level, or customer_priority_tier.
5. Every claim must be grounded in the data provided. Do not speculate.
6. In key_signal_drivers, quote exact numeric values from the context — do not round, estimate, or substitute.
7. If a field is missing or blank, say what is missing rather than inventing a value.
8. Write for a reader with 30 seconds — prioritize urgency, clarity, and action.

Your explanation must address:
1. What the health, churn risk, and expansion scores signal together for this account.
2. Which 3–5 specific metrics most justify the current classification and plan.
3. Why the recommended action type is the right response for this account's signals.
4. How the immediate steps connect to the account's signal data.
5. What the phase 2 follow-up steps are designed to accomplish.
6. What the success metrics are measuring and why they matter.
7. How confidently the team should act given the available signals.

Respond with valid JSON only. No markdown fences, no explanatory text outside the JSON:
{
  "ai_summary": "One to two sentence overview of the account situation and why the pre-determined plan makes sense.",
  "account_status_explanation": "Two to three sentences on what the health, churn risk, and expansion scores mean together for this specific account.",
  "key_signal_drivers": [
    {
      "signal": "Name of the metric",
      "value": "Exact value from the data",
      "interpretation": "One sentence explaining why this signal justifies the plan."
    }
  ],
  "recommended_next_step": "One sentence explaining why the pre-determined action type is the right response for this account right now — do not invent a different action.",
  "why_this_action_matters": "Two to three sentences connecting the immediate steps and phase 2 follow-up to the account's signals and explaining what they are designed to achieve.",
  "confidence_note": "One sentence on how confidently the team should act on this plan given the available signals."
}

Return 3–5 items in key_signal_drivers. Focus on the signals most directly tied to the recommended action type and playbook.
""".strip()


def _fmt(val: object, prefix: str = "", suffix: str = "") -> str:
    """Format an optional field for context output."""
    if val is None or val == "":
        return "—"
    return f"{prefix}{val}{suffix}"


def _build_account_context(a: dict) -> str:
    lines = [
        "ACCOUNT CONTEXT (pre-computed by PostgreSQL scoring and action playbook engine):",
        "",
        "ACCOUNT PROFILE:",
        f"  Company:            {_fmt(a.get('company_name') or a.get('account_name'))}",
        f"  Industry:           {_fmt(a.get('industry'))}",
        f"  Segment:            {_fmt(a.get('segment'))}",
        f"  Plan Type:          {_fmt(a.get('plan_type'))}",
        f"  Account Owner:      {_fmt(a.get('account_owner'))}",
        f"  Days Until Renewal: {_fmt(a.get('days_until_renewal'))}",
        "",
        "COMPUTED SCORES (ground truth — do not recalculate):",
        f"  Health Score:          {_fmt(a.get('computed_health_score'))}  ({_fmt(a.get('health_status'))})",
        f"  Churn Risk Score:      {_fmt(a.get('computed_churn_risk_score'))}  ({_fmt(a.get('churn_status'))})",
        f"  Expansion Score:       {_fmt(a.get('computed_expansion_score'))}  ({_fmt(a.get('expansion_status'))})",
        "",
        "CLASSIFICATION (ground truth — do not override):",
        f"  Risk Level:            {_fmt(a.get('risk_level'))}",
        f"  Expansion Level:       {_fmt(a.get('expansion_level'))}",
        f"  Priority Tier:         {_fmt(a.get('customer_priority_tier'))}",
        f"  Business Motion:       {_fmt(a.get('primary_business_motion'))}",
        "",
        "BEHAVIORAL SIGNALS (last 30 days):",
        f"  Usage Events:          {_fmt(a.get('usage_events_last_30_days'))}",
        f"  Active Users:          {_fmt(a.get('active_users_last_30_days'))}",
        f"  Support Tickets:       {_fmt(a.get('support_tickets_last_30_days'))}",
        f"  NPS Score:             {_fmt(a.get('nps_score'))}",
        f"  Overdue Actions:       {_fmt(a.get('overdue_action_count'))}",
        "",
        "DETERMINISTIC ACTION PLAN (do not alter — explain why this plan fits the signals above):",
        f"  Action Type:           {_fmt(a.get('recommended_action_type'))}",
        f"  Priority:              {_fmt(a.get('recommended_action_priority'))}",
        f"  Suggested Owner:       {_fmt(a.get('suggested_owner_role'))}",
        f"  Due Date:              {_fmt(a.get('recommended_due_date'))}",
        f"  Timeline:              {_fmt(a.get('timeline_label'))}",
        f"  Recommendation Reason: {_fmt(a.get('recommendation_reason'))}",
        f"  Human Review Required: {'Yes' if a.get('needs_human_review') else 'No'}",
    ]

    if a.get("human_review_reason"):
        lines.append(f"  Review Reason:         {a['human_review_reason']}")

    if a.get("recommended_next_action"):
        lines += ["", "NEXT ACTION (pre-determined — do not replace):",
                  f"  {a['recommended_next_action']}"]

    immediate = a.get("immediate_next_steps") or []
    if immediate:
        lines += ["", "IMMEDIATE STEPS (pre-determined — explain why these fit the signals, do not invent alternatives):"]
        for i, step in enumerate(immediate, 1):
            lines.append(f"  {i}. {step}")

    phase2 = a.get("phase_2_next_steps") or []
    if phase2:
        lines += ["", "PHASE 2 FOLLOW-UP STEPS (pre-determined):"]
        for i, step in enumerate(phase2, 1):
            lines.append(f"  {i}. {step}")

    metrics = a.get("success_metrics") or []
    if metrics:
        lines += ["", "SUCCESS METRICS (pre-determined — explain what each measures and why it matters):"]
        for i, m in enumerate(metrics, 1):
            lines.append(f"  {i}. {m}")

    if a.get("escalation_guidance"):
        lines += ["", "ESCALATION GUIDANCE (pre-determined):",
                  f"  {a['escalation_guidance']}"]

    return "\n".join(lines)


@app.post("/accounts/{account_id}/ai-explanation", response_model=AIExplanationResponse)
def generate_ai_explanation(account_id: str):
    _INVALID_KEYS = {"", "your-openai-api-key-here", "YOUR_OPENAI_API_KEY"}
    api_key = (os.getenv("OPENAI_API_KEY") or "").strip()
    if api_key in _INVALID_KEYS or not api_key.startswith("sk-"):
        raise HTTPException(
            status_code=500,
            detail=(
                "OpenAI API key is not configured correctly. "
                "Set OPENAI_API_KEY in backend/.env to a valid key starting with sk-."
            ),
        )

    query = """
        SELECT *
        FROM core.account_intelligence_view
        WHERE account_id = :account_id;
    """
    account = fetch_one(query, {"account_id": account_id})
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")

    model_name = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
    context_text = _build_account_context(account)

    client = OpenAI(api_key=api_key)
    try:
        completion = client.chat.completions.create(
            model=model_name,
            messages=[
                {"role": "system", "content": _SYSTEM_PROMPT},
                {"role": "user", "content": context_text},
            ],
            temperature=0.3,
            response_format={"type": "json_object"},
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"OpenAI API error: {exc}")

    raw = completion.choices[0].message.content or ""
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        raise HTTPException(
            status_code=500,
            detail="OpenAI returned non-JSON content. Check the model name and try again.",
        )

    raw_drivers = parsed.get("key_signal_drivers", [])
    signal_drivers = [
        SignalDriver(
            signal=d.get("signal", ""),
            value=str(d.get("value", "")),
            interpretation=d.get("interpretation", ""),
        )
        for d in raw_drivers
        if isinstance(d, dict)
    ]

    return AIExplanationResponse(
        account_id=account_id,
        company_name=account.get("company_name", ""),
        model_used=model_name,
        ai_summary=parsed.get("ai_summary", ""),
        account_status_explanation=parsed.get("account_status_explanation", ""),
        key_signal_drivers=signal_drivers,
        recommended_next_step=parsed.get("recommended_next_step", ""),
        why_this_action_matters=parsed.get("why_this_action_matters", ""),
        confidence_note=parsed.get("confidence_note", ""),
        guardrail_note="AI explains deterministic recommendations. It does not calculate scores or next steps.",
    )