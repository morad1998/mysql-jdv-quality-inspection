-- =====================================================================
-- D2 / Step 1 negative test: the view must refuse writes
-- NOTE (weak test): this update sets card_status to the value it already has. MySQL accepted it
-- silently, so this script does NOT prove the view is read-only. The real proof is F3 in
-- 04_followup_checks.sql: a real change is refused with ERROR 6497 (see B-015).
-- Run as : quality_app, with the mysql client option --force
-- The update sets the card_status to the value it already has, so even if the view
-- were unexpectedly writable, no data would change.
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

SELECT 'N1 update through the read-only view -> EXPECT an error (record its number)' AS test_step;
UPDATE inspection_card_dv
   SET data = JSON_SET(data, '$.card_status', data->>'$.card_status')
 WHERE data->>'$._id' = '1';

SELECT 'N1 state check: card 1 unchanged' AS test_step;
SELECT card_id, card_status, disposition FROM inspection_card WHERE card_id = 1;
-- Expected: 1, CLOSED, PASS
