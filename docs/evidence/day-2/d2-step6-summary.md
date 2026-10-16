# D2 Step 6 Summary: attachments array and the short-key B-016 probe

## Overall result

PASS. inspection_card_dv is still read-only, is valid, and agrees with the tables with a nested unit object and four independent nested arrays (measurements, checklist, findings, attachments). The read side of D2 is complete. The short-key probe refuted the "first key" explanation for B-016.

## Scripts (database/02_duality_views/)

| Script | Purpose |
|---|---|
| 17_inspection_card_dv_with_attachments.sql | Recreates inspection_card_dv with unit and four arrays |
| 18_verify_with_attachments.sql | Checks AA1 to AA9 (read-only) and tests T1 to T3 (rolled-back transactions) |
| 19_probe_b016_short_key.sql | One throwaway view, probe_c_dv, whose nested object stores the key sn before unit_id; dropped at the end |

## Results

| Check | Result |
|---|---|
| View metadata | valid, READ_ONLY 1, insert/update/delete 0/0/0 |
| AA1 | 2 documents, 2 table rows |
| AA2 and AA3 | Card 1 has two attachments (finding_id 1, and finding_id null); card 2 shows null; the table has two rows |
| AA4 | Card 1 ARRAY in all four arrays; card 2 ARRAY, ARRAY, NULL, NULL |
| AA5a | Table rows 4, 6, 1, 2 and document elements 4, 6, 1, 2 |
| AA5b | 2 of 2 attachments fully matching, including the null finding_id |
| AA6 | Attachment order [1, 2] for card 1, NULL for card 2 |
| AA7, AA8 | Unit still matches 2 of 2; 0 documents expose open_unit_key |
| T1 (attachment inserted directly into card 2, rolled back) | Card 2 attachments changed from null to ARRAY of 1; its ETag changed |
| T2 (real change to attachments[0].file_name through the view) | ERROR 6497 naming inspection_card.unit_id, path $.unit.unit_id (B-016 pattern); file_name still photo1.jpg |
| T3 (after the rollbacks) | 2 attachment rows, photo1.jpg, ETags equal to AA9 |

## B-016 short-key probe (script 19)

| Line in script 19 | Probe | Path named in ERROR 6497 | Correct? |
|---|---|---|---|
| (JSON_KEYS) | stored key order of the nested unit object | ["sn", "unit_id"] | sn is stored first, as intended |
| 56 | C1 array element result_status | inspection_card.unit_id, $.unit.unit_id | no |
| 61 | C2 nested object field sn | production_unit.unit_serial, $.unit.sn | yes |
| 66 | C3 root opened_by | inspection_card.opened_by, $.opened_by | yes |

FINAL check: 0 probe views left, opened_by 1 and 2, unit serial SN-DEMO-0001.

Reading: even with sn stored first, the array-element error still named the join column unit_id. The first-key explanation is refuted. A join-column explanation is consistent but not proven (see B-016).

## ETag of each card by view version (same data)

| View version | Card 1 | Card 2 |
|---|---|---|
| Step 1 (flat) | d2a4080cedfed7c8845bd31c75c22f35 | 36abcd924f2f7dcc8b092ef8559f8d23 |
| Step 2 (with unit) | e5da5a2a79574f81b77a0293f9f11521 | 35ad8d49834b05a274a00acfefa1f844 |
| Step 3 (unit, measurements) | e3d6884abbc6aa86f48348f08890f9af | b643594a6aeb85aa11ce75b7b7390f47 |
| Step 4 (plus checklist) | 6e2e2e43d45acf90218f5ab1b17c1980 | 74f7c59c6b4cac25ceb441247be97516 |
| Step 5 (plus findings) | a7406ed8e5cb22ffaabee4c5464c7539 | 1058ee0acd03c056694cffacae5bf555 |
| Step 6 (plus attachments) | 3771df754a7104188f3b9139d41986a7 | a1d3e9312e549f7dad4fb6c001b2532c |

## Evidence notes

- Windows PowerShell prints each error line before or after the label it belongs to. In d2-6-verify.txt the T2 error (line 111 of script 18) is printed next to check AA8. Match errors to probes by the "at line N" number (see B-010).
- Test T1 inserted an attachment inside a transaction that was rolled back. The AUTO_INCREMENT counter is not rolled back; the next automatic attachment id is expected to be 4.
- Evidence text files were converted to UTF-8 with LF line endings.
- Script 17 drops and recreates inspection_card_dv. After this step the live view is the step 6 version.

## Next step

Write phase: a separate edit view with modification tags, which tests B-008. The design is agreed before scripts are written.
