-- =====================================================================
-- D2 / Step 4 probes for B-016: which path does ERROR 6497 name?
-- Run as : quality_app, with the mysql client option --force
-- Safety : every probe runs inside its own transaction that is rolled back, and the script
--          checks the baseline afterwards. Nothing is committed.
-- How to read the output: the ERROR line carries the line number of the failing statement
--          ("at line N"). Match N to the probe in the table that the chat message lists.
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

SELECT 'BASELINE etags (card 1 and card 2) and row counts' AS test_step;
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS etag
FROM inspection_card_dv ORDER BY CAST(data->>'$._id' AS UNSIGNED);
SELECT (SELECT COUNT(*) FROM inspection_card) AS cards,
       (SELECT COUNT(*) FROM measurement_result) AS measurements,
       (SELECT COUNT(*) FROM checklist_result) AS checklist;

SELECT 'P1 root field opened_by (card 1)' AS test_step;
START TRANSACTION;
UPDATE inspection_card_dv SET data = JSON_SET(data, '$.opened_by', 2) WHERE data->>'$._id' = '1';
ROLLBACK;

SELECT 'P2 nested object field unit.unit_serial (card 1)' AS test_step;
START TRANSACTION;
UPDATE inspection_card_dv SET data = JSON_SET(data, '$.unit.unit_serial', 'SN-DEMO-CHANGED') WHERE data->>'$._id' = '1';
ROLLBACK;

SELECT 'P3 measurements element result_status (card 1)' AS test_step;
START TRANSACTION;
UPDATE inspection_card_dv SET data = JSON_SET(data, '$.measurements[0].result_status', 'CHANGED_THROUGH_VIEW') WHERE data->>'$._id' = '1';
ROLLBACK;

SELECT 'P4 measurements element measured_value (card 1)' AS test_step;
START TRANSACTION;
UPDATE inspection_card_dv SET data = JSON_SET(data, '$.measurements[0].measured_value', 1000.5) WHERE data->>'$._id' = '1';
ROLLBACK;

SELECT 'P5 checklist element answer_code (card 1)' AS test_step;
START TRANSACTION;
UPDATE inspection_card_dv SET data = JSON_SET(data, '$.checklist[0].answer_code', 'NO') WHERE data->>'$._id' = '1';
ROLLBACK;

SELECT 'P6 two changes in one statement: root opened_by and checklist element answer_code (card 1)' AS test_step;
START TRANSACTION;
UPDATE inspection_card_dv SET data = JSON_SET(data, '$.opened_by', 2, '$.checklist[0].answer_code', 'NO') WHERE data->>'$._id' = '1';
ROLLBACK;

SELECT 'P7 repeat of P3 (is the error deterministic?)' AS test_step;
START TRANSACTION;
UPDATE inspection_card_dv SET data = JSON_SET(data, '$.measurements[0].result_status', 'CHANGED_THROUGH_VIEW') WHERE data->>'$._id' = '1';
ROLLBACK;

SELECT 'P8 measurements element result_status on card 2 (a different card)' AS test_step;
START TRANSACTION;
UPDATE inspection_card_dv SET data = JSON_SET(data, '$.measurements[0].result_status', 'CHANGED_THROUGH_VIEW') WHERE data->>'$._id' = '2';
ROLLBACK;

SELECT 'P9 second measurements element, second element index (card 1, index 1)' AS test_step;
START TRANSACTION;
UPDATE inspection_card_dv SET data = JSON_SET(data, '$.measurements[1].result_status', 'CHANGED_THROUGH_VIEW') WHERE data->>'$._id' = '1';
ROLLBACK;

SELECT 'FINAL baseline check. EXPECT the same etags and the same counts as BASELINE' AS test_step;
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS etag
FROM inspection_card_dv ORDER BY CAST(data->>'$._id' AS UNSIGNED);
SELECT (SELECT COUNT(*) FROM inspection_card) AS cards,
       (SELECT COUNT(*) FROM measurement_result) AS measurements,
       (SELECT COUNT(*) FROM checklist_result) AS checklist;
SELECT card_id, opened_by, card_status FROM inspection_card ORDER BY card_id;
SELECT checklist_result_id, answer_code FROM checklist_result WHERE card_id = 1 ORDER BY checklist_result_id;
