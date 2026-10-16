-- =====================================================================
-- AI data boundary, step 4: verify the agent views and the statistics against the tables
-- Run as : quality_app (read-only script)
-- Every check prints PASS or FAIL. Expected values for the S checks assume the baseline plus 03_ai_demo_data.sql.
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

SELECT check_name, expected, actual, IF(expected <=> actual, 'PASS', 'FAIL') AS verdict
FROM (
  SELECT 'T01 agent_card_dv documents = cards' AS check_name,
         (SELECT COUNT(*) FROM inspection_card) AS expected, (SELECT COUNT(*) FROM agent_card_dv) AS actual
  UNION ALL SELECT 'T02 agent_work_order_dv documents = work orders',
         (SELECT COUNT(*) FROM work_order), (SELECT COUNT(*) FROM agent_work_order_dv)
  UNION ALL SELECT 'T03 agent_checkpoint_dv documents = sections',
         (SELECT COUNT(*) FROM inspection_section), (SELECT COUNT(*) FROM agent_checkpoint_dv)
  UNION ALL SELECT 'T04 card documents: measurement elements = rows',
         (SELECT COUNT(*) FROM measurement_result),
         (SELECT CAST(SUM(JSON_LENGTH(data->'$.measurements')) AS SIGNED) FROM agent_card_dv WHERE JSON_TYPE(data->'$.measurements') = 'ARRAY')
  UNION ALL SELECT 'T05 card documents: checklist elements = rows',
         (SELECT COUNT(*) FROM checklist_result),
         (SELECT CAST(SUM(JSON_LENGTH(data->'$.checklist')) AS SIGNED) FROM agent_card_dv WHERE JSON_TYPE(data->'$.checklist') = 'ARRAY')
  UNION ALL SELECT 'T06 card documents: finding elements = rows',
         (SELECT COUNT(*) FROM quality_finding),
         (SELECT CAST(SUM(JSON_LENGTH(data->'$.findings')) AS SIGNED) FROM agent_card_dv WHERE JSON_TYPE(data->'$.findings') = 'ARRAY')
  UNION ALL SELECT 'T07 work-order documents: unit elements = units',
         (SELECT COUNT(*) FROM production_unit),
         (SELECT CAST(SUM(JSON_LENGTH(data->'$.units')) AS SIGNED) FROM agent_work_order_dv WHERE JSON_TYPE(data->'$.units') = 'ARRAY')
  UNION ALL SELECT 'T08 work-order documents: cards inside units = cards (array in array)',
         (SELECT COUNT(*) FROM inspection_card),
         (SELECT CAST(SUM(JSON_LENGTH(u.cards)) AS SIGNED)
            FROM agent_work_order_dv w, JSON_TABLE(w.data, '$.units[*]' COLUMNS (cards JSON PATH '$.cards')) AS u
           WHERE JSON_TYPE(u.cards) = 'ARRAY')
  UNION ALL SELECT 'T09 checkpoint documents: measurement checkpoints = definitions',
         (SELECT COUNT(*) FROM measurement_definition),
         (SELECT CAST(SUM(JSON_LENGTH(data->'$.measurement_checkpoints')) AS SIGNED) FROM agent_checkpoint_dv WHERE JSON_TYPE(data->'$.measurement_checkpoints') = 'ARRAY')
  UNION ALL SELECT 'T10 checkpoint documents: checklist checkpoints = definitions',
         (SELECT COUNT(*) FROM checklist_definition),
         (SELECT CAST(SUM(JSON_LENGTH(data->'$.checklist_checkpoints')) AS SIGNED) FROM agent_checkpoint_dv WHERE JSON_TYPE(data->'$.checklist_checkpoints') = 'ARRAY')
  UNION ALL SELECT 'T11 card documents expose no person, attachment or key paths',
         0,
         (SELECT COUNT(*) FROM agent_card_dv WHERE JSON_CONTAINS_PATH(data, 'one',
            '$.opened_by', '$.closed_by', '$.attachments', '$.open_unit_key',
            '$.measurements[*].recorded_by', '$.checklist[*].answered_by', '$.findings[*].raised_by'))
  UNION ALL SELECT 'T12 work-order documents expose no person or key paths',
         0,
         (SELECT COUNT(*) FROM agent_work_order_dv WHERE JSON_CONTAINS_PATH(data, 'one',
            '$.units[*].cards[*].opened_by', '$.units[*].cards[*].closed_by', '$.open_unit_key'))
  UNION ALL SELECT 'T13 hostile finding text arrives verbatim as DATA (card 1005)',
         1,
         (SELECT COUNT(*) FROM agent_card_dv WHERE data->>'$._id' = '1005'
             AND data->>'$.findings[0].description' LIKE 'IGNORE ALL PREVIOUS INSTRUCTIONS%')
  UNION ALL SELECT 'T14 the three agent duality views are read-only and valid',
         3,
         (SELECT COUNT(*) FROM INFORMATION_SCHEMA.JSON_DUALITY_VIEWS
           WHERE TABLE_SCHEMA = 'quality_inspection' AND TABLE_NAME LIKE 'agent\_%' AND READ_ONLY = 1 AND STATUS = 'valid')
  UNION ALL SELECT 'S01 cards CLOSED', 5, COALESCE((SELECT cards FROM agent_stat_cards_by_status WHERE card_status = 'CLOSED'), 0)
  UNION ALL SELECT 'S02 cards REJECTED', 1, COALESCE((SELECT cards FROM agent_stat_cards_by_status WHERE card_status = 'REJECTED'), 0)
  UNION ALL SELECT 'S03 cards IN_PROGRESS', 1, COALESCE((SELECT cards FROM agent_stat_cards_by_status WHERE card_status = 'IN_PROGRESS'), 0)
  UNION ALL SELECT 'S04 cards OPEN', 1, COALESCE((SELECT cards FROM agent_stat_cards_by_status WHERE card_status = 'OPEN'), 0)
  UNION ALL SELECT 'S05 final cards PASS', 4, COALESCE((SELECT cards FROM agent_stat_final_cards_by_disposition WHERE disposition = 'PASS'), 0)
  UNION ALL SELECT 'S06 final cards REJECT', 2, COALESCE((SELECT cards FROM agent_stat_final_cards_by_disposition WHERE disposition = 'REJECT'), 0)
  UNION ALL SELECT 'S07 findings CRITICAL RESOLVED', 2, COALESCE((SELECT findings FROM agent_stat_findings WHERE severity = 'CRITICAL' AND finding_status = 'RESOLVED'), 0)
  UNION ALL SELECT 'S08 findings MAJOR OPEN', 1, COALESCE((SELECT findings FROM agent_stat_findings WHERE severity = 'MAJOR' AND finding_status = 'OPEN'), 0)
  UNION ALL SELECT 'S09 findings MINOR OPEN', 1, COALESCE((SELECT findings FROM agent_stat_findings WHERE severity = 'MINOR' AND finding_status = 'OPEN'), 0)
  UNION ALL SELECT 'S10 DIM-LEN recorded', 6, COALESCE((SELECT recorded FROM agent_stat_measurement_tolerance WHERE checkpoint_code = 'DIM-LEN'), 0)
  UNION ALL SELECT 'S11 DIM-LEN out of tolerance', 1, COALESCE((SELECT out_of_tolerance FROM agent_stat_measurement_tolerance WHERE checkpoint_code = 'DIM-LEN'), 0)
  UNION ALL SELECT 'S12 DIM-WID recorded', 4, COALESCE((SELECT recorded FROM agent_stat_measurement_tolerance WHERE checkpoint_code = 'DIM-WID'), 0)
  UNION ALL SELECT 'S13 DIM-WID out of tolerance', 0, COALESCE((SELECT out_of_tolerance FROM agent_stat_measurement_tolerance WHERE checkpoint_code = 'DIM-WID'), 0)
  UNION ALL SELECT 'S14 cycle time: final cards', 6, (SELECT final_cards FROM agent_stat_cycle_time)
  UNION ALL SELECT 'S15 cycle time: average seconds', 4350, (SELECT CAST(ROUND(avg_cycle_seconds) AS SIGNED) FROM agent_stat_cycle_time)
  UNION ALL SELECT 'S16 WO-DEMO-2001 cards total / final / pass / reject / active / open findings / open critical',
         '4/3/2/1/1/1/0',
         (SELECT CONCAT(cards_total, '/', cards_final, '/', cards_pass, '/', cards_reject, '/', cards_active, '/', open_findings, '/', open_critical_findings)
            FROM agent_stat_work_order_progress WHERE work_order_number = 'WO-DEMO-2001')
  UNION ALL SELECT 'S17 WO-DEMO-2002 cards total / final / pass / reject / active / open findings / open critical',
         '2/1/1/0/1/1/0',
         (SELECT CONCAT(cards_total, '/', cards_final, '/', cards_pass, '/', cards_reject, '/', cards_active, '/', open_findings, '/', open_critical_findings)
            FROM agent_stat_work_order_progress WHERE work_order_number = 'WO-DEMO-2002')
) AS checks;

SELECT 'SAMPLE agent_card_dv, card 1002 (a REJECT card with a resolved MAJOR finding)' AS info;
SELECT JSON_PRETTY(data) AS doc FROM agent_card_dv WHERE data->>'$._id' = '1002';

SELECT 'SAMPLE agent_work_order_dv, work order 10 (units with their cards)' AS info;
SELECT JSON_PRETTY(data) AS doc FROM agent_work_order_dv WHERE data->>'$._id' = '10';

SELECT 'SAMPLE agent_checkpoint_dv, all sections' AS info;
SELECT JSON_PRETTY(data) AS doc FROM agent_checkpoint_dv ORDER BY data->>'$._id';
