-- =====================================================================
-- D2 / Step 7c: lock final cards (the database enforces "a retest is a new card", D-009 / Q5)
-- Target : MySQL Community 9.7.2, database quality_inspection
-- Run as : root (see D-013), triggers are created with DEFINER = quality_app
-- Rules  : 50020 a CLOSED or REJECTED card row cannot be changed (status, disposition, closed_by,
--                closed_at, unit_id, opened_by, opened_at). A write that changes nothing is allowed.
--          50021 a measurement result of a CLOSED or REJECTED card cannot be updated
--          50022 a checklist result of a CLOSED or REJECTED card cannot be updated
-- Not locked on purpose: findings and attachment metadata (a photo or a resolved finding may be added
--          after a card is final), and direct INSERT or DELETE of result rows (the edit view cannot do either).
-- Added as NEW triggers; the verified D1 triggers are not modified.
-- Undo   : 98_rollback_final_card_lock.sql
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

DELIMITER $$

CREATE DEFINER=`quality_app`@`%` TRIGGER trg_inspection_card_bu_lock
BEFORE UPDATE ON inspection_card
FOR EACH ROW
FOLLOWS trg_inspection_card_bu
BEGIN
    IF OLD.card_status IN ('CLOSED','REJECTED')
       AND NOT (    NEW.unit_id     <=> OLD.unit_id
                AND NEW.card_status <=> OLD.card_status
                AND NEW.disposition <=> OLD.disposition
                AND NEW.opened_by   <=> OLD.opened_by
                AND NEW.opened_at   <=> OLD.opened_at
                AND NEW.closed_by   <=> OLD.closed_by
                AND NEW.closed_at   <=> OLD.closed_at) THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50020,
                MESSAGE_TEXT = 'A closed or rejected card cannot be changed';
    END IF;
END$$

CREATE DEFINER=`quality_app`@`%` TRIGGER trg_measurement_result_bu_lock
BEFORE UPDATE ON measurement_result
FOR EACH ROW
BEGIN
    IF (SELECT card_status FROM inspection_card WHERE card_id = OLD.card_id) IN ('CLOSED','REJECTED') THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50021,
                MESSAGE_TEXT = 'Measurement results of a closed or rejected card cannot be changed';
    END IF;
END$$

CREATE DEFINER=`quality_app`@`%` TRIGGER trg_checklist_result_bu_lock
BEFORE UPDATE ON checklist_result
FOR EACH ROW
BEGIN
    IF (SELECT card_status FROM inspection_card WHERE card_id = OLD.card_id) IN ('CLOSED','REJECTED') THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50022,
                MESSAGE_TEXT = 'Checklist results of a closed or rejected card cannot be changed';
    END IF;
END$$

DELIMITER ;

SELECT TRIGGER_NAME, ACTION_TIMING, EVENT_MANIPULATION, EVENT_OBJECT_TABLE, ACTION_ORDER, DEFINER
FROM INFORMATION_SCHEMA.TRIGGERS
WHERE TRIGGER_SCHEMA = 'quality_inspection'
ORDER BY EVENT_OBJECT_TABLE, ACTION_TIMING, EVENT_MANIPULATION, ACTION_ORDER;
-- Expected: 8 triggers in total (the 5 from D1 plus these 3). On inspection_card BEFORE UPDATE:
--           trg_inspection_card_bu with ACTION_ORDER 1, then trg_inspection_card_bu_lock with ACTION_ORDER 2.
