# Frontend — Customer Revenue Intelligence Engine

React 19 + TypeScript dashboard built with Vite.

**Live:** [customer-revenue-intelligence-engin.vercel.app](https://customer-revenue-intelligence-engin.vercel.app)

---

## Structure

```
frontend/
  src/
    components/     # Dashboard panels, account table, score tiles, AI explanation
    lib/
      api.ts        # All API calls — reads VITE_API_BASE_URL or falls back to /api proxy
    App.tsx
    main.tsx
  vite.config.ts    # /api proxy → http://127.0.0.1:8000 (local dev only)
```

## Local Development

```bash
npm install
npm run dev
```

The Vite dev server proxies `/api/*` to `http://127.0.0.1:8000`. No `.env` file needed locally — just have the backend running.

## Production Build

```bash
npm run build
```

Set `VITE_API_BASE_URL=https://your-render-backend.onrender.com` in Vercel before deploying.
The app falls back to `/api` (Vite proxy) when this variable is unset, so local dev is unchanged.

## Key Design Decisions

- **No modal overlays.** The account detail panel pushes the dashboard content left (380px inline panel). No z-index stacking, no focus traps.
- **60-second auto-refresh.** Dashboard polls the backend every 60 seconds without requiring a manual reload.
- **AI is opt-in.** The AI explanation is only triggered when the user clicks "Explain This Plan". No automatic calls.