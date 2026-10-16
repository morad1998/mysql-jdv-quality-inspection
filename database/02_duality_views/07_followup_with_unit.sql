-- =====================================================================
-- D2 / Step 2 follow-up: refused writes to the nested part, and does the ETag cover it?
-- Run as : quality_app, with the mysql client option --force
-- Safety : every change runs inside a transaction that is rolled back; the script
--          checks the state afterwards. Nothing is committed.
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

SELECT 'S1 baseline. Record the etag and the unit serial' AS test_step;
SELECT data->>'$._metadata.etag' AS card1_etag, data->>'$.unit.unit_serial' AS unit_serial_in_document
FROM inspection_card_dv WHERE data->>'$._id' = '1';
SELECT unit_id, unit_serial FROM production_unit WHERE unit_id = 1;

SELECT 'S2 REAL change to the nested unit through the read-only view -> EXPECT an error (record its number)' AS test_step;
START TRANSACTION;
UPDATE inspection_card_dv
   SET data = JSON_SET(data, '$.unit.unit_serial', 'SN-DEMO-CHANGED')
 WHERE data->>'$._id' = '1';
SELECT unit_id, unit_serial AS unit_serial_inside_transaction FROM production_unit WHERE unit_id = 1;
ROLLBACK;

SELECT 'S3 after the rollback. EXPECT the baseline values from S1' AS test_step;
SELECT unit_id, unit_serial FROM production_unit WHERE unit_id = 1;
SELECT data->>'$._metadata.etag' AS card1_etag_after FROM inspection_card_dv WHERE data->>'$._id' = '1';

SELECT 'S4 does the card ETag change when only the nested unit row changes? (direct table update, rolled back)' AS test_step;
START TRANSACTION;
UPDATE production_unit SET unit_serial = 'SN-DEMO-0001-X' WHERE unit_id = 1;
SELECT data->>'$._metadata.etag' AS card1_etag_with_changed_unit, data->>'$.unit.unit_serial' AS unit_serial_in_document
FROM inspection_card_dv WHERE data->>'$._id' = '1';
ROLLBACK;

SELECT 'S5 after the rollback. EXPECT the original serial and the baseline etag' AS test_step;
SELECT unit_serial FROM production_unit WHERE unit_id = 1;
SELECT data->>'$._metadata.etag' AS card1_etag_final FROM inspection_card_dv WHERE data->>'$._id' = '1';
-- S4 result is an observation, not a pass/fail: record whether the etag differs from S1.
