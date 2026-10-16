-- =====================================================================
-- D2 / Step 7c tests: can a final card or its results be changed through a document?
-- Run as : quality_app, with the mysql client option --force. RUN IT TWICE:
--          once BEFORE 05_final_card_lock_triggers.sql (shows the gap) and once AFTER (shows the lock).
-- Safety : every test runs in its own transaction that is rolled back; the script checks the baseline
--          at the end. Nothing is committed. The new test card uses the explicit id 930 on unit 3.
-- Side effect: the card insert fires the N2 trigger, which inserts result rows with automatic ids; a
--          rollback does not reset those counters.
-- An ERROR line carries "at line N": match N to the table in the chat message.
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

SELECT 'BASELINE: cards, counts and the etags of both views' AS test_step;
SELECT card_id, card_status, disposition, opened_by FROM inspection_card ORDER BY card_id;
SELECT (SELECT COUNT(*) FROM measurement_result) AS measurements,
       (SELECT COUNT(*) FROM checklist_result)   AS checklist,
       (SELECT COUNT(*) FROM quality_finding)    AS findings,
       (SELECT COUNT(*) FROM attachment_metadata) AS attachments;
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS edit_view_etag
FROM inspection_card_edit_dv ORDER BY CAST(data->>'$._id' AS UNSIGNED);
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS read_view_etag
FROM inspection_card_dv ORDER BY CAST(data->>'$._id' AS UNSIGNED);

SELECT 'L1 reopen CLOSED card 1 through the document. BEFORE lock: success. AFTER lock: ERROR 50020' AS test_step;
START TRANSACTION;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.card_status', 'OPEN', '$.disposition', CAST('null' AS JSON), '$.closed_by', CAST('null' AS JSON), '$.closed_at', CAST('null' AS JSON))
 WHERE data->>'$._id' = '1';
SELECT 'L1 state (inside the transaction)' AS test_step;
SELECT card_id, card_status, disposition, open_unit_key FROM inspection_card WHERE card_id = 1;
ROLLBACK;

SELECT 'L2 change the disposition of CLOSED card 1 from PASS to REJECT. BEFORE lock: success. AFTER lock: ERROR 50020' AS test_step;
START TRANSACTION;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.disposition', 'REJECT')
 WHERE data->>'$._id' = '1';
SELECT 'L2 state (inside the transaction)' AS test_step;
SELECT card_id, card_status, disposition FROM inspection_card WHERE card_id = 1;
ROLLBACK;

SELECT 'L3 change a checklist answer of CLOSED card 1 from YES to NO. BEFORE lock: success. AFTER lock: ERROR 50022' AS test_step;
START TRANSACTION;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.checklist[0].answer_code', 'NO')
 WHERE data->>'$._id' = '1';
SELECT 'L3 state (inside the transaction)' AS test_step;
SELECT checklist_result_id, answer_code FROM checklist_result WHERE card_id = 1 ORDER BY checklist_result_id;
ROLLBACK;

SELECT 'L4 change a recorded measurement of CLOSED card 1 from 1000.250 to 999.500. BEFORE lock: success. AFTER lock: ERROR 50021' AS test_step;
START TRANSACTION;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.measurements[0].measured_value', 999.5)
 WHERE data->>'$._id' = '1';
SELECT 'L4 state (inside the transaction)' AS test_step;
SELECT measurement_result_id, result_status, measured_value FROM measurement_result WHERE card_id = 1 ORDER BY measurement_result_id;
ROLLBACK;

SELECT 'L5 answer a PENDING checklist item of REJECTED card 2. BEFORE lock: success. AFTER lock: ERROR 50022' AS test_step;
START TRANSACTION;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.checklist[0].answer_code', 'YES', '$.checklist[0].answered_by', 1, '$.checklist[0].answered_at', '2026-10-16 03:00:00.000000')
 WHERE data->>'$._id' = '2';
