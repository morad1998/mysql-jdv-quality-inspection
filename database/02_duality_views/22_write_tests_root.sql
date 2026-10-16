-- =====================================================================
-- D2 / Step 7a write tests: close path through the document, and rejections
-- Run as : quality_app, with the mysql client option --force
-- Safety : all changes run inside two transactions that are rolled back, and the script checks
--          the baseline afterwards. Nothing is committed. Test cards use explicit ids 900 and 901 on unit 3.
-- Side effect: the card insert fires the N2 trigger, which inserts result rows with automatic ids;
--          a rollback does not reset those counters, so later automatic ids skip.
-- An ERROR line carries "at line N": match N to the table in the chat message.
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

SELECT 'BASELINE: counts and the two read-view etags' AS test_step;
SELECT (SELECT COUNT(*) FROM inspection_card) AS cards,
       (SELECT COUNT(*) FROM measurement_result) AS measurements,
       (SELECT COUNT(*) FROM checklist_result) AS checklist,
       (SELECT COUNT(*) FROM quality_finding) AS findings;
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS read_view_etag
FROM inspection_card_dv ORDER BY CAST(data->>'$._id' AS UNSIGNED);

-- ---------------------------------------------------------------
-- TRANSACTION A: the close path (business rules must fire for document writes too)
-- ---------------------------------------------------------------
START TRANSACTION;
INSERT INTO inspection_card (card_id, unit_id, opened_by) VALUES (900, 3, 1);

SELECT 'A1 new card 900 has 3 PENDING checklist rows (N2). EXPECT 3' AS test_step;
SELECT COUNT(*) AS pending_checklist FROM checklist_result WHERE card_id = 900 AND answer_code = 'PENDING';

SELECT 'A2 close card 900 through the document while checklist items are PENDING -> EXPECT ERROR 50002' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.card_status', 'CLOSED', '$.disposition', 'PASS', '$.closed_by', 3, '$.closed_at', '2026-10-16 02:00:00.000000')
 WHERE data->>'$._id' = '900';
SELECT 'A2 state check: EXPECT OPEN and NULL' AS test_step;
SELECT card_status, disposition FROM inspection_card WHERE card_id = 900;

UPDATE checklist_result SET answer_code = 'YES', answered_by = 1, answered_at = UTC_TIMESTAMP() WHERE card_id = 900;
INSERT INTO quality_finding (finding_id, card_id, severity, description, raised_by) VALUES (900, 900, 'CRITICAL', 'Demo critical finding for write test', 1);

SELECT 'A3 close card 900 through the document with an open CRITICAL finding -> EXPECT ERROR 50003' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.card_status', 'CLOSED', '$.disposition', 'PASS', '$.closed_by', 3, '$.closed_at', '2026-10-16 02:00:00.000000')
 WHERE data->>'$._id' = '900';
SELECT 'A3 state check: EXPECT OPEN and NULL' AS test_step;
SELECT card_status, disposition FROM inspection_card WHERE card_id = 900;

UPDATE quality_finding SET finding_status = 'RESOLVED', resolved_at = UTC_TIMESTAMP() WHERE finding_id = 900;

SELECT 'A4 close card 900 through the document with all rules satisfied -> EXPECT success' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.card_status', 'CLOSED', '$.disposition', 'PASS', '$.closed_by', 3, '$.closed_at', '2026-10-16 02:00:00.000000')
 WHERE data->>'$._id' = '900';
SELECT 'A4 table row: EXPECT CLOSED, PASS, 3, closed_at set, open_unit_key NULL' AS test_step;
SELECT card_status, disposition, closed_by, closed_at, open_unit_key FROM inspection_card WHERE card_id = 900;
SELECT 'A4 the document as the edit view now shows it' AS test_step;
SELECT JSON_PRETTY(data) AS doc FROM inspection_card_edit_dv WHERE data->>'$._id' = '900';
ROLLBACK;

SELECT 'A5 after rollback: card 900 gone. EXPECT 0 rows' AS test_step;
SELECT COUNT(*) AS rows_for_card_900 FROM inspection_card WHERE card_id = 900;

