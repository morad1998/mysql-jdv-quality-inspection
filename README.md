# MySQL JSON Duality Views: manufacturing quality inspection

A worked example for the Oracle ACE bounty on MySQL JSON Relational Duality Views. Normalized MySQL tables stay the
system of record; two Duality Views give an application JSON documents; the database, not the application, enforces the
business rules, including for JSON writes. A small Node.js and TypeScript API shows how an application uses the views.

Everything here was run on **MySQL Community Server 9.7.2** in Docker, and every claim in the write-up has evidence in
`docs/evidence/`. Where something was not tested, the documents say so.

## What is in it

| Part | Where | Status |
|---|---|---|
| 12-table relational model, 8 triggers, CHECK and unique constraints | `database/01_domain_model/` | built, tested |
| Read-only view `inspection_card_dv`: a card with a nested unit object and four arrays | `database/02_duality_views/17_*.sql` | built, tested |
| Update-enabled view `inspection_card_edit_dv`: a card with two writable arrays | `database/02_duality_views/23_*.sql` | built, tested |
| Day 0 proof: a read-only and a writable view on customers and orders | `database/00_environment/` | built, tested |
| Demo API (Node.js 24, TypeScript): 54 unit and route tests, 16 integration tests | `api/`, `docs/api/` | built, tested |
| Architecture and ER diagrams, document-boundary and behavior matrices | `docs/architecture/`, `docs/design/` | written |
| Article, when-to-use guidance | `docs/article/`, `docs/design/when-to-use.md` | written |
| Decision log (D-001 to D-028), blocker register, evidence, backup and restore runbook | `docs/` | written |
| **Not built:** web or tablet app, offline mode, AI assistant, MySQL REST Service, `INSERT` or `DELETE` through a view | | see `docs/article/article.md`, section "What I did not build" |

## What you need

- Docker Desktop (or Docker Engine with the Compose plugin)
- Git
- Node.js 24 or newer with npm (for the API)
- Windows PowerShell 5.1 or newer for the two helper scripts. The SQL files themselves run with any MySQL client; the
  required order is in `scripts/setup-database.ps1` and in `docs/runbooks/restore-from-backup.md` (Path B2). Bash
  equivalents of the scripts are not provided and were not tested.

## Quick start (PowerShell, from the repository root)

```powershell
git clone https://github.com/morad1998/mysql-jdv-quality-inspection.git
cd mysql-jdv-quality-inspection

# 1. Configuration: copy the template and replace the two CHANGE_ME values with passwords of your own.
Copy-Item .env.example .env
notepad .env

# 2. Start MySQL 9.7.2 and wait until it is healthy.
docker compose up -d
docker compose ps

# 3. Load the database scripts in the verified order and check the result.
powershell -ExecutionPolicy Bypass -File scripts/setup-database.ps1

# 4. The API: install from the lock file, run the tests, start the server.
cd api
npm ci
npm test                    # 54 tests, no database needed
npm run test:integration    # 16 tests against the database; they clean up after themselves
npm start                   # http://127.0.0.1:3000/api
```

With the server running, in a second window: `npm run examples` replays 14 requests and writes
`docs/api/example-transcript.md`; then `npm run cleanup -- <id it prints>` removes the card it created.

Port 3307 is used on the host so that it does not clash with a MySQL that is already on 3306. Change `MYSQL_PORT` in `.env`
if 3307 is taken. The API is bound to 127.0.0.1 and uses **demo authentication only**: a header selects a seeded user. Never
expose it.

## Prove it works from nothing

`scripts/replay-clean-environment.ps1` clones the repository from GitHub into a temporary folder, starts its own
throwaway MySQL (own container, volume and port 3308, so an existing database is not touched), runs every step above,
writes `replay-report.txt` and cleans up. The result of the run that was made for this release is in
`docs/evidence/day-3/replay/` (if that folder is missing, the replay has not been recorded yet).

```powershell
powershell -ExecutionPolicy Bypass -File scripts/replay-clean-environment.ps1 -OutDir .\replay-evidence
```

## Where to read next

1. `docs/article/article.md`: the write-up, with the measured findings and the candid limits.
2. `docs/architecture/README.md`: the two diagrams.
3. `docs/design/document-boundaries-and-behavior.md` and `docs/design/when-to-use.md`.
4. `docs/api/README.md`: endpoints, errors, the two-write close.
5. `docs/decisions/decision-log.md` and `docs/decisions/blocker-register.md`: every decision and every problem, including the
   mistakes (for example B-017, a first lock version that blocked legitimate work, and B-019, a test model that hid a
   database behavior).

## Layout

```
compose.yaml, .env.example     MySQL 9.7.2 container (no secrets in the repository)
database/00_environment/       Day 0 proof on customers and orders (jdv_spike database)
database/01_domain_model/      schema, triggers, seed data, tests, final-card lock
database/02_duality_views/     the step-by-step history of the views; the final ones are 17 and 23
api/                           the demo API and its tests
scripts/                       setup-database.ps1, replay-clean-environment.ps1
docs/                          article, diagrams, matrices, API reference, decisions, evidence, runbook
```

The numbered files in `database/02_duality_views/` are a lab notebook: each step recreated `inspection_card_dv` with one more
part, and 01 to 16 are superseded by 17. `docs/runbooks/restore-from-backup.md` lists which files rebuild the final state.

## Honest limits

- Role permissions are not enforced by the database; the API's roles are a demo (D-010).
- Checkpoint definitions are not versioned in the schema.
- Results come from one MySQL version on one machine. The MySQL manual serves the same feature set under two version paths
  (9.7 and 26.7).
- Some behaviors were observed but not explained: see B-016 (a misleading error path) and D-019 (gaps in generated IDs).

## License and security

MIT, see `LICENSE`. Do not commit `.env`, passwords, tokens or private data. The data in this repository is synthetic.
