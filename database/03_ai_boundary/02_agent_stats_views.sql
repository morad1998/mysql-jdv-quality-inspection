-- =====================================================================
-- AI data boundary, step 2: six plain SQL views that hold the APPROVED statistics
-- Run as : quality_app
-- These are NOT Duality Views on purpose: a statistic is an aggregate, not a document (D-015).
-- The model never calculates a figure: it receives these rows and explains them.
-- Definitions (the application repeats them next to every answer):
--   final card        card_status CLOSED or REJECTED
--   pass rate         PASS / (PASS + REJECT) among final cards (computed by the application from the disposition view)
--   active card       card_status OPEN or IN_PROGRESS
--   out of tolerance  RECORDED value below min_value or above max_value of its checkpoint definition
--   cycle time        closed_at minus opened_at in seconds, final cards only
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

DROP VIEW IF EXISTS agent_stat_cards_by_status;
DROP VIEW IF EXISTS agent_stat_final_cards_by_disposition;
DROP VIEW IF EXISTS agent_stat_findings;
DROP VIEW IF EXISTS agent_stat_work_order_progress;
DROP VIEW IF EXISTS agent_stat_measurement_tolerance;
DROP VIEW IF EXISTS agent_stat_cycle_time;

CREATE VIEW agent_stat_cards_by_status AS
SELECT card_status, COUNT(*) AS cards
FROM inspection_card
GROUP BY card_status;

CREATE VIEW agent_stat_final_cards_by_disposition AS
SELECT disposition, COUNT(*) AS cards
FROM inspection_card
WHERE card_status IN ('CLOSED', 'REJECTED')
GROUP BY disposition;

CREATE VIEW agent_stat_findings AS
SELECT severity, finding_status, COUNT(*) AS findings
FROM quality_finding
GROUP BY severity, finding_status;

CREATE VIEW agent_stat_work_order_progress AS
SELECT wo.work_order_number,
       wo.planned_quantity,
       (SELECT COUNT(*) FROM production_unit u WHERE u.work_order_id = wo.work_order_id) AS units_registered,
       (SELECT COUNT(*) FROM inspection_card c JOIN production_unit u ON u.unit_id = c.unit_id
         WHERE u.work_order_id = wo.work_order_id) AS cards_total,
       (SELECT COUNT(*) FROM inspection_card c JOIN production_unit u ON u.unit_id = c.unit_id
         WHERE u.work_order_id = wo.work_order_id AND c.card_status IN ('CLOSED', 'REJECTED')) AS cards_final,
       (SELECT COUNT(*) FROM inspection_card c JOIN production_unit u ON u.unit_id = c.unit_id
         WHERE u.work_order_id = wo.work_order_id AND c.card_status IN ('CLOSED', 'REJECTED') AND c.disposition = 'PASS') AS cards_pass,
       (SELECT COUNT(*) FROM inspection_card c JOIN production_unit u ON u.unit_id = c.unit_id
         WHERE u.work_order_id = wo.work_order_id AND c.card_status IN ('CLOSED', 'REJECTED') AND c.disposition = 'REJECT') AS cards_reject,
       (SELECT COUNT(*) FROM inspection_card c JOIN production_unit u ON u.unit_id = c.unit_id
         WHERE u.work_order_id = wo.work_order_id AND c.card_status IN ('OPEN', 'IN_PROGRESS')) AS cards_active,
       (SELECT COUNT(*) FROM quality_finding f JOIN inspection_card c ON c.card_id = f.card_id JOIN production_unit u ON u.unit_id = c.unit_id
         WHERE u.work_order_id = wo.work_order_id AND f.finding_status = 'OPEN') AS open_findings,
       (SELECT COUNT(*) FROM quality_finding f JOIN inspection_card c ON c.card_id = f.card_id JOIN production_unit u ON u.unit_id = c.unit_id
         WHERE u.work_order_id = wo.work_order_id AND f.finding_status = 'OPEN' AND f.severity = 'CRITICAL') AS open_critical_findings
FROM work_order wo;

CREATE VIEW agent_stat_measurement_tolerance AS
SELECT d.checkpoint_code,
       COUNT(*) AS recorded,
       SUM(CASE WHEN (d.min_value IS NOT NULL AND r.measured_value < d.min_value)
                  OR (d.max_value IS NOT NULL AND r.measured_value > d.max_value) THEN 1 ELSE 0 END) AS out_of_tolerance
FROM measurement_result r
JOIN measurement_definition d ON d.measurement_definition_id = r.measurement_definition_id
WHERE r.result_status = 'RECORDED'
GROUP BY d.checkpoint_code;

CREATE VIEW agent_stat_cycle_time AS
SELECT COUNT(*) AS final_cards,
       AVG(TIMESTAMPDIFF(SECOND, opened_at, closed_at)) AS avg_cycle_seconds
FROM inspection_card
WHERE card_status IN ('CLOSED', 'REJECTED') AND closed_at IS NOT NULL;

SELECT TABLE_NAME FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'quality_inspection' AND TABLE_NAME LIKE 'agent\_stat\_%'
ORDER BY TABLE_NAME;
-- Expected: 6 views
