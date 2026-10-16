# D2 Step 1 Summary: flat read-only inspection_card_dv

## Overall result

PASS. A read-only JSON Duality View over inspection_card was created, is valid, and agrees with the table.

D2 is not complete. This is step 1 of the plan: nested objects and collections, and write annotations, come in later steps.

## Scripts (database/02_duality_views/)

| Script | Purpose |
|---|---|
| 01_inspection_card_dv_flat.sql | Creates inspection_card_dv (read-only, flat) and shows its metadata |
| 02_verify_inspection_card_dv_flat.sql | Read-only checks V1 to V5 |
| 03_negative_tests_flat.sql | First negative test (no-change update); see the note in the file |
| 04_followup_checks.sql | Real-change negative test F3 and NULL-path test F5, inside rolled-back transactions |
| 99_rollback.sql | Drops inspection_card_dv only |

## Results

| Check | Result |
|---|---|
| View metadata | inspection_card_dv, JSON column data, root table inspection_card, insert/update/delete 0/0/0, READ_ONLY 1, STATUS valid |
| V1 | 2 documents, 2 table rows |
| V4 | 2 of 2 cards fully matching |
| V5 | 0 documents expose open_unit_key |
| N1 (no-change update) | No error; data unchanged. Weak test, see B-015 |
| F1 | 1 matching document |
| F3 (real change) | ERROR 6497 Missing UPDATE tag on inspection_card.opened_by; data and ETag unchanged after rollback |
| F5 (OPEN card) | Document shows null for disposition, closed_at and closed_by; 3 of 3 cards matching; 0 cards on unit 3 and 2 in total after rollback |

## Findings

- B-008 (partial): a read-only view over a table that has a virtual generated column is accepted, provided the column is not exposed. A writable view is still untested.
- DATETIME values appear as "YYYY-MM-DD HH:MM:SS.ffffff" strings with no timezone marker (D-018).
- SQL NULL appears as JSON null.
- Error numbers seen so far: 6494 stale ETag (Day 0), 6497 missing UPDATE tag.
- A no-change update through a read-only view is accepted silently. The likely cause is that MySQL validates only the paths whose values change; this is not proven.

## Evidence notes

- The step 1 negative test output (d2-1-negative.txt) shows no error. Read it together with B-015.
- Evidence text files were converted to UTF-8 with LF line endings.
- The F5 insert used card id 3 inside a rolled-back transaction. The AUTO_INCREMENT counter is not rolled back, so the next automatic card id is expected to be 4.
- A transaction rollback restored the F3 state; the ETag before and after was identical.

## Next step

D2 step 2: add the production unit as a nested object in inspection_card_dv, verify the JSON against the tables, and test the negative case again.
