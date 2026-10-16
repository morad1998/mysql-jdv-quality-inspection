# MySQL JSON Duality Views in a quality-inspection app: what held, what surprised me, and where I would not use them

*16 October 2026. Everything was run on MySQL Community Server 9.7.2 in Docker. The data is synthetic. Code, scripts, tests and
evidence: https://github.com/morad1998/mysql-jdv-quality-inspection (MIT license).*

## In short

I built a small manufacturing quality-inspection system on MySQL 9.7.2 to find out what JSON Relational Duality Views are good
for, and where they hurt. The relational tables stay the system of record. Two Duality Views serve the application: one
read-only view that shows a whole inspection card as one document, and one update-enabled view that lets an inspector
change only what an inspector may change. A thin Node.js and TypeScript API sits on top.

What I can say from running it, not from reading the manual:

- One view can serve a card with a nested object and four arrays, and every part matched the tables.
- A document write is atomic, protected by an ETag, and **the database's triggers and constraints apply to it**. Closing a
  card with an unanswered checklist item was refused by a trigger when the write arrived as JSON, with the trigger's own error number.
- That last point has a catch: without extra rules, a document could **reopen a closed card**. I found it by testing, and
  closed it with three triggers. My first version of those triggers was wrong, and my test model hid a database behavior
  until a real run exposed it. Both mistakes are in the repository.
- I would not use a Duality View for statistics, for clients that cache documents without a plan for ETags changing when
  the view changes, or where you need error messages you can trust to point at the problem.

Every claim below has a decision number (D-nnn, B-nnn) in `docs/decisions/` and evidence in `docs/evidence/`. Where I did not
test something, I say so.

## The scenario

A work order has production units. An inspector opens an inspection card for a unit, records measurements, answers a checklist,
raises findings and attaches photos. A supervisor closes the card with a disposition. Rules that must hold whoever writes:

- a card cannot be closed while a checklist item is unanswered or a CRITICAL finding is open;
- a unit has at most one open card at a time; a retest is a new card, never an overwrite;
- a closed card cannot be changed;
- the audit table is append-only.

The relational model has 12 tables, 18 foreign keys, 17 CHECK constraints and 8 triggers.

