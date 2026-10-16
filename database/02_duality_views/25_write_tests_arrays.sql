-- =====================================================================
-- D2 / Step 7b write tests: child arrays, atomic failure, close-in-one-document, reopen, one-active-card
-- Run as : quality_app, with the mysql client option --force
-- Safety : every change runs inside one of four transactions (C, D, E) that are rolled back, and the
--          script checks the baseline afterwards. Nothing is committed. Test cards use explicit ids
--          900, 910, 911 and 920, all on unit 3.
-- Side effect: card inserts fire the N2 trigger, which inserts result rows with automatic ids; a rollback
--          does not reset those counters, so later automatic ids skip.
-- An ERROR line carries "at line N": match N to the table in the chat message.
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

SELECT 'BASELINE: counts and the edit-view etags' AS test_step;
SELECT (SELECT COUNT(*) FROM inspection_card) AS cards,
       (SELECT COUNT(*) FROM measurement_result) AS measurements,
       (SELECT COUNT(*) FROM checklist_result) AS checklist,
       (SELECT COUNT(*) FROM quality_finding) AS findings;
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS edit_view_etag
FROM inspection_card_edit_dv ORDER BY CAST(data->>'$._id' AS UNSIGNED);

-- ---------------------------------------------------------------
-- TRANSACTION C: child updates and atomic failure (card 900)
-- ---------------------------------------------------------------
START TRANSACTION;
INSERT INTO inspection_card (card_id, unit_id, opened_by) VALUES (900, 3, 1);

SELECT 'C0 the new card as the edit view shows it: EXPECT 2 PENDING measurements and 3 PENDING checklist items' AS test_step;
SELECT JSON_PRETTY(data) AS doc FROM inspection_card_edit_dv WHERE data->>'$._id' = '900';

SELECT 'C1 record the first measurement through the document -> EXPECT success' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data,
         '$.measurements[0].result_status', 'RECORDED',
         '$.measurements[0].measured_value', 1000.125,
         '$.measurements[0].recorded_by', 1,
         '$.measurements[0].recorded_at', '2026-10-16 02:10:00.000000')
 WHERE data->>'$._id' = '900';
SELECT 'C1 table rows: EXPECT the lower id RECORDED 1000.125 by 1, the other still PENDING' AS test_step;
SELECT measurement_result_id, result_status, measured_value, recorded_by FROM measurement_result WHERE card_id = 900 ORDER BY measurement_result_id;

SELECT 'C2 answer all three checklist items in one document -> EXPECT success' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data,
         '$.checklist[0].answer_code', 'YES', '$.checklist[0].answered_by', 1, '$.checklist[0].answered_at', '2026-10-16 02:11:00.000000',
         '$.checklist[1].answer_code', 'YES', '$.checklist[1].answered_by', 1, '$.checklist[1].answered_at', '2026-10-16 02:11:00.000000',
         '$.checklist[2].answer_code', 'YES', '$.checklist[2].answered_by', 1, '$.checklist[2].answered_at', '2026-10-16 02:11:00.000000')
 WHERE data->>'$._id' = '900';
SELECT 'C2 table rows: EXPECT YES 3' AS test_step;
SELECT answer_code, COUNT(*) AS n FROM checklist_result WHERE card_id = 900 GROUP BY answer_code;

SELECT 'C3 atomic failure, variant a: valid root change plus an INVALID child value -> EXPECT an error, root and child unchanged' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.card_status', 'IN_PROGRESS', '$.measurements[1].result_status', 'BOGUS')
 WHERE data->>'$._id' = '900';
SELECT 'C3 state check: EXPECT card OPEN, second measurement PENDING' AS test_step;
SELECT card_status FROM inspection_card WHERE card_id = 900;
SELECT measurement_result_id, result_status FROM measurement_result WHERE card_id = 900 ORDER BY measurement_result_id;

