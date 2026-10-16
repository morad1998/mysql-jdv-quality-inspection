# D2 Step 7a Summary: writable edit view, root close path

## Overall result

PASS. A separate update-enabled view, inspection_card_edit_dv, was created over inspection_card and is valid. Writes through documents obey the table's triggers and CHECK constraints, unknown and unprojected paths are refused, a stale ETag is refused, and the read view is unchanged. B-008 is resolved for UPDATE.

D2 is not complete. Remaining: the two child arrays for update, atomic-failure and close-in-one-document behavior, reopen and one-active-card behavior through documents.

## Scripts (database/02_duality_views/)

| Script | Purpose |
|---|---|
| 20_inspection_card_edit_dv.sql | Creates inspection_card_edit_dv with WITH (UPDATE) on the root object |
| 21_verify_edit_view_read.sql | Read-only checks V1 to V7, including a regression check of the read view |
| 22_write_tests_root.sql | Write tests A1 to A5 and B0 to B5 in two transactions that are rolled back |
| 98_rollback_edit_view.sql | Drops inspection_card_edit_dv only |

## Results

| Check | Result |
|---|---|
| View metadata | inspection_card_edit_dv: ALLOW_INSERT 0, ALLOW_UPDATE 1, ALLOW_DELETE 0, READ_ONLY 0, valid. inspection_card_dv unchanged: READ_ONLY 1, valid |
| V1 to V4 | 2 documents with only _id, _metadata, closed_at, closed_by, card_status, disposition; 2 of 2 matching the table |
| V5 | 0 documents expose open_unit_key |
| V6 | Edit-view ETags 9052eccba3447c89cd79e0934d056d28 and b59ab53f009206f9695cb44a1b6cfdb8 |
| V7 | Read-view ETags unchanged: 3771df754a7104188f3b9139d41986a7 and a1d3e9312e549f7dad4fb6c001b2532c |

## Write tests (script 22)

| Line | Test | Result |
|---|---|---|
| 31 | A2 close with PENDING checklist items | ERROR 50002; card stays OPEN |
| 41 | A3 close with an open CRITICAL finding | ERROR 50003; card stays OPEN |
| 50 | A4 close with every rule satisfied | Success: CLOSED, PASS, closed_by 3, closed_at 2026-10-16 02:00:00, open_unit_key NULL |
| 70 | B0 OPEN to IN_PROGRESS | Success; open_unit_key 3 |
| 77 | B1 close without a disposition | ERROR 3819 chk_card_disposition_final; card stays IN_PROGRESS |
| 84 | B2 unknown property bogus | ERROR 6489 Path '$.bogus' is not mapped to any column of inspection_card |
| 89 | B3 real column opened_by, not projected | ERROR 6489 Path '$.opened_by' is not mapped to any column of inspection_card; opened_by still 1 |
| (direct) | B4 change opened_by directly | Edit-view ETag unchanged (b6f72c3eb59f0e94b8bb79a26e59e5fc before and after) |
| 108 | B5 stale document after a direct change | ERROR 6494; card stays OPEN. Stale ETag b6f72c3e..., current 51de0dc9... |

FINAL check: 2 cards, 4 measurement rows, 6 checklist rows, 1 finding, 0 test cards left, read-view ETags equal to the baseline, card 1 CLOSED/PASS, card 2 REJECTED/REJECT.

## Evidence notes

- Windows PowerShell prints each error line before or after the label it belongs to. In d2-7a-writes.txt the errors appear out of order (for example ERROR 3819 appears inside the B0 label block). Match each error to its test by the "at line N" number in the table above (see B-010).
- All write tests ran inside transactions that were rolled back. Auto-increment counters are not rolled back, so ids skip.
- Evidence text files were converted to UTF-8 with LF line endings.
- The .gitkeep files in database/01_schema, 02_seed, 03_duality_views and 04_tests and in some docs folders are empty Day 0 placeholders. The real scripts live in database/00_environment, 01_domain_model and 02_duality_views.

## Next step

Step 7b: add the measurements and checklist arrays (update only) to inspection_card_edit_dv; test atomic failure, answer-and-close in one document, reopen, and the one-active-card rule through documents.
