-- Removes ONLY the AI demo data (work orders 10 and 11, their units and cards). Run as quality_app.
USE quality_inspection;
DELETE FROM quality_finding   WHERE card_id BETWEEN 1001 AND 1006;
DELETE FROM checklist_result  WHERE card_id BETWEEN 1001 AND 1006;
DELETE FROM measurement_result WHERE card_id BETWEEN 1001 AND 1006;
DELETE FROM inspection_card   WHERE card_id BETWEEN 1001 AND 1006;
DELETE FROM production_unit   WHERE unit_id IN (101, 102, 103, 104, 111, 112, 113);
DELETE FROM work_order        WHERE work_order_id IN (10, 11);
