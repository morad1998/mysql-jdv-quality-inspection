-- =====================================================================
-- D2 / Step 3 follow-up: refused writes into the array, ETag coverage, NULL and empty cases
-- Run as : quality_app, with the mysql client option --force
-- Safety : every change runs inside a transaction that is rolled back; the script checks
--          the state afterwards. Nothing is committed.
-- Side effect: the card insert in M4 uses the next AUTO_INCREMENT ids for inspection_card
--          and measurement_result; a rollback does not reset those counters.
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

SELECT 'M1 baseline: card 1 etag and the RECORDED result' AS test_step;
SELECT data->>'$._metadata.etag' AS card1_etag FROM inspection_card_dv WHERE data->>'$._id' = '1';
SELECT measurement_result_id, result_status, measured_value
FROM measurement_result WHERE card_id = 1 AND measurement_definition_id = 1;

SELECT 'M2 REAL change to an array element through the read-only view -> EXPECT an error (record its number and path)' AS test_step;
START TRANSACTION;
UPDATE inspection_card_dv
   SET data = JSON_SET(data, '$.measurements[0].result_status', 'CHANGED_THROUGH_VIEW')
 WHERE data->>'$._id' = '1';
SELECT result_status, COUNT(*) AS n FROM measurement_result WHERE card_id = 1 GROUP BY result_status;
ROLLBACK;

SELECT 'M3 after the rollback. EXPECT baseline: etag as in M1, one NOT_APPLICABLE and one RECORDED' AS test_step;
SELECT data->>'$._metadata.etag' AS card1_etag_after FROM inspection_card_dv WHERE data->>'$._id' = '1';
SELECT result_status, COUNT(*) AS n FROM measurement_result WHERE card_id = 1 GROUP BY result_status;

SELECT 'M4 does the card etag change when only one measurement row changes? (direct table update, rolled back)' AS test_step;
START TRANSACTION;
UPDATE measurement_result SET measured_value = 1000.500
 WHERE card_id = 1 AND measurement_definition_id = 1;
SELECT data->>'$._metadata.etag' AS card1_etag_with_changed_result FROM inspection_card_dv WHERE data->>'$._id' = '1';
ROLLBACK;

SELECT 'M5 after the rollback. EXPECT the etag from M1 and value 1000.250' AS test_step;
SELECT data->>'$._metadata.etag' AS card1_etag_final FROM inspection_card_dv WHERE data->>'$._id' = '1';
SELECT measured_value FROM measurement_result WHERE card_id = 1 AND measurement_definition_id = 1;

SELECT 'M6 NULL elements and the EMPTY array, inside a transaction that is rolled back' AS test_step;
START TRANSACTION;
INSERT INTO inspection_card (unit_id, opened_by) VALUES (3, 1);
SELECT 'M6a open card on unit 3: EXPECT two PENDING elements with null values' AS test_step;
SELECT JSON_PRETTY(data->'$.measurements') AS measurements_of_new_card
FROM inspection_card_dv WHERE data->>'$.unit.unit_serial' = 'SN-DEMO-0003';
DELETE FROM measurement_result
 WHERE card_id = (SELECT card_id FROM inspection_card WHERE unit_id = 3);
SELECT 'M6b same card with no measurement rows: EXPECT null or [] (record which)' AS test_step;
SELECT JSON_TYPE(data->'$.measurements') AS array_node_type,
       data->>'$.measurements' AS array_as_text
FROM inspection_card_dv WHERE data->>'$.unit.unit_serial' = 'SN-DEMO-0003';
ROLLBACK;

SELECT 'M7 after the rollback. EXPECT 0 cards on unit 3, 2 cards in total, 4 measurement rows' AS test_step;
SELECT (SELECT COUNT(*) FROM inspection_card WHERE unit_id = 3) AS cards_for_unit_3,
       (SELECT COUNT(*) FROM inspection_card) AS cards_total,
       (SELECT COUNT(*) FROM measurement_result) AS measurement_rows;
