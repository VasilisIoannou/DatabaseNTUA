#Special Delete for festival / do the same for every  table we revoked delete privilages

DELIMITER //

-- 1. Create a special deletion procedure with additional validation
CREATE PROCEDURE supervisor_delete_festival(
    IN p_festival_id INT,
    IN p_supervisor_id VARCHAR(20),
    IN p_reason VARCHAR(255)
BEGIN
    DECLARE v_is_supervisor BOOLEAN;
    
    -- Verify supervisor status (you'll need a supervisors table)
    SELECT COUNT(*) > 0 INTO v_is_supervisor
    FROM supervisors
    WHERE supervisor_id = p_supervisor_id
    AND is_active = TRUE;
    
    IF NOT v_is_supervisor THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Access denied: Supervisor privileges required';
    ELSEIF p_reason IS NULL OR LENGTH(p_reason) < 10 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A detailed reason (min 10 chars) must be provided';
    ELSEIF NOT EXISTS (SELECT 1 FROM festival WHERE id = p_festival_id) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Festival ID does not exist';
    ELSE
        -- Log the deletion first
        INSERT INTO festival_deletion_log
        (festival_id, deleted_by, deletion_time, reason)
        VALUES (p_festival_id, p_supervisor_id, NOW(), p_reason);
        
        -- Perform the actual deletion (bypasses trigger)
        SET @bypass_trigger = TRUE;
        DELETE FROM festival WHERE id = p_festival_id;
        SET @bypass_trigger = NULL;
    END IF;
END //

-- 2. Modify your existing trigger to check the bypass flag
CREATE TRIGGER prevent_festival_deletion
BEFORE DELETE ON festival
FOR EACH ROW
BEGIN
    IF @bypass_trigger IS NULL OR @bypass_trigger <> TRUE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Direct deletions prohibited. Use supervisor_delete_festival procedure';
    END IF;
END //

DELIMITER ;

#Custom Insert for Ticket and Event

DELIMITER //

CREATE PROCEDURE insert_visitor_with_ticket(
    IN p_visitor_name VARCHAR(255),
    IN p_visitor_surname VARCHAR(255),
    IN p_visitor_age INT,
    IN p_visitor_email VARCHAR(255),
    IN p_visitor_phone VARCHAR(255),
    IN p_EAN_13 BIGINT,
    IN p_ticket_type_name VARCHAR(255), -- I will have a search in the procedure for the id
    IN p_event_id INT,
    -- The Ticket price will be automatic based on the ticket type
    IN p_payment_method_id INT,
    -- Validation is always false when Inserted
)
BEGIN
    DECLARE v_visitor_id INT;
    DECLARE v_ticket_type_id INT;
    DECLARE v_ticket_price FLOAT;
    DECLARE v_price_exist INT;

    -- Start transaction to ensure both inserts succeed or fail together
    START TRANSACTION;

    -- Find the ticket type id
    SELECT ticket_type_id INTO v_ticket_type_id 
    FROM ticket_type 
    WHERE ticket_type_name = v_ticket_type_name;
   
    IF v_ticket_type_id IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Invalid ticket type specified';
    END IF;

    -- Check if price exists for this event and ticket type
    SELECT COUNT(*), ticket_price_price INTO v_price_exists, v_ticket_price
    FROM ticket_price
    WHERE ticket_type_id = v_ticket_type_id AND event_id = p_event_id;
    
    IF v_price_exists = 0 THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'No price defined for this ticket type at the specified event';
    END IF;
    
    -- Insert visitor data
    INSERT INTO visitor (visitor_name, visitor_surname, visitor_age)
    VALUES (p_visitor_name, p_visitor_surname, p_visitor_age);
    
    -- Get the auto-generated visitor_id
    SET v_visitor_id = LAST_INSERT_ID();
    
     -- Insert visitor contact information
    INSERT INTO visitor_contact (visitor_id, visitor_email, visitor_phone)
    VALUES (v_visitor_id, p_visitor_email, p_visitor_phone);
    
    -- Insert ticket data with the visitor_id
    INSERT INTO ticket (EAN_13, ticket_type_id, visitor_id, event_id, ticket_price, payment_method_id, validated)
    VALUES (p_EAN_13, v_ticket_type_id, v_visitor_id, p_event_id, v_ticket_price, p_payment_method_id, FALSE );

    
    -- Commit the transaction if all inserts succeeded
    COMMIT;
    
    -- Return the new visitor_id and EAN_13 for reference
    SELECT v_visitor_id AS new_visitor_id, p_EAN_13 AS ticket_EAN;
END //

DELIMITER ;



