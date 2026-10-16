-- =====================================================================
-- D2 / Step 4: add the checklist results as the SECOND nested array (still read-only)
-- Target : MySQL Community 9.7.2, database quality_inspection
-- Run as : quality_app
-- Basis  : D1.9 plan: one nested collection at a time, then compare with the tables.
-- Pattern: same JSON_ARRAYAGG pattern as the measurements array. This step tests whether
--          two independent arrays can live in one document.
-- Scope  : array elements carry the checklist_result columns only; the definition
--          (description) is not included yet.
-- Warning: this script DROPS inspection_card_dv and recreates it. If the CREATE fails,
--          the step 3 view is gone; run 08_inspection_card_dv_with_measurements.sql to bring it back.
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

DROP VIEW IF EXISTS inspection_card_dv;

CREATE JSON RELATIONAL DUALITY VIEW inspection_card_dv AS
SELECT JSON_DUALITY_OBJECT(
    '_id': card_id,
    'card_status': card_status,
    'disposition': disposition,
    'opened_by': opened_by,
    'opened_at': opened_at,
    'closed_by': closed_by,
    'closed_at': closed_at,
    'unit': (
        SELECT JSON_DUALITY_OBJECT(
            'unit_id': unit_id,
            'unit_serial': unit_serial,
            'work_order_id': work_order_id
        )
        FROM production_unit
        WHERE production_unit.unit_id = inspection_card.unit_id
    ),
    'measurements': (
        SELECT JSON_ARRAYAGG(
            JSON_DUALITY_OBJECT(
                'measurement_result_id': measurement_result_id,
                'measurement_definition_id': measurement_definition_id,
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
                'checklist_result_id': checklist_result_id,
                'checklist_definition_id': checklist_definition_id,
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
-- Expected: inspection_card_dv, data, inspection_card, 0, 0, 0, 1, valid
