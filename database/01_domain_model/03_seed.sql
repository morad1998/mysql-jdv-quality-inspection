-- =====================================================================
-- D1 / Step 12E-1: deterministic seed data (generic demo values only)
-- Target : MySQL Community 9.7.2, database quality_inspection
-- Run as : quality_app, AFTER 01_schema.sql and 02_rules_triggers.sql
-- Basis  : D1 Design Pack v2 (Q1: manually seeded work orders; N1: demo roles)
-- Notes  : Fixed ids so every run gives the same result. No company, tenant or
--          real person identifiers. Cards are NOT seeded; 04_tests.sql opens them.
--          Definitions must exist before a card opens, because opening a card
--          creates one PENDING result row per definition (N2).
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

INSERT INTO app_user (user_id, username, display_name, role_code, is_active) VALUES
    (1, 'inspector1',  'Demo Inspector One', 'INSPECTOR',  1),
    (2, 'inspector2',  'Demo Inspector Two', 'INSPECTOR',  1),
    (3, 'supervisor1', 'Demo Supervisor',    'SUPERVISOR', 1);

INSERT INTO work_order (work_order_id, work_order_number, product_model, planned_quantity) VALUES
    (1, 'WO-DEMO-1001', 'Demo Model A', 50),
    (2, 'WO-DEMO-1002', 'Demo Model B', 20);

INSERT INTO production_unit (unit_id, work_order_id, unit_serial) VALUES
    (1, 1, 'SN-DEMO-0001'),
    (2, 1, 'SN-DEMO-0002'),
    (3, 2, 'SN-DEMO-0003');

INSERT INTO inspection_section (section_id, section_code, section_name, sort_order) VALUES
    (1, 'SEC-VISUAL', 'Visual inspection',  1),
    (2, 'SEC-DIM',    'Dimensional checks', 2);

INSERT INTO measurement_definition
    (measurement_definition_id, section_id, checkpoint_code, description, unit_of_measure, min_value, max_value) VALUES
    (1, 2, 'DIM-LEN', 'Overall length', 'mm', 995.000, 1005.000),
    (2, 2, 'DIM-WID', 'Overall width',  'mm', 495.000,  505.000);

INSERT INTO checklist_definition (checklist_definition_id, section_id, checkpoint_code, description) VALUES
    (1, 1, 'VIS-LABEL',   'Label present and legible'),
    (2, 1, 'VIS-SURFACE', 'Surface free of damage'),
    (3, 2, 'DIM-MARK',    'Reference marks visible');

SELECT 'app_user' AS table_name, COUNT(*) AS row_count FROM app_user
UNION ALL SELECT 'work_order',             COUNT(*) FROM work_order
UNION ALL SELECT 'production_unit',        COUNT(*) FROM production_unit
UNION ALL SELECT 'inspection_section',     COUNT(*) FROM inspection_section
UNION ALL SELECT 'measurement_definition', COUNT(*) FROM measurement_definition
UNION ALL SELECT 'checklist_definition',   COUNT(*) FROM checklist_definition
UNION ALL SELECT 'inspection_card',        COUNT(*) FROM inspection_card;
-- Expected: 3, 2, 3, 2, 2, 3 and 0 cards.
