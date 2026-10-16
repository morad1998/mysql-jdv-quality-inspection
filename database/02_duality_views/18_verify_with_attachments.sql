-- =====================================================================
-- D2 / Step 6 verification: all four arrays and the unit must agree with the tables
-- Run as : quality_app, with the mysql client option --force
-- Parts AA1 to AA9 are read-only. Parts T1 to T3 change data inside transactions that are
-- rolled back and then check the baseline (T1 uses the next AUTO_INCREMENT id of
-- attachment_metadata).
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

SELECT 'AA1 document count equals table row count' AS check_name;
SELECT (SELECT COUNT(*) FROM inspection_card_dv) AS documents,
       (SELECT COUNT(*) FROM inspection_card)    AS table_rows;
-- Expected: 2 and 2

SELECT 'AA2 attachments part of each document' AS check_name;
SELECT data->>'$._id' AS card_id, JSON_PRETTY(data->'$.attachments') AS attachments
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
-- Expected: card 1 has two elements (attachment 1 with finding_id 1, attachment 2 with finding_id null);
--           card 2 shows null because it has no attachments.

SELECT 'AA3 relational rows for comparison' AS check_name;
SELECT attachment_id, card_id, finding_id, file_name, mime_type, size_bytes, storage_key, uploaded_by
FROM attachment_metadata
ORDER BY attachment_id;
-- Expected: 2 rows, both on card 1; attachment 2 has finding_id NULL

SELECT 'AA4 type of each array node per card' AS check_name;
SELECT data->>'$._id' AS card_id,
       JSON_TYPE(data->'$.measurements') AS measurements_type,
       JSON_TYPE(data->'$.checklist')    AS checklist_type,
       JSON_TYPE(data->'$.findings')     AS findings_type,
       JSON_TYPE(data->'$.attachments')  AS attachments_type
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
-- Expected: card 1 ARRAY x4; card 2 ARRAY, ARRAY, NULL, NULL

SELECT 'AA5a element counts versus table rows, counting real arrays only' AS check_name;
SELECT (SELECT COUNT(*) FROM measurement_result) AS measurement_rows,
       (SELECT COUNT(*) FROM checklist_result)   AS checklist_rows,
       (SELECT COUNT(*) FROM quality_finding)    AS finding_rows,
       (SELECT COUNT(*) FROM attachment_metadata) AS attachment_rows,
       SUM(CASE WHEN JSON_TYPE(data->'$.measurements') = 'ARRAY' THEN JSON_LENGTH(data->'$.measurements') ELSE 0 END) AS measurement_elements,
       SUM(CASE WHEN JSON_TYPE(data->'$.checklist')    = 'ARRAY' THEN JSON_LENGTH(data->'$.checklist')    ELSE 0 END) AS checklist_elements,
       SUM(CASE WHEN JSON_TYPE(data->'$.findings')     = 'ARRAY' THEN JSON_LENGTH(data->'$.findings')     ELSE 0 END) AS finding_elements,
       SUM(CASE WHEN JSON_TYPE(data->'$.attachments')  = 'ARRAY' THEN JSON_LENGTH(data->'$.attachments')  ELSE 0 END) AS attachment_elements
FROM inspection_card_dv;
-- Expected: 4, 6, 1, 2 and 4, 6, 1, 2

SELECT 'AA5b attachment element-by-element agreement' AS check_name;
SELECT COUNT(*) AS elements_compared,
       SUM( (am.card_id = CAST(d.data->>'$._id' AS UNSIGNED))
        AND (am.finding_id <=> jt.finding_id)
        AND (am.file_name = jt.file_name)
        AND (am.mime_type = jt.mime_type)
        AND (am.size_bytes = jt.size_bytes)
        AND (am.storage_key = jt.storage_key)
        AND (am.uploaded_by = jt.uploaded_by) ) AS elements_fully_matching
FROM inspection_card_dv d,
     JSON_TABLE(d.data, '$.attachments[*]' COLUMNS (
         attachment_id INT          PATH '$.attachment_id',
         finding_id    INT          PATH '$.finding_id',
         file_name     VARCHAR(255) PATH '$.file_name',
         mime_type     VARCHAR(100) PATH '$.mime_type',
         size_bytes    BIGINT       PATH '$.size_bytes',
         storage_key   VARCHAR(500) PATH '$.storage_key',
         uploaded_by   INT          PATH '$.uploaded_by')) AS jt,
     attachment_metadata am
WHERE JSON_TYPE(d.data->'$.attachments') = 'ARRAY'
  AND am.attachment_id = jt.attachment_id;
-- Expected: 2 and 2

SELECT 'AA6 attachments array order as returned (observation)' AS check_name;
SELECT data->>'$._id' AS card_id, JSON_EXTRACT(data, '$.attachments[*].attachment_id') AS ids_in_document_order
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);

SELECT 'AA7 the nested unit is still present and correct' AS check_name;
SELECT COUNT(*) AS cards_compared,
       SUM( (d.data->>'$.unit.unit_serial' = u.unit_serial)
        AND (CAST(d.data->>'$.unit.unit_id' AS UNSIGNED) = c.unit_id) ) AS cards_unit_matching
FROM inspection_card c
JOIN production_unit u ON u.unit_id = c.unit_id
JOIN inspection_card_dv d ON CAST(d.data->>'$._id' AS UNSIGNED) = c.card_id;
-- Expected: 2 and 2

SELECT 'AA8 open_unit_key must not be exposed' AS check_name;
SELECT COUNT(*) AS documents_exposing_open_unit_key
FROM inspection_card_dv
WHERE JSON_CONTAINS_PATH(data, 'one', '$.open_unit_key') = 1;
-- Expected: 0

SELECT 'AA9 etag of each card in this view version' AS check_name;
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS etag
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);

SELECT 'T1 add an attachment to card 2 by direct table insert (rolled back): EXPECT card 2 array becomes ARRAY of 1 and its etag changes' AS test_step;
START TRANSACTION;
INSERT INTO attachment_metadata (card_id, file_name, mime_type, size_bytes, storage_key, uploaded_by)
VALUES (2, 'rollback_test.jpg', 'image/jpeg', 512, 'demo/card_2/rollback_test.jpg', 1);
SELECT JSON_TYPE(data->'$.attachments') AS attachments_type,
       JSON_LENGTH(data->'$.attachments') AS attachments_length,
       data->>'$._metadata.etag' AS card2_etag_with_attachment
FROM inspection_card_dv WHERE data->>'$._id' = '2';
ROLLBACK;

SELECT 'T2 REAL change to an attachments element through the read-only view -> EXPECT ERROR 6497 (record which path it names)' AS test_step;
START TRANSACTION;
UPDATE inspection_card_dv
   SET data = JSON_SET(data, '$.attachments[0].file_name', 'changed_through_view.jpg')
 WHERE data->>'$._id' = '1';
SELECT file_name FROM attachment_metadata WHERE attachment_id = 1;
ROLLBACK;

SELECT 'T3 after the rollbacks. EXPECT 2 attachment rows, file photo1.jpg, and the etags from AA9' AS test_step;
SELECT (SELECT COUNT(*) FROM attachment_metadata) AS attachment_rows,
       (SELECT file_name FROM attachment_metadata WHERE attachment_id = 1) AS attachment1_file_name;
SELECT data->>'$._id' AS card_id, data->>'$._metadata.etag' AS etag
FROM inspection_card_dv
ORDER BY CAST(data->>'$._id' AS UNSIGNED);