![Entity-relationship diagram](https://raw.githubusercontent.com/morad1998/mysql-jdv-quality-inspection/main/docs/architecture/er-diagram.png)

## Two views, two jobs

**The read view** shows a card for display. It has no `WITH` clause, so it is read-only.

```sql
CREATE JSON RELATIONAL DUALITY VIEW inspection_card_dv AS
SELECT JSON_DUALITY_OBJECT(
    '_id': card_id, 'card_status': card_status, 'disposition': disposition,
    'opened_by': opened_by, 'opened_at': opened_at, 'closed_by': closed_by, 'closed_at': closed_at,
    'unit': (
        SELECT JSON_DUALITY_OBJECT('unit_id': unit_id, 'unit_serial': unit_serial, 'work_order_id': work_order_id)
        FROM production_unit WHERE production_unit.unit_id = inspection_card.unit_id
    ),
    'measurements': (
        SELECT JSON_ARRAYAGG(JSON_DUALITY_OBJECT(
            'measurement_result_id': measurement_result_id, 'measurement_definition_id': measurement_definition_id,
            'result_status': result_status, 'measured_value': measured_value,
            'recorded_by': recorded_by, 'recorded_at': recorded_at))
        FROM measurement_result WHERE measurement_result.card_id = inspection_card.card_id
    ),
    -- 'checklist', 'findings' and 'attachments' follow the same pattern (database/02_duality_views/17_*.sql)
    ...
)
FROM inspection_card;
```

**The edit view** is a separate view. In MySQL the modification tag works per object, and the fields an object projects are exactly
the fields a document can write. So the edit view projects only the close path and two arrays, with `UPDATE` only: no insert, no delete.

```sql
CREATE JSON RELATIONAL DUALITY VIEW inspection_card_edit_dv AS
SELECT JSON_DUALITY_OBJECT(
    WITH (UPDATE)
    '_id': card_id, 'card_status': card_status, 'disposition': disposition,
    'closed_by': closed_by, 'closed_at': closed_at,
    'measurements': (
        SELECT JSON_ARRAYAGG(JSON_DUALITY_OBJECT(
            WITH (UPDATE)
            'measurement_result_id': measurement_result_id, 'result_status': result_status,
            'measured_value': measured_value, 'recorded_by': recorded_by, 'recorded_at': recorded_at))
        FROM measurement_result WHERE measurement_result.card_id = inspection_card.card_id
    ),
    -- 'checklist' is the same pattern (database/02_duality_views/23_*.sql)
    ...
)
FROM inspection_card;
```

`unit_id`, `opened_by` and the definition ids are not projected, so no document can change them: a write that names one is
refused (error 6489, "not mapped to any column"). The ETag in the document is how MySQL protects concurrent writers.

![Runtime architecture](https://raw.githubusercontent.com/morad1998/mysql-jdv-quality-inspection/main/docs/architecture/architecture.png)

## What I measured

All of these were observed, each with an evidence file. Strength is stated honestly.

| # | Finding | Record | Strength |
|---|---|---|---|
| 1 | One read-only view held a nested object and four independent arrays; every element matched the tables | D-019 to D-022 | tested |
| 2 | A parent with no child rows shows `null`, not `[]`; SQL NULL in an element is JSON `null` | D-019, D-022 | tested |
| 3 | DATETIME is a plain string (`"2026-10-16 01:13:25.000000"`, no `T`, no `Z`, not labelled UTC); DECIMAL keeps its scale; JSON keys come back shorter-first, then alphabetical | D-018, D-019 | tested |
| 4 | The ETag covers nested rows, and it changes whenever the view's shape changes: the same card had six different ETags as the view grew. A change to an unprojected column did not change it | D-019, D-021, D-023 | tested; how MySQL computes it was not examined |
| 5 | A real change through a read-only view is refused (error 6497). A write that changes nothing is accepted silently | D-018 | tested |
| 6 | A stale ETag is refused (error 6494) and changes nothing | D-023, D-024 | tested |
| 7 | Triggers, CHECK constraints and unique indexes apply to document writes, with their own error numbers (50002, 50003, 3819, 1062) | D-023, D-024 | tested |
| 8 | A failed document write is atomic. The root is written first, then the child rows, so "answer everything and close" in one write fails: the close rule sees the old answers. Closing takes two writes | D-024 | tested |
| 9 | Child rows whose values did not change are updated too, so a rule on a child table must ignore no-op updates | D-024, B-017 | inferred from a trigger that fired |
| 10 | A virtual generated column behind a unique index (the one-active-card rule) coexists with both views, and stays correct under document writes | D-012, D-023, B-008 | tested for UPDATE |
| 11 | With an `UPDATE` tag alone, nothing stopped a document from reopening a closed card or editing its results | D-025 | tested |
| 12 | For a write inside an array, error 6497 named `inspection_card.unit_id` whichever array and field changed, as soon as the view contained a nested object; the refusal was right, the message misleading. I ruled out one explanation and do not know the cause | B-016 | tested; unexplained |

## Rules in the database: and a mistake I am glad I found

The close rules, the one-active-card index and the CHECK constraints behaved for JSON writes exactly as they did for SQL. That
is the strongest argument for Duality Views in this project: the rules live in one place.

Then I tried to break it. A document could set `card_status` back to `OPEN` on a closed card, change its disposition or
overwrite a recorded measurement, because the views only say *which fields are writable*, not *when*. The lock is three
triggers: a closed or rejected card, and its result rows, cannot be changed.

My first version of the lock refused every update of a result row of a final card. It also blocked the *legitimate close*:
because MySQL writes the root first and then updates child rows, including unchanged ones, the child triggers saw a card that
was already closed. A regression test that I had written for the close failed, and it showed the lock raising the wrong
error number as well. The fixed version only refuses an update that changes a column. The flawed first attempt is kept
in the repository (`05_final_card_lock_triggers.sql`, replaced by `06_...v2.sql`), with the evidence of both runs (B-017).

I made a second, smaller mistake in the API tests. They ran against an in-memory model of the database and all passed. The
first run against the real database failed: closing a closed card a second time returned 200, not 409. The database accepts a
write that changes nothing, and my model had stored times with milliseconds, so it never saw one. The API now refuses a
repeated close itself, and the lesson is in the repository (B-019): a model proves your logic, only the database proves the database.

## A thin API on top

The API checks the request, picks the view, fills in who and when, and turns a database **error number** into an HTTP status.
It never forwards the text of a database error.

| Database signal | HTTP | Meaning |
|---|---|---|
| 6494 stale ETag | 412, with the current document | the card changed after you read it |
| 50002, 50003 | 409 | an unanswered item or an open CRITICAL finding blocks the close |
| 50020 to 50022 | 409 | a closed card cannot be changed |
| 1062 | 409 | the unit already has an open card |
| 3819, 1452 | 422 | a CHECK constraint or a foreign key refused it |
| 6489 | 400 | the API never forwards an unknown property, so this should not occur |

Closing a card is two calls, because that is what MySQL does:

```text
GET  /api/cards/7/edit                  -> 200, ETag E1
PUT  /api/cards/7/edit   If-Match: E1   -> 200, ETag E2     (the answers)
POST /api/cards/7/close  If-Match: E2   -> 200 or 409       (the close rules fire here)
```

Fourteen recorded requests and responses, taken against the real database, are in `docs/api/example-transcript.md`.

## When to use a Duality View, and when not to

Use one when relational, governed data must be written and read as whole objects by several kinds of clients, and the rules
must hold for all of them. In this project that gave me atomic writes, optimistic concurrency and enforced rules for free.

I would not use one:

- for **statistics**: a document is one object, and a pass rate is plain SQL over the tables;
- for **clients that cache documents** unless they treat the shape as a versioned contract (finding 4);
- where you need to **trust the error message** to find the problem (finding 12);
- where you need what the manual lists as unsupported: `REPLACE`, `EXPLAIN`, `INSERT ... SELECT`, multi-table
  `UPDATE` or `DELETE`, updates of several objects, or an update without a `WHERE` that identifies a single row
  (https://dev.mysql.com/doc/refman/9.7/en/jdv-limitations.html; I did not test these);
- for **one table with simple CRUD**: a view adds little.

Against the usual alternatives, reasoned and not measured here: a JSON column gives you one row per object but leaves
consistency to you; hand-built `JSON_OBJECT` views give you read documents but leave the write path, the concurrency check
and the atomicity to you; an ORM puts the mapping and the rules in application code. A Duality View is the better choice when
several kinds of clients need documents over the same governed tables. The full table is in `docs/design/when-to-use.md`.

## What I did not build

- **No web or tablet app and no offline mode.** I had planned both and cut them to finish what I could test.
- **No AI assistant.** The design is written (D-015): a read-only view cut for an agent, a `SELECT`-only account, fixed
  tools, free text such as finding descriptions treated as untrusted. Nothing was implemented, so I make no claim about it.
- **No MySQL REST Service.** The Node.js API is the transparent substitute.
- **No `INSERT` or `DELETE` through a view.** A card is opened with a plain `INSERT`; a trigger creates its pending rows.
- **No real authentication.** The API selects a seeded user from a header. The database enforces no roles.
- The status `REJECTED` exists in the schema, is locked like `CLOSED`, and is not reachable through the API; I have not decided
  whether it should need the same close checks (D-011).

I also did not benchmark anything. Treat all of this as behavior on one MySQL version (9.7.2 Community) on one machine.

## Reproduce it

```powershell
git clone https://github.com/morad1998/mysql-jdv-quality-inspection.git
cd mysql-jdv-quality-inspection
Copy-Item .env.example .env          # then set the two passwords
docker compose up -d
powershell -ExecutionPolicy Bypass -File scripts/setup-database.ps1
cd api; npm ci; npm test; npm run test:integration
```

`scripts/replay-clean-environment.ps1` does all of this from a fresh clone in a throwaway container and writes a report; the
report for this release is in `docs/evidence/day-3/replay/`.

## Links

- Repository: https://github.com/morad1998/mysql-jdv-quality-inspection
- Decision log and blocker register: `docs/decisions/`
- Evidence: `docs/evidence/day-0` to `day-3`
- MySQL manual, DML on Duality Views: https://dev.mysql.com/doc/refman/9.7/en/json-duality-views-updatable.html
