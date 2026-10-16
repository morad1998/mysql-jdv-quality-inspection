-- =====================================================================
-- AI data boundary, step 1: three READ-ONLY Duality Views cut for the AI assistant
-- Target : MySQL Community 9.7.2, database quality_inspection
-- Run as : quality_app
-- Design : separate from the application views. No WITH clause, so nothing is writable.
--   agent_card_dv       one document per inspection card (explain a card)
--   agent_work_order_dv one document per work order: units, each with its cards (report a work order)
--   agent_checkpoint_dv one document per section: the checkpoint definitions, tolerances included
-- Left out ON PURPOSE: opened_by, closed_by, recorded_by, answered_by, raised_by (people),
--   attachments (file names and storage_key), open_unit_key, and every write path.
-- Untrusted text: finding.description is typed by users. It appears verbatim; the application must wrap it as data.
-- NEW and untested before this script: an array INSIDE an array element (units -> cards) in agent_work_order_dv.
--   If that CREATE fails, send the error text; the fallback is in the chat message, not here.
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

DROP VIEW IF EXISTS agent_card_dv;
DROP VIEW IF EXISTS agent_work_order_dv;
DROP VIEW IF EXISTS agent_checkpoint_dv;

CREATE JSON RELATIONAL DUALITY VIEW agent_checkpoint_dv AS
SELECT JSON_DUALITY_OBJECT(
    '_id': section_id,
    'section_code': section_code,
    'section_name': section_name,
    'sort_order': sort_order,
    'measurement_checkpoints': (
        SELECT JSON_ARRAYAGG(
            JSON_DUALITY_OBJECT(
                'measurement_definition_id': measurement_definition_id,
                'checkpoint_code': checkpoint_code,
                'description': description,
                'unit_of_measure': unit_of_measure,
                'min_value': min_value,
                'max_value': max_value
            )
        )
        FROM measurement_definition
        WHERE measurement_definition.section_id = inspection_section.section_id
    ),
    'checklist_checkpoints': (
        SELECT JSON_ARRAYAGG(
            JSON_DUALITY_OBJECT(
                'checklist_definition_id': checklist_definition_id,
                'checkpoint_code': checkpoint_code,
                'description': description
            )
        )
        FROM checklist_definition
        WHERE checklist_definition.section_id = inspection_section.section_id
    )
)
FROM inspection_section;

CREATE JSON RELATIONAL DUALITY VIEW agent_card_dv AS
SELECT JSON_DUALITY_OBJECT(
    '_id': card_id,
    'card_status': card_status,
    'disposition': disposition,
    'opened_at': opened_at,
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
                'measured_value': measured_value
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
                'answer_code': answer_code
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
                'raised_at': raised_at,
                'resolved_at': resolved_at
            )
        )
        FROM quality_finding
        WHERE quality_finding.card_id = inspection_card.card_id
    )
)
FROM inspection_card;

CREATE JSON RELATIONAL DUALITY VIEW agent_work_order_dv AS
SELECT JSON_DUALITY_OBJECT(
    '_id': work_order_id,
    'work_order_number': work_order_number,
    'product_model': product_model,
    'planned_quantity': planned_quantity,
    'created_at': created_at,
    'units': (
        SELECT JSON_ARRAYAGG(
            JSON_DUALITY_OBJECT(
                'unit_id': unit_id,
                'unit_serial': unit_serial,
                'cards': (
                    SELECT JSON_ARRAYAGG(
                        JSON_DUALITY_OBJECT(
                            'card_id': card_id,
                            'card_status': card_status,
                            'disposition': disposition,
                            'opened_at': opened_at,
                            'closed_at': closed_at
                        )
                    )
                    FROM inspection_card
                    WHERE inspection_card.unit_id = production_unit.unit_id
                )
            )
        )
        FROM production_unit
        WHERE production_unit.work_order_id = work_order.work_order_id
    )
)
FROM work_order;

SELECT TABLE_NAME, ROOT_TABLE_NAME, ALLOW_INSERT, ALLOW_UPDATE, ALLOW_DELETE, READ_ONLY, STATUS
FROM INFORMATION_SCHEMA.JSON_DUALITY_VIEWS
WHERE TABLE_SCHEMA = 'quality_inspection' AND TABLE_NAME LIKE 'agent\_%'
ORDER BY TABLE_NAME;
-- Expected: agent_card_dv, agent_checkpoint_dv, agent_work_order_dv; all READ_ONLY 1, insert/update/delete 0, valid