SELECT 'C4 atomic failure, variant b: valid child change plus an INVALID root change (CLOSED without a disposition) -> EXPECT an error, child unchanged' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.card_status', 'CLOSED',
         '$.measurements[1].result_status', 'NOT_APPLICABLE', '$.measurements[1].recorded_by', 1, '$.measurements[1].recorded_at', '2026-10-16 02:12:00.000000')
 WHERE data->>'$._id' = '900';
SELECT 'C4 state check: EXPECT card OPEN, second measurement still PENDING (if the document write is atomic)' AS test_step;
SELECT card_status FROM inspection_card WHERE card_id = 900;
SELECT measurement_result_id, result_status FROM measurement_result WHERE card_id = 900 ORDER BY measurement_result_id;
ROLLBACK;

SELECT 'C5 after rollback: card 900 gone. EXPECT 0 rows' AS test_step;
SELECT COUNT(*) AS rows_for_card_900 FROM inspection_card WHERE card_id = 900;

-- ---------------------------------------------------------------
-- TRANSACTION D: answer-and-close in one document, reopen, one-active-card (cards 910 and 911)
-- ---------------------------------------------------------------
START TRANSACTION;
INSERT INTO inspection_card (card_id, unit_id, opened_by) VALUES (910, 3, 1);

SELECT 'D1 OBSERVATION: answer all checklist items AND close in ONE document. Success = the close rule sees the answers; ERROR 50002 = the root is checked before the children are applied' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data,
         '$.checklist[0].answer_code', 'YES', '$.checklist[0].answered_by', 1, '$.checklist[0].answered_at', '2026-10-16 02:20:00.000000',
         '$.checklist[1].answer_code', 'YES', '$.checklist[1].answered_by', 1, '$.checklist[1].answered_at', '2026-10-16 02:20:00.000000',
         '$.checklist[2].answer_code', 'YES', '$.checklist[2].answered_by', 1, '$.checklist[2].answered_at', '2026-10-16 02:20:00.000000',
         '$.card_status', 'CLOSED', '$.disposition', 'PASS', '$.closed_by', 3, '$.closed_at', '2026-10-16 02:20:00.000000')
 WHERE data->>'$._id' = '910';
SELECT 'D1 state: record the card status and the checklist answers' AS test_step;
SELECT card_status, disposition FROM inspection_card WHERE card_id = 910;
SELECT answer_code, COUNT(*) AS n FROM checklist_result WHERE card_id = 910 GROUP BY answer_code;

SELECT 'D2 bring card 910 to CLOSED whatever D1 did (direct answers, then close through the document)' AS test_step;
UPDATE checklist_result SET answer_code = 'YES', answered_by = 1, answered_at = '2026-10-16 02:20:00' WHERE card_id = 910 AND answer_code = 'PENDING';
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.card_status', 'CLOSED', '$.disposition', 'PASS', '$.closed_by', 3, '$.closed_at', '2026-10-16 02:20:00.000000')
 WHERE data->>'$._id' = '910';
SELECT 'D2 state: EXPECT CLOSED, PASS, open_unit_key NULL' AS test_step;
SELECT card_status, disposition, open_unit_key FROM inspection_card WHERE card_id = 910;

SELECT 'D3 open a second card on the same unit (allowed, because 910 is closed)' AS test_step;
INSERT INTO inspection_card (card_id, unit_id, opened_by) VALUES (911, 3, 1);
SELECT card_id, card_status, open_unit_key FROM inspection_card WHERE card_id IN (910, 911) ORDER BY card_id;
-- Expected: 910 CLOSED NULL; 911 OPEN 3

SELECT 'D4 REOPEN card 910 through the document while card 911 is active -> EXPECT ERROR 1062 on uq_card_one_active_per_unit' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.card_status', 'OPEN', '$.disposition', CAST('null' AS JSON), '$.closed_by', CAST('null' AS JSON), '$.closed_at', CAST('null' AS JSON))
 WHERE data->>'$._id' = '910';
SELECT 'D4 state check: EXPECT card 910 still CLOSED' AS test_step;
SELECT card_status, disposition FROM inspection_card WHERE card_id = 910;

