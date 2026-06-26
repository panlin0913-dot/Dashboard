# AGENTS.md

## Cursor Cloud specific instructions

This repo is a single product: a **Payment Merchant Health Dashboard** — a Node.js (CommonJS) + Express 5 backend with a static frontend in `public/`, backed by MySQL. Standard commands live in `package.json` and `README.md`; only the non-obvious caveats are captured here.

### Services
- **Web app** (Express, port `3000`): `npm run dev` (watch mode) or `npm start`. Serves the API and the dashboard UI at `http://localhost:3000/dashboard`.
- **MySQL** (port `3306`): required for real (non-demo) data.

### Running MySQL (read this — it does not auto-start)
- MySQL Server 8.0 is installed natively in the VM (not via Docker; `docker` is not available here). The data dir, the `app_user`/`app_password` account, the `payment_dashboard_db` database, and the seed data from `database/init.sql` are already provisioned and persist in the VM snapshot.
- It is **not** started automatically on boot. Start it with: `sudo service mysql start` (then `sudo mysqladmin ping` to confirm).
- `app_user` was granted global privileges (not just on `payment_dashboard_db`) so the app's `initializeDatabase()` (which runs `CREATE DATABASE IF NOT EXISTS`) succeeds. The repo's `docker-compose.yml` is unused in this environment.

### Environment file
- The app loads `.env` via `dotenv`. `.env` is gitignored; if missing, recreate it with `cp .env.example .env` (defaults already point at the local MySQL).

### Gotchas
- **Demo mode masks DB problems.** If MySQL is down/unreachable, the app still boots and `/dashboard` serves built-in mock data instead of crashing. A loading dashboard does NOT prove DB connectivity — verify with `curl -s http://localhost:3000/health` and check `"database":"connected"` (vs `"demo-mode"`).
- **Dashboard date filter excludes "today".** The UI's default end date is midnight of the current day, so rows created today are filtered out and KPIs/GMV show `0`. To see today's data, set the end date one day ahead, or query the API without date params (e.g. `curl "http://localhost:3000/api/dashboard/platform"`).

### Lint / test / build
- There are no lint, test, or build scripts (only `start` and `dev` in `package.json`). For a quick static check, use `node --check src/server.js` and `node --check src/config/db.js`.
