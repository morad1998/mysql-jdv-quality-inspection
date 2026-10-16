-- =====================================================================
-- D1 / Step 12B: business rules as triggers
-- Target : MySQL Community 9.7.2, database quality_inspection
-- Run as : root (see note), triggers are created with DEFINER = quality_app
-- Basis  : D1 Design Pack v2 (N2, Q8, Q9)
-- Note   : With binary logging on, CREATE TRIGGER can fail for a normal account
--          with error 1419. Running as root avoids that. DEFINER quality_app means
--          the triggers execute with the application account's rights, not root's.
-- Error codes used (user-defined, identify each expected failure):
--   50001 card must start OPEN              50002 unanswered checklist blocks close
--   50003 open CRITICAL finding blocks close
--   50010 audit_event update blocked        50011 audit_event delete blocked
-- Plain ASCII only.
-- =====================================================================
USE quality_inspection;

DELIMITER $$

-- A new card must start OPEN (lifecycle rule behind N2) --------------------
CREATE DEFINER=`quality_app`@`%` TRIGGER trg_inspection_card_bi
BEFORE INSERT ON inspection_card
FOR EACH ROW
BEGIN
    IF NEW.card_status <> 'OPEN' THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50001,
                MESSAGE_TEXT = 'A new inspection card must start in status OPEN';
    END IF;
END$$

-- N2: create one PENDING result row for every definition when a card opens --
CREATE DEFINER=`quality_app`@`%` TRIGGER trg_inspection_card_ai
AFTER INSERT ON inspection_card
FOR EACH ROW
BEGIN
    INSERT INTO measurement_result (card_id, measurement_definition_id, result_status)
        SELECT NEW.card_id, md.measurement_definition_id, 'PENDING'
        FROM measurement_definition md;

    INSERT INTO checklist_result (card_id, checklist_definition_id, answer_code)
        SELECT NEW.card_id, cd.checklist_definition_id, 'PENDING'
        FROM checklist_definition cd;
END$$

-- Q8: close rules, checked when a card moves to CLOSED -----------------------
CREATE DEFINER=`quality_app`@`%` TRIGGER trg_inspection_card_bu
BEFORE UPDATE ON inspection_card
FOR EACH ROW
BEGIN
    IF NEW.card_status = 'CLOSED' AND OLD.card_status <> 'CLOSED' THEN
        IF EXISTS (SELECT 1 FROM checklist_result
                   WHERE card_id = OLD.card_id AND answer_code = 'PENDING') THEN
            SIGNAL SQLSTATE '45000'
                SET MYSQL_ERRNO = 50002,
                    MESSAGE_TEXT = 'Cannot close card: unanswered checklist items exist';
        END IF;
        IF EXISTS (SELECT 1 FROM quality_finding
                   WHERE card_id = OLD.card_id
                     AND severity = 'CRITICAL' AND finding_status = 'OPEN') THEN
            SIGNAL SQLSTATE '45000'
                SET MYSQL_ERRNO = 50003,
                    MESSAGE_TEXT = 'Cannot close card: an open CRITICAL finding exists';
        END IF;
    END IF;
END$$

-- Q9: audit_event is append-only ---------------------------------------------
CREATE DEFINER=`quality_app`@`%` TRIGGER trg_audit_event_bu
BEFORE UPDATE ON audit_event
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MYSQL_ERRNO = 50010, MESSAGE_TEXT = 'audit_event is append-only: update blocked';
END$$

CREATE DEFINER=`quality_app`@`%` TRIGGER trg_audit_event_bd
BEFORE DELETE ON audit_event
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MYSQL_ERRNO = 50011, MESSAGE_TEXT = 'audit_event is append-only: delete blocked';
END$$

DELIMITER ;
