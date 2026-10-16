-- =====================================================================
-- AI data boundary, step 5a: what the restricted account may read. Run as ROOT, after the account exists.
-- The account itself is created by scripts/create-ai-reader.ps1 (the password is generated and never printed).
-- SELECT on nine objects and NOTHING else: no table, no application view, no edit view, no other database,
-- no INSERT, UPDATE, DELETE, no DDL.
-- =====================================================================
GRANT SELECT ON quality_inspection.agent_card_dv                       TO 'ai_reader'@'%';
GRANT SELECT ON quality_inspection.agent_work_order_dv                 TO 'ai_reader'@'%';
GRANT SELECT ON quality_inspection.agent_checkpoint_dv                 TO 'ai_reader'@'%';
GRANT SELECT ON quality_inspection.agent_stat_cards_by_status          TO 'ai_reader'@'%';
GRANT SELECT ON quality_inspection.agent_stat_final_cards_by_disposition TO 'ai_reader'@'%';
GRANT SELECT ON quality_inspection.agent_stat_findings                 TO 'ai_reader'@'%';
GRANT SELECT ON quality_inspection.agent_stat_work_order_progress      TO 'ai_reader'@'%';
GRANT SELECT ON quality_inspection.agent_stat_measurement_tolerance    TO 'ai_reader'@'%';
GRANT SELECT ON quality_inspection.agent_stat_cycle_time               TO 'ai_reader'@'%';
SHOW GRANTS FOR 'ai_reader'@'%';