SELECT 'L5 state (inside the transaction)' AS test_step;
SELECT checklist_result_id, answer_code FROM checklist_result WHERE card_id = 2 ORDER BY checklist_result_id;
ROLLBACK;

SELECT 'POSITIVE CONTROLS on a new OPEN card 930: P0 and P3 are regressions of rules that must hold before AND after the lock' AS test_step;
START TRANSACTION;
INSERT INTO inspection_card (card_id, unit_id, opened_by) VALUES (930, 3, 1);

SELECT 'P0 close card 930 with PENDING checklist items. BEFORE and AFTER lock: ERROR 50002 (D1 rule, unchanged)' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.card_status', 'CLOSED', '$.disposition', 'PASS', '$.closed_by', 3, '$.closed_at', '2026-10-16 03:10:00.000000')
 WHERE data->>'$._id' = '930';
SELECT card_status FROM inspection_card WHERE card_id = 930;

SELECT 'P1 answer all checklist items and record one measurement on the OPEN card through the document. BEFORE and AFTER lock: success' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data,
         '$.checklist[0].answer_code', 'YES', '$.checklist[0].answered_by', 1, '$.checklist[0].answered_at', '2026-10-16 03:11:00.000000',
         '$.checklist[1].answer_code', 'YES', '$.checklist[1].answered_by', 1, '$.checklist[1].answered_at', '2026-10-16 03:11:00.000000',
         '$.checklist[2].answer_code', 'YES', '$.checklist[2].answered_by', 1, '$.checklist[2].answered_at', '2026-10-16 03:11:00.000000',
         '$.measurements[0].result_status', 'RECORDED', '$.measurements[0].measured_value', 1000.125,
         '$.measurements[0].recorded_by', 1, '$.measurements[0].recorded_at', '2026-10-16 03:11:00.000000')
 WHERE data->>'$._id' = '930';
SELECT answer_code, COUNT(*) AS n FROM checklist_result WHERE card_id = 930 GROUP BY answer_code;
SELECT measurement_result_id, result_status, measured_value FROM measurement_result WHERE card_id = 930 ORDER BY measurement_result_id;

SELECT 'P2 close card 930 through the document. BEFORE and AFTER lock: success (CLOSED, PASS, open_unit_key NULL)' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.card_status', 'CLOSED', '$.disposition', 'PASS', '$.closed_by', 3, '$.closed_at', '2026-10-16 03:12:00.000000')
 WHERE data->>'$._id' = '930';
SELECT card_status, disposition, open_unit_key FROM inspection_card WHERE card_id = 930;

SELECT 'P3 change a checklist answer of the now CLOSED card 930. BEFORE lock: success. AFTER lock: ERROR 50022' AS test_step;
UPDATE inspection_card_edit_dv
   SET data = JSON_SET(data, '$.checklist[0].answer_code', 'NO')
 WHERE data->>'$._id' = '930';
SELECT answer_code, COUNT(*) AS n FROM checklist_result WHERE card_id = 930 GROUP BY answer_code;
ROLLBACK;

SELECT 'FINAL baseline check. EXPECT the same cards, counts and etags as BASELINE and no card 930' AS test_step;
SELECT card_id, card_status, disposition, opened_by FROM inspection_card ORDER BY card_id;
SELECT (SELECT COUNT(*) FROM measurement_result) AS measurements,
       (SELECT COUNT(*) FROM checklist_result)   AS checklist,
       (SELECT COUNT(*) FROM quality_finding)    AS findings,
       (SELECT COUNT(*) FROM attachment_metadata) AS attachments,
       (SELECT COUNT(*) FROM inspection_card WHERE card_id = 930) AS test_cards_left;
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS edit_view_etag
FROM inspection_card_edit_dv ORDER BY CAST(data->>'$._id' AS UNSIGNED);
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS read_view_etag
FROM inspection_card_dv ORDER BY CAST(data->>'$._id' AS UNSIGNED);
