# D2 Step 4 Summary: second nested array (checklist) and B-016 probes

## Overall result

PASS. inspection_card_dv is still read-only, is valid, and agrees with the tables with a nested unit object and two independent nested arrays (measurements and checklist). The nine B-016 probes were all refused and left the data unchanged. B-016 stays WATCH with a characterized pattern and no known cause.

## Scripts (database/02_duality_views/)

| Script | Purpose |
|---|---|
| 11_inspection_card_dv_with_checklist.sql | Recreates inspection_card_dv with unit, measurements and checklist |
| 12_verify_with_checklist.sql | Read-only checks Y1 to Y9 |
| 13_probes_error_path.sql | Nine probes P1 to P9, each in a rolled-back transaction |

## Results

| Check | Result |
|---|---|
| View metadata | valid, READ_ONLY 1, insert/update/delete 0/0/0 |
| Y1 | 2 documents, 2 table rows |
| Y4 | measurements ARRAY length 2 and checklist ARRAY length 3 for both cards |
| Y5a | 6 table rows, 6 checklist elements |
| Y5b | 6 of 6 checklist elements fully matching |
| Y5c | 4 of 4 measurement elements still matching |
| Y6 | Checklist element order [1, 2, 3] and [4, 5, 6] (primary-key order; not guaranteed) |
| Y7, Y8 | Unit still matches 2 of 2; 0 documents expose open_unit_key |
| Probes P1 to P9 | All nine refused with ERROR 6497; FINAL check equal to BASELINE (same ETags, counts 2, 4, 6; opened_by 1 and 2; checklist of card 1 all YES) |

## B-016 probe table

| Line in 13_probes_error_path.sql | Probe | Path named in ERROR 6497 | Path correct? |
|---|---|---|---|
| 21 | P1 root opened_by | inspection_card.opened_by, $.opened_by | yes |
| 26 | P2 unit.unit_serial | production_unit.unit_serial, $.unit.unit_serial | yes |
| 31 | P3 measurements[0].result_status | inspection_card.unit_id, $.unit.unit_id | no |
| 36 | P4 measurements[0].measured_value | inspection_card.unit_id, $.unit.unit_id | no |
| 41 | P5 checklist[0].answer_code | inspection_card.unit_id, $.unit.unit_id | no |
| 46 | P6 opened_by plus checklist[0].answer_code in one statement | inspection_card.opened_by, $.opened_by | root path named |
| 51 | P7 repeat of P3 | inspection_card.unit_id, $.unit.unit_id | no (same as P3) |
| 56 | P8 measurements[0].result_status on card 2 | inspection_card.unit_id, $.unit.unit_id | no |
| 61 | P9 measurements[1].result_status | inspection_card.unit_id, $.unit.unit_id | no |

## ETag of each card by view version (same data)

| View version | Card 1 | Card 2 |
|---|---|---|
| Step 1 (flat) | d2a4080cedfed7c8845bd31c75c22f35 | 36abcd924f2f7dcc8b092ef8559f8d23 |
| Step 2 (with unit) | e5da5a2a79574f81b77a0293f9f11521 | 35ad8d49834b05a274a00acfefa1f844 |
| Step 3 (with unit and measurements) | e3d6884abbc6aa86f48348f08890f9af | b643594a6aeb85aa11ce75b7b7390f47 |
| Step 4 (with unit, measurements and checklist) | 6e2e2e43d45acf90218f5ab1b17c1980 | 74f7c59c6b4cac25ceb441247be97516 |

## Evidence notes

- Windows PowerShell prints each error line before or after the label it belongs to. Match each error to its probe by the "at line N" number in the table above (see B-010).
- Each probe ran inside a transaction that was rolled back. The state checks after the probes equal the baseline.
- Evidence text files were converted to UTF-8 with LF line endings.
- Script 11 drops and recreates inspection_card_dv. After this step the live view is the step 4 version.

## Next step

D2 step 5: add the findings as the third nested array, and test the B-016 hypothesis with two throwaway probe views.
