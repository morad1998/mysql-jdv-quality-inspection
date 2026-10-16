-- =====================================================================
-- AI data boundary, step 5b: prove what the restricted account CANNOT do. Run AS ai_reader with --force.
-- Expected: the first two statements succeed; every later statement fails with ERROR 1142 (command denied).
-- If a statement SUCCEEDS where an error is expected, the boundary is broken: stop and send the output.
-- Plain ASCII only.
-- =====================================================================
SELECT CURRENT_USER() AS connected_as;

SELECT 'A1 allowed: read an agent document' AS test_step;
SELECT COUNT(*) AS agent_card_documents FROM quality_inspection.agent_card_dv;
SELECT 'A2 allowed: read an approved statistic' AS test_step;
SELECT COUNT(*) AS status_rows FROM quality_inspection.agent_stat_cards_by_status;

SELECT 'D1 denied: read a base table' AS test_step;
SELECT * FROM quality_inspection.inspection_card LIMIT 1;
SELECT 'D2 denied: read the application read view' AS test_step;
SELECT * FROM quality_inspection.inspection_card_dv LIMIT 1;
SELECT 'D3 denied: read the application edit view' AS test_step;
SELECT * FROM quality_inspection.inspection_card_edit_dv LIMIT 1;
SELECT 'D4 denied: read the users table' AS test_step;
SELECT * FROM quality_inspection.app_user LIMIT 1;
SELECT 'D5 denied: read another database' AS test_step;
SELECT * FROM jdv_spike.customers LIMIT 1;
SELECT 'D6 denied: update through an agent view' AS test_step;
UPDATE quality_inspection.agent_card_dv SET data = JSON_SET(data, '$.card_status', 'OPEN') WHERE data->>'$._id' = '1001';
SELECT 'D7 denied: insert into a table' AS test_step;
INSERT INTO quality_inspection.audit_event (actor_id, event_type, target_type, target_id) VALUES (1, 'AI_QUERY', 'inspection_card', 1);
SELECT 'D8 denied: delete from a table' AS test_step;
DELETE FROM quality_inspection.quality_finding WHERE finding_id = 1004;
SELECT 'D9 denied: create an object' AS test_step;
CREATE TABLE quality_inspection.ai_should_not_exist (x INT);

SELECT 'FINAL: the data was not changed. EXPECT finding 1004 present and card 1001 still CLOSED' AS test_step;
SELECT COUNT(*) AS finding_1004_present FROM quality_inspection.agent_card_dv WHERE data->>'$._id' = '1005' AND data->>'$.findings[0].finding_id' = '1004';
SELECT data->>'$.card_status' AS card_1001_status FROM quality_inspection.agent_card_dv WHERE data->>'$._id' = '1001';
