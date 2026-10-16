-- =====================================================================
-- D2 / Step 1 follow-up: settle the unexpected N1 result and test the NULL path
-- Run as : quality_app, with the mysql client option --force
-- Safety : every change runs inside a transaction that is rolled back, and the
--          script checks the rolled-back state. Nothing is committed.
-- Side effect: F5 uses the next AUTO_INCREMENT id for inspection_card; a rollback does
--          not reset that counter, so the next automatic card id will be one higher.
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

SELECT 'F1 does the earlier WHERE clause match a document? EXPECT 1' AS test_step;
SELECT COUNT(*) AS matching_documents FROM inspection_card_dv WHERE data->>'$._id' = '1';

SELECT 'F2 baseline before the test. EXPECT opened_by 1 and etag d2a4080cedfed7c8845bd31c75c22f35' AS test_step;
SELECT card_id, opened_by FROM inspection_card WHERE card_id = 1;
SELECT data->>'$._metadata.etag' AS card1_etag FROM inspection_card_dv WHERE data->>'$._id' = '1';

SELECT 'F3 REAL change through the read-only view, inside a transaction -> EXPECT an error (record its number)' AS test_step;
START TRANSACTION;
UPDATE inspection_card_dv
   SET data = JSON_SET(data, '$.opened_by', 2)
 WHERE data->>'$._id' = '1';
SELECT ROW_COUNT() AS rows_changed_by_update_ignore_if_the_update_errored;
SELECT card_id, opened_by AS opened_by_inside_transaction FROM inspection_card WHERE card_id = 1;
ROLLBACK;

SELECT 'F4 after the rollback. EXPECT opened_by 1 and the same etag as F2' AS test_step;
SELECT card_id, opened_by FROM inspection_card WHERE card_id = 1;
SELECT data->>'$._metadata.etag' AS card1_etag_after FROM inspection_card_dv WHERE data->>'$._id' = '1';

SELECT 'F5 document of an OPEN card shows NULL fields; inside a transaction that is rolled back' AS test_step;
START TRANSACTION;
INSERT INTO inspection_card (unit_id, opened_by) VALUES (3, 1);
SELECT JSON_PRETTY(data) AS doc FROM inspection_card_dv WHERE data->>'$.unit_id' = '3';
SELECT COUNT(*) AS cards_compared,
       SUM( (d.data->>'$.card_status' = c.card_status)
        AND (NULLIF(d.data->>'$.disposition','null') <=> c.disposition)
        AND (CAST(d.data->>'$.unit_id' AS UNSIGNED) = c.unit_id)
        AND (CAST(d.data->>'$.opened_by' AS UNSIGNED) = c.opened_by)
        AND (CAST(NULLIF(d.data->>'$.closed_by','null') AS UNSIGNED) <=> c.closed_by) ) AS cards_fully_matching
FROM inspection_card c
JOIN inspection_card_dv d
  ON CAST(d.data->>'$._id' AS UNSIGNED) = c.card_id;
ROLLBACK;

SELECT 'F5 after the rollback. EXPECT 0 cards on unit 3 and 2 cards in total' AS test_step;
SELECT (SELECT COUNT(*) FROM inspection_card WHERE unit_id = 3) AS cards_for_unit_3,
       (SELECT COUNT(*) FROM inspection_card) AS cards_total;
