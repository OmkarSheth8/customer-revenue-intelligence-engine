"""
Reference script documenting the synthetic data generation approach used for the
Customer Revenue Intelligence Engine.

This file is intended for transparency and reproducibility documentation.
It should not be treated as the production backend runtime.

The production app reads from Supabase PostgreSQL via FastAPI.
The actual generation was done in the Jupyter notebooks under notebooks/.
"""

import random
import uuid
from datetime import datetime, timedelta

# ============================================================
# Configuration
# ============================================================

RANDOM_SEED = 42
random.seed(RANDOM_SEED)

NUM_ACCOUNTS = 100
NUM_OPPORTUNITIES = 150
NUM_ACTIONS = 250
NUM_SCORE_HISTORY_RECORDS = 1200  # 12 per account
NUM_EXPERIMENTS = 20
NUM_SYSTEM_LOGS = 500

REFERENCE_DATE = datetime(2026, 6, 28)

INDUSTRIES = ["FinTech", "MarTech", "EdTech", "HealthTech", "LegalTech", "SalesTech", "HRTech"]
SEGMENTS = ["Startup", "Mid-Market", "Enterprise"]
PLAN_TYPES = ["Starter", "Professional", "Enterprise"]
CUSTOMER_STAGES = ["Active", "Healthy", "At Risk", "Onboarding", "Churned"]
ACCOUNT_OWNERS = ["Sarah Johnson", "Michael Chen", "Emily Davis", "James Wilson", "David Rodriguez"]

EVENT_TYPES = ["Login", "Dashboard Viewed", "Report Created", "Integration Connected", "API Call", "Export", "Invite User"]
FEATURE_NAMES = ["Dashboard", "Reports", "Settings", "Integrations", "Analytics", "API", "Admin"]

PIPELINE_STAGES = ["Prospecting", "Qualification", "Proposal", "Negotiation", "Closed Won", "Closed Lost"]
OPPORTUNITY_TYPES = ["Renewal", "Expansion", "Upsell", "Cross-sell"]

ACTION_STATUSES = ["Pending", "In Progress", "Completed", "Dismissed"]
ACTION_PRIORITIES = ["Critical", "High", "Medium", "Low"]

LOG_TYPES = ["Export", "Validation", "AI Generation", "Import", "Scoring"]
LOG_COMPONENTS = ["Data Ingestion", "Monitoring", "API", "Scoring Engine", "Playbook Engine"]
LOG_STATUSES = ["Success", "Failed", "Warning"]


# ============================================================
# Generator functions (reference outlines)
# ============================================================

def generate_account_id():
    return str(uuid.uuid4())


def generate_accounts(n=NUM_ACCOUNTS):
    """
    Generate synthetic B2B SaaS account records.

    Key design decisions:
    - ARR varies by plan type and segment
    - Renewal dates spread across 12-24 months from reference date
    - Customer stage distribution: ~60% Active/Healthy, ~25% At Risk, ~15% other
    """
    accounts = []
    for _ in range(n):
        account_id = generate_account_id()
        segment = random.choice(SEGMENTS)
        plan_type = random.choice(PLAN_TYPES)

        # ARR varies by plan and segment
        arr_base = {"Starter": 10000, "Professional": 50000, "Enterprise": 200000}[plan_type]
        arr = round(arr_base * random.uniform(0.5, 3.0), 2)

        contract_start = REFERENCE_DATE - timedelta(days=random.randint(30, 730))
        renewal_date = contract_start + timedelta(days=365)

        accounts.append({
            "account_id": account_id,
            "company_name": f"SyntheticCo_{account_id[:8]}",
            "industry": random.choice(INDUSTRIES),
            "segment": segment,
            "company_size": random.randint(10, 5000),
            "annual_recurring_revenue": arr,
            "plan_type": plan_type,
            "customer_stage": random.choice(CUSTOMER_STAGES),
            "account_owner": random.choice(ACCOUNT_OWNERS),
            "contract_start_date": contract_start.date(),
            "renewal_date": renewal_date.date(),
            "created_at": contract_start,
            "updated_at": REFERENCE_DATE,
        })
    return accounts


def generate_product_usage_events(accounts):
    """
    Generate raw product usage events.

    Key design decisions:
    - At-risk accounts receive fewer events (signal of churn risk)
    - Healthy accounts receive 80-200 events in the last 30 days
    - Events span 12+ months of history per account
    - Multiple users per account (user_id derived from account_id + user index)
    """
    events = []
    for account in accounts:
        # Usage volume varies by account health
        num_events = random.randint(5, 500)
        num_users = random.randint(1, 80)

        for _ in range(num_events):
            event_timestamp = REFERENCE_DATE - timedelta(
                days=random.randint(0, 365),
                hours=random.randint(0, 23),
                minutes=random.randint(0, 59)
            )
            user_index = random.randint(1, num_users)
            events.append({
                "event_id": str(uuid.uuid4()),
                "account_id": account["account_id"],
                "user_id": f"{account['account_id']}_user_{user_index}",
                "event_type": random.choice(EVENT_TYPES),
                "feature_name": random.choice(FEATURE_NAMES),
                "session_duration_minutes": round(random.uniform(0.5, 60.0), 2),
                "event_timestamp": event_timestamp,
            })
    return events


