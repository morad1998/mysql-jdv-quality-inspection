# D2 Step 5 Summary: findings array and B-016 probe views

## Overall result

PASS. inspection_card_dv is still read-only, is valid, and agrees with the tables with a nested unit object and three independent nested arrays (measurements, checklist, findings). The B-016 throwaway views narrowed the pattern: the misleading error path appears only when a nested single object is present. The cause is still unknown and one hypothesis pair is still not separated.

## Scripts (database/02_duality_views/)

| Script | Purpose |
|---|---|
| 14_inspection_card_dv_with_findings.sql | Recreates inspection_card_dv with unit, measurements, checklist and findings |
| 15_verify_with_findings.sql | Checks Z1 to Z9 (read-only) and tests R1 to R3 (rolled-back transactions) |
| 16_probe_b016_hypothesis.sql | Two throwaway views, probe_a_dv and probe_b_dv, and five refused updates; both views dropped at the end |

## Results

| Check | Result |
|---|---|
| View metadata | valid, READ_ONLY 1, insert/update/delete 0/0/0 |
| Z1 | 2 documents, 2 table rows |
| Z2 and Z3 | Card 1 has one finding (CRITICAL, RESOLVED, description and resolved_at present); card 2 shows null; the table has one row |
| Z4 | Card 1 ARRAY, ARRAY, ARRAY; card 2 ARRAY, ARRAY, NULL (findings) |
| Z5a | Table rows 4, 6, 1 and document elements 4, 6, 1 (counting real arrays only) |
| Z5b | 1 of 1 finding fully matching |
| Z6 | Findings order [1] for card 1, NULL for card 2 |
| Z7, Z8 | Unit still matches 2 of 2; 0 documents expose open_unit_key |
| R1 (second finding inserted directly, rolled back) | Two elements, order [1, 2], ETag changed |
| R2 (real change to findings[0].severity through the view) | ERROR 6497 naming inspection_card.unit_id, path $.unit.unit_id (B-016 pattern); severity still CRITICAL |
| R3 (after the rollbacks) | 1 finding row, severity CRITICAL, ETags equal to Z9 |

## B-016 throwaway-view results (script 16)

| Line in script 16 | Probe | Path named in ERROR 6497 | Correct? |
|---|---|---|---|
| 76 | A1 probe_a root opened_by | inspection_card.opened_by, $.opened_by | yes |
| 81 | A2 probe_a measurements[0].result_status (no nested unit in this view) | measurement_result.result_status, $.measurements[0].result_status | yes |
| 86 | B1 probe_b root opened_by | inspection_card.opened_by, $.opened_by | yes |
| 91 | B2 probe_b unit.unit_serial | production_unit.unit_serial, $.unit.unit_serial | yes |
| 96 | B3 probe_b measurements[0].result_status (nested unit present) | inspection_card.unit_id, $.unit.unit_id | no |

FINAL check: 0 probe views left, opened_by 1 and 2, 4 measurement rows, result 1 still RECORDED.

## ETag of each card by view version (same data)

| View version | Card 1 | Card 2 |
|---|---|---|
| Step 1 (flat) | d2a4080cedfed7c8845bd31c75c22f35 | 36abcd924f2f7dcc8b092ef8559f8d23 |
| Step 2 (with unit) | e5da5a2a79574f81b77a0293f9f11521 | 35ad8d49834b05a274a00acfefa1f844 |
| Step 3 (with unit and measurements) | e3d6884abbc6aa86f48348f08890f9af | b643594a6aeb85aa11ce75b7b7390f47 |
| Step 4 (with unit, measurements and checklist) | 6e2e2e43d45acf90218f5ab1b17c1980 | 74f7c59c6b4cac25ceb441247be97516 |
| Step 5 (with unit, measurements, checklist and findings) | a7406ed8e5cb22ffaabee4c5464c7539 | 1058ee0acd03c056694cffacae5bf555 |

## Evidence notes

- Windows PowerShell prints each error line before or after the label it belongs to. Match each error to its probe by the "at line N" number (see B-010).
- Test R1 inserted a finding inside a transaction that was rolled back. The AUTO_INCREMENT counter is not rolled back.
- Probe design flaw: probe_b_dv listed unit_serial before unit_id to test a "first field" hypothesis, but MySQL stores JSON keys shorter-first, so unit_id stayed first. See B-016.
- Evidence text files were converted to UTF-8 with LF line endings.
- Script 14 drops and recreates inspection_card_dv. After this step the live view is the step 5 version.

## Next step

D2 step 6: add the attachment metadata as the fourth nested array, and run one more probe view whose nested object has a short key before the join column (script 19).
