# Deployment — Customer Revenue Intelligence Engine

## Production Architecture

```
Supabase PostgreSQL  →  Render FastAPI  →  Vercel React/Vite
```

| Service | URL |
|---|---|
| Frontend | https://customer-revenue-intelligence-engin.vercel.app |
| Backend API | https://customer-revenue-intelligence-engine.onrender.com |
| Health check | https://customer-revenue-intelligence-engine.onrender.com/health |
| API docs | https://customer-revenue-intelligence-engine.onrender.com/docs |

---

## Replicate This Deployment

Use this guide to stand up your own instance. Complete the steps in order.

### Step 1 — Supabase (database)

1. Create a project at [supabase.com](https://supabase.com).
2. In **Settings → Database → Connection string → URI**, copy the direct connection string (port **5432**, not 6543 pooler).
3. Import the schema, then the data:

```bash
psql "postgresql://postgres:[PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres" \
  -f deployment/schema_supabase_clean.sql

psql "postgresql://postgres:[PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres" \
  -f deployment/data.sql
```

> Use `psql` direct import rather than the Supabase SQL editor. The schema file is ~99 KB and the data file is ~9 MB — too large to paste reliably into the web editor.

4. Validate the import:

```sql
SELECT COUNT(*) FROM core.accounts;                  -- expect 100
SELECT COUNT(*) FROM core.account_intelligence_view; -- expect 100
SELECT * FROM core.dashboard_kpis;
```

---

### Step 2 — Render (FastAPI backend)

1. Go to [render.com](https://render.com) → **New → Web Service**.
2. Connect your GitHub repository.
3. Configure:

| Setting | Value |
|---|---|
| Root Directory | `backend` |
| Runtime | `Python 3` |
| Build Command | `pip install -r requirements.txt` |
| Start Command | `uvicorn main:app --host 0.0.0.0 --port $PORT` |

4. Add environment variables:

| Variable | Value |
|---|---|
| `DATABASE_URL` | Supabase direct connection string (port 5432) |
| `OPENAI_API_KEY` | Your OpenAI API key |
| `OPENAI_MODEL` | `gpt-4o-mini` |
| `FRONTEND_URL` | *(leave blank until Step 3 is complete)* |

5. Deploy. Verify at `https://your-render-url.onrender.com/health`.

---

### Step 3 — Vercel (React/Vite frontend)

1. Go to [vercel.com](https://vercel.com) → **New Project** → import your repository.
2. Configure:

| Setting | Value |
|---|---|
| Framework Preset | `Vite` |
| Root Directory | `frontend` |
| Build Command | `npm run build` |
| Output Directory | `dist` |

3. Add environment variable before deploying:

| Variable | Value |
|---|---|
| `VITE_API_BASE_URL` | `https://your-render-url.onrender.com` |

4. Deploy. Vercel assigns a URL like `https://your-app.vercel.app`.

---

### Step 4 — Wire CORS

Once you have the Vercel URL, go back to **Render → your service → Environment** and set:

| Variable | Value |
|---|---|
| `FRONTEND_URL` | `https://your-app.vercel.app` |

Redeploy Render. Without this, the frontend will receive CORS errors on all API calls.

---

## Environment Variable Reference

### Render (backend)

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | Yes | Supabase direct PostgreSQL connection string |
| `OPENAI_API_KEY` | Yes (AI feature) | OpenAI API key starting with `sk-` |
| `OPENAI_MODEL` | No (default: `gpt-4o-mini`) | OpenAI model name |
| `FRONTEND_URL` | Yes (CORS) | Vercel frontend URL |
| `ALLOWED_ORIGINS` | No | Additional comma-separated origins |

### Vercel (frontend)

| Variable | Required | Description |
|---|---|---|
| `VITE_API_BASE_URL` | Yes | Render backend URL |

---

## Local Development

Local dev requires no changes to the deployed configuration.

```bash
# Backend — reads DATABASE_URL from backend/.env
cd backend
uvicorn main:app --reload

# Frontend (new terminal) — Vite proxy handles /api → http://127.0.0.1:8000
cd frontend
npm run dev
```

`VITE_API_BASE_URL` is unset locally, so the frontend falls back to `/api`, which Vite proxies to the local backend. No `.env` file needed in the frontend directory for local dev.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `/accounts` returns 500 on Render | `DATABASE_URL` wrong or missing | Check the Supabase connection string — use port 5432, not 6543 |
| CORS error in browser | `FRONTEND_URL` not set on Render | Add `FRONTEND_URL=https://your-app.vercel.app` and redeploy |
| API calls go to `/api/...` on Vercel | `VITE_API_BASE_URL` missing | Add the env var in Vercel and redeploy (the build must re-run) |
| Views return errors in Supabase | Schema imported out of order | Re-run `schema_supabase_clean.sql` — pg_dump preserves dependency order |
| AI explanation returns 500 | `OPENAI_API_KEY` not set or invalid | Set the key in Render environment variables |
| Render cold start timeout | Free tier spins down after inactivity | First request after idle takes ~30s; upgrade to paid tier for production SLA |

---

## Database Export

To re-export the schema or data from a local PostgreSQL instance:

```bash
# Schema only (tables, views, indexes, constraints)
"C:\Program Files\PostgreSQL\18\bin\pg_dump.exe" \
  -h localhost -p 5433 -U postgres \
  -d customer_revenue_intelligence \
  -n core --schema-only --no-owner --no-privileges \
  > deployment/schema.sql

# Data only (INSERT statements for all 8 base tables)
"C:\Program Files\PostgreSQL\18\bin\pg_dump.exe" \
  -h localhost -p 5433 -U postgres \
  -d customer_revenue_intelligence \
  -n core --data-only --inserts --no-owner --no-privileges \
  > deployment/data.sql
```

PostgreSQL 18 adds `\restrict` / `\unrestrict` nonce lines to pg_dump output that are incompatible with Supabase. Strip them before importing:

```python
# Run from project root
for path in ["deployment/schema.sql", "deployment/data.sql"]:
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(l for l in lines
                     if not l.startswith("\\restrict ")
                     and not l.startswith("\\unrestrict "))
```

After stripping, generate `schema_supabase_clean.sql` (adds `DROP SCHEMA IF EXISTS core CASCADE;` and removes `SET transaction_timeout = 0;`) by re-running the `make_supabase_schema.py` approach documented in the session history, or manually prepend the DROP line to the cleaned `schema.sql`.