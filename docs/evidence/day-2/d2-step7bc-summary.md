# D2 Steps 7b and 7c Summary: edit view with child arrays, and the final-card lock

## Overall result

PASS. inspection_card_edit_dv serves and accepts the card with its measurements and checklist arrays. Database rules apply to document writes. A gap was found (a closed card could be reopened or edited through a document), closed with three lock triggers, and the first version of those triggers was found flawed by its own regression test and fixed. The verified state is the second version.

D2 is closed on the database side. Remaining outside the database: a refreshed backup and runbook (B-018), Design Pack v4, the API, the diagram, the article.

## Scripts

| Script | Purpose |
|---|---|
| database/02_duality_views/23_inspection_card_edit_dv_with_arrays.sql | Recreates inspection_card_edit_dv with measurements and checklist arrays (update only) |
| 24_verify_edit_view_arrays_read.sql | Read-only checks U1 to U7 |
| 25_write_tests_arrays.sql | Write tests C0 to C5, D1 to D6, E0 to E3 in three rolled-back transactions |
| 26_final_card_lock_tests.sql | Tests L1 to L5 and P0 to P3, run three times (before the lock, with the first lock, with the fixed lock) |
| database/01_domain_model/05_final_card_lock_triggers.sql | First version of the three lock triggers (root account) |
| 06_final_card_lock_triggers_v2.sql | Replaces the two child triggers with a version that ignores unchanged rows |
| 98_rollback_final_card_lock.sql | Drops the three lock triggers |

## Step 7b results (before any lock)

| Check | Result |
|---|---|
| View metadata | inspection_card_edit_dv: ALLOW_UPDATE 1, READ_ONLY 0, valid; inspection_card_dv unchanged |
| U1 to U5 | Documents match the tables (measurements 4 of 4, checklist 6 of 6); definition ids not exposed; open_unit_key not exposed |
| U6, U7 | Edit-view ETags 35f30871ad37da0025e8c336080e9021 and aeb1eb08f0eade1111df3532d4c9e50b; read-view ETags unchanged |
| C1 (line 32), C2 (line 43) | Recording a measurement and answering three checklist items through the document succeeded |
| C3 (line 53) | Valid root change plus invalid child value: ERROR 3819 chk_measurement_result_status; card stayed OPEN |
| C4 (line 61) | Valid child change plus invalid root change: ERROR 3819 chk_card_close_fields; child stayed PENDING |
| D1 (line 80) | Answer and close in one document: ERROR 50002; checklist stayed PENDING |
| D4 (line 105) | Reopen while another card is active: ERROR 1062 on uq_card_one_active_per_unit |
| D5 (line 115) | Reopen after removing the other card: succeeded (OPEN, open_unit_key 3). This was the gap |
| E1 (line 140) | Stale document after a direct child change: ERROR 6494 |
| E2 (line 146), E3 (line 151) | Unknown property and unprojected measurement_definition_id inside an array element: ERROR 6489, naming measurement_result and the full path |

FINAL check: 2 cards, 4 measurement rows, 6 checklist rows, 1 finding, no test cards, ETags of both views equal to the baseline.

## Step 7c results

| Line | Test | Before the lock | First lock (flawed) | Fixed lock |
|---|---|---|---|---|
| 27 | L1 reopen CLOSED card 1 | success (gap) | 50020 | 50020 |
| 36 | L2 change disposition of card 1 | success (gap) | 50020 | 50020 |
| 45 | L3 change a checklist answer of card 1 | success (gap) | 50021 (wrong number) | 50022 |
| 54 | L4 change a measurement of card 1 | success (gap) | 50021 | 50021 |
| 63 | L5 answer a pending item of REJECTED card 2 | success (gap) | 50021 (wrong number) | 50022 |
| 75 | P0 close card 930 with pending items | 50002 | 50002 | 50002 |
| 81 | P1 answer everything on an OPEN card | success | success | success |
| 93 | P2 close card 930 | success | 50021 (card stayed OPEN) | success (CLOSED, PASS, open_unit_key NULL) |
| 99 | P3 edit a checklist answer of the now closed card | success (gap) | no error (card 930 was never closed: uninformative) | 50022; answers stayed 3 YES |

In every run the data protected by an error was unchanged afterwards, and the FINAL check equalled the baseline (cards 1 CLOSED/PASS and 2 REJECTED/REJECT, 4 measurements, 6 checklist rows, 1 finding, 2 attachments, ETags of both views).

Trigger listing after creation (8 triggers): trg_inspection_card_bu has ACTION_ORDER 1 and trg_inspection_card_bu_lock has ACTION_ORDER 2.

## Findings

- A document write updates the root first and then the child rows, including child rows whose values did not change.
- Closing a card needs two document writes (answers, then close).
- Database triggers and CHECK constraints apply to document writes, and a failed document write is atomic.
- The ETag of the edit view covers its child rows and differs from the read view's ETag.
- A rule on a child table must ignore unchanged rows (B-017).
- After a lock the replay order matters: 05, then 06.

## Evidence notes

- Windows PowerShell prints each error line before or after the label it belongs to. Match each error to its test by the "at line N" number (see B-010). In the step 7b writes output the errors for lines 105, 140, 146 and 151 appear inside or next to neighbouring labels.
- d2-7b-writes.txt was captured before the lock. Running 25_write_tests_arrays.sql now would give ERROR 50020 for D4 and D5, because the lock fires before the unique index is checked.
- Test cards 900, 910, 911, 920 and 930 were created inside transactions that were rolled back. Auto-increment counters are not rolled back, so ids skip (for example measurement_result ids 19, 20, 28, 29, 31, 32, 34, 35, 37, 38).
- The lock-create run printed the trigger listing only; the lock itself is proven by the tests.
- Evidence text files were converted to UTF-8 with LF line endings.

## Next step

Refresh the backup set and the restore runbook for D2 (B-018); Design Pack v4; then the API phase (design agreed before code).
