# Deployment Guide — Customer Revenue Intelligence Engine

**Architecture:** Supabase (PostgreSQL) → Render (FastAPI) → Vercel (React/Vite)

---

## Prerequisites

- Supabase account: https://supabase.com
- Render account: https://render.com
- Vercel account: https://vercel.com
- GitHub repository with this project pushed to it
- Local PostgreSQL running on port 5433 with `customer_revenue_intelligence` database intact

---

## Deployment Order

```
1. Export local database
2. Create Supabase project → import schema + data → validate
3. Deploy backend to Render → set env vars → validate
4. Deploy frontend to Vercel → set VITE_API_BASE_URL → validate
5. Update Render FRONTEND_URL with Vercel URL
6. Final end-to-end QA
```

Do not deploy Render or Vercel until Supabase is validated. Do not finalize Render env vars until you have the Vercel URL.

---

## Step 1 — Export local database

Run these from the project root. See `deployment/export_database_commands.md` for the full command reference.

```bash
# Export schema (tables, views, indexes, constraints)
pg_dump -h localhost -p 5433 -U postgres \
  -d customer_revenue_intelligence \
  -n core \
  --schema-only \
  --no-owner \
  --no-privileges \
  > deployment/schema.sql

# Export data (INSERT statements for all 8 base tables)
pg_dump -h localhost -p 5433 -U postgres \
  -d customer_revenue_intelligence \
  -n core \
  --data-only \
  --inserts \
  --no-owner \
  --no-privileges \
  > deployment/data.sql
```

`schema.sql` and `data.sql` contain no secrets and are safe to commit.

---

## Step 2 — Create Supabase project

1. Go to https://supabase.com → New Project.
2. Choose a region close to your users.
3. Set a strong database password and save it (you will need it for `DATABASE_URL`).
4. Wait for the project to fully provision (roughly 1–2 minutes).

### Get the connection string

In Supabase dashboard → **Settings** → **Database** → **Connection string** → select **URI** mode.

It will look like:
```
postgresql://postgres:[YOUR-PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres
```

Save this — it becomes your `DATABASE_URL` on Render.

> Supabase also offers a **pooler** connection string (port 6543, pgBouncer). Use the **direct** connection string (port 5432) for this project because SQLAlchemy manages its own connection pool and pgBouncer can cause statement-mode conflicts.

---

## Step 3 — Import schema and data into Supabase

### Option A — Supabase SQL editor (recommended for first deployment)

1. In Supabase dashboard → **SQL Editor** → **New query**.
2. Paste the entire contents of `deployment/schema.sql` and click **Run**.
3. Once complete, paste the entire contents of `deployment/data.sql` and click **Run**.

If the SQL editor has a size limit, split `data.sql` into smaller batches or use Option B.

### Option B — psql direct import

```bash
# Replace the placeholders with your real Supabase connection values
psql "postgresql://postgres:[PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres" \
  -f deployment/schema.sql

psql "postgresql://postgres:[PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres" \
  -f deployment/data.sql
```

---

## Step 4 — Validate Supabase

Run these in the Supabase SQL editor after importing:

```sql
-- Base tables
SELECT COUNT(*) FROM core.accounts;
SELECT COUNT(*) FROM core.customer_engagement;
SELECT COUNT(*) FROM core.crm_opportunities;
SELECT COUNT(*) FROM core.product_usage_events;
SELECT COUNT(*) FROM core.score_history;
SELECT COUNT(*) FROM core.actions;
SELECT COUNT(*) FROM core.experiments;
SELECT COUNT(*) FROM core.system_logs;

-- Intelligence views
SELECT COUNT(*) FROM core.account_intelligence_view;
SELECT COUNT(*) FROM core.account_action_playbook;

-- Dashboard
SELECT * FROM core.dashboard_kpis;
```

**Expected results:**

| Query | Expected |
|---|---|
| `core.accounts` | 100 |
| `core.account_intelligence_view` | 100 |
| `core.account_action_playbook` | 100 |
| `dashboard_kpis.total_accounts` | 100 |

If any view returns an error, the schema import likely ran out of order. Re-run `schema.sql` — pg_dump outputs objects in dependency order so re-running is safe.

---

## Step 5 — Deploy FastAPI backend to Render

1. Go to https://render.com → **New** → **Web Service**.
2. Connect your GitHub repository.
3. Configure the service:

| Setting | Value |
|---|---|
| **Name** | `customer-revenue-intelligence-api` (or your choice) |
| **Root Directory** | `backend` |
| **Runtime** | `Python 3` |
| **Build Command** | `pip install -r requirements.txt` |
| **Start Command** | `uvicorn main:app --host 0.0.0.0 --port $PORT` |
| **Instance Type** | Free tier works for demo; upgrade for production SLA |

---

## Step 6 — Set Render environment variables

In Render dashboard → your service → **Environment** → add:

| Variable | Value |
|---|---|
| `DATABASE_URL` | Your Supabase direct connection string (see Step 2) |
| `OPENAI_API_KEY` | Your OpenAI API key (required for AI explanation feature) |
| `OPENAI_MODEL` | `gpt-4o-mini` (or `gpt-4o` for higher quality) |
| `FRONTEND_URL` | *(leave blank for now — add after Step 9)* |

> Never paste these values into any file. Set them only via the Render dashboard.

Deploy the service. Render will run `pip install -r requirements.txt` then start uvicorn.

---

## Step 7 — Validate Render backend

