-- =====================================================================
-- D2 / Step 7b: the edit view gains two child arrays, both writable for UPDATE only
-- Target : MySQL Community 9.7.2, database quality_inspection
-- Run as : quality_app
-- Design : same rule as step 7a: the fields an object projects are the fields a document can write.
--          measurement_definition_id and checklist_definition_id are NOT projected, so a document
--          cannot re-point a result at another definition. The read view carries them for context.
--          Tag WITH (UPDATE) on every object: no INSERT and no DELETE, so documents cannot add or
--          remove rows.
-- Warning: this script DROPS inspection_card_edit_dv and recreates it. If the CREATE fails, send the
--          error text, then run 20_inspection_card_edit_dv.sql to bring the step 7a view back.
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

DROP VIEW IF EXISTS inspection_card_edit_dv;

CREATE JSON RELATIONAL DUALITY VIEW inspection_card_edit_dv AS
SELECT JSON_DUALITY_OBJECT(
    WITH (UPDATE)
    '_id': card_id,
    'card_status': card_status,
    'disposition': disposition,
    'closed_by': closed_by,
    'closed_at': closed_at,
    'measurements': (
        SELECT JSON_ARRAYAGG(
            JSON_DUALITY_OBJECT(
                WITH (UPDATE)
                'measurement_result_id': measurement_result_id,
                'result_status': result_status,
                'measured_value': measured_value,
                'recorded_by': recorded_by,
                'recorded_at': recorded_at
            )
        )
        FROM measurement_result
        WHERE measurement_result.card_id = inspection_card.card_id
    ),
    'checklist': (
        SELECT JSON_ARRAYAGG(
            JSON_DUALITY_OBJECT(
                WITH (UPDATE)
                'checklist_result_id': checklist_result_id,
                'answer_code': answer_code,
                'answered_by': answered_by,
                'answered_at': answered_at
            )
        )
        FROM checklist_result
        WHERE checklist_result.card_id = inspection_card.card_id
    )
)
FROM inspection_card;

SELECT TABLE_NAME, JSON_COLUMN_NAME, ROOT_TABLE_NAME,
       ALLOW_INSERT, ALLOW_UPDATE, ALLOW_DELETE, READ_ONLY, STATUS
FROM INFORMATION_SCHEMA.JSON_DUALITY_VIEWS
WHERE TABLE_SCHEMA = 'quality_inspection'
ORDER BY TABLE_NAME;
-- Expected: inspection_card_dv (read-only, valid) and
--           inspection_card_edit_dv, data, inspection_card, 0, 1, 0, 0, valid