-- ---------------------------------------------------------------
-- TRANSACTION B: a successful write, and rejections
-- ---------------------------------------------------------------
START TRANSACTION;
INSERT INTO inspection_card (card_id, unit_id, opened_by) VALUES (901, 3, 1);
UPDATE checklist_result SET answer_code = 'YES', answered_by = 1, answered_at = UTC_TIMESTAMP() WHERE card_id = 901;

SELECT 'B0 positive control: OPEN to IN_PROGRESS through the document -> EXPECT success' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.card_status', 'IN_PROGRESS')
 WHERE data->>'$._id' = '901';
SELECT 'B0 state check: EXPECT IN_PROGRESS and open_unit_key 3 (still the active card for unit 3)' AS test_step;
SELECT card_status, open_unit_key FROM inspection_card WHERE card_id = 901;

SELECT 'B1 close without a disposition -> EXPECT an error, probably 3819 (check chk_card_disposition_final)' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.card_status', 'CLOSED', '$.closed_by', 3, '$.closed_at', '2026-10-16 02:00:00.000000')
 WHERE data->>'$._id' = '901';
SELECT 'B1 state check: EXPECT IN_PROGRESS' AS test_step;
SELECT card_status, disposition FROM inspection_card WHERE card_id = 901;

SELECT 'B2 unknown property bogus -> EXPECT an error (record its number and text)' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.bogus', 1)
 WHERE data->>'$._id' = '901';

SELECT 'B3 a REAL column that the view does not project (opened_by) -> EXPECT an error (record whether it differs from B2)' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.opened_by', 2)
 WHERE data->>'$._id' = '901';
SELECT 'B3 state check: EXPECT opened_by 1' AS test_step;
SELECT opened_by FROM inspection_card WHERE card_id = 901;

SELECT 'B4 observation: does the etag change when only an UNPROJECTED column changes? (direct table update)' AS test_step;
SELECT data->>'$._metadata.etag' AS etag_before FROM inspection_card_edit_dv WHERE data->>'$._id' = '901';
UPDATE inspection_card SET opened_by = 2 WHERE card_id = 901;
SELECT data->>'$._metadata.etag' AS etag_after_unprojected_change FROM inspection_card_edit_dv WHERE data->>'$._id' = '901';
UPDATE inspection_card SET opened_by = 1 WHERE card_id = 901;

SELECT 'B5 stale etag: keep the document, change a projected field directly, then write the old document -> EXPECT ERROR 6494' AS test_step;
SET @stale_document = (SELECT data FROM inspection_card_edit_dv WHERE data->>'$._id' = '901');
SELECT JSON_UNQUOTE(JSON_EXTRACT(@stale_document, '$._metadata.etag')) AS stale_etag,
       JSON_UNQUOTE(JSON_EXTRACT(@stale_document, '$.card_status')) AS stale_card_status;
UPDATE inspection_card SET card_status = 'OPEN' WHERE card_id = 901;
SELECT data->>'$._metadata.etag' AS current_etag, data->>'$.card_status' AS current_card_status
FROM inspection_card_edit_dv WHERE data->>'$._id' = '901';
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(@stale_document, '$.card_status', 'IN_PROGRESS')
 WHERE data->>'$._id' = '901';
SELECT 'B5 state check: EXPECT OPEN (the stale write must not have been applied)' AS test_step;
SELECT card_status FROM inspection_card WHERE card_id = 901;
ROLLBACK;

SELECT 'FINAL baseline check. EXPECT the same counts and the same read-view etags as BASELINE, and no cards 900 or 901' AS test_step;
SELECT (SELECT COUNT(*) FROM inspection_card) AS cards,
       (SELECT COUNT(*) FROM measurement_result) AS measurements,
       (SELECT COUNT(*) FROM checklist_result) AS checklist,
       (SELECT COUNT(*) FROM quality_finding) AS findings,
       (SELECT COUNT(*) FROM inspection_card WHERE card_id IN (900, 901)) AS test_cards_left;
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS read_view_etag
FROM inspection_card_dv ORDER BY CAST(data->>'$._id' AS UNSIGNED);
SELECT card_id, card_status, disposition, opened_by FROM inspection_card ORDER BY card_id;
