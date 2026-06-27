# AGENTS.md

## Cursor Cloud specific instructions

This repo is a single product: a **Payment Merchant Health Dashboard** — a Node.js (CommonJS) + Express 5 backend with a static frontend in `public/`, backed by a MySQL-compatible database. Standard commands live in `package.json` and `README.md`; only the non-obvious caveats are captured here.

### Services
- **Web app** (Express, port `3000`): `npm run dev` (watch mode) or `npm start`. Serves the JSON API and the dashboard UI at `http://localhost:3000/dashboard`.
- **Database** (port `3306`): required for real (non-demo) data.

### Database is MariaDB, not MySQL (read this)
- The DB server provisioned in this VM is **MariaDB 10.11** (installed via apt), not MySQL/Docker. `docker` is not available here, so the repo's `docker-compose.yml` is unused.
- MariaDB is required (not just convenient) because the unmodified app uses MariaDB-only SQL: `database/init.sql` and `src/config/db.js` both run `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` and `CREATE USER IF NOT EXISTS ...@'%'`, which standard MySQL 8.x rejects. On MySQL the bootstrap would throw and the app would silently fall back to demo mode.
- It does **not** start on boot. Start it with `sudo service mariadb start`, then confirm with `sudo mariadb-admin ping`.
- First-time data load (idempotent — uses `IF NOT EXISTS` / `ON DUPLICATE KEY UPDATE`): `sudo mariadb < database/init.sql`. This creates the `payment_dashboard_db` database, the `app_user`/`app_password` account, all tables, and seed data.

### Environment file
- The app loads `.env` via `dotenv`. `.env` is gitignored; if missing, recreate it with `cp .env.example .env` (defaults already point at the local DB at `127.0.0.1:3306`).

### Gotchas
- **Demo mode masks DB problems.** If the DB is down/unreachable, the app still boots and `/dashboard` serves built-in mock data instead of crashing. A loading dashboard does NOT prove DB connectivity — verify with `curl -s http://localhost:3000/health` and check `"database":"connected"` (vs `"demo-mode"`).
- **Dashboard date filter excludes "today".** The UI's default end date is the current day, and the API treats `endDate` as exclusive of that day's rows, so rows created today are filtered out and KPIs/GMV show `0`. To see today's data in the UI, set the end date one day ahead; or query the API with no date params (e.g. `curl "http://localhost:3000/api/dashboard/platform"`).

### Lint / test / build
- There are no lint, test, or build scripts (only `start` and `dev` in `package.json`). For a quick static check, use `node --check src/server.js` and `node --check src/config/db.js`.