SELECT 'D5 remove card 911 directly, then REOPEN card 910 through the document -> OBSERVATION: success means the database has no reopen rule' AS test_step;
DELETE FROM measurement_result WHERE card_id = 911;
DELETE FROM checklist_result WHERE card_id = 911;
DELETE FROM inspection_card WHERE card_id = 911;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.card_status', 'OPEN', '$.disposition', CAST('null' AS JSON), '$.closed_by', CAST('null' AS JSON), '$.closed_at', CAST('null' AS JSON))
 WHERE data->>'$._id' = '910';
SELECT 'D5 state: record the result' AS test_step;
SELECT card_status, disposition, closed_by, closed_at, open_unit_key FROM inspection_card WHERE card_id = 910;
ROLLBACK;

SELECT 'D6 after rollback: cards 910 and 911 gone. EXPECT 0' AS test_step;
SELECT COUNT(*) AS rows_for_cards_910_911 FROM inspection_card WHERE card_id IN (910, 911);

-- ---------------------------------------------------------------
-- TRANSACTION E: stale etag on a child change, unknown and unprojected paths inside an array (card 920)
-- ---------------------------------------------------------------
START TRANSACTION;
INSERT INTO inspection_card (card_id, unit_id, opened_by) VALUES (920, 3, 1);

SELECT 'E0 keep the document, then change ONE measurement row directly; the card etag should change' AS test_step;
SET @stale_document = (SELECT data FROM inspection_card_edit_dv WHERE data->>'$._id' = '920');
SELECT JSON_UNQUOTE(JSON_EXTRACT(@stale_document, '$._metadata.etag')) AS stale_etag;
UPDATE measurement_result
   SET result_status = 'NOT_APPLICABLE', recorded_by = 1, recorded_at = '2026-10-16 02:30:00'
 WHERE card_id = 920 ORDER BY measurement_result_id LIMIT 1;
SELECT data->>'$._metadata.etag' AS current_etag FROM inspection_card_edit_dv WHERE data->>'$._id' = '920';

SELECT 'E1 write the stale document -> EXPECT ERROR 6494, card unchanged' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(@stale_document, '$.card_status', 'IN_PROGRESS')
 WHERE data->>'$._id' = '920';
SELECT card_status FROM inspection_card WHERE card_id = 920;

SELECT 'E2 unknown property inside an array element -> EXPECT ERROR 6489 (record the path it names)' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.measurements[0].bogus', 1)
 WHERE data->>'$._id' = '920';

SELECT 'E3 real column not projected inside an array element (measurement_definition_id) -> EXPECT ERROR 6489 (record the path)' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.measurements[0].measurement_definition_id', 2)
 WHERE data->>'$._id' = '920';
SELECT 'E3 state check: EXPECT the definition ids of the card 920 results unchanged (1 and 2)' AS test_step;
SELECT measurement_result_id, measurement_definition_id FROM measurement_result WHERE card_id = 920 ORDER BY measurement_result_id;
ROLLBACK;

SELECT 'FINAL baseline check. EXPECT the same counts and etags as BASELINE, and no test cards left' AS test_step;
SELECT (SELECT COUNT(*) FROM inspection_card) AS cards,
       (SELECT COUNT(*) FROM measurement_result) AS measurements,
       (SELECT COUNT(*) FROM checklist_result) AS checklist,
       (SELECT COUNT(*) FROM quality_finding) AS findings,
       (SELECT COUNT(*) FROM inspection_card WHERE card_id IN (900, 910, 911, 920)) AS test_cards_left;
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS edit_view_etag
FROM inspection_card_edit_dv ORDER BY CAST(data->>'$._id' AS UNSIGNED);
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS read_view_etag
FROM inspection_card_dv ORDER BY CAST(data->>'$._id' AS UNSIGNED);
SELECT card_id, card_status, disposition, opened_by FROM inspection_card ORDER BY card_id;
