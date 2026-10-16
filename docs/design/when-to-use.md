# When to use JSON Duality Views, and when not to

Based on one project: a manufacturing quality-inspection model on MySQL 9.7.2 Community. "Measured" means it was
observed in this project (evidence in `docs/evidence/`); "reasoned" means it follows from the design but was not measured
here. Nothing below was benchmarked: this project measured behavior, not speed.

## Use a Duality View when

| Situation | Why, in this project | Basis |
|---|---|---|
| The data is relational and governed (keys, constraints, triggers), but applications want one document per business object | One view served a card with a nested object and four arrays that matched the tables element by element | measured (D-019 to D-022) |
| The application must write whole objects, not individual rows | A document with the root and its child rows was written in one atomic operation: a failure in the root or in a child left nothing applied | measured (D-024) |
| You want optimistic concurrency without writing it | The ETag covers the projected document including nested rows; a stale write was refused with error 6494 and changed nothing | measured (D-023, D-024) |
| Database rules must hold for every client | Close rules, the final-card lock, the one-active-card index and the CHECK constraints fired for JSON writes with their own error numbers | measured (D-023 to D-025) |
| You need to control exactly what a client may change | The fields an object projects are the fields it can write; an unprojected column was refused (error 6489) | measured (D-023) |
| You expose a bounded, read-only document to a service or an AI agent | A read-only view refused real changes (error 6497); the document can leave out columns such as `storage_key` | measured (read-only); the agent view itself was designed, not built (D-015) |

## Do not use one (or use it carefully) when

| Situation | What happened or follows | Basis |
|---|---|---|
| You need aggregates and statistics (pass rate, counts, averages) | A document is one object; statistics are plain SQL over the tables | reasoned; the aggregate views were not built (D-015) |
| You need a lot of control over how a write is decomposed | The root is written before its children, and unchanged child rows are updated too. A rule on a child table must ignore updates that change nothing, or it blocks the legitimate write (B-017). Closing a card with its answers takes two writes | measured (D-024, B-017) |
| Clients cache documents | An ETag is valid only for one view definition: the same card had six different ETags as the view grew. A cached ETag, and the document with it, must be dropped when the view changes | measured (D-019 to D-022, D-023) |
| You rely on error messages to find the problem | For a write inside an array, error 6497 named `inspection_card.unit_id` whichever array and field changed, as soon as the view contained a nested object. The refusal was correct; the message misled. The cause is unknown | measured (B-016) |
| You want empty arrays, UTC labels or ordered arrays | A parent with no child rows gives `null`, not `[]`. DATETIME values are plain strings without a timezone. Array order was the primary-key order every time, but nothing guarantees it | measured (D-018, D-019) |
| You need `REPLACE`, `EXPLAIN`, `LOAD DATA`, `INSERT ... SELECT`, multi-table `UPDATE` or `DELETE` on a document, or updates of several objects at once | The MySQL manual lists these as not supported, and says updates need a `WHERE` clause that identifies a single row (https://dev.mysql.com/doc/refman/9.7/en/jdv-limitations.html) | documentation; not tested here |
| You need `INSERT` or `DELETE` through a view | Not built or tested in this project; a card is opened with a plain `INSERT` | not tested |
| You need per-user permissions inside the data | The views carry no roles. Permissions stay in the application or in MySQL accounts and privileges | reasoned (D-010) |
| The access pattern is one table, simple CRUD | A view adds little; a plain table or a JSON column is simpler | reasoned |

## Compared with the usual alternatives (reasoned, not measured)

| Approach | What you write yourself | What the database gives you | When it is the better choice |
|---|---|---|---|
| JSON column holding the whole object | all consistency: keys, references, constraints across objects | one row per object, simple reads and writes | the object is truly self-contained and never queried relationally |
| Hand-built JSON with `JSON_OBJECT`/`JSON_ARRAYAGG` views | the write path (decomposing the document into table writes), the concurrency check, the atomicity | read documents | read-only consumers, or full control of the write path is wanted |
| ORM mapping in the application | the mapping layer and its queries, the concurrency token, the transaction boundaries | tables with constraints | many applications in one language already use it; the rules live in code |
| Duality View | the tags and the shape of each view | document reads and writes, atomic decomposition, ETag, all table constraints and triggers | several kinds of clients need documents over the same governed tables, and the rules must hold for all of them |

The honest cost of the last row, from this project: a new thing to learn (the tag rules), error messages that can mislead,
and a document shape that is part of every client's contract.

## Rule of thumb from this build

Give each consumer its own view, cut to what that consumer may see and change; put the rules in the database so that every
view and every plain SQL statement obeys them; and keep statistics in ordinary SQL views.