def generate_customer_engagement(accounts):
    """
    Generate one engagement record per account.

    Key design decisions:
    - NPS ranges 1-10, biased toward at-risk vs healthy profiles
    - Support tickets spike for at-risk accounts
    - last_touch_date within the last 90 days
    """
    records = []
    for account in accounts:
        at_risk = account["customer_stage"] == "At Risk"
        records.append({
            "engagement_id": str(uuid.uuid4()),
            "account_id": account["account_id"],
            "emails_opened": random.randint(0, 30),
            "emails_replied": random.randint(0, 10),
            "meetings_last_30_days": random.randint(0, 5),
            "support_tickets_last_30_days": random.randint(5, 15) if at_risk else random.randint(0, 4),
            "nps_score": random.randint(1, 5) if at_risk else random.randint(5, 10),
            "last_touch_date": (REFERENCE_DATE - timedelta(days=random.randint(1, 90))).date(),
        })
    return records


def generate_crm_opportunities(accounts, n=NUM_OPPORTUNITIES):
    """
    Generate CRM opportunities -- approximately 1.5 per account on average.
    Includes Renewal, Expansion, Upsell, and Cross-sell types.
    """
    opportunities = []
    for _ in range(n):
        account = random.choice(accounts)
        stage = random.choice(PIPELINE_STAGES)
        amount = round(random.uniform(10000, 500000), 2)
        probability = random.randint(10, 90)
        created = REFERENCE_DATE - timedelta(days=random.randint(30, 180))
        close_date = created + timedelta(days=random.randint(30, 365))

        opportunities.append({
            "opportunity_id": str(uuid.uuid4()),
            "account_id": account["account_id"],
            "opportunity_type": random.choice(OPPORTUNITY_TYPES),
            "pipeline_stage": stage,
            "amount": amount,
            "probability": probability,
            "created_date": created.date(),
            "expected_close_date": close_date.date(),
            "last_activity_date": (REFERENCE_DATE - timedelta(days=random.randint(1, 60))).date(),
        })
    return opportunities


def generate_score_history(accounts, records_per_account=12):
    """
    Generate 12 monthly score records per account, going back ~12 months.
    Scores reflect trends: declining for at-risk, improving for healthy accounts.
    """
    records = []
    for account in accounts:
        at_risk = account["customer_stage"] == "At Risk"
        for month_offset in range(records_per_account, 0, -1):
            score_date = REFERENCE_DATE - timedelta(days=30 * month_offset)
            trend = -1 if at_risk else 1
            health = max(10, min(100, 60 + trend * month_offset + random.randint(-5, 5)))
            churn = max(0, min(100, 40 - trend * month_offset + random.randint(-5, 5)))
            expansion = max(0, min(100, 50 + trend * month_offset + random.randint(-5, 5)))

            records.append({
                "score_id": str(uuid.uuid4()),
                "account_id": account["account_id"],
                "health_score": round(health, 2),
                "churn_score": round(churn, 2),
                "expansion_score": round(expansion, 2),
                "score_reason": "Synthetic score reason for reference.",
                "calculated_at": score_date.date(),
            })
    return records


def generate_actions(accounts, n=NUM_ACTIONS):
    """
    Generate approximately 2.5 action records per account.
    Mix of Pending, In Progress, Completed, and Dismissed statuses.
    """
    actions = []
    for _ in range(n):
        account = random.choice(accounts)
        status = random.choice(ACTION_STATUSES)
        created = REFERENCE_DATE - timedelta(days=random.randint(1, 90))
        due_date = created + timedelta(days=random.randint(1, 30))
        completed_at = due_date + timedelta(days=random.randint(0, 5)) if status == "Completed" else None

        actions.append({
            "action_id": str(uuid.uuid4()),
            "account_id": account["account_id"],
            "recommended_action": "Synthetic action description.",
            "assigned_to": random.choice(ACCOUNT_OWNERS),
            "priority": random.choice(ACTION_PRIORITIES),
            "status": status,
            "due_date": due_date.date(),
            "completed_at": completed_at,
            "outcome": "Action outcome." if status == "Completed" else None,
            "created_at": created,
        })
    return actions


def generate_experiments(n=NUM_EXPERIMENTS):
    """Generate synthetic GTM experiment records."""
    experiments = []
    names = [
        "Expansion Candidate Discovery Sequence",
        "Renewal Acceleration Campaign",
        "High-Risk Account Executive Outreach",
        "Churn Save Playbook Pilot",
        "NPS Recovery Program",
        "QBR Impact Study",
    ]
    for i in range(n):
        experiments.append({
            "experiment_id": str(uuid.uuid4()),
            "experiment_name": names[i % len(names)],
            "hypothesis": "Synthetic hypothesis.",
            "target_accounts": random.randint(10, 50),
            "success_metric": random.choice(["Churn score reduction", "Renewal cycle length", "Expansion pipeline created"]),
            "result": "Experiment showed positive impact.",
            "decision": random.choice(["Scale", "Stop", "Continue"]),
            "created_at": REFERENCE_DATE - timedelta(days=random.randint(30, 365)),
        })
    return experiments


def generate_system_logs(n=NUM_SYSTEM_LOGS):
    """Generate synthetic operational log records."""
    logs = []
    for _ in range(n):
        logs.append({
            "log_id": str(uuid.uuid4()),
            "log_type": random.choice(LOG_TYPES),
            "component": random.choice(LOG_COMPONENTS),
            "status": random.choice(LOG_STATUSES),
            "message": "Synthetic log message.",
            "created_at": REFERENCE_DATE - timedelta(days=random.randint(0, 180)),
        })
    return logs