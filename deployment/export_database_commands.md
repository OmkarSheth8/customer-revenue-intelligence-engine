# Database Export Commands

Run these commands locally to export the full `core` schema from your local PostgreSQL
database into two SQL files that can be imported into Supabase.

## Prerequisites

- PostgreSQL client tools installed and `pg_dump` in your PATH.
- Local PostgreSQL running on port 5433 (adjust if different).
- Database name: `customer_revenue_intelligence`
- Schema: `core`

---

## Step 1 — Export schema (tables, views, indexes, constraints)

### Bash / Git Bash (recommended)
```bash
pg_dump -h localhost -p 5433 -U postgres \
  -d customer_revenue_intelligence \
  -n core \
  --schema-only \
  --no-owner \
  --no-privileges \
  > deployment/schema.sql
```

### Windows Command Prompt (one line)
```cmd
pg_dump -h localhost -p 5433 -U postgres -d customer_revenue_intelligence -n core --schema-only --no-owner --no-privileges > deployment\schema.sql
```

---

## Step 2 — Export data (all rows as INSERT statements)

### Bash / Git Bash
```bash
pg_dump -h localhost -p 5433 -U postgres \
  -d customer_revenue_intelligence \
  -n core \
  --data-only \
  --inserts \
  --no-owner \
  --no-privileges \
  > deployment/data.sql
```

### Windows Command Prompt (one line)
```cmd
pg_dump -h localhost -p 5433 -U postgres -d customer_revenue_intelligence -n core --data-only --inserts --no-owner --no-privileges > deployment\data.sql
```

---

## Flags explained

| Flag | Reason |
|---|---|
| `-n core` | Export `core` schema only, not `public` or system schemas |
| `--schema-only` / `--data-only` | Separate schema and data so Supabase can import them in the right order |
| `--inserts` | Use `INSERT INTO` syntax instead of `COPY` — required for Supabase SQL editor import |
| `--no-owner` | Strip owner commands that would fail with a different Supabase user |
| `--no-privileges` | Strip `GRANT`/`REVOKE` — Supabase manages its own permissions |

---

## After running

You will have two files:
- `deployment/schema.sql` — all `CREATE TABLE`, `CREATE VIEW`, indexes, sequences
- `deployment/data.sql` — all `INSERT INTO` statements for the 8 base tables

Both files are safe to commit to git (they contain no secrets).

Import order in Supabase: **schema first, then data.**

See `deployment/DEPLOYMENT.md` for the full import walkthrough.

---

## Notes

- `pg_dump` will output the views in dependency order — base tables first, then views on top of them.
- The Phase 20A/20B views (`core.account_action_playbook`, updated `core.account_intelligence_view`) are captured by pg_dump from the live database state, so they will include the latest version even if the SQL files in `sql/` are from an earlier draft.
- `data.sql` will only contain rows for the 8 base tables. Views have no rows to export.