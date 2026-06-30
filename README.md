# Customer Revenue Intelligence Engine

A full-stack revenue intelligence platform for B2B SaaS teams. Surfaces account health, churn risk, expansion opportunity, and structured action playbooks â€” all computed deterministically from behavioral signals.

**Live Demo:** [customer-revenue-intelligence-engin.vercel.app](https://customer-revenue-intelligence-engin.vercel.app)
**API:** [customer-revenue-intelligence-engine.onrender.com](https://customer-revenue-intelligence-engine.onrender.com)
**Health:** [/health](https://customer-revenue-intelligence-engine.onrender.com/health)

---

## What It Does

The system ingests product usage, CRM pipeline, support ticket volume, NPS scores, engagement history, and open action items â€” and converts those signals into a prioritized account queue with a structured action plan for every account.

Every CSM, AE, or RevOps manager gets:

- A real-time **account health, churn risk, and expansion score** for each account
- A **priority tier and business motion** (Save, Recover, Renewal, Expand, Maintain, Monitor)
- A **deterministic action playbook**: immediate steps, phase 2 follow-up, success metrics, escalation guidance
- An **on-demand AI explanation** of why that specific playbook was assigned

---

## Who It's For

| Team | How It Helps |
|---|---|
| **Customer Success** | See which accounts need attention today and get a 5-step action plan for each |
| **Revenue / RevOps** | Understand portfolio-level ARR at risk, expansion pipeline, and owner workload |
| **GTM / Sales** | Identify accounts ready for expansion discovery and track renewal timing |
| **Leadership** | Review accounts flagged for human escalation with a plain-language reason |

---

## Deterministic Intelligence â€” Not AI Inference

> **Scores, risk levels, recommended actions, owner assignments, due dates, immediate steps, phase 2 follow-up, success metrics, and escalation guidance are all calculated by deterministic SQL logic applied to behavioral signals.**
>
> **AI only explains the already-computed recommendation. It does not calculate scores, generate new next steps, or override classifications.**

Every decision in this system is traceable to a specific SQL formula. There is no ML model, no stochastic inference, and no black box in the core intelligence layer.

---

## System Architecture

```mermaid
flowchart LR
    subgraph "Supabase PostgreSQL"
        A[Raw Tables\n8 base tables] --> B[Feature Engineering\nSQL views]
        B --> C[Scoring Engine\nhealth Â· churn Â· expansion]
        C --> D[Actions Engine\npriority Â· owner Â· due date]
        D --> E[Action Playbook\nimmediate Â· phase2 Â· metrics Â· escalation]
        E --> F[Intelligence View\nsingle source of truth]
    end

    subgraph "Render â€” FastAPI"
        G[REST API]
        H[AI Explanation\nOpenAI gpt-4o-mini]
    end

    subgraph "Vercel â€” React/Vite"
        I[Dashboard]
    end

    F --> G
    G --> I
    G --> H
    H --> I
```

**Data flow:** Raw behavioral data â†’ SQL feature engineering â†’ deterministic scoring â†’ rule-based action assignment â†’ structured playbook â†’ FastAPI REST endpoints â†’ React dashboard.

AI is a read-only layer that receives the completed playbook and explains it. It writes nothing.

---

## Screenshots

<!-- TODO: Add screenshots after capturing from the live app -->
<!-- Image paths are reserved below â€” drop PNG files into assets/screenshots/ -->

**Dashboard overview**
![Dashboard](assets/screenshots/dashboard.png)

**Account detail panel**
![Account Detail](assets/screenshots/account-detail.png)

**AI explanation panel**
![AI Explanation](assets/screenshots/ai-explanation.png)

---

## Tech Stack

### Data & Intelligence
| Layer | Technology |
|---|---|
| Database | Supabase PostgreSQL (hosted) |
| Scoring engine | Pure SQL views â€” no ORM, no ML |
| Feature engineering | 9 SQL views, one per signal group |
| Action playbook | `CASE`-based SQL view, 11 action types Ã— 4 signal flags |

### Backend
| Package | Purpose |
|---|---|
| FastAPI | REST API framework |
| SQLAlchemy | DB connection and query execution |
| psycopg2-binary | PostgreSQL driver |
| Uvicorn | ASGI server |
| python-dotenv | Env var management |
| openai | AI explanation API calls |

### Frontend
| Package | Purpose |
|---|---|
| React 19 + TypeScript | UI framework |
| Vite | Build tool and dev server |
| Recharts | Portfolio charts (risk, actions, workload) |
| Lucide React | Icon library |

### Deployment
| Service | Role |
|---|---|
| Supabase | PostgreSQL database (hosted, managed) |
| Render | FastAPI backend (Python web service) |
| Vercel | React/Vite frontend (static build) |

---

## Key Features

**Deterministic scoring.** Health, churn risk, and expansion scores are weighted composites of behavioral signals â€” usage events, active users, NPS, support load, renewal proximity, pipeline value. Every weight is visible in SQL.

**11-action-type playbook engine.** The recommended actions engine classifies each account into one of 11 action types (Immediate Churn Intervention, Expansion Discovery, Renewal Risk Review, etc.) with a matching 5-step immediate action plan, phase 2 follow-up, and measurable success metrics â€” all generated from SQL signal flags.

**Priority-ranked account queue.** Accounts are sorted by a composite urgency score combining action priority, churn risk, and renewal timing. The most critical accounts always surface first.

**Human review flagging.** Accounts are automatically flagged when they meet rules-based escalation criteria â€” critical action priority, high churn risk, renewal within 30 days â€” with a machine-generated plain-language reason.

**Motion-based filtering.** Every account is assigned a business motion: Save, Recover, Renewal, Expand, Maintain, or Monitor. Teams can filter the account list by motion type.

**On-demand AI explanation.** Clicking "Explain This Plan" sends the deterministic context â€” scores, classification, behavioral signals, and the full playbook â€” to OpenAI. The AI explains why the plan fits the signals. It cannot modify the plan.

**Inline account detail panel.** Selecting an account pushes the main dashboard left and reveals a detail panel showing score tiles, the full deterministic playbook, and the AI explanation section. No modal, no overlay.

---

## Local Setup

### Prerequisites

- Python 3.11+
- Node.js 20+
- PostgreSQL 14+ (or use the Supabase project directly)

### 1. Clone

```bash
git clone https://github.com/OmkarSheth8/customer-revenue-intelligence-engine
cd customer-revenue-intelligence-engine
```

### 2. Backend

```bash
cd backend
python -m venv venv
source venv/bin/activate      # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

Copy the example env file and fill in your values:

```bash
cp .env.example .env
```

```
DATABASE_URL=postgresql://user:password@host:5432/database
OPENAI_API_KEY=sk-...        # Required only for AI explanation feature
OPENAI_MODEL=gpt-4o-mini
```

Start the API:

```bash
uvicorn main:app --reload
# API at http://127.0.0.1:8000
# Swagger docs at http://127.0.0.1:8000/docs
```

### 3. Frontend

```bash
cd frontend
npm install
npm run dev
# Dashboard at http://localhost:5173
```

The Vite dev server proxies `/api/*` to `http://127.0.0.1:8000`. No frontend env file needed for local development.

### 4. Database (optional â€” use deployment/schema_supabase_clean.sql)

To load the full schema and synthetic dataset into your own PostgreSQL instance:

```bash
psql "postgresql://user:password@host:5432/database" -f deployment/schema_supabase_clean.sql
psql "postgresql://user:password@host:5432/database" -f deployment/data.sql
```

---

## API Reference

| Method | Endpoint | Description |
|---|---|---|
| GET | `/health` | Service health check |
| GET | `/accounts` | All accounts, sorted by priority rank |
| GET | `/accounts/{id}` | Single account detail |
| GET | `/accounts/high-risk` | Critical and high-risk accounts |
| GET | `/accounts/expansion-ready` | High-expansion-score accounts |
| GET | `/accounts/review-needed` | Accounts flagged for human review |
| GET | `/accounts/motion/{motion}` | Filter by business motion |
| GET | `/dashboard/kpis` | Portfolio KPI summary |
| GET | `/dashboard/risk-summary` | Risk distribution by level |
| GET | `/dashboard/action-summary` | Action type distribution |
| GET | `/dashboard/owner-workload` | Workload per owner role |
| POST | `/accounts/{id}/ai-explanation` | On-demand AI explanation of the account's playbook |

Full interactive docs: [customer-revenue-intelligence-engine.onrender.com/docs](https://customer-revenue-intelligence-engine.onrender.com/docs)

---

## Security

- `.env` files are excluded from version control via `.gitignore`
- No database passwords, API keys, or Supabase credentials are committed to this repository
- See `backend/.env.example` and `frontend/.env.example` for the required variable names
- Production secrets are managed via Render and Vercel environment variable dashboards
