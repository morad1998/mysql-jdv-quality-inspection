# D2 Steps 2 and 3 Summary: nested unit object and measurements array

## Overall result

PASS for both steps. inspection_card_dv is still read-only, is valid, and agrees with the tables after adding a nested unit object (step 2) and a nested measurements array (step 3). One observation is open: B-016.

D2 is not complete. Remaining steps: checklist results, findings and attachment metadata as nested arrays; write annotations; ETag, unknown-property and atomic-failure tests.

## Scripts (database/02_duality_views/)

| Script | Purpose |
|---|---|
| 05_inspection_card_dv_with_unit.sql | Recreates inspection_card_dv with a nested unit object |
| 06_verify_with_unit.sql | Read-only checks W1 to W6 |
| 07_followup_with_unit.sql | Nested write refusal and ETag observation, in rolled-back transactions |
| 08_inspection_card_dv_with_measurements.sql | Recreates inspection_card_dv with unit and a measurements array |
| 09_verify_with_measurements.sql | Read-only checks X1 to X8 |
| 10_followup_with_measurements.sql | Array write refusal, ETag coverage, NULL and empty cases, in rolled-back transactions |

## Results, step 2 (nested unit)

| Check | Result |
|---|---|
| View metadata | valid, READ_ONLY 1, insert/update/delete 0/0/0 |
| W1 | 2 documents, 2 table rows |
| W4 | unit node type OBJECT for both cards |
| W5 | 2 of 2 cards fully matching, including the nested object |
| W6 | 0 documents expose open_unit_key |
| S2 (real change to unit.unit_serial) | ERROR 6497 Missing UPDATE tag on production_unit.unit_serial, path $.unit.unit_serial; data and ETag unchanged afterwards |
| S4 (only the unit row changed) | The card ETag changed, so the ETag covers nested data |

## Results, step 3 (measurements array)

| Check | Result |
|---|---|
| View metadata | valid, READ_ONLY 1, insert/update/delete 0/0/0 |
| X1 | 2 documents, 2 table rows |
| X4 | measurements node type ARRAY, length 2 for both cards |
| X5a | 4 table rows, 4 elements in the documents |
| X5b | 4 of 4 elements fully matching, matched by measurement_result_id |
| X6 | Element order [1, 2] and [4, 5] (primary-key order; not guaranteed) |
| X7 | Nested unit still present and correct, 2 of 2 |
| X8 | 0 documents expose open_unit_key |
| M2 (real change to an array element) | ERROR 6497, refused; the error named $.unit.unit_id, not the changed path (B-016); data and ETag unchanged afterwards |
| M4 (only one measurement row changed) | The card ETag changed, so the ETag covers the array |
| M6a (new OPEN card) | Two PENDING elements with null recorded_at, recorded_by and measured_value |
| M6b (card with no measurement rows) | "measurements": null (JSON null), not [] |
| M7 | After rollback: 0 cards on unit 3, 2 cards in total, 4 measurement rows |

## ETag of card 1 by view version (same data)

| View version | ETag |
|---|---|
| Step 1 (flat) | d2a4080cedfed7c8845bd31c75c22f35 |
| Step 2 (with unit) | e5da5a2a79574f81b77a0293f9f11521 |
| Step 3 (with unit and measurements) | e3d6884abbc6aa86f48348f08890f9af |

## Evidence notes

- Windows PowerShell merges error and output streams with different buffering, so an ERROR line can appear before the test it belongs to. In d2-3-followup.txt the M2 error is printed at the top. The error belongs to the update at line 19 of 10_followup_with_measurements.sql (test M2). See B-010.
- All follow-up changes ran inside transactions that were rolled back; the state checks after each rollback show the baseline.
- Auto-increment counters are not rolled back, so ids skip. measurement_result ids 1, 2, 4, 5 show a skipped 3; the new card in M6a received ids 10 and 11.
- Evidence text files were converted to UTF-8 with LF line endings.
- Scripts 05, 08 drop and recreate inspection_card_dv. After the last step the live view is the step 3 version.

## Next step

D2 step 4: add the checklist results as the second nested array, with probes that characterize the error path in B-016.