Once deployed, Render assigns a URL like `https://customer-revenue-intelligence-api.onrender.com`.

Test each endpoint:

```bash
# Health
curl https://your-render-url.onrender.com/health
# Expected: {"status":"ok"}

# Dashboard KPIs
curl https://your-render-url.onrender.com/dashboard/kpis
# Expected: JSON with total_accounts: 100

# Accounts
curl https://your-render-url.onrender.com/accounts
# Expected: JSON array of 100 accounts

# AI explanation (replace with a real account_id from the /accounts response)
curl -X POST https://your-render-url.onrender.com/accounts/{account_id}/ai-explanation
# Expected: JSON with ai_summary, key_signal_drivers, guardrail_note, etc.
```

If `/health` returns 200 but `/accounts` returns a database error, check that `DATABASE_URL` is set correctly in Render.

---

## Step 8 — Deploy Vite frontend to Vercel

1. Go to https://vercel.com → **New Project**.
2. Import your GitHub repository.
3. Configure:

| Setting | Value |
|---|---|
| **Framework Preset** | `Vite` |
| **Root Directory** | `frontend` |
| **Build Command** | `npm run build` |
| **Output Directory** | `dist` |

4. Before deploying, add the environment variable:

| Variable | Value |
|---|---|
| `VITE_API_BASE_URL` | `https://your-render-url.onrender.com` |

> Vercel exposes `VITE_*` variables to the browser bundle at build time. If this variable is missing, the frontend silently falls back to `/api` which will 404 in production.

5. Click **Deploy**.

---

## Step 9 — Wire Vercel URL back to Render

Once Vercel assigns your URL (e.g. `https://your-app.vercel.app`):

1. Go to Render dashboard → your backend service → **Environment**.
2. Add or update:

| Variable | Value |
|---|---|
| `FRONTEND_URL` | `https://your-app.vercel.app` |

3. Redeploy the Render service (or it will pick up the change on next deploy).

This adds the Vercel URL to the FastAPI CORS allowed origins. Without it, browser requests from Vercel will be blocked with CORS errors.

---

## Step 10 — Final end-to-end QA

Open the live Vercel URL and verify:

**Data and navigation**
- [ ] Dashboard loads with KPI cards (total accounts, critical risk, ARR)
- [ ] All KPI numbers match expectations (total = 100)
- [ ] Search works — type a company name and results filter
- [ ] Risk Review tab loads high-risk accounts
- [ ] Expansion tab loads high-expansion accounts
- [ ] Human Review tab loads review-needed accounts

**Account inspector / drawer**
- [ ] Click any account row — inspector panel opens inline (push layout, no overlay)
- [ ] Score tiles show Health, Churn Risk, Expansion scores
- [ ] Immediate Steps section populated
- [ ] Phase 2 Follow-up section populated
- [ ] Success Metrics section populated
- [ ] Escalation Guidance section populated
- [ ] Click LedgerWorks specifically — action type shows "Immediate Churn Intervention"

**AI explanation**
- [ ] Click "Explain This Plan" in the account inspector
- [ ] Response loads (requires valid OPENAI_API_KEY on Render)
- [ ] Response references the deterministic playbook steps
- [ ] Guardrail note reads "AI explains deterministic recommendations. It does not calculate scores or next steps."

**Technical checks**
- [ ] No CORS errors in browser DevTools → Network tab
- [ ] No horizontal scroll at any viewport width
- [ ] API calls in Network tab go to `https://your-render-url.onrender.com/...` (not `/api/...`)

---

## Environment variable reference

### Render (backend)

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | Yes | Supabase direct PostgreSQL connection string |
| `OPENAI_API_KEY` | Yes (for AI feature) | OpenAI API key starting with `sk-` |
| `OPENAI_MODEL` | No (default: `gpt-4o-mini`) | OpenAI model name |
| `FRONTEND_URL` | Yes (for CORS) | Vercel frontend URL, e.g. `https://your-app.vercel.app` |
| `ALLOWED_ORIGINS` | No | Comma-separated extra origins, e.g. for custom domains |

### Vercel (frontend)

| Variable | Required | Description |
|---|---|---|
| `VITE_API_BASE_URL` | Yes | Render backend URL, e.g. `https://your-render-url.onrender.com` |

---

## Local development — unchanged

Local dev requires no changes to existing workflow:

```bash
# Backend
cd backend
uvicorn main:app --reload
# Reads DATABASE_URL from backend/.env

# Frontend (new terminal)
cd frontend
npm run dev
# VITE_API_BASE_URL not set → BASE defaults to /api → Vite proxy → http://127.0.0.1:8000
```

The Vite proxy in `vite.config.ts` is untouched and continues to work locally.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `/accounts` returns 500 on Render | `DATABASE_URL` wrong or Supabase firewall | Verify connection string; Supabase allows all IPs by default on free tier |
| CORS error in browser | `FRONTEND_URL` not set on Render | Add `FRONTEND_URL=https://your-app.vercel.app` and redeploy |
| API calls go to `/api/...` on Vercel | `VITE_API_BASE_URL` missing | Add env var in Vercel dashboard and redeploy |
| Views return errors in Supabase | Schema imported out of order | Re-run `schema.sql` — pg_dump preserves dependency order |
| AI explanation returns 500 | `OPENAI_API_KEY` not set or invalid | Set key in Render env vars |
| Render cold start timeout | Free tier spins down after inactivity | Upgrade instance or accept ~30s first-request delay |