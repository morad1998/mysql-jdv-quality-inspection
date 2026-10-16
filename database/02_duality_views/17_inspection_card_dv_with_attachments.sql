-- =====================================================================
-- D2 / Step 6: add the attachment metadata as the FOURTH nested array (still read-only)
-- Target : MySQL Community 9.7.2, database quality_inspection
-- Run as : quality_app
-- Basis  : D1.9 plan: one nested collection at a time, then compare with the tables.
-- Scope  : card-level array. finding_id is a plain field (null when the file belongs to the
--          card and not to a finding). Attachments nested INSIDE the findings array are a
--          separate, later experiment and are not part of this step.
-- Note   : storage_key is included here so the document matches the table. It is an object
--          location, not user content; the agent-facing view (D-015) will not need it.
-- Warning: this script DROPS inspection_card_dv and recreates it. If the CREATE fails,
--          the step 5 view is gone; run 14_inspection_card_dv_with_findings.sql to bring it back.
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
    ),
    'findings': (
        SELECT JSON_ARRAYAGG(
            JSON_DUALITY_OBJECT(
                'finding_id': finding_id,
                'severity': severity,
                'finding_status': finding_status,
                'description': description,
                'raised_by': raised_by,
                'raised_at': raised_at,
                'resolved_at': resolved_at
            )
        )
        FROM quality_finding
        WHERE quality_finding.card_id = inspection_card.card_id
    ),
    'attachments': (
        SELECT JSON_ARRAYAGG(
            JSON_DUALITY_OBJECT(
                'attachment_id': attachment_id,
                'finding_id': finding_id,
                'file_name': file_name,
                'mime_type': mime_type,
                'size_bytes': size_bytes,
                'storage_key': storage_key,
                'uploaded_by': uploaded_by,
                'uploaded_at': uploaded_at
            )
        )
        FROM attachment_metadata
        WHERE attachment_metadata.card_id = inspection_card.card_id
    )
)
FROM inspection_card;

SELECT TABLE_NAME, JSON_COLUMN_NAME, ROOT_TABLE_NAME,
       ALLOW_INSERT, ALLOW_UPDATE, ALLOW_DELETE, READ_ONLY, STATUS
FROM INFORMATION_SCHEMA.JSON_DUALITY_VIEWS
WHERE TABLE_SCHEMA = 'quality_inspection'
ORDER BY TABLE_NAME;
-- Expected: inspection_card_dv, data, inspection_card, 0, 0, 0, 1, valid
