# Demo API (Node.js and TypeScript)

A small server-side API over the two Duality Views of this project. It shows how an application reads and writes the
JSON documents and how MySQL's errors become HTTP answers. Reference: [docs/api/README.md](../docs/api/README.md).

**Demo authentication only.** A header selects a seeded demo user. Never expose this server beyond your own machine.

## What you need

- Node.js 24 or newer (it runs `.ts` files directly; there is no build step).
- The Docker database from the main README running on `127.0.0.1:3307`, with the D1 and D2 scripts applied
  (see `docs/runbooks/restore-from-backup.md`, Path A or Path B2).
- The repository's `.env` (copy of `.env.example` with your real values). The API reads `MYSQL_USER`, `MYSQL_PASSWORD`,
  `MYSQL_DATABASE`, optionally `MYSQL_HOST` (default 127.0.0.1), `MYSQL_PORT` (default 3307), `API_HOST` and `API_PORT`.

## Install

The package versions are not pinned by hand: `npm install` picks the current ones and records them in `package.json` and
`package-lock.json`, which are committed.

```powershell
cd api
npm install mysql2
npm install --save-dev typescript @types/node
npm ls --depth=0
```

## Run, test, try

| Command | What it does | Needs the database |
|---|---|---|
| `npm test` | Unit tests and route tests against an in-memory model of the database | no |
| `npm run typecheck` | TypeScript check of all code | no |
| `npm run test:integration` | The same flows against the real database; deletes what it created and checks the baseline | yes |
| `npm start` | Starts the API on `http://127.0.0.1:3000/api` | yes |
| `npm run examples` | With the API running: replays the example requests and writes `docs/api/example-transcript.md` | yes |
| `npm run cleanup -- <card id>` | Deletes demo cards that were created through the API (never cards 1 and 2) | yes |

Node may print an "ExperimentalWarning" about type stripping; it is harmless.

## Layout

```
src/        the API (app.ts routes, errors.ts error mapping, documents.ts edit logic, db.ts the only file that talks to MySQL)
test/       unit tests, route tests (fake-db.ts is a model of the database), integration test
scripts/    cleanup-cards.ts
examples/   run-examples.ts
```

`test/fake-db.ts` models the behavior recorded in `docs/evidence/day-2`. The route tests therefore prove the API's own
logic; only `test/integration.test.ts` proves it against MySQL.
