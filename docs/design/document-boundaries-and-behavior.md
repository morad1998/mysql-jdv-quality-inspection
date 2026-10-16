# Document boundaries and behavior matrices

Two of the planned D1 deliverables, written after the facts were measured. Everything below was observed on MySQL
9.7.2 Community; the evidence is in `docs/evidence/day-2` and `day-3`, and the decision numbers refer to
`docs/decisions/decision-log.md`. "Not tested" means exactly that.

## 1. Document-boundary matrix: what is in which document

The relational tables stay the system of record. Each document is cut for one consumer. The read view shows a card;
the edit view lets an inspector or supervisor change only what they may change.

| Part of the document | Source table | Read view `inspection_card_dv` | Edit view `inspection_card_edit_dv` | Why |
|---|---|---|---|---|
| `_id`, `card_status`, `disposition`, `closed_by`, `closed_at` | `inspection_card` | shown, read-only | shown, writable (`WITH (UPDATE)`) | the close path |
| `opened_by`, `opened_at` | `inspection_card` | shown, read-only | not projected | history; a document never changes it (writing it gives error 6489) |
| `unit` (`unit_id`, `unit_serial`, `work_order_id`) | `production_unit` | nested object, read-only | not included | context for display; a card never changes its unit |
| `measurements` | `measurement_result` | array, read-only; includes `measurement_definition_id` | array, writable (`UPDATE` only); definition id not projected | a result cannot be re-pointed at another definition |
| `checklist` | `checklist_result` | array, read-only; includes `checklist_definition_id` | array, writable (`UPDATE` only); definition id not projected | same |
| `findings` | `quality_finding` | array, read-only; the `description` is free text typed by a user | not included | findings are created by plain SQL; the text must be treated as untrusted (D-021) |
| `attachments` | `attachment_metadata` | array, read-only; includes `storage_key` | not included | file bytes live outside MySQL; `storage_key` is an object location, not for agent views (D-022) |
| `open_unit_key` | `inspection_card` | never exposed | never exposed | it implements "one active card per unit" and is not data |
| definition text (description, unit of measure, limits) | `*_definition` | not included | not included | reference data; adding it as a nested object inside each array element was not built |

Rules of thumb that came out of the build:

- The fields an object projects are exactly the fields a document can write (D-023). There are no per-column tags.
- A document is a contract: any change to a view's shape changes every ETag it serves (F-4 in Design Pack v4).
- Arrays are `null`, not `[]`, when the parent has no child rows (D-019, D-022).

## 2. Behavior matrix: what each view does with each operation

| Operation | Read view | Edit view | Evidence |
|---|---|---|---|
| Read one card or all cards | works | works (smaller document, own ETag) | D-018 to D-022, D-023 |
| Real change to a projected field | refused, error 6497 "Missing UPDATE tag" | allowed, subject to every database rule | D-018, D-023 |
| Write that changes nothing | accepted silently | accepted silently | D-018, D-028 |
| Change inside an array element | refused, error 6497; when the view has a nested object the message names `inspection_card.unit_id` whichever array was changed (B-016, cause unknown) | allowed for `measurements` and `checklist` | D-024, B-016 |
| Property the view does not project (unknown, or a real column such as `opened_by`) | not tested | refused, error 6489 "not mapped to any column", naming the path | D-023, D-024 |
| Stale ETag | not applicable (not writable) | refused, error 6494; the API returns 412 with the current document | D-023, D-024, D-027 |
| One write that fails in a child or in the root | not applicable | atomic: nothing is applied (root is written first, then the child rows) | D-024 |
| Close with an unanswered checklist item | not applicable | refused by trigger, error 50002 | D-023, D-024 |
| Close with an open CRITICAL finding | not applicable | refused by trigger, error 50003 (tested in D2 step 7a) | D-023 |
| Answer and close in one write | not applicable | refused (50002): the root is checked before the children are written; close takes two writes | D-024 |
| Change or reopen a CLOSED or REJECTED card | not applicable | refused by the lock triggers, errors 50020 to 50022 | D-025 |
| Close a card that is already closed | not applicable | the database would accept an identical write as a no-op within the same second; the API refuses it first | D-028 |
| `INSERT` or `DELETE` a document | not enabled (`ALLOW_INSERT` 0, `ALLOW_DELETE` 0); the error was not tested | not enabled; the error was not tested | D-023 |
| Open a card | by plain SQL `INSERT` into `inspection_card`; a trigger creates the PENDING result rows; a second active card on the unit is refused, error 1062 | the same | D-010, D-012, D-027 |
| Write with a prepared statement | not tested | not tested | D-027 |

## 3. What this does not cover

- Findings and attachment metadata have no edit document. Adding them is possible in principle; it was not built or tested.
- No `INSERT` or `DELETE` through a view over the card tables was built, so the second half of B-008 (a generated column
  with a view that can insert) is untested.
- The aggregate and agent-facing views planned in D-015 are not built.
