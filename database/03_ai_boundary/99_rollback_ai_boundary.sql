-- Removes the AI views and statistics views. Run as quality_app. The ai_reader account is removed by DROP USER (root).
USE quality_inspection;
DROP VIEW IF EXISTS agent_card_dv;
DROP VIEW IF EXISTS agent_work_order_dv;
DROP VIEW IF EXISTS agent_checkpoint_dv;
DROP VIEW IF EXISTS agent_stat_cards_by_status;
DROP VIEW IF EXISTS agent_stat_final_cards_by_disposition;
DROP VIEW IF EXISTS agent_stat_findings;
DROP VIEW IF EXISTS agent_stat_work_order_progress;
DROP VIEW IF EXISTS agent_stat_measurement_tolerance;
DROP VIEW IF EXISTS agent_stat_cycle_time;
